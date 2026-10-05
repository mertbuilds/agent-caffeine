import XCTest

final class LabRecorderTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)

    private var directory: URL!
    private var seconds: TimeInterval = 0
    private var recorder: LabRecorder!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lab-\(UUID().uuidString)")
        seconds = 0
        recorder = LabRecorder(directory: directory, now: { [unowned self] in self.at(self.seconds) })
    }

    override func tearDownWithError() throws {
        recorder.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    private func header(_ label: String = "desk") -> LabHeader {
        var settings = DetectionSettings()
        settings.agentRules = ["grok": .ignore]
        return LabHeader(label: label, startedAt: at(0), app: "Version 0.2.3 (13)", os: "Version 26.7.1 (Build 25G241)", model: "Mac16,1",
                         mode: AwakeMode.agentWorking.rawValue, settings: settings, wronglyHeldBudget: 30)
    }

    /// Every field filled, so every key shows up in the line.
    private func fullFrame(at seconds: TimeInterval, name: String = "Codex", id: String = "codex-desktop") -> EvidenceFrame {
        let agent = AgentEvidence(
            agentID: id, displayName: name, level: .state, kind: .desktop, role: .engine, pid: 25445, startTime: 1_791_196_400.25,
            reported: StateReport(state: .waitingForUser, since: at(-30), observedAt: at(seconds), source: .codexRollout, detail: "waiting for you"),
            backgroundJobsWorking: 1, childCommands: 4, busyChildCommands: 2, subtreeCPUSeconds: 0.125, sampleInterval: 1,
            energyNanojoules: 9_000_000, logicalWriteBytes: 4096, fileActivityAt: at(-2), ownsSleepAssertion: true,
            hasLiveSession: true, hookState: .working, hookStateAt: at(-1)
        )
        return EvidenceFrame(
            at: at(seconds), agents: [agent],
            context: FrameContext(onBattery: true, batteryPercent: 64, lidClosed: true, thermalState: ProcessInfo.ThermalState.fair.rawValue, remoteAccessDetected: true)
        )
    }

    private func decision(for frame: EvidenceFrame) -> HoldDecision {
        let (readings, _) = VerdictRules.readings(for: frame, memory: [:], settings: DetectionSettings())
        return HoldPolicy.decide(readings: readings, memory: PolicyMemory(), mode: .agentWorking, enabled: true, entitlement: nil,
                                 safety: nil, settings: DetectionSettings(), context: frame.context, now: frame.at).0
    }

    private func lines(of url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    func testRecordingReadsBackAsItWasWritten() throws {
        XCTAssertFalse(recorder.isRecording)
        let url = try recorder.start(label: "desk", header: header())
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.fileURL, url)
        XCTAssertEqual(url.deletingLastPathComponent().path, directory.path)
        XCTAssertEqual(url.lastPathComponent, "2026-10-05T11-33-20Z-desk.jsonl")

        let frames = [fullFrame(at: 0), fullFrame(at: 2)]
        recorder.record(frame: frames[0], decision: decision(for: frames[0]), cost: 0.00213)
        seconds = 1
        recorder.mark(agent: "codex-desktop", truth: .waiting, note: "asked to run a command")
        recorder.record(frame: frames[1], decision: decision(for: frames[1]))
        recorder.stop()
        XCTAssertFalse(recorder.isRecording)
        recorder.record(frame: fullFrame(at: 4), decision: decision(for: frames[1]))
        recorder.mark(agent: "*", truth: .idle)

        let recording = try LabFormat.recording(at: url)
        XCTAssertEqual(recording.header, header())
        XCTAssertEqual(recording.samples.map(\.frame), frames)
        XCTAssertEqual(recording.samples.map(\.ms), [2.13, nil])
        XCTAssertEqual(recording.samples.first?.hold, LabHold(on: true, lid: true, headline: "Awake: Codex is working"))
        XCTAssertEqual(recording.samples.first?.verdicts, [LabVerdict(id: "codex-desktop", pid: 25445, state: .working, why: "reportsBusy", hold: "working")])
        XCTAssertEqual(recording.marks, [LabMark(at: at(1), agent: "codex-desktop", truth: .waiting, note: "asked to run a command")])

        let raw = try lines(of: url)
        XCTAssertEqual(raw.count, 4)
        XCTAssertEqual(raw.map { $0.keys.sorted() }, [["header"], ["frame", "hold", "ms", "verdicts"], ["mark"], ["frame", "hold", "verdicts"]])
        XCTAssertEqual((raw[2]["mark"] as? [String: Any])?["truth"] as? String, "waiting")
        let head = try XCTUnwrap(raw[0]["header"] as? [String: Any])
        XCTAssertEqual(head["catalog"] as? Int, AgentCatalog.version)
        XCTAssertEqual(head["frameVersion"] as? Int, EvidenceFrame.currentVersion)
        XCTAssertEqual(head["mode"] as? String, "agentWorking")
    }

    /// The hook state makes the full frame read as working; what counts
    /// here is the list of keys. A recording must never hold what the user
    /// typed or where the user works, so a new key has to be added here by
    /// hand, and no text may look like a path.
    func testSampleLineHasOnlyKnownKeysAndNoPaths() throws {
        let known: Set<String> = [
            "frame", "verdicts", "hold", "ms",
            "v", "at", "agents", "ctx",
            "id", "name", "level", "kind", "role", "pid", "start", "rep", "jobs", "cmds", "busy", "cpu", "dt", "nj", "wr", "file", "pwr", "live", "hook", "hookAt",
            "state", "since", "seen", "source", "detail",
            "bat", "pct", "lid", "heat", "remote",
            "why", "on", "headline",
        ]
        var keys: Set<String> = []
        var texts: [String] = []
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                keys.formUnion(object.keys)
                object.values.forEach(walk)
            } else if let list = value as? [Any] {
                list.forEach(walk)
            } else if let text = value as? String {
                texts.append(text)
            }
        }
        let url = try recorder.start(label: "keys", header: header())
        let frame = fullFrame(at: 0, name: "/Users/me/bin/myagent", id: "user:/Users/me/bin/myagent")
        recorder.record(frame: frame, decision: decision(for: frame), cost: 0.002)
        recorder.stop()
        let sample = try XCTUnwrap(lines(of: url).last)
        walk(sample)
        XCTAssertEqual(keys.subtracting(known), [])
        XCTAssertEqual(keys.count, known.count, "Every known key is in the full line")
        XCTAssertEqual(texts.filter { $0.contains("/") }, [])
        XCTAssertTrue(texts.contains("user:myagent"))
        XCTAssertTrue(texts.contains("Awake: myagent is working"))
    }

    func testFileNameKeepsOnlySafeCharacters() {
        XCTAssertEqual(LabRecorder.fileName(label: "../my desk #2", at: at(0)), "2026-10-05T11-33-20Z-mydesk2.jsonl")
        XCTAssertEqual(LabRecorder.fileName(label: "///", at: at(0)), "2026-10-05T11-33-20Z-recording.jsonl")
        XCTAssertTrue(LabRecorder.labDirectory(bundleID: "com.example.app").path.hasSuffix("/Library/Application Support/com.example.app/lab"))
    }

    func testMarkFromAnotherProcessGoesToTheNewestRecording() throws {
        XCTAssertNil(LabRecorder.newestRecording(in: directory))
        let old = try recorder.start(label: "old", header: header("old"))
        recorder.stop()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: old.path)
        seconds = 60
        var later = header("new")
        later.startedAt = at(60)
        let new = try recorder.start(label: "new", header: later)
        try Data("not a recording".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        XCTAssertEqual(LabRecorder.newestRecording(in: directory)?.lastPathComponent, new.lastPathComponent)

        let mark = LabMark(at: at(61), agent: "claude:20946", truth: .working, note: nil)
        try LabRecorder.appendMark(mark, to: try XCTUnwrap(LabRecorder.newestRecording(in: directory)))
        let frame = fullFrame(at: 62)
        recorder.record(frame: frame, decision: decision(for: frame))
        recorder.stop()
        let recording = try LabFormat.recording(at: new)
        XCTAssertEqual(recording.marks, [mark])
        XCTAssertEqual(recording.samples.count, 1)
        XCTAssertThrowsError(try LabRecorder.appendMark(mark, to: directory.appendingPathComponent("missing.jsonl")))
    }

    func testCutOffLastLineIsLeftOutAndABadLineIsAnError() throws {
        let url = try recorder.start(label: "cut", header: header())
        let frame = fullFrame(at: 0)
        recorder.record(frame: frame, decision: decision(for: frame))
        recorder.stop()
        let text = try String(contentsOf: url, encoding: .utf8)
        let cut = try LabFormat.recording(from: text + #"{"frame":{"at":17912"#)
        XCTAssertEqual(cut.samples.count, 1)
        XCTAssertThrowsError(try LabFormat.recording(from: #"{"frame":{"at":17912"# + "\n" + text)) { error in
            XCTAssertEqual(error as? LabError, .unreadableLine(1))
        }
        XCTAssertEqual(try LabFormat.recording(from: ""), LabRecording())
    }
}
