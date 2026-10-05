import Darwin
import Foundation

// The command the agents run as a hook:
//
//     CaffeinagentHook <hook agent id> <event> [v=<n>]
//
// It reads the hook's JSON from stdin, writes one small state file for the
// app to read, prints nothing and always exits 0. The app does not have to
// run.

/// At most `limit` bytes, and at most `timeout` seconds of waiting. What
/// comes after the limit is read and dropped, so the agent never writes
/// into a closed pipe.
func readInput(limit: Int, timeout: TimeInterval) -> [UInt8] {
    var input: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 16 * 1024)
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
    while true {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { break }
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, Int32((deadline - now) / 1_000_000) + 1) > 0 else { break }
        let count = read(STDIN_FILENO, &chunk, chunk.count)
        guard count > 0 else { break }
        if input.count < limit { input.append(contentsOf: chunk[..<min(count, limit - input.count)]) }
    }
    return input
}

signal(SIGPIPE, SIG_IGN)
let arguments = CommandLine.arguments
if arguments.count >= 3, HookEvents.rules[arguments[1]] != nil {
    let input = readInput(limit: 64 * 1024, timeout: 0.2)
    HookCommand.record(
        agent: arguments[1], event: arguments[2], input: input,
        chain: HookCommand.ancestors(of: getpid()), directory: HookStateFile.directory()
    )
}
exit(0)
