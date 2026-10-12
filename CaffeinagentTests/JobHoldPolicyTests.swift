import XCTest

/// A job hold in `HoldPolicy`, at the wake gate and in a recording.
final class JobHoldPolicyTests: XCTestCase {
    /// The time of the job. The alarm is a minute before it.
    private static let fire = JobTime.date("2026-10-10 03:00")

    private func at(_ seconds: TimeInterval) -> Date { Self.fire.addingTimeInterval(seconds) }

    private func hold(_ source: ScheduledJob.Source = .crontab, name: String = "backup.sh", settings: JobSettings = JobSettings()) -> JobHold {
        let job = ScheduledJob(id: "\(source.rawValue):\(name)", source: source, name: name, schedule: .cron(JobTime.cron("0 3 * * *")), enabled: true)
        return JobHold.open(job: job, fireAt: Self.fire, settings: settings)!
    }

    private func working(_ name: String = "Claude Code") -> AgentReading {
        AgentReading(
            agentID: "claude", displayName: name, level: .state, identity: ProcessIdentity(pid: 1, startTime: 1),
            verdict: AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy)
        )
    }

    private func decide(
        _ jobs: [JobHold], holds: [ManualHold] = [], readings: [AgentReading] = [], at seconds: TimeInterval = 0, enabled: Bool = true,
        pausedUntil: Date? = nil, safety: SafetyStop? = nil,
        settings: DetectionSettings = DetectionSettings(), mayHold: Bool = true, jobsMayHold: Bool? = nil
    ) -> HoldDecision {
        HoldPolicy.decide(
            readings: readings, memory: PolicyMemory(), mode: .agentWorking, enabled: enabled, pausedUntil: pausedUntil, holds: holds,
            jobHolds: jobs, safety: safety, settings: settings, context: FrameContext(), mayHold: mayHold,
            jobsMayHold: jobsMayHold, now: at(seconds)
        ).0
    }

    // MARK: The policy

    func testAJobHoldKeepsTheMacAwakeFromTheTimeOfTheAlarm() {
        XCTAssertFalse(decide([hold()], at: -61).hold, "Before the alarm")
        XCTAssertEqual(decide([hold()], at: -61).jobHolds, [])
        let decision = decide([hold()], at: -60)
        XCTAssertTrue(decision.hold)
        XCTAssertEqual(decision.headline, .scheduledJob(.one("backup.sh")))
        XCTAssertEqual(decision.jobHolds, [hold()])
        XCTAssertNil(decision.waitingEnds)
        XCTAssertEqual(decide([hold(), hold(name: "report")], at: 0).headline, .scheduledJob(.many(2)))
    }

    func testEveryStopBeatsAJobHold() {
        let jobs = [hold()]
        let stops: [(HoldDecision, HoldHeadline)] = [
            (decide(jobs, safety: .batteryLow(percent: 18)), .safetyStop(.batteryLow(percent: 18))),
            (decide(jobs, safety: .tooHot), .safetyStop(.tooHot)),
            (decide(jobs, enabled: false), .switchedOff),
            (decide(jobs, pausedUntil: at(3600)), .paused(until: at(3600))),
        ]
        for (decision, headline) in stops {
            XCTAssertFalse(decision.hold, "\(headline)")
            XCTAssertFalse(decision.lidClosedFlag, "\(headline)")
            XCTAssertEqual(decision.headline, headline)
            XCTAssertEqual(decision.jobHolds, jobs, "It is listed all the same")
        }
    }

    func testItEndsAtTheStartGraceWhenTheJobNeverStarts() {
        XCTAssertTrue(decide([hold()], at: 239).hold)
        let over = decide([hold()], at: 240)
        XCTAssertFalse(over.hold)
        XCTAssertEqual(over.headline, .noAgents)
        XCTAssertEqual(over.jobHolds, [])
    }

    func testItEndsWhenTheProcessIsGone() {
        var seen = hold()
        seen.observe(running: true, now: at(5))
        XCTAssertTrue(decide([seen], at: 600).hold, "A job that runs holds past the start grace")
        seen.observe(running: false, now: at(700))
        XCTAssertFalse(decide([seen], at: 700).hold)
    }

    func testItEndsAtTheCap() {
        var seen = hold()
        seen.observe(running: true, now: at(5))
        XCTAssertTrue(decide([seen], at: -60 + 1799).hold)
        XCTAssertFalse(decide([seen], at: -60 + 1800).hold)
    }

    func testTheLidClosedFlagFollowsTheSameSettingAsForAnAgent() {
        var settings = DetectionSettings()
        settings.stayAwakeLidClosedOnBattery = true
        XCTAssertTrue(decide([hold()], settings: settings).lidClosedFlag)
        XCTAssertEqual(decide([hold()], settings: settings).lidClosedFlag, decide([], readings: [working()], settings: settings).lidClosedFlag)
        settings.stayAwakeLidClosedOnBattery = false
        XCTAssertFalse(decide([hold()], settings: settings).lidClosedFlag)
        XCTAssertTrue(decide([hold()], settings: settings).hold)
    }

    func testAnAgentIsNamedBeforeAJobAndAJobBeforeAHoldFromTheCommandLine() {
        XCTAssertEqual(decide([hold()], readings: [working()]).headline, .working(.one("Claude Code")))
        let manual = ManualHold.timed(id: "aaaa0001", length: 600, reason: "Render", now: at(-10))
        let decision = decide([hold()], holds: [manual])
        XCTAssertEqual(decision.headline, .scheduledJob(.one("backup.sh")))
        XCTAssertEqual(decision.manualHolds, [manual])
    }

    func testTheWordsOfAJobHoldNameNoJobWhereOthersCanReadThem() {
        XCTAssertEqual(HoldHeadline.scheduledJob(.one("backup.sh")).awakeReason, "a scheduled job", "The list of power assertions")
        XCTAssertEqual(HoldHeadline.scheduledJob(.many(3)).text, "Awake: 3 scheduled jobs")
        XCTAssertTrue(HoldHeadline.scheduledJob(.one("a")).keepsAwake)
        XCTAssertFalse(HoldHeadline.scheduledJob(.one("a")).isStop)
        XCTAssertEqual(MenuModel.pose(for: .scheduledJob(.one("a"))), .awake(wisps: 2))
    }

    // MARK: The wake gate

    /// The Mac slept after the word of sleep, and no full wake came.
    private var closedGate: WakeGate {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        gate.sampled(awake: 10, slept: true)
        return gate
    }

    func testTheWindowOfAnAlarm() {
        let window = AlarmWindow(hold())
        XCTAssertEqual(window.alarmAt, at(-60))
        XCTAssertEqual(window.end, at(240), "The start grace after the time of the job")
        XCTAssertFalse(window.contains(at(-91)))
        XCTAssertTrue(window.contains(at(-90)), "30 seconds before the alarm")
        XCTAssertTrue(window.contains(at(239)))
        XCTAssertFalse(window.contains(at(240)))
        var seen = hold()
        seen.observe(running: true, now: at(5))
        XCTAssertEqual(AlarmWindow(seen).end, at(-60 + 1800), "The cap while the job runs")
        seen.observe(running: false, now: at(90))
        XCTAssertEqual(AlarmWindow(seen).end, at(90), "Over with the job")
    }

    func testInsideTheWindowAJobHoldPassesTheClosedGate() {
        let gate = closedGate
        let windows = [AlarmWindow(hold())]
        XCTAssertFalse(gate.allowsHold(holding: false))
        XCTAssertFalse(gate.allowsHold(holding: true))
        XCTAssertTrue(gate.allowsJobHold(holding: false, windows: windows, now: at(-58)))
        XCTAssertTrue(gate.allowsJobHold(holding: true, windows: windows, now: at(200)))
        XCTAssertFalse(gate.allowsJobHold(holding: false, windows: windows, now: at(240)), "Nothing passes after the window")
        XCTAssertFalse(gate.allowsJobHold(holding: true, windows: windows, now: at(-120)), "Nothing passes before it")
        XCTAssertFalse(gate.allowsJobHold(holding: false, windows: [], now: at(0)), "No alarm, no window")
        XCTAssertTrue(WakeGate().allowsJobHold(holding: false, windows: [], now: at(0)), "An open gate needs no window")
    }

    func testAJobHoldStartsBehindTheClosedGateAndAStaleAgentDoesNot() {
        let jobs = [hold()]
        var settings = DetectionSettings()
        settings.stayAwakeLidClosedOnBattery = true
        let inside = decide(jobs, readings: [working()], at: -58, settings: settings, mayHold: false, jobsMayHold: true)
        XCTAssertTrue(inside.hold)
        XCTAssertTrue(inside.lidClosedFlag)
        XCTAssertEqual(inside.headline, .scheduledJob(.one("backup.sh")), "The job is the reason, not the agent")
        XCTAssertEqual(inside.perAgent.map(\.cause), [nil], "What the agent did before the sleep holds nothing")
        let agentOnly = decide([], readings: [working()], at: -58, mayHold: false, jobsMayHold: true)
        XCTAssertFalse(agentOnly.hold, "With no job hold nothing passes")
        let outside = decide(jobs, readings: [working()], at: 240, mayHold: false, jobsMayHold: false)
        XCTAssertFalse(outside.hold)
        XCTAssertFalse(outside.lidClosedFlag)
        let gateOnly = decide(jobs, at: -58, mayHold: false)
        XCTAssertFalse(gateOnly.hold, "A caller that says nothing of the window gets the gate alone")
        XCTAssertEqual(gateOnly.jobHolds, jobs)
    }

    func testAStopBeatsAJobHoldBehindTheClosedGateToo() {
        let decision = decide([hold()], safety: .batteryLow(percent: 12), mayHold: false, jobsMayHold: true)
        XCTAssertFalse(decision.hold)
        XCTAssertEqual(decision.headline, .safetyStop(.batteryLow(percent: 12)))
    }

    // MARK: After the job

    /// "Sleep back" is not in this version: when the hold ends, Agent
    /// Caffeine lets go and asks macOS for nothing. No part of the app
    /// knows a command that puts the Mac to sleep.
    func testNoPartOfTheAppPutsTheMacToSleep() throws {
        var seen = hold()
        seen.observe(running: true, now: at(5))
        seen.observe(running: false, now: at(90))
        let after = decide([seen], at: 91)
        XCTAssertFalse(after.hold)
        XCTAssertEqual(after.headline, .noAgents)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var count = 0
        for folder in ["Caffeinagent", "CaffeinagentHelper", "CaffeinagentCLI", "CaffeinagentHook"] {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                count += 1
                let source = try String(contentsOf: file, encoding: .utf8)
                XCTAssertNil(source.range(of: #"(?<![A-Za-z])sleepnow|IOPMSleepSystem|kIOPMAutoSleep"#, options: .regularExpression), file.lastPathComponent)
            }
        }
        XCTAssertGreaterThan(count, 100)
    }

    // MARK: The recording

    func testTheFrameCarriesTheJobHoldsAndTheAlarmAndAnOldLineHasNone() throws {
        var frame = EvidenceFrame(at: at(0), agents: [])
        frame.jobHolds = [hold()]
        frame.wakeAlarm = at(86_340).timeIntervalSince1970
        let data = try LabFormat.encoder().encode(frame)
        XCTAssertEqual(try LabFormat.decoder().decode(EvidenceFrame.self, from: data), frame)
        let empty = String(decoding: try LabFormat.encoder().encode(EvidenceFrame(at: at(0), agents: [])), as: UTF8.self)
        XCTAssertFalse(empty.contains("jobs"), "A line with no job hold is as it was")
        XCTAssertFalse(empty.contains("alarm"))
        let old = try LabFormat.decoder().decode(EvidenceFrame.self, from: Data(empty.utf8))
        XCTAssertEqual(old.jobHolds, [])
        XCTAssertNil(old.wakeAlarm)
        XCTAssertEqual(EvidenceFrame.currentVersion, 1, "A key that is added needs no new version")
    }

    func testARecordingKeepsNoNameOfAJob() throws {
        var frame = EvidenceFrame(at: at(0), agents: [])
        frame.jobHolds = [hold(.launchd, name: "com.acme-secret.backup"), hold(name: "hunter2.sh")]
        let line = LabFormat.sample(frame: frame, decision: decide(frame.jobHolds), cost: nil)
        XCTAssertEqual(line.frame?.jobHolds.map(\.name), ["launchd", "crontab"])
        XCTAssertEqual(line.frame?.jobHolds.map(\.jobID), ["launchd:1", "crontab:2"])
        XCTAssertEqual(line.frame?.jobHolds.map(\.start), frame.jobHolds.map(\.start), "The times stay")
        XCTAssertEqual(line.hold?.headline, "Awake: 2 scheduled jobs")
        let text = String(decoding: try LabFormat.line(line), as: UTF8.self)
        for word in ["acme", "secret", "hunter2", "backup"] { XCTAssertFalse(text.contains(word), word) }
    }

    /// One night as it is recorded: the alarm is set in the evening, the
    /// Mac sleeps, wakes at the alarm, the job runs for three minutes,
    /// and the Mac can sleep again.
    func testAReplayOfANightHoldsForTheJobAndLetsGoAfterIt() throws {
        let alarm = at(-60).timeIntervalSince1970
        var running = hold()
        var samples: [LabSample] = []
        func add(_ seconds: TimeInterval, awake: TimeInterval, job: JobHold? = nil, alarm: TimeInterval? = nil) {
            var frame = EvidenceFrame(at: at(seconds), agents: [])
            frame.awake = awake
            frame.jobHolds = job.map { [$0] } ?? []
            frame.wakeAlarm = alarm
            samples.append(LabSample(frame: frame))
        }
        add(-5 * 3600, awake: 100, alarm: alarm)
        add(-5 * 3600 + 5, awake: 105, alarm: alarm)
        add(-58, awake: 107, job: running)
        running.observe(running: true, now: at(4))
        add(4, awake: 169, job: running)
        add(150, awake: 315, job: running)
        running.observe(running: false, now: at(180))
        add(180, awake: 345, job: running)
        add(185, awake: 350)
        var recording = LabRecording()
        recording.samples = try samples.map { sample in
            let line = LabFormat.sample(frame: sample.frame, decision: decide(sample.frame.jobHolds, at: sample.frame.at.timeIntervalSince(Self.fire)), cost: nil)
            return try XCTUnwrap(LabFormat.recording(from: String(decoding: LabFormat.line(line), as: UTF8.self)).samples.first)
        }
        let steps = LabReplay.steps(of: recording)
        XCTAssertEqual(steps.map(\.decision.hold), [false, false, true, true, true, false, false])
        XCTAssertEqual(steps[2].decision.headline, .scheduledJob(.one("crontab")), "The name is not in the recording")
        XCTAssertEqual(recording.samples.map(\.frame.wakeAlarm), [alarm, alarm, nil, nil, nil, nil, nil])
        XCTAssertEqual(LabReplay.score(recording).samples, 7)
        for (step, sample) in zip(steps, recording.samples) { XCTAssertEqual(sample.hold?.on, step.decision.hold, "The replay decides as the app did") }
    }
}
