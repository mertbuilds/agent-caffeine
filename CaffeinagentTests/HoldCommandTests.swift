import XCTest

final class HoldCommandTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)

    private var directory: URL!
    private var store: HoldStore!
    private var seconds: TimeInterval = 0
    private var processes: [Int32: TimeInterval] = [:]
    private var lock: HoldStore.AppLock?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hold-cli-\(UUID().uuidString)/holds")
        store = HoldStore(directory: directory)
        seconds = 0
        processes = [:]
        lock = nil
    }

    override func tearDownWithError() throws {
        lock = nil
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private var tools: HoldTools {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return HoldTools(
            store: store, now: { [unowned self] in Self.start.addingTimeInterval(self.seconds) },
            startTime: { [unowned self] in self.processes[$0] }, calendar: calendar, locale: Locale(identifier: "en_GB")
        )
    }

    /// Stands in for the app: it holds the lock, and says what it decided.
    private func startApp(awake: Bool = true, line: String = "Your Mac stays awake: A command asked for it", stopped: Bool = false) {
        lock = lock ?? HoldStore.AppLock(store: store)
        store.write(HoldStore.Status(awake: awake, line: line, stopped: stopped))
    }

    private func parse(_ arguments: String...) -> HoldInvocation? {
        try? HoldArguments.parse(arguments).get()
    }

    private func refusal(_ arguments: String...) -> String? {
        if case .failure(let error) = HoldArguments.parse(arguments) { return error.message }
        return nil
    }

    // MARK: Arguments

    func testTheCommands() {
        XCTAssertEqual(parse("hold", "--for", "30m"), .hold(length: 1800, reason: nil, json: false))
        XCTAssertEqual(parse("hold", "--reason", "render", "--for", "90s", "--json"), .hold(length: 90, reason: "render", json: true))
        XCTAssertEqual(parse("hold"), .hold(length: 3600, reason: nil, json: false), "One hour with no --for")
        XCTAssertEqual(parse("hold", "--", "ffmpeg", "-i", "a.mov"), .run(command: ["ffmpeg", "-i", "a.mov"], reason: nil))
        XCTAssertEqual(parse("hold", "--reason", "render", "--", "make", "--for", "x"), .run(command: ["make", "--for", "x"], reason: "render"))
        XCTAssertEqual(parse("release"), .release(.only))
        XCTAssertEqual(parse("release", "--all"), .release(.all))
        XCTAssertEqual(parse("release", "0a1b2c3d"), .release(.id("0a1b2c3d")))
        XCTAssertEqual(parse("status"), .status(json: false))
        XCTAssertEqual(parse("status", "--json"), .status(json: true))
        XCTAssertEqual(parse("mcp"), .mcp)
        XCTAssertEqual(parse(), .help)
        XCTAssertEqual(parse("--help"), .help)
    }

    func testATimedHoldOfMoreThanTwelveHoursIsRefused() {
        XCTAssertEqual(parse("hold", "--for", "12h"), .hold(length: 12 * 3600, reason: nil, json: false))
        XCTAssertEqual(refusal("hold", "--for", "12h1s"), "A hold lasts 12 hours at most. Ask for a shorter time, and ask again when it ends.")
        XCTAssertEqual(refusal("hold", "--for", "3d"), "--for takes a time such as 90s, 30m or 2h.")
    }

    func testWhatIsRefused() {
        XCTAssertNotNil(refusal("hold", "--for"))
        XCTAssertNotNil(refusal("hold", "--reason"))
        XCTAssertNotNil(refusal("hold", "ffmpeg"), "A command comes after --")
        XCTAssertNotNil(refusal("hold", "--"))
        XCTAssertNotNil(refusal("hold", "--for", "30m", "--", "make"))
        XCTAssertNotNil(refusal("hold", "--json", "--", "make"))
        XCTAssertNotNil(refusal("release", "../x"))
        XCTAssertNotNil(refusal("release", "a", "b"))
        XCTAssertNotNil(refusal("status", "--all"))
        XCTAssertNotNil(refusal("sleep"))
    }

    // MARK: Hold

    func testATimedHoldIsWrittenWhileTheAppRuns() throws {
        startApp()
        let outcome = HoldCommands.hold(length: 1800, reason: "Nightly\nbackup", json: false, tools: tools)
        let hold = try XCTUnwrap(tools.liveHolds.first)
        XCTAssertEqual(outcome, HoldOutcome(out: ["Agent Caffeine keeps your Mac awake until 12:03. Hold \(hold.id)."]))
        XCTAssertEqual(hold.kind, .timed)
        XCTAssertEqual(hold.reason, "Nightly backup")
        XCTAssertEqual(hold.end - hold.start, 1800)
        XCTAssertNil(hold.pid)
    }

    func testATimedHoldIsRefusedWhileTheAppDoesNotRun() {
        let outcome = HoldCommands.hold(length: 1800, reason: nil, json: false, tools: tools)
        XCTAssertEqual(outcome, HoldOutcome(code: 1, err: [HoldCommands.notRunning]))
        XCTAssertEqual(tools.liveHolds, [], "No hold that nothing honours")
    }

    func testTheCapHoldsWhateverTheCallerIs() {
        startApp()
        XCTAssertEqual(HoldCommands.hold(length: ManualHold.timedCap + 1, reason: nil, json: false, tools: tools).code, 1)
        XCTAssertEqual(tools.liveHolds, [])
    }

    func testAHoldAsJSON() throws {
        startApp()
        let outcome = HoldCommands.hold(length: 90, reason: "render", json: true, tools: tools)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(outcome.out.first).utf8)) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "timed")
        XCTAssertEqual(object["reason"] as? String, "render")
        XCTAssertEqual(object["appRunning"] as? Bool, true)
        XCTAssertEqual(object["id"] as? String, tools.liveHolds.first?.id)
        XCTAssertEqual((object["end"] as? Double).map { $0 - Self.start.timeIntervalSince1970 }, 90)
    }

    func testAStopIsSaidWithTheHold() {
        startApp(awake: false, line: "Agent Caffeine is paused: Starts again at 15:30", stopped: true)
        let outcome = HoldCommands.hold(length: 600, reason: nil, json: false, tools: tools)
        XCTAssertEqual(outcome.code, 0)
        XCTAssertEqual(outcome.err, ["Agent Caffeine is paused: Starts again at 15:30. The hold counts when that ends."])
        XCTAssertEqual(tools.liveHolds.count, 1)
    }

    // MARK: A command

    func testACommandHoldsWhileItsHolderRuns() throws {
        startApp()
        processes[700] = 5000
        let begun = HoldCommands.beginRun(command: ["/usr/bin/make", "all"], reason: nil, holder: ProcessIdentity(pid: 700, startTime: 5000), tools: tools)
        XCTAssertEqual(begun.warnings, [])
        let hold = try XCTUnwrap(begun.hold)
        XCTAssertEqual(hold.command, "make")
        XCTAssertEqual(tools.liveHolds, [hold])
        processes[700] = nil
        XCTAssertEqual(tools.liveHolds, [], "The holder is gone")
        processes[700] = 6000
        XCTAssertEqual(tools.liveHolds, [], "The pid is another process now")
    }

    func testACommandRunsWithAWarningWhileTheAppDoesNotRun() {
        processes[700] = 5000
        let begun = HoldCommands.beginRun(command: ["make"], reason: nil, holder: ProcessIdentity(pid: 700, startTime: 5000), tools: tools)
        XCTAssertEqual(begun.warnings, [HoldCommands.notRunningForCommand])
        XCTAssertNotNil(begun.hold, "Written all the same, for an app that starts later")
    }

    func testACommandWithNoHolderRunsWithoutAHold() {
        startApp()
        let begun = HoldCommands.beginRun(command: ["make"], reason: nil, holder: nil, tools: tools)
        XCTAssertNil(begun.hold)
        XCTAssertEqual(begun.warnings.count, 1)
    }

    // MARK: Release and status

    func testRelease() {
        startApp()
        _ = HoldCommands.hold(length: 600, reason: "one", json: false, tools: tools)
        seconds = 1
        _ = HoldCommands.hold(length: 600, reason: "two", json: false, tools: tools)
        let ids = tools.liveHolds.map(\.id)
        let unsure = HoldCommands.release(.only, tools: tools)
        XCTAssertEqual(unsure.code, 2)
        XCTAssertEqual(unsure.err, ["There are 2 holds. Name one, or use --all:", "\(ids[0])  one, until 11:43", "\(ids[1])  two, until 11:43"])
        XCTAssertEqual(HoldCommands.release(.id(ids[0]), tools: tools), HoldOutcome(out: ["Released \(ids[0])."]))
        XCTAssertEqual(HoldCommands.release(.id(ids[0]), tools: tools), HoldOutcome(code: 1, err: ["There is no hold \(ids[0])."]))
        XCTAssertEqual(HoldCommands.release(.only, tools: tools), HoldOutcome(out: ["Released 1 hold."]))
        XCTAssertEqual(HoldCommands.release(.all, tools: tools), HoldOutcome(out: ["There is no hold to release."]))
    }

    func testStatusListsTheHoldsAndSaysWhetherTheMacCanSleep() {
        XCTAssertEqual(
            HoldCommands.status(json: false, tools: tools).out, ["No holds.", "Agent Caffeine is not running. Your Mac sleeps as usual."]
        )
        startApp(line: "Your Mac stays awake: 2 commands asked for it")
        _ = HoldCommands.hold(length: 2 * 3600, reason: "Nightly backup", json: false, tools: tools)
        processes[700] = 5000
        seconds = 1
        _ = HoldCommands.beginRun(command: ["ffmpeg"], reason: nil, holder: ProcessIdentity(pid: 700, startTime: 5000), tools: tools)
        seconds = 12 * 60 + 1
        let holds = tools.liveHolds
        XCTAssertEqual(HoldCommands.status(json: false, tools: tools).out, [
            "\(holds[0].id)  Nightly backup, until 13:33",
            "\(holds[1].id)  ffmpeg, while it runs, for 12 minutes",
            "Your Mac stays awake: 2 commands asked for it",
        ])
    }

    func testATimeThatIsNotTodaySaysTomorrow() {
        startApp()
        let outcome = HoldCommands.hold(length: 12 * 3600, reason: nil, json: false, tools: tools)
        // 11:33 and twelve hours.
        XCTAssertEqual(outcome.out.first?.contains("until 23:33."), true)
        seconds = 3600
        let late = HoldCommands.hold(length: 12 * 3600, reason: nil, json: false, tools: tools)
        XCTAssertEqual(late.out.first?.contains("until 00:33 tomorrow."), true)
    }

    func testStatusAsJSON() throws {
        startApp(awake: false, line: "Your Mac can sleep: No agent is open")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(HoldCommands.status(json: true, tools: tools).out[0].utf8)) as? [String: Any])
        XCTAssertEqual(object["appRunning"] as? Bool, true)
        XCTAssertEqual(object["awake"] as? Bool, false)
        XCTAssertEqual(object["line"] as? String, "Your Mac can sleep: No agent is open")
        XCTAssertEqual((object["holds"] as? [Any])?.count, 0)
        lock = nil
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(HoldCommands.status(json: true, tools: tools).out[0].utf8)) as? [String: Any])
        XCTAssertEqual(object["appRunning"] as? Bool, false)
        XCTAssertNil(object["awake"], "Only the app knows")
    }

    // MARK: A closed pipe

    /// As the tool does at its start, so a write to a closed pipe fails
    /// and ends no process.
    private func ignoringSIGPIPE(_ body: () throws -> Void) rethrows {
        let before = signal(SIGPIPE, SIG_IGN)
        defer { signal(SIGPIPE, before) }
        try body()
    }

    /// `agent-caffeine help | true`.
    func testAWriteToAClosedPipeFailsAndRaisesNothing() throws {
        try ignoringSIGPIPE {
            let closed = Pipe()
            try closed.fileHandleForReading.close()
            XCTAssertFalse(closed.fileHandleForWriting.put("Agent Caffeine\n"))
            let open = Pipe()
            XCTAssertTrue(open.fileHandleForWriting.put("Agent Caffeine\n"))
            try open.fileHandleForWriting.close()
            XCTAssertEqual(open.fileHandleForReading.readDataToEndOfFile(), Data("Agent Caffeine\n".utf8))
        }
    }

    func testTheServerStopsWhenItsAnswerCannotBeWritten() throws {
        startApp()
        _ = HoldCommands.hold(length: 600, reason: "from a script", json: false, tools: tools)
        let id = try XCTUnwrap(tools.liveHolds.first?.id)
        try ignoringSIGPIPE {
            let input = Pipe()
            let output = Pipe()
            let lines = try [request(1, "ping"), call(2, "release", ["id": id])].map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            input.fileHandleForWriting.write(Data((lines.joined(separator: "\n") + "\n").utf8))
            try input.fileHandleForWriting.close()
            try output.fileHandleForReading.close()
            MCPServer(tools: tools, version: "1").run(input: input.fileHandleForReading, output: output.fileHandleForWriting)
        }
        XCTAssertEqual(tools.liveHolds.map(\.id), [id], "The client is gone, and nothing more is done for it")
    }

    // MARK: MCP

    /// Sends the lines through pipes, as an agent does, and reads the answers.
    private func session(_ requests: [[String: Any]], raw: [String] = []) throws -> [[String: Any]] {
        let input = Pipe()
        let output = Pipe()
        let lines = try requests.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) } + raw
        input.fileHandleForWriting.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        input.fileHandleForWriting.closeFile()
        MCPServer(tools: tools, version: "1.2.3").run(input: input.fileHandleForReading, output: output.fileHandleForWriting)
        output.fileHandleForWriting.closeFile()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return try text.split(separator: "\n").map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }

    private func request(_ id: Int, _ method: String, _ parameters: [String: Any]? = nil) -> [String: Any] {
        var request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        request["params"] = parameters
        return request
    }

    private func call(_ id: Int, _ tool: String, _ arguments: [String: Any] = [:]) -> [String: Any] {
        request(id, "tools/call", ["name": tool, "arguments": arguments])
    }

    private func text(_ answer: [String: Any]) -> String? {
        let result = answer["result"] as? [String: Any]
        return ((result?["content"] as? [[String: Any]])?.first)?["text"] as? String
    }

    private func isError(_ answer: [String: Any]) -> Bool? {
        (answer["result"] as? [String: Any])?["isError"] as? Bool
    }

    func testTheHandshake() throws {
        let answers = try session([
            request(1, "initialize", ["protocolVersion": "2025-03-26", "capabilities": [String: Any](), "clientInfo": ["name": "test", "version": "1"]]),
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            request(2, "ping"),
            request(3, "tools/list"),
        ])
        XCTAssertEqual(answers.count, 3, "A notification gets no answer")
        XCTAssertEqual(answers.map { $0["id"] as? Int }, [1, 2, 3])
        XCTAssertEqual(answers.map { $0["jsonrpc"] as? String }, ["2.0", "2.0", "2.0"])
        let initialized = try XCTUnwrap(answers[0]["result"] as? [String: Any])
        XCTAssertEqual(initialized["protocolVersion"] as? String, "2025-03-26", "The version the client asked for, when we know it")
        XCTAssertNotNil((initialized["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((initialized["serverInfo"] as? [String: Any])?["name"] as? String, "agent-caffeine")
        XCTAssertEqual((initialized["serverInfo"] as? [String: Any])?["version"] as? String, "1.2.3")
        let listed = try XCTUnwrap((answers[2]["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(listed.map { $0["name"] as? String }, ["hold_awake", "release", "status"])
        for tool in listed {
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object")
            let description = try XCTUnwrap(tool["description"] as? String)
            XCTAssertFalse(description.isEmpty)
            XCTAssertFalse(description.contains("\u{2014}"))
        }
        let minutes = (((listed[0]["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])?["minutes"] as? [String: Any])
        XCTAssertEqual(minutes?["minimum"] as? Int, 1)
        XCTAssertEqual(minutes?["maximum"] as? Int, 720)
    }

    func testAnUnknownVersionGetsOurNewest() throws {
        let answers = try session([request(1, "initialize", ["protocolVersion": "1999-01-01"])])
        XCTAssertEqual((answers[0]["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServer.protocolVersions[0])
    }

    func testHoldStatusAndReleaseThroughTheTools() throws {
        startApp(line: "Your Mac stays awake: Long build asked for it")
        let answers = try session([
            call(1, "hold_awake", ["minutes": 30, "reason": "Long build"]),
            call(2, "status"),
            call(3, "release"),
            call(4, "status"),
            call(5, "release"),
        ])
        XCTAssertEqual(answers.compactMap(isError), [false, false, false, false, false])
        let held = try XCTUnwrap(text(answers[0]))
        XCTAssertTrue(held.hasPrefix("Agent Caffeine keeps your Mac awake until 12:03. Hold "), held)
        XCTAssertTrue(held.contains("Call release with the id"), held)
        let status = try XCTUnwrap(text(answers[1]))
        XCTAssertTrue(status.contains("Long build, until 12:03"), status)
        XCTAssertTrue(status.hasSuffix("Your Mac stays awake: Long build asked for it"), status)
        XCTAssertEqual(text(answers[2])?.hasPrefix("Released "), true)
        XCTAssertEqual(text(answers[3])?.hasPrefix("No holds."), true)
        XCTAssertEqual(text(answers[4]), "This session has no hold to release.")
        XCTAssertEqual(tools.liveHolds, [])
    }

    func testReleaseByID() throws {
        startApp()
        _ = HoldCommands.hold(length: 600, reason: "from a script", json: false, tools: tools)
        let id = try XCTUnwrap(tools.liveHolds.first?.id)
        let answers = try session([call(1, "release"), call(2, "release", ["id": id]), call(3, "release", ["id": id]), call(4, "release", ["id": "../x"])])
        XCTAssertEqual(text(answers[0]), "This session has no hold to release.", "A hold of somebody else stays")
        XCTAssertEqual(text(answers[1]), "Released \(id).")
        XCTAssertEqual(answers.compactMap(isError), [false, false, true, true])
    }

    func testTheMinutesHaveToBeFromOneToTheCap() throws {
        startApp()
        let answers = try session([
            call(1, "hold_awake", ["minutes": 0]),
            call(2, "hold_awake", ["minutes": 721]),
            call(3, "hold_awake", ["minutes": "30"]),
            call(4, "hold_awake", ["minutes": 1.5]),
            call(5, "hold_awake", ["minutes": true]),
            call(6, "hold_awake", ["minutes": 30, "reason": 5]),
        ])
        XCTAssertEqual(answers.compactMap(isError), [true, true, true, true, true, true])
        XCTAssertEqual(tools.liveHolds, [])
        let good = try session([call(1, "hold_awake", ["minutes": 720]), call(2, "hold_awake")])
        XCTAssertEqual(good.compactMap(isError), [false, false])
        XCTAssertEqual(tools.liveHolds.map { $0.end - $0.start }.sorted(), [3600, 720 * 60], "One hour with no minutes")
    }

    func testTheToolSaysThatTheAppDoesNotRun() throws {
        let answers = try session([call(1, "hold_awake", ["minutes": 30]), call(2, "status")])
        XCTAssertEqual(isError(answers[0]), true)
        XCTAssertEqual(text(answers[0]), HoldCommands.notRunning)
        XCTAssertEqual(text(answers[1]), "No holds.\nAgent Caffeine is not running. Your Mac sleeps as usual.")
    }

    func testWhatIsNoRequest() throws {
        let answers = try session(
            [request(1, "resources/list"), call(2, "sleep_now"), ["jsonrpc": "2.0", "id": 7, "result": [String: Any]()]],
            raw: ["{not json", "", "[1,2]"]
        )
        XCTAssertEqual(answers.count, 4)
        XCTAssertEqual((answers[0]["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual((answers[1]["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertEqual((answers[2]["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertTrue(answers[2]["id"] is NSNull)
        XCTAssertEqual((answers[3]["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testAnAnswerIsOneLine() throws {
        startApp()
        let server = MCPServer(tools: tools, version: "1")
        let line = try JSONSerialization.data(withJSONObject: call(1, "status"))
        let answer = try XCTUnwrap(server.handle(line))
        XCTAssertFalse(answer.contains(UInt8(ascii: "\n")))
    }
}
