import Darwin
import Foundation

// The command line tool of Agent Caffeine:
//
//     agent-caffeine hold --for 30m [--reason "text"]
//     agent-caffeine hold [--reason "text"] -- <command> [args...]
//     agent-caffeine release [<id> | --all]
//     agent-caffeine status [--json]
//     agent-caffeine mcp
//
// It writes one small file per hold for the app to read, as the hook
// command does for an agent's state. It holds nothing awake itself.

signal(SIGPIPE, SIG_IGN)

func finish(_ outcome: HoldOutcome) -> Never {
    if !outcome.out.isEmpty { FileHandle.standardOutput.write(Data((outcome.out.joined(separator: "\n") + "\n").utf8)) }
    if !outcome.err.isEmpty { FileHandle.standardError.write(Data((outcome.err.joined(separator: "\n") + "\n").utf8)) }
    exit(outcome.code)
}

let tools = HoldTools(store: HoldStore())

switch HoldArguments.parse(Array(CommandLine.arguments.dropFirst())) {
case .failure(let error):
    finish(HoldOutcome(code: HoldOutcome.usage, err: [error.message, "Run agent-caffeine help for the commands."]))
case .success(.help):
    finish(HoldOutcome(out: [HoldArguments.usage]))
case .success(.hold(let length, let reason, let json)):
    finish(HoldCommands.hold(length: length, reason: reason, json: json, tools: tools))
case .success(.release(let target)):
    finish(HoldCommands.release(target, tools: tools))
case .success(.status(let json)):
    finish(HoldCommands.status(json: json, tools: tools))
case .success(.mcp):
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    MCPServer(tools: tools, version: version).run(input: .standardInput, output: .standardOutput)
    exit(0)
case .success(.run(let command, let reason)):
    let holder = SystemProcessCensus.row(of: getpid())?.identity
    let begun = HoldCommands.beginRun(command: command, reason: reason, holder: holder, tools: tools)
    if !begun.warnings.isEmpty {
        FileHandle.standardError.write(Data((begun.warnings.map { "agent-caffeine: \($0)" }.joined(separator: "\n") + "\n").utf8))
    }
    let code = ChildProcess.run(command)
    if let hold = begun.hold { tools.store.remove(id: hold.id) }
    exit(code)
}
