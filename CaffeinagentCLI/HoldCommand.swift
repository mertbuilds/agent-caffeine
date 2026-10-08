import Foundation

/// What the command line tool reaches the Mac through. A test passes a
/// folder of its own, a fixed time and a process table it made up.
struct HoldTools {
    var store: HoldStore
    var now: () -> Date = Date.init
    /// Of a process that runs now, nil when it is gone.
    var startTime: (Int32) -> TimeInterval? = { SystemProcessCensus.row(of: $0)?.startTime }
    var calendar = Calendar.current
    var locale = Locale.current

    var liveHolds: [ManualHold] {
        store.live(now: now(), startTime: startTime)
    }
}

/// One call of the tool, as its arguments say it.
enum HoldInvocation: Equatable {
    enum Release: Equatable {
        case id(String)
        case all
        /// No id was given: the one hold there is.
        case only
    }

    case hold(length: TimeInterval, reason: String?, json: Bool)
    case run(command: [String], reason: String?)
    case release(Release)
    case status(json: Bool)
    case mcp
    case help
}

struct HoldUsageError: Error, Equatable {
    var message: String
}

/// What a call prints and how it ends. The lines of `out` go to stdout,
/// the lines of `err` to stderr.
struct HoldOutcome: Equatable {
    static let failed: Int32 = 1
    static let usage: Int32 = 2

    var code: Int32 = 0
    var out: [String] = []
    var err: [String] = []
}

enum HoldArguments {
    static let usage = """
    Agent Caffeine keeps your Mac awake while something works.

      agent-caffeine hold --for 30m [--reason "text"]    Keep the Mac awake for a time: 90s, 30m, 2h. 1 hour without --for, 12 hours at most.
      agent-caffeine hold [--reason "text"] -- <command>  Run the command and keep the Mac awake while it runs, 24 hours at most.
      agent-caffeine release [<id> | --all]               End a hold.
      agent-caffeine status [--json]                      Show the holds, and whether the Mac can sleep.
      agent-caffeine mcp                                  Run as an MCP server on stdin and stdout.

    The battery limit, a pause and the switch of Agent Caffeine still let the Mac sleep.
    """

    /// The arguments after the name of the tool.
    static func parse(_ arguments: [String]) -> Result<HoldInvocation, HoldUsageError> {
        guard let verb = arguments.first else { return .success(.help) }
        let rest = Array(arguments.dropFirst())
        switch verb {
        case "hold": return hold(rest)
        case "release": return release(rest)
        case "status": return flags(rest, allowed: ["--json"]).map { .status(json: $0.contains("--json")) }
        case "mcp": return flags(rest, allowed: []).map { _ in .mcp }
        case "help", "--help", "-h": return .success(.help)
        default: return .failure(HoldUsageError(message: "Unknown command \(verb)."))
        }
    }

    private static func flags(_ arguments: [String], allowed: Set<String>) -> Result<Set<String>, HoldUsageError> {
        if let unknown = arguments.first(where: { !allowed.contains($0) }) {
            return .failure(HoldUsageError(message: "Unknown option \(unknown)."))
        }
        return .success(Set(arguments))
    }

    private static func hold(_ arguments: [String]) -> Result<HoldInvocation, HoldUsageError> {
        var length: TimeInterval?
        var reason: String?
        var json = false
        var command: [String]?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "--":
                command = Array(arguments[index...])
                index = arguments.count
            case "--for":
                guard index < arguments.count, let parsed = HoldDuration.parse(arguments[index]) else {
                    return .failure(HoldUsageError(message: "--for takes a time such as 90s, 30m or 2h."))
                }
                length = parsed
                index += 1
            case "--reason":
                guard index < arguments.count else { return .failure(HoldUsageError(message: "--reason takes a text.")) }
                reason = arguments[index]
                index += 1
            case "--json":
                json = true
            default:
                return .failure(HoldUsageError(message: "Unknown option \(argument). Put a command after --."))
            }
        }
        if let command {
            guard !command.isEmpty else { return .failure(HoldUsageError(message: "Name a command after --.")) }
            guard length == nil else {
                return .failure(HoldUsageError(message: "Use --for or a command, not both. A command holds while it runs."))
            }
            guard !json else { return .failure(HoldUsageError(message: "--json goes with --for. The output of a command is its own.")) }
            return .success(.run(command: command, reason: reason))
        }
        let asked = length ?? ManualHold.defaultLength
        guard asked <= ManualHold.timedCap else {
            return .failure(HoldUsageError(message: "A hold lasts 12 hours at most. Ask for a shorter time, and ask again when it ends."))
        }
        return .success(.hold(length: asked, reason: reason, json: json))
    }

    private static func release(_ arguments: [String]) -> Result<HoldInvocation, HoldUsageError> {
        guard arguments.count <= 1 else { return .failure(HoldUsageError(message: "release takes one id, or --all.")) }
        guard let target = arguments.first else { return .success(.release(.only)) }
        if target == "--all" { return .success(.release(.all)) }
        guard ManualHold.isValidID(target) else { return .failure(HoldUsageError(message: "\(target) is no id of a hold. status lists them.")) }
        return .success(.release(.id(target)))
    }
}

