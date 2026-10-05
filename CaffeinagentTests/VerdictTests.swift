import XCTest

final class VerdictTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)
    /// The agent processes started an hour before each story.
    private static let processStart = start.timeIntervalSince1970 - 3600

    private typealias Sample = (seconds: TimeInterval, evidence: AgentEvidence)

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    /// One sample every `step` seconds. `cpu` is percent of one core.
    private func samples(from: TimeInterval = 0, to: TimeInterval, every step: TimeInterval = 5, _ make: (TimeInterval) -> AgentEvidence) -> [Sample] {
        stride(from: from, through: to, by: step).map { ($0, make($0)) }
    }

    private func run(_ samples: [Sample], settings: DetectionSettings = DetectionSettings()) -> [(seconds: TimeInterval, verdict: AgentVerdict)] {
        var memory = AgentMemory()
        return samples.map { sample in
            let (verdict, next) = VerdictRules.verdict(for: sample.evidence, memory: memory, settings: settings, now: at(sample.seconds))
            memory = next
            return (sample.seconds, verdict)
        }
    }

    private func report(_ state: ReportedState, at seconds: TimeInterval, source: StateReport.Source = .claudeSessionFile) -> StateReport {
        StateReport(state: state, since: Self.start.addingTimeInterval(-600), observedAt: at(seconds), source: source, detail: nil)
    }

    private func evidence(
        _ id: String, _ name: String, _ level: AgentDefinition.Level, cpu percent: Double = 0, interval: TimeInterval = 5,
        reported: StateReport? = nil, jobs: Int = 0, commands: Int = 0, busy: Int = 0, fileAt: Date? = nil,
        assertion: Bool = false, hook: ReportedState? = nil, hookAt: Date? = nil
    ) -> AgentEvidence {
        AgentEvidence(
            agentID: id, displayName: name, level: level, pid: 100, startTime: Self.processStart,
            reported: reported, backgroundJobsWorking: jobs, childCommands: commands, busyChildCommands: busy,
            subtreeCPUSeconds: percent / 100 * interval, sampleInterval: interval, fileActivityAt: fileAt,
            ownsSleepAssertion: assertion, hookState: hook, hookStateAt: hookAt
        )
    }

    private func claude(_ state: ReportedState?, at seconds: TimeInterval, cpu: Double = 0.4, commands: Int = 0, busy: Int = 0, jobs: Int = 0) -> AgentEvidence {
        evidence("claude", "Claude Code", .state, cpu: cpu, reported: state.map { report($0, at: seconds) }, jobs: jobs, commands: commands, busy: busy)
    }

    private func opencode(cpu: Double, interval: TimeInterval = 5, commands: Int = 0, busy: Int = 0, fileAt: Date? = nil) -> AgentEvidence {
        evidence("opencode", "opencode", .activity, cpu: cpu, interval: interval, commands: commands, busy: busy, fileAt: fileAt)
    }

    private func verdict(_ state: WorkState, _ confidence: AgentVerdict.Confidence, _ reason: VerdictReason) -> AgentVerdict {
        AgentVerdict(state: state, confidence: confidence, reason: reason)
    }

    // MARK: Reported state

    /// False positive 1: idle Claude sessions reach 3 to 10.7 percent in 2.5
    /// percent of windows, most of them in one 70 second cluster.
    func testIdleClaudeCPUSpikesStayIdle() {
        let story = samples(to: 420) { t in
            self.claude(.idle, at: t, cpu: (100...170).contains(t) || t == 300 ? 10.7 : 0.4)
        }
        for (seconds, got) in run(story) {
            XCTAssertEqual(got, verdict(.idle, .reported, .atPrompt), "at \(seconds) s")
        }
    }

    /// False positive 2: a session that waits for the user spikes too.
    func testWaitingClaudeCPUSpikesStayWaiting() {
        let story = samples(to: 240) { t in self.claude(.waitingForUser, at: t, cpu: t.truncatingRemainder(dividingBy: 20) == 0 ? 5.3 : 0.6) }
        for (seconds, got) in run(story) {
            XCTAssertEqual(got, verdict(.waitingForUser, .reported, .asksPermission), "at \(seconds) s")
        }
    }

    /// False negatives 1 and 2: Codex runs a tool at 1.3 percent and waits
    /// for the model at 0.4, and its rollout says the turn has started.
    func testCodexQuietToolCallIsWorking() {
        let story = samples(to: 34) { t in
            self.evidence("codex", "Codex", .state, cpu: t <= 20 ? 1.3 : 0.4, reported: self.report(.working, at: t, source: .codexRollout), commands: t <= 20 ? 1 : 0)
        }
        for (seconds, got) in run(story) {
            XCTAssertEqual(got, verdict(.working, .reported, .reportsBusy), "at \(seconds) s")
        }
    }

    /// A reported working does not expire by age.
    func testLongSilentToolCallStaysWorking() {
        let story = samples(to: 4 * 3600, every: 60) { t in self.claude(.working, at: t, cpu: 0) }
        let got = run(story)
        XCTAssertEqual(got.count, 241)
        XCTAssertTrue(got.allSatisfy { $0.verdict == verdict(.working, .reported, .reportsBusy) })
    }

    /// Claude Code without a session state file, after an interrupt the
    /// reader did not see, or a crash: the transcript says working for ever.
    func testTranscriptWorkingLapsesWhenTheFileStaysUnwritten() {
        func transcript(_ t: TimeInterval, lastWrite: TimeInterval, busy: Int = 0) -> AgentEvidence {
            let report = StateReport(state: .working, since: at(lastWrite), observedAt: at(t), source: .claudeTranscript, detail: "in a turn")
            return evidence("claude", "Claude Code", .state, cpu: 0.4, reported: report, commands: busy, busy: busy, fileAt: at(lastWrite))
        }
        // Written until 60 s, then silent.
        let story = samples(to: 600) { t in transcript(t, lastWrite: min(t, 60)) }
        for (seconds, got) in run(story) {
            if seconds < 360 {
                XCTAssertEqual(got, verdict(.working, .reported, .reportsBusy), "at \(seconds) s")
            } else {
                XCTAssertEqual(got.state, .idle, "at \(seconds) s")
                XCTAssertEqual(got.confidence, .inferredWeak, "at \(seconds) s")
            }
        }
        // A command that still runs holds after the transcript lapsed.
        let building = samples(to: 600) { t in transcript(t, lastWrite: 0, busy: 1) }
        XCTAssertEqual(run(building).last?.verdict, verdict(.working, .inferredStrong, .runningCommand(1)))
        // A shorter release time lapses sooner.
        var settings = DetectionSettings()
        settings.releaseAfterActivity = 60
        let short = run(samples(to: 100) { t in transcript(t, lastWrite: 0) }, settings: settings)
        XCTAssertEqual(short.first { $0.verdict.state == .idle }?.seconds, 60)
        // A working without a write time is no working.
        let undated = StateReport(state: .working, since: nil, observedAt: at(0), source: .claudeTranscript, detail: nil)
        XCTAssertEqual(run([(0, evidence("claude", "Claude Code", .state, reported: undated))]).first?.verdict.state, .idle)
        // The state file's working does not lapse.
        let stated = samples(to: 3600, every: 60) { t in self.claude(.working, at: t) }
        XCTAssertTrue(run(stated).allSatisfy { $0.verdict == self.verdict(.working, .reported, .reportsBusy) })
    }

    func testUnreadableStateFile() {
        let story: [Sample] = [
            (0, claude(.working, at: 0)),
            (1, claude(nil, at: 1)),
            (2, claude(.working, at: 2)),
            (3, claude(nil, at: 3)),
            (12, claude(nil, at: 12)),
            (13, claude(nil, at: 13)),
            (14, claude(.idle, at: 14)),
        ]
        let want: [AgentVerdict] = [
            verdict(.working, .reported, .reportsBusy),
            verdict(.working, .reported, .reportsBusy),
            verdict(.working, .reported, .reportsBusy),
            verdict(.working, .reported, .reportsBusy),
            verdict(.working, .reported, .reportsBusy),
            // Unknown after 10 seconds: judged by its activity, and there is none.
            verdict(.idle, .inferredWeak, .noActivity(minutes: 0)),
            verdict(.idle, .reported, .atPrompt),
        ]
        XCTAssertEqual(run(story).map(\.verdict), want)
    }

    /// The turn ended, the work did not.
    func testLeftOverWorkAfterIdle() {
        let cases: [(name: String, evidence: AgentEvidence, want: AgentVerdict)] = [
            ("busy build", claude(.idle, at: 0, commands: 2, busy: 1), verdict(.working, .inferredStrong, .runningCommand(1))),
            ("idle dev server", claude(.idle, at: 0, commands: 1, busy: 0), verdict(.idle, .reported, .atPrompt)),
            ("background job", claude(.idle, at: 0, jobs: 2), verdict(.working, .inferredStrong, .backgroundJob(2))),
            ("busy build while it asks", claude(.waitingForUser, at: 0, commands: 1, busy: 1), verdict(.working, .inferredStrong, .runningCommand(1))),
            ("dev server while it asks", claude(.waitingForUser, at: 0, commands: 1), verdict(.waitingForUser, .reported, .asksPermission)),
            ("busy command inside a turn", claude(.working, at: 0, commands: 1, busy: 1), verdict(.working, .reported, .reportsBusy)),
        ]
        for c in cases {
            XCTAssertEqual(run([(0, c.evidence)]).last?.verdict, c.want, c.name)
        }
    }

    func testBuildEndsAfterIdle() {
        let story = samples(to: 60) { t in self.claude(.idle, at: t, cpu: t <= 30 ? 180 : 0.4, commands: 1, busy: t <= 30 ? 1 : 0) }
        for (seconds, got) in run(story) {
            XCTAssertEqual(got.state, seconds <= 30 ? .working : .idle, "at \(seconds) s")
        }
    }

    func testHookState() {
        let cases: [(name: String, hook: ReportedState, age: TimeInterval, reported: ReportedState, want: AgentVerdict)] = [
            ("fresh idle does not beat a reported working", .idle, 5, .working, verdict(.working, .reported, .reportsBusy)),
            ("fresh idle beats a reported wait", .idle, 5, .waitingForUser, verdict(.idle, .reported, .atPrompt)),
            ("fresh working beats an idle state file", .working, 60, .idle, verdict(.working, .reported, .reportsBusy)),
            ("fresh waiting", .waitingForUser, 1, .working, verdict(.waitingForUser, .reported, .asksPermission)),
            ("old hook gives way", .idle, 61, .working, verdict(.working, .reported, .reportsBusy)),
        ]
        for c in cases {
            let sample = evidence("claude", "Claude Code", .state, reported: report(c.reported, at: 100), hook: c.hook, hookAt: at(100 - c.age))
            XCTAssertEqual(run([(100, sample)]).last?.verdict, c.want, c.name)
        }
    }

    /// One Codex engine, threads A and B. A stops and its hook says idle,
    /// B is in a turn. With "An agent finishes" at 30 seconds the Mac was
    /// released while B worked.
    func testHookIdleOfOneThreadDoesNotHideTheWorkOfAnother() {
        var settings = DetectionSettings()
        settings.releaseAfterState = 30
        let story = samples(to: 600) { t in self.codexHook(.idle, hookAt: max(0, t - 5), rollout: .working, at: t) }
        for got in runHeld(story, settings: settings) {
            XCTAssertEqual(got.verdict, verdict(.working, .reported, .reportsBusy), "at \(got.seconds) s")
            XCTAssertTrue(got.hold, "at \(got.seconds) s")
        }
        // With no state of its own, the hook's idle is all there is.
        let droid = evidence("droid", "Droid", .activity, hook: .idle, hookAt: at(95))
        XCTAssertEqual(run([(100, droid)]).last?.verdict, verdict(.idle, .reported, .atPrompt))
    }

    // MARK: Hook wait

    private func codexHook(_ hook: ReportedState, hookAt: TimeInterval, rollout: ReportedState?, at seconds: TimeInterval, writeAt: TimeInterval = -5, busy: Int = 0) -> AgentEvidence {
        let reported = rollout.map { StateReport(state: $0, since: self.at(-10), observedAt: self.at(seconds), source: .codexRollout, detail: nil) }
        return evidence("codex", "Codex", .state, cpu: 0.4, reported: reported, commands: busy, busy: busy, fileAt: at(writeAt), hook: hook, hookAt: at(hookAt))
    }

    /// The verdicts and what the policy makes of them, as the engine does.
    private func runHeld(_ samples: [Sample], settings: DetectionSettings = DetectionSettings()) -> [(seconds: TimeInterval, verdict: AgentVerdict, hold: Bool)] {
        var memory = AgentMemory()
        var policy = PolicyMemory()
        return samples.map { sample in
            let now = at(sample.seconds)
            let (verdict, next) = VerdictRules.verdict(for: sample.evidence, memory: memory, settings: settings, now: now)
            memory = next
            let (decision, nextPolicy) = HoldPolicy.decide(
                readings: [AgentReading(evidence: sample.evidence, verdict: verdict)], memory: policy, mode: .agentWorking, enabled: true,
                entitlement: .licensed, safety: nil, settings: settings, context: FrameContext(), now: now
            )
            policy = nextPolicy
            return (sample.seconds, verdict, decision.hold)
        }
    }

    /// Codex asked for permission and nobody answers. The rollout says "in
    /// a turn" all the time, and the hook's wait is older than a minute.
    func testHookWaitDoesNotAgeOutAndItsHoldEnds() {
        let story = samples(to: 900) { t in self.codexHook(.waitingForUser, hookAt: 0, rollout: .working, at: t) }
        for got in runHeld(story) {
            XCTAssertEqual(got.verdict, verdict(.waitingForUser, .reported, .asksPermission), "at \(got.seconds) s")
            XCTAssertEqual(got.hold, got.seconds < 300, "at \(got.seconds) s")
        }
    }

    /// The user approved, and Codex sends no event until the tool is done.
    func testHookWaitEndsOnARolloutWrite() {
        let story = samples(to: 600) { t in self.codexHook(.waitingForUser, hookAt: 0, rollout: .working, at: t, writeAt: t >= 10 ? 10 : 1) }
        for got in runHeld(story) {
            let want = got.seconds < 10 ? verdict(.waitingForUser, .reported, .asksPermission) : verdict(.working, .reported, .reportsBusy)
            XCTAssertEqual(got.verdict, want, "at \(got.seconds) s")
            XCTAssertTrue(got.hold, "at \(got.seconds) s")
        }
    }

    func testHookWaitEndsOnSignsOfWorkOnly() {
        // A write within the margin is the write of the tool call that asks.
        let near = samples(to: 120) { t in self.codexHook(.waitingForUser, hookAt: 0, rollout: .working, at: t, writeAt: 2) }
        XCTAssertTrue(run(near).allSatisfy { $0.verdict.state == .waitingForUser })
        // A write with no reported working is no sign: the turn may be over.
        let idle = samples(to: 120) { t in self.codexHook(.waitingForUser, hookAt: 0, rollout: .idle, at: t, writeAt: 30) }
        XCTAssertTrue(run(idle).allSatisfy { $0.verdict.state == .waitingForUser })
        // A command that ran once ends the wait, also after it went quiet.
        let command = samples(to: 600) { t in self.codexHook(.waitingForUser, hookAt: 0, rollout: .working, at: t, busy: (20...40).contains(t) ? 1 : 0) }
        for (seconds, got) in run(command) {
            XCTAssertEqual(got.state, seconds < 20 ? .waitingForUser : .working, "at \(seconds) s")
        }
        // A new wait of the same session is a new wait.
        let again = samples(to: 120) { t in
            self.codexHook(.waitingForUser, hookAt: t < 60 ? 0 : 60, rollout: .working, at: t, writeAt: t >= 10 ? 10 : 1)
        }
        for (seconds, got) in run(again) {
            XCTAssertEqual(got.state, (10..<60).contains(seconds) ? .working : .waitingForUser, "at \(seconds) s")
        }
        // The state file of Claude Code turns to busy when the tool starts.
        let claude = samples(to: 120) { t in
            let report = StateReport(state: .working, since: self.at(t < 30 ? -10 : 30), observedAt: self.at(t), source: .claudeSessionFile, detail: nil)
            return self.evidence("claude", "Claude Code", .state, reported: report, hook: .waitingForUser, hookAt: self.at(0))
        }
        for (seconds, got) in run(claude) {
            XCTAssertEqual(got.state, seconds < 30 ? .waitingForUser : .working, "at \(seconds) s")
        }
    }

    /// Droid and opencode have no state of their own. The wait of their
    /// hooks holds for the whole waiting time, not for a minute.
    func testHookWaitOfAnActivityAgentHoldsTheWholeWaitingTime() {
        for (id, level) in [("droid", AgentDefinition.Level.activity), ("opencode", .activity)] {
            let story = samples(to: 600) { t in self.evidence(id, id, level, cpu: 0.4, hook: .waitingForUser, hookAt: self.at(0)) }
            for got in runHeld(story) {
                XCTAssertEqual(got.verdict, verdict(.waitingForUser, .reported, .asksPermission), "\(id) at \(got.seconds) s")
                XCTAssertEqual(got.hold, got.seconds < 300, "\(id) at \(got.seconds) s")
            }
        }
    }

    // MARK: Inferred state

    /// False negative 4: opencode writes its database around a tool call and
    /// is silent for the 20 seconds of the call, at 0.4 to 1.1 percent.
    func testOpencodeQuietToolCallIsHeldByFileWrites() {
        let writes: [TimeInterval] = [1, 3, 7, 12, 13, 16, 36.6, 42, 44]
        let story = samples(to: 400) { t in
            self.opencode(cpu: 0.9, commands: (16...36).contains(t) ? 1 : 0, fileAt: writes.last { $0 <= t }.map(self.at))
        }
        let got = run(story)
        XCTAssertEqual(got[0].verdict, verdict(.idle, .inferredWeak, .noActivity(minutes: 0)))
        XCTAssertEqual(got[1].verdict, verdict(.working, .inferredStrong, .writingSessionFile(secondsAgo: 2)))
        XCTAssertEqual(got[6].verdict, verdict(.working, .inferredStrong, .writingSessionFile(secondsAgo: 14)))
        for (seconds, one) in got.dropFirst() {
            XCTAssertEqual(one.state, seconds < 344 ? .working : .idle, "at \(seconds) s")
        }
        XCTAssertEqual(got.last?.verdict, verdict(.idle, .inferredWeak, .noActivity(minutes: 5)))
    }

    /// opencode streams text at 14 percent with no file write: CPU is the
    /// only sign. It holds for 30 minutes from when it became the only sign,
    /// then reads idle until a strong sign comes back.
    func testWeakOnlyEvidenceIsCapped() {
        var story = samples(to: 2400) { _ in self.opencode(cpu: 14.5) }
        story += samples(from: 2405, to: 2420) { t in self.opencode(cpu: 14.5, fileAt: self.at(2405)) }
        for (seconds, got) in run(story) {
            switch seconds {
            case ..<10:
                XCTAssertEqual(got, verdict(.idle, .inferredWeak, .noActivity(minutes: 0)), "at \(seconds) s")
            case ..<1810:
                XCTAssertEqual(got, verdict(.working, .inferredWeak, .cpuActivity), "at \(seconds) s")
            case ..<2405:
                XCTAssertEqual(got, verdict(.idle, .inferredWeak, .onlyWeakSigns(minutes: 30)), "at \(seconds) s")
            default:
                XCTAssertEqual(got.state, .working, "at \(seconds) s")
                XCTAssertEqual(got.confidence, .inferredStrong, "at \(seconds) s")
            }
        }
    }

    /// The cap does not lift because the CPU went quiet for a while.
    func testWeakCapSurvivesAQuietStretch() {
        var story = samples(to: 1900) { _ in self.opencode(cpu: 14.5) }
        story += samples(from: 1905, to: 2600) { _ in self.opencode(cpu: 0.2) }
        story += samples(from: 2605, to: 2700) { _ in self.opencode(cpu: 14.5) }
        story += [(2705, opencode(cpu: 14.5, commands: 1, busy: 1))]
        let got = run(story)
        XCTAssertTrue(got.filter { $0.seconds >= 1810 && $0.seconds <= 2700 }.allSatisfy { $0.verdict.state == .idle })
        XCTAssertEqual(got.last?.verdict, verdict(.working, .inferredStrong, .runningCommand(1)))
    }

    /// A quiet stretch as long as the cap lifts it: the agent gets a new
    /// count when it starts again.
    func testWeakCapLiftsAfterAQuietStretchAsLongAsTheCap() {
        var story = samples(to: 1900) { _ in self.opencode(cpu: 14.5) }
        story += samples(from: 1905, to: 3800) { _ in self.opencode(cpu: 0.2) }
        story += samples(from: 3805, to: 3900) { _ in self.opencode(cpu: 14.5) }
        let got = run(story)
        XCTAssertTrue(got.filter { $0.seconds >= 1810 && $0.seconds <= 3805 }.allSatisfy { $0.verdict.state == .idle })
        XCTAssertEqual(got.last?.verdict, verdict(.working, .inferredWeak, .cpuActivity))
        // The new count has a cap of its own.
        var settings = DetectionSettings()
        settings.weakEvidenceCap = 600
        var short = samples(to: 700) { _ in self.opencode(cpu: 14.5) }
        short += samples(from: 705, to: 1400) { _ in self.opencode(cpu: 0.2) }
        short += samples(from: 1405, to: 2200) { _ in self.opencode(cpu: 14.5) }
        let again = run(short, settings: settings)
        XCTAssertEqual(again.first { $0.seconds == 1500 }?.verdict.state, .working)
        XCTAssertEqual(again.last?.verdict, verdict(.idle, .inferredWeak, .onlyWeakSigns(minutes: 10)))
    }

    /// A process that spins all the time is never quiet, so its cap stays.
    func testWeakCapNeverLiftsForAProcessThatSpins() {
        let got = run(samples(to: 9000, every: 5) { _ in self.opencode(cpu: 14.5) })
        XCTAssertTrue(got.filter { $0.seconds >= 1810 }.allSatisfy { $0.verdict == self.verdict(.idle, .inferredWeak, .onlyWeakSigns(minutes: 30)) })
        // Once capped, breaks that are shorter than the cap do not add up.
        let bursts = run(samples(to: 9000, every: 5) { t in self.opencode(cpu: t < 1900 || Int(t / 600) % 2 == 0 ? 14.5 : 0.2) })
        XCTAssertTrue(bursts.filter { $0.seconds >= 1810 }.allSatisfy { $0.verdict.state == .idle })
    }

    /// CPU use during work that the agent reports is not "only weak signs".
    /// The cap must not run out behind the report and then call the agent
    /// idle the moment its state file cannot be read.
    /// 60 seconds of CPU use every 365 seconds: each break is a little
    /// longer than the release time. One quiet sample started the count
    /// again, so the cap never came.
    func testWeakCapCountsBurstsWithBreaksJustOverTheReleaseTime() throws {
        let story = samples(to: 4 * 3600) { t in self.opencode(cpu: t.truncatingRemainder(dividingBy: 365) < 60 ? 14.2 : 0.4) }
        let got = run(story)
        let working = got.filter { $0.verdict.state == .working }
        let cap = DetectionSettings().weakEvidenceCap
        XCTAssertGreaterThan(Double(working.count) * 5, cap / 2, "The bursts count as work up to the cap")
        XCTAssertLessThanOrEqual(Double(working.count) * 5, cap + 365)
        XCTAssertLessThanOrEqual(try XCTUnwrap(working.last).seconds, cap + 365)
        XCTAssertEqual(got.last { $0.verdict.reason == .onlyWeakSigns(minutes: 30) }.map { $0.seconds > 3.9 * 3600 }, true, "The cap never lifts")
    }

    func testWeakCapDoesNotCountTimeOfReportedWork() {
        var story = samples(to: 2400) { t in self.claude(.working, at: t, cpu: 14.5) }
        story += samples(from: 2405, to: 2600) { t in self.claude(nil, at: t, cpu: 14.5) }
        let got = run(story)
        XCTAssertTrue(got.filter { $0.seconds <= 2410 }.allSatisfy { $0.verdict == self.verdict(.working, .reported, .reportsBusy) })
        XCTAssertTrue(got.filter { $0.seconds > 2415 }.allSatisfy { $0.verdict == self.verdict(.working, .inferredWeak, .cpuActivity) })
    }

    /// Weak evidence that stops before the cap releases after the release time.
    func testWeakEvidenceReleases() {
        var story = samples(to: 60) { _ in self.opencode(cpu: 14.5) }
        story += samples(from: 65, to: 500) { _ in self.opencode(cpu: 0.4) }
        for (seconds, got) in run(story) where seconds >= 10 {
            // The rule last holds at 75 s, with the windows of 50, 55 and 60 s.
            XCTAssertEqual(got.state, seconds < 375 ? .working : .idle, "at \(seconds) s")
        }
    }

    /// False positive 3: every agent starts with a burst of 48 to 125 percent.
    func testStartUpBurstIsNotWork() {
        let perSecond = samples(to: 120, every: 1) { t in self.opencode(cpu: t < 3 ? 110 : 0.2, interval: 1) }
        XCTAssertTrue(run(perSecond).allSatisfy { $0.verdict.state == .idle })
        let perFiveSeconds = samples(to: 120) { t in self.opencode(cpu: t == 0 ? 60 : 0.2) }
        XCTAssertTrue(run(perFiveSeconds).allSatisfy { $0.verdict.state == .idle })
    }

    /// A lone spike, and two spikes in 30 seconds, are not work for an agent
    /// that is judged by its activity either.
    func testScatteredSpikesAreNotWork() {
        let story = samples(to: 420) { t in self.opencode(cpu: [100, 115, 300].contains(t) ? 10.7 : 0.4) }
        XCTAssertTrue(run(story).allSatisfy { $0.verdict.state == .idle })
    }

    /// False negative 6: busy interactive Claude runs at 2.0 to 3.9 percent,
    /// under the old 3 percent rule in 45 percent of windows. With no state
    /// file to read, the 2 percent rule still catches it.
    func testBusyClaudeWithoutStateFile() {
        let levels = [2.0, 3.9, 2.4, 3.2, 2.1, 2.8]
        let story = samples(to: 120) { t in self.claude(nil, at: t, cpu: levels[Int(t / 5) % levels.count]) }
        for (seconds, got) in run(story) where seconds >= 10 {
            XCTAssertEqual(got, verdict(.working, .inferredWeak, .cpuActivity), "at \(seconds) s")
        }
    }

    func testStrongSigns() {
        let cases: [(name: String, evidence: AgentEvidence, want: AgentVerdict)] = [
            ("busy command", opencode(cpu: 40, commands: 2, busy: 2), verdict(.working, .inferredStrong, .runningCommand(2))),
            ("quiet command", opencode(cpu: 0.5, commands: 1), verdict(.idle, .inferredWeak, .noActivity(minutes: 0))),
            ("own sleep assertion", evidence("claude", "Claude Code", .state, assertion: true), verdict(.working, .inferredStrong, .holdsSleepAssertion)),
            ("file activity report", evidence("opencode", "opencode", .activity, reported: report(.working, at: 0, source: .fileActivity)), verdict(.working, .inferredStrong, .writingSessionFile(secondsAgo: 0))),
            ("write before the process started", opencode(cpu: 0.2, fileAt: Date(timeIntervalSince1970: Self.processStart - 1)), verdict(.idle, .inferredWeak, .noActivity(minutes: 0))),
            ("write 4 minutes ago", opencode(cpu: 0.2, fileAt: at(-240)), verdict(.working, .inferredStrong, .writingSessionFile(secondsAgo: 240))),
            ("write 5 minutes ago", opencode(cpu: 0.2, fileAt: at(-300)), verdict(.idle, .inferredWeak, .noActivity(minutes: 5))),
        ]
        for c in cases {
            XCTAssertEqual(run([(0, c.evidence)]).last?.verdict, c.want, c.name)
        }
    }

    func testCommandThatJustEnded() {
        let story: [Sample] = [(0, opencode(cpu: 40, commands: 1, busy: 1)), (90, opencode(cpu: 0.2)), (300, opencode(cpu: 0.2))]
        XCTAssertEqual(run(story).map(\.verdict), [
            verdict(.working, .inferredStrong, .runningCommand(1)),
            verdict(.working, .inferredStrong, .workedRecently(secondsAgo: 90)),
            verdict(.idle, .inferredWeak, .noActivity(minutes: 5)),
        ])
    }

    func testReleaseAfterActivityIsAdjustable() {
        var settings = DetectionSettings()
        settings.releaseAfterActivity = 60
        let story: [Sample] = [(0, opencode(cpu: 0.2, fileAt: at(0))), (59, opencode(cpu: 0.2, fileAt: at(0))), (60, opencode(cpu: 0.2, fileAt: at(0)))]
        XCTAssertEqual(run(story, settings: settings).map(\.verdict.state), [.working, .working, .idle])
    }

    // MARK: Rules and helpers

    func testPerAgentRules() {
        var settings = DetectionSettings()
        settings.agentRules = ["claude": .ignore, "opencode": .alwaysWorkingWhileOpen, "codex": .automatic]
        XCTAssertEqual(run([(0, claude(.working, at: 0))], settings: settings).last?.verdict, verdict(.idle, .reported, .ignoredByRule))
        XCTAssertEqual(run([(0, opencode(cpu: 0))], settings: settings).last?.verdict, verdict(.working, .reported, .alwaysWorkingByRule))
        let codex = evidence("codex", "Codex", .state, reported: report(.idle, at: 0, source: .codexRollout))
        XCTAssertEqual(run([(0, codex)], settings: settings).last?.verdict, verdict(.idle, .reported, .atPrompt))
    }

    func testBusyChildThreshold() {
        let cases: [(cpuSeconds: Double, interval: TimeInterval, want: Bool)] = [
            (0.03, 5, false),   // 0.6 percent: the busiest idle helper measured
            (0.06, 5, true),    // 1.2 percent
            (4.0, 5, true),     // a build
            (0, 5, false),      // sleep 20
            (1.0, 0, false),    // first sample
        ]
        for c in cases {
            XCTAssertEqual(VerdictRules.isBusyChild(cpuSeconds: c.cpuSeconds, interval: c.interval), c.want, "\(c)")
        }
    }

    func testReadingsDropGoneInstances() {
        let first = opencode(cpu: 0.2, fileAt: at(0))
        var second = claude(.working, at: 0)
        second.pid = 200
        let (readings, memory) = VerdictRules.readings(for: EvidenceFrame(at: at(0), agents: [first, second]), memory: [:], settings: DetectionSettings())
        XCTAssertEqual(readings.map(\.verdict.state), [.working, .working])
        XCTAssertEqual(readings.map(\.identity), [first.identity, second.identity])
        XCTAssertEqual(Set(memory.keys), [first.identity, second.identity])

        let (later, kept) = VerdictRules.readings(for: EvidenceFrame(at: at(5), agents: [second]), memory: memory, settings: DetectionSettings())
        XCTAssertEqual(later.map(\.displayName), ["Claude Code"])
        XCTAssertEqual(Set(kept.keys), [second.identity])
    }

    func testReasonText() {
        let cases: [(reason: VerdictReason, text: String)] = [
            (.reportsBusy, "Working on a task"),
            (.runningCommand(1), "Running 1 command"),
            (.runningCommand(3), "Running 3 commands"),
            (.backgroundJob(1), "Running 1 background task"),
            (.backgroundJob(2), "Running 2 background tasks"),
            (.holdsSleepAssertion, "Asks the Mac to stay awake"),
            (.writingSessionFile(secondsAgo: 14), "Wrote to its session a moment ago"),
            (.writingSessionFile(secondsAgo: 60), "Wrote to its session 1 minute ago"),
            (.writingSessionFile(secondsAgo: 250), "Wrote to its session 4 minutes ago"),
            (.workedRecently(secondsAgo: 5), "Worked a moment ago"),
            (.workedRecently(secondsAgo: 130), "Worked 2 minutes ago"),
            (.cpuActivity, "Uses the processor"),
            (.asksPermission, "Waits for your answer"),
            (.atPrompt, "Ready for your next message"),
            (.noActivity(minutes: 0), "No activity"),
            (.noActivity(minutes: 1), "No activity for 1 minute"),
            (.noActivity(minutes: 45), "No activity for 45 minutes"),
            (.onlyWeakSigns(minutes: 30), "No clear sign of work for 30 minutes"),
            (.alwaysWorkingByRule, "Counts as working while it is open"),
            (.ignoredByRule, "Ignored by agent caffeine"),
        ]
        for c in cases {
            XCTAssertEqual(c.reason.text, c.text)
            XCTAssertFalse(c.text.contains("\u{2014}"))
        }
    }

    // MARK: Codable

    func testEvidenceFrameRoundTrip() throws {
        let full = AgentEvidence(
            agentID: "codex-desktop", displayName: "Codex", level: .state, kind: .desktop, role: .engine, pid: 25445, startTime: Self.processStart + 0.25,
            reported: StateReport(state: .waitingForUser, since: at(-30), observedAt: at(0), source: .codexRollout, detail: "waiting for you"),
            backgroundJobsWorking: 1, childCommands: 4, busyChildCommands: 2, subtreeCPUSeconds: 0.125, sampleInterval: 1,
            energyNanojoules: 9_000_000, logicalWriteBytes: 4096, fileActivityAt: at(-2), ownsSleepAssertion: true,
            hasLiveSession: true, hookState: .working, hookStateAt: at(-1)
        )
        let frame = EvidenceFrame(
            at: at(0), agents: [full, opencode(cpu: 0)],
            context: FrameContext(onBattery: true, batteryPercent: 64, lidClosed: true, thermalState: ProcessInfo.ThermalState.fair.rawValue, remoteAccessDetected: true)
        )
        let data = try JSONEncoder().encode(frame)
        XCTAssertEqual(try JSONDecoder().decode(EvidenceFrame.self, from: data), frame)
    }

    func testDefaultsAreLeftOutOfTheLog() throws {
        let frame = EvidenceFrame(at: at(0), agents: [evidence("opencode", "opencode", .activity, interval: 0)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any])
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual((object["ctx"] as? [String: Any])?.count, 0)
        let agent = try XCTUnwrap((object["agents"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(agent.keys), ["id", "name", "level", "pid", "start"])
        XCTAssertEqual(agent["level"] as? String, "activity")
    }

    func testFrameWithoutOptionalFieldsDecodes() throws {
        let json = #"{"at":812892800,"agents":[{"id":"claude","name":"Claude Code","level":"state","pid":42,"start":1791196400}]}"#
        let frame = try JSONDecoder().decode(EvidenceFrame.self, from: Data(json.utf8))
        XCTAssertEqual(frame.version, 1)
        XCTAssertEqual(frame.at, Self.start)
        XCTAssertEqual(frame.context, FrameContext())
        XCTAssertEqual(frame.agents, [AgentEvidence(agentID: "claude", displayName: "Claude Code", level: .state, pid: 42, startTime: Self.processStart)])
        XCTAssertNil(frame.agents.first?.cpuFraction)

        let withState = #"{"v":1,"at":812892800,"ctx":{"bat":true,"pct":18},"agents":[{"id":"claude","name":"Claude Code","level":"state","pid":42,"start":1791196400,"cpu":0.1,"dt":5,"rep":{"state":"waiting","seen":812892800,"source":"claudeSession"}}]}"#
        let second = try JSONDecoder().decode(EvidenceFrame.self, from: Data(withState.utf8))
        XCTAssertEqual(second.agents.first?.reported, StateReport(state: .waitingForUser, since: nil, observedAt: Self.start, source: .claudeSessionFile, detail: nil))
        XCTAssertEqual(second.agents.first?.cpuFraction ?? 0, 0.02, accuracy: 1e-9)
        XCTAssertEqual(second.agents.first?.reportAge(at: at(3)), 3)
        XCTAssertEqual(second.context.safetyInputs, SafetyInputs(batteryPercent: 18, onBattery: true, thermalState: .nominal))

        XCTAssertThrowsError(try JSONDecoder().decode(EvidenceFrame.self, from: Data(#"{"at":0,"agents":[{"id":"x","name":"x","level":"psychic","pid":1,"start":0}]}"#.utf8)))
    }

    func testSettingsDefaultsAndRoundTrip() throws {
        let defaults = DetectionSettings()
        XCTAssertEqual(defaults.releaseAfterState, 120)
        XCTAssertEqual(defaults.releaseAfterActivity, 300)
        XCTAssertEqual(defaults.waitingHold, 300)
        XCTAssertEqual(defaults.weakEvidenceCap, 1800)
        XCTAssertEqual(defaults.batteryFloorPercent, 20)
        XCTAssertTrue(defaults.stayAwakeLidClosedOnBattery)
        XCTAssertEqual(defaults.rule(for: "claude"), .automatic)

        var changed = DetectionSettings()
        changed.waitingHold = 60
        changed.agentRules = ["opencode": .ignore]
        changed.userAgentNames = ["my-agent"]
        XCTAssertEqual(try JSONDecoder().decode(DetectionSettings.self, from: JSONEncoder().encode(changed)), changed)

        let old = try JSONDecoder().decode(DetectionSettings.self, from: Data(#"{"releaseAfterState":90}"#.utf8))
        var want = DetectionSettings()
        want.releaseAfterState = 90
        XCTAssertEqual(old, want)
    }
}
