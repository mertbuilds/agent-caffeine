import Foundation

/// Which agent notifications the user wants.
struct AgentNoticeSettings: Equatable {
    /// "An agent waits for you".
    var waiting = true
    /// "An agent finishes".
    var finished = false
    /// No notification while the user works in the app the agent runs in.
    var onlyWhenAway = true

    var wantsAny: Bool { waiting || finished }

    private static let waitingKey = "AgentNotices.waiting"
    private static let finishedKey = "AgentNotices.finished"
    private static let onlyWhenAwayKey = "AgentNotices.onlyWhenAway"

    static func load(from defaults: UserDefaults) -> AgentNoticeSettings {
        var settings = AgentNoticeSettings()
        settings.waiting = defaults.object(forKey: waitingKey) as? Bool ?? settings.waiting
        settings.finished = defaults.object(forKey: finishedKey) as? Bool ?? settings.finished
        settings.onlyWhenAway = defaults.object(forKey: onlyWhenAwayKey) as? Bool ?? settings.onlyWhenAway
        return settings
    }

    func save(to defaults: UserDefaults) {
        defaults.set(waiting, forKey: Self.waitingKey)
        defaults.set(finished, forKey: Self.finishedKey)
        defaults.set(onlyWhenAway, forKey: Self.onlyWhenAwayKey)
    }
}

enum AgentNoticeKind: Equatable {
    case waiting
    case finished
}

/// One notification that is due: about one session, or about three or
/// more that changed together.
struct AgentNotice: Equatable {
    /// The label can come from what the user typed. It is shown in the
    /// notification on this Mac and goes nowhere else, so this prints as
    /// nothing, like `SessionHint`.
    struct Session: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        var identity: ProcessIdentity
        var agentID: String
        var displayName: String
        var label: String?
        /// The app the session runs in, for a click on the notification.
        var ownerPid: Int32?
        /// How long it worked. Finished only.
        var workedFor: TimeInterval?
        /// The agent says that the turn ended with an error. Finished only.
        var failed = false

        var description: String { "AgentNotice.Session" }
        var debugDescription: String { description }
    }

    var kind: AgentNoticeKind
    /// One, or `AgentNoticeReducer.coalesceCount` and more.
    var sessions: [Session]
}

/// What the reducer sees at one sample.
struct AgentNoticeInput {
    var readings: [AgentReading]
    /// The name of each session, else its folder.
    var labels: [ProcessIdentity: String] = [:]
    /// The app each session runs in, where that is known.
    var owners: [ProcessIdentity: Int32] = [:]
    var frontmostPid: Int32?
    /// The user touched the keyboard or the pointer a moment ago.
    var userActive = false
    var settings = AgentNoticeSettings()
    /// False while Agent Caffeine is off or paused.
    var active = true
}

/// What the reducer made of one change of one session: told, or why not.
/// It holds no name, so it can go to the log.
struct AgentNoticeDecision: Equatable {
    enum Outcome: Equatable {
        case told
        /// It waited already when the app started or the switch went on.
        case atLaunch
        /// Agent Caffeine is off or paused.
        case notActive
        /// "Only when not in front" is on and the user works in its app.
        case inFront
        /// Finished only: at work again before the notification was due.
        case backAtWork(after: TimeInterval)
        /// Waiting only: the wait ended before the notification was due.
        case waitEnded(after: TimeInterval)
        /// Finished only: the end became a question, and that was told.
        case asksInstead
    }

    var kind: AgentNoticeKind
    var pid: Int32
    var outcome: Outcome
    /// Finished only.
    var workedFor: TimeInterval?

    /// One line for the log: states, times and the pid.
    var logLine: String {
        let name = kind == .waiting ? "waiting" : "finished"
        switch outcome {
        case .told:
            let after = workedFor.map { " after \(Int($0.rounded())) s" } ?? ""
            return "\(name) fired pid \(pid)\(after)"
        case .atLaunch: return "\(name) skipped pid \(pid): it waited already at launch"
        case .notActive: return "\(name) skipped pid \(pid): Agent Caffeine is off or paused"
        case .inFront: return "\(name) skipped pid \(pid): front app is its app"
        case .backAtWork(let after): return "\(name) skipped pid \(pid): working again after \(String(format: "%.1f", after)) s"
        case .waitEnded(let after): return "\(name) skipped pid \(pid): the wait ended after \(String(format: "%.1f", after)) s"
        case .asksInstead: return "\(name) skipped pid \(pid): it asks a question, and that was told"
        }
    }
}

