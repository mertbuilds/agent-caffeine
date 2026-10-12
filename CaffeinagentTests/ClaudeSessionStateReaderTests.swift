import XCTest

final class ClaudeSessionStateReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_200_000)

    private func session(status: String?, extra: String = "") -> Data {
        let statusField = status.map { #""status":"\#($0)","# } ?? ""
        return Data((#"{"pid":4242,"sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/tmp/demo","kind":"interactive","version":"2.1.289",\#(statusField)"updatedAt":1791199000500,"statusUpdatedAt":1791199000000\#(extra)}"#).utf8)
    }

    func testStatusMapping() {
        let cases: [(status: String, state: ReportedState?, detail: String?)] = [
            ("busy", .working, "in a turn"),
            ("shell", .idle, "turn ended, background commands run"),
            ("waiting", .waitingForUser, "waiting for you"),
            ("idle", .idle, nil),
            ("compacting", nil, nil),
            ("", nil, nil),
        ]
        for (status, state, detail) in cases {
            let parsed = ClaudeSessionStateReader.parse(session(status: status), now: now)
            XCTAssertEqual(parsed?.state, state, status)
            XCTAssertEqual(parsed?.report.detail, detail, status)
            if state != nil { XCTAssertEqual(parsed?.rawStatus, status) }
            XCTAssertEqual(parsed?.backgroundWork ?? false, status == "shell", status)
            XCTAssertEqual(parsed?.report.backgroundWork ?? false, status == "shell", status)
        }
    }

    func testSessionName() throws {
        let named = try XCTUnwrap(ClaudeSessionStateReader.parse(session(status: "busy", extra: #","name":" wiki-1d\n","nameSource":"derived""#), now: now))
        XCTAssertEqual(named.name, "wiki-1d")
        XCTAssertNil(named.report.detail?.range(of: "wiki-1d"), "A report never carries the name")
        XCTAssertNil(ClaudeSessionStateReader.parse(session(status: "busy"), now: now)?.name)
        XCTAssertNil(ClaudeSessionStateReader.parse(session(status: "busy", extra: #","name":7"#), now: now)?.name)
    }

    func testFullFile() throws {
        let parsed = try XCTUnwrap(ClaudeSessionStateReader.parse(session(status: "busy"), now: now))
        XCTAssertEqual(parsed.pid, 4242)
        XCTAssertEqual(parsed.kind, .interactive)
        XCTAssertEqual(parsed.sessionID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(parsed.cwd, "/tmp/demo")
        XCTAssertEqual(parsed.version, "2.1.289")
        XCTAssertEqual(parsed.statusUpdatedAt, Date(timeIntervalSince1970: 1_791_199_000))
        XCTAssertEqual(parsed.report, StateReport(
            state: .working,
            since: Date(timeIntervalSince1970: 1_791_199_000),
            observedAt: now,
            source: .claudeSessionFile,
            detail: "in a turn"
        ))
    }

    /// The two start times of a file, as on 2.1.286 to 2.1.296: the
    /// process of this file started 1790845119 (08:58:39 UTC), and
    /// `startedAt` is 2 seconds later.
    func testStartTimesSayWhichProcessTheFileIsOf() throws {
        let start: TimeInterval = 1_790_845_119.48
        let both = try XCTUnwrap(ClaudeSessionStateReader.parse(session(status: "busy", extra: #","startedAt":1790845121236,"procStart":"Thu Oct  1 08:58:39 2026""#), now: now))
        XCTAssertEqual(both.startedAt, Date(timeIntervalSince1970: 1_790_845_121.236))
        XCTAssertEqual(both.processStartedAt, Date(timeIntervalSince1970: 1_790_845_119))
        let cases: [(name: String, extra: String, start: TimeInterval, fits: Bool)] = [
            ("both times", #","startedAt":1790845121236,"procStart":"Thu Oct  1 08:58:39 2026""#, start, true),
            ("the start of the process only", #","procStart":"Thu Oct  1 08:58:39 2026""#, start, true),
            ("the start of the session only", #","startedAt":1790845121236"#, start, true),
            ("a spare that took its job hours after it started", #","startedAt":1790859521236"#, start, true),
            ("a process start in a form that is not known", #","startedAt":1790845121236,"procStart":"2026-10-01 11:58:39""#, start, true),
            ("neither time", "", start, false),
            ("times of the wrong type", #","startedAt":"soon","procStart":7"#, start, false),
            // The file of a process that crashed, and its pid went to a
            // process that started a day later.
            ("a file from before the process", #","startedAt":1790845121236,"procStart":"Thu Oct  1 08:58:39 2026""#, start + 86400, false),
            ("a file from 3 seconds before the process", #","startedAt":1790845121236"#, 1_790_845_124.3, false),
            ("another process start and no session start", #","procStart":"Thu Oct  1 08:58:49 2026""#, start, false),
        ]
        for testCase in cases {
            let parsed = try XCTUnwrap(ClaudeSessionStateReader.parse(session(status: "busy", extra: testCase.extra), now: now), testCase.name)
            XCTAssertEqual(parsed.isOfProcess(startedAt: testCase.start), testCase.fits, testCase.name)
        }
    }

    func testPidsOfTheFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-pids-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["4242.json", "17.json", "notes.json", "99.json.tmp", "-5.txt", ".json"] {
            try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
        }
        XCTAssertEqual(ClaudeSessionStateReader(sessionsDirectory: directory).pids(), [4242, 17])
        XCTAssertEqual(ClaudeSessionStateReader(sessionsDirectory: directory.appendingPathComponent("none")).pids(), [])
    }

    func testKinds() {
        let cases: [(json: String, kind: ClaudeSessionState.Kind?)] = [
            (#"{"status":"idle","kind":"interactive"}"#, .interactive),
            (#"{"status":"busy","kind":"bg","jobId":"ab12cd34"}"#, .background),
            (#"{"status":"idle","kind":"bg","spare":true}"#, .spare),
            (#"{"status":"idle","kind":"bg","spare":{"id":"e5f57e77"}}"#, .spare),
            (#"{"status":"idle","kind":"bg","spare":false}"#, .background),
            (#"{"status":"idle","kind":"bg","spare":null}"#, .background),
            (#"{"status":"idle","kind":"remote"}"#, .other("remote")),
            (#"{"status":"idle"}"#, nil),
            (#"{"status":"idle","kind":7}"#, nil),
        ]
        for (json, kind) in cases {
            XCTAssertEqual(ClaudeSessionStateReader.parse(Data(json.utf8), now: now)?.kind, kind, json)
        }
        let background = ClaudeSessionStateReader.parse(Data(cases[1].json.utf8), now: now)
        XCTAssertEqual(background?.jobID, "ab12cd34")
    }

    func testMissingAndWrongTypedKeys() throws {
        let bare = try XCTUnwrap(ClaudeSessionStateReader.parse(Data(#"{"status":"waiting"}"#.utf8), now: now))
        XCTAssertEqual(bare.state, .waitingForUser)
        XCTAssertNil(bare.pid)
        XCTAssertNil(bare.statusUpdatedAt)
        XCTAssertNil(bare.sessionID)
        XCTAssertNil(bare.report.since)

        let odd = try XCTUnwrap(ClaudeSessionStateReader.parse(Data(#"{"status":"idle","pid":"4242","sessionId":9,"statusUpdatedAt":"soon","cwd":[],"future":{"a":1}}"#.utf8), now: now))
        XCTAssertEqual(odd.state, .idle)
        XCTAssertNil(odd.pid)
        XCTAssertNil(odd.sessionID)
        XCTAssertNil(odd.statusUpdatedAt)
        XCTAssertNil(odd.cwd)

        XCTAssertNil(ClaudeSessionStateReader.parse(session(status: nil), now: now))
        XCTAssertNil(ClaudeSessionStateReader.parse(Data(#"{"status":3}"#.utf8), now: now))
        XCTAssertNil(ClaudeSessionStateReader.parse(Data(#"{"pid":99999999999,"status":"idle"}"#.utf8), now: now)?.pid)
    }

    func testStatusTimeFormats() {
        let cases: [(json: String, expected: Date?)] = [
            (#"{"status":"idle","statusUpdatedAt":1791199000000}"#, Date(timeIntervalSince1970: 1_791_199_000)),
            (#"{"status":"idle","statusUpdatedAt":1791199000}"#, Date(timeIntervalSince1970: 1_791_199_000)),
            (#"{"status":"idle","statusUpdatedAt":"2026-10-05T12:00:00.250Z"}"#, Date(timeIntervalSince1970: 1_791_201_600.25)),
            (#"{"status":"idle","statusUpdatedAt":"2026-10-05T12:00:00Z"}"#, Date(timeIntervalSince1970: 1_791_201_600)),
            (#"{"status":"idle","updatedAt":1791199000000}"#, Date(timeIntervalSince1970: 1_791_199_000)),
            (#"{"status":"idle","statusUpdatedAt":0}"#, nil),
            (#"{"status":"idle","statusUpdatedAt":-5}"#, nil),
        ]
        for (json, expected) in cases {
            let parsed = ClaudeSessionStateReader.parse(Data(json.utf8), now: now)?.statusUpdatedAt
            if let expected, let parsed {
                XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001, json)
            } else {
                XCTAssertEqual(parsed, expected, json)
            }
        }
    }

    func testNotUnderstoodShapes() {
        let full = String(decoding: session(status: "busy"), as: UTF8.self)
        let cases = [
            "",
            String(full.prefix(40)),
            String(full.dropLast(1)),
            "[]",
            #"["status","busy"]"#,
            #""busy""#,
            "null",
            "not json",
        ]
        for text in cases {
            XCTAssertNil(ClaudeSessionStateReader.parse(Data(text.utf8), now: now), text)
        }
        XCTAssertNil(ClaudeSessionStateReader.parse(Data([0xFF, 0xFE, 0x00]), now: now))
    }

    func testReadsFileForPid() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try session(status: "waiting").write(to: directory.appendingPathComponent("4242.json"))
        try session(status: "idle").write(to: directory.appendingPathComponent("77.json"))
        try Data(#"{"status":"busy"}"#.utf8).write(to: directory.appendingPathComponent("88.json"))
        try Data(#"{"status":"bus"#.utf8).write(to: directory.appendingPathComponent("99.json"))
        try Data("secret".utf8).write(to: directory.appendingPathComponent("4242.abcdef.key"))

        let reader = ClaudeSessionStateReader(sessionsDirectory: directory)
        let report = try XCTUnwrap(reader.report(forPid: 4242, now: now))
        XCTAssertEqual(report.state, .waitingForUser)
        XCTAssertEqual(report.source, .claudeSessionFile)
        XCTAssertEqual(report.observedAt, now)
        // The file names pid 4242, so it does not describe pid 77.
        XCTAssertNil(reader.report(forPid: 77, now: now))
        // A file without a pid key takes the pid of its name.
        XCTAssertEqual(reader.state(forPid: 88, now: now)?.pid, 88)
        XCTAssertNil(reader.report(forPid: 99, now: now))
        XCTAssertNil(reader.report(forPid: 1, now: now))
        XCTAssertEqual(reader.allStates(now: now).compactMap(\.pid).sorted(), [88, 4242])
    }

    func testMissingDirectory() {
        let reader = ClaudeSessionStateReader(sessionsDirectory: URL(fileURLWithPath: "/nonexistent/caffeinagent-\(UUID().uuidString)"))
        XCTAssertNil(reader.report(forPid: 1, now: now))
        XCTAssertTrue(reader.allStates(now: now).isEmpty)
    }

    func testJobStates() {
        let cases: [(json: String, state: ReportedState?, finished: Bool?)] = [
            (#"{"state":"working","tempo":"active","inFlight":{"tasks":0,"queued":0,"kinds":[]}}"#, .working, false),
            (#"{"state":"blocked","tempo":"active","inFlight":{"tasks":2,"queued":0,"kinds":["local_bash"]}}"#, .working, false),
            (#"{"state":"blocked","tempo":"idle","inFlight":{"tasks":0,"queued":0,"kinds":[]}}"#, .waitingForUser, false),
            (#"{"state":"blocked"}"#, .waitingForUser, false),
            (#"{"state":"done","tempo":"idle","inFlight":{"tasks":0}}"#, .idle, true),
            (#"{"state":"paused"}"#, nil, nil),
            (#"{"tempo":"active"}"#, nil, nil),
            (#"{"state":"work"#, nil, nil),
        ]
        for (json, state, finished) in cases {
            let parsed = ClaudeJobStateReader.parse(Data(json.utf8), now: now)
            XCTAssertEqual(parsed?.state, state, json)
            XCTAssertEqual(parsed?.isFinished, finished, json)
            XCTAssertEqual(parsed?.report.state, state, json)
        }
    }

    func testReadsJobFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString)")
        let job = directory.appendingPathComponent("ab12cd34")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"state":"working","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/tmp/demo","updatedAt":"2026-10-05T12:00:00.250Z","inFlight":{"tasks":1}}"#.utf8)
            .write(to: job.appendingPathComponent("state.json"))

        let reader = ClaudeJobStateReader(jobsDirectory: directory)
        let state = try XCTUnwrap(reader.state(forJobID: "ab12cd34", now: now))
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.tasksInFlight, 1)
        XCTAssertEqual(state.sessionID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(state.cwd, "/tmp/demo")
        XCTAssertEqual(try XCTUnwrap(state.updatedAt).timeIntervalSince1970, 1_791_201_600.25, accuracy: 0.001)
        XCTAssertEqual(state.report.source, .claudeJobState)
        XCTAssertNil(reader.state(forJobID: "missing", now: now))
        XCTAssertNil(reader.state(forJobID: "../ab12cd34", now: now))
        XCTAssertNil(reader.state(forJobID: "", now: now))
    }

    func testTranscriptFallback() {
        let written = Date(timeIntervalSince1970: 1_791_199_900)
        let tool = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"make"}}]}}"#
        let prompt = #"{"type":"user","message":{"role":"user","content":"build it"}}"#
        let done = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Built."}],"stop_reason":"end_turn"}}"#
        let meta = #"{"type":"system","subtype":"turn_duration","durationMs":900}"#
        let cases: [(lines: [String], state: ReportedState?, detail: String?)] = [
            ([prompt], .working, "in a turn"),
            ([prompt, tool], .working, "running a tool"),
            ([prompt, tool, done, meta], .idle, nil),
            ([meta], nil, nil),
            ([], nil, nil),
        ]
        for (lines, state, detail) in cases {
            let parsed = ClaudeTranscriptReader.parseTail(lines.joined(separator: "\n"))
            let report = ClaudeTranscriptReader.report(from: parsed, lastWrite: written, now: now)
            XCTAssertEqual(report?.state, state, "\(lines.count) lines")
            XCTAssertEqual(report?.detail, detail, "\(lines.count) lines")
            if let report {
                XCTAssertEqual(report.source, .claudeTranscript)
                XCTAssertEqual(report.since, written)
                XCTAssertEqual(report.observedAt, now)
            }
        }
    }

    func testTranscriptFileFallback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString).jsonl")
        try Data((#"{"type":"user","message":{"role":"user","content":"build it"}}"# + "\n").utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = try XCTUnwrap(ClaudeTranscriptReader().report(forTranscript: url, now: now))
        XCTAssertEqual(report.state, .working)
        XCTAssertNotNil(report.since)
        XCTAssertNil(ClaudeTranscriptReader().report(forTranscript: url.appendingPathExtension("missing"), now: now))
    }
}
