import Foundation

/// Reads the hook state files into one state per agent process, and removes
/// the files of processes that are gone. Not thread safe: the collector
/// calls it from its one queue.
struct HookStateReader {
    /// A file younger than this is never removed: its process may have
    /// started after the process table was read.
    static let removalAge: TimeInterval = 10

    let directory: URL
    private var files = FileCache<HookStateFile>()

    init(directory: URL) {
        self.directory = directory
    }

    /// The folder has to exist before it can be watched.
    func prepare() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    struct State: Equatable {
        var agent: String
        var state: ReportedState
        var at: Date
        var path: String
    }

    /// By pid, for the processes in `snapshot` only. A file whose process is
    /// gone, or whose pid now belongs to another process, is deleted.
    mutating func states(snapshot: [ProcessInfoRow], now: Date, freshness: TimeInterval = VerdictRules.hookFreshness) -> [Int32: State] {
        defer { files.endSample() }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }
        guard !names.isEmpty else { return [:] }
        let alive = Dictionary(snapshot.map { ($0.pid, $0.startTime) }, uniquingKeysWith: { first, _ in first })
        var states: [Int32: State] = [:]
        for name in names {
            let path = directory.appendingPathComponent(name).path
            guard let hit = files.value(at: path, read: { Self.read(path) }) else { continue }
            let old = now.timeIntervalSince(hit.signature.modifiedAt) >= Self.removalAge
            guard let file = hit.value else {
                // Never a half-written file: the hook command renames a whole one into place.
                if old { unlink(path) }
                continue
            }
            guard let start = alive[file.pid], abs(start - file.start) <= HookCommand.startTolerance else {
                if old { unlink(path) }
                continue
            }
            guard let summary = file.summary(now: now, freshness: freshness) else { continue }
            states[file.pid] = State(agent: file.agent, state: summary.state, at: summary.at, path: path)
        }
        return states
    }

    private static func read(_ path: String) -> HookStateFile? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let file = try? JSONDecoder().decode(HookStateFile.self, from: data),
              file.v == HookStateFile.currentVersion else { return nil }
        return file
    }
}