/// Says when an agent notification is due. Pure: the caller passes the
/// readings of each sample and the time.
///
/// The state of a session is its turn where the agent reports one, else
/// its verdict: a command that runs on after the answer is no work here.
/// Waiting: a session starts to wait for the user and stays so for
/// `waitingDebounce`. Finished: a session that worked goes idle or is gone
/// and is not at work again within `finishedDebounce`. Work that ends in
/// a wait which was never told, and then in idle, finished too. What was there at
/// the first sample is never told, and nothing is told while agent
/// caffeine is off or paused. Three or more sessions that change within
/// `coalesceWindow` give one notification.
struct AgentNoticeReducer {
    /// A wait that is over sooner was a flicker.
    static let waitingDebounce: TimeInterval = 3
    /// An end that is followed by work sooner was no end.
    static let finishedDebounce: TimeInterval = 2
    static let coalesceWindow: TimeInterval = 2
    static let coalesceCount = 3

    private struct Session {
        var state: WorkState
        var agentID: String
        var displayName: String
        var label: String?
        var ownerPid: Int32?
        /// When the work began that goes on now, also over a wait for
        /// the user and over an end that is not told yet. Nil while idle.
        var workStart: Date?
        /// The wait that goes on now was told.
        var waitTold = false
        /// The turn that ended last ended with an error.
        var failed = false
    }

    private struct Candidate {
        var kind: AgentNoticeKind
        var session: AgentNotice.Session
        var at: Date
    }

    /// What the last update decided, for the log.
    private(set) var decisions: [AgentNoticeDecision] = []
    private var sessions: [ProcessIdentity: Session] = [:]
    private var candidates: [Candidate] = []
    private var primed = false
    private var lastUpdate: Date?

    init() {}

    mutating func update(_ input: AgentNoticeInput, now: Date) -> [AgentNotice] {
        decisions = []
        let wasPrimed = primed
        primed = true
        func watched(_ ownerPid: Int32?) -> Bool {
            guard input.settings.onlyWhenAway, input.userActive, let ownerPid else { return false }
            return ownerPid == input.frontmostPid
        }
        /// A change that may become a notification.
        func offer(_ kind: AgentNoticeKind, _ session: AgentNotice.Session) {
            guard kind == .waiting ? input.settings.waiting : input.settings.finished else { return }
            let outcome: AgentNoticeDecision.Outcome? = !wasPrimed ? .atLaunch : !input.active ? .notActive : watched(session.ownerPid) ? .inFront : nil
            if let outcome {
                decisions.append(AgentNoticeDecision(kind: kind, pid: session.identity.pid, outcome: outcome, workedFor: session.workedFor))
                return
            }
            candidates.removeAll { $0.session.identity == session.identity && $0.kind == kind }
            candidates.append(Candidate(kind: kind, session: session, at: now))
        }

        var next: [ProcessIdentity: Session] = [:]
        for reading in input.readings where !Self.byRule(reading) {
            let identity = reading.identity
            let old = sessions[identity]
            let state = reading.turn?.state ?? reading.verdict.state
            var session = Session(
                state: state, agentID: reading.agentID, displayName: reading.displayName,
                label: input.labels[identity] ?? old?.label, ownerPid: input.owners[identity] ?? old?.ownerPid, workStart: old?.workStart,
                failed: reading.turn?.failed ?? false
            )
            switch state {
            case .working:
                if session.workStart == nil {
                    // The agent's own time, so work that began before the
                    // app saw it counts in full. Not from before the last
                    // sample that saw the session idle.
                    let said = reading.turn?.since.flatMap { $0 <= now ? $0 : nil }
                    let idleAt = old == nil ? nil : lastUpdate
                    session.workStart = said.map { max($0, idleAt ?? $0) } ?? now
                }
                // Back at work before it was told: it did not finish.
                withdraw(identity, now: now)
            case .waitingForUser:
                // An end that is on its way stays: see `due`.
                if old?.state != .waitingForUser { offer(.waiting, snapshot(identity, session)) }
                session.waitTold = old?.state == .waitingForUser && old?.waitTold == true
            case .idle:
                withdraw(identity, kind: .waiting, now: now)
                // A wait that was told brought the user, and its end is
                // no news. One that was not told, as a wait shorter than
                // the debounce, would swallow the end of the work.
                let untoldWait = old?.state == .waitingForUser && old?.waitTold == false && old?.workStart != nil
                    && !candidates.contains { $0.session.identity == identity && $0.kind == .finished }
                if let old, old.state == .working || untoldWait {
                    offer(.finished, snapshot(identity, old, workedFor: old.workStart.map { now.timeIntervalSince($0) }))
                }
                if !candidates.contains(where: { $0.session.identity == identity && $0.kind == .finished }) { session.workStart = nil }
            }
            next[identity] = session
        }
        for (identity, old) in sessions where next[identity] == nil {
            withdraw(identity, kind: .waiting, now: now)
            if old.state == .working {
                offer(.finished, snapshot(identity, old, workedFor: old.workStart.map { now.timeIntervalSince($0) }))
            }
        }
        sessions = next
        lastUpdate = now

        // A clock that was set back leaves times in the future.
        candidates.removeAll { $0.at > now }
        candidates.removeAll { !input.settings.waiting && $0.kind == .waiting || !input.settings.finished && $0.kind == .finished }
        drop(as: .notActive) { _ in !input.active }
        drop(as: .inFront) { watched($0.session.ownerPid) }
        return due(now: now)
    }

