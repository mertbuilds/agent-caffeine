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

    // MARK: Background commands after the turn (Claude Code's `shell`)

    /// Claude Code with `status: "shell"` since `since`: the turn is over
    /// and the session says that background commands still run.
    private func shell(at seconds: TimeInterval, since: TimeInterval, commands: Int = 1, busy: Int = 0) -> AgentEvidence {
        let report = StateReport(state: .idle, since: at(since), observedAt: at(seconds), source: .claudeSessionFile, detail: nil, backgroundWork: true)
        return evidence("claude", "Claude Code", .state, cpu: busy > 0 ? 180 : 0.4, reported: report, commands: commands, busy: busy)
    }

    func testShellWithABusyCommandIsWorking() {
        let story = samples(to: 3600, every: 60) { t in self.shell(at: t, since: 0, busy: 1) }
        XCTAssertTrue(run(story).allSatisfy { $0.verdict == self.verdict(.working, .inferredStrong, .runningCommand(1)) })
    }

    /// The release time after the turn, for a command that is quiet
    /// between two steps. Then the session is idle.
    func testShellWithAQuietCommandSettlesAndGoesIdle() {
        // The second story: the only children are the MCP servers of the session.
        for commands in [1, 3] {
            let story = samples(to: 900) { t in self.shell(at: t, since: 0, commands: commands) }
            for (seconds, got) in run(story) {
                let want = seconds < 300 ? verdict(.working, .reported, .backgroundWork) : verdict(.idle, .reported, .backgroundIdle(minutes: Int(seconds / 60)))
                XCTAssertEqual(got, want, "\(commands) commands at \(seconds) s")
            }
        }
        var settings = DetectionSettings()
        settings.releaseAfterActivity = 60
        let short = run(samples(to: 100) { t in self.shell(at: t, since: 0) }, settings: settings)
        XCTAssertEqual(short.first { $0.verdict.state == .idle }?.seconds, 60)
    }

    /// A build that wakes up holds again, and for the release time after it.
    func testShellIsWorkingAgainWhenACommandIsBusyAgain() {
        let story = samples(to: 1000) { t in self.shell(at: t, since: 0, busy: (600..<700).contains(t) ? 1 : 0) }
        for (seconds, got) in run(story) {
            switch seconds {
            case ..<300: XCTAssertEqual(got, verdict(.working, .reported, .backgroundWork), "at \(seconds) s")
            case ..<600: XCTAssertEqual(got.state, .idle, "at \(seconds) s")
            case ..<700: XCTAssertEqual(got, verdict(.working, .inferredStrong, .runningCommand(1)), "at \(seconds) s")
            // The last busy sample is the one at 695 s.
            case ..<995: XCTAssertEqual(got, verdict(.working, .reported, .backgroundWork), "at \(seconds) s")
            default: XCTAssertEqual(got, verdict(.idle, .reported, .backgroundIdle(minutes: 5)), "at \(seconds) s")
            }
        }
    }

    /// The night of 2026-10-10: `shell` for 13 hours, for a dev server at
    /// 0.0 percent CPU. Idle from the first sample.
    func testShellThatIsHoursOldWithAQuietCommandIsIdleAtOnce() {
        let story = samples(to: 600) { t in self.shell(at: t, since: -13 * 3600, commands: 4) }
        for (seconds, got) in run(story) {
            XCTAssertEqual(got, verdict(.idle, .reported, .backgroundIdle(minutes: Int((13 * 3600 + seconds) / 60))), "at \(seconds) s")
        }
    }

    /// `busy` has no such limit: a long turn does not write the file again.
    func testBusyWithAnOldStatusTimeStaysWorking() {
        let story = samples(to: 3600, every: 60) { t in
            self.evidence("claude", "Claude Code", .state, cpu: 0, reported: StateReport(
                state: .working, since: self.at(-13 * 3600), observedAt: self.at(t), source: .claudeSessionFile, detail: nil
            ), commands: 4)
        }
        XCTAssertTrue(run(story).allSatisfy { $0.verdict == self.verdict(.working, .reported, .reportsBusy) })
    }

    /// A status with no time counts from when the session was first seen.
    func testShellWithoutATimeSettlesFromTheFirstSample() {
        let story = samples(to: 400) { t in
            var evidence = self.shell(at: t, since: 0)
            evidence.reported?.since = nil
            return evidence
        }
        XCTAssertEqual(run(story).first { $0.verdict.state == .idle }?.seconds, 300)
    }

    /// A new prompt: the hook says working before the file does.
    func testAFreshHookWorkingBeatsShell() {
        var prompt = shell(at: 400, since: 0)
        prompt.hookState = .working
        prompt.hookStateAt = at(398)
        XCTAssertEqual(run([(400, prompt)]).last?.verdict, verdict(.working, .reported, .reportsBusy))
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

    /// A turn that fails at once, and an interrupt, send no hook event for
    /// their end. The agent's own idle that is newer than the hook's
    /// working counts at once. An older one is a file that lags behind a
    /// new prompt, and the hook's working stands.
    func testAReportedIdleThatIsNewerThanAFreshHookWorkingCounts() {
        let working = verdict(.working, .reported, .reportsBusy), idle = verdict(.idle, .reported, .atPrompt)
        let agents: [(id: String, source: StateReport.Source)] = [("claude", .claudeSessionFile), ("codex", .codexRollout), ("cursor-desktop", .cursorTranscript)]
        let cases: [(name: String, hookAt: TimeInterval, endedAt: TimeInterval?, bySession: Bool, want: AgentVerdict)] = [
            ("the end is newer", 90, 91, false, idle),
            ("the end is newer by a moment", 90, 90.001, false, idle),
            ("the end is older: the file lags behind the prompt", 90, 84, false, working),
            ("the same time: the hook's working stands", 90, 90, false, working),
            ("an end with no time", 90, nil, false, working),
            ("an end from ahead of the clock", 90, 200, false, working),
            ("compared session by session already", 90, 91, true, working),
        ]
        for agent in agents {
            for c in cases {
                var report = StateReport(state: .idle, since: c.endedAt.map(at), observedAt: at(100), source: agent.source, detail: nil)
                var sample = evidence(agent.id, agent.id, .state, reported: report, hook: .working, hookAt: at(c.hookAt))
                sample.hookStateBySession = c.bySession
                XCTAssertEqual(run([(100, sample)]).last?.verdict, c.want, "\(agent.id): \(c.name)")
                // A command of the turn that ended still holds.
                sample.busyChildCommands = 1
                XCTAssertEqual(run([(100, sample)]).last?.verdict.state, .working, "\(agent.id): \(c.name)")
                // The own state says working or waiting: the hook's working stands.
                for state in [ReportedState.working, .waitingForUser] {
                    report.state = state
                    let other = evidence(agent.id, agent.id, .state, reported: report, hook: .working, hookAt: at(c.hookAt))
                    XCTAssertEqual(run([(100, other)]).last?.verdict, working, "\(agent.id): \(c.name), \(state)")
                }
            }
        }
        // An agent with no state of its own has no such report.
        let droid = evidence("droid", "Droid", .activity, reported: StateReport(state: .idle, since: at(91), observedAt: at(100), source: .fileActivity, detail: nil), hook: .working, hookAt: at(90))
        XCTAssertEqual(run([(100, droid)]).last?.verdict, working)
    }

    /// Claude Code and Codex over time: the prompt at 10 s, the own state
    /// follows 2 seconds later, the turn is interrupted at 40 s and no
    /// Stop comes. The hook's working held for a minute more.
    func testAnInterruptedTurnEndsWithTheAgentsOwnIdle() {
        for (id, source) in [("claude", StateReport.Source.claudeSessionFile), ("codex", .codexRollout)] {
            let story = samples(to: 120, every: 1) { t in
                let own: (ReportedState, TimeInterval) = t < 12 ? (.idle, -600) : t < 40 ? (.working, 12) : (.idle, 40)
                let report = StateReport(state: own.0, since: self.at(own.1), observedAt: self.at(t), source: source, detail: nil)
                return self.evidence(id, id, .state, interval: 1, reported: report, hook: t < 10 ? nil : .working, hookAt: t < 10 ? nil : self.at(min(t, 39)))
            }
            for (seconds, got) in run(story) {
                XCTAssertEqual(got.state, (10..<40).contains(seconds) ? .working : .idle, "\(id) at \(seconds) s")
            }
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

    /// A hook state from ahead of the clock was written before the clock
    /// was set back. A stuck idle of that kind beat the reported working.
    func testHookStateFromAheadOfTheClockIsNotUsed() {
        for hook in [ReportedState.idle, .waitingForUser, .working] {
            let ahead = evidence("droid", "Droid", .activity, hook: hook, hookAt: at(3700))
            XCTAssertEqual(run([(100, ahead)]).last?.verdict, verdict(.idle, .inferredWeak, .noActivity(minutes: 0)), "\(hook)")
        }
        let waiting = evidence("claude", "Claude Code", .state, reported: report(.working, at: 100), hook: .waitingForUser, hookAt: at(3700))
        XCTAssertEqual(run([(100, waiting)]).last?.verdict, verdict(.working, .reported, .reportsBusy))
        let near = evidence("droid", "Droid", .activity, hook: .waitingForUser, hookAt: at(104))
        XCTAssertEqual(run([(100, near)]).last?.verdict.state, .waitingForUser, "A few seconds ahead is no step")
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

    // MARK: Hook working of an agent with no state of its own

    /// An agent that speaks through its hooks only. `events` are the hook
    /// events of its one session, as (second, state).
    private func hooked(_ id: String, at seconds: TimeInterval, events: [(TimeInterval, ReportedState)], fileAt: TimeInterval? = nil, busy: Int = 0, cpu: Double = 0.4) -> AgentEvidence {
        let last = events.last { $0.0 <= seconds }
        return evidence(id, id, .activity, cpu: cpu, interval: 2, commands: busy, busy: busy, fileAt: fileAt.map(at), hook: last?.1, hookAt: last.map { at($0.0) })
    }

    /// What the notifications tell over a timeline of one agent.
    private func told(_ samples: [Sample]) -> [String] {
        let recording = LabRecording(samples: samples.map { LabSample(frame: EvidenceFrame(at: at($0.seconds), agents: [$0.evidence])) })
        return LabNotices.lines(recording).filter { $0.contains(" fired pid ") }
    }

    /// Droid: PreToolUse at 10 s, a tool that is silent until 300 s, Stop
    /// at 310 s. The Mac was released at 72 s, and "finished" was told at
    /// 74 s and again at 312 s.
    func testDroidQuietToolCallIsHeldUntilItsStop() {
        let story = samples(to: 400, every: 2) { t in self.hooked("droid", at: t, events: [(10, .working), (310, .idle)]) }
        for got in runHeld(story) {
            if got.seconds < 10 {
                XCTAssertEqual(got.verdict.state, .idle, "at \(got.seconds) s")
            } else if got.seconds < 310 {
                XCTAssertEqual(got.verdict, verdict(.working, .reported, .reportsBusy), "at \(got.seconds) s")
            } else if got.seconds <= 370 {
                XCTAssertEqual(got.verdict, verdict(.idle, .reported, .atPrompt), "at \(got.seconds) s")
            } else {
                XCTAssertEqual(got.verdict.state, .idle, "at \(got.seconds) s")
            }
            XCTAssertEqual(got.hold, (10..<310).contains(got.seconds), "at \(got.seconds) s")
        }
        let told = told(story)
        XCTAssertEqual(told.count, 1, "\(told)")
        XCTAssertTrue(told.first?.contains("312.0 s    finished fired pid 100 after 300 s") ?? false, "\(told)")
    }

    /// opencode with its plugin: `session.busy` at 10 s, database writes
    /// until 20 s, then a tool that is silent until `session.idle` at 710
    /// s. The writes alone held it until 320 s.
    func testOpencodeQuietToolCallIsHeldUntilItsIdleEvent() {
        let story = samples(to: 800, every: 2) { t in
            self.hooked("opencode", at: t, events: [(10, .working), (710, .idle)], fileAt: t < 10 ? nil : min(t, 20))
        }
        for got in runHeld(story) {
            XCTAssertEqual(got.verdict.state, (10..<710).contains(got.seconds) ? .working : .idle, "at \(got.seconds) s")
            XCTAssertEqual(got.hold, (10..<710).contains(got.seconds), "at \(got.seconds) s")
        }
        let told = told(story)
        XCTAssertEqual(told.count, 1, "\(told)")
        XCTAssertTrue(told.first?.contains("712.0 s    finished fired pid 100 after 700 s") ?? false, "\(told)")
    }

    /// Pi with its extension, as the hook command records it:
    /// `session_start` when Pi opens, `agent_start` and
    /// `tool_execution_start` at 10 s, a tool that is silent for 400 s,
    /// `tool_execution_end` and `agent_settled` at 410 s. Pi has no state
    /// of its own, so the working of its hooks holds for the whole call.
    func testPiQuietToolCallIsHeldUntilItSettles() throws {
        var file = HookStateFile(agent: "pi", pid: 100, start: Self.processStart)
        let turn: [(TimeInterval, String, Int)] = [
            (0, "session_start", 1), (10, "agent_start", 2), (10, "turn_start", 3), (10, "tool_execution_start", 4),
            (410, "tool_execution_end", 5), (410, "turn_start", 6), (410, "agent_settled", 7),
        ]
        var story: [Sample] = []
        for t in stride(from: 0.0, through: 500, by: 2) {
            for (second, event, seq) in turn where second == t {
                let action = HookEvents.action(agent: "pi", event: event, notificationType: nil, isSubagent: false)
                file.apply(action, session: "s", event: event, at: at(second), stamp: HookStamp(ts: second * 1000, seq: seq))
            }
            let summary = try XCTUnwrap(file.summary(now: at(t), freshness: VerdictRules.hookFreshness, workingLimit: VerdictRules.hookWorkingLimit))
            story.append((t, evidence("pi", "Pi", .activity, cpu: 0.4, interval: 2, hook: summary.state, hookAt: summary.at)))
        }
        XCTAssertEqual(AgentCatalog.standard.definitions.first { $0.id == "pi" }?.level, .activity, "The hooks are all Pi says about itself")
        for got in runHeld(story) {
            if (10..<410).contains(got.seconds) {
                XCTAssertEqual(got.verdict, verdict(.working, .reported, .reportsBusy), "at \(got.seconds) s")
            } else {
                XCTAssertEqual(got.verdict.state, .idle, "at \(got.seconds) s")
            }
            XCTAssertEqual(got.hold, (10..<410).contains(got.seconds), "at \(got.seconds) s")
        }
        let told = told(story)
        XCTAssertEqual(told.count, 1, "\(told)")
        XCTAssertTrue(told.first?.contains("412.0 s    finished fired pid 100 after 400 s") ?? false, "\(told)")
    }

    /// The Stop never arrives. The hook's working holds for
    /// `hookWorkingLimit`, and then the signs of activity decide. The turn
    /// stays open, so nothing is told early.
    func testALostStopHoldsForTheLimitAndNoLonger() {
        XCTAssertEqual(VerdictRules.hookWorkingLimit, 1800)
        for id in ["droid", "opencode"] {
            let story = samples(to: 3 * 3600, every: 10) { t in self.hooked(id, at: t, events: [(10, .working)]) }
            for got in runHeld(story) {
                XCTAssertEqual(got.hold, (10..<1810).contains(got.seconds), "\(id) at \(got.seconds) s")
                if got.seconds >= 1810 { XCTAssertEqual(got.verdict.confidence, .inferredWeak, "\(id) at \(got.seconds) s") }
            }
            XCTAssertEqual(told(story), [], id)
            var memory = AgentMemory()
            for sample in story {
                let frame = EvidenceFrame(at: at(sample.seconds), agents: [sample.evidence])
                let (readings, next) = VerdictRules.readings(for: frame, memory: [sample.evidence.identity: memory], settings: DetectionSettings())
                memory = next[sample.evidence.identity] ?? AgentMemory()
                if sample.seconds >= 10 { XCTAssertEqual(readings[0].turn, AgentTurn(state: .working), "\(id) at \(sample.seconds) s") }
            }
        }
    }

    /// After the limit a command that is busy still holds, as for an
    /// agent with no hooks, and each new event starts the limit again.
    func testAfterTheLimitTheSignsOfActivityDecide() {
        let build = samples(to: 4000, every: 10) { t in self.hooked("droid", at: t, events: [(10, .working)], busy: t < 3000 ? 1 : 0) }
        for got in runHeld(build) where got.seconds >= 10 {
            XCTAssertEqual(got.hold, got.seconds < 3290, "at \(got.seconds) s")
        }
        let events = stride(from: 10.0, through: 6000, by: 600).map { ($0, ReportedState.working) }
        let steady = samples(to: 6000, every: 10) { t in self.hooked("droid", at: t, events: events) }
        for got in runHeld(steady) where got.seconds >= 10 {
            XCTAssertEqual(got.verdict, verdict(.working, .reported, .reportsBusy), "at \(got.seconds) s")
        }
    }

    /// The Mac slept for two hours in the middle of the tool call. The
    /// time of the sleep counts for no limit.
    func testTheLimitDoesNotRunWhileTheMacSleeps() {
        var memory = AgentMemory()
        var state = WorkState.idle
        for (seconds, hole) in [(10.0, 0.0), (20, 0), (7220, 7200), (7230, 0), (9030, 0)] {
            if hole > 0 { memory = memory.shifted(by: hole) }
            let sample = hooked("droid", at: seconds, events: [(10, .working)])
            let (verdict, next) = VerdictRules.verdict(for: sample, memory: memory, settings: DetectionSettings(), now: at(seconds))
            memory = next
            state = verdict.state
            XCTAssertEqual(state, seconds < 9010 ? .working : .idle, "at \(seconds) s")
        }
    }

    // MARK: Hook idle of an agent with no state of its own

    /// Measured on 2026-10-07 with opencode 1.18.16 and its plugin: one
    /// turn, `session.busy` at 1 s, `session.idle` and the last database
    /// write at 54 s, no command, and the idle TUI at a steady 2 percent.
    /// The hook idle was dropped at 114 s, the CPU rule took over, and at
    /// 720 s the panel said "Working for 11 minutes".
    func testIdleOpencodeTUIThatUsesTheCPUStaysIdle() {
        for id in ["opencode", "droid"] {
            let story = samples(to: 900, every: 2) { t in
                self.hooked(id, at: t, events: [(1, .working), (54, .idle), (800, .working)], fileAt: t < 1 ? nil : min(t, 54), cpu: 2.0)
            }
            for got in runHeld(story) {
                if (2..<54).contains(got.seconds) || got.seconds >= 800 {
                    XCTAssertEqual(got.verdict, verdict(.working, .reported, .reportsBusy), "\(id) at \(got.seconds) s")
                } else if got.seconds >= 54 {
                    XCTAssertEqual(got.verdict, verdict(.idle, .reported, .atPrompt), "\(id) at \(got.seconds) s")
                }
                XCTAssertEqual(got.hold, (2..<54).contains(got.seconds) || got.seconds >= 800, "\(id) at \(got.seconds) s")
            }
            let told = told(story.filter { $0.seconds < 800 })
            XCTAssertEqual(told.count, 1, "\(told)")
        }
    }

    /// The same story with the hooks off: the CPU rule decides as before.
    /// The write holds until 354 s, then the CPU alone for the cap.
    func testWithoutHooksTheCPUOfTheIdleTUIDecidesAsBefore() {
        let story = samples(to: 2700, every: 2) { t in self.hooked("opencode", at: t, events: [], fileAt: t < 1 ? nil : min(t, 54), cpu: 2.0) }
        for got in runHeld(story) where got.seconds >= 2 {
            XCTAssertEqual(got.hold, got.seconds < 2154, "at \(got.seconds) s")
            if got.seconds >= 354 {
                let want = got.seconds < 2154 ? verdict(.working, .inferredWeak, .cpuActivity) : verdict(.idle, .inferredWeak, .onlyWeakSigns(minutes: 30))
                XCTAssertEqual(got.verdict, want, "at \(got.seconds) s")
            }
        }
    }

    /// A command the agent started runs on after the turn: it holds while
    /// it is busy and for the release time after, as it did. The CPU of
    /// the TUI holds nothing after that.
    func testACommandThatOutlivesTheTurnHoldsAfterAHookIdle() {
        let story = samples(to: 900, every: 2) { t in
            self.hooked("opencode", at: t, events: [(0, .working), (30, .idle)], fileAt: min(t, 30), busy: (20..<150).contains(t) ? 1 : 0, cpu: 2.0)
        }
        for got in runHeld(story) {
            switch got.seconds {
            case ..<30: XCTAssertEqual(got.verdict, verdict(.working, .reported, .reportsBusy), "at \(got.seconds) s")
            case ..<150: XCTAssertEqual(got.verdict, verdict(.working, .inferredStrong, .runningCommand(1)), "at \(got.seconds) s")
            case ..<448: XCTAssertEqual(got.verdict, verdict(.working, .inferredStrong, .workedRecently(secondsAgo: Int(got.seconds - 148))), "at \(got.seconds) s")
            default: XCTAssertEqual(got.verdict, verdict(.idle, .reported, .atPrompt), "at \(got.seconds) s")
            }
            XCTAssertEqual(got.hold, got.seconds < 448, "at \(got.seconds) s")
        }
        XCTAssertEqual(told(story).count, 1)
        // A command that ends with the turn leaves no hold behind.
        let ended = samples(to: 400, every: 2) { t in
            self.hooked("droid", at: t, events: [(0, .working), (30, .idle)], busy: t < 36 ? 1 : 0, cpu: 2.0)
        }
        for got in runHeld(ended) {
            XCTAssertEqual(got.hold, got.seconds < 36, "at \(got.seconds) s")
        }
    }

    /// opencode writes its database when it stops. A write that close to
    /// the idle is the turn that ended. A later one is work with no event,
    /// and holds for the release time, as for opencode with no hooks.
    func testADatabaseWriteAfterAHookIdle() {
        XCTAssertEqual(VerdictRules.hookIdleMargin, 10)
        let atTheStop = samples(to: 720, every: 2) { t in
            self.hooked("opencode", at: t, events: [(1, .working), (54, .idle)], fileAt: t < 1 ? nil : min(t, 64), cpu: 2.0)
        }
        XCTAssertTrue(runHeld(atTheStop).allSatisfy { $0.hold == (2..<54).contains($0.seconds) })
        let later = samples(to: 900, every: 2) { t in
            self.hooked("opencode", at: t, events: [(1, .working), (54, .idle)], fileAt: t < 200 ? min(t, 54) : 200, cpu: 2.0)
        }
        for got in runHeld(later) where got.seconds >= 54 {
            if (200..<500).contains(got.seconds) {
                XCTAssertEqual(got.verdict, verdict(.working, .inferredStrong, .writingSessionFile(secondsAgo: Int(got.seconds - 200))), "at \(got.seconds) s")
            } else {
                XCTAssertEqual(got.verdict, verdict(.idle, .reported, .atPrompt), "at \(got.seconds) s")
            }
            XCTAssertEqual(got.hold, (200..<500).contains(got.seconds), "at \(got.seconds) s")
        }
    }

    /// One process, two sessions: the idle of one does not hide the other
    /// that works, within `hookWorkingLimit`.
    func testAHookIdleDoesNotHideAWorkingSessionOfTheSameProcess() throws {
        var file = HookStateFile(agent: "opencode", pid: 100, start: Self.processStart)
        file.apply(.set(.working), session: "a", event: "session.busy", at: at(1))
        file.apply(.set(.working), session: "b", event: "session.busy", at: at(2))
        file.apply(.set(.idle), session: "b", event: "session.idle", at: at(54))
        func sample(_ t: TimeInterval) throws -> AgentEvidence {
            let summary = try XCTUnwrap(file.summary(now: at(t), freshness: VerdictRules.hookFreshness, workingLimit: VerdictRules.hookWorkingLimit))
            return evidence("opencode", "opencode", .activity, cpu: 2.0, interval: 2, hook: summary.state, hookAt: summary.at)
        }
        let story = try stride(from: 54.0, through: 720, by: 2).map { (seconds: $0, evidence: try sample($0)) }
        for got in runHeld(story) {
            XCTAssertEqual(got.verdict, verdict(.working, .reported, .reportsBusy), "at \(got.seconds) s")
            XCTAssertTrue(got.hold, "at \(got.seconds) s")
        }
        file.apply(.set(.idle), session: "a", event: "session.idle", at: at(730))
        let ended = try stride(from: 730.0, through: 1500, by: 2).map { (seconds: $0, evidence: try sample($0)) }
        XCTAssertTrue(runHeld(ended).allSatisfy { $0.verdict == self.verdict(.idle, .reported, .atPrompt) && !$0.hold })
    }

    /// The Mac slept for two hours after the turn. The idle stands, and
    /// the write of the stop is no new work because the memory moved.
    func testAHookIdleFromBeforeASleepStands() {
        var memory = AgentMemory()
        for (seconds, hole) in [(52.0, 0.0), (54, 0), (56, 0), (7256, 7200), (7258, 0), (7400, 0)] {
            if hole > 0 { memory = memory.shifted(by: hole) }
            let sample = hooked("opencode", at: seconds, events: [(1, .working), (54, .idle)], fileAt: min(seconds, 54), cpu: 2.0)
            let (got, next) = VerdictRules.verdict(for: sample, memory: memory, settings: DetectionSettings(), now: at(seconds))
            memory = next
            XCTAssertEqual(got, seconds < 54 ? verdict(.working, .reported, .reportsBusy) : verdict(.idle, .reported, .atPrompt), "at \(seconds) s")
        }
    }

    /// The wait of a hook, and an agent with a state of its own, are as
    /// they were: an old hook idle of Claude Code or Codex decides nothing.
    func testAnOldHookIdleOfAnAgentWithItsOwnStateDecidesNothing() {
        for (id, source) in [("claude", StateReport.Source.claudeSessionFile), ("codex", .codexRollout)] {
            let working = samples(to: 600) { t in
                self.evidence(id, id, .state, cpu: 2.0, reported: self.report(.working, at: t, source: source), hook: .idle, hookAt: self.at(0))
            }
            XCTAssertTrue(run(working).allSatisfy { $0.verdict == self.verdict(.working, .reported, .reportsBusy) }, id)
            let silent = samples(to: 600) { t in self.evidence(id, id, .state, cpu: 2.0, hook: .idle, hookAt: self.at(0)) }
            for (seconds, got) in run(silent) where seconds > 60 {
                XCTAssertEqual(got, verdict(.working, .inferredWeak, .cpuActivity), "\(id) at \(seconds) s")
            }
        }
        let waits = samples(to: 600, every: 2) { t in self.hooked("opencode", at: t, events: [(0, .waitingForUser)], cpu: 2.0) }
        for got in runHeld(waits) {
            XCTAssertEqual(got.verdict, verdict(.waitingForUser, .reported, .asksPermission), "at \(got.seconds) s")
            XCTAssertEqual(got.hold, got.seconds < 300, "at \(got.seconds) s")
        }
    }

    /// An agent with a state of its own keeps the ladder: its hook working
    /// counts for a minute, and then its session file, rollout or
    /// transcript decides.
    func testAnAgentWithItsOwnStateIsNotHeldByAnOldHookWorking() {
        for (id, source) in [("claude", StateReport.Source.claudeSessionFile), ("codex", .codexRollout), ("cursor-desktop", .cursorTranscript)] {
            let story = samples(to: 600) { t in
                self.evidence(id, id, .state, reported: self.report(.idle, at: t, source: source), hook: .working, hookAt: self.at(0))
            }
            for (seconds, got) in run(story) {
                XCTAssertEqual(got.state, seconds <= 60 ? .working : .idle, "\(id) at \(seconds) s")
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
            (.holdsSleepAssertion, "Asking your Mac to stay awake"),
            (.writingSessionFile(secondsAgo: 14), "Wrote to its session a moment ago"),
            (.writingSessionFile(secondsAgo: 60), "Wrote to its session 1 minute ago"),
            (.writingSessionFile(secondsAgo: 250), "Wrote to its session 4 minutes ago"),
            (.workedRecently(secondsAgo: 5), "Last worked a moment ago"),
            (.workedRecently(secondsAgo: 130), "Last worked 2 minutes ago"),
            (.cpuActivity, "Using the processor"),
            (.asksPermission, "Waiting for your answer"),
            (.atPrompt, "Ready for your next message"),
            (.backgroundWork, "Running a background command"),
            (.backgroundIdle(minutes: 0), "Background command with no activity"),
            (.backgroundIdle(minutes: 5), "Background command with no activity for 5 minutes"),
            (.backgroundIdle(minutes: 780), "Background command with no activity for 13 hours"),
            (.noActivity(minutes: 0), "No activity"),
            (.noActivity(minutes: 1), "No activity for 1 minute"),
            (.noActivity(minutes: 45), "No activity for 45 minutes"),
            (.noActivity(minutes: 395), "No activity for 6 hours 35 minutes"),
            (.noActivity(minutes: 3 * 24 * 60), "No activity for 3 days"),
            (.onlyWeakSigns(minutes: 30), "Using the processor for 30 minutes with no other sign of work"),
            (.onlyWeakSigns(minutes: 120), "Using the processor for 2 hours with no other sign of work"),
            (.alwaysWorkingByRule, "You set this agent to always count as working"),
            (.ignoredByRule, "You set Agent Caffeine to ignore this agent"),
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
            context: FrameContext(onBattery: true, batteryPercent: 64, lidClosed: true, thermalState: ProcessInfo.ThermalState.fair.rawValue, remoteAccessDetected: true, charging: true)
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
