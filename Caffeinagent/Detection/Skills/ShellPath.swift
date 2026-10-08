import Darwin
import Foundation

/// Whether `~/.local/bin` seems to be on the PATH of the user's login
/// shell, for the one line Settings shows below the link to the tool. It
/// only reads files and runs nothing. For a shell it does not know, it
/// says nothing.
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

    /// Nil for a shell we do not know. True when one of the shell's own
    /// files names the folder, or the system's list of paths has it. No
    /// shell is run for this, so a PATH that is set in another way is
    /// not seen, and the line Settings shows says "does not seem".
    /// - Parameters:
    ///   - startupFiles: the text of the files the shell reads at its start.
    ///   - systemPaths: the lines of `/etc/paths` and `/etc/paths.d`.
    static func hasLocalBin(shell: String, home: String, startupFiles: [String], systemPaths: [String]) -> Bool? {
        guard shells[name(ofShell: shell)] != nil else { return nil }
        if startupFiles.contains(where: { $0.contains(folder) }) { return true }
        let wanted = URL(fileURLWithPath: home).appendingPathComponent(folder).standardizedFileURL.path
        return systemPaths.contains { URL(fileURLWithPath: $0).standardizedFileURL.path == wanted }
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

    /// The lines of `paths` and of the files in `paths.d`, which
    /// `path_helper` makes the PATH of a login shell from.
    static func systemPaths(etc: URL = URL(fileURLWithPath: "/etc", isDirectory: true)) -> [String] {
        let folder = etc.appendingPathComponent("paths.d")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        return ([etc.appendingPathComponent("paths")] + names.map(folder.appendingPathComponent))
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The whole check for a shell. It reads files and starts no process.
    static func localBinIsOnPath(
        shell: String, home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        etc: URL = URL(fileURLWithPath: "/etc", isDirectory: true)
    ) -> Bool? {
        hasLocalBin(shell: shell, home: home.path, startupFiles: startupFiles(shell: shell, home: home), systemPaths: systemPaths(etc: etc))
    }
}