    /// A rule of the user decides these, not what the agent does.
    private static func byRule(_ reading: AgentReading) -> Bool {
        reading.verdict.reason == .ignoredByRule || reading.verdict.reason == .alwaysWorkingByRule
    }

    private func snapshot(_ identity: ProcessIdentity, _ session: Session, workedFor: TimeInterval? = nil) -> AgentNotice.Session {
        AgentNotice.Session(
            identity: identity, agentID: session.agentID, displayName: session.displayName, label: session.label,
            ownerPid: session.ownerPid, workedFor: workedFor
        )
    }

    /// The change that was on its way did not last.
    private mutating func withdraw(_ identity: ProcessIdentity, kind: AgentNoticeKind? = nil, now: Date) {
        for candidate in candidates where candidate.session.identity == identity && (kind == nil || candidate.kind == kind) {
            let after = now.timeIntervalSince(candidate.at)
            decisions.append(AgentNoticeDecision(
                kind: candidate.kind, pid: identity.pid,
                outcome: candidate.kind == .finished ? .backAtWork(after: after) : .waitEnded(after: after), workedFor: candidate.session.workedFor
            ))
        }
        candidates.removeAll { $0.session.identity == identity && (kind == nil || $0.kind == kind) }
    }

    private mutating func drop(as outcome: AgentNoticeDecision.Outcome, where gone: (Candidate) -> Bool) {
        for candidate in candidates where gone(candidate) {
            decisions.append(AgentNoticeDecision(
                kind: candidate.kind, pid: candidate.session.identity.pid, outcome: outcome, workedFor: candidate.session.workedFor
            ))
        }
        candidates.removeAll(where: gone)
    }

    /// The oldest of a kind and the ones that came up to `coalesceWindow`
    /// after it are told together, when the time of the last of them has
    /// come. The group is fixed by its oldest, so a row of changes cannot
    /// push a notification back for ever, and each group is told.
    ///
    /// An end that turns into a question within the debounce is held
    /// while the question is on its way. A question that is told takes
    /// its place, and one that does not last leaves the end to be told.
    private mutating func due(now: Date) -> [AgentNotice] {
        var notices: [AgentNotice] = []
        for kind in [AgentNoticeKind.waiting, .finished] {
            let delay = kind == .waiting ? Self.waitingDebounce : Self.finishedDebounce
            let asking = Set(candidates.filter { $0.kind == .waiting }.map(\.session.identity))
            while true {
                let mine = candidates.filter { $0.kind == kind && (kind == .waiting || !asking.contains($0.session.identity)) }.sorted { $0.at < $1.at }
                guard let first = mine.first else { break }
                let group = mine.filter { $0.at.timeIntervalSince(first.at) <= Self.coalesceWindow }
                guard let last = group.last, now.timeIntervalSince(last.at) >= delay else { break }
                let told = Set(group.map(\.session.identity))
                candidates.removeAll { $0.kind == kind && told.contains($0.session.identity) }
                // The work that was told is over.
                if kind == .finished { told.forEach { self.sessions[$0]?.workStart = nil } }
                if kind == .waiting { told.forEach { self.sessions[$0]?.waitTold = true } }
                if kind == .waiting { drop(as: .asksInstead) { $0.kind == .finished && told.contains($0.session.identity) } }
                // A name that was read after the change still counts, and
                // so does an error: the hook can say the end before the log.
                let sessions = group.map { candidate -> AgentNotice.Session in
                    var session = candidate.session
                    session.label = self.sessions[session.identity]?.label ?? session.label
                    session.failed = kind == .finished && self.sessions[session.identity]?.failed == true
                    return session
                }
                decisions += sessions.map { AgentNoticeDecision(kind: kind, pid: $0.identity.pid, outcome: .told, workedFor: $0.workedFor) }
                if sessions.count >= Self.coalesceCount {
                    notices.append(AgentNotice(kind: kind, sessions: sessions))
                } else {
                    notices += sessions.map { AgentNotice(kind: kind, sessions: [$0]) }
                }
            }
        }
        return notices
    }
}

