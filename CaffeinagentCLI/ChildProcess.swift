import Darwin
import Foundation

/// The command that `hold -- <command>` runs. Read by the signal handler,
/// so it is a plain global that is set before the handler is.
private var runningChild: pid_t = 0

/// Runs a command as a child and waits for it, as `time` or `env` would:
/// the child has this terminal and this environment, and the tool ends
/// with what the child ended with.
enum ChildProcess {
    /// A signal that is sent to the tool alone is passed on, so `kill`
    /// on the tool ends the command too.
    static let forwarded = [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGUSR1, SIGUSR2]
    static let notFound: Int32 = 127
    static let notExecutable: Int32 = 126

    /// - Returns: the exit code of the command, 128 plus the signal for a
    ///   command that a signal ended, 127 for a command that is not
    ///   there and 126 for one that cannot be run.
    static func run(_ command: [String]) -> Int32 {
        var arguments: [UnsafeMutablePointer<CChar>?] = command.map { strdup($0) } + [nil]
        defer { arguments.forEach { free($0) } }
        var child: pid_t = 0
        let failure = posix_spawnp(&child, command[0], nil, nil, &arguments, environ)
        guard failure == 0 else {
            let message = failure == ENOENT ? "command not found" : String(cString: strerror(failure))
            FileHandle.standardError.write(Data("agent-caffeine: \(command[0]): \(message)\n".utf8))
            return failure == ENOENT ? notFound : notExecutable
        }
        runningChild = child
        forwardSignals()
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 {
            guard errno == EINTR else { return HoldOutcome.failed }
        }
        runningChild = 0
        // WIFEXITED and WEXITSTATUS, which Swift does not have as macros.
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    /// Ctrl-C in a terminal reaches the child by itself: the terminal
    /// sends it to the whole foreground group, and the kernel names no
    /// sender for it. Such a signal is not sent twice. One that a process
    /// sent, as `kill` does, names its sender and is passed on.
    private static func forwardSignals() {
        var action = sigaction()
        action.__sigaction_u.__sa_sigaction = { signal, info, _ in
            guard runningChild > 0, let info, info.pointee.si_pid != 0 else { return }
            kill(runningChild, signal)
        }
        action.sa_flags = SA_SIGINFO | SA_RESTART
        sigemptyset(&action.sa_mask)
        for signal in forwarded { sigaction(signal, &action, nil) }
    }
}
