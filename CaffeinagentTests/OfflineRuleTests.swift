import XCTest

/// The offline rule: `OfflineRule`, with the policy, the texts, the menu,
/// the settings and the state for the tests. Every path is passed in.
final class OfflineRuleTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)
    private static let minute: TimeInterval = 60
    /// Below `SampleGap.threshold`, so two samples have no hole between them.
    private static let step: TimeInterval = 10

    private static func reading(
        _ state: WorkState, _ reason: VerdictReason? = nil, name: String = "Claude Code", pid: Int32 = 1, busy: Int = 0
    ) -> AgentReading {
        AgentReading(
            agentID: "claude", displayName: name, level: .state, identity: ProcessIdentity(pid: pid, startTime: 1),
            verdict: AgentVerdict(state: state, confidence: .reported, reason: reason ?? (state == .working ? .reportsBusy : .atPrompt)),
            busyCommands: busy
        )
    }

    /// A Mac that is sampled every 10 seconds, as the engine does it: the
    /// rule sees the path of each sample, and the policy decides with it.
    private struct Mac {
        var rule = OfflineRule()
        var settings = DetectionSettings()
        var context = FrameContext(offline: true)
        var readings = [OfflineRuleTests.reading(.working)]
        var holds: [ManualHold] = []
        var jobHolds: [JobHold] = []
        var reachableUntil: Date?
        var mode = AwakeMode.agentWorking
        var enabled = true
        var pausedUntil: Date?
        var safety: SafetyStop?

        private(set) var decision: HoldDecision?
        private(set) var awake: TimeInterval = 0
        private(set) var wall: TimeInterval = 0
        private var memory = PolicyMemory()
        private var previous: SampleTime?

        var held: Bool { decision?.hold ?? false }
        var now: Date { OfflineRuleTests.start.addingTimeInterval(wall) }

        /// The Mac sleeps for this long. No sample is taken.
        mutating func sleep(_ seconds: TimeInterval) {
            wall += seconds
        }

        @discardableResult
        mutating func sample() -> HoldDecision {
            awake += OfflineRuleTests.step
            wall += OfflineRuleTests.step
            let time = SampleTime(at: now, awake: awake)
            if let gap = SampleGap.length(from: previous, to: time) { memory = memory.shifted(by: gap) }
            previous = time
            rule.limit = settings.offlineLimit()
            rule.update(offline: context.offline, at: time)
            let (next, nextMemory) = HoldPolicy.decide(
                readings: readings, memory: memory, mode: mode, enabled: enabled, pausedUntil: pausedUntil, reachableUntil: reachableUntil,
                holds: holds, jobHolds: jobHolds, safety: safety, settings: settings, context: context,
                agentStop: rule.agentsReleased ? .offline : nil, now: now
            )
            memory = nextMemory
            decision = next
            return next
        }

        /// Samples for this long of awake time.
        mutating func run(_ seconds: TimeInterval) {
            for _ in 0..<Int(seconds / OfflineRuleTests.step) { sample() }
        }

        /// Samples until the hold ends, for 14 hours at most.
        /// - Returns: the awake seconds at the first sample without a hold.
        mutating func runUntilReleased() -> TimeInterval? {
            for _ in 0..<Int(14 * 3600 / OfflineRuleTests.step) where !sample().hold { return awake }
            return nil
        }
    }

    private func jobHold(at now: Date) -> JobHold {
        JobHold(
            id: "launchd:backup@1", jobID: "launchd:backup", source: .launchd, name: "backup", start: now.timeIntervalSince1970,
            fireAt: now.timeIntervalSince1970 + 30, startGrace: 3600, cap: 3600
        )
    }

    // MARK: The rule

    func testAgentsStopHoldingAfterTenMinutesOffline() throws {
        var mac = Mac()
        mac.run(10 * Self.minute - Self.step)
        XCTAssertTrue(mac.held, "Not before the ten minutes are over")
        XCTAssertEqual(mac.decision?.headline, .working(.one("Claude Code")))
        XCTAssertFalse(mac.rule.agentsReleased)
        var again = Mac()
        let released = try XCTUnwrap(again.runUntilReleased())
        XCTAssertEqual(released, 10 * Self.minute, accuracy: 20)
        XCTAssertEqual(again.decision?.headline, .agentsStopped(.offline))
        XCTAssertEqual(again.decision?.lidClosedFlag, false, "The sleep flag goes off with the hold")
        XCTAssertEqual(again.decision?.perAgent.map(\.cause), [nil])
        XCTAssertEqual(again.decision?.perAgent.map(\.stopped), [.offline])
        XCTAssertFalse(HoldHeadline.agentsStopped(.offline).isStop, "Other holds go on, so it is no stop")
    }

    func testOnlineNothingIsReleased() {
        var mac = Mac()
        mac.context.offline = false
        XCTAssertNil(mac.runUntilReleased())
        XCTAssertNil(mac.rule.offlineFor)
    }

    /// One sample with a path ends the count, so ten minutes offline are
    /// ten minutes without a break.
    func testAPathThatComesBackForAMomentStartsTheCountAgain() {
        var mac = Mac()
        mac.run(9 * Self.minute)
        mac.context.offline = false
        mac.sample()
        mac.context.offline = true
        mac.run(9 * Self.minute)
        XCTAssertTrue(mac.held)
        mac.run(2 * Self.minute)
        XCTAssertFalse(mac.held)
    }

    /// No release time and no wait: the first sample with a path holds.
    func testWhenThePathComesBackTheAgentsHoldAtOnce() {
        var mac = Mac()
        mac.run(20 * Self.minute)
        XCTAssertFalse(mac.held)
        mac.context.offline = false
        XCTAssertTrue(mac.sample().hold)
        XCTAssertEqual(mac.decision?.headline, .working(.one("Claude Code")))
        XCTAssertEqual(mac.decision?.perAgent.map(\.stopped), [nil])
    }

    /// The release time after work would start a hold for an agent that
    /// is idle when the path comes back.
    func testAnAgentThatFinishedOfflineStartsNoReleaseTimeWhenThePathComesBack() {
        var mac = Mac()
        mac.run(20 * Self.minute)
        mac.readings = [Self.reading(.idle)]
        mac.sample()
        XCTAssertEqual(mac.decision?.headline, .idle(.one("Claude Code")))
        mac.context.offline = false
        XCTAssertFalse(mac.sample().hold)
        XCTAssertEqual(mac.decision?.headline, .idle(.one("Claude Code")))
    }

    func testAnAgentThatFinishedAMomentAgoIsReleasedToo() {
        var mac = Mac()
        mac.run(9 * Self.minute)
        mac.readings = [Self.reading(.idle)]
        mac.sample()
        XCTAssertEqual(mac.decision?.headline, .finishedRecently(.one("Claude Code")))
        mac.run(Self.minute)
        XCTAssertFalse(mac.held, "Offline for ten minutes, inside the release time of two")
        XCTAssertEqual(mac.decision?.headline, .idle(.one("Claude Code")))
    }

    func testAnAgentThatWaitsAndOneThatIsOnlyOpenAreReleased() {
        var waiting = Mac()
        waiting.settings.waitingHold = 3600
        waiting.readings = [Self.reading(.waitingForUser, .asksPermission)]
        waiting.run(9 * Self.minute)
        XCTAssertEqual(waiting.decision?.headline, .waitingHeld(.one("Claude Code")))
        waiting.run(2 * Self.minute)
        XCTAssertEqual(waiting.decision?.headline, .agentsStopped(.offline))

        var open = Mac()
        open.mode = .agentOpen
        open.readings = [Self.reading(.idle)]
        open.run(9 * Self.minute)
        XCTAssertEqual(open.decision?.headline, .open(.one("Claude Code")))
        open.run(2 * Self.minute)
        XCTAssertEqual(open.decision?.headline, .agentsStopped(.offline))
    }

    func testIdleAgentsReadAsIdleOffline() {
        var mac = Mac()
        mac.readings = [Self.reading(.idle)]
        mac.run(20 * Self.minute)
        XCTAssertEqual(mac.decision?.headline, .idle(.one("Claude Code")), "Nothing was let go")
        XCTAssertEqual(mac.decision?.perAgent.map(\.stopped), [nil])
    }

    // MARK: What keeps holding

    func testAHoldFromTheCommandLineKeepsHoldingOffline() {
        var mac = Mac()
        mac.holds = [ManualHold.timed(id: "aaaa0001", length: 4 * 3600, reason: "deploy", now: Self.start)]
        mac.run(2 * 3600)
        XCTAssertTrue(mac.held)
        XCTAssertEqual(mac.decision?.headline, .manualHold(.one("deploy")), "The agent is no longer the reason")
        XCTAssertEqual(mac.decision?.perAgent.map(\.stopped), [.offline])
        XCTAssertEqual(mac.decision?.lidClosedFlag, true)
    }

    func testAJobHoldKeepsHoldingOffline() {
        var mac = Mac()
        mac.jobHolds = [jobHold(at: Self.start)]
        mac.run(30 * Self.minute)
        XCTAssertTrue(mac.held)
        XCTAssertEqual(mac.decision?.headline, .scheduledJob(.one("backup")))
    }

    func testStayReachableAndTheModeAlwaysKeepHoldingOffline() {
        var reachable = Mac()
        let until = Self.start.addingTimeInterval(4 * 3600)
        reachable.reachableUntil = until
        reachable.run(2 * 3600)
        XCTAssertEqual(reachable.decision?.headline, .reachable(until: until))
        XCTAssertTrue(reachable.held)

        var always = Mac()
        always.mode = .always
        always.run(2 * 3600)
        XCTAssertEqual(always.decision?.headline, .alwaysOn)
        XCTAssertTrue(always.held)
    }

    /// A build or a test needs no network. The command counts by the
    /// verdict of an agent that says nothing, and by the evidence of one
    /// that says it works.
    func testABusyChildCommandKeepsHoldingOffline() {
        for reading in [Self.reading(.working, .runningCommand(1)), Self.reading(.working, .reportsBusy, busy: 2)] {
            var mac = Mac()
            mac.readings = [reading]
            mac.run(2 * 3600)
            XCTAssertTrue(mac.held, "\(reading.verdict.reason)")
            XCTAssertEqual(mac.decision?.headline, .working(.one("Claude Code")))
            XCTAssertEqual(mac.decision?.perAgent.map(\.stopped), [nil])
            // The command ends, and the agent still says it works.
            mac.readings = [Self.reading(.working)]
            XCTAssertFalse(mac.sample().hold, "No release time after the command")
        }
    }

    func testOnlyTheAgentWithTheBusyCommandHoldsOn() {
        var mac = Mac()
        mac.readings = [Self.reading(.working, name: "Claude Code", pid: 1), Self.reading(.working, .runningCommand(1), name: "Codex", pid: 2)]
        mac.run(30 * Self.minute)
        XCTAssertEqual(mac.decision?.headline, .working(.one("Codex")))
        XCTAssertEqual(mac.decision?.perAgent.map(\.stopped), [.offline, nil])
    }

    func testOtherBackgroundWorkOfAnAgentIsReleased() {
        for reason in [VerdictReason.backgroundJob(1), .backgroundWork, .alwaysWorkingByRule, .cpuActivity] {
            var mac = Mac()
            mac.readings = [Self.reading(.working, reason)]
            mac.run(11 * Self.minute)
            XCTAssertFalse(mac.held, "\(reason)")
        }
    }

    // MARK: Time

    /// A Mac that slept offline for hours does not let go at once.
    func testTimeAsleepDoesNotCountAndTheCountStartsFreshAfterASleep() {
        var mac = Mac()
        mac.run(8 * Self.minute)
        mac.sleep(6 * 3600)
        mac.sample()
        XCTAssertTrue(mac.held)
        XCTAssertEqual(mac.rule.offlineFor, 0)
        mac.run(9 * Self.minute)
        XCTAssertTrue(mac.held, "Ten whole minutes after the wake")
        mac.run(Self.minute)
        XCTAssertFalse(mac.held)
    }

    /// Samples that come late count with the time the Mac was awake.
    func testAwakeTimeBetweenLateSamplesCounts() {
        var rule = OfflineRule()
        for index in 0...12 {
            let seconds = TimeInterval(index) * 60
            rule.update(offline: true, at: SampleTime(at: Self.start.addingTimeInterval(seconds), awake: seconds))
        }
        XCTAssertEqual(rule.offlineFor, 720)
        XCTAssertTrue(rule.agentsReleased)
    }

    /// Without the awake clock, as in an older recording, a hole is
    /// taken for a sleep.
    func testWithoutTheAwakeClockAHoleStartsTheCountAgain() {
        var rule = OfflineRule()
        rule.update(offline: true, at: SampleTime(at: Self.start, awake: nil))
        rule.update(offline: true, at: SampleTime(at: Self.start.addingTimeInterval(10), awake: nil))
        XCTAssertEqual(rule.offlineFor, 10)
        rule.update(offline: true, at: SampleTime(at: Self.start.addingTimeInterval(3600), awake: nil))
        XCTAssertEqual(rule.offlineFor, 0)
    }

    // MARK: Settings

    func testNeverReleasesNothing() {
        var mac = Mac()
        mac.settings.offlineLimitMinutes = OfflineRule.never
        XCTAssertNil(mac.settings.offlineLimit())
        XCTAssertNil(mac.runUntilReleased())
    }

    func testTheChoicesOfTheSettings() throws {
        XCTAssertEqual(DetectionSettings().offlineLimit(), 600, "Ten minutes unless set")
        for minutes in OfflineRule.minuteChoices {
            var mac = Mac()
            mac.settings.offlineLimitMinutes = minutes
            let released = try XCTUnwrap(mac.runUntilReleased())
            XCTAssertEqual(released, TimeInterval(minutes) * 60, accuracy: 20)
        }
    }

    func testTheSettingIsSavedAndAnOddValueIsTheDefault() throws {
        let defaults = TestDefaults()
        var settings = DetectionSettings()
        settings.offlineLimitMinutes = 30
        DetectionSettingsStore.save(settings, to: defaults)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults).offlineLimitMinutes, 30)
        settings.offlineLimitMinutes = OfflineRule.never
        DetectionSettingsStore.save(settings, to: defaults)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults).offlineLimitMinutes, OfflineRule.never)
        defaults.set(Data(#"{"waitingHold":60}"#.utf8), forKey: DetectionSettingsStore.key)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults).offlineLimitMinutes, 10, "Settings of a build that did not have it")
        defaults.set(Data(#"{"offlineLimitMinutes":7}"#.utf8), forKey: DetectionSettingsStore.key)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults).offlineLimitMinutes, 10)
    }

    /// The hidden default of the tests counts only with the switch of the
    /// tests, and only makes the limit shorter.
    func testTheHiddenDefaultOnlyShortensAndNeedsTheSwitch() {
        let defaults = TestDefaults()
        defaults.set(60, forKey: OfflineRule.testSecondsKey)
        XCTAssertEqual(OfflineRule.testSeconds(in: defaults), 0, "The switch is off")
        XCTAssertEqual(DetectionSettings().offlineLimit(testSeconds: OfflineRule.testSeconds(in: defaults)), 600)
        defaults.set(true, forKey: HoldStore.stateSwitchKey)
        XCTAssertEqual(OfflineRule.testSeconds(in: defaults), 60)
        XCTAssertEqual(DetectionSettings().offlineLimit(testSeconds: 60), 60, "It shortens")
        XCTAssertEqual(DetectionSettings().offlineLimit(testSeconds: 1e9), 600, "It never makes the limit longer")
        XCTAssertEqual(DetectionSettings().offlineLimit(testSeconds: -5), 600)
        var never = DetectionSettings()
        never.offlineLimitMinutes = OfflineRule.never
        XCTAssertEqual(never.offlineLimit(testSeconds: 60), 60)
    }

    // MARK: The other stops

    func testEveryOtherStopStillWins() {
        let until = Self.start.addingTimeInterval(24 * 3600)
        let cases: [(HoldHeadline, (inout Mac) -> Void)] = [
            (.safetyStop(.batteryLow(percent: 20)), { $0.safety = .batteryLow(percent: 20) }),
            (.safetyStop(.tooHot), { $0.safety = .tooHot }),
            (.switchedOff, { $0.enabled = false }),
            (.paused(until: until), { $0.pausedUntil = until }),
        ]
        for (headline, set) in cases {
            var mac = Mac()
            mac.holds = [ManualHold.timed(id: "aaaa0001", length: 4 * 3600, now: Self.start)]
            mac.run(20 * Self.minute)
            XCTAssertTrue(mac.held)
            set(&mac)
            XCTAssertFalse(mac.sample().hold, "\(headline)")
            XCTAssertEqual(mac.decision?.headline, headline)
            XCTAssertEqual(mac.decision?.perAgent.map(\.stopped), [nil], "The stop is the reason, not the network")
        }
    }

    /// The closed lid limit lets go of every agent, so it is named
    /// before the offline rule, which leaves a busy command.
    func testTheClosedLidLimitComesBeforeTheOfflineRule() {
        let lid = AgentStop.closedLid(.time(seconds: 10_800))
        let decision = HoldPolicy.decide(
            readings: [Self.reading(.working, .runningCommand(1))], memory: PolicyMemory(), mode: .agentWorking, enabled: true,
            safety: nil, settings: DetectionSettings(), context: FrameContext(offline: true), agentStop: lid, now: Self.start
        ).0
        XCTAssertEqual(decision.headline, .agentsStopped(lid))
    }

    // MARK: The incident

    /// 2026-10: the Mac in a bag on the hotspot of a phone. The hotspot
    /// went away, the agent said "working" all night and could do
    /// nothing, and the Mac stayed awake.
    func testAnAgentThatSaysWorkingForThirteenHoursOfflineHoldsForTenMinutes() throws {
        var mac = Mac()
        mac.context = FrameContext(onBattery: true, batteryPercent: 80, lidClosed: true, offline: true)
        let released = try XCTUnwrap(mac.runUntilReleased())
        XCTAssertEqual(released, 10 * Self.minute, accuracy: 20)
        XCTAssertEqual(mac.decision?.lidClosedFlag, false)
        for _ in 0..<Int(13 * 3600 / Self.step) {
            XCTAssertFalse(mac.sample().hold)
        }
        XCTAssertEqual(mac.decision?.headline, .agentsStopped(.offline))
    }

    // MARK: Texts

    /// An agent with a model on this Mac works offline, so the line does
    /// not say that no agent can, and it names the way out.
    func testTheSettingsWords() {
        XCTAssertEqual(PanelText.offlineLimitPicker, "Stop when offline for")
        XCTAssertEqual(PanelText.offlineLimitExplained, "Choose Never if your agents use a model on this Mac")
        XCTAssertTrue(PanelText.offlineLimitExplained.contains("Choose \(PanelText.never)"))
        XCTAssertEqual(
            PanelText.offlineLimitInfo,
            "Most agents cannot work without the internet. This stops only agents. Command line holds and scheduled jobs keep your Mac awake. Wi-Fi with no internet does not count as offline."
        )
    }

    func testTheNotificationNamesTheTimeAndTheAgentsThatWorked() {
        XCTAssertEqual(
            PanelText.offlineNotice(limit: 600, working: .one("Claude Code")),
            "Agent Caffeine let your Mac sleep because it was offline for 10 minutes. Claude Code was still working"
        )
        XCTAssertEqual(
            PanelText.offlineNotice(limit: 1800, working: .many(3)),
            "Agent Caffeine let your Mac sleep because it was offline for 30 minutes. 3 agents were still working"
        )
        XCTAssertEqual(PanelText.offlineNotice(limit: 300, working: nil), "Agent Caffeine let your Mac sleep because it was offline for 5 minutes")
        XCTAssertEqual(PanelText.offlineNotice(limit: 45, working: nil), "Agent Caffeine let your Mac sleep because it was offline for 45 seconds")
    }

    func testTheNoteAfterTheLidOpens() throws {
        let at = Date(timeIntervalSince1970: 1_000_000)
        var snapshot = SleepSnapshot(at: at, headline: .agentsStopped(.offline), agentActive: true, lidClosed: true, onBattery: true)
        snapshot.working = .one("Claude Code")
        let note = try XCTUnwrap(SleepNote(snapshot))
        XCTAssertEqual(note.reason, .offline(limit: 600, working: .one("Claude Code")))
        XCTAssertEqual(
            PanelText.slept(note, calendar: .current, locale: Locale(identifier: "en_GB")),
            "Your Mac slept at \(PanelText.time(at, locale: Locale(identifier: "en_GB"))): it was offline for 10 minutes, and Claude Code was still working"
        )
        snapshot.working = .many(2)
        snapshot.offlineLimit = 300
        XCTAssertTrue(PanelText.slept(try XCTUnwrap(SleepNote(snapshot))).hasSuffix(": it was offline for 5 minutes, and 2 agents were still working"))
        snapshot.working = nil
        XCTAssertTrue(PanelText.slept(try XCTUnwrap(SleepNote(snapshot))).hasSuffix(": it was offline for 5 minutes"))
    }

    func testTheLineOfTheLabLog() {
        XCTAssertEqual(HoldHeadline.agentsStopped(.offline).text, "Mac can sleep: the Mac is offline, so agents do not keep it awake")
        XCTAssertNil(HoldHeadline.agentsStopped(.offline).awakeReason)
    }

    // MARK: Menu

    /// Only agents are there: the headline says that the Mac can sleep
    /// and why, and the line of the agent does not read as a hold.
    func testTheMenuWithAgentsOnly() {
        var mac = Mac()
        mac.run(11 * Self.minute)
        let state = MenuModel.state(PanelInput(decision: mac.decision!), now: mac.now)
        XCTAssertEqual(state.title, "Your Mac can sleep")
        XCTAssertEqual(state.subtitle, "Your Mac is offline, so agents do not keep it awake")
        XCTAssertEqual(state.pose, .asleep)
        XCTAssertNil(state.attention, "The headline says it")
        XCTAssertEqual(state.groups.map(\.header.name), ["Claude Code"])
        XCTAssertEqual(state.groups.map(\.header.detail), ["Working, but your Mac is offline"])
        XCTAssertNil(state.emptyText)
    }

    /// A hold from the command line keeps the Mac awake: the headline
    /// names it, a line below says that the agents do not count, and the
    /// two lines of the list read true.
    func testTheMenuWithAgentsAndAHoldFromTheCommandLine() {
        var mac = Mac()
        mac.holds = [ManualHold.timed(id: "aaaa0001", length: 4 * 3600, reason: "deploy", now: Self.start)]
        mac.run(11 * Self.minute)
        let state = MenuModel.state(PanelInput(decision: mac.decision!), now: mac.now)
        XCTAssertEqual(state.title, "Your Mac stays awake")
        XCTAssertEqual(state.subtitle, "deploy asked for it")
        XCTAssertEqual(state.attention, PanelAttention(kind: .agentsOffline, text: "Your Mac is offline, so agents do not keep it awake"))
        XCTAssertEqual(state.groups.map(\.header.name), ["Claude Code", "deploy"])
        XCTAssertEqual(state.groups[0].header.detail, "Working, but your Mac is offline")
        XCTAssertTrue(state.groups[1].header.detail.hasPrefix("Keeps your Mac awake until "))
    }

    func testAnAgentWithABusyCommandKeepsItsLineInTheMenu() {
        var mac = Mac()
        mac.readings = [Self.reading(.working, .runningCommand(1))]
        mac.run(11 * Self.minute)
        let state = MenuModel.state(PanelInput(decision: mac.decision!), now: mac.now)
        XCTAssertEqual(state.title, "Your Mac stays awake")
        XCTAssertEqual(state.subtitle, "Claude Code is working")
        XCTAssertNil(state.attention)
        XCTAssertEqual(state.groups.map(\.header.detail), ["Running 1 command"])
    }

    /// A safety stop has its own line, and it is the more urgent one.
    func testTheLineOfASafetyStopComesFirst() {
        var mac = Mac()
        mac.holds = [ManualHold.timed(id: "aaaa0001", length: 4 * 3600, now: Self.start)]
        mac.run(11 * Self.minute)
        mac.safety = .tooHot
        mac.sample()
        XCTAssertEqual(MenuModel.state(PanelInput(decision: mac.decision!), now: mac.now).attention?.kind, .safetyStop)
    }

    // MARK: State for the tests, recording

    func testTheFrameCarriesThePathAndAnOlderLineIsOnline() throws {
        let frame = EvidenceFrame(at: Self.start, agents: [], context: FrameContext(offline: true))
        let line = String(decoding: try LabFormat.encoder().encode(frame), as: UTF8.self)
        XCTAssertTrue(line.contains(#""off":true"#), line)
        XCTAssertEqual(try LabFormat.decoder().decode(EvidenceFrame.self, from: Data(line.utf8)).context.offline, true)
        let online = String(decoding: try LabFormat.encoder().encode(EvidenceFrame(at: Self.start, agents: [])), as: UTF8.self)
        XCTAssertFalse(online.contains("off"), "Left out of a line that is online")
        XCTAssertEqual(try LabFormat.decoder().decode(EvidenceFrame.self, from: Data(online.utf8)).context.offline, false)
    }

    /// The replay runs the rule from the path of each frame.
    func testAReplayReleasesAfterTenMinutesOfOfflineFrames() {
        let claude = AgentEvidence(
            agentID: "claude", displayName: "Claude Code", level: .state, pid: 1, startTime: 1,
            reported: StateReport(state: .working, since: nil, observedAt: Self.start, source: .claudeSessionFile, detail: nil)
        )
        func recording(offline: Bool) -> LabRecording {
            var recording = LabRecording()
            for index in 0...90 {
                let seconds = TimeInterval(index) * 10
                var agent = claude
                agent.reported?.observedAt = Self.start.addingTimeInterval(seconds)
                var frame = EvidenceFrame(at: Self.start.addingTimeInterval(seconds), agents: [agent], context: FrameContext(offline: offline))
                frame.awake = seconds
                recording.samples.append(LabSample(frame: frame))
            }
            return recording
        }
        let steps = LabReplay.steps(of: recording(offline: true))
        XCTAssertEqual(steps.firstIndex { !$0.decision.hold }, 60)
        XCTAssertEqual(steps.last?.decision.headline, .agentsStopped(.offline))
        XCTAssertTrue(LabReplay.steps(of: recording(offline: false)).allSatisfy(\.decision.hold))
        var never = DetectionSettings()
        never.offlineLimitMinutes = OfflineRule.never
        XCTAssertTrue(LabReplay.steps(of: recording(offline: true), settings: never).allSatisfy(\.decision.hold))
    }
}