/// What became of one agent notification.
enum AgentNoticeDelivery: Equatable {
    case delivered
    /// macOS took it and shows no banner: the style is "None" in System Settings.
    case noBanner
    /// Notifications are off for Agent Caffeine.
    case notAllowed
    /// macOS did not take it.
    case failed
}

/// The last agent notifications and what became of them, for Preferences.
/// It holds the words of the title and no session name.
struct AgentNoticeHistory: Equatable {
    static let length = 5

    enum Result: Equatable {
        /// Handed to macOS, no answer yet.
        case sending
        case sent(AgentNoticeDelivery)
        case inFront
        case notActive

        var text: String {
            switch self {
            case .sending: return "Sending"
            case .sent(.delivered): return "Delivered"
            case .sent(.noBanner): return "Delivered, no banner"
            case .sent(.notAllowed): return "Not shown: notifications are off"
            case .sent(.failed): return "Not shown: macOS refused it"
            case .inFront: return "Not sent: you were in the agent's app"
            case .notActive: return "Not sent: Agent Caffeine was off or paused"
            }
        }
    }

    struct Entry: Equatable, Identifiable {
        var id: String
        var at: Date
        var title: String
        var result: Result
    }

    /// Newest first.
    private(set) var entries: [Entry] = []
    private var count = 0

    mutating func posted(_ content: AgentNoticeContent, at: Date) {
        add(Entry(id: content.id, at: at, title: content.title, result: .sending))
    }

    /// Only what the user would ask about: a notification that was held
    /// back. A flicker that was no change is in the log.
    mutating func note(_ decision: AgentNoticeDecision, at: Date) {
        let result: Result
        switch decision.outcome {
        case .inFront: result = .inFront
        case .notActive: result = .notActive
        case .told, .atLaunch, .backAtWork, .waitEnded, .asksInstead: return
        }
        count += 1
        let title = decision.kind == .waiting ? "An agent started to wait for you" : "An agent finished"
        add(Entry(id: "skipped-\(count)", at: at, title: title, result: result))
    }

    mutating func delivered(_ id: String, _ delivery: AgentNoticeDelivery) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].result = .sent(delivery)
    }

    private mutating func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.length { entries.removeLast(entries.count - Self.length) }
    }
}

/// What a notification shows.
struct AgentNoticeContent: Equatable {
    /// The request identifier. Never the same twice: macOS puts a request
    /// with a known identifier in the place of the old one and shows no
    /// new banner.
    var id: String
    /// What the notification is about: a kind and a session. The older
    /// notification with the same key is taken away.
    var key: String
    /// macOS groups the notifications of one agent.
    var thread: String
    var title: String
    var subtitle: String?
    var body: String?
    var sound: Bool
    var ownerPid: Int32?
    /// The one session it is about, for a click. Nil for several.
    var agent: ProcessIdentity?
}

/// Where a click on a notification goes: to the app of one agent.
struct AgentNoticeTarget: Equatable {
    var agent: ProcessIdentity
    /// The app the agent ran in when the notification was made, for an
    /// agent that is gone at the click.
    var ownerPid: Int32?

    private static let pidKey = "agentPid"
    private static let startKey = "agentStart"
    private static let ownerKey = "ownerPid"

