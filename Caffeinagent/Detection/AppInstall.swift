import Darwin
import Foundation

/// The other ways to write the path of the installed app, next to the one
/// this copy writes into the files of the agents.
struct AppPathSpellings: Equatable {
    /// Known paths that are the same bundle on disk. An entry with one of
    /// them runs the same hook command, so it is current and stays.
    var same: [String] = []
    /// Known paths with nothing on disk. An entry with one of them runs
    /// nothing. A file of ours that nobody edited is rewritten at launch.
    var gone: [String] = []
}

/// The name and the place of the installed app, and the one answer to "is
/// this the same bundle". The bundle is `Agent Caffeine.app` from 1.0.2.
/// 1.0.0 and 1.0.1 were `agent caffeine.app`, and an update keeps the name
/// of the bundle it replaces, so both names are installed for good. On the
/// usual volume, which does not tell names apart by case, the two paths are
/// one file. On a volume that does, they are two. So no path of the app is
/// compared as a text: the files on disk are asked.
struct AppInstall {
    static let bundleName = "Agent Caffeine.app"
    /// The name in 1.0.0 and 1.0.1. The hooks, the plugins and the link
    /// those builds wrote hold it.
    static let earlierBundleName = "agent caffeine.app"
    static let bundleNames = [bundleName, earlierBundleName]
    static let folder = "/Applications"
    /// The paths the hook command of an install can have, the new one first.
    static let knownPaths = bundleNames.map { folder + "/" + $0 }
    /// Where a new install is.
    static let defaultPath = knownPaths[0]

    /// The file behind a path, links followed.
    struct FileIdentity: Equatable {
        var device: UInt64
        var inode: UInt64
    }

    /// Nil when nothing is at the path.
    var identity: (String) -> FileIdentity?
    /// True when the volume of the path tells `A` from `a` in a name. Nil
    /// when it does not say.
    var caseSensitive: (String) -> Bool?
    /// The names in a folder, as they are written on disk.
    var names: (String) -> [String]

    static let live = AppInstall(
        identity: { path in
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            return FileIdentity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino))
        },
        caseSensitive: { path in
            // The path may not be there: the folder above it is on the same volume.
            var url = URL(fileURLWithPath: path)
            while true {
                if let answer = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames { return answer }
                let parent = url.deletingLastPathComponent()
                guard parent.path != url.path else { return nil }
                url = parent
            }
        },
        names: { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
    )

    /// True when the two paths are one item on disk. When both are there,
    /// the file itself decides. When one is there, the other is another
    /// item. When none is there, the names decide as the volume would read
    /// them: without case on a volume that keeps no case apart, and to the
    /// letter on every other one.
    func isSameItem(_ first: String, _ second: String) -> Bool {
        if first == second { return true }
        switch (identity(first), identity(second)) {
        case let (one?, other?): return one == other
        case (nil, nil): return first.caseInsensitiveCompare(second) == .orderedSame && caseSensitive(first) == false
        default: return false
        }
    }

    /// True for the copy in the Applications folder, under either name.
    func isStableInstall(_ path: String) -> Bool {
        Self.knownPaths.contains { isSameItem($0, path) }
    }

    /// The path the hooks, the plugins and the link are written with, with
    /// the name as it is on disk: the install that is this copy, else an
    /// install that is there, else where a new install goes. A path that is
    /// not on disk is never chosen over one that is.
    func stablePath(running: String) -> String {
        let onDisk = Set(names(Self.folder))
        let present = Self.knownPaths.filter { onDisk.contains(($0 as NSString).lastPathComponent) }
        return present.first { isSameItem($0, running) } ?? present.first ?? Self.defaultPath
    }

    func spellings(of path: String) -> AppPathSpellings {
        let others = Self.knownPaths.filter { $0 != path }
        let same = others.filter { isSameItem($0, path) }
        return AppPathSpellings(same: same, gone: others.filter { !same.contains($0) && identity($0) == nil })
    }

    /// Where a copy named `name` goes in the Applications folder. An
    /// install under the other name is the same app: the copy takes its
    /// place and its name, so what points at it stays valid and no second
    /// install is made next to it.
    func relocationPath(for name: String) -> String {
        let wanted = Self.folder + "/" + name
        guard Self.bundleNames.contains(name), identity(wanted) == nil else { return wanted }
        return Self.knownPaths.first { identity($0) != nil } ?? wanted
    }
}

extension AppInstall {
    /// What the copy that runs found when it started. The name of a bundle
    /// does not change while its app runs: an update ends with a relaunch.
    struct Running {
        /// The bundle that runs, with the name as it is on disk when it is
        /// the install.
        let path: String
        /// See `stablePath(running:)`.
        let stablePath: String
        let isStableInstall: Bool
        let spellings: AppPathSpellings

        init(bundlePath: String, install: AppInstall) {
            stablePath = install.stablePath(running: bundlePath)
            isStableInstall = install.isStableInstall(bundlePath)
            path = isStableInstall ? stablePath : bundlePath
            spellings = install.spellings(of: stablePath)
        }
    }

    static let running = Running(bundlePath: Bundle.main.bundleURL.standardizedFileURL.path, install: .live)
}
