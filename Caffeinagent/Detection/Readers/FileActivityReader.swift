import Foundation

struct FileSnapshot: Equatable {
    var path: String
    var size: UInt64
    var modifiedAt: Date
}

struct FileActivity: Equatable {
    /// Newest modification time over the current files.
    var newestModification: Date?
    /// Net size change since the last poll. Negative after a truncation, such
    /// as a SQLite WAL checkpoint.
    var sizeDelta: Int64 = 0
    /// Paths that are new, gone, or differ in size or modification time.
    var changedPaths: [String] = []

    var hasChanged: Bool { !changedPaths.isEmpty }
}

/// For agents that publish no readable state: writes to their session files
/// are the only sign of work. A write proves activity; silence proves
/// nothing, because every agent measured is silent for the whole of a tool
/// run and a model answer.
///
/// Measured on this Mac:
/// - opencode `opencode.db-wal` grows on each event, but its size stood
///   still for a 15 s text stream (the text part is updated in place), so
///   size alone misses streaming. Compare the modification time too.
/// - SQLite `-shm` files are written through mmap and update nothing
///   reliably. Do not watch them.
/// - Antigravity `conversations/*.db` and `antigravity_state.pbtxt`: the
///   write rhythm while it works was not measured; the pbtxt holds no
///   session state.
struct FileActivityReader {
    enum Target: Equatable {
        case paths([URL])
        /// Files directly inside `directory` whose name matches the shell
        /// pattern `glob`, such as `*.db`.
        case directory(URL, glob: String)
    }

    static let opencode = Target.paths([
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/opencode/opencode.db-wal"),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/opencode/opencode.db"),
    ])
    static let antigravity = Target.directory(
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/antigravity/conversations"),
        glob: "*.db"
    )

    var target: Target
    private(set) var previous: [FileSnapshot]?

    init(target: Target) {
        self.target = target
    }

    /// Compares the files with the last poll. The first poll only sets the
    /// baseline and reports no change.
    mutating func poll() -> FileActivity {
        let current = Self.snapshot(of: target)
        defer { previous = current }
        return Self.activity(previous: previous, current: current)
    }

    /// Working when files changed since the last poll, else nil: no write
    /// does not mean idle.
    nonisolated static func report(for activity: FileActivity, now: Date = Date()) -> StateReport? {
        guard activity.hasChanged else { return nil }
        return StateReport(state: .working, since: nil, observedAt: now, source: .fileActivity, detail: "writing session files")
    }

    nonisolated static func activity(previous: [FileSnapshot]?, current: [FileSnapshot]) -> FileActivity {
        var result = FileActivity(newestModification: current.map(\.modifiedAt).max())
        guard let previous else { return result }
        var before: [String: FileSnapshot] = [:]
        for snapshot in previous { before[snapshot.path] = snapshot }
        for snapshot in current {
            let old = before.removeValue(forKey: snapshot.path)
            if old == snapshot { continue }
            result.changedPaths.append(snapshot.path)
            result.sizeDelta += Int64(clamping: snapshot.size) - Int64(clamping: old?.size ?? 0)
        }
        for gone in before.values {
            result.changedPaths.append(gone.path)
            result.sizeDelta -= Int64(clamping: gone.size)
        }
        result.changedPaths.sort()
        return result
    }

    nonisolated static func snapshot(of target: Target) -> [FileSnapshot] {
        let urls: [URL]
        switch target {
        case .paths(let paths):
            urls = paths
        case .directory(let directory, let glob):
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            urls = names.filter { matches($0, glob: glob) }.map(directory.appendingPathComponent)
        }
        return urls.compactMap(snapshot(of:)).sorted { $0.path < $1.path }
    }

    nonisolated static func matches(_ name: String, glob: String) -> Bool {
        fnmatch(glob, name, 0) == 0
    }

    nonisolated private static func snapshot(of url: URL) -> FileSnapshot? {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modifiedAt = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        return FileSnapshot(path: url.path, size: UInt64(max(info.st_size, 0)), modifiedAt: modifiedAt)
    }
}
