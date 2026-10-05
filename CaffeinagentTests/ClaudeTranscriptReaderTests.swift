import XCTest

final class ClaudeTranscriptReaderTests: XCTestCase {
    private let toolRunning = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Running the tests."},{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"swift test"}}]},"uuid":"a1"}"#
    private let done = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All tests pass."}]},"uuid":"a2"}"#
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
