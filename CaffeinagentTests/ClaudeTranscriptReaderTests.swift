import XCTest

final class ClaudeTranscriptReaderTests: XCTestCase {
    private let toolRunning = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Running the tests."},{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"swift test"}}]},"uuid":"a1"}"#
    private let done = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All tests pass."}],"stop_reason":"end_turn"},"uuid":"a2"}"#
    private let prompt = #"{"type":"user","message":{"role":"user","content":"run the tests"},"uuid":"u1"}"#
    private let turnDuration = #"{"type":"system","subtype":"turn_duration","durationMs":41250}"#
    private let lastPrompt = #"{"type":"last-prompt","lastPrompt":"run the tests"}"#
    private let title = #"{"type":"ai-title","aiTitle":"Run the test suite"}"#

    private func toolResult(_ content: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":""# + content + #""}]},"uuid":"u2"}"#
    }

    private func lines(_ lines: String...) -> String { lines.joined(separator: "\n") + "\n" }

    func testToolRunningIsActive() {
        let parsed = ClaudeTranscriptReader.parseTail(lines(title, prompt, toolRunning))
        XCTAssertEqual(parsed.lastTurn, "assistant")
        XCTAssertTrue(parsed.turnInProgress)
    }

    func testDoneFollowedByMetadataIsWaiting() {
        let parsed = ClaudeTranscriptReader.parseTail(lines(prompt, toolRunning, toolResult("ok"), done, turnDuration, lastPrompt))
        XCTAssertEqual(parsed.lastTurn, "assistant")
        XCTAssertFalse(parsed.turnInProgress)
    }

    func testToolResultIsActive() {
        let parsed = ClaudeTranscriptReader.parseTail(lines(prompt, toolRunning, toolResult("Executed 42 tests, with 0 failures")))
        XCTAssertEqual(parsed.lastTurn, "user")
        XCTAssertTrue(parsed.turnInProgress)
    }

    private func assistant(stop: String?) -> String {
        let reason = stop.map { #""\#($0)""# } ?? "null"
        return #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Checking the apples."}],"stop_reason":\#(reason)},"uuid":"a3"}"#
    }

    func testInterruptEndsTheTurn() {
        let asText = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"uuid":"u3"}"#
        let forTool = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]},"uuid":"u4"}"#
        let asString = #"{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"},"uuid":"u5"}"#
        for interrupt in [asText, forTool, asString] {
            let parsed = ClaudeTranscriptReader.parseTail(lines(prompt, toolRunning, interrupt, lastPrompt))
            XCTAssertEqual(parsed.lastTurn, "user")
            XCTAssertFalse(parsed.turnInProgress, interrupt)
        }
        // A prompt after the interrupt starts the next turn.
        XCTAssertTrue(ClaudeTranscriptReader.parseTail(lines(toolRunning, asText, prompt)).turnInProgress)
        // A prompt that only quotes the marker is a prompt.
        let quoting = #"{"type":"user","message":{"role":"user","content":"why did it say [Request interrupted by user]"},"uuid":"u6"}"#
        XCTAssertTrue(ClaudeTranscriptReader.parseTail(lines(quoting)).turnInProgress)
    }

    func testMetaUserLinesAreSkipped() {
        let meta = #"{"type":"user","isMeta":true,"message":{"role":"user","content":"Caveat: the lines below came from local commands."},"uuid":"u7"}"#
        let afterDone = ClaudeTranscriptReader.parseTail(lines(prompt, assistant(stop: "end_turn"), meta, turnDuration))
        XCTAssertEqual(afterDone.lastTurn, "assistant")
        XCTAssertFalse(afterDone.turnInProgress)
        XCTAssertTrue(ClaudeTranscriptReader.parseTail(lines(prompt, toolRunning, meta)).turnInProgress)
        XCTAssertNil(ClaudeTranscriptReader.parseTail(lines(meta)).lastTurn)
    }

    func testAssistantStopReason() {
        let cases: [(stop: String?, working: Bool)] = [
            ("tool_use", true), (nil, true), ("end_turn", false), ("stop_sequence", false), ("max_tokens", false),
        ]
        for (stop, working) in cases {
            let parsed = ClaudeTranscriptReader.parseTail(lines(prompt, assistant(stop: stop)))
            XCTAssertEqual(parsed.turnInProgress, working, stop ?? "null")
        }
        let toolEnded = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_02","name":"Read","input":{}}],"stop_reason":"tool_use"},"uuid":"a4"}"#
        XCTAssertTrue(ClaudeTranscriptReader.parseTail(lines(prompt, toolEnded)).turnInProgress)
    }

    func testCutOffFirstLineIsSkipped() {
        let fragment = String(toolRunning.dropFirst(60))
        let onlyFragment = ClaudeTranscriptReader.parseTail(lines(fragment, turnDuration))
        XCTAssertNil(onlyFragment.lastTurn)
        let parsed = ClaudeTranscriptReader.parseTail(lines(fragment, done, lastPrompt))
        XCTAssertEqual(parsed.lastTurn, "assistant")
        XCTAssertFalse(parsed.turnInProgress)
    }

    func testOverlongLastLineReadsFurtherBack() throws {
        // A tool result larger than the 16KB window, as a big diff or log produces.
        let big = toolResult(String(repeating: "x", count: 40_000))
        let text = lines(prompt, toolRunning, big)
        XCTAssertNil(ClaudeTranscriptReader.parseTail(String(text.suffix(16_384))).lastTurn)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let parsed = ClaudeTranscriptReader.parseTail(of: url)
        XCTAssertEqual(parsed.lastTurn, "user")
        XCTAssertTrue(parsed.turnInProgress)
    }

    func testSmallFileReadsWhole() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString).jsonl")
        try Data(lines(prompt, done, turnDuration).utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let parsed = ClaudeTranscriptReader.parseTail(of: url)
        XCTAssertEqual(parsed.lastTurn, "assistant")
        XCTAssertFalse(parsed.turnInProgress)
    }
}