    /// For the `userInfo` of a notification: property list values only.
    var userInfo: [String: Any] {
        var info: [String: Any] = [Self.pidKey: Int(agent.pid), Self.startKey: agent.startTime]
        if let ownerPid { info[Self.ownerKey] = Int(ownerPid) }
        return info
    }

    /// Nil for a notification about several agents, and for any other one.
    init?(userInfo: [AnyHashable: Any]) {
        guard let pid = userInfo[Self.pidKey] as? Int, let start = userInfo[Self.startKey] as? Double,
              let pid = Int32(exactly: pid) else { return nil }
        agent = ProcessIdentity(pid: pid, startTime: start)
        ownerPid = (userInfo[Self.ownerKey] as? Int).flatMap(Int32.init(exactly:))
    }

    init(agent: ProcessIdentity, ownerPid: Int32? = nil) {
        self.agent = agent
        self.ownerPid = ownerPid
    }

    /// Whether the process that has `ownerPid` now is still the app the
    /// agent ran in. A notification stays in Notification Center for days,
    /// also over a restart of the Mac, and a pid is used again. The app is
    /// above the agent in the process tree, or is the agent, so it started
    /// no later than the agent. A process that started after the agent is
    /// another one, and a click must not bring that to the front.
    /// - Parameter startTime: of the process with `ownerPid` now. Nil when
    ///   there is none.
    func ownerIsStill(startTime: TimeInterval?) -> Bool {
        guard ownerPid != nil, let startTime else { return false }
        return startTime <= agent.startTime + Self.startTolerance
    }

    /// Two readings of one start time can differ in the last digit.
    private static let startTolerance: TimeInterval = 0.001
}

/// The words of the agent notifications.
enum AgentNoticeText {
    /// - Parameter outlook: what happens when the hold for the agents that
    ///   wait ends, for the whole Mac at this moment.
    static func content(_ notice: AgentNotice, outlook: SleepOutlook, now: Date) -> AgentNoticeContent {
        let sessions = notice.sessions
        let owners = Set(sessions.map(\.ownerPid))
        let ownerPid = owners.count == 1 ? owners.first ?? nil : nil
        let sleeps = notice.kind == .waiting ? PanelText.sleepOutlook(outlook) : nil
        let stamp = Int64((now.timeIntervalSince1970 * 1000).rounded())
        guard sessions.count == 1, let session = sessions.first else {
            let key = notice.kind == .waiting ? "agents-waiting" : "agents-finished"
            return AgentNoticeContent(
                id: "\(key)-\(stamp)", key: key, thread: "agents",
                title: notice.kind == .waiting ? "\(sessions.count) agents are waiting for you" : "\(sessions.count) agents finished",
                subtitle: nil, body: sleeps, sound: true, ownerPid: ownerPid
            )
        }
        let id = "\(session.identity.pid)-\(Int(session.identity.startTime))"
        switch notice.kind {
        case .waiting:
            return AgentNoticeContent(
                id: "waiting-\(id)-\(stamp)", key: "waiting-\(id)", thread: "agent-\(session.agentID)", title: "\(session.displayName) is waiting for you",
                subtitle: session.label, body: sleeps, sound: true, ownerPid: ownerPid, agent: session.identity
            )
        case .finished:
            return AgentNoticeContent(
                id: "finished-\(id)-\(stamp)", key: "finished-\(id)", thread: "agent-\(session.agentID)",
                title: session.failed ? PanelText.stoppedWithError(session.displayName) : "\(session.displayName) finished",
                subtitle: session.label, body: session.workedFor.flatMap(HumaneDuration.length(seconds:)).map { "After \($0)" },
                sound: true, ownerPid: ownerPid, agent: session.identity
            )
        }
    }
}

/// Finds the app a session runs in: the terminal, the editor, or the
/// agent's own app.
enum AgentOwner {
    /// The user counts as active for this long after the last key or
    /// move of the pointer.
    static let activeWithin: TimeInterval = 10
    static let deepest = 32

    /// Walks up from the agent to the first process that is an app with
    /// windows. Nil when there is none, as under tmux or over SSH.
    static func find(from pid: Int32, parent: (Int32) -> Int32?, isApp: (Int32) -> Bool) -> Int32? {
        var current = pid
        for _ in 0..<deepest {
            if isApp(current) { return current }
            guard let next = parent(current), next > 1, next != current else { return nil }
            current = next
        }
        return nil
    }
}
