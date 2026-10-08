import Foundation

/// `agent-caffeine mcp`: a Model Context Protocol server on stdin and
/// stdout, so an agent can ask for a hold itself. JSON-RPC 2.0, one
/// message per line, written by hand: `initialize`, `ping`, `tools/list`
/// and `tools/call` are all an agent needs for three tools.
///
/// The tools do what the commands do, through `HoldCommands`.
final class MCPServer {
    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let name = "agent-caffeine"
    static let maxMinutes = Int(ManualHold.timedCap / 60)
    static let defaultMinutes = Int(ManualHold.defaultLength / 60)

    private let tools: HoldTools
    private let version: String
    /// The holds this server made, for a `release` that names none.
    private var made: [String] = []

    init(tools: HoldTools, version: String) {
        self.tools = tools
        self.version = version
    }

    // MARK: Lines

    /// Answers until the input ends.
    func run(input: FileHandle, output: FileHandle) {
        var pending = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending.subdata(in: pending.startIndex..<newline)
                pending.removeSubrange(pending.startIndex...newline)
                answer(line, to: output)
            }
        }
        if !pending.isEmpty { answer(pending, to: output) }
    }

    private func answer(_ line: Data, to output: FileHandle) {
        guard line.contains(where: { !UInt8($0).isWhitespace }), var reply = handle(line) else { return }
        reply.append(UInt8(ascii: "\n"))
        output.write(reply)
    }

    /// The answer to one message. Nil for a notification and for an
    /// answer of the client, which get none.
    func handle(_ line: Data) -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: line) else {
            return Self.encode(Self.failure(id: NSNull(), code: -32700, message: "Parse error"))
        }
        guard let request = message as? [String: Any], let method = request["method"] as? String else {
            // An answer to a request of ours: we send none.
            if let object = message as? [String: Any], object["method"] == nil, object["result"] != nil || object["error"] != nil { return nil }
            return Self.encode(Self.failure(id: NSNull(), code: -32600, message: "Invalid Request"))
        }
        guard let id = request["id"], !(id is NSNull) else { return nil }
        let parameters = request["params"] as? [String: Any] ?? [:]
        return Self.encode(reply(to: method, parameters: parameters, id: id))
    }

    private func reply(to method: String, parameters: [String: Any], id: Any) -> [String: Any] {
        switch method {
        case "initialize":
            let asked = parameters["protocolVersion"] as? String
            let agreed = asked.flatMap { Self.protocolVersions.contains($0) ? $0 : nil } ?? Self.protocolVersions[0]
            return Self.success(id: id, result: [
                "protocolVersion": agreed,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": Self.name, "title": "Agent Caffeine", "version": version],
                "instructions": "Keeps this Mac awake while long work runs. Call hold_awake before the work and release when it is done.",
            ])
        case "ping":
            return Self.success(id: id, result: [String: Any]())
        case "tools/list":
            return Self.success(id: id, result: ["tools": Self.toolList])
        case "tools/call":
            guard let name = parameters["name"] as? String, Self.toolList.contains(where: { $0["name"] as? String == name }) else {
                return Self.failure(id: id, code: -32602, message: "Unknown tool: \(parameters["name"] as? String ?? "")")
            }
            let outcome = call(name, arguments: parameters["arguments"] as? [String: Any] ?? [:])
            return Self.success(id: id, result: ["content": [["type": "text", "text": outcome.text]], "isError": outcome.isError])
        default:
            return Self.failure(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: Tools

    static let toolList: [[String: Any]] = [
        [
            "name": "hold_awake",
            "title": "Keep the Mac awake",
            "description": "Keeps this Mac awake for a number of minutes, also with the lid closed, so long work is not cut off by sleep. Use it before a build, a render, a download, a training run or any job that takes more than a few minutes. Call release when the work is done. The hold ends by itself after the minutes. The battery limit, a pause and the switch of Agent Caffeine still let the Mac sleep.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "minutes": [
                        "type": "integer", "minimum": 1, "maximum": maxMinutes,
                        "description": "How long to keep the Mac awake, in minutes. From 1 to \(maxMinutes). \(defaultMinutes) when left out.",
                    ],
                    "reason": [
                        "type": "string", "maxLength": ManualHold.reasonLimit,
                        "description": "What the hold is for, in a few words. The person at the Mac sees it in the menu of Agent Caffeine.",
                    ],
                ],
            ],
        ],
        [
            "name": "release",
            "title": "Let the Mac sleep again",
            "description": "Ends a hold, so the Mac can sleep again. Give the id that hold_awake returned. With no id, it ends the holds this session made.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "The id of the hold to end."]],
            ],
        ],
        [
            "name": "status",
            "title": "Show the holds",
            "description": "Lists the holds that are active now, and says whether the Mac stays awake or can sleep.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
    ]

    private func call(_ name: String, arguments: [String: Any]) -> (text: String, isError: Bool) {
        switch name {
        case "hold_awake":
            let minutes = arguments["minutes"].map(Self.wholeNumber) ?? Self.defaultMinutes
            guard let minutes, (1...Self.maxMinutes).contains(minutes) else {
                return ("minutes has to be a whole number from 1 to \(Self.maxMinutes). Ask for a shorter time, and ask again when it ends.", true)
            }
            if let reason = arguments["reason"], !(reason is String) { return ("reason has to be a text.", true) }
            switch HoldCommands.hold(length: TimeInterval(minutes) * 60, reason: arguments["reason"] as? String, tools: tools) {
            case .failure(let error):
                return (error.message, true)
            case .success(let hold):
                made.append(hold.id)
                let note = tools.store.status().flatMap { $0.stopped ? " \($0.line), so the Mac can sleep until that ends." : nil } ?? ""
                return ("\(HoldText.held(hold, tools: tools)) Call release with the id \(hold.id) when the work is done.\(note)", false)
            }
        case "release":
            if let id = arguments["id"] {
                guard let id = id as? String, ManualHold.isValidID(id) else { return ("id is not the id of a hold. status lists the holds.", true) }
                let outcome = HoldCommands.release(.id(id), tools: tools)
                made.removeAll { $0 == id }
                return ((outcome.out + outcome.err).joined(separator: "\n"), outcome.code != 0)
            }
            let released = made.filter { tools.store.remove(id: $0) }
            made.removeAll()
            return (released.isEmpty ? "This session has no hold to release." : "Released \(released.joined(separator: ", ")).", false)
        default:
            return (HoldCommands.status(json: false, tools: tools).out.joined(separator: "\n"), false)
        }
    }

    /// Nil for true and false, which JSON would also read as a number,
    /// and for a number with a fraction.
    private static func wholeNumber(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded(), abs(number.doubleValue) < 1_000_000 else { return nil }
        return number.intValue
    }

    // MARK: JSON-RPC

    private static func success(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func failure(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]]
    }

    /// One line: JSON keeps a line break inside a text as `\n`.
    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }
}

private extension UInt8 {
    var isWhitespace: Bool { self == 0x20 || self == 0x09 || self == 0x0a || self == 0x0d }
}
