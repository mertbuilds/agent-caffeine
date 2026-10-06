import XCTest

final class AgentNoticesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private var reducer = AgentNoticeReducer()
    private var settings = AgentNoticeSettings(waiting: true, finished: true, onlyWhenAway: true)

    private func identity(_ pid: Int32) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startTime: 5)
    }

    private func reading(_ pid: Int32, _ state: WorkState, _ reason: VerdictReason = .reportsBusy, id: String = "claude", name: String = "Claude Code") -> AgentReading {
        AgentReading(
            agentID: id, displayName: name, level: .state, identity: identity(pid),
            verdict: AgentVerdict(state: state, confidence: .reported, reason: reason)
        )
    }

    /// One sample at `seconds` after the start.
    private func sample(
        _ seconds: TimeInterval, _ readings: [AgentReading], labels: [Int32: String] = [:], owners: [Int32: Int32] = [:],
        frontmost: Int32? = nil, userActive: Bool = false, active: Bool = true
    ) -> [AgentNotice] {
        let input = AgentNoticeInput(
            readings: readings,
            labels: Dictionary(uniqueKeysWithValues: labels.map { (identity($0.key), $0.value) }),
            owners: Dictionary(uniqueKeysWithValues: owners.map { (identity($0.key), $0.value) }),
            frontmostPid: frontmost, userActive: userActive, settings: settings, active: active
        )
        return reducer.update(input, now: start.addingTimeInterval(seconds))
    }

    private func kinds(_ notices: [AgentNotice]) -> [AgentNoticeKind] {
        notices.map(\.kind)
    }

    // MARK: Waiting

    func testWaitingIsToldOnceAfterTheDebounce() {
        XCTAssertEqual(sample(0, [reading(1, .working)]), [])
        XCTAssertEqual(sample(10, [reading(1, .waitingForUser)], labels: [1: "wiki-6e"]), [])
        XCTAssertEqual(sample(12, [reading(1, .waitingForUser)]), [], "Not yet 3 seconds")
        let told = sample(14, [reading(1, .waitingForUser)])
        XCTAssertEqual(kinds(told), [.waiting])
        XCTAssertEqual(told.first?.sessions.map(\.label), ["wiki-6e"])
        XCTAssertEqual(told.first?.sessions.first?.waitingSince, start.addingTimeInterval(10))
        XCTAssertEqual(sample(16, [reading(1, .waitingForUser)]), [], "Once")
        XCTAssertEqual(sample(600, [reading(1, .waitingForUser)]), [])
    }

    func testAWaitThatEndsWithinTheDebounceIsNotTold() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(10, [reading(1, .waitingForUser)])
        XCTAssertEqual(sample(12, [reading(1, .working)]), [])
        XCTAssertEqual(sample(14, [reading(1, .working)]), [])
        XCTAssertEqual(sample(20, [reading(1, .working)]), [])
    }

    func testASessionThatAppearsWaitingIsTold() {
        _ = sample(0, [])
        _ = sample(10, [reading(1, .waitingForUser)])
        XCTAssertEqual(kinds(sample(14, [reading(1, .waitingForUser)])), [.waiting])
    }

    func testIdleToWaitingIsNotTold() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .waitingForUser)])
        XCTAssertEqual(sample(14, [reading(1, .waitingForUser)]), [])
    }

    func testASecondQuestionAfterMoreWorkIsToldAgain() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(10, [reading(1, .waitingForUser)])
        XCTAssertEqual(kinds(sample(14, [reading(1, .waitingForUser)])), [.waiting])
        _ = sample(20, [reading(1, .working)])
        _ = sample(30, [reading(1, .waitingForUser)])
        XCTAssertEqual(kinds(sample(34, [reading(1, .waitingForUser)])), [.waiting])
    }

    // MARK: Finished

    func testFinishedIsToldAfterWorkOfThirtySeconds() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)], labels: [1: "wiki"])
        XCTAssertEqual(sample(100, [reading(1, .idle)]), [], "Held for the others that may finish with it")
        let told = sample(102, [reading(1, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 90)
        XCTAssertEqual(told.first?.sessions.first?.label, "wiki")
        XCTAssertEqual(sample(104, [reading(1, .idle)]), [])
    }

    func testShortWorkIsNotTold() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)])
        XCTAssertEqual(sample(39, [reading(1, .idle)]), [])
        XCTAssertEqual(sample(45, [reading(1, .idle)]), [])
    }

    func testThirtySecondsIsTheConstant() {
        XCTAssertEqual(AgentNoticeReducer.shortestWork, 30)
        XCTAssertEqual(AgentNoticeReducer.waitingDebounce, 3)
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)])
        _ = sample(40, [reading(1, .idle)])
        XCTAssertEqual(kinds(sample(42, [reading(1, .idle)])), [.finished])
    }

    func testASessionThatIsGoneAfterWorkFinished() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(60, [])
        let told = sample(65, [])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 60)
    }

    func testAWaitInsideTheWorkCountsAsWorkAndIsNoFinish() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)])
        _ = sample(20, [reading(1, .waitingForUser)])
        XCTAssertEqual(kinds(sample(24, [reading(1, .waitingForUser)])), [.waiting])
        _ = sample(30, [reading(1, .working)])
        _ = sample(70, [reading(1, .idle)])
        let told = sample(72, [reading(1, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 60)
    }

    func testWaitingThenIdleIsNoFinish() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(60, [reading(1, .waitingForUser)])
        _ = sample(64, [reading(1, .waitingForUser)])
        XCTAssertEqual(sample(70, [reading(1, .idle)]), [])
        XCTAssertEqual(sample(80, [reading(1, .idle)]), [])
    }

    func testIdleForOneSampleInsideTheWorkIsNoFinish() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)])
        _ = sample(50, [reading(1, .idle)])
        XCTAssertEqual(sample(51, [reading(1, .working)]), [], "Back at work before it was told")
        XCTAssertEqual(sample(60, [reading(1, .working)]), [])
        _ = sample(62, [reading(1, .idle)])
        let told = sample(64, [reading(1, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 52, "The work goes on from where it began")
    }

    // MARK: Launch, pause, switches

    func testNothingIsToldForWhatWasThereAtLaunch() {
        XCTAssertEqual(sample(0, [reading(1, .waitingForUser), reading(2, .working), reading(3, .idle)]), [])
        XCTAssertEqual(sample(4, [reading(1, .waitingForUser), reading(2, .working), reading(3, .idle)]), [])
        XCTAssertEqual(sample(10, [reading(1, .waitingForUser), reading(2, .working), reading(3, .idle)]), [])
    }

    func testWorkSeenFromLaunchCountsFromLaunch() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(20, [reading(1, .idle)])
        XCTAssertEqual(sample(22, [reading(1, .idle)]), [], "20 seconds seen")
        _ = sample(30, [reading(1, .working)])
        _ = sample(90, [reading(1, .idle)])
        XCTAssertEqual(kinds(sample(92, [reading(1, .idle)])), [.finished])
    }

    func testNothingIsToldWhilePausedOrOff() {
        _ = sample(0, [reading(1, .working), reading(2, .working)], active: false)
        _ = sample(60, [reading(1, .waitingForUser), reading(2, .idle)], active: false)
        XCTAssertEqual(sample(64, [reading(1, .waitingForUser), reading(2, .idle)], active: false), [])
        XCTAssertEqual(sample(70, [reading(1, .waitingForUser), reading(2, .idle)], active: true), [], "Not told later either")
    }

    func testAPauseDropsWhatWasOnItsWay() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(10, [reading(1, .waitingForUser)])
        XCTAssertEqual(sample(12, [reading(1, .waitingForUser)], active: false), [])
        XCTAssertEqual(sample(14, [reading(1, .waitingForUser)]), [])
    }

    func testEachSwitchSilencesItsKind() {
        settings.waiting = false
        _ = sample(0, [reading(1, .working), reading(2, .working)])
        _ = sample(60, [reading(1, .waitingForUser), reading(2, .idle)])
        XCTAssertEqual(kinds(sample(64, [reading(1, .waitingForUser), reading(2, .idle)])), [.finished])
        settings = AgentNoticeSettings(waiting: true, finished: false, onlyWhenAway: true)
        _ = sample(70, [reading(1, .working), reading(2, .working)])
        _ = sample(130, [reading(1, .waitingForUser), reading(2, .idle)])
        XCTAssertEqual(kinds(sample(134, [reading(1, .waitingForUser), reading(2, .idle)])), [.waiting])
    }

    func testDefaults() {
        let defaults = AgentNoticeSettings()
        XCTAssertTrue(defaults.waiting)
        XCTAssertFalse(defaults.finished)
        XCTAssertTrue(defaults.onlyWhenAway)
    }

    func testSettingsAreSavedAndLoaded() throws {
        let name = "AgentNoticesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AgentNoticeSettings.load(from: defaults), AgentNoticeSettings())
        let changed = AgentNoticeSettings(waiting: false, finished: true, onlyWhenAway: false)
        changed.save(to: defaults)
        XCTAssertEqual(AgentNoticeSettings.load(from: defaults), changed)
    }

    func testAgentsUnderARuleAreNotTold() {
        _ = sample(0, [reading(1, .working, .alwaysWorkingByRule), reading(2, .idle, .ignoredByRule)])
        _ = sample(60, [])
        XCTAssertEqual(sample(64, []), [])
    }

    // MARK: Together

    func testThreeThatFinishTogetherGiveOneNotice() {
        let working = [reading(1, .working), reading(2, .working), reading(3, .working)]
        _ = sample(0, working)
        _ = sample(60, [reading(1, .idle), reading(2, .working), reading(3, .working)])
        let told = sample(62, [reading(1, .idle), reading(2, .idle), reading(3, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.count, 3)
        XCTAssertEqual(sample(64, [reading(1, .idle), reading(2, .idle), reading(3, .idle)]), [])
    }

    func testTwoThatFinishTogetherGiveTwoNotices() {
        _ = sample(0, [reading(1, .working), reading(2, .working)])
        _ = sample(60, [reading(1, .idle), reading(2, .idle)])
        let told = sample(62, [reading(1, .idle), reading(2, .idle)])
        XCTAssertEqual(told.map(\.sessions.count), [1, 1])
    }

    func testThreeThatWaitTogetherGiveOneNotice() {
        _ = sample(0, [reading(1, .working), reading(2, .working), reading(3, .working)])
        _ = sample(10, [reading(1, .waitingForUser), reading(2, .working), reading(3, .working)])
        _ = sample(12, [reading(1, .waitingForUser), reading(2, .waitingForUser), reading(3, .waitingForUser)])
        let told = sample(14, [reading(1, .waitingForUser), reading(2, .waitingForUser), reading(3, .waitingForUser)])
        XCTAssertEqual(kinds(told), [.waiting])
        XCTAssertEqual(told.first?.sessions.count, 3)
    }

    func testOneThatChangesLaterIsToldOnItsOwn() {
        _ = sample(0, [reading(1, .working), reading(2, .working), reading(3, .working)])
        _ = sample(60, [reading(1, .idle), reading(2, .idle), reading(3, .working)])
        XCTAssertEqual(sample(62, [reading(1, .idle), reading(2, .idle), reading(3, .working)]).map(\.sessions.count), [1, 1])
        _ = sample(70, [reading(1, .idle), reading(2, .idle), reading(3, .idle)])
        XCTAssertEqual(sample(72, [reading(1, .idle), reading(2, .idle), reading(3, .idle)]).map(\.sessions.count), [1])
    }

    // MARK: Only when away

    func testNotToldWhileTheUserWorksInTheAgentsApp() {
        _ = sample(0, [reading(1, .working)], owners: [1: 500])
        _ = sample(60, [reading(1, .waitingForUser)], owners: [1: 500], frontmost: 500, userActive: true)
        XCTAssertEqual(sample(64, [reading(1, .waitingForUser)], owners: [1: 500], frontmost: 500, userActive: true), [])
        XCTAssertEqual(sample(600, [reading(1, .waitingForUser)], owners: [1: 500]), [], "Not told later: the user saw it")
    }

    func testToldWhenAnotherAppIsInFrontOrTheUserIsAway() {
        _ = sample(0, [reading(1, .working), reading(2, .working)], owners: [1: 500, 2: 500])
        _ = sample(60, [reading(1, .waitingForUser), reading(2, .working)], owners: [1: 500, 2: 500], frontmost: 900, userActive: true)
        XCTAssertEqual(kinds(sample(64, [reading(1, .waitingForUser), reading(2, .working)], frontmost: 900, userActive: true)), [.waiting])
        _ = sample(70, [reading(1, .waitingForUser), reading(2, .waitingForUser)], frontmost: 500, userActive: false)
        let told = sample(74, [reading(1, .waitingForUser), reading(2, .waitingForUser)], frontmost: 500, userActive: false)
        XCTAssertEqual(kinds(told), [.waiting], "In front, and nobody at the keyboard")
        XCTAssertEqual(told.first?.sessions.first?.ownerPid, 500, "The owner is kept from the sample that gave it")
    }

    func testToldWhenTheAppIsNotKnown() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(60, [reading(1, .waitingForUser)], frontmost: 500, userActive: true)
        XCTAssertEqual(kinds(sample(64, [reading(1, .waitingForUser)], frontmost: 500, userActive: true)), [.waiting])
    }

    func testTheUserWhoComesToTheAppBeforeTheNoticeIsNotTold() {
        _ = sample(0, [reading(1, .working)], owners: [1: 500])
        _ = sample(60, [reading(1, .waitingForUser)], frontmost: 900, userActive: true)
        XCTAssertEqual(sample(64, [reading(1, .waitingForUser)], frontmost: 500, userActive: true), [])
    }

    func testWithTheSwitchOffTheFrontAppDoesNotCount() {
        settings.onlyWhenAway = false
        _ = sample(0, [reading(1, .working)], owners: [1: 500])
        _ = sample(60, [reading(1, .waitingForUser)], frontmost: 500, userActive: true)
        XCTAssertEqual(kinds(sample(64, [reading(1, .waitingForUser)], frontmost: 500, userActive: true)), [.waiting])
    }

    func testAFinishedSessionThatIsGoneIsNotToldWhileItsAppIsInFront() {
        _ = sample(0, [reading(1, .working)], owners: [1: 500])
        _ = sample(60, [], frontmost: 500, userActive: true)
        XCTAssertEqual(sample(64, [], frontmost: 500, userActive: true), [])
    }

    // MARK: Owner

    func testTheOwnerIsTheFirstAppUpTheTree() {
        let parents: [Int32: Int32] = [40: 30, 30: 20, 20: 10, 10: 1]
        XCTAssertEqual(AgentOwner.find(from: 40, parent: { parents[$0] }, isApp: { $0 == 20 }), 20, "claude, zsh, login, Terminal")
        XCTAssertEqual(AgentOwner.find(from: 20, parent: { parents[$0] }, isApp: { $0 == 20 }), 20, "The agent's own app")
        XCTAssertNil(AgentOwner.find(from: 40, parent: { parents[$0] }, isApp: { _ in false }), "Under tmux no app is above")
        XCTAssertNil(AgentOwner.find(from: 99, parent: { parents[$0] }, isApp: { _ in false }), "A process that is gone")
        XCTAssertNil(AgentOwner.find(from: 7, parent: { _ in 7 }, isApp: { _ in false }), "No loop")
        XCTAssertNil(AgentOwner.find(from: 1000, parent: { $0 - 1 }, isApp: { $0 == 900 }), "Not deeper than the limit")
    }

    // MARK: Words

    private func session(label: String? = "wiki-6e", workedFor: TimeInterval? = nil, waitingSince: Date? = nil, pid: Int32 = 7, owner: Int32? = 500) -> AgentNotice.Session {
        AgentNotice.Session(
            identity: identity(pid), agentID: "claude", displayName: "Claude Code", label: label, ownerPid: owner,
            workedFor: workedFor, waitingSince: waitingSince
        )
    }

    func testWaitingWords() {
        let notice = AgentNotice(kind: .waiting, sessions: [session(waitingSince: start)])
        let content = AgentNoticeText.content(notice, waitingHold: 300, now: start.addingTimeInterval(4))
        XCTAssertEqual(content.title, "Claude Code is waiting for you")
        XCTAssertEqual(content.subtitle, "wiki-6e")
        XCTAssertEqual(content.body, "Your Mac can sleep in 5 minutes")
        XCTAssertTrue(content.sound)
        XCTAssertEqual(content.thread, "agent-claude")
        XCTAssertEqual(content.id, "waiting-7-5")
        XCTAssertEqual(content.ownerPid, 500)
    }

    func testWaitingWordsWithoutTheHoldOrTheLabel() {
        let notice = AgentNotice(kind: .waiting, sessions: [session(label: nil, waitingSince: start)])
        let content = AgentNoticeText.content(notice, waitingHold: nil, now: start.addingTimeInterval(4))
        XCTAssertEqual(content.title, "Claude Code is waiting for you")
        XCTAssertNil(content.subtitle)
        XCTAssertNil(content.body, "In the mode always the Mac does not sleep")
    }

    func testTheRealWaitingHoldIsSaid() {
        let cases: [(TimeInterval, TimeInterval, String?)] = [
            (300, 4, "Your Mac can sleep in 5 minutes"), (300, 250, "Your Mac can sleep in 1 minute"), (120, 4, "Your Mac can sleep in 2 minutes"),
            (30, 4, "Your Mac can sleep in 1 minute"), (5400, 4, "Your Mac can sleep in 1 hour 30 minutes"), (300, 300, nil), (300, 900, nil),
        ]
        for (hold, elapsed, text) in cases {
            XCTAssertEqual(AgentNoticeText.canSleep(waitingHold: hold, since: start, now: start.addingTimeInterval(elapsed)), text, "\(hold) \(elapsed)")
        }
    }

    func testFinishedWords() {
        let notice = AgentNotice(kind: .finished, sessions: [session(workedFor: 82 * 60)])
        let content = AgentNoticeText.content(notice, waitingHold: 300, now: start)
        XCTAssertEqual(content.title, "Claude Code finished")
        XCTAssertEqual(content.subtitle, "wiki-6e")
        XCTAssertEqual(content.body, "After 1 hour 22 minutes")
        XCTAssertFalse(content.sound)
        XCTAssertEqual(content.thread, "agent-claude")
        XCTAssertEqual(content.id, "finished-7-5")
        let short = AgentNoticeText.content(AgentNotice(kind: .finished, sessions: [session(label: nil, workedFor: 45)]), waitingHold: nil, now: start)
        XCTAssertNil(short.subtitle)
        XCTAssertNil(short.body, "Under a minute there is no length to say")
    }

    func testWordsForSeveral() {
        let three = [session(pid: 1), session(pid: 2), session(pid: 3, owner: 600)]
        let finished = AgentNoticeText.content(AgentNotice(kind: .finished, sessions: three), waitingHold: 300, now: start)
        XCTAssertEqual(finished.title, "3 agents finished")
        XCTAssertNil(finished.subtitle)
        XCTAssertNil(finished.body)
        XCTAssertFalse(finished.sound)
        XCTAssertNil(finished.ownerPid, "They run in two apps")
        let waiting = AgentNoticeText.content(
            AgentNotice(kind: .waiting, sessions: three.map { var session = $0; session.waitingSince = start; session.ownerPid = 500; return session }),
            waitingHold: 300, now: start.addingTimeInterval(4)
        )
        XCTAssertEqual(waiting.title, "3 agents are waiting for you")
        XCTAssertEqual(waiting.body, "Your Mac can sleep in 5 minutes")
        XCTAssertTrue(waiting.sound)
        XCTAssertEqual(waiting.ownerPid, 500)
    }

    func testASessionLabelNeverPrints() {
        let session = session(label: "what the user typed")
        XCTAssertFalse("\(session)".contains("typed"))
        XCTAssertFalse(String(reflecting: session).contains("typed"))
        XCTAssertFalse("\(AgentNotice(kind: .waiting, sessions: [session]))".contains("typed"))
    }
}
