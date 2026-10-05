import XCTest

final class MenuModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func hold(
        _ id: String, _ name: String, pid: Int32, _ state: WorkState, _ reason: VerdictReason, cause: HoldCause? = nil
    ) -> AgentHold {
        AgentHold(
            reading: AgentReading(
                agentID: id, displayName: name, level: .state, identity: identity(pid),
                verdict: AgentVerdict(state: state, confidence: .reported, reason: reason)
            ),
            cause: cause
        )
    }

    private func claude(pid: Int32, _ state: WorkState, _ reason: VerdictReason = .atPrompt) -> AgentHold {
        hold("claude", "Claude Code", pid: pid, state, reason)
    }

    private func identity(_ pid: Int32) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startTime: 5)
    }

    private func input(_ headline: HoldHeadline, _ perAgent: [AgentHold] = []) -> PanelInput {
        PanelInput(decision: HoldDecision(hold: headline.keepsAwake, lidClosedFlag: false, headline: headline, perAgent: perAgent))
    }

    /// Each hold in its state since the given number of seconds.
    private func clock(_ perAgent: [AgentHold], secondsAgo: [Int32: TimeInterval]) -> StateClock {
        var clock = StateClock()
        for seconds in Set(secondsAgo.values).sorted(by: >) {
            let seen = perAgent.map(\.reading).filter { (secondsAgo[$0.identity.pid] ?? 0) >= seconds }
            clock = clock.updated(with: seen, now: now.addingTimeInterval(-seconds))
        }
        return clock.updated(with: perAgent.map(\.reading), now: now)
    }

    // MARK: Hero

    func testHeadlinePairs() {
        let awake = "Your Mac stays awake"
        let canSleep = "Your Mac can sleep"
        let cases: [(HoldHeadline, String, String)] = [
            (.working(.one("Claude Code")), awake, "Claude Code is working"),
            (.working(.many(2)), awake, "2 agents are working"),
            (.waitingHeld(.one("Codex")), awake, "Codex waits for you"),
            (.waitingHeld(.many(2)), awake, "2 agents wait for you"),
            (.finishedRecently(.one("Claude Code")), awake, "Claude Code finished a moment ago"),
            (.finishedRecently(.many(3)), awake, "3 agents finished a moment ago"),
            (.open(.one("opencode")), awake, "opencode is open"),
            (.open(.many(4)), awake, "4 agents are open"),
            (.alwaysOn, awake, "Until you switch it off"),
            (.remoteAccess, awake, "Phone access is on"),
            (.idle(.one("Codex")), canSleep, "Codex is idle"),
            (.idle(.many(5)), canSleep, "All agents are idle"),
            (.waitingReleased(.one("Codex")), canSleep, "Codex waits for your answer"),
            (.waitingReleased(.many(2)), canSleep, "2 agents wait for your answer"),
            (.noAgents, canSleep, "No agent is open"),
            (.safetyStop(.batteryLow(percent: 20)), canSleep, "Battery at 20 percent"),
            (.safetyStop(.tooHot), canSleep, "It got too hot"),
            (.switchedOff, "agent caffeine is off", "Your Mac sleeps as usual"),
            (.notEntitled(.trialOver), canSleep, "The trial ended"),
            (.notEntitled(.unverified), canSleep, "License not checked for 30 days"),
            (.notEntitled(.activationRemoved), canSleep, "This Mac is no longer activated"),
        ]
        for (headline, title, subtitle) in cases {
            let state = MenuModel.state(input(headline), now: now)
            XCTAssertEqual(state.title, title, "\(headline)")
            XCTAssertEqual(state.subtitle, subtitle, "\(headline)")
            XCTAssertEqual(state.title == awake, headline.keepsAwake, "\(headline)")
            for text in [state.title, state.subtitle] {
                XCTAssertFalse(text.hasSuffix("."), text)
                XCTAssertFalse(text.contains("\u{2014}"), text)
            }
        }
        XCTAssertEqual(MenuModel.state(input(.working(.many(2))), now: now).headlineAccessibilityLabel, "Your Mac stays awake, 2 agents are working")
    }

    func testWaitingHeadlineCountsTheHoldDown() {
        let codex = hold("codex", "Codex", pid: 1, .waitingForUser, .asksPermission, cause: .waitingForUser)
        var input = input(.waitingHeld(.one("Codex")), [codex])
        input.settings.waitingHold = 300
        let cases: [(TimeInterval, String)] = [
            (0, "Codex waits for you, for 5 more minutes"),
            (61, "Codex waits for you, for 4 more minutes"),
            (120, "Codex waits for you, for 3 more minutes"),
            (241, "Codex waits for you, for 1 more minute"),
            (299, "Codex waits for you, for 1 more minute"),
        ]
        for (waited, subtitle) in cases {
            input.clock = clock([codex], secondsAgo: [1: waited])
            XCTAssertEqual(MenuModel.state(input, now: now).subtitle, subtitle, "after \(waited) s")
        }
    }

    func testTheLongestWaitingHoldCounts() {
        let perAgent = [
            hold("codex", "Codex", pid: 1, .waitingForUser, .asksPermission, cause: .waitingForUser),
            claude(pid: 2, .waitingForUser, .asksPermission),
            hold("claude", "Claude Code", pid: 3, .waitingForUser, .asksPermission, cause: .waitingForUser),
        ]
        var input = input(.waitingHeld(.many(2)), perAgent)
        // The second one waits since a moment ago, and its hold has run out.
        input.clock = clock(perAgent, secondsAgo: [1: 200, 2: 0, 3: 30])
        XCTAssertEqual(MenuModel.state(input, now: now).subtitle, "2 agents wait for you, for 5 more minutes")
    }

    func testEveryHeroPose() {
        let cases: [(HoldHeadline, HeroPose)] = [
            (.working(.one("Claude Code")), .awake(wisps: 2)),
            (.working(.many(2)), .awake(wisps: 2)),
            (.working(.many(3)), .awake(wisps: 3)),
            (.working(.many(7)), .awake(wisps: 3)),
            (.finishedRecently(.one("Claude Code")), .awake(wisps: 2)),
            (.open(.many(4)), .awake(wisps: 2)),
            (.alwaysOn, .awake(wisps: 2)),
            (.remoteAccess, .awake(wisps: 2)),
            (.waitingHeld(.one("Codex")), .attentive),
            (.idle(.many(3)), .asleep),
            (.waitingReleased(.one("Codex")), .asleep),
            (.noAgents, .asleep),
            (.switchedOff, .off),
            (.notEntitled(.trialOver), .off),
            (.safetyStop(.batteryLow(percent: 12)), .safetyStop(.battery)),
            (.safetyStop(.tooHot), .safetyStop(.heat)),
        ]
        for (headline, pose) in cases {
            XCTAssertEqual(MenuModel.state(input(headline), now: now).pose, pose, "\(headline)")
        }
    }

    func testTheRobotIsKnockedOutWhenTheHelperWasSwitchedOff() {
        var awake = input(.alwaysOn)
        awake.flagLeftOn = true
        XCTAssertEqual(MenuModel.state(awake, now: now).pose, .helperOff)
        // A safety stop comes first, as in the line below the headline.
        var stopped = input(.safetyStop(.tooHot))
        stopped.flagLeftOn = true
        XCTAssertEqual(MenuModel.state(stopped, now: now).pose, .safetyStop(.heat))
    }

    func testTheHeadlineSaysThatTheMacMayNotSleepWhenTheHelperWasSwitchedOff() {
        for headline in [HoldHeadline.alwaysOn, .working(.one("Claude Code")), .noAgents, .switchedOff] {
            var input = input(headline)
            input.flagLeftOn = true
            let state = MenuModel.state(input, now: now)
            XCTAssertEqual(state.title, "Your Mac may not sleep", "\(headline)")
            XCTAssertEqual(state.subtitle, "agent caffeine was switched off in Login Items", "\(headline)")
            XCTAssertEqual(state.attention?.actions.map(\.title), ["Open System Settings"], "\(headline)")
        }
        // A safety stop keeps its own headline, as it keeps its robot.
        var stopped = input(.safetyStop(.tooHot))
        stopped.flagLeftOn = true
        XCTAssertEqual(MenuModel.state(stopped, now: now).title, "Your Mac can sleep")
    }

    func testEveryRobotLook() {
        let awake = RobotLook(pose: .awake(wisps: 3))
        XCTAssertEqual([awake.eyes, RobotLook(pose: .attentive).eyes, RobotLook(pose: .asleep).eyes, RobotLook(pose: .off).eyes], [.happy, .open, .closed, .dim])
        XCTAssertEqual(awake.wisps, 3)
        XCTAssertEqual(RobotLook(pose: .attentive).antenna, .amber)
        XCTAssertTrue(RobotLook(pose: .asleep).snoozes)
        XCTAssertEqual(RobotLook(pose: .off).saturation, 0)
        // Only a robot that is awake steams, bobs and blinks.
        for pose in [HeroPose.asleep, .off, .safetyStop(.battery), .safetyStop(.heat), .helperOff] {
            let look = RobotLook(pose: pose)
            XCTAssertEqual(look.wisps, 0, "\(pose)")
            XCTAssertEqual(look.bob, 0, "\(pose)")
            XCTAssertFalse(look.blinks, "\(pose)")
        }
        // The stops that knock the robot out: red crosses, a red antenna.
        let badges: [(HeroPose, String?)] = [(.safetyStop(.battery), "battery.25"), (.safetyStop(.heat), "thermometer.high"), (.helperOff, nil)]
        for (pose, badge) in badges {
            let look = RobotLook(pose: pose)
            XCTAssertEqual(look.eyes, .dead, "\(pose)")
            XCTAssertEqual(look.antenna, .red, "\(pose)")
            XCTAssertEqual(look.badge, badge, "\(pose)")
        }
    }

    func testTheRobotFloatsOnlyInAnOpenMenu() {
        let travel = RobotLook(pose: .awake(wisps: 2)).bob
        XCTAssertTrue(RobotFloat.runs(travel: travel, isOpen: true, reduceMotion: false, frozen: false))
        XCTAssertFalse(RobotFloat.runs(travel: travel, isOpen: false, reduceMotion: false, frozen: false), "A closed menu animates nothing")
        XCTAssertFalse(RobotFloat.runs(travel: travel, isOpen: true, reduceMotion: true, frozen: false))
        XCTAssertFalse(RobotFloat.runs(travel: travel, isOpen: true, reduceMotion: false, frozen: true))
        XCTAssertFalse(RobotFloat.runs(travel: RobotLook(pose: .asleep).bob, isOpen: true, reduceMotion: false, frozen: false))
    }

    /// The float as a 120 Hz display shows it, over one loop.
    func testTheFloatMovesWithoutStepsOrStops() {
        let rate = 120.0
        let count = Int(RobotFloat.period * rate)
        let heights = (0...count).map { RobotFloat.travel * RobotFloat.rise(at: Double($0) / rate) }
        XCTAssertEqual(heights[0], 0, accuracy: 0.0001, "It starts on the tile")
        XCTAssertEqual(heights[count / 2], RobotFloat.travel, accuracy: 0.0001)
        XCTAssertEqual(heights[count], 0, accuracy: 0.0001, "The loop closes")
        XCTAssertTrue((2...2.5).contains(RobotFloat.travel))

        let steps = zip(heights.dropFirst(), heights).map { $0 - $1 }
        XCTAssertLessThan(steps.map(abs).max() ?? 1, 0.05, "No step that shows")
        // Up for the first half, down for the second, never back.
        XCTAssertTrue(steps.prefix(count / 2).allSatisfy { $0 >= 0 })
        XCTAssertTrue(steps.suffix(count / 2).allSatisfy { $0 <= 0 })
        // It only slows at the bottom and at the top. Anywhere else no
        // more than 3 frames in a row stand still.
        let still = 0.1 * RobotFloat.travel / Double(count / 2)
        var run = 0
        for (index, step) in steps.enumerated() {
            let turn = Double(index) / Double(count / 2)
            let nearTurn = abs(turn - turn.rounded()) < 0.15
            run = abs(step) < still && !nearTurn ? run + 1 : 0
            XCTAssertLessThanOrEqual(run, 3, "A stop at \(Double(index) / rate) s")
        }
        // The two ways mirror each other.
        XCTAssertEqual(RobotFloat.rise(at: 0.7), RobotFloat.rise(at: RobotFloat.period - 0.7), accuracy: 0.0001)
    }

    func testTheRobotBlinksNowAndThen() {
        let first = RobotBlink.gaps[0]
        XCTAssertEqual(RobotBlink.closure(at: 0), 0)
        XCTAssertEqual(RobotBlink.closure(at: first - RobotBlink.duration / 2), 1, accuracy: 0.001)
        XCTAssertEqual(RobotBlink.closure(at: first + 1), 0)
        // The pattern starts again after the last gap.
        let round = RobotBlink.gaps.reduce(0, +)
        XCTAssertEqual(RobotBlink.closure(at: round + first - RobotBlink.duration / 2), 1, accuracy: 0.001)
        XCTAssertTrue(RobotBlink.gaps.allSatisfy { (4...7).contains($0) })
    }

    // MARK: Attention

    func testNothingAsksForAttentionWhenAllIsWell() {
        var input = input(.working(.one("Claude Code")))
        XCTAssertNil(MenuModel.attention(input))
        input.entitlement = .trial(daysLeft: 3)
        XCTAssertNil(MenuModel.attention(input), "The trial is named in Preferences until 2 days are left")
        input.lidClosedNeedsSetup = true
        input.lidClosedHintDismissed = true
        XCTAssertNil(MenuModel.attention(input))
    }

    func testAttentionTexts() {
        var battery = input(.safetyStop(.batteryLow(percent: 18)))
        battery.settings.batteryFloorPercent = 20
        XCTAssertEqual(MenuModel.attention(battery), PanelAttention(kind: .safetyStop, text: "Starts again when the battery is at 25 percent"))
        XCTAssertEqual(MenuModel.attention(input(.safetyStop(.tooHot))), PanelAttention(kind: .safetyStop, text: "Starts again when your Mac has cooled down"))

        var helper = input(.alwaysOn)
        helper.flagLeftOn = true
        XCTAssertEqual(MenuModel.attention(helper), PanelAttention(
            kind: .helperSwitchedOff,
            text: "Allow it again and your Mac sleeps as usual",
            actions: [.openLoginItems]
        ))

        var lid = input(.noAgents)
        lid.lidClosedNeedsSetup = true
        XCTAssertEqual(MenuModel.attention(lid), PanelAttention(
            kind: .lidClosedNotSetUp, text: "Lid closed on battery is not set up", actions: [.setUpLidClosed, .dismissLidClosedHint]
        ))
    }

    func testLicenseAttention() {
        let cases: [(Entitlement, Bool, String, [PanelAction])] = [
            (.trial(daysLeft: 2), false, "The trial ends in 2 days", [.buy]),
            (.trial(daysLeft: 1), false, "The trial ends in 1 day", [.buy]),
            (.trial(daysLeft: 1), true, "The trial ends in 1 day", [.enterKey]),
            (.expired(.trialOver), false, "Buy a key to keep your Mac awake", [.buy, .enterKey]),
            (.expired(.unverified), true, "Connect to the internet, then check again", [.checkLicense]),
            (.expired(.activationRemoved), true, "Activate this Mac again to keep it awake", [.activateAgain, .enterKey]),
        ]
        for (entitlement, hasKey, text, actions) in cases {
            var input = input(.noAgents)
            input.entitlement = entitlement
            input.hasLicenseKey = hasKey
            XCTAssertEqual(MenuModel.attention(input), PanelAttention(kind: .license, text: text, actions: actions), "\(entitlement)")
        }
    }

    func testTheMostUrgentAttentionWins() {
        var input = input(.safetyStop(.tooHot))
        input.flagLeftOn = true
        input.entitlement = .expired(.trialOver)
        input.lidClosedNeedsSetup = true
        XCTAssertEqual(MenuModel.attention(input)?.kind, .safetyStop)
        input.decision.headline = .notEntitled(.trialOver)
        XCTAssertEqual(MenuModel.attention(input)?.kind, .helperSwitchedOff)
        input.flagLeftOn = false
        XCTAssertEqual(MenuModel.attention(input)?.kind, .license)
        input.entitlement = .trial(daysLeft: 6)
        XCTAssertEqual(MenuModel.attention(input)?.kind, .lidClosedNotSetUp)
    }

    func testLidClosedNeedsSetupOnlyWhereItCanMatter() {
        for helper in [HelperStatus.notRegistered, .requiresApproval, .notFound] {
            XCTAssertTrue(MenuModel.lidClosedNeedsSetup(helper: helper, wanted: true, hasBattery: true))
            XCTAssertFalse(MenuModel.lidClosedNeedsSetup(helper: helper, wanted: false, hasBattery: true), "The user switched it off")
            XCTAssertFalse(MenuModel.lidClosedNeedsSetup(helper: helper, wanted: true, hasBattery: false), "No battery")
        }
        XCTAssertFalse(MenuModel.lidClosedNeedsSetup(helper: .enabled, wanted: true, hasBattery: true))
    }

    func testLicenseItemsOfTheGearMenu() {
        var input = input(.noAgents)
        XCTAssertEqual(MenuModel.state(input, now: now).licenseActions, [])
        input.entitlement = .trial(daysLeft: 6)
        XCTAssertEqual(MenuModel.state(input, now: now).licenseActions, [.buy, .enterKey])
        input.entitlement = .expired(.activationRemoved)
        input.hasLicenseKey = true
        XCTAssertEqual(MenuModel.state(input, now: now).licenseActions, [.enterKey])
    }

    func testActionTitles() {
        let titles: [(PanelAction, String)] = [
            (.openLoginItems, "Open System Settings"), (.buy, "Buy for $9"), (.enterKey, "Enter key…"),
            (.checkLicense, "Check now"), (.activateAgain, "Activate again"), (.setUpLidClosed, "Set up…"),
            (.dismissLidClosedHint, "Dismiss"),
        ]
        for (action, title) in titles { XCTAssertEqual(action.title, title) }
    }

    // MARK: Rows

    func testNoAgentsGiveTheEmptyLine() {
        let state = MenuModel.state(input(.noAgents), now: now)
        XCTAssertEqual(state.rows, [])
        XCTAssertEqual(state.emptyText, "Start an agent and agent caffeine keeps your Mac awake while it works")
        XCTAssertNil(MenuModel.state(input(.idle(.one("Codex")), [hold("codex", "Codex", pid: 1, .idle, .atPrompt)]), now: now).emptyText)
        var always = input(.alwaysOn)
        always.mode = .always
        XCTAssertEqual(MenuModel.state(always, now: now).emptyText, "No agent is open")
    }

    func testModeTitles() {
        XCTAssertEqual(AwakeMode.allCases.map(\.title), ["Always", "While an agent is open", "While an agent is working"])
        XCTAssertEqual(AwakeMode.allCases.map(\.shortTitle), ["Always", "While open", "While working"])
    }

    func testWorkingComesFirstTheLongestOnTopThenWaitingThenIdle() {
        let perAgent = [
            claude(pid: 1, .idle),
            claude(pid: 2, .waitingForUser, .asksPermission),
            claude(pid: 3, .working, .runningCommand(3)),
            claude(pid: 4, .idle),
            claude(pid: 5, .working, .reportsBusy),
            hold("codex", "Codex", pid: 6, .working, .backgroundJob(1)),
            hold("opencode", "opencode", pid: 7, .working, .cpuActivity),
        ]
        var input = input(.working(.many(4)), perAgent)
        input.labels = [identity(3): "site", identity(5): "wiki", identity(2): "notes"]
        input.clock = clock(perAgent, secondsAgo: [3: 3 * 60, 5: 12 * 60, 6: 20, 2: 3 * 60, 7: 95 * 60])
        let (rows, more) = MenuModel.rows(input, now: now)
        XCTAssertEqual(more, [])
        XCTAssertEqual(rows.map(\.title), ["opencode", "Claude Code · wiki", "Claude Code · site", "Codex", "Claude Code · notes", "Claude Code"])
        XCTAssertEqual(rows.map(\.state), [.working, .working, .working, .working, .waiting, .idle])
        XCTAssertEqual(rows.map(\.detail), [
            "Working · 1 hour", "Working · 12 minutes", "Running 3 commands · 3 minutes", "Running 1 background task · a moment",
            "Waits for your answer · 3 minutes", "2 idle sessions",
        ])
        XCTAssertEqual(rows.map(\.accessibilityLabel), [
            "opencode, working, 1 hour", "Claude Code, wiki, working, 12 minutes", "Claude Code, site, running 3 commands, 3 minutes",
            "Codex, running 1 background task, a moment", "Claude Code, notes, waits for your answer, 3 minutes", "Claude Code, 2 idle sessions",
        ])
        XCTAssertEqual(rows[2].hint, "Running 3 commands")
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testAnAgentWithNoKnownStartHasNoDuration() {
        let state = MenuModel.state(input(.working(.one("Claude Code")), [claude(pid: 1, .working, .reportsBusy)]), now: now)
        XCTAssertEqual(state.rows.map(\.detail), ["Working"])
    }

    func testRulesAreNamedQuietly() {
        let perAgent = [
            hold("goose", "Goose", pid: 1, .working, .alwaysWorkingByRule),
            hold("amp", "Amp", pid: 2, .idle, .ignoredByRule),
            hold("codex", "Codex", pid: 3, .idle, .atPrompt),
        ]
        var input = input(.working(.one("Goose")), perAgent)
        input.clock = clock(perAgent, secondsAgo: [1: 600, 2: 600, 3: 7200])
        let rows = MenuModel.rows(input, now: now).inView
        XCTAssertEqual(rows.map(\.title), ["Goose", "Codex", "Amp"], "An ignored agent is last")
        XCTAssertEqual(rows.map(\.detail), ["Counts as working while it is open", "Idle 2 hours", "Ignored"])
    }

    func testIdleTimeComesFromTheVerdictWhenItKnowsMore() {
        let perAgent = [
            hold("opencode", "opencode", pid: 1, .idle, .noActivity(minutes: 395)),
            hold("codex", "Codex", pid: 2, .idle, .atPrompt),
            hold("amp", "Amp", pid: 3, .idle, .noActivity(minutes: 0)),
        ]
        var input = input(.idle(.many(3)), perAgent)
        input.clock = clock(perAgent, secondsAgo: [1: 30, 2: 30, 3: 30])
        let rows = MenuModel.rows(input, now: now).inView
        XCTAssertEqual(rows.map(\.title), ["Codex", "Amp", "opencode"], "The one that was active last is on top")
        XCTAssertEqual(rows.map(\.detail), ["Idle", "Idle", "Idle 6 hours"])
        XCTAssertEqual(rows[2].hint, "No activity for 6 hours")
        XCTAssertEqual(rows[2].accessibilityLabel, "opencode, idle, 6 hours")
    }

    func testManyIdleSessionsShareOneLineAndTheRestGoesBehindMoreIdle() {
        let names = [("codex", "Codex"), ("opencode", "opencode"), ("amp", "Amp"), ("goose", "Goose"), ("pi", "Pi"), ("grok", "Grok")]
        var perAgent = (1...8).map { claude(pid: $0, .idle) }
        perAgent += names.enumerated().map { hold($1.0, $1.1, pid: Int32(20 + $0), .idle, .atPrompt) }
        var input = input(.idle(.many(14)), perAgent)
        // Claude Code went idle last, then the others in their order.
        var ages = Dictionary(uniqueKeysWithValues: (20...25).map { (Int32($0), TimeInterval($0) * 600) })
        ages[4] = 120
        input.clock = clock(perAgent, secondsAgo: ages)
        let state = MenuModel.state(input, now: now)
        XCTAssertEqual(state.rows.map(\.title), ["Claude Code", "Codex", "opencode"])
        XCTAssertEqual(state.rows.map(\.detail), ["8 idle sessions", "Idle 3 hours", "Idle 3 hours"])
        XCTAssertEqual(state.moreIdle.map(\.title), ["Amp", "Goose", "Pi", "Grok"])
        XCTAssertEqual(state.moreIdleTitle, "4 more idle")
        XCTAssertEqual(Set((state.rows + state.moreIdle).map(\.id)).count, 7)
    }

    func testOneMoreIdleAgentIsShownInsteadOfHidden() {
        let names = [("codex", "Codex"), ("opencode", "opencode"), ("amp", "Amp"), ("goose", "Goose")]
        let perAgent = names.enumerated().map { hold($1.0, $1.1, pid: Int32($0), .idle, .atPrompt) }
        let state = MenuModel.state(input(.idle(.many(4)), perAgent), now: now)
        XCTAssertEqual(state.rows.count, 4)
        XCTAssertNil(state.moreIdleTitle)
    }

    func testAgentsWithTheSameNameStayApart() {
        let rows = MenuModel.rows(input(.idle(.many(3)), [
            hold("codex", "Codex", pid: 1, .idle, .atPrompt),
            hold("codex-desktop", "Codex", pid: 2, .idle, .atPrompt),
            hold("codex", "Codex", pid: 3, .idle, .atPrompt),
        ]), now: now).inView
        XCTAssertEqual(rows.map(\.detail), ["2 idle sessions", "Idle"])
    }

    func testSessionLabelIsTheFolderName() {
        XCTAssertEqual(MenuModel.sessionLabel(workingDirectory: "/Users/me/code/website"), "website")
        XCTAssertEqual(MenuModel.sessionLabel(workingDirectory: "/Users/me/code/website/"), "website")
        XCTAssertNil(MenuModel.sessionLabel(workingDirectory: "/"))
        XCTAssertNil(MenuModel.sessionLabel(workingDirectory: nil))
    }

    // MARK: Clock

    func testTheClockCountsFromTheChangeOfState() {
        let working = claude(pid: 1, .working, .reportsBusy).reading
        let commands = claude(pid: 1, .working, .runningCommand(2)).reading
        let idle = claude(pid: 1, .idle).reading
        let start = now.addingTimeInterval(-600)
        var clock = StateClock().updated(with: [working], now: start)
        clock = clock.updated(with: [commands], now: start.addingTimeInterval(60))
        XCTAssertEqual(clock.since(identity(1)), start, "Another reason is the same state")
        clock = clock.updated(with: [idle], now: start.addingTimeInterval(120))
        XCTAssertEqual(clock.since(identity(1)), start.addingTimeInterval(120))
        clock = clock.updated(with: [], now: now)
        XCTAssertNil(clock.since(identity(1)), "An instance that is gone is forgotten")
    }
}
