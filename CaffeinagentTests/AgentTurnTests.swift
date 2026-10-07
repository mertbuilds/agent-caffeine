import XCTest

/// The turn that the notifications follow, next to the verdict.
final class AgentTurnTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)
    private static let processStart = start.timeIntervalSince1970 - 3600
    private static let recordings = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Recordings")

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    private func claude(
        _ state: ReportedState?, at seconds: TimeInterval, since: TimeInterval = -600, source: StateReport.Source = .claudeSessionFile,
        shell: Bool = false, busy: Int = 0, jobs: Int = 0, hook: ReportedState? = nil, pid: Int32 = 100
    ) -> AgentEvidence {
        AgentEvidence(
            agentID: "claude", displayName: "Claude Code", level: .state, pid: pid, startTime: Self.processStart,
            reported: state.map { StateReport(state: $0, since: at(since), observedAt: at(seconds), source: source, detail: nil, turnEnded: shell) },
            backgroundJobsWorking: jobs, childCommands: busy, busyChildCommands: busy, subtreeCPUSeconds: 0.02, sampleInterval: 5,
            hookState: hook, hookStateAt: hook.map { _ in at(seconds) }
        )
    }

    private func reading(_ evidence: AgentEvidence, at seconds: TimeInterval, settings: DetectionSettings = DetectionSettings()) -> AgentReading {
        VerdictRules.readings(for: EvidenceFrame(at: at(seconds), agents: [evidence]), memory: [:], settings: settings).0[0]
    }

    func testTheTurnIsTheStateTheAgentGives() {
        XCTAssertEqual(reading(claude(.working, at: 0), at: 0).turn, AgentTurn(state: .working, since: at(-600)))
        XCTAssertEqual(reading(claude(.waitingForUser, at: 0), at: 0).turn, AgentTurn(state: .waitingForUser))
        XCTAssertEqual(reading(claude(.idle, at: 0), at: 0).turn, AgentTurn(state: .idle))
    }

    func testACommandOrAJobThatRunsOnChangesTheVerdictAndNotTheTurn() {
        let ended = reading(claude(.idle, at: 0, busy: 1), at: 0)
        XCTAssertEqual(ended.verdict.state, .working)
        XCTAssertEqual(ended.turn?.state, .idle)
        let asks = reading(claude(.waitingForUser, at: 0, jobs: 1), at: 0)
        XCTAssertEqual(asks.verdict.state, .working)
        XCTAssertEqual(asks.turn?.state, .waitingForUser)
    }

    func testClaudesShellStatusIsATurnThatEnded() {
        let shell = reading(claude(.working, at: 0, shell: true), at: 0)
        XCTAssertEqual(shell.verdict.state, .working)
        XCTAssertEqual(shell.turn, AgentTurn(state: .idle))
        let state = ClaudeSessionStateReader.parse(Data(#"{"status":"shell","statusUpdatedAt":1791200000000}"#.utf8), now: at(0))
        XCTAssertEqual(state?.report.turnEnded, true)
        XCTAssertEqual(ClaudeSessionStateReader.parse(Data(#"{"status":"busy"}"#.utf8), now: at(0))?.report.turnEnded, false)
    }

    func testAHookWaitIsTheTurn() {
        XCTAssertEqual(reading(claude(.working, at: 0, hook: .waitingForUser), at: 0).turn?.state, .waitingForUser)
    }

    func testNoTurnWithoutAStateOrUnderARule() {
        XCTAssertNil(reading(claude(nil, at: 0), at: 0).turn)
        var settings = DetectionSettings()
        settings.agentRules["claude"] = .ignore
        XCTAssertNil(reading(claude(.working, at: 0), at: 0, settings: settings).turn)
    }

    func testTheTimeOfATranscriptIsNotTheStartOfTheTurn() {
        XCTAssertEqual(reading(claude(.working, at: 0, since: -2, source: .claudeTranscript), at: 0).turn, AgentTurn(state: .working))
    }

    func testTheTurnEndedFlagIsRecordedOnlyWhenSet() throws {
        let plain = StateReport(state: .working, since: nil, observedAt: at(0), source: .claudeSessionFile, detail: nil)
        var shell = plain
        shell.turnEnded = true
        let encoder = LabFormat.encoder()
        XCTAssertFalse(String(decoding: try encoder.encode(plain), as: UTF8.self).contains("over"))
        XCTAssertEqual(try LabFormat.decoder().decode(StateReport.self, from: try encoder.encode(shell)), shell)
        XCTAssertEqual(try LabFormat.decoder().decode(StateReport.self, from: try encoder.encode(plain)), plain)
    }

    // MARK: Replay

    func testTheReplayListsTheChangesAndWhatWasTold() {
        // Work, a question, more work, the end with a server that runs on,
        // and then that server alone.
        func state(_ seconds: TimeInterval) -> AgentEvidence {
            switch seconds {
            case ..<10: return claude(.idle, at: seconds)
            case ..<40: return claude(.working, at: seconds, since: 10)
            case ..<60: return claude(.waitingForUser, at: seconds, busy: 1)
            case ..<90: return claude(.working, at: seconds, since: 60)
            case ..<120: return claude(.idle, at: seconds, busy: 1)
            default: return claude(.idle, at: seconds)
            }
        }
        let samples = stride(from: 0.0, through: 140, by: 5).map { LabSample(frame: EvidenceFrame(at: at($0), agents: [state($0)])) }
        let lines = LabNotices.lines(LabRecording(samples: samples))
        XCTAssertEqual(lines.filter { $0.contains("fired") || $0.contains("skipped") }.map { String($0.drop { $0 == " " }) }, [
            "45.0 s    waiting fired pid 100",
            "95.0 s    finished fired pid 100 after 80 s",
        ])
        XCTAssertTrue(lines.contains { $0.contains("turn idle, verdict working -> idle (atPrompt) after 30.0 s: no change for the notifications") }, "\(lines)")
        XCTAssertTrue(LabNotices.report(LabRecording(samples: samples)).hasPrefix("Agent notifications in the replay: 2 fired"))
    }

    func testTheSyntheticRecordingTellsItsWaitAndItsFinish() throws {
        let recording = try LabFormat.recording(at: Self.recordings.appendingPathComponent("synthetic-claude-codex.jsonl"))
        let told = LabNotices.lines(recording).filter { $0.contains(" fired pid ") }
        XCTAssertEqual(told.count, 2, "\(told)")
        XCTAssertTrue(told[0].contains("waiting fired pid 100"))
        XCTAssertTrue(told[1].contains("finished fired pid 25445"))
    }
}
