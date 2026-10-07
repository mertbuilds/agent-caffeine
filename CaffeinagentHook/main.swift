import Darwin
import Foundation

// The command the agents run as a hook:
//
//     CaffeinagentHook <hook agent id> <event> [v=<n>]
//
// It reads the hook's JSON from stdin, writes one small state file for the
// app to read, prints nothing and always exits 0. The app does not have to
// run.

signal(SIGPIPE, SIG_IGN)
let arguments = CommandLine.arguments
if arguments.count >= 3, HookEvents.rules[arguments[1]] != nil {
    let input = HookCommand.readInput()
    HookCommand.record(
        agent: arguments[1], event: arguments[2], input: input,
        chain: HookCommand.ancestors(of: getpid()), directory: HookStateFile.directory(),
        now: HookCommand.startTime() ?? Date()
    )
}
exit(0)
