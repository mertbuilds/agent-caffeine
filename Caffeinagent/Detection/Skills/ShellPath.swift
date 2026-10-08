import Darwin
import Foundation

/// Whether `~/.local/bin` is on the PATH of the user's login shell, for
/// the one line Settings shows below the link to the tool. It only
/// reads. When it cannot tell, it says nothing.
enum ShellPath {
    static let folder = ".local/bin"
    static let exportLine = #"export PATH="$HOME/.local/bin:$PATH""#

    /// The files a shell reads at its start, relative to the home folder,
    /// and the one a new line goes into.
    private static let shells: [String: (reads: [String], addTo: String)] = [
        "zsh": ([".zshenv", ".zprofile", ".zshrc", ".zlogin"], ".zshrc"),
        "bash": ([".bash_profile", ".bash_login", ".profile", ".bashrc"], ".bash_profile"),
    ]

    private static func name(ofShell shell: String) -> String {
        (shell as NSString).lastPathComponent
    }

    /// "~/.zshrc" for zsh. Nil for a shell we do not know.
    static func startupFile(shell: String) -> String? {
        shells[name(ofShell: shell)].map { "~/" + $0.addTo }
    }

    /// Nil when it cannot be told: a shell we do not know, or a login
    /// shell that gave no PATH. True when the PATH of the login shell has
    /// the folder, or one of the shell's own files names it: a PATH that
    /// is set for an interactive shell only is not in `loginPath`.
    /// - Parameters:
    ///   - loginPath: the PATH of a login shell that is not interactive.
    ///   - startupFiles: the text of the files the shell reads at its start.
    static func hasLocalBin(shell: String, home: String, loginPath: String?, startupFiles: [String]) -> Bool? {
        guard shells[name(ofShell: shell)] != nil else { return nil }
        if startupFiles.contains(where: { $0.contains(folder) }) { return true }
        guard let loginPath, !loginPath.isEmpty else { return nil }
        let wanted = URL(fileURLWithPath: home).appendingPathComponent(folder).standardizedFileURL.path
        return loginPath.split(separator: ":").contains { URL(fileURLWithPath: String($0)).standardizedFileURL.path == wanted }
    }

    // MARK: The Mac

    /// The login shell of the user, from the user database.
    static func loginShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }

    static func startupFiles(shell: String, home: URL) -> [String] {
        (shells[name(ofShell: shell)]?.reads ?? []).compactMap { try? String(contentsOf: home.appendingPathComponent($0), encoding: .utf8) }
    }

    private static let open = "__agent_caffeine_path__", close = "__end__"

    /// The PATH between our two marks: a profile may print lines of its own.
    static func path(inOutput output: String) -> String? {
        guard let start = output.range(of: open, options: .backwards),
              let end = output.range(of: close, range: start.upperBound..<output.endIndex) else { return nil }
        return String(output[start.upperBound..<end.lowerBound])
    }

    /// Asks a login shell that is not interactive for its PATH, with no
    /// input. Nil for a shell we do not know, and when the shell gives no
    /// answer within `timeout`. Never on the main thread.
    static func loginPath(shell: String, timeout: TimeInterval = 5) -> String? {
        guard shells[name(ofShell: shell)] != nil, FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf '%s%s%s' '\(open)' \"$PATH\" '\(close)'"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let done = DispatchSemaphore(value: 0)
        var output = Data()
        guard (try? process.run()) != nil else { return nil }
        DispatchQueue.global(qos: .utility).async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        return path(inOutput: String(decoding: output, as: UTF8.self))
    }

    /// The whole check for this Mac. Never on the main thread.
    static func localBinIsOnPath(home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) -> Bool? {
        guard let shell = loginShell() else { return nil }
        let files = startupFiles(shell: shell, home: home)
        if hasLocalBin(shell: shell, home: home.path, loginPath: nil, startupFiles: files) == true { return true }
        return hasLocalBin(shell: shell, home: home.path, loginPath: loginPath(shell: shell), startupFiles: files)
    }
}
