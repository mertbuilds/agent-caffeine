import XCTest

final class LabReplayTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)
    private static let processStart: TimeInterval = 1_791_196_400
    /// The recordings are read from the source folder, so a new file needs
    /// no change to the project.
    private static let recordings = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Recordings")

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    // MARK: Timeline helpers

    /// One frame every 5 seconds.
    private func frames(to end: TimeInterval, _ make: (TimeInterval) -> [AgentEvidence]) -> [EvidenceFrame] {
        stride(from: 0, through: end, by: 5).map { EvidenceFrame(at: at($0), agents: make($0)) }
    }

    private func agent(
        _ id: String, _ name: String, _ level: AgentDefinition.Level, pid: Int32, state: ReportedState?, at seconds: TimeInterval,
        kind: AgentDefinition.Kind = .cli, role: AgentRole = .session, source: StateReport.Source = .claudeSessionFile,
        cpu percent: Double = 0.4, commands: Int = 0, busy: Int = 0, assertion: Bool = false, live: Bool = false
    ) -> AgentEvidence {
        let interval: TimeInterval = seconds == 0 ? 0 : 5
        return AgentEvidence(
            agentID: id, displayName: name, level: level, kind: kind, role: role, pid: pid, startTime: Self.processStart,
            reported: state.map { StateReport(state: $0, since: nil, observedAt: at(seconds), source: source, detail: nil) },
            childCommands: commands, busyChildCommands: busy, subtreeCPUSeconds: percent / 100 * interval, sampleInterval: interval,
            ownsSleepAssertion: assertion, hasLiveSession: live
        )
    }

    private func claude(_ state: ReportedState, at seconds: TimeInterval, pid: Int32 = 100) -> AgentEvidence {
        agent("claude", "Claude Code", .state, pid: pid, state: state, at: seconds)
    }

    private func header(_ label: String, settings: DetectionSettings = DetectionSettings(), budget: TimeInterval? = nil) -> LabHeader {
        LabHeader(label: label, startedAt: at(0), app: "synthetic", os: "synthetic", model: "synthetic",
                  mode: AwakeMode.agentWorking.rawValue, settings: settings, wronglyHeldBudget: budget)
    }

    private func mark(_ agent: String, _ truth: LabTruth, at seconds: TimeInterval) -> LabMark {
        LabMark(at: at(seconds), agent: agent, truth: truth, note: nil)
    }

    /// A recording as the app would have written it: each sample carries
    /// the decision that the rules give for it.
    private func recording(_ label: String, frames: [EvidenceFrame], marks: [LabMark], budget: TimeInterval? = nil) -> LabRecording {
        var recording = LabRecording(header: header(label, budget: budget), samples: frames.map { LabSample(frame: $0) }, marks: marks)
        for (index, step) in LabReplay.steps(of: recording).enumerated() {
            let line = LabFormat.sample(frame: frames[index], decision: step.decision, cost: nil)
            recording.samples[index] = LabSample(frame: frames[index], verdicts: line.verdicts ?? [], hold: line.hold)
        }
        return recording
    }

    /// The lines in the order of their times, a mark before the sample of
    /// the same instant.
    private func text(of recording: LabRecording) throws -> String {
        var lines: [LabLine] = []
        if let header = recording.header { lines.append(LabLine(header: header)) }
        var marks = recording.marks[...]
        for sample in recording.samples {
            while let mark = marks.first, mark.at <= sample.frame.at {
                lines.append(LabLine(mark: mark))
                marks = marks.dropFirst()
            }
            lines.append(LabLine(frame: sample.frame, verdicts: sample.verdicts, hold: sample.hold, ms: sample.ms))
        }
        lines += marks.map { LabLine(mark: $0) }
        return try lines.map { String(decoding: try LabFormat.line($0), as: UTF8.self) }.joined()
    }

    // MARK: Scoring

    func testWorkThatIsNotSeenCountsAsWronglyReleased() {
        let story = frames(to: 100) { t in [self.claude(.idle, at: t)] }
        let score = LabReplay.score(recording("missed", frames: story, marks: [mark("claude", .working, at: 10), mark("claude", .idle, at: 50)]))
        XCTAssertEqual(score.agents.map(\.agent), ["claude"])
        XCTAssertEqual(score.wronglyReleased, 40, "From the mark at 10 s to the mark at 50 s")
        XCTAssertEqual(score.wronglyHeld, 0)
        XCTAssertEqual(score.agents[0].reactions, [
            LabScore.Reaction(at: at(10), truth: .working, delay: nil),
            LabScore.Reaction(at: at(50), truth: .idle, delay: 0),
        ])
        XCTAssertEqual(score.heldSeconds, 0)
        XCTAssertEqual(score.samples, 21)
        XCTAssertEqual(score.duration, 100)
        XCTAssertEqual(score.liveMismatches, 0)
    }

    func testHoldPastTheReleaseTimeCountsAsWronglyHeld() {
        let story = frames(to: 300) { t in [self.claude(.working, at: t)] }
        let stuck = LabReplay.score(recording("stuck", frames: story, marks: [mark("claude", .working, at: 0), mark("claude", .idle, at: 20)]))
        XCTAssertEqual(stuck.wronglyHeld, 160, "The release time of 120 s after the mark is allowed")
        XCTAssertEqual(stuck.wronglyReleased, 0)
        XCTAssertEqual(stuck.agents[0].reactions.map(\.delay), [0, nil])
        XCTAssertTrue(stuck.report.contains("claude: wrongly held 160.0 s, wrongly released 0.0 s"), stuck.report)
        XCTAssertTrue(stuck.report.contains("idle: never seen"), stuck.report)
        XCTAssertTrue(stuck.report.contains("Claude Code [claude:100]: working 300.0 s"), stuck.report)

        // Waiting may hold for the waiting hold, 300 s, and no longer.
        let long = frames(to: 400) { t in [self.claude(.working, at: t)] }
        let waiting = LabReplay.score(recording("waiting", frames: long, marks: [mark("claude", .waiting, at: 60)]))
        XCTAssertEqual(waiting.wronglyHeld, 40)

        let gone = LabReplay.score(recording("gone", frames: story, marks: [mark("claude", .gone, at: 100)]))
        XCTAssertEqual(gone.wronglyHeld, 80)
    }

    // MARK: Clock

    func testSampleGap() {
        func time(_ wall: TimeInterval, _ awake: TimeInterval?) -> SampleTime { SampleTime(at: at(wall), awake: awake) }
        let cases: [(name: String, from: SampleTime?, to: SampleTime, want: TimeInterval?)] = [
            ("first sample", nil, time(0, 50), nil),
            ("next sample", time(0, 50), time(2, 52), nil),
            ("a time sync moves the date a little", time(0, 50), time(2.6, 52), nil),
            ("late timer", time(0, 50), time(14, 64), nil),
            ("sleep of an hour", time(0, 50), time(3602, 52), 3600),
            ("short sleep", time(0, 50), time(10, 52), 8),
            ("sampling stopped for ten minutes", time(0, 50), time(600, 650), 600),
            ("clock set forward by an hour", time(0, 50), time(3602, 52), 3600),
            ("clock set back by an hour", time(0, 50), time(-3598, 52), -3600),
            ("clock set back while the sampling was stopped", time(0, 50), time(-3000, 650), -3000),
            ("no awake clock: by the date", time(0, nil), time(16, nil), 16),
            ("no awake clock: no hole", time(0, nil), time(15, nil), nil),
            ("no awake clock: a step back is not seen", time(0, nil), time(-3598, nil), nil),
            ("awake clock of another boot: by the date", time(0, 500), time(20, 3), 20),
        ]
        for c in cases {
            XCTAssertEqual(SampleGap.length(from: c.from, to: c.to), c.want, c.name)
        }
        XCTAssertEqual(SampleGap.interval(from: time(0, 50), to: time(-3598, 52)), 2)
        XCTAssertEqual(SampleGap.interval(from: time(0, nil), to: time(5, nil)), 5)
        XCTAssertGreaterThan(SampleGap.awakeSeconds(), 0)
    }

    /// The clock is set by an hour after 100 seconds, back or forward. The
    /// timers run on the awake time: the release times, the waiting hold
    /// and the release after a command all end where they would have.
    /// With the step back, every one of them ran for an hour longer.
    func testClockStepCountsForNoTimer() {
        for step in [-3600.0, 3600.0] {
            func wall(_ awake: TimeInterval) -> TimeInterval { awake <= 100 ? awake : awake + step }
            let story = stride(from: 0, through: 500, by: 5).map { (t: TimeInterval) -> EvidenceFrame in
                let w = wall(t)
                var builder = self.agent("opencode", "opencode", .activity, pid: 200, state: nil, at: w, commands: 1, busy: t <= 100 ? 1 : 0)
                // As the collector gives it: no CPU number on the sample after the step.
                if t == 105 { builder.sampleInterval = 0 }
                var frame = EvidenceFrame(at: self.at(w), agents: [
                    self.claude(t <= 90 ? .working : .idle, at: w, pid: 100),
                    self.claude(t < 50 ? .working : .waitingForUser, at: w, pid: 101),
                    builder,
                ])
                frame.awake = 5000 + t
                return frame
            }
            let steps = LabReplay.steps(of: LabRecording(header: header("clock"), samples: story.map { LabSample(frame: $0) }, marks: []))
            XCTAssertEqual(steps.count, 101)
            for (index, got) in steps.enumerated() {
                let t = TimeInterval(index * 5)
                let causes = got.decision.perAgent.map(\.cause)
                XCTAssertEqual(causes[0], t <= 90 ? .working : t < 210 ? .finishedRecently : nil, "step \(step): finished at 90 s, awake time \(t) s")
                XCTAssertEqual(causes[1], t < 50 ? .working : t < 350 ? .waitingForUser : nil, "step \(step): waits from 50 s, awake time \(t) s")
                XCTAssertEqual(causes[2], t < 400 ? .working : nil, "step \(step): command until 100 s, awake time \(t) s")
            }
        }
    }

    func testFrameKeepsItsAwakeTime() throws {
        var frame = EvidenceFrame(at: at(0), agents: [])
        XCTAssertFalse(String(decoding: try LabFormat.encoder().encode(frame), as: UTF8.self).contains("\"up\""))
        frame.awake = 1234.5
        let data = try LabFormat.encoder().encode(frame)
        XCTAssertEqual(try LabFormat.decoder().decode(EvidenceFrame.self, from: data).awake, 1234.5)
    }

    /// The Mac sleeps for 6 minutes after 100 seconds. No timer counts the
    /// sleep: not the release times, not the waiting hold, not the weak cap.
    /// The step across the sleep does not count either, so each timer ends
    /// one step of 5 seconds later than its awake time says.
    func testSleepGapCountsForNoTimer() {
        let hole: TimeInterval = 360
        func wall(_ awake: TimeInterval) -> TimeInterval { awake <= 100 ? awake : awake + hole }
        var settings = DetectionSettings()
        settings.weakEvidenceCap = 200
        let story = stride(from: 0, through: 500, by: 5).map { (t: TimeInterval) -> EvidenceFrame in
            let w = wall(t)
            // As the collector gives it: no CPU number on the sample after the hole.
            let interval: TimeInterval = t == 0 || t == 105 ? 0 : 5
            let writer = AgentEvidence(agentID: "opencode", displayName: "opencode", level: .activity, pid: 200, startTime: Self.processStart,
                                       subtreeCPUSeconds: 0.004 * interval, sampleInterval: interval, fileActivityAt: self.at(min(t, 100)))
            let spinner = AgentEvidence(agentID: "goose", displayName: "Goose", level: .activity, pid: 201, startTime: Self.processStart,
                                        subtreeCPUSeconds: 0.145 * interval, sampleInterval: interval)
            return EvidenceFrame(at: self.at(w), agents: [
                self.claude(t <= 90 ? .working : .idle, at: w, pid: 100),
                self.claude(t < 50 ? .working : .waitingForUser, at: w, pid: 101),
                writer, spinner,
            ])
        }
        var recording = LabRecording(header: header("sleep", settings: settings), samples: story.map { LabSample(frame: $0) }, marks: [])
        recording.samples = story.map { LabSample(frame: $0) }
        let steps = LabReplay.steps(of: recording)
        XCTAssertEqual(steps.count, 101)
        for (index, step) in steps.enumerated() {
            let t = TimeInterval(index * 5)
            let causes = step.decision.perAgent.map(\.cause)
            XCTAssertEqual(causes[0], t <= 90 ? .working : t < 215 ? .finishedRecently : nil, "finished at 90 s, awake time \(t) s")
            XCTAssertEqual(causes[1], t < 50 ? .working : t < 355 ? .waitingForUser : nil, "waits from 50 s, awake time \(t) s")
            XCTAssertEqual(causes[2], t < 405 ? .working : nil, "last write at 100 s, awake time \(t) s")
            let spinner = step.readings[3].verdict
            if t >= 15, t < 220 { XCTAssertEqual(spinner.state, .working, "awake time \(t) s") }
            if t >= 220 { XCTAssertEqual(spinner.reason, .onlyWeakSigns(minutes: 3), "The cap counts on across the sleep, awake time \(t) s") }
        }
        XCTAssertTrue(steps[21].decision.hold, "The first sample after the sleep")
    }

    func testReactionDelayIsTheTimeToTheFirstSampleThatAgrees() {
        let story = frames(to: 500) { t in
            if t >= 470 { return [] }
            return [self.claude(t < 25 ? .idle : t < 60 ? .working : t < 90 ? .waitingForUser : .idle, at: t)]
        }
        let marks = [mark("claude", .working, at: 21), mark("claude", .waiting, at: 57), mark("claude", .idle, at: 90), mark("claude", .gone, at: 468.5)]
        let score = LabReplay.score(recording("follow", frames: story, marks: marks))
        XCTAssertEqual(score.agents[0].reactions.map(\.delay), [4, 3, 0, 1.5])
        XCTAssertEqual(score.wronglyReleased, 4, "Idle from the mark at 21 s until the sample at 25 s")
        XCTAssertEqual(score.wronglyHeld, 0)
    }

    func testMarksCanNameOneInstanceAnAgentOrEverything() {
        let story = frames(to: 400) { t in
            [
                self.claude(.working, at: t, pid: 1),
                self.claude(.idle, at: t, pid: 2),
                self.agent("opencode", "opencode", .activity, pid: 3, state: nil, at: t),
            ]
        }
        let marks = ["claude:2", "claude", "*", "opencode", "grok"].map { mark($0, .idle, at: 0) } + [mark("claude:1", .working, at: 0), mark("opencode", .gone, at: 200)]
        let score = LabReplay.score(recording("targets", frames: story, marks: marks))
        let held = Dictionary(uniqueKeysWithValues: score.agents.map { ($0.agent, $0.wronglyHeld) })
        XCTAssertEqual(held, ["claude:2": 0, "claude": 280, "*": 100, "opencode": 0, "grok": 0, "claude:1": 0])
        XCTAssertEqual(score.wronglyHeld, 380)
        XCTAssertEqual(score.wronglyReleased, 0)
        let opencode = score.agents.first { $0.agent == "opencode" }
        XCTAssertEqual(opencode?.reactions.map(\.delay), [0, nil], "It is still there, so it is not gone")
        XCTAssertEqual(score.agents.first { $0.agent == "grok" }?.reactions.map(\.delay), [0], "An agent that is not there is as good as idle")
        XCTAssertEqual(score.seen.map(\.pid), [1, 2, 3])
        XCTAssertEqual(score.seen.map(\.working), [400, 0, 0])
        XCTAssertEqual(score.seen.map(\.held), [400, 0, 0])
        XCTAssertEqual(score.heldSeconds, 400)
    }

    func testOtherSettingsChangeTheReplayNotTheRecording() {
        let story = frames(to: 200) { t in [self.claude(t <= 10 ? .working : .idle, at: t)] }
        let recording = recording("settings", frames: story, marks: [mark("claude", .working, at: 0), mark("claude", .idle, at: 15)])
        let recorded = LabReplay.score(recording)
        XCTAssertEqual(recorded.heldSeconds, 130)
        XCTAssertEqual(recorded.liveMismatches, 0)
        XCTAssertEqual(recorded.wronglyHeld, 0)

        var quick = DetectionSettings()
        quick.releaseAfterState = 30
        let replayed = LabReplay.score(recording, settings: quick)
        XCTAssertEqual(replayed.heldSeconds, 40)
        XCTAssertEqual(replayed.liveMismatches, 18)
        XCTAssertEqual(LabReplay.score(recording, mode: .always).heldSeconds, 200)

        let noMarks = LabReplay.score(LabRecording(samples: recording.samples))
        XCTAssertEqual(noMarks.agents, [])
        XCTAssertTrue(noMarks.report.contains("No marks, so nothing to score."), noMarks.report)
    }

    // MARK: Recordings

    /// A Claude Code session that works, runs a command, asks and stops,
    /// and a Codex desktop engine that takes one turn.
    private func synthetic() -> LabRecording {
        let story = frames(to: 340) { t in
            let claudeState: ReportedState = t < 20 ? .idle : t < 80 ? .working : t < 110 ? .waitingForUser : .idle
            let inTurn = claudeState == .working
            let building = t >= 40 && t < 60
            let codexWorking = t >= 150 && t < 200
            return [
                self.agent("claude", "Claude Code", .state, pid: 100, state: claudeState, at: t, cpu: building ? 180 : inTurn ? 3 : 0.4,
                           commands: inTurn ? 3 : 2, busy: building ? 1 : 0, assertion: inTurn),
                self.agent("codex-desktop", "Codex", .state, pid: 25445, state: codexWorking ? .working : .idle, at: t,
                           kind: .desktop, role: .engine, source: .codexRollout, cpu: codexWorking ? 1.2 : 0.2, commands: 2, live: t >= 150),
            ]
        }
        let marks = [
            mark("claude", .working, at: 20), mark("claude", .waiting, at: 80), mark("claude", .idle, at: 110),
            mark("codex-desktop", .working, at: 150), mark("codex-desktop", .idle, at: 200),
        ]
        return recording("synthetic", frames: story, marks: marks, budget: 0)
    }

    /// When the format changes on purpose, copy the file this test names
    /// over the one in `Recordings`.
    func testSyntheticRecordingIsCurrent() throws {
        let expected = try text(of: synthetic())
        let url = Self.recordings.appendingPathComponent("synthetic-claude-codex.jsonl")
        let found = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if found != expected {
            let fresh = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-claude-codex.jsonl")
            try Data(expected.utf8).write(to: fresh)
            XCTFail("\(url.path) is not what the timeline gives. The current one is at \(fresh.path)")
        }
        XCTAssertEqual(try LabFormat.recording(from: expected), synthetic())
    }

    /// The night of 2026-10-10 (docs/research/01-oss-detection.md, section
    /// 9), with the lid closed, on battery: a turn of Claude Code starts a
    /// dev server and ends, and the session file says `shell` from then
    /// on. The server is busy while it starts, and for 30 seconds more
    /// when it builds again later. The other three commands are the MCP
    /// servers of the session.
    private func backgroundShell() -> LabRecording {
        let context = FrameContext(onBattery: true, batteryPercent: 94, lidClosed: true)
        let story = stride(from: 0.0, through: 900, by: 5).map { t -> EvidenceFrame in
            let inTurn = t < 20
            let busy = t < 40 || (500..<530).contains(t)
            var claude = self.agent("claude", "Claude Code", .state, pid: 100, state: inTurn ? .working : .idle, at: t,
                                    cpu: busy ? 60 : 0.4, commands: 4, busy: busy ? 1 : 0)
            claude.reported?.since = self.at(inTurn ? -100 : 20)
            claude.reported?.backgroundWork = !inTurn
            return EvidenceFrame(at: self.at(t), agents: [claude], context: context)
        }
        let marks = [mark("claude", .working, at: 0), mark("claude", .idle, at: 40), mark("claude", .working, at: 500), mark("claude", .idle, at: 530)]
        // The rule holds for `releaseAfterActivity` after the last busy
        // sample, and the score allows `releaseAfterState` after a mark:
        // 175 seconds more, two times.
        return recording("synthetic-claude-background-shell", frames: story, marks: marks, budget: 350)
    }

    /// As `testSyntheticRecordingIsCurrent`.
    func testBackgroundShellRecordingIsCurrent() throws {
        let expected = try text(of: backgroundShell())
        let url = Self.recordings.appendingPathComponent("synthetic-claude-background-shell.jsonl")
        let found = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if found != expected {
            let fresh = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-claude-background-shell.jsonl")
            try Data(expected.utf8).write(to: fresh)
            XCTFail("\(url.path) is not what the timeline gives. The current one is at \(fresh.path)")
        }
        XCTAssertEqual(try LabFormat.recording(from: expected), backgroundShell())
    }

    func testABackgroundCommandHoldsOnlyWhileItWorks() throws {
        let recording = try LabFormat.recording(at: Self.recordings.appendingPathComponent("synthetic-claude-background-shell.jsonl"))
        XCTAssertEqual(recording.samples.first?.frame.context, FrameContext(onBattery: true, batteryPercent: 94, lidClosed: true))
        for step in LabReplay.steps(of: recording) {
            let seconds = step.at.timeIntervalSince(at(0))
            // The last busy samples are those at 35 s and at 525 s.
            let held = seconds < 335 || (500..<825).contains(seconds)
            XCTAssertEqual(step.decision.hold, held, "at \(seconds) s")
            XCTAssertEqual(step.decision.lidClosedFlag, held, "at \(seconds) s")
            XCTAssertEqual(step.readings.first?.verdict.state, held ? .working : .idle, "at \(seconds) s")
            XCTAssertEqual(step.readings.first?.turn?.state, seconds < 20 ? .working : .idle, "at \(seconds) s")
        }
        XCTAssertEqual(LabReplay.score(recording).heldSeconds, 335 + 325)
    }

    /// The incident as the app met it: `shell` for 13 hours, a pnpm tree
    /// at 0 percent CPU, the lid closed, on battery. No hold and no sleep
    /// flag, from the first sample on.
    func testAShellStatusOfThirteenHoursDoesNotHoldTheMac() {
        let context = FrameContext(onBattery: true, batteryPercent: 46, lidClosed: true)
        let story = stride(from: 0.0, through: 600, by: 5).map { t -> EvidenceFrame in
            var claude = self.agent("claude", "Claude Code", .state, pid: 100, state: .idle, at: t, cpu: 0, commands: 4)
            claude.reported?.since = self.at(-13 * 3600)
            claude.reported?.backgroundWork = true
            return EvidenceFrame(at: self.at(t), agents: [claude], context: context)
        }
        let steps = LabReplay.steps(of: LabRecording(header: header("incident"), samples: story.map { LabSample(frame: $0) }))
        XCTAssertEqual(steps.count, 121)
        for step in steps {
            XCTAssertFalse(step.decision.hold)
            XCTAssertFalse(step.decision.lidClosedFlag)
            XCTAssertEqual(step.decision.headline, .idle(.one("Claude Code")))
            XCTAssertEqual(step.readings.first?.verdict.state, .idle)
        }
        XCTAssertEqual(steps.last?.readings.first?.verdict.reason, .backgroundIdle(minutes: 13 * 60 + 10))
    }

    func testRecordingsStayWithinTheirBudget() throws {
        let urls = try FileManager.default.contentsOfDirectory(at: Self.recordings, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(urls.isEmpty, "No recording in \(Self.recordings.path)")
        for url in urls {
            let name = url.lastPathComponent
            let recording = try LabFormat.recording(at: url)
            let header = try XCTUnwrap(recording.header, "\(name) has no header")
            XCTAssertFalse(recording.samples.isEmpty, "\(name) has no samples")
            XCTAssertFalse(recording.marks.isEmpty, "\(name) has no marks, so it proves nothing")
            let score = LabReplay.score(recording)
            XCTAssertEqual(score.wronglyReleased, 0, "\(name)\n\(score.report)")
            XCTAssertLessThanOrEqual(score.wronglyHeld, header.wronglyHeldBudget ?? 0, "\(name)\n\(score.report)")
        }
    }
}
