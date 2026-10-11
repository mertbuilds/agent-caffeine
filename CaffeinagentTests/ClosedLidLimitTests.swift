import XCTest

/// The last stop for a closed lid on battery: `ClosedLidLimit`, with the
/// policy, the texts, the settings and the replay.
final class ClosedLidLimitTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)
    private static let hour: TimeInterval = 3600
    /// Below `SampleGap.threshold`, so two samples have no hole between them.
    private static let step: TimeInterval = 10

    private static func reading(_ state: WorkState, name: String = "Claude Code", pid: Int32 = 1) -> AgentReading {
        AgentReading(
            agentID: "claude", displayName: name, level: .state, identity: ProcessIdentity(pid: pid, startTime: 1),
            verdict: AgentVerdict(state: state, confidence: .reported, reason: state == .working ? .reportsBusy : .atPrompt)
        )
    }

    /// A Mac that is sampled every 10 seconds, as the app does it: the
    /// limit sees the hold of the sample before, and the policy decides
    /// with the stop.
    private struct Mac {
        var limit = ClosedLidLimit()
        var settings = DetectionSettings()
        var context = FrameContext(onBattery: true, batteryPercent: 90, lidClosed: true)
        var readings = [ClosedLidLimitTests.reading(.working)]
        var holds: [ManualHold] = []
        var jobHolds: [JobHold] = []
        var reachableUntil: Date?
        var enabled = true
        /// A stop of `SafetyMonitor`. It comes first.
        var otherStop: SafetyStop?
        /// The battery loses this many points in an hour of awake time.
        var drainPerHour = 0.0

        private(set) var decision: HoldDecision?
        /// Seconds the Mac was awake, and seconds on the clock.
        private(set) var awake: TimeInterval = 0
        private(set) var wall: TimeInterval = 0
        private var memory = PolicyMemory()
        private var previous: SampleTime?
        private var startPercent: Int?

        var held: Bool { decision?.hold ?? false }
        var now: Date { ClosedLidLimitTests.start.addingTimeInterval(wall) }

        /// The Mac sleeps for this long. No sample is taken.
        mutating func sleep(_ seconds: TimeInterval) {
            wall += seconds
        }

        @discardableResult
        mutating func sample() -> HoldDecision {
            awake += ClosedLidLimitTests.step
            wall += ClosedLidLimitTests.step
            if drainPerHour > 0, let percent = startPercent ?? context.batteryPercent {
                startPercent = percent
                context.batteryPercent = percent - Int(awake / ClosedLidLimitTests.hour * drainPerHour)
            }
            let time = SampleTime(at: now, awake: awake)
            let gap = SampleGap.length(from: previous, to: time)
            if let gap { memory = memory.shifted(by: gap) }
            previous = time
            let lidStop = limit.update(context, holding: held, at: time, afterGap: gap != nil)
            let (next, nextMemory) = HoldPolicy.decide(
                readings: readings, memory: memory, mode: .agentWorking, enabled: enabled, reachableUntil: reachableUntil, holds: holds,
                jobHolds: jobHolds, entitlement: .licensed, safety: otherStop ?? lidStop.map(SafetyStop.closedLid), settings: settings,
                context: context, now: now
            )
            memory = nextMemory
            decision = next
            return next
        }

        /// Samples for this long of awake time.
        mutating func run(_ seconds: TimeInterval) {
            for _ in 0..<Int(seconds / ClosedLidLimitTests.step) { sample() }
        }

        /// Samples until the hold ends, for 14 hours at most.
        /// - Returns: the awake seconds at the first sample without a hold.
        mutating func runUntilReleased() -> TimeInterval? {
            for _ in 0..<Int(14 * ClosedLidLimitTests.hour / ClosedLidLimitTests.step) where !sample().hold { return awake }
            return nil
        }
    }

    private func assertStopped(_ mac: Mac, _ stop: ClosedLidStop, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(mac.decision?.headline, .safetyStop(.closedLid(stop)), file: file, line: line)
        XCTAssertEqual(mac.decision?.hold, false, file: file, line: line)
        XCTAssertEqual(mac.decision?.lidClosedFlag, false, "The sleep flag goes off with the hold", file: file, line: line)
    }

    // MARK: The two limits

    func testAHoldEndsAtTheTimeLimit() throws {
        var mac = Mac()
        let released = try XCTUnwrap(mac.runUntilReleased())
        XCTAssertEqual(released, 3 * Self.hour, accuracy: 30)
        assertStopped(mac, .time(seconds: 3 * Self.hour))
        XCTAssertEqual(mac.limit.period?.percentAtStart, 90)
    }

    func testAHoldEndsWhenTheBatteryLostTheDropLimit() throws {
        var mac = Mac()
        mac.drainPerHour = 20
        let released = try XCTUnwrap(mac.runUntilReleased())
        XCTAssertEqual(released, 1.5 * Self.hour, accuracy: 30, "30 points at 20 points in an hour")
        assertStopped(mac, .drop(points: 30))
        XCTAssertEqual(mac.context.batteryPercent, 60)
    }

    func testOnPowerAndWithTheLidOpenThereIsNoLimit() {
        let free = [
            FrameContext(onBattery: false, batteryPercent: 90, lidClosed: true),
            FrameContext(onBattery: true, batteryPercent: 90, lidClosed: false),
            FrameContext(onBattery: false, batteryPercent: 90, lidClosed: false),
        ]
        for context in free {
            var mac = Mac()
            mac.context = context
            XCTAssertNil(mac.runUntilReleased(), "\(context)")
            XCTAssertNil(mac.limit.period, "\(context)")
        }
    }

    func testEachLimitCanBeSwitchedOff() throws {
        var noTime = DetectionSettings()
        noTime.closedLidLimitHours = ClosedLidLimit.noLimit
        XCTAssertNil(noTime.closedLidLimits().time)
        XCTAssertEqual(noTime.closedLidLimits().drop, 30)
        var mac = Mac()
        (mac.limit.timeLimit, mac.limit.dropLimit) = noTime.closedLidLimits()
        XCTAssertNil(mac.runUntilReleased(), "No time limit, and the battery does not fall")
        mac.drainPerHour = 20
        XCTAssertNotNil(mac.runUntilReleased(), "The drop limit still counts")
        assertStopped(mac, .drop(points: 30))

        var noDrop = DetectionSettings()
        noDrop.closedLidLimitDrop = ClosedLidLimit.noLimit
        XCTAssertNil(noDrop.closedLidLimits().drop)
        XCTAssertEqual(noDrop.closedLidLimits().time, 3 * Self.hour)
        mac = Mac()
        (mac.limit.timeLimit, mac.limit.dropLimit) = noDrop.closedLidLimits()
        mac.drainPerHour = 25
        XCTAssertEqual(try XCTUnwrap(mac.runUntilReleased()), 3 * Self.hour, accuracy: 30)
        assertStopped(mac, .time(seconds: 3 * Self.hour))

        mac = Mac()
        (mac.limit.timeLimit, mac.limit.dropLimit) = (nil, nil)
        mac.drainPerHour = 5
        XCTAssertNil(mac.runUntilReleased(), "With both off nothing stops but the other stops")
        XCTAssertNotNil(mac.limit.period, "The period is still counted")
    }

    func testTheLimitsOfTheSettings() {
        XCTAssertEqual(DetectionSettings().closedLidLimits().time, 3 * Self.hour)
        XCTAssertEqual(DetectionSettings().closedLidLimits().drop, 30)
        var settings = DetectionSettings()
        settings.closedLidLimitHours = 12
        settings.closedLidLimitDrop = 15
        XCTAssertEqual(settings.closedLidLimits().time, 12 * Self.hour)
        XCTAssertEqual(settings.closedLidLimits().drop, 15)
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 120).time, 120, "The hidden default of the tests")
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 0).time, 12 * Self.hour)
        XCTAssertEqual(settings.closedLidLimits(testSeconds: -5).time, 12 * Self.hour)
        settings.closedLidLimitHours = ClosedLidLimit.noLimit
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 120).time, 120)
    }

    /// A value that is too large must not take the last stop away.
    func testTheHiddenDefaultOfTheTestsCannotMakeTheLimitLonger() {
        var settings = DetectionSettings()
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 1e9).time, 3 * Self.hour)
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 3 * Self.hour + 1).time, 3 * Self.hour)
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 3 * Self.hour - 1).time, 3 * Self.hour - 1)
        settings.closedLidLimitHours = 1
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 2 * Self.hour).time, Self.hour)
        XCTAssertEqual(settings.closedLidLimits(testSeconds: 1e9).drop, 30, "The drop limit is as the settings have it")
    }

    /// A value that an aborted test left in place does nothing in a build
    /// that is not under test.
    func testTheHiddenDefaultOfTheTestsCountsOnlyWhileTheSwitchOfTheTestsIsOn() {
        let defaults = TestDefaults()
        XCTAssertEqual(ClosedLidLimit.testSeconds(in: defaults), 0)
        defaults.set(180, forKey: ClosedLidLimit.testSecondsKey)
        XCTAssertEqual(ClosedLidLimit.testSeconds(in: defaults), 0, "The switch is off")
        XCTAssertEqual(DetectionSettings().closedLidLimits(testSeconds: ClosedLidLimit.testSeconds(in: defaults)).time, 3 * Self.hour)
        defaults.set(false, forKey: HoldStore.stateSwitchKey)
        XCTAssertEqual(ClosedLidLimit.testSeconds(in: defaults), 0)

        defaults.set(true, forKey: HoldStore.stateSwitchKey)
        XCTAssertEqual(ClosedLidLimit.testSeconds(in: defaults), 180)
        XCTAssertEqual(DetectionSettings().closedLidLimits(testSeconds: ClosedLidLimit.testSeconds(in: defaults)).time, 180, "It shortens")
        defaults.set(1e9, forKey: ClosedLidLimit.testSecondsKey)
        XCTAssertEqual(DetectionSettings().closedLidLimits(testSeconds: ClosedLidLimit.testSeconds(in: defaults)).time, 3 * Self.hour)
        defaults.set(-5, forKey: ClosedLidLimit.testSecondsKey)
        XCTAssertEqual(DetectionSettings().closedLidLimits(testSeconds: ClosedLidLimit.testSeconds(in: defaults)).time, 3 * Self.hour)
        defaults.removeObject(forKey: ClosedLidLimit.testSecondsKey)
        XCTAssertEqual(ClosedLidLimit.testSeconds(in: defaults), 0)
    }

    // MARK: One closed-lid period

    func testTimeAsleepDoesNotCount() throws {
        var mac = Mac()
        mac.run(Self.hour)
        XCTAssertTrue(mac.held)
        // The agent is idle, the Mac sleeps for 10 hours, and a sample
        // comes after it.
        mac.readings = [Self.reading(.idle)]
        mac.run(600)
        XCTAssertFalse(mac.held)
        mac.sleep(10 * Self.hour)
        mac.readings = [Self.reading(.working)]
        mac.run(1.9 * Self.hour)
        XCTAssertTrue(mac.held, "1 hour and 1.9 hours of hold, and 10 hours of sleep that do not count")
        let released = try XCTUnwrap(mac.runUntilReleased())
        XCTAssertEqual(released, 3 * Self.hour + 600, accuracy: 180, "The release time after the turn is held time too")
        assertStopped(mac, .time(seconds: 3 * Self.hour))
    }

    /// A hold that sleeps is no hold. The sample after a sleep has a hole
    /// before it, and the hole counts for nothing, whatever the clocks say.
    func testAHoleBetweenTwoSamplesCountsForNothing() {
        var limit = ClosedLidLimit()
        let context = FrameContext(onBattery: true, batteryPercent: 80, lidClosed: true)
        func time(_ seconds: TimeInterval) -> SampleTime { SampleTime(at: Self.start.addingTimeInterval(seconds), awake: nil) }
        XCTAssertNil(limit.update(context, holding: true, at: time(0)))
        XCTAssertNil(limit.update(context, holding: true, at: time(10)))
        XCTAssertNil(limit.update(context, holding: true, at: time(5 * Self.hour), afterGap: true))
        XCTAssertEqual(limit.period?.held, 10)
        XCTAssertNil(limit.update(context, holding: true, at: time(5 * Self.hour + 10)))
        XCTAssertEqual(limit.period?.held, 20)
    }

    func testSeveralAgentTurnsAreOnePeriod() throws {
        var mac = Mac()
        var since: Date?
        // An hour of work, half an hour of rest, three times over.
        for turn in 1...3 {
            mac.readings = [Self.reading(.working)]
            mac.run(Self.hour - 300)
            XCTAssertTrue(mac.held, "Turn \(turn)")
            since = since ?? mac.limit.period?.since
            XCTAssertEqual(mac.limit.period?.since, since, "The period began with the first hold")
            mac.readings = [Self.reading(.idle)]
            mac.run(1800)
            XCTAssertFalse(mac.held)
            XCTAssertNil(mac.limit.period?.stop)
        }
        mac.readings = [Self.reading(.working)]
        mac.run(300)
        XCTAssertTrue(mac.held)
        _ = try XCTUnwrap(mac.runUntilReleased())
        assertStopped(mac, .time(seconds: 3 * Self.hour))
        XCTAssertEqual(try XCTUnwrap(mac.limit.period?.held), 3 * Self.hour, accuracy: 30, "The held time of all turns together")
    }

    func testTheDropIsCountedFromTheStartOfThePeriod() throws {
        var mac = Mac()
        mac.drainPerHour = 12
        mac.run(Self.hour)
        mac.readings = [Self.reading(.idle)]
        mac.run(Self.hour)
        mac.readings = [Self.reading(.working)]
        XCTAssertNil(mac.limit.period?.stop)
        _ = try XCTUnwrap(mac.runUntilReleased())
        assertStopped(mac, .drop(points: 30))
        XCTAssertEqual(mac.limit.period?.percentAtStart, 90)
        XCTAssertEqual(mac.context.batteryPercent, 60)
    }

    func testTheStopStaysWhileTheLidIsClosedOnBattery() throws {
        var mac = Mac()
        _ = try XCTUnwrap(mac.runUntilReleased())
        mac.run(2 * Self.hour)
        assertStopped(mac, .time(seconds: 3 * Self.hour))
        // A new turn of the agent does not start a new count.
        mac.readings = [Self.reading(.idle)]
        mac.run(600)
        mac.readings = [Self.reading(.working)]
        mac.sleep(4 * Self.hour)
        mac.run(600)
        assertStopped(mac, .time(seconds: 3 * Self.hour))
        XCTAssertEqual(mac.decision?.perAgent.map(\.cause), [nil])
    }

    func testOpeningTheLidOrPowerStartsAFreshPeriod() throws {
        let resets: [(String, (inout FrameContext) -> Void, (inout FrameContext) -> Void)] = [
            ("lid", { $0.lidClosed = false }, { $0.lidClosed = true }),
            ("power", { $0.onBattery = false }, { $0.onBattery = true }),
        ]
        for (name, reset, back) in resets {
            var mac = Mac()
            _ = try XCTUnwrap(mac.runUntilReleased())
            reset(&mac.context)
            mac.sample()
            XCTAssertNil(mac.limit.period, name)
            XCTAssertTrue(mac.sample().hold, "The hold is back: \(name)")
            back(&mac.context)
            let before = mac.awake
            let released = try XCTUnwrap(mac.runUntilReleased())
            XCTAssertEqual(released - before, 3 * Self.hour, accuracy: 30, "A full limit again: \(name)")
        }
    }

    /// A reset in the middle of a period gives the whole limit again.
    func testAResetBeforeTheLimitStartsTheCountAgain() throws {
        var mac = Mac()
        mac.run(2 * Self.hour)
        mac.context.lidClosed = false
        mac.sample()
        mac.context.lidClosed = true
        let before = mac.awake
        XCTAssertEqual(try XCTUnwrap(mac.runUntilReleased()) - before, 3 * Self.hour, accuracy: 30)
    }

    func testAMacThatDoesNotSayItsBatteryLevelHasTheTimeLimitOnly() throws {
        var mac = Mac()
        mac.context.batteryPercent = nil
        XCTAssertEqual(try XCTUnwrap(mac.runUntilReleased()), 3 * Self.hour, accuracy: 30)
        assertStopped(mac, .time(seconds: 3 * Self.hour))
    }

    // MARK: The other stops and the other holds

    func testEveryOtherStopWins() {
        let lid = SafetyStop.closedLid(.time(seconds: 3 * Self.hour))
        func decide(enabled: Bool = true, pausedUntil: Date? = nil, entitlement: Entitlement = .licensed) -> HoldHeadline {
            HoldPolicy.decide(
                readings: [Self.reading(.working)], memory: PolicyMemory(), mode: .agentWorking, enabled: enabled, pausedUntil: pausedUntil,
                entitlement: entitlement, safety: lid, settings: DetectionSettings(), context: FrameContext(), now: Self.start
            ).0.headline
        }
        XCTAssertEqual(decide(), .safetyStop(lid))
        XCTAssertEqual(decide(enabled: false), .switchedOff)
        let until = Self.start.addingTimeInterval(600)
        XCTAssertEqual(decide(pausedUntil: until), .paused(until: until))
        XCTAssertEqual(decide(entitlement: .expired(.trialOver)), .notEntitled(.trialOver))
        XCTAssertTrue(lid.isLastStop)
        for stop in [SafetyStop.batteryLow(percent: 20), .weakCharger(percent: 20), .tooHot] { XCTAssertFalse(stop.isLastStop) }
    }

    func testHeatAndTheBatteryFloorComeFirst() throws {
        var mac = Mac()
        _ = try XCTUnwrap(mac.runUntilReleased())
        for stop in [SafetyStop.tooHot, .batteryLow(percent: 20)] {
            mac.otherStop = stop
            XCTAssertEqual(mac.sample().headline, .safetyStop(stop))
        }
        mac.otherStop = nil
        XCTAssertEqual(mac.sample().headline, .safetyStop(.closedLid(.time(seconds: 3 * Self.hour))), "It is still on behind the other stop")
    }

    func testTimeUnderAnotherStopIsNoHeldTime() throws {
        var mac = Mac()
        mac.run(Self.hour)
        let held = mac.limit.period?.held
        mac.otherStop = .tooHot
        mac.run(Self.hour)
        XCTAssertEqual(try XCTUnwrap(mac.limit.period?.held), try XCTUnwrap(held), accuracy: 20)
        mac.enabled = false
        mac.otherStop = nil
        mac.run(Self.hour)
        XCTAssertEqual(try XCTUnwrap(mac.limit.period?.held), try XCTUnwrap(held), accuracy: 20)
    }

    func testAManualHoldAJobHoldAndStayReachableAreStoppedToo() throws {
        let manual = ManualHold.timed(id: "aaaa0001", length: 4 * Self.hour, now: Self.start)
        let job = ScheduledJob(id: "crontab:backup.sh", source: .crontab, name: "backup.sh", schedule: .cron(JobTime.cron("0 3 * * *")), enabled: true)
        let jobHold = try XCTUnwrap(JobHold.open(job: job, fireAt: Self.start.addingTimeInterval(60), settings: JobSettings()))
        let cases: [(String, HoldHeadline, (inout Mac) -> Void)] = [
            ("manual", .manualHold(.one(manual.subject)), { $0.holds = [manual] }),
            ("job", .scheduledJob(.one("backup.sh")), { $0.jobHolds = [jobHold] }),
            ("reachable", .reachable(until: Self.start.addingTimeInterval(4 * Self.hour)), { $0.reachableUntil = Self.start.addingTimeInterval(4 * Self.hour) }),
        ]
        for (name, headline, set) in cases {
            var mac = Mac()
            mac.readings = []
            // The hidden default of the tests: 2 minutes.
            (mac.limit.timeLimit, mac.limit.dropLimit) = DetectionSettings().closedLidLimits(testSeconds: 120)
            set(&mac)
            XCTAssertEqual(mac.sample().headline, headline, name)
            XCTAssertEqual(try XCTUnwrap(mac.runUntilReleased()), 120, accuracy: 30, name)
            assertStopped(mac, .time(seconds: 120))
            XCTAssertEqual(mac.decision?.manualHolds, mac.holds, "Listed, and it keeps nothing awake: \(name)")
        }
    }

    // MARK: The night of 2026-10-10

    /// A state that says "working" for 13 hours, the lid closed, on
    /// battery, from 94 percent down as in that night: let go at 3 hours.
    func testAStateThatSaysWorkingForThirteenHoursIsLetGoAtThreeHours() throws {
        var mac = Mac()
        mac.context.batteryPercent = 94
        mac.drainPerHour = 3.5
        let released = try XCTUnwrap(mac.runUntilReleased())
        XCTAssertEqual(released, 3 * Self.hour, accuracy: 30)
        assertStopped(mac, .time(seconds: 3 * Self.hour))
        XCTAssertEqual(mac.context.batteryPercent, 94 - 10, "The battery of 3 hours, and not of 13")
        mac.run(10 * Self.hour)
        assertStopped(mac, .time(seconds: 3 * Self.hour))
        XCTAssertEqual(mac.decision?.working(mac.settings), .one("Claude Code"), "The state still says working")
    }

    /// The same night in a bag that gets hot: the battery falls faster,
    /// and the drop limit comes before the time limit.
    func testAHotBagIsLetGoEarlierAtThirtyPoints() throws {
        var mac = Mac()
        mac.context.batteryPercent = 94
        mac.drainPerHour = 15
        let released = try XCTUnwrap(mac.runUntilReleased())
        XCTAssertEqual(released, 2 * Self.hour, accuracy: 30)
        assertStopped(mac, .drop(points: 30))
    }

    /// The same as a recording: a session that reports "busy" with no end.
    func testTheReplayHasTheLimit() throws {
        let context = FrameContext(onBattery: true, batteryPercent: 94, lidClosed: true)
        let frames = stride(from: 0.0, through: 4 * Self.hour, by: 5).map { seconds -> EvidenceFrame in
            let at = Self.start.addingTimeInterval(seconds)
            let claude = AgentEvidence(
                agentID: "claude", displayName: "Claude Code", level: .state, kind: .cli, role: .session, pid: 100, startTime: 1_791_196_400,
                reported: StateReport(state: .working, since: nil, observedAt: at, source: .claudeSessionFile, detail: nil),
                childCommands: 0, busyChildCommands: 0, subtreeCPUSeconds: 0, sampleInterval: seconds == 0 ? 0 : 5,
                ownsSleepAssertion: false, hasLiveSession: false
            )
            return EvidenceFrame(at: at, agents: [claude], context: context)
        }
        func recording(_ settings: DetectionSettings) -> LabRecording {
            let header = LabHeader(
                label: "closed-lid", startedAt: Self.start, app: "synthetic", os: "synthetic", model: "synthetic",
                mode: AwakeMode.agentWorking.rawValue, settings: settings
            )
            return LabRecording(header: header, samples: frames.map { LabSample(frame: $0) })
        }
        let steps = LabReplay.steps(of: recording(DetectionSettings()))
        let released = steps.first { !$0.decision.hold }
        XCTAssertEqual(try XCTUnwrap(released).at.timeIntervalSince(Self.start), 3 * Self.hour, accuracy: 15)
        XCTAssertEqual(released?.decision.headline, .safetyStop(.closedLid(.time(seconds: 3 * Self.hour))))
        XCTAssertEqual(steps.last?.decision.hold, false)
        XCTAssertEqual(LabReplay.score(recording(DetectionSettings())).heldSeconds, 3 * Self.hour, accuracy: 15)

        var off = DetectionSettings()
        off.closedLidLimitHours = ClosedLidLimit.noLimit
        XCTAssertTrue(LabReplay.steps(of: recording(off)).allSatisfy(\.decision.hold), "With no limit the recording holds to its end")
    }

    // MARK: Texts

    func testTheWordsOfTheStop() {
        let time = SafetyStop.closedLid(.time(seconds: 3 * Self.hour))
        let drop = SafetyStop.closedLid(.drop(points: 30))
        XCTAssertEqual(time.notificationText, "Agent Caffeine let your Mac sleep because it kept it awake for 3 hours with the lid closed on battery")
        XCTAssertEqual(drop.notificationText, "Agent Caffeine let your Mac sleep because the battery lost 30% with the lid closed")
        XCTAssertEqual(
            time.notificationText(working: .one("Claude Code")),
            "Agent Caffeine let your Mac sleep because it kept it awake for 3 hours with the lid closed on battery. Claude Code was still working"
        )
        XCTAssertEqual(
            drop.notificationText(working: .many(2)),
            "Agent Caffeine let your Mac sleep because the battery lost 30% with the lid closed. 2 agents were still working"
        )
        XCTAssertEqual(time.notificationText(working: nil), time.notificationText)
        XCTAssertEqual(SafetyStop.tooHot.notificationText(working: .one("Codex")), SafetyStop.tooHot.notificationText, "Only the closed lid limit names an agent")

        XCTAssertEqual(SafetyStop.closedLid(.time(seconds: Self.hour)).notificationText, "Agent Caffeine let your Mac sleep because it kept it awake for 1 hour with the lid closed on battery")
        XCTAssertEqual(PanelText.closedLidReason(.time(seconds: 120)), "kept awake for 2 minutes with the lid closed on battery")
        XCTAssertEqual(PanelText.closedLidReason(.time(seconds: 45)), "kept awake for 45 seconds with the lid closed on battery")

        XCTAssertEqual(HoldHeadline.safetyStop(time).text, "Sleeping allowed: kept awake for 3 hours with the lid closed on battery")
        XCTAssertEqual(HoldHeadline.safetyStop(drop).text, "Sleeping allowed: the battery lost 30% with the lid closed")
        let now = Date()
        XCTAssertEqual(PanelText.headline(.safetyStop(time), now: now).subtitle, "Kept awake for 3 hours with the lid closed on battery")
        XCTAssertEqual(PanelText.headline(.safetyStop(drop), now: now).subtitle, "The battery lost 30% with the lid closed")
        XCTAssertEqual(PanelText.headline(.safetyStop(time), now: now).title, PanelText.stoppedTitle)
        XCTAssertEqual(PanelText.startsAgainWhenLidOpens, "Agent Caffeine starts again when you open the lid or connect power")
        XCTAssertEqual(MenuModel.pose(for: .safetyStop(time)), .safetyStop(.battery))
        XCTAssertFalse(HoldHeadline.safetyStop(time).keepsAwake)
        XCTAssertTrue(HoldHeadline.safetyStop(time).isStop)
    }

    func testTheSettingsWords() {
        XCTAssertEqual(PanelText.closedLidLimitExplained, "A last stop, so a job that hangs does not empty the battery in a bag")
        XCTAssertEqual(PanelText.noLimit, "No limit")
        XCTAssertEqual(ClosedLidLimit.hourChoices, [1, 2, 3, 6, 12])
        XCTAssertEqual(ClosedLidLimit.dropChoices, [15, 30, 50])
        XCTAssertTrue(ClosedLidLimit.hourChoices.contains(ClosedLidLimit.defaultHours))
        XCTAssertTrue(ClosedLidLimit.dropChoices.contains(ClosedLidLimit.defaultDropPoints))
    }

    // MARK: The note after the sleep

    func testTheNoteAfterTheSleepSaysWhyAndWhoStillWorked() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let at = Date(timeIntervalSince1970: 2 * 3600 + 14 * 60)
        let stop = ClosedLidStop.time(seconds: 3 * Self.hour)
        var snapshot = SleepSnapshot(at: at, headline: .safetyStop(.closedLid(stop)), agentActive: false, lidClosed: true, onBattery: true)
        XCTAssertEqual(SleepReason.reason(snapshot), .closedLidLimit(stop, working: nil), "Told with no agent too: it ends every kind of hold")
        snapshot.agentActive = true
        snapshot.working = .one("Claude Code")
        XCTAssertEqual(SleepNote(snapshot), SleepNote(at: at, reason: .closedLidLimit(stop, working: .one("Claude Code"))))

        let cases: [(SleepReason, String)] = [
            (.closedLidLimit(stop, working: nil), "Agent Caffeine had kept it awake for 3 hours with the lid closed on battery"),
            (.closedLidLimit(stop, working: .one("Claude Code")), "Agent Caffeine had kept it awake for 3 hours with the lid closed on battery, and Claude Code was still working"),
            (.closedLidLimit(.drop(points: 30), working: nil), "the battery lost 30% with the lid closed"),
            (.closedLidLimit(.drop(points: 30), working: .many(2)), "the battery lost 30% with the lid closed, and 2 agents were still working"),
        ]
        for (reason, text) in cases {
            let line = PanelText.slept(SleepNote(at: at, reason: reason), calendar: calendar, locale: Locale(identifier: "en_GB"))
            XCTAssertEqual(line, "Your Mac slept at 02:14: \(text)")
        }
    }

    func testOnlyAgentsThatWorkAndAreNotIgnoredAreNamed() {
        let readings = [Self.reading(.working), Self.reading(.idle, name: "Codex", pid: 2)]
        var decision = HoldDecision(hold: false, lidClosedFlag: false, headline: .noAgents, perAgent: readings.map { AgentHold(reading: $0, cause: nil) })
        XCTAssertEqual(decision.working(DetectionSettings()), .one("Claude Code"))
        var ignoring = DetectionSettings()
        ignoring.agentRules = ["claude": .ignore]
        XCTAssertNil(decision.working(ignoring))
        decision.perAgent = []
        XCTAssertNil(decision.working(DetectionSettings()))
    }

    // MARK: Settings store

    func testTheLimitsAreSavedAndLoaded() throws {
        let defaults = TestDefaults()
        var settings = DetectionSettings()
        settings.closedLidLimitHours = 6
        settings.closedLidLimitDrop = ClosedLidLimit.noLimit
        DetectionSettingsStore.save(settings, to: defaults)
        let loaded = DetectionSettingsStore.load(from: defaults)
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.closedLidLimitDrop, ClosedLidLimit.noLimit, "No limit is kept, and is not the default")

        defaults.set(Data(#"{"batteryFloorPercent":35}"#.utf8), forKey: DetectionSettingsStore.key)
        let old = DetectionSettingsStore.load(from: defaults)
        XCTAssertEqual(old.closedLidLimitHours, 3, "On for settings of a build that did not have it")
        XCTAssertEqual(old.closedLidLimitDrop, 30)
    }

    func testALimitThatIsNotOfferedIsTheDefault() throws {
        func decode(_ json: String) throws -> DetectionSettings {
            try JSONDecoder().decode(DetectionSettings.self, from: Data(json.utf8))
        }
        for json in [#"{"closedLidLimitHours":5,"closedLidLimitDrop":99}"#, #"{"closedLidLimitHours":-1,"closedLidLimitDrop":-30}"#, #"{"closedLidLimitHours":1000,"closedLidLimitDrop":1}"#] {
            let settings = try decode(json)
            XCTAssertEqual(settings.closedLidLimitHours, 3, json)
            XCTAssertEqual(settings.closedLidLimitDrop, 30, json)
        }
        let fine = try decode(#"{"closedLidLimitHours":1,"closedLidLimitDrop":50}"#)
        XCTAssertEqual(fine.closedLidLimitHours, 1)
        XCTAssertEqual(fine.closedLidLimitDrop, 50)
        let none = try decode(#"{"closedLidLimitHours":0,"closedLidLimitDrop":0}"#)
        XCTAssertEqual(none.closedLidLimitHours, ClosedLidLimit.noLimit)
        XCTAssertEqual(none.closedLidLimitDrop, ClosedLidLimit.noLimit)
    }
}