/// What the commands do, without the process around them: the MCP server
/// calls the same.
enum HoldCommands {
    static let notRunning = "Agent Caffeine is not running, so nothing keeps your Mac awake. Open Agent Caffeine and try again."
    static let notRunningForCommand = "Agent Caffeine is not running, so your Mac can sleep while this runs."

    // MARK: Hold

    /// A timed hold. Refused while the app does not run: a hold that
    /// nothing honours would be a promise the tool cannot keep.
    static func hold(length: TimeInterval, reason: String?, tools: HoldTools) -> Result<ManualHold, HoldUsageError> {
        guard length > 0, length <= ManualHold.timedCap else {
            return .failure(HoldUsageError(message: "A hold lasts 12 hours at most."))
        }
        guard tools.store.appIsRunning else { return .failure(HoldUsageError(message: notRunning)) }
        let hold = ManualHold.timed(length: length, reason: reason, now: tools.now())
        guard tools.store.write(hold) else {
            return .failure(HoldUsageError(message: "The hold could not be written to \(tools.store.directory.path)."))
        }
        return .success(hold)
    }

    static func hold(length: TimeInterval, reason: String?, json: Bool, tools: HoldTools) -> HoldOutcome {
        switch hold(length: length, reason: reason, tools: tools) {
        case .failure(let error):
            return HoldOutcome(code: HoldOutcome.failed, err: [error.message])
        case .success(let hold):
            let note = stopNote(tools)
            if json {
                var object = HoldText.json(hold)
                object["appRunning"] = true
                return HoldOutcome(out: [HoldText.line(object)], err: note.map { [$0] } ?? [])
            }
            return HoldOutcome(out: [HoldText.held(hold, tools: tools)], err: note.map { [$0] } ?? [])
        }
    }

    /// The hold of a command that is about to start. It is written also
    /// while the app does not run, so an app that starts later sees it.
    /// - Parameter holder: this process, which waits for the command.
    static func beginRun(command: [String], reason: String?, holder: ProcessIdentity?, tools: HoldTools) -> (hold: ManualHold?, warnings: [String]) {
        var warnings: [String] = []
        if !tools.store.appIsRunning {
            warnings.append(notRunningForCommand)
        } else if let note = stopNote(tools) {
            warnings.append(note)
        }
        guard let holder, let name = command.first else {
            return (nil, warnings.isEmpty ? ["Agent Caffeine could not set up the hold. The command runs without it."] : warnings)
        }
        let hold = ManualHold.command(holder: holder, command: name, reason: reason, now: tools.now())
        guard tools.store.write(hold) else {
            return (nil, warnings + ["The hold could not be written to \(tools.store.directory.path). The command runs without it."])
        }
        return (hold, warnings)
    }

    /// The app runs and a stop is in force: the hold is taken and keeps
    /// nothing awake for now.
    private static func stopNote(_ tools: HoldTools) -> String? {
        guard let status = tools.store.status(), status.stopped else { return nil }
        return "\(status.line). The hold counts when that ends."
    }

    // MARK: Release

