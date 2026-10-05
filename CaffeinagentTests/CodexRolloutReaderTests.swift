import XCTest

final class CodexRolloutReaderTests: XCTestCase {
    private let turnA = "0199aaaa-0000-7000-8000-00000000000a"
    private let turnB = "0199aaaa-0000-7000-8000-00000000000b"
    private let meta = #"{"timestamp":"2026-10-05T12:00:00.000Z","ordinal":0,"type":"session_meta","payload":{"session_id":"s1","id":"01a10000-aaaa-7000-8000-00000000c78f","timestamp":"2026-10-05T12:00:00.000Z","cwd":"/tmp/demo","originator":"codex-tui","base_instructions":{"text":"Be brief."}}}"#
    private let message = #"{"timestamp":"2026-10-05T12:00:03.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Looking at the build."}]}}"#
    private let toolCall = #"{"timestamp":"2026-10-05T12:00:04.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","status":"completed"}}"#
    private let tokenCount = #"{"timestamp":"2026-10-05T12:00:05.000Z","type":"event_msg","payload":{"type":"token_count"}}"#

    private func started(_ turn: String?, at seconds: Int = 1_791_201_602) -> String {
        let id = turn.map { #""turn_id":"\#($0)","# } ?? ""
        return #"{"timestamp":"2026-10-05T12:00:02.500Z","type":"event_msg","payload":{"type":"task_started",\#(id)"started_at":\#(seconds)}}"#
    }

    private func complete(_ turn: String?, at seconds: Int = 1_791_201_660) -> String {
        let id = turn.map { #""turn_id":"\#($0)","# } ?? ""
        return #"{"timestamp":"2026-10-05T12:01:00.500Z","type":"event_msg","payload":{"type":"task_complete",\#(id)"completed_at":\#(seconds),"duration_ms":58000,"last_agent_message":"Done."}}"#
    }

    private func aborted(_ turn: String?, reason: String = "interrupted") -> String {
        let id = turn.map { #""turn_id":"\#($0)","# } ?? ""
        return #"{"timestamp":"2026-10-05T12:00:30.000Z","type":"event_msg","payload":{"type":"turn_aborted",\#(id)"reason":"\#(reason)"}}"#
    }

    private func context(cwd: String) -> String {
        #"{"timestamp":"2026-10-05T12:00:02.600Z","type":"turn_context","payload":{"cwd":"\#(cwd)","turn_id":"x","model":"gpt"}}"#
    }

    private func lines(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

    func testTurnStates() {
        let cases: [(name: String, lines: [String], state: ReportedState?, marker: CodexTurnState.Marker?)] = [
            ("started only", [meta, started(turnA), message, toolCall], .working, .started),
            ("started then complete", [meta, started(turnA), message, tokenCount, complete(turnA)], .idle, .completed),
            ("started then aborted", [started(turnA), message, aborted(turnA)], .idle, .aborted),
            ("two turns, second open", [started(turnA), complete(turnA), started(turnB), message], .working, .started),
            ("two turns, both closed", [started(turnA), complete(turnA), started(turnB), aborted(turnB)], .idle, .aborted),
            ("only old turns", [complete(turnA), tokenCount, message], .idle, .completed),
            ("new turn replaces a running one", [started(turnA), started(turnB), aborted(turnA, reason: "replaced"), message], .working, .started),
            ("no turn ids, open", [started(nil), message], .working, .started),
            ("no turn ids, closed", [started(nil), complete(nil)], .idle, .completed),
            ("end without id closes a turn with id", [started(turnA), complete(nil)], .idle, .completed),
            ("no markers", [meta, message, tokenCount], nil, nil),
            ("marker name in a message is not a marker", [#"{"type":"response_item","payload":{"type":"message","content":[{"type":"output_text","text":"task_started"}]}}"#], nil, nil),
            ("marker under another record type", [#"{"type":"response_item","payload":{"type":"task_started","turn_id":"x"}}"#], nil, nil),
            ("empty", [], nil, nil),
        ]
        for (name, input, state, marker) in cases {
            let parsed = CodexRolloutReader.parseTail(lines(input))
            XCTAssertEqual(parsed.state, state, name)
            XCTAssertEqual(parsed.lastMarker, marker, name)
            XCTAssertEqual(parsed.turnInProgress, state == .working, name)
        }
    }

    func testMarkerTimeAndTurn() {
        let open = CodexRolloutReader.parseTail(lines([started(turnA), complete(turnA), started(turnB, at: 1_791_201_700)]))
        XCTAssertEqual(open.turnID, turnB)
        XCTAssertEqual(open.markerAt, Date(timeIntervalSince1970: 1_791_201_700))

        let closed = CodexRolloutReader.parseTail(lines([started(turnA), complete(turnA)]))
        XCTAssertEqual(closed.turnID, turnA)
        XCTAssertEqual(closed.markerAt, Date(timeIntervalSince1970: 1_791_201_660))

        // An abort record has no own time here, so the record timestamp is used.
        let stopped = CodexRolloutReader.parseTail(lines([started(turnA), aborted(turnA)]))
        XCTAssertEqual(try XCTUnwrap(stopped.markerAt).timeIntervalSince1970, 1_791_201_630, accuracy: 0.001)

        let replaced = CodexRolloutReader.parseTail(lines([started(turnA), started(turnB, at: 1_791_201_700), aborted(turnA, reason: "replaced")]))
        XCTAssertEqual(replaced.turnID, turnB)
        XCTAssertEqual(replaced.markerAt, Date(timeIntervalSince1970: 1_791_201_700))
    }

    func testTailStartingMidLine() {
        let cut = String(complete(turnA).dropFirst(45))
        let open = CodexRolloutReader.parseTail(lines([cut, started(turnB), message]))
        XCTAssertEqual(open.state, .working)
        XCTAssertEqual(open.turnID, turnB)

        let cutStart = String(started(turnA).dropFirst(45))
        XCTAssertEqual(CodexRolloutReader.parseTail(lines([cutStart, message, complete(turnA)])).state, .idle)
        XCTAssertNil(CodexRolloutReader.parseTail(lines([cutStart, message])).state)
        // A last line that is still being written.
        let partial = String(complete(turnA).prefix(60))
        XCTAssertEqual(CodexRolloutReader.parseTail(lines([started(turnA), message]) + partial).state, .working)
    }

    func testTailCwdComesFromNewestTurnContext() {
        let parsed = CodexRolloutReader.parseTail(lines([started(turnA), context(cwd: "/tmp/old"), complete(turnA), started(turnB), context(cwd: "/tmp/new"), message]))
        XCTAssertEqual(parsed.cwd, "/tmp/new")
        XCTAssertNil(CodexRolloutReader.parseTail(lines([started(turnA), message])).cwd)
    }

    func testSessionIDFromFileName() {
        let cases: [(name: String, id: String?)] = [
            ("rollout-2026-10-05T15-00-00-01a10000-aaaa-7000-8000-00000000c78f.jsonl", "01a10000-aaaa-7000-8000-00000000c78f"),
            ("rollout-2026-10-05T15-00-00-01a10000-aaaa-7000-8000-00000000c78f", "01a10000-aaaa-7000-8000-00000000c78f"),
            ("rollout-2026-10-05T15-00-00.jsonl", nil),
            ("rollout-.jsonl", nil),
            ("", nil),
        ]
        for (name, id) in cases {
            XCTAssertEqual(CodexRolloutReader.sessionID(fromFileName: name), id, name)
        }
    }

    func testSessionCwd() {
        XCTAssertEqual(CodexRolloutReader.sessionCwd(firstLine: Data(meta.utf8)), "/tmp/demo")
        XCTAssertNil(CodexRolloutReader.sessionCwd(firstLine: Data(message.utf8)))
        XCTAssertNil(CodexRolloutReader.sessionCwd(firstLine: Data(meta.prefix(120).utf8)))
        XCTAssertNil(CodexRolloutReader.sessionCwd(firstLine: Data()))
    }

    func testLongRecordsReadFurther() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let big = #"{"type":"response_item","payload":{"type":"custom_tool_call_output","output":""# + String(repeating: "x", count: 100_000) + #""}}"#
        let bigMeta = #"{"type":"session_meta","payload":{"cwd":"/tmp/demo","base_instructions":{"text":""# + String(repeating: "y", count: 100_000) + #""}}}"#
        let text = lines([bigMeta, started(turnA), big])
        XCTAssertNil(CodexRolloutReader.parseTail(String(text.suffix(65_536))).state)

        let url = directory.appendingPathComponent("rollout-2026-10-05T15-00-00-01a10000-aaaa-7000-8000-00000000c78f.jsonl")
        try Data(text.utf8).write(to: url)
        XCTAssertEqual(CodexRolloutReader.parseTail(of: url).state, .working)
        XCTAssertEqual(CodexRolloutReader.sessionCwd(of: url), "/tmp/demo")
        XCTAssertNil(CodexRolloutReader.parseTail(of: directory.appendingPathComponent("missing.jsonl")).state)
        XCTAssertNil(CodexRolloutReader.sessionCwd(of: directory.appendingPathComponent("missing.jsonl")))
    }

    func testFindsRecentFilesNewestFirst() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let files: [(path: String, id: String, age: TimeInterval, lines: [String])] = [
            ("2026/10/03", "01a10000-0000-7000-8000-000000000001", 3_600, [meta, started(turnA), message]),
            ("2026/10/05", "01a10000-0000-7000-8000-000000000002", 60, [meta, started(turnA), complete(turnA)]),
            ("2026/10/04", "01a10000-0000-7000-8000-000000000003", 7_200, [started(turnA), context(cwd: "/tmp/from-context")]),
            ("2026/09/01", "01a10000-0000-7000-8000-000000000004", 200_000, [meta, started(turnA)]),
        ]
        for file in files {
            let day = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
            let url = day.appendingPathComponent("rollout-2026-10-05T15-00-00-\(file.id).jsonl")
            try Data(lines(file.lines).utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-file.age)], ofItemAtPath: url.path)
        }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("2026/10/05/notes.jsonl"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("2026/10/05/rollout-other.txt"))

        let reader = CodexRolloutReader(sessionsDirectory: directory)
        let recent = reader.rollouts(now: now)
        XCTAssertEqual(recent.map(\.file.sessionID), [files[1].id, files[0].id, files[2].id])
        XCTAssertEqual(recent.map(\.turn.state), [.idle, .working, .working])
        XCTAssertEqual(recent.map(\.cwd), ["/tmp/demo", "/tmp/demo", "/tmp/from-context"])
        XCTAssertEqual(recent.map { CodexRolloutReader.report(for: $0, now: now)?.state }, [.idle, .working, .working])
        XCTAssertEqual(CodexRolloutReader.report(for: recent[1], now: now)?.source, .codexRollout)
        XCTAssertGreaterThan(recent[0].file.size, 0)
        XCTAssertEqual(recent[0].file.lastWrite.timeIntervalSince1970, now.addingTimeInterval(-60).timeIntervalSince1970, accuracy: 1)

        XCTAssertEqual(reader.recentFiles(maxAge: 600, now: now).map(\.sessionID), [files[1].id])
        XCTAssertEqual(reader.recentFiles(maxAge: 300_000, now: now).count, 4)
        XCTAssertTrue(CodexRolloutReader(sessionsDirectory: directory.appendingPathComponent("missing")).rollouts(now: now).isEmpty)
    }

    private func output(bytes: Int) -> String {
        #"{"timestamp":"2026-10-05T12:00:06.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","output":""# + String(repeating: "x", count: bytes) + #""}}"#
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func makeRollout(_ text: String) throws -> URL {
        let directory = try makeDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollout-2026-10-05T15-00-00-01a10000-aaaa-7000-8000-00000000c78f.jsonl")
        try Data(text.utf8).write(to: url)
        return url
    }

    func testMarkersInFileOrder() {
        typealias Step = (CodexTurnState.Marker, String?)
        let cases: [(name: String, steps: [Step], working: Bool, marker: CodexTurnState.Marker, turn: String?)] = [
            ("start", [(.started, turnA)], true, .started, turnA),
            ("start, end", [(.started, turnA), (.completed, turnA)], false, .completed, turnA),
            ("end of an older turn", [(.started, turnA), (.started, turnB), (.aborted, turnA)], true, .started, turnB),
            ("end without id", [(.started, turnA), (.completed, nil)], false, .completed, nil),
            ("start without id", [(.started, nil), (.aborted, turnA)], false, .aborted, turnA),
            ("end with nothing open", [(.completed, turnA)], false, .completed, turnA),
            ("second turn", [(.started, turnA), (.completed, turnA), (.started, turnB)], true, .started, turnB),
        ]
        for (name, steps, working, marker, turn) in cases {
            var state = CodexTurnState()
            for step in steps { state.note(step.0, turnID: step.1, at: nil) }
            XCTAssertEqual(state.turnInProgress, working, name)
            XCTAssertEqual(state.lastMarker, marker, name)
            XCTAssertEqual(state.turnID, turn, name)
        }
    }

    func testTurnThatWroteMoreThanOneMegabyte() throws {
        let filler = Array(repeating: output(bytes: 100_000), count: 30)
        let url = try makeRollout(lines([meta, started(turnA), context(cwd: "/tmp/long")] + filler))
        XCTAssertEqual(CodexRolloutReader.parseTail(of: url).state, .working)
        XCTAssertEqual(CodexRolloutReader.parseTail(of: url).cwd, "/tmp/long")

        var tracker = CodexRolloutTracker()
        let reading = try XCTUnwrap(tracker.read(path: url.path))
        XCTAssertTrue(reading.resolved)
        XCTAssertEqual(reading.turn.state, .working)
        XCTAssertEqual(reading.turn.turnID, turnA)

        // One line that is longer than the tracker keeps in memory.
        let long = try makeRollout(lines([started(turnB), output(bytes: 5_000_000), output(bytes: 2_000_000)]))
        XCTAssertEqual(CodexRolloutReader.parseTail(of: long).turnID, turnB)
        XCTAssertEqual(CodexRolloutReader.parseTail(of: long).state, .working)
    }

    func testLongSearchIsSpreadOverSamplesAndIsUnknownMeanwhile() throws {
        let filler = Array(repeating: output(bytes: 100_000), count: 35)
        let url = try makeRollout(lines([started(turnA)] + filler))
        var tracker = CodexRolloutTracker(searchBudget: 1_048_576)
        var reads = 0
        var reading = try XCTUnwrap(tracker.read(path: url.path))
        while !reading.resolved, reads < 10 {
            XCTAssertNil(reading.turn.state, "No state before the marker is found")
            tracker.endSample()
            reads += 1
            reading = try XCTUnwrap(tracker.read(path: url.path))
        }
        XCTAssertEqual(reads, 3, "About one megabyte per sample")
        XCTAssertEqual(reading.turn.state, .working)

        // A marker that is appended during the search settles the state at once.
        let other = try makeRollout(lines([started(turnA)] + filler))
        tracker = CodexRolloutTracker(searchBudget: 1_048_576)
        XCTAssertFalse(try XCTUnwrap(tracker.read(path: other.path)).resolved)
        tracker.endSample()
        try append(lines([complete(turnA)]), to: other)
        let settled = try XCTUnwrap(tracker.read(path: other.path))
        XCTAssertTrue(settled.resolved)
        XCTAssertEqual(settled.turn.state, .idle)
    }

    func testOnlyAppendedBytesAreParsed() throws {
        let url = try makeRollout(lines([meta, started(turnA)] + Array(repeating: output(bytes: 100_000), count: 20)))
        var tracker = CodexRolloutTracker()
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .working)
        // With no budget left, only the forward read can give these answers.
        tracker.searchBudget = 0
        tracker.endSample()

        try append(lines([output(bytes: 2_000_000), message]), to: url)
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .working)
        tracker.endSample()

        let end = complete(turnA) + "\n"
        try append(String(end.prefix(60)), to: url)
        let partial = try XCTUnwrap(tracker.read(path: url.path))
        XCTAssertEqual(partial.turn.state, .working, "A last line that is still being written")
        XCTAssertTrue(partial.resolved)
        tracker.endSample()

        try append(String(end.dropFirst(60)), to: url)
        let closed = try XCTUnwrap(tracker.read(path: url.path))
        XCTAssertEqual(closed.turn.state, .idle)
        XCTAssertEqual(closed.turn.markerAt, Date(timeIntervalSince1970: 1_791_201_660))
        tracker.endSample()

        try append(lines([started(turnB, at: 1_791_201_700), context(cwd: "/tmp/next"), aborted(turnA, reason: "replaced")]), to: url)
        let next = try XCTUnwrap(tracker.read(path: url.path))
        XCTAssertEqual(next.turn.state, .working)
        XCTAssertEqual(next.turn.turnID, turnB)
        XCTAssertEqual(next.turn.cwd, "/tmp/next")
    }

    func testPartialLastLineOnFirstRead() throws {
        let url = try makeRollout(lines([started(turnA), message]) + String(complete(turnA).prefix(60)))
        var tracker = CodexRolloutTracker()
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .working)
        tracker.endSample()
        try append(String(complete(turnA).dropFirst(60)) + "\n", to: url)
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .idle)
    }

    func testTruncatedOrReplacedFileIsReadAgain() throws {
        let url = try makeRollout(lines([started(turnA), message, message]))
        var tracker = CodexRolloutTracker()
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .working)
        tracker.endSample()

        // Shorter, same inode.
        try Data(lines([complete(turnB)]).utf8).write(to: url)
        XCTAssertEqual(tracker.read(path: url.path)?.turn.turnID, turnB)
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .idle)
        tracker.endSample()

        // Longer, same inode, other content.
        try Data(lines([message, message, started(turnA), message, message]).utf8).write(to: url)
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .working)
        tracker.endSample()

        // Another file under the same name.
        try Data(lines([started(turnA), message, message, message, message, complete(turnA)]).utf8).write(to: url, options: .atomic)
        XCTAssertEqual(tracker.read(path: url.path)?.turn.state, .idle)
        tracker.endSample()

        try FileManager.default.removeItem(at: url)
        XCTAssertNil(tracker.read(path: url.path))
    }

    func testFileWithNoMarkerIsResolvedWithNoState() throws {
        let url = try makeRollout(lines([meta, message]))
        var tracker = CodexRolloutTracker()
        let reading = try XCTUnwrap(tracker.read(path: url.path))
        XCTAssertTrue(reading.resolved)
        XCTAssertNil(reading.turn.state)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
