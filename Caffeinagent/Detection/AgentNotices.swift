import Foundation

/// Which agent notifications the user wants.
struct AgentNoticeSettings: Equatable {
    /// "An agent is waiting for your answer".
    var waiting = true
    /// "An agent finished".
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
        /// Since when it waits. Waiting only.
        var waitingSince: Date?

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
    /// False while agent caffeine is off, paused or without a license.
    var active = true
}

/// Says when an agent notification is due. Pure: the caller passes the
/// readings of each sample and the time.
///
/// Waiting: a session goes from working, or from nothing, to waiting for
/// the user and stays so for `waitingDebounce`. Finished: a session that
/// worked for `shortestWork` or longer goes idle or is gone. What was
/// there at the first sample is never told, and nothing is told while
/// agent caffeine is off or paused. Three or more sessions that change
/// within `coalesceWindow` give one notification.
struct AgentNoticeReducer {
    /// A wait that is over sooner was a flicker.
    static let waitingDebounce: TimeInterval = 3
    /// Shorter work is a one-line answer, and no news.
    static let shortestWork: TimeInterval = 30
    static let coalesceWindow: TimeInterval = 2
    static let coalesceCount = 3

    private struct Session {
        var state: WorkState
        var agentID: String
        var displayName: String
        var label: String?
        var ownerPid: Int32?
        /// When the work began that goes on now, also over a wait for
        /// the user. Nil while idle.
        var workStart: Date?
    }

    private struct Candidate {
        var kind: AgentNoticeKind
        var session: AgentNotice.Session
        var at: Date
    }

    private var sessions: [ProcessIdentity: Session] = [:]
    private var candidates: [Candidate] = []
    private var primed = false

    init() {}

    mutating func update(_ input: AgentNoticeInput, now: Date) -> [AgentNotice] {
        let wasPrimed = primed
        primed = true
        let tells = wasPrimed && input.active
        func watched(_ ownerPid: Int32?) -> Bool {
            guard input.settings.onlyWhenAway, input.userActive, let ownerPid else { return false }
            return ownerPid == input.frontmostPid
        }

        var next: [ProcessIdentity: Session] = [:]
        for reading in input.readings where !Self.byRule(reading) {
            let identity = reading.identity
            let old = sessions[identity]
            var session = Session(
                state: reading.verdict.state, agentID: reading.agentID, displayName: reading.displayName,
                label: input.labels[identity] ?? old?.label, ownerPid: input.owners[identity] ?? old?.ownerPid, workStart: old?.workStart
            )
            switch reading.verdict.state {
            case .working:
                // Back at work before it was told: it did not finish, and
                // the work goes on from where it began.
                let pending = candidates.first { $0.session.identity == identity && $0.kind == .finished }
                let began = pending.flatMap { candidate in candidate.session.workedFor.map { candidate.at.addingTimeInterval(-$0) } }
                session.workStart = session.workStart ?? began ?? now
                candidates.removeAll { $0.session.identity == identity }
            case .waitingForUser:
                let began = old == nil || old?.state == .working
                if began, tells, input.settings.waiting, !watched(session.ownerPid) {
                    candidates.removeAll { $0.session.identity == identity }
                    candidates.append(Candidate(kind: .waiting, session: snapshot(identity, session, waitingSince: now), at: now))
                }
            case .idle:
                if let old, old.state == .working, tells, input.settings.finished, !watched(session.ownerPid) {
                    addFinished(identity, old, now: now)
                }
                session.workStart = nil
                candidates.removeAll { $0.session.identity == identity && $0.kind == .waiting }
            }
            next[identity] = session
        }
        for (identity, old) in sessions where next[identity] == nil {
            candidates.removeAll { $0.session.identity == identity && $0.kind == .waiting }
            if old.state == .working, tells, input.settings.finished, !watched(old.ownerPid) {
                addFinished(identity, old, now: now)
            }
        }
        sessions = next

        if !input.active { candidates = [] }
        // A clock that was set back leaves times in the future.
        candidates.removeAll { $0.at > now || watched($0.session.ownerPid) }
        candidates.removeAll { !input.settings.waiting && $0.kind == .waiting || !input.settings.finished && $0.kind == .finished }
        return due(now: now)
    }

    /// A rule of the user decides these, not what the agent does.
    private static func byRule(_ reading: AgentReading) -> Bool {
        reading.verdict.reason == .ignoredByRule || reading.verdict.reason == .alwaysWorkingByRule
    }

    private func snapshot(_ identity: ProcessIdentity, _ session: Session, workedFor: TimeInterval? = nil, waitingSince: Date? = nil) -> AgentNotice.Session {
        AgentNotice.Session(
            identity: identity, agentID: session.agentID, displayName: session.displayName, label: session.label,
            ownerPid: session.ownerPid, workedFor: workedFor, waitingSince: waitingSince
        )
    }