    static func release(_ target: HoldInvocation.Release, tools: HoldTools) -> HoldOutcome {
        switch target {
        case .id(let id):
            return tools.store.remove(id: id)
                ? HoldOutcome(out: ["Released \(id)."])
                : HoldOutcome(code: HoldOutcome.failed, err: ["There is no hold \(id)."])
        case .all:
            return releaseAll(tools.liveHolds, tools: tools)
        case .only:
            let holds = tools.liveHolds
            guard holds.count > 1 else { return releaseAll(holds, tools: tools) }
            return HoldOutcome(
                code: HoldOutcome.usage,
                err: ["There are \(holds.count) holds. Name one, or use --all:"] + holds.map { HoldText.listed($0, tools: tools) }
            )
        }
    }

    private static func releaseAll(_ holds: [ManualHold], tools: HoldTools) -> HoldOutcome {
        let released = holds.filter { tools.store.remove(id: $0.id) }
        if released.isEmpty { return HoldOutcome(out: ["There is no hold to release."]) }
        return HoldOutcome(out: ["Released \(HumaneDuration.counted(released.count, "hold"))."])
    }

    // MARK: Status

    static func status(json: Bool, tools: HoldTools) -> HoldOutcome {
        let holds = tools.liveHolds
        let running = tools.store.appIsRunning
        let status = tools.store.status()
        let line = sleepLine(running: running, status: status)
        if json {
            var object: [String: Any] = ["appRunning": running, "holds": holds.map(HoldText.json), "line": line]
            if let status { object["awake"] = status.awake }
            return HoldOutcome(out: [HoldText.line(object)])
        }
        let listed = holds.isEmpty ? ["No holds."] : holds.map { HoldText.listed($0, tools: tools) }
        return HoldOutcome(out: listed + [line])
    }

    /// The one line that says whether the Mac can sleep. Only the app
    /// knows: a stop is stronger than a hold.
    static func sleepLine(running: Bool, status: HoldStore.Status?) -> String {
        guard running else { return "Agent Caffeine is not running. Your Mac sleeps as usual." }
        return status?.line ?? "Agent Caffeine is running and has not said yet whether your Mac stays awake."
    }
}

extension FileHandle {
    /// False when the text could not be written, as to a pipe whose
    /// reader is gone. `write(_:)` ends the tool with an exception then.
    @discardableResult
    func put(_ data: Data) -> Bool {
        (try? write(contentsOf: data)) != nil
    }

    @discardableResult
    func put(_ text: String) -> Bool {
        put(Data(text.utf8))
    }
}

/// The words of the command line tool.
enum HoldText {
    /// "14:30", or "3:30 PM" for a user who set the 12-hour clock. With
    /// "tomorrow" for a time that is not today.
    static func time(_ date: Date, tools: HoldTools) -> String {
        let formatter = DateFormatter()
        formatter.locale = tools.locale
        formatter.calendar = tools.calendar
        formatter.timeZone = tools.calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: date)
        return tools.calendar.isDate(date, inSameDayAs: tools.now()) ? time : "\(time) tomorrow"
    }

    static func held(_ hold: ManualHold, tools: HoldTools) -> String {
        "Agent Caffeine keeps your Mac awake until \(time(hold.endsAt, tools: tools)). Hold \(hold.id)."
    }

    /// One hold in a list: "0a1b2c3d  ffmpeg, while it runs, for 12 minutes".
    static func listed(_ hold: ManualHold, tools: HoldTools) -> String {
        let ends: String
        switch hold.kind {
        case .timed:
            ends = "until \(time(hold.endsAt, tools: tools))"
        case .command:
            let lasting = HumaneDuration.lasting(seconds: tools.now().timeIntervalSince(hold.startedAt))
            ends = ["while it runs", lasting].compactMap { $0 }.joined(separator: ", ")
        }
        return "\(hold.id)  \(hold.title), \(ends)"
    }

    static func json(_ hold: ManualHold) -> [String: Any] {
        var object: [String: Any] = ["id": hold.id, "kind": hold.kind.rawValue, "start": hold.start, "end": hold.end]
        object["reason"] = hold.reason
        object["command"] = hold.command
        if let pid = hold.pid { object["pid"] = Int(pid) }
        return object
    }

    /// One line of JSON with the keys in order.
    static func line(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
