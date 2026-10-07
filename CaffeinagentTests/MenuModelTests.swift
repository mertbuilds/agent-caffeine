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
            (.waitingHeld(.one("Codex")), awake, "Codex is waiting for you"),
            (.waitingHeld(.many(2)), awake, "2 agents are waiting for you"),
            (.finishedRecently(.one("Claude Code")), awake, "Claude Code finished a moment ago"),
            (.finishedRecently(.many(3)), awake, "3 agents finished a moment ago"),
            (.open(.one("opencode")), awake, "opencode is open"),
            (.open(.many(4)), awake, "4 agents are open"),
            (.alwaysOn, awake, "Until you switch it off"),
            (.remoteAccess, awake, "Phone access is on"),
            (.reachable(until: now.addingTimeInterval(3600)), awake, "Reachable until \(PanelText.time(now.addingTimeInterval(3600)))"),
            (.idle(.one("Codex")), canSleep, "Codex is idle"),
            (.idle(.many(5)), canSleep, "All agents are idle"),
            (.waitingReleased(.one("Codex")), canSleep, "Codex is waiting for your answer"),
            (.waitingReleased(.many(2)), canSleep, "2 agents are waiting for your answer"),
            (.noAgents, canSleep, "No agent is open"),
            (.safetyStop(.batteryLow(percent: 20)), canSleep, "The battery is at 20%"),
            (.safetyStop(.tooHot), canSleep, "Your Mac got too hot"),
            (.switchedOff, "agent caffeine is off", "Your Mac sleeps as usual"),
            (.notEntitled(.trialOver), canSleep, "Your trial has ended"),
            (.notEntitled(.unverified), canSleep, "Your license was not checked for 30 days"),
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
            (0, "Codex is waiting for you, can sleep in 5 minutes"),
            (61, "Codex is waiting for you, can sleep in 4 minutes"),
            (120, "Codex is waiting for you, can sleep in 3 minutes"),
            (241, "Codex is waiting for you, can sleep in 1 minute"),
            (299, "Codex is waiting for you, can sleep in 1 minute"),
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
        XCTAssertEqual(MenuModel.state(input, now: now).subtitle, "2 agents are waiting for you, can sleep in 5 minutes")
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
            (.reachable(until: now), .reachable),
            (.waitingHeld(.one("Codex")), .attentive),
            (.idle(.many(3)), .asleep),
            (.waitingReleased(.one("Codex")), .asleep),
            (.noAgents, .asleep),
            (.switchedOff, .off),
            (.paused(until: now), .paused),
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

    /// The Mac still stays awake with the lid open, so the robot and the
    /// headline stay as they are. Only the line below says it.
    func testAHelperThatGivesNoAnswerKeepsTheRobotAndTheHeadline() {
        for headline in [HoldHeadline.working(.one("Claude Code")), .working(.many(3)), .alwaysOn, .noAgents] {
            let plain = MenuModel.state(input(headline), now: now)
            var silent = input(headline)
            silent.helperNotResponding = true
            let state = MenuModel.state(silent, now: now)
            XCTAssertEqual(state.pose, plain.pose, "\(headline)")
            XCTAssertEqual(state.title, plain.title, "\(headline)")
            XCTAssertEqual(state.subtitle, plain.subtitle, "\(headline)")
            XCTAssertEqual(state.attention?.kind, .helperNotResponding, "\(headline)")
        }
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

    // MARK: Pause

    private func pausedInput(until: Date, locale: String = "en_GB") -> PanelInput {
        var input = input(.paused(until: until), [claude(pid: 1, .working, .reportsBusy)])
        input.pausedUntil = until
        input.calendar = Calendar(identifier: .gregorian)
        input.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        input.locale = Locale(identifier: locale)
        return input
    }

    /// `now` is 13:46 on a day in 1970, in the time zone of the test.
    func testThePausedHeadlineSaysWhenItStartsAgain() {
        let today = MenuModel.state(pausedInput(until: now.addingTimeInterval(104 * 60)), now: now)
        XCTAssertEqual(today.pose, .paused)
        XCTAssertEqual(today.title, "agent caffeine is paused")
        XCTAssertEqual(today.subtitle, "Starts again at 15:30")
        XCTAssertEqual(today.pausedLabel, "Paused until 15:30")
        XCTAssertNil(today.attention)
        // The agents keep their own states.
        XCTAssertEqual(today.groups.map(\.header.state), [.working])

        let tomorrow = MenuModel.state(pausedInput(until: now.addingTimeInterval((16 * 60 + 14) * 60)), now: now)
        XCTAssertEqual(tomorrow.subtitle, "Starts again tomorrow at 06:00")
        XCTAssertEqual(tomorrow.pausedLabel, "Paused until 06:00")
        for text in [today.title, today.subtitle, tomorrow.subtitle, today.pausedLabel ?? ""] {
            XCTAssertFalse(text.hasSuffix("."), text)
        }
    }

    func testTheTimeFollowsTheClockOfTheUser() {
        let until = now.addingTimeInterval(104 * 60)
        func plain(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{202F}", with: " ") }
        let twelve = MenuModel.state(pausedInput(until: until, locale: "en_US"), now: now)
        XCTAssertEqual(plain(twelve.subtitle), "Starts again at 3:30 PM")
        XCTAssertEqual(plain(twelve.pausedLabel), "Paused until 3:30 PM")
        XCTAssertEqual(MenuModel.state(pausedInput(until: until, locale: "de_DE"), now: now).pausedLabel, "Paused until 15:30")
    }

    func testOnlyAPauseHasThePausedLabel() {
        XCTAssertNil(MenuModel.state(input(.switchedOff), now: now).pausedLabel)
        XCTAssertNil(MenuModel.state(input(.working(.one("Claude Code"))), now: now).pausedLabel)
        // A safety stop takes the headline. The bar still offers to resume.
        var stopped = pausedInput(until: now.addingTimeInterval(600))
        stopped.decision.headline = .safetyStop(.tooHot)
        let state = MenuModel.state(stopped, now: now)
        XCTAssertEqual(state.title, "Your Mac can sleep")
        XCTAssertEqual(state.pausedLabel, "Paused until 13:56")
    }

    // MARK: Stay reachable

    private func reachableInput(until: Date, _ perAgent: [AgentHold] = [], locale: String = "en_GB") -> PanelInput {
        var input = input(.reachable(until: until), perAgent)
        input.reachableUntil = until
        input.calendar = Calendar(identifier: .gregorian)
        input.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        input.locale = Locale(identifier: locale)
        return input
    }

    /// `now` is 13:46 on a day in 1970, in the time zone of the test.
    func testTheReachableHeadlineSaysUntilWhen() {
        let state = MenuModel.state(reachableInput(until: now.addingTimeInterval(284 * 60)), now: now)
        XCTAssertEqual(state.pose, .reachable)
        XCTAssertEqual(state.title, "Your Mac stays awake")
        XCTAssertEqual(state.subtitle, "Reachable until 18:30")
        XCTAssertEqual(state.reachableLabel, "Reachable until 18:30")
        XCTAssertEqual(state.menuBarAccessibilityLabel, "agent caffeine, reachable until 18:30")
        XCTAssertNil(state.pausedLabel)
        XCTAssertNil(state.attention)
        func plain(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{202F}", with: " ") }
        let twelve = MenuModel.state(reachableInput(until: now.addingTimeInterval(284 * 60), locale: "en_US"), now: now)
        XCTAssertEqual(plain(twelve.subtitle), "Reachable until 6:30 PM")
        // Over midnight the time alone says it.
        XCTAssertEqual(MenuModel.state(reachableInput(until: now.addingTimeInterval(13 * 3600)), now: now).subtitle, "Reachable until 02:46")
    }

    func testAnAgentAtWorkKeepsItsHeadlineWhileTheBarSaysReachable() {
        var input = reachableInput(until: now.addingTimeInterval(284 * 60), [claude(pid: 1, .working, .reportsBusy)])
        input.decision.headline = .working(.one("Claude Code"))
        let state = MenuModel.state(input, now: now)
        XCTAssertEqual(state.subtitle, "Claude Code is working")
        XCTAssertEqual(state.pose, .awake(wisps: 2))
        XCTAssertEqual(state.reachableLabel, "Reachable until 18:30")
        XCTAssertNil(state.menuBarAccessibilityLabel, "The pose says it")
    }

    func testOnlyStayReachableHasItsLabel() {
        XCTAssertNil(MenuModel.state(input(.working(.one("Claude Code"))), now: now).reachableLabel)
        XCTAssertNil(MenuModel.state(input(.noAgents), now: now).menuBarAccessibilityLabel)
    }

    func testTheReachableActionsReadAsWholePhrases() {
        XCTAssertEqual(
            ReachableChoice.allCases.map { PanelAction.stayReachable($0).title },
            ["Stay reachable for 1 hour", "Stay reachable for 2 hours", "Stay reachable for 4 hours"]
        )
        XCTAssertEqual(PanelAction.stopReachable.title, "Stop")
        XCTAssertEqual(MenuModel.state(input(.noAgents), now: now).reachableActions, ReachableChoice.allCases.map(PanelAction.stayReachable))
    }

    func testStayReachableIsOfferedOnlyWhileAgentCaffeineCouldHold() {
        var off = input(.switchedOff)
        off.enabled = false
        XCTAssertEqual(MenuModel.state(off, now: now).reachableActions, [])
        var expired = input(.notEntitled(.trialOver))
        expired.entitlement = .expired(.trialOver)
        XCTAssertEqual(MenuModel.state(expired, now: now).reachableActions, [])
        XCTAssertEqual(MenuModel.state(input(.safetyStop(.batteryLow(percent: 20))), now: now).reachableActions, [])
        var trial = input(.noAgents)
        trial.entitlement = .trial(daysLeft: 5)
        XCTAssertEqual(MenuModel.state(trial, now: now).reachableActions.count, 3)
    }

    func testTheCostIsSaidOnBatteryOnly() {
        XCTAssertNil(MenuModel.state(input(.noAgents), now: now).reachableCost)
        var onBattery = input(.noAgents)
        onBattery.onBattery = true
        onBattery.batteryPercent = 80
        XCTAssertEqual(MenuModel.state(onBattery, now: now).reachableCost, "Uses about 1% of battery per hour")
    }

    func testOnBatteryWithoutTheHelperTheLineSaysTheLidStillSleeps() {
        var input = reachableInput(until: now.addingTimeInterval(3600))
        input.onBattery = true
        input.batteryPercent = 80
        input.lidClosedNeedsSetup = true
        input.lidClosedHintDismissed = true
        let attention = MenuModel.state(input, now: now).attention
        XCTAssertEqual(attention?.kind, .reachableNeedsLidClosed)
        XCTAssertEqual(attention?.text, "Close the lid and your Mac still sleeps. Set up lid closed to stay reachable")
        XCTAssertEqual(attention?.actions, [.setUpLidClosed])
        XCTAssertEqual(attention?.actions.map(\.title), ["Set up…"])
        // On wall power a closed lid does not put the Mac to sleep.
        input.onBattery = false
        XCTAssertNil(MenuModel.state(input, now: now).attention)
        // With the helper set up there is nothing to say.
        input.onBattery = true
        input.lidClosedNeedsSetup = false
        XCTAssertNil(MenuModel.state(input, now: now).attention)
        // Without "stay reachable" the old hint stands, and can be dismissed.
        input.lidClosedNeedsSetup = true
        input.reachableUntil = nil
        XCTAssertNil(MenuModel.state(input, now: now).attention)
        input.lidClosedHintDismissed = false
        XCTAssertEqual(MenuModel.state(input, now: now).attention?.kind, .lidClosedNotSetUp)
    }

    func testTheReachableRobotIsCalm() {
        let look = RobotLook(pose: .reachable)
        XCTAssertEqual(look.eyes, .happy)
        XCTAssertEqual(look.wisps, 1)
        XCTAssertEqual(look.antenna, .steady)
        XCTAssertTrue(look.blinks)
        XCTAssertEqual(MenuBarLook(pose: .reachable), MenuBarLook(eyes: .happy, solid: true), "The solid awake look")
    }

    func testThePauseActionsReadAsWholePhrases() {
        XCTAssertEqual(PauseChoice.allCases.map { PanelAction.pause($0).title }, ["Pause for 30 minutes", "Pause for 1 hour", "Pause until tomorrow"])
        XCTAssertEqual(PanelAction.resume.title, "Resume")
    }

    func testEveryRobotLook() {
        let awake = RobotLook(pose: .awake(wisps: 3))
        XCTAssertEqual([awake.eyes, RobotLook(pose: .attentive).eyes, RobotLook(pose: .asleep).eyes, RobotLook(pose: .off).eyes], [.happy, .open, .closed, .dim])
        XCTAssertEqual(awake.wisps, 3)
        XCTAssertEqual(RobotLook(pose: .attentive).antenna, .amber)
        XCTAssertTrue(RobotLook(pose: .asleep).snoozes)
        XCTAssertEqual(RobotLook(pose: .off).saturation, 0)
        // Only a robot that is awake steams, bobs and blinks.
        // A pause comes back by itself: the sleeping robot, not the grey one.
        XCTAssertEqual(RobotLook(pose: .paused), RobotLook(pose: .asleep))
        for pose in [HeroPose.asleep, .paused, .off, .safetyStop(.battery), .safetyStop(.heat), .helperOff] {
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
        XCTAssertEqual(MenuModel.attention(battery), PanelAttention(kind: .safetyStop, text: "agent caffeine starts again at 25%"))
        // The line of the battery says it when it is there, so the sentence comes once.
        battery.onBattery = true
        battery.batteryPercent = 18
        XCTAssertNil(MenuModel.attention(battery))
        XCTAssertEqual(MenuModel.battery(battery)?.consequence, "starts again at 25%")
        battery.lidClosedNeedsSetup = true
        XCTAssertEqual(MenuModel.attention(battery)?.kind, .lidClosedNotSetUp, "What else needs the user is still said")
        XCTAssertEqual(MenuModel.attention(input(.safetyStop(.tooHot))), PanelAttention(kind: .safetyStop, text: "agent caffeine starts again when it is cool"))

        var helper = input(.alwaysOn)
        helper.flagLeftOn = true
        XCTAssertEqual(MenuModel.attention(helper), PanelAttention(
            kind: .helperSwitchedOff,
            text: "Allow it again and your Mac sleeps as usual",
            actions: [.openLoginItems]
        ))

        var silent = input(.working(.one("Claude Code")))
        silent.helperNotResponding = true
        let cannotReach = "agent caffeine cannot reach its helper. Your Mac will sleep when you close the lid on battery"
        XCTAssertEqual(MenuModel.attention(silent), PanelAttention(kind: .helperNotResponding, text: cannotReach, actions: [.tryHelperAgain]))
        silent.helperRepairTried = true
        XCTAssertEqual(MenuModel.attention(silent), PanelAttention(
            kind: .helperNotResponding, text: cannotReach, actions: [.tryHelperAgain, .openLoginItems]
        ))
        silent.helperNotResponding = false
        XCTAssertNil(MenuModel.attention(silent), "A repair that helped leaves no line")

        var lid = input(.noAgents)
        lid.lidClosedNeedsSetup = true
        XCTAssertEqual(MenuModel.attention(lid), PanelAttention(
            kind: .lidClosedNotSetUp, text: "Your Mac still sleeps with the lid closed on battery", actions: [.setUpLidClosed, .dismissLidClosedHint]
        ))
    }

    func testLicenseAttention() {
        let cases: [(Entitlement, Bool, String, [PanelAction])] = [
            (.trial(daysLeft: 2), false, "Your trial ends in 2 days", [.buy]),
            (.trial(daysLeft: 1), false, "Your trial ends in 1 day", [.buy]),
            (.trial(daysLeft: 1), true, "Your trial ends in 1 day", [.enterKey]),
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
        input.helperNotResponding = true
        XCTAssertEqual(MenuModel.attention(input)?.kind, .helperNotResponding)
        input.helperNotResponding = false
        XCTAssertEqual(MenuModel.attention(input)?.kind, .license)
        input.entitlement = .trial(daysLeft: 6)
        XCTAssertEqual(MenuModel.attention(input)?.kind, .lidClosedNotSetUp)
    }

    func testLidClosedNeedsSetupOnlyWhereItCanMatter() {
        for setup in [HelperSetup.notSetUp, .requiresApproval] {
            XCTAssertTrue(MenuModel.lidClosedNeedsSetup(setup: setup, wasSetUp: false, wanted: true, hasBattery: true))
            XCTAssertFalse(MenuModel.lidClosedNeedsSetup(setup: setup, wasSetUp: false, wanted: false, hasBattery: true), "The user switched it off")
            XCTAssertFalse(MenuModel.lidClosedNeedsSetup(setup: setup, wasSetUp: false, wanted: true, hasBattery: false), "No battery")
        }
        for setup in [HelperSetup.ready, .repairing, .notResponding, .lost] {
            XCTAssertFalse(MenuModel.lidClosedNeedsSetup(setup: setup, wasSetUp: false, wanted: true, hasBattery: true), "\(setup)")
        }
    }

    func testAHelperThatWasSetUpBeforeNeverGetsTheHintOfTheFirstTime() {
        for setup in [HelperSetup.notSetUp, .requiresApproval, .ready, .repairing, .notResponding, .lost] {
            XCTAssertFalse(MenuModel.lidClosedNeedsSetup(setup: setup, wasSetUp: true, wanted: true, hasBattery: true), "\(setup)")
        }
        XCTAssertTrue(MenuModel.helperLost(setup: .lost, wasSetUp: true, wanted: true, hasBattery: true))
        XCTAssertTrue(MenuModel.helperLost(setup: .requiresApproval, wasSetUp: true, wanted: true, hasBattery: true))
        XCTAssertFalse(MenuModel.helperLost(setup: .requiresApproval, wasSetUp: false, wanted: true, hasBattery: true))
        XCTAssertFalse(MenuModel.helperLost(setup: .repairing, wasSetUp: true, wanted: true, hasBattery: true), "agent caffeine is still at it")
        XCTAssertFalse(MenuModel.helperLost(setup: .notResponding, wasSetUp: true, wanted: true, hasBattery: true))
        XCTAssertFalse(MenuModel.helperLost(setup: .lost, wasSetUp: true, wanted: false, hasBattery: true), "The user switched it off")
        XCTAssertFalse(MenuModel.helperLost(setup: .lost, wasSetUp: true, wanted: true, hasBattery: false), "No battery")

        var lost = input(.working(.one("Claude Code")))
        lost.helperLost = true
        lost.lidClosedHintDismissed = true
        XCTAssertEqual(MenuModel.attention(lost), PanelAttention(
            kind: .helperLost, text: "agent caffeine has to set up its helper again", actions: [.setUpLidClosed]
        ))
        XCTAssertEqual(PanelText.helperRepairing, "Setting up the helper again…")
    }

    func testAHelperThatGivesNoAnswerIsToldOnlyWhereItCanMatter() {
        XCTAssertTrue(MenuModel.helperNotResponding(notResponding: true, wanted: true, hasBattery: true))
        XCTAssertFalse(MenuModel.helperNotResponding(notResponding: false, wanted: true, hasBattery: true))
        XCTAssertFalse(MenuModel.helperNotResponding(notResponding: true, wanted: false, hasBattery: true), "The user switched it off")
        XCTAssertFalse(MenuModel.helperNotResponding(notResponding: true, wanted: true, hasBattery: false), "No battery")
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
            (.openLoginItems, "Open System Settings"), (.tryHelperAgain, "Try again"), (.buy, "Buy for $9"), (.enterKey, "Enter license key…"),
            (.checkLicense, "Check now"), (.activateAgain, "Activate again"), (.setUpLidClosed, "Set up…"),
            (.dismissLidClosedHint, "Dismiss"),
        ]
        for (action, title) in titles { XCTAssertEqual(action.title, title) }
    }

    // MARK: Groups

    private func headers(_ input: PanelInput) -> [PanelRow] {
        MenuModel.groups(input, now: now).inView.map(\.header)
    }

    func testNoAgentsGiveTheEmptyLine() {
        let state = MenuModel.state(input(.noAgents), now: now)
        XCTAssertEqual(state.groups, [])
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

    func testOneSessionIsTheHeaderItself() {
        let perAgent = [claude(pid: 1, .working, .runningCommand(3)), hold("codex", "Codex", pid: 2, .idle, .atPrompt)]
        var input = input(.working(.one("Claude Code")), perAgent)
        input.labels = [identity(1): "wiki"]
        input.hints = [identity(1): SessionHint(name: "wiki-6e", terminal: "ttys001")]
        input.clock = clock(perAgent, secondsAgo: [1: 3 * 60, 2: 6 * 60])
        let groups = MenuModel.groups(input, now: now).inView
        XCTAssertEqual(groups.map(\.id), ["claude", "codex"])
        XCTAssertEqual(groups.map(\.header.title), ["Claude Code · wiki", "Codex"])
        XCTAssertEqual(groups.map(\.header.detail), ["Running 3 commands for 3 minutes", "Idle for 6 minutes"])
        XCTAssertEqual(groups.map(\.header.state), [.working, .idle])
        XCTAssertEqual(groups.map(\.children), [[], []])
        XCTAssertEqual(groups.map(\.canToggle), [false, false])
        XCTAssertEqual(groups.map(\.accessibilityLabel), ["Claude Code, wiki, running 3 commands for 3 minutes", "Codex, idle for 6 minutes"])
        XCTAssertEqual(groups[0].header.hint, "Running 3 commands")
    }

    /// Three sessions of Claude Code at work and eight idle ones.
    func testSessionsOfOneAgentShareOneGroup() {
        var perAgent = (1...3).map { claude(pid: $0, .working, .reportsBusy) } + (4...11).map { claude(pid: $0, .idle) }
        perAgent += [hold("codex", "Codex", pid: 20, .idle, .atPrompt), hold("antigravity", "Antigravity", pid: 21, .idle, .noActivity(minutes: 13 * 60))]
        var input = input(.working(.many(3)), perAgent)
        input.labels = [identity(1): "wiki", identity(2): "wiki", identity(3): "wiki"]
        input.hints = [identity(1): SessionHint(name: "wiki-6e"), identity(2): SessionHint(name: "speaker-grille-spacing"), identity(3): SessionHint(name: "wiki-1d")]
        input.clock = clock(perAgent, secondsAgo: [1: 360, 2: 400, 3: 380, 20: 360])
        let state = MenuModel.state(input, now: now)
        XCTAssertEqual(state.moreIdle, [])
        XCTAssertEqual(state.groups.map(\.header.title), ["Claude Code", "Codex", "Antigravity"])
        XCTAssertEqual(state.groups.map(\.header.detail), ["3 working", "Idle for 6 minutes", "Idle for 13 hours"])
        let group = state.groups[0]
        XCTAssertEqual(group.header.state, .working)
        XCTAssertEqual(group.kind, .active)
        XCTAssertTrue(group.canToggle)
        XCTAssertTrue(group.opensByDefault)
        XCTAssertEqual(group.children.map(\.label), ["speaker-grille-spacing", "wiki-1d", "wiki-6e", "8 idle sessions"], "The longest at work on top")
        XCTAssertEqual(group.children.map(\.detail), ["Working for 6 minutes", "Working for 6 minutes", "Working for 6 minutes", nil])
        XCTAssertEqual(group.children[0].hint, "wiki · Working on a task")
        XCTAssertEqual(group.children[0].accessibilityLabel, "speaker-grille-spacing, working for 6 minutes")
        XCTAssertEqual(group.accessibilityLabel, "Claude Code, 3 working, 8 idle")
        XCTAssertEqual(Set(group.children.map(\.id)).count, 4)
        XCTAssertFalse(group.children.contains { $0.label.contains("Claude Code") }, "The name of the agent is in the header only")
    }

    func testWaitingSessionsComeBeforeWorkingOnes() {
        let perAgent = [
            claude(pid: 1, .working, .reportsBusy),
            claude(pid: 2, .waitingForUser, .asksPermission),
            claude(pid: 3, .working, .runningCommand(3)),
            claude(pid: 4, .idle),
        ]
        var input = input(.working(.many(2)), perAgent)
        input.labels = [identity(1): "wiki", identity(2): "notes", identity(3): "site"]
        input.clock = clock(perAgent, secondsAgo: [1: 3 * 60, 2: 30, 3: 12 * 60])
        let group = MenuModel.groups(input, now: now).inView[0]
        XCTAssertEqual(group.header.detail, "2 working, 1 waiting for you")
        XCTAssertEqual(group.header.state, .waiting, "The most urgent state is on the ring")
        XCTAssertEqual(group.children.map(\.label), ["notes", "site", "wiki", "1 idle session"])
        XCTAssertEqual(group.children.map(\.detail), ["Waiting for your answer", "Running 3 commands for 12 minutes", "Working for 3 minutes", nil])
        XCTAssertEqual(group.accessibilityLabel, "Claude Code, 2 working, 1 waiting for you, 1 idle")
    }

    func testAGroupOfIdleSessionsIsClosedAndListsThemWhenOpened() {
        let perAgent = (1...10).map { claude(pid: $0, .idle) }
        var input = input(.idle(.many(10)), perAgent)
        input.hints = Dictionary(uniqueKeysWithValues: (1...10).map { (identity(Int32($0)), SessionHint(terminal: "ttys\($0)")) })
        input.clock = clock(perAgent, secondsAgo: Dictionary(uniqueKeysWithValues: (1...10).map { (Int32($0), TimeInterval($0) * 600) }))
        let group = MenuModel.groups(input, now: now).inView[0]
        XCTAssertEqual(group.header.detail, "10 idle sessions")
        XCTAssertEqual(group.header.state, .idle)
        XCTAssertEqual(group.kind, .idle)
        XCTAssertFalse(group.opensByDefault)
        XCTAssertTrue(group.canToggle)
        XCTAssertFalse(GroupDisclosure().isOpen(group))
        XCTAssertEqual(group.children.map(\.label), ["ttys1", "ttys2", "ttys3", "ttys4", "ttys5", "ttys6", "and 4 more"], "The one that was active last on top")
        XCTAssertEqual(group.children.prefix(2).map(\.detail), ["Idle for 10 minutes", "Idle for 20 minutes"])
        XCTAssertNil(group.children[6].detail)
        XCTAssertEqual(group.accessibilityLabel, "Claude Code, 10 idle sessions")
    }

    func testGroupsWithAWaitingSessionComeFirstThenWorkingThenIdle() {
        let perAgent = [
            hold("amp", "Amp", pid: 1, .idle, .atPrompt),
            hold("amp", "Amp", pid: 2, .idle, .atPrompt),
            claude(pid: 3, .working, .reportsBusy),
            claude(pid: 4, .working, .reportsBusy),
            hold("codex", "Codex", pid: 5, .working, .backgroundJob(1)),
            hold("codex", "Codex", pid: 6, .waitingForUser, .asksPermission),
            hold("opencode", "opencode", pid: 7, .working, .cpuActivity),
            hold("goose", "Goose", pid: 8, .idle, .atPrompt),
            hold("pi", "Pi", pid: 9, .waitingForUser, .asksPermission),
        ]
        var input = input(.working(.many(4)), perAgent)
        input.clock = clock(perAgent, secondsAgo: [1: 900, 2: 7200, 3: 60, 4: 12 * 60, 5: 20, 6: 3 * 60, 7: 95 * 60, 8: 300, 9: 10 * 60])
        let (groups, more) = MenuModel.groups(input, now: now)
        XCTAssertEqual(more, [])
        XCTAssertEqual(groups.map(\.header.name), ["Pi", "Codex", "opencode", "Claude Code", "Goose", "Amp"])
        XCTAssertEqual(groups.map(\.header.state), [.waiting, .waiting, .working, .working, .idle, .idle])
        XCTAssertEqual(groups.map(\.header.detail), [
            "Waiting for your answer for 10 minutes", "1 working, 1 waiting for you", "Working for 1 hour 35 minutes", "2 working", "Idle for 5 minutes", "2 idle sessions",
        ])
        XCTAssertEqual(groups.map(\.opensByDefault), [true, true, true, true, false, false])
        XCTAssertEqual(groups.map(\.canToggle), [false, true, false, true, false, true])
        XCTAssertEqual(groups[1].children.map(\.detail), ["Waiting for your answer for 3 minutes", "Running 1 background task"])
        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)
    }

    func testAGroupKeepsItsIdentityWhenItsStateChanges() {
        let before = MenuModel.groups(input(.idle(.many(2)), [claude(pid: 1, .idle), claude(pid: 2, .idle)]), now: now).inView
        let after = MenuModel.groups(input(.working(.one("Claude Code")), [claude(pid: 1, .working, .reportsBusy), claude(pid: 2, .idle)]), now: now).inView
        XCTAssertEqual(before.map(\.id), after.map(\.id))
        XCTAssertEqual(before[0].kind, .idle)
        XCTAssertEqual(after[0].kind, .active)
        XCTAssertEqual(after[0].children.last?.label, "1 idle session")
    }

    func testSummariesAndPlurals() {
        XCTAssertEqual(PanelText.groupSummary(working: 3, waiting: 0, idle: 8), "3 working")
        XCTAssertEqual(PanelText.groupSummary(working: 1, waiting: 0, idle: 0), "1 working")
        XCTAssertEqual(PanelText.groupSummary(working: 0, waiting: 1, idle: 2), "1 waiting for you")
        XCTAssertEqual(PanelText.groupSummary(working: 2, waiting: 1, idle: 0), "2 working, 1 waiting for you")
        XCTAssertEqual(PanelText.groupSummary(working: 0, waiting: 0, idle: 8), "8 idle sessions")
        XCTAssertEqual(PanelText.groupSummary(working: 0, waiting: 0, idle: 1), "1 idle session")
        XCTAssertEqual(PanelText.groupSpoken(working: 3, waiting: 0, idle: 8), "3 working, 8 idle")
        XCTAssertEqual(PanelText.groupSpoken(working: 1, waiting: 2, idle: 0), "1 working, 2 waiting for you")
        XCTAssertEqual(PanelText.groupSpoken(working: 0, waiting: 0, idle: 2), "2 idle sessions")
        XCTAssertEqual(PanelText.idleSessions(1), "1 idle session")
        XCTAssertEqual(PanelText.idleSessions(7), "7 idle sessions")
        XCTAssertEqual(PanelText.moreIdle(3), "3 more idle agents")
        XCTAssertEqual(PanelText.moreIdle(1), "1 more idle agent")
        XCTAssertEqual(PanelText.andMore(4), "and 4 more")
    }

    func testAnAgentWithNoKnownStartHasNoDuration() {
        let state = MenuModel.state(input(.working(.one("Claude Code")), [claude(pid: 1, .working, .reportsBusy)]), now: now)
        XCTAssertEqual(state.groups.map(\.header.detail), ["Working"])
    }

    func testRulesAreNamedQuietly() {
        let perAgent = [
            hold("goose", "Goose", pid: 1, .working, .alwaysWorkingByRule),
            hold("amp", "Amp", pid: 2, .idle, .ignoredByRule),
            hold("amp", "Amp", pid: 4, .idle, .ignoredByRule),
            hold("codex", "Codex", pid: 3, .idle, .atPrompt),
        ]
        var input = input(.working(.one("Goose")), perAgent)
        input.clock = clock(perAgent, secondsAgo: [1: 600, 2: 600, 3: 7200, 4: 600])
        let groups = MenuModel.groups(input, now: now).inView
        XCTAssertEqual(groups.map(\.header.title), ["Goose", "Codex", "Amp"], "An ignored agent is last")
        XCTAssertEqual(groups.map(\.header.detail), ["Always counts as working", "Idle for 2 hours", "Ignored"])
        XCTAssertFalse(groups[2].canToggle, "Nothing to open below an agent that is ignored")
    }

    func testIdleTimeComesFromTheVerdictWhenItKnowsMore() {
        let perAgent = [
            hold("opencode", "opencode", pid: 1, .idle, .noActivity(minutes: 395)),
            hold("codex", "Codex", pid: 2, .idle, .atPrompt),
            hold("amp", "Amp", pid: 3, .idle, .noActivity(minutes: 0)),
        ]
        var input = input(.idle(.many(3)), perAgent)
        input.clock = clock(perAgent, secondsAgo: [1: 30, 2: 30, 3: 30])
        let rows = headers(input)
        XCTAssertEqual(rows.map(\.title), ["Codex", "Amp", "opencode"], "The one that was active last is on top")
        XCTAssertEqual(rows.map(\.detail), ["Idle", "Idle", "Idle for 6 hours 35 minutes"])
        XCTAssertEqual(rows[2].hint, "No activity for 6 hours 35 minutes")
        XCTAssertEqual(rows[2].accessibilityLabel, "opencode, idle for 6 hours 35 minutes")
    }

    func testIdleAgentsBeyondFourGoBehindMoreIdleAgents() {
        let names = [("codex", "Codex"), ("opencode", "opencode"), ("amp", "Amp"), ("goose", "Goose"), ("pi", "Pi"), ("grok", "Grok")]
        var perAgent = (1...8).map { claude(pid: $0, .idle) }
        perAgent += names.enumerated().map { hold($1.0, $1.1, pid: Int32(20 + $0), .idle, .atPrompt) }
        var input = input(.idle(.many(14)), perAgent)
        // Claude Code went idle last, then the others in their order.
        var ages = Dictionary(uniqueKeysWithValues: (20...25).map { (Int32($0), TimeInterval($0) * 600) })
        ages[4] = 120
        input.clock = clock(perAgent, secondsAgo: ages)
        let state = MenuModel.state(input, now: now)
        XCTAssertEqual(state.groups.map(\.header.title), ["Claude Code", "Codex", "opencode", "Amp"])
        XCTAssertEqual(state.groups.map(\.header.detail), ["8 idle sessions", "Idle for 3 hours 20 minutes", "Idle for 3 hours 30 minutes", "Idle for 3 hours 40 minutes"])
        XCTAssertEqual(state.moreIdle.map(\.header.title), ["Goose", "Pi", "Grok"])
        XCTAssertEqual(state.moreIdleTitle, "3 more idle agents")
        XCTAssertEqual(Set((state.groups + state.moreIdle).map(\.id)).count, 7)
    }

    func testOneMoreIdleAgentIsShownInsteadOfHidden() {
        let names = [("codex", "Codex"), ("opencode", "opencode"), ("amp", "Amp"), ("goose", "Goose"), ("pi", "Pi")]
        var perAgent = names.enumerated().map { hold($1.0, $1.1, pid: Int32($0), .idle, .atPrompt) }
        perAgent += [claude(pid: 10, .working, .reportsBusy), claude(pid: 11, .working, .reportsBusy)]
        let state = MenuModel.state(input(.working(.many(2)), perAgent), now: now)
        XCTAssertEqual(state.groups.count, 6, "Agents at work do not count")
        XCTAssertNil(state.moreIdleTitle)
    }

    func testAgentsWithTheSameNameStayApart() {
        let rows = headers(input(.idle(.many(3)), [
            hold("codex", "Codex", pid: 1, .idle, .atPrompt),
            hold("user:codex", "Codex", pid: 2, .idle, .atPrompt),
            hold("codex", "Codex", pid: 3, .idle, .atPrompt),
        ]))
        XCTAssertEqual(rows.map(\.detail), ["2 idle sessions", "Idle"])
    }

    func testADesktopAppNextToItsCommandLineToolSaysThatItIsTheApp() {
        func app(pid: Int32) -> AgentHold {
            AgentHold(reading: AgentReading(
                agentID: "codex-desktop", displayName: "Codex", level: .state, kind: .desktop, identity: identity(pid),
                verdict: AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt)
            ), cause: nil)
        }
        let both = headers(input(.idle(.many(2)), [hold("codex", "Codex", pid: 1, .idle, .atPrompt), app(pid: 2)]))
        XCTAssertEqual(both.map(\.title), ["Codex", "Codex app"])
        XCTAssertEqual(headers(input(.idle(.one("Codex")), [app(pid: 2)])).map(\.title), ["Codex"], "Alone it needs no other name")
    }

    func testSessionLabelIsTheFolderName() {
        XCTAssertEqual(MenuModel.sessionLabel(workingDirectory: "/Users/me/code/website"), "website")
        XCTAssertEqual(MenuModel.sessionLabel(workingDirectory: "/Users/me/code/website/"), "website")
        XCTAssertNil(MenuModel.sessionLabel(workingDirectory: "/"))
        XCTAssertNil(MenuModel.sessionLabel(workingDirectory: nil))
    }

    // MARK: Open and closed

    func testTheUsersChoiceHoldsWhileTheGroupStaysOfOneKind() {
        let working = MenuModel.groups(input(.working(.many(2)), [claude(pid: 1, .working, .reportsBusy), claude(pid: 2, .working, .reportsBusy)]), now: now).inView[0]
        let moreWork = MenuModel.groups(input(.working(.many(2)), [claude(pid: 1, .working, .reportsBusy), claude(pid: 2, .waitingForUser, .asksPermission), claude(pid: 3, .idle)]), now: now).inView[0]
        let idle = MenuModel.groups(input(.idle(.many(2)), [claude(pid: 1, .idle), claude(pid: 2, .idle)]), now: now).inView[0]
        var disclosure = GroupDisclosure()
        XCTAssertTrue(disclosure.isOpen(working))
        XCTAssertFalse(disclosure.isOpen(idle))

        disclosure.toggle(working)
        XCTAssertFalse(disclosure.isOpen(working))
        XCTAssertFalse(disclosure.settled(with: [moreWork]).isOpen(moreWork), "Another session that works or waits changes nothing")

        // All sessions went idle, then one works again.
        disclosure = disclosure.settled(with: [idle])
        XCTAssertFalse(disclosure.isOpen(idle))
        XCTAssertTrue(disclosure.settled(with: [working]).isOpen(working), "The choice went with the change of kind")

        disclosure.toggle(idle)
        XCTAssertTrue(disclosure.isOpen(idle))
        disclosure.toggle(idle)
        XCTAssertFalse(disclosure.isOpen(idle))
        disclosure.toggle(idle)
        XCTAssertTrue(disclosure.isOpen(working), "A choice for the idle group says nothing about the working one")
        XCTAssertEqual(disclosure.settled(with: []), GroupDisclosure(), "A group that is gone is forgotten")
    }

    func testAGroupOfOneSessionNeverOpens() {
        let single = MenuModel.groups(input(.working(.one("Claude Code")), [claude(pid: 1, .working, .reportsBusy)]), now: now).inView[0]
        var disclosure = GroupDisclosure()
        XCTAssertFalse(disclosure.isOpen(single))
        disclosure.toggle(single)
        XCTAssertEqual(disclosure, GroupDisclosure())
    }

    // MARK: First minute

    func testTheFirstMinuteSaysWhatJustHappened() {
        let (idle, busy, asks) = (claude(pid: 1, .idle).reading, claude(pid: 1, .working, .reportsBusy).reading, claude(pid: 1, .waitingForUser, .asksPermission).reading)
        func detail(_ steps: [(AgentReading, TimeInterval)]) -> String {
            var clock = StateClock()
            for (reading, secondsAgo) in steps { clock = clock.updated(with: [reading], now: now.addingTimeInterval(-secondsAgo)) }
            var input = input(.noAgents, [AgentHold(reading: steps[steps.count - 1].0, cause: nil)])
            input.clock = clock
            return headers(input)[0].detail
        }
        XCTAssertEqual(detail([(idle, 300), (busy, 20)]), "Started a moment ago")
        XCTAssertEqual(detail([(idle, 300), (busy, 60)]), "Working for 1 minute")
        XCTAssertEqual(detail([(busy, 20)]), "Working", "The app did not see the work begin")
        XCTAssertEqual(detail([(busy, 300), (asks, 59)]), "Asked you a moment ago")
        XCTAssertEqual(detail([(busy, 300), (asks, 180)]), "Waiting for your answer for 3 minutes")
        XCTAssertEqual(detail([(asks, 10)]), "Waiting for your answer")
        XCTAssertEqual(detail([(busy, 300), (idle, 30)]), "Finished a moment ago")
        XCTAssertEqual(detail([(busy, 300), (idle, 13 * 60)]), "Idle for 13 minutes")
        XCTAssertEqual(detail([(busy, 300), (idle, 2 * 24 * 3600)]), "Idle for 2 days")
        XCTAssertEqual(detail([(asks, 300), (idle, 30)]), "Idle", "It did not work before")
        XCTAssertEqual(detail([(idle, 30)]), "Idle")
    }

    func testACommandCountHasNoDurationInTheFirstMinute() {
        XCTAssertEqual(PanelText.working(.runningCommand(3), seconds: 20, startSeen: true), "Running 3 commands")
        XCTAssertEqual(PanelText.working(.runningCommand(1), seconds: 12 * 60, startSeen: true), "Running 1 command for 12 minutes")
        XCTAssertEqual(PanelText.working(.backgroundJob(1), seconds: 5 * 60, startSeen: false), "Running 1 background task for 5 minutes")
        XCTAssertEqual(PanelText.working(.alwaysWorkingByRule, seconds: 600, startSeen: true), "Always counts as working")
    }

    func testNoLineOfTheListIsABareDuration() {
        for (name, state) in PanelFixtures.all {
            for group in state.groups + state.moreIdle {
                for detail in [group.header.detail] + group.children.compactMap(\.detail) {
                    XCTAssertFalse(detail.contains("·"), detail)
                    XCTAssertFalse(detail.hasSuffix("."), detail)
                    if detail.contains("minute") || detail.contains("hour") || detail.contains("day") {
                        XCTAssertTrue(detail.contains(" for ") || detail.hasSuffix(" ago"), detail)
                    }
                }
                XCTAssertEqual(Set(group.children.map(\.label)).count, group.children.count, "\(name): two sessions read the same")
                XCTAssertEqual(Set(group.children.map(\.id)).count, group.children.count, name)
            }
            XCTAssertEqual(Set((state.groups + state.moreIdle).map(\.id)).count, state.groups.count + state.moreIdle.count, name)
        }
    }

    // MARK: Session names

    private func sameFolder(_ hints: [Int32: SessionHint], pids: [Int32] = [1, 2, 3]) -> PanelInput {
        var input = input(.working(.many(pids.count)), pids.map { claude(pid: $0, .working, .reportsBusy) })
        input.labels = Dictionary(uniqueKeysWithValues: pids.map { (identity($0), "wiki") })
        input.hints = Dictionary(uniqueKeysWithValues: hints.map { (identity($0.key), $0.value) })
        input.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return input
    }

    private func childLabels(_ input: PanelInput) -> [String] {
        MenuModel.groups(input, now: now).inView[0].children.map(\.label)
    }

    func testOneSessionKeepsItsPlainTitle() {
        let rows = headers(sameFolder([1: SessionHint(name: "wiki-1d", terminal: "ttys001")], pids: [1]))
        XCTAssertEqual(rows.map(\.title), ["Claude Code · wiki"])
        XCTAssertNil(rows[0].distinction)
    }

    func testASessionIsCalledByItsOwnNameThenItsFolder() {
        XCTAssertEqual(childLabels(sameFolder([
            1: SessionHint(name: "wiki-1d", terminal: "ttys001"),
            2: SessionHint(name: "speaker-grille-spacing", terminal: "ttys002"),
        ])), ["wiki-1d", "speaker-grille-spacing", "wiki"])
        let long = String(repeating: "a", count: 40)
        XCTAssertEqual(childLabels(sameFolder([1: SessionHint(name: long)], pids: [1, 2])), [long, "wiki"], "A long name stays whole: the menu cuts it at its end")
    }

    func testSessionsThatWouldReadTheSameGetTheirTerminalThenTheirStart() {
        XCTAssertEqual(childLabels(sameFolder([
            1: SessionHint(name: "same", terminal: "ttys004"),
            2: SessionHint(name: "same", terminal: "ttys005"),
        ])), ["same · ttys004", "same · ttys005", "wiki"])
        XCTAssertEqual(childLabels(sameFolder([1: SessionHint(terminal: "ttys004"), 2: SessionHint(terminal: "ttys005")], pids: [1, 2])), ["wiki · ttys004", "wiki · ttys005"])
        // Two sessions in one terminal name: only the start is left.
        XCTAssertEqual(childLabels(sameFolder([1: SessionHint(terminal: "ttys004"), 2: SessionHint(terminal: "ttys004")], pids: [1, 2])), ["wiki · since 00:00", "wiki · since 00:00"])
    }

    func testWithoutANameOrAFolderTheTerminalThenTheStartNamesASession() {
        var input = input(.idle(.many(3)), [claude(pid: 1, .idle), claude(pid: 2, .idle), claude(pid: 3, .idle)])
        input.hints = [identity(1): SessionHint(terminal: "ttys004"), identity(2): SessionHint(terminal: "ttys004")]
        input.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(childLabels(input), ["ttys004 · since 00:00", "ttys004 · since 00:00", "since 00:00"])
    }

    func testAFolderThatOnlyBeginsLikeTheNameStays() {
        var row = PanelRow(id: "1", agentID: "claude", name: "Claude Code", label: "a", distinction: "about-page", state: .working, detail: "Working", hint: "")
        XCTAssertEqual(row.title, "Claude Code · a · about-page")
        row.label = "about"
        XCTAssertEqual(row.title, "Claude Code · about-page")
        row.distinction = "about"
        XCTAssertEqual(row.title, "Claude Code · about")
    }

    func testIdleAgentsWithTheSameNameAreToldApart() {
        var input = input(.idle(.many(2)), [
            hold("codex", "Codex", pid: 1, .idle, .atPrompt),
            hold("user:codex", "Codex", pid: 2, .idle, .atPrompt),
        ])
        input.hints = [identity(1): SessionHint(terminal: "ttys009")]
        input.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(headers(input).map(\.title), ["Codex · ttys009", "Codex · since 00:00"])
    }

    func testASessionHintPrintsNothing() {
        let hint = SessionHint(name: "secret plan", terminal: "ttys001")
        XCTAssertFalse("\(hint)".contains("secret"))
        XCTAssertFalse(String(reflecting: hint).contains("secret"))
        XCTAssertEqual(SessionHint.cleaned(name: "  fix\n the   bug "), "fix the bug")
        XCTAssertNil(SessionHint.cleaned(name: " \n"))
        XCTAssertNil(SessionHint.cleaned(name: nil))
        XCTAssertEqual(SessionHint.cleaned(name: String(repeating: "a", count: 200))?.count, SessionHint.nameLimit)
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
        XCTAssertNil(clock.before(identity(1)), "First seen in this state")
        clock = clock.updated(with: [idle], now: start.addingTimeInterval(120))
        XCTAssertEqual(clock.since(identity(1)), start.addingTimeInterval(120))
        XCTAssertEqual(clock.before(identity(1)), .working)
        clock = clock.updated(with: [], now: now)
        XCTAssertNil(clock.since(identity(1)), "An instance that is gone is forgotten")
    }
}