    private mutating func addFinished(_ identity: ProcessIdentity, _ old: Session, now: Date) {
        guard let start = old.workStart, now.timeIntervalSince(start) >= Self.shortestWork else { return }
        candidates.removeAll { $0.session.identity == identity }
        candidates.append(Candidate(kind: .finished, session: snapshot(identity, old, workedFor: now.timeIntervalSince(start)), at: now))
    }

    /// The oldest of a kind is told when its time has come, together with
    /// the ones that came up to `coalesceWindow` after it.
    private mutating func due(now: Date) -> [AgentNotice] {
        var notices: [AgentNotice] = []
        for kind in [AgentNoticeKind.waiting, .finished] {
            let delay = kind == .waiting ? Self.waitingDebounce : Self.coalesceWindow
            let mine = candidates.filter { $0.kind == kind }.sorted { $0.at < $1.at }
            guard let first = mine.first, now.timeIntervalSince(first.at) >= delay else { continue }
            let group = mine.filter { $0.at.timeIntervalSince(first.at) <= Self.coalesceWindow }
            let told = Set(group.map(\.session.identity))
            candidates.removeAll { $0.kind == kind && told.contains($0.session.identity) }
            // A name that was read after the change still counts.
            let sessions = group.map { candidate -> AgentNotice.Session in
                var session = candidate.session
                session.label = self.sessions[session.identity]?.label ?? session.label
                return session
            }
            if sessions.count >= Self.coalesceCount {
                notices.append(AgentNotice(kind: kind, sessions: sessions))
            } else {
                notices += sessions.map { AgentNotice(kind: kind, sessions: [$0]) }
            }
        }
        return notices
    }
}

/// What a notification shows.
struct AgentNoticeContent: Equatable {
    /// A new notification with the same id takes the place of the old one.
    var id: String
    /// macOS groups the notifications of one agent.
    var thread: String
    var title: String
    var subtitle: String?
    var body: String?
    var sound: Bool
    var ownerPid: Int32?
}

/// The words of the agent notifications.
enum AgentNoticeText {
    /// - Parameter waitingHold: how long the Mac stays awake for an agent
    ///   that waits. Nil when that does not decide when the Mac sleeps.
    static func content(_ notice: AgentNotice, waitingHold: TimeInterval?, now: Date) -> AgentNoticeContent {
        let sessions = notice.sessions
        let owners = Set(sessions.map(\.ownerPid))
        let ownerPid = owners.count == 1 ? owners.first ?? nil : nil
        // The Mac stays awake until the last one's hold runs out.
        let since = sessions.compactMap(\.waitingSince).max()
        let sleeps = notice.kind == .waiting ? canSleep(waitingHold: waitingHold, since: since, now: now) : nil
        guard sessions.count == 1, let session = sessions.first else {
            return AgentNoticeContent(
                id: notice.kind == .waiting ? "agents-waiting" : "agents-finished", thread: "agents",
                title: notice.kind == .waiting ? "\(sessions.count) agents are waiting for you" : "\(sessions.count) agents finished",
                subtitle: nil, body: sleeps, sound: notice.kind == .waiting, ownerPid: ownerPid
            )
        }
        let id = "\(session.identity.pid)-\(Int(session.identity.startTime))"
        switch notice.kind {
        case .waiting:
            return AgentNoticeContent(
                id: "waiting-\(id)", thread: "agent-\(session.agentID)", title: "\(session.displayName) is waiting for you",
                subtitle: session.label, body: sleeps, sound: true, ownerPid: ownerPid
            )
        case .finished:
            return AgentNoticeContent(
                id: "finished-\(id)", thread: "agent-\(session.agentID)", title: "\(session.displayName) finished",
                subtitle: session.label, body: session.workedFor.flatMap(HumaneDuration.length(seconds:)).map { "After \($0)" },
                sound: false, ownerPid: ownerPid
            )
        }
    }

    /// "Your Mac can sleep in 5 minutes", with the minutes rounded up as
    /// in the menu. Nil when the hold is over.
    static func canSleep(waitingHold: TimeInterval?, since: Date?, now: Date) -> String? {
        guard let waitingHold else { return nil }
        let left = waitingHold - (since.map { now.timeIntervalSince($0) } ?? 0)
        guard left > 0 else { return nil }
        let minutes = Int((left / 60).rounded(.up))
        return "Your Mac can sleep in \(HumaneDuration.length(seconds: TimeInterval(minutes) * 60) ?? "a moment")"
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
