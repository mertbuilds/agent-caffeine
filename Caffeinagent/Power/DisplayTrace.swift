import Foundation

/// One step of a fade, for a look at what the lid angle sensor, the fade
/// and macOS did.
struct DisplayTraceRow: Equatable {
    var time: Date
    /// What the sensor gave, in whole degrees.
    var raw: Double?
    /// The angle of `LidAngleEstimator`.
    var estimate: Double?
    /// The brightness the fade wants.
    var target: Float?
    /// The brightness that was set in this step. Nil when none was.
    var written: Float?
    /// The brightness of the display after this step.
    var read: Float?
}

/// The text of a trace: tab-separated values, one line per step. It holds
/// angles and brightness only.
struct DisplayTrace: Equatable {
    static let header = ["seconds", "rawAngle", "angle", "target", "written", "read", "fight"].joined(separator: "\t")
    /// The switch: `defaults write com.caffeinagent.app Display.debugTrace -bool YES`.
    static let defaultsKey = "Display.debugTrace"
    static let prefix = "display-trace-"
    static let suffix = ".tsv"
    static let maxLines = 2000
    static let keptFiles = 5
    /// The file gets the new lines at least this often while a fade runs,
    /// so a hard restart keeps what came before it.
    static let flushEvery: TimeInterval = 1
    /// A brightness this far from the one that was set: macOS set its own.
    static let fight: Float = 0.01

    private(set) var lines: [String] = []
    private(set) var start: Date?
    /// What the fade set last.
    private var ours: Float?

    var isEmpty: Bool { lines.isEmpty }

    /// False when the trace is full and the row was left out.
    @discardableResult
    mutating func add(_ row: DisplayTraceRow) -> Bool {
        guard lines.count < Self.maxLines else { return false }
        let start = start ?? row.time
        self.start = start
        if let written = row.written { ours = written }
        let fights = row.read.flatMap { read in ours.map { abs(read - $0) > Self.fight } } ?? false
        lines.append([
            String(format: "%.4f", row.time.timeIntervalSince(start)),
            row.raw.map { String(format: "%.0f", $0) } ?? "-",
            row.estimate.map { String(format: "%.3f", $0) } ?? "-",
            Self.text(row.target), Self.text(row.written), Self.text(row.read),
            fights ? "1" : "0",
        ].joined(separator: "\t"))
        return true
    }

    var text: String { ([Self.header] + lines).joined(separator: "\n") + "\n" }

    static func fileName(start: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return prefix + format.string(from: start) + suffix
    }

    /// The traces to remove, so the newest `keptFiles` stay. The names
    /// sort by time.
    static func stale(among names: [String]) -> [String] {
        let traces = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.sorted()
        return Array(traces.dropLast(keptFiles))
    }

    private static func text(_ level: Float?) -> String {
        level.map { String(format: "%.4f", $0) } ?? "-"
    }
}

/// Keeps the trace of one fade in memory and writes it to a file: the
/// first step at once, then the new steps once per second, and the rest
/// when the fade ends. Off unless the switch in the defaults is on.
final class DisplayTraceRecorder {
    private let defaults: UserDefaults
    private let directory: URL
    private var trace: DisplayTrace?
    /// The file of the fade that runs.
    private var file: URL?
    /// The lines of the trace that are in the file.
    private var flushed = 0
    private var flushedAt: Date?

    /// `~/Library/Application Support/<bundle id>`.
    static func traceDirectory(bundleID: String = Bundle.main.bundleIdentifier ?? "com.caffeinagent.app") -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent(bundleID)
    }

    init(defaults: UserDefaults, directory: URL = DisplayTraceRecorder.traceDirectory()) {
        self.defaults = defaults
        self.directory = directory
    }

    /// The switch is read when a fade starts.
    var isRecording: Bool {
        if trace == nil, defaults.bool(forKey: DisplayTrace.defaultsKey) { trace = DisplayTrace() }
        return trace != nil
    }

    func add(_ row: DisplayTraceRow) {
        guard isRecording else { return }
        trace?.add(row)
        // A clock that was set back writes too.
        if let flushedAt, (0..<DisplayTrace.flushEvery).contains(row.time.timeIntervalSince(flushedAt)) { return }
        flushedAt = row.time
        flush()
    }

    /// The fade ended: the rest is written.
    func finish() {
        flush()
        trace = nil
        file = nil
        flushed = 0
        flushedAt = nil
    }

    /// The new lines go to the end of the file. The first write makes the
    /// file and removes old files.
    private func flush() {
        guard let trace, let start = trace.start, flushed < trace.lines.count else { return }
        let files = FileManager.default
        do {
            if file == nil {
                try files.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(DisplayTrace.fileName(start: start))
                try (DisplayTrace.header + "\n").write(to: url, atomically: true, encoding: .utf8)
                file = url
                for name in DisplayTrace.stale(among: try files.contentsOfDirectory(atPath: directory.path)) {
                    try files.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            guard let file else { return }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((trace.lines[flushed...].joined(separator: "\n") + "\n").utf8))
            flushed = trace.lines.count
        } catch {
            // A trace is for a test by hand. Without it the fade is the same.
        }
    }
}
