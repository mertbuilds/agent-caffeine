import XCTest

final class AgentNoticesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private var reducer = AgentNoticeReducer()
    private var settings = AgentNoticeSettings(waiting: true, finished: true, onlyWhenAway: true)

    private func identity(_ pid: Int32) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startTime: 5)
    }

    private func reading(
        _ pid: Int32, _ state: WorkState, _ reason: VerdictReason = .reportsBusy, id: String = "claude", name: String = "Claude Code",
        turn: WorkState? = nil, since: TimeInterval? = nil
    ) -> AgentReading {
        AgentReading(
            agentID: id, displayName: name, level: .state, identity: identity(pid),
            verdict: AgentVerdict(state: state, confidence: .reported, reason: reason),
            turn: turn.map { AgentTurn(state: $0, since: since.map(start.addingTimeInterval)) }
        )
    }

    private func outcomes() -> [AgentNoticeDecision.Outcome] {
        reducer.decisions.map(\.outcome)
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

    func testIdleToWaitingIsTold() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .waitingForUser)])
        XCTAssertEqual(kinds(sample(14, [reading(1, .waitingForUser)])), [.waiting], "A question of a background task of an idle session")
        XCTAssertEqual(sample(16, [reading(1, .waitingForUser)]), [], "Once")
    }

    func testAnEndThatTurnsIntoAQuestionIsAWaitAndNoFinish() {
        _ = sample(0, [reading(1, .working)])
        XCTAssertEqual(sample(60, [reading(1, .idle)]), [])
        XCTAssertEqual(sample(60.4, [reading(1, .waitingForUser)]), [])
        XCTAssertEqual(sample(62, [reading(1, .waitingForUser)]), [], "No finish")
        XCTAssertEqual(kinds(sample(64, [reading(1, .waitingForUser)])), [.waiting])
        XCTAssertEqual(outcomes(), [.asksInstead, .told])
        XCTAssertEqual(sample(66, [reading(1, .waitingForUser)]), [], "The finish is not told later")
        _ = sample(70, [reading(1, .working)])
        _ = sample(80, [reading(1, .idle)])
        XCTAssertEqual(sample(82, [reading(1, .idle)]).first?.sessions.first?.workedFor, 80, "The work went on over the question")
    }

    func testAnEndWithAShortWaitAfterItIsStillAFinish() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(60, [reading(1, .idle)])
        _ = sample(60.4, [reading(1, .waitingForUser)])
        let told = sample(62, [reading(1, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 60)
        XCTAssertEqual(reducer.decisions.map(\.logLine), ["waiting skipped pid 1: the wait ended after 1.6 s", "finished fired pid 1 after 60 s"])
        XCTAssertEqual(sample(64, [reading(1, .idle)]), [])
        XCTAssertEqual(sample(70, [reading(1, .idle)]), [])
    }

    func testAnEndThatTurnsIntoAQuestionWithTheWaitingSwitchOffIsAFinish() {
        settings.waiting = false
        _ = sample(0, [reading(1, .working)])
        _ = sample(60, [reading(1, .idle)])
        _ = sample(60.4, [reading(1, .waitingForUser)])
        XCTAssertEqual(kinds(sample(64, [reading(1, .waitingForUser)])), [.finished])
        XCTAssertEqual(sample(70, [reading(1, .idle)]), [])
        XCTAssertEqual(sample(80, [reading(1, .idle)]), [])
    }

    func testAWaitBehindARunningCommandIsTold() {
        // The verdict is working for the command, and the agent asks.
        _ = sample(0, [reading(1, .working, turn: .working)])
        _ = sample(10, [reading(1, .working, .runningCommand(1), turn: .waitingForUser)])
        XCTAssertEqual(kinds(sample(14, [reading(1, .working, .runningCommand(1), turn: .waitingForUser)])), [.waiting])
        XCTAssertEqual(sample(20, [reading(1, .waitingForUser, .asksPermission, turn: .waitingForUser)]), [], "The command ended: no second one")
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

    func testFinishedIsTold() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)], labels: [1: "wiki"])
        XCTAssertEqual(sample(100, [reading(1, .idle)]), [], "Held for the others that may finish with it")
        let told = sample(102, [reading(1, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 90)
        XCTAssertEqual(told.first?.sessions.first?.label, "wiki")
        XCTAssertEqual(sample(104, [reading(1, .idle)]), [])
    }

    func testShortWorkIsToldToo() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)])
        XCTAssertEqual(sample(14, [reading(1, .idle)]), [])
        let told = sample(16, [reading(1, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 4)
        XCTAssertEqual(reducer.decisions.map(\.logLine), ["finished fired pid 1 after 4 s"])
    }

    func testTheDebounces() {
        XCTAssertEqual(AgentNoticeReducer.finishedDebounce, 2)
        XCTAssertEqual(AgentNoticeReducer.waitingDebounce, 3)
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)])
        _ = sample(40, [reading(1, .idle)])
        XCTAssertEqual(sample(41.9, [reading(1, .idle)]), [])
        XCTAssertEqual(kinds(sample(42, [reading(1, .idle)])), [.finished])
    }

    func testEveryTurnOfManyShortOnesIsTold() {
        _ = sample(0, [reading(1, .idle)])
        var told = 0
        for turn in 0..<5 {
            let at = TimeInterval(10 + turn * 20)
            _ = sample(at, [reading(1, .working)])
            XCTAssertEqual(sample(at + 6, [reading(1, .idle)]), [])
            let notices = sample(at + 8, [reading(1, .idle)])
            XCTAssertEqual(notices.first?.sessions.first?.workedFor, 6)
            told += notices.count
            XCTAssertEqual(sample(at + 10, [reading(1, .idle)]), [])
        }
        XCTAssertEqual(told, 5)
    }

    func testTheTurnCountsFromWhenTheAgentSaysItBegan() {
        // The app started in the middle of a turn that began 500 seconds before.
        _ = sample(0, [reading(1, .working, turn: .working, since: -500)])
        _ = sample(100, [reading(1, .idle, turn: .idle)])
        XCTAssertEqual(sample(102, [reading(1, .idle, turn: .idle)]).first?.sessions.first?.workedFor, 600)
        // Not from before the reducer saw it idle, and not from a time ahead.
        _ = sample(200, [reading(1, .working, turn: .working, since: -500)])
        _ = sample(260, [reading(1, .idle, turn: .idle)])
        XCTAssertEqual(sample(262, [reading(1, .idle, turn: .idle)]).first?.sessions.first?.workedFor, 158, "From the last idle sample at 102")
        _ = sample(300, [reading(1, .working, turn: .working, since: 900)])
        _ = sample(330, [reading(1, .idle, turn: .idle)])
        XCTAssertEqual(sample(332, [reading(1, .idle, turn: .idle)]).first?.sessions.first?.workedFor, 30)
    }

    func testTheTurnEndIsToldWhileACommandRunsOnAndNotAgainWhenItStops() {
        _ = sample(0, [reading(1, .idle, turn: .idle)])
        _ = sample(10, [reading(1, .working, turn: .working, since: 10)])
        // The answer is there, and a dev server it started still runs.
        XCTAssertEqual(sample(100, [reading(1, .working, .runningCommand(1), turn: .idle)]), [])
        let told = sample(102, [reading(1, .working, .runningCommand(1), turn: .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 90)
        XCTAssertEqual(sample(500, [reading(1, .working, .runningCommand(1), turn: .idle)]), [])
        XCTAssertEqual(sample(600, [reading(1, .idle, .atPrompt, turn: .idle)]), [], "The command stopped")
        XCTAssertEqual(sample(602, [reading(1, .idle, .atPrompt, turn: .idle)]), [])
    }

    func testALeftOverCommandOfAnIdleSessionIsNoWork() {
        // As recorded: a command of a session that is idle for days uses
        // the processor for some seconds, again and again.
        _ = sample(0, [reading(1, .idle, .atPrompt, turn: .idle)])
        for at in stride(from: 10.0, to: 200, by: 40) {
            XCTAssertEqual(sample(at, [reading(1, .working, .runningCommand(1), turn: .idle)]), [])
            XCTAssertEqual(sample(at + 35, [reading(1, .idle, .atPrompt, turn: .idle)]), [])
            XCTAssertEqual(sample(at + 38, [reading(1, .idle, .atPrompt, turn: .idle)]), [])
        }
        XCTAssertEqual(reducer.decisions, [])
    }

    func testAnAgentWithoutATurnFollowsItsVerdict() {
        _ = sample(0, [reading(1, .idle, .noActivity(minutes: 1), id: "opencode")])
        _ = sample(10, [reading(1, .working, .cpuActivity, id: "opencode")])
        _ = sample(50, [reading(1, .idle, .noActivity(minutes: 0), id: "opencode")])
        XCTAssertEqual(kinds(sample(52, [reading(1, .idle, .noActivity(minutes: 0), id: "opencode")])), [.finished])
    }

    func testAFlickerOfTheStateIsNoFinishAndTheWorkGoesOn() {
        _ = sample(0, [reading(1, .idle)])
        _ = sample(10, [reading(1, .working)])
        // Short work, one idle sample, work again: one task.
        XCTAssertEqual(sample(15, [reading(1, .idle)]), [])
        XCTAssertEqual(sample(15.4, [reading(1, .working)]), [])
        XCTAssertEqual(reducer.decisions.map(\.logLine), ["finished skipped pid 1: working again after 0.4 s"])
        XCTAssertEqual(sample(18, [reading(1, .working)]), [])
        _ = sample(40, [reading(1, .idle)])
        let told = sample(42, [reading(1, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.first?.workedFor, 30, "From the first start")
        XCTAssertEqual(sample(44, [reading(1, .idle)]), [], "Once")
    }

    func testASessionThatIsReplacedIsToldOnceEach() {
        // The process of a session ends in its work and a new one takes
        // its place: the old one finished, the new one is no news yet.
        _ = sample(0, [reading(1, .working)])
        XCTAssertEqual(sample(60, [reading(2, .working)]), [])
        let told = sample(62, [reading(2, .working)])
        XCTAssertEqual(told.map { $0.sessions.map(\.identity.pid) }, [[1]])
        _ = sample(100, [reading(2, .idle)])
        XCTAssertEqual(sample(102, [reading(2, .idle)]).map { $0.sessions.map(\.identity.pid) }, [[2]])
        // A new one that waits at once is told.
        _ = sample(200, [reading(2, .idle), reading(3, .waitingForUser)])
        XCTAssertEqual(kinds(sample(203, [reading(2, .idle), reading(3, .waitingForUser)])), [.waiting])
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

    func testWhatWaitedAtLaunchIsSaidInTheLogOnce() {
        _ = sample(0, [reading(1, .waitingForUser)])
        XCTAssertEqual(reducer.decisions.map(\.logLine), ["waiting skipped pid 1: it waited already at launch"])
        _ = sample(2, [reading(1, .waitingForUser)])
        XCTAssertEqual(reducer.decisions, [])
    }

    func testWorkSeenFromLaunchCountsFromLaunch() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(20, [reading(1, .idle)])
        XCTAssertEqual(sample(22, [reading(1, .idle)]).first?.sessions.first?.workedFor, 20, "20 seconds seen")
        _ = sample(30, [reading(1, .working)])
        _ = sample(90, [reading(1, .idle)])
        XCTAssertEqual(sample(92, [reading(1, .idle)]).first?.sessions.first?.workedFor, 60)
    }

    func testNothingIsToldWhilePausedOrOff() {
        _ = sample(0, [reading(1, .working), reading(2, .working)], active: false)
        _ = sample(60, [reading(1, .waitingForUser), reading(2, .idle)], active: false)
        XCTAssertEqual(outcomes(), [.notActive, .notActive])
        XCTAssertEqual(sample(64, [reading(1, .waitingForUser), reading(2, .idle)], active: false), [])
        XCTAssertEqual(sample(70, [reading(1, .waitingForUser), reading(2, .idle)], active: true), [], "Not told later either")
    }

    func testAPauseDropsWhatWasOnItsWay() {
        _ = sample(0, [reading(1, .working)])
        _ = sample(10, [reading(1, .waitingForUser)])
        XCTAssertEqual(sample(12, [reading(1, .waitingForUser)], active: false), [])
        XCTAssertEqual(outcomes(), [.notActive])
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
        XCTAssertEqual(sample(62, [reading(1, .idle), reading(2, .idle), reading(3, .idle)]), [], "The last two may still go on")
        let told = sample(64, [reading(1, .idle), reading(2, .idle), reading(3, .idle)])
        XCTAssertEqual(kinds(told), [.finished])
        XCTAssertEqual(told.first?.sessions.count, 3)
        XCTAssertEqual(sample(66, [reading(1, .idle), reading(2, .idle), reading(3, .idle)]), [])
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
        XCTAssertEqual(sample(14, [reading(1, .waitingForUser), reading(2, .waitingForUser), reading(3, .waitingForUser)]), [], "Two of them wait for 2 seconds only")
        let told = sample(15, [reading(1, .waitingForUser), reading(2, .waitingForUser), reading(3, .waitingForUser)])
        XCTAssertEqual(kinds(told), [.waiting])
        XCTAssertEqual(told.first?.sessions.count, 3)
    }

    func testARowOfChangesLosesNoneAndHoldsNoneBack() {
        // Five sessions end one second apart: no window that rolls on.
        let pids: [Int32] = [1, 2, 3, 4, 5]
        _ = sample(0, pids.map { reading($0, .working) })
        var told: [[Int32]] = []
        var times: [TimeInterval] = []
        for second in 60...70 {
            let done = pids.filter { Int($0) <= second - 60 }
            let notices = sample(TimeInterval(second), pids.map { reading($0, done.contains($0) ? .idle : .working) })
            told += notices.map { $0.sessions.map(\.identity.pid) }
            times += notices.map { _ in TimeInterval(second) }
        }
        XCTAssertEqual(told, [[1, 2, 3], [4], [5]])
        XCTAssertEqual(times, [65, 67, 67], "The first group is told 2 seconds after its last, not after the last of all")
    }

    func testAFinishOnItsWayStaysWhenAnotherSessionChanges() {
        _ = sample(0, [reading(1, .working), reading(2, .working), reading(3, .idle)])
        _ = sample(60, [reading(1, .idle), reading(2, .working), reading(3, .idle)])
        XCTAssertEqual(sample(61, [reading(1, .idle), reading(2, .waitingForUser), reading(3, .working)]), [])
        XCTAssertEqual(kinds(sample(62, [reading(1, .idle), reading(2, .waitingForUser), reading(3, .working)])), [.finished])
        XCTAssertEqual(kinds(sample(64, [reading(1, .idle), reading(2, .waitingForUser), reading(3, .idle)])), [.waiting])
        XCTAssertEqual(kinds(sample(66, [reading(1, .idle), reading(2, .waitingForUser), reading(3, .idle)])), [.finished])
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
        XCTAssertEqual(reducer.decisions.map(\.logLine), ["waiting skipped pid 1: front app is its app"])
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
        _ = sample(0, [reading(1, .working), reading(2, .working)], owners: [1: 500, 2: 500])
        _ = sample(60, [reading(1, .waitingForUser), reading(2, .idle)], frontmost: 500, userActive: true)
        XCTAssertEqual(kinds(sample(64, [reading(1, .waitingForUser), reading(2, .idle)], frontmost: 500, userActive: true)), [.waiting, .finished])
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
        XCTAssertEqual(content.key, "waiting-7-5")
        XCTAssertEqual(content.id, "waiting-7-5-1000004000")
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
        XCTAssertEqual(content.key, "finished-7-5")
        XCTAssertEqual(content.id, "finished-7-5-1000000000")
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

    func testEachNotificationHasAnIdentifierOfItsOwn() {
        // The same session finishes twice, and three wait twice.
        let one = AgentNotice(kind: .finished, sessions: [session(workedFor: 40)])
        let three = AgentNotice(kind: .waiting, sessions: [session(pid: 1), session(pid: 2), session(pid: 3)])
        var ids: Set<String> = []
        for seconds in [0.0, 30, 60] {
            for notice in [one, three] {
                let content = AgentNoticeText.content(notice, waitingHold: nil, now: start.addingTimeInterval(seconds))
                XCTAssertTrue(ids.insert(content.id).inserted, content.id)
                XCTAssertEqual(content.thread, notice.sessions.count == 1 ? "agent-claude" : "agents", "Grouped by the thread only")
            }
        }
        XCTAssertEqual(ids.count, 6)
    }

    func testTheLogLinesHoldNoName() {
        _ = sample(0, [reading(1, .working, name: "what the user typed")], labels: [1: "a secret folder"])
        _ = sample(60, [reading(1, .waitingForUser, name: "what the user typed")])
        _ = sample(61, [reading(1, .working, name: "what the user typed")])
        _ = sample(70, [reading(1, .idle, name: "what the user typed")])
        _ = sample(72, [reading(1, .idle, name: "what the user typed")])
        XCTAssertEqual(reducer.decisions.map(\.logLine), ["finished fired pid 1 after 70 s"])
        _ = sample(80, [reading(1, .waitingForUser, name: "what the user typed")])
        _ = sample(81, [reading(1, .idle, name: "what the user typed")])
        XCTAssertEqual(reducer.decisions.map(\.logLine), ["waiting skipped pid 1: the wait ended after 1.0 s"])
        XCTAssertFalse("\(reducer.decisions)".contains("typed"))
        XCTAssertFalse("\(reducer.decisions)".contains("secret"))
    }

    // MARK: History

    func testTheHistoryKeepsTheLastFiveAndWhatBecameOfThem() {
        var history = AgentNoticeHistory()
        for index in 0..<7 {
            let notice = AgentNotice(kind: .finished, sessions: [session(label: "a secret folder", workedFor: 40)])
            history.posted(AgentNoticeText.content(notice, waitingHold: nil, now: start.addingTimeInterval(TimeInterval(index))), at: start.addingTimeInterval(TimeInterval(index)))
        }
        XCTAssertEqual(history.entries.count, 5)
        XCTAssertEqual(history.entries.first?.id, "finished-7-5-1000006000", "Newest first")
        XCTAssertEqual(history.entries.first?.result.text, "Sending")
        history.delivered("finished-7-5-1000006000", .delivered)
        history.delivered("finished-7-5-1000005000", .noBanner)
        history.delivered("gone", .failed)
        XCTAssertEqual(history.entries.prefix(3).map(\.result), [.sent(.delivered), .sent(.noBanner), .sending])
        XCTAssertEqual(history.entries.first?.title, "Claude Code finished")
        XCTAssertFalse("\(history)".contains("secret"))
        history.note(AgentNoticeDecision(kind: .waiting, pid: 1, outcome: .inFront), at: start)
        history.note(AgentNoticeDecision(kind: .finished, pid: 1, outcome: .backAtWork(after: 1)), at: start)
        history.note(AgentNoticeDecision(kind: .finished, pid: 1, outcome: .told), at: start)
        XCTAssertEqual(history.entries.count, 5)
        XCTAssertEqual(history.entries.first?.result, .inFront)
        XCTAssertEqual(history.entries.first?.title, "An agent started to wait for you")
    }

    func testASessionLabelNeverPrints() {
        let session = session(label: "what the user typed")
        XCTAssertFalse("\(session)".contains("typed"))
        XCTAssertFalse(String(reflecting: session).contains("typed"))
        XCTAssertFalse("\(AgentNotice(kind: .waiting, sessions: [session]))".contains("typed"))
    }
}
