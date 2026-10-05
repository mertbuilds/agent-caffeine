import Darwin
import Foundation

/// Writes what the detection saw and decided, one JSON line per sample, so
/// the same samples can be replayed later against other settings or rules.
/// The owner adds marks that say what an agent really did.
///
/// Each line goes out in one `write` on a descriptor opened for appending,
/// so a second process (`--lab-mark`) can add a mark to the same file. The
/// recorder holds a lock on the file for as long as it records, and that
/// lock is how the second process knows the recording still runs.
final class LabRecorder {
    let directory: URL
    private let now: () -> Date
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var url: URL?

    /// `~/Library/Application Support/<bundle id>/lab`.
    static func labDirectory(bundleID: String = Bundle.main.bundleIdentifier ?? "com.caffeinagent.app") -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent(bundleID).appendingPathComponent("lab")
    }

    init(directory: URL = LabRecorder.labDirectory(), now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return descriptor >= 0
    }

    /// The file of the running recording, or of the last one.
    var fileURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return url
    }

    /// Starts a new file and writes the header. A running recording ends.
    @discardableResult
    func start(label: String, header: LabHeader) throws -> URL {
        stop()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName(label: label, at: header.startedAt))
        let opened = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard opened >= 0 else { throw LabError.cannotWrite(url.path) }
        // Gone with the descriptor, also when the process dies.
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            close(opened)
            throw LabError.cannotWrite(url.path)
        }
        lock.lock()
        descriptor = opened
        self.url = url
        lock.unlock()
        write(LabLine(header: LabFormat.scrubbed(header)))
        return url
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1
    }

    /// One sample: the frame, the verdicts and the decision made from it.
    func record(frame: EvidenceFrame, decision: HoldDecision, cost: TimeInterval? = nil) {
        guard isRecording else { return }
        write(LabFormat.sample(frame: frame, decision: decision, cost: cost))
    }

    /// `agent` is an `AgentDefinition.id`, `id:pid`, or `*` for every agent.
    func mark(agent: String, truth: LabTruth, note: String? = nil) {
        guard isRecording else { return }
        write(LabLine(mark: LabMark(at: now(), agent: agent, truth: truth, note: note)))
    }

    private func write(_ line: LabLine) {
        guard let data = try? LabFormat.line(line) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { return }
        Self.writeAll(data, to: descriptor)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, bytes.baseAddress.map { $0 + offset }, bytes.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }

    // MARK: Files

    /// `2026-10-05T16-20-33Z-smoke.jsonl`. The label keeps letters, digits,
    /// `-` and `_`.
    static func fileName(label: String, at date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let safe = String(String.UnicodeScalarView(label.unicodeScalars.filter(allowed.contains)))
        return "\(stamp)-\(safe.isEmpty ? "recording" : safe).jsonl"
    }

    /// The recording that was written to last.
    static func newestRecording(in directory: URL = LabRecorder.labDirectory()) -> URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var newest: (url: URL, at: Date)?
        for url in urls where url.pathExtension == "jsonl" {
            guard let at = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            if newest.map({ at > $0.at }) ?? true { newest = (url, at) }
        }
        return newest?.url
    }

    /// True while a recorder holds its lock on the file. The time of the
    /// last write says nothing: a mark is a write too.
    static func isBeingRecorded(_ url: URL) -> Bool {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_SH | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }

    /// The recording that a recorder still writes, for a mark from another
    /// process. A mark in a finished recording would change its score.
    static func runningRecording(in directory: URL = LabRecorder.labDirectory()) -> URL? {
        guard let url = newestRecording(in: directory), isBeingRecorded(url) else { return nil }
        return url
    }

    /// Adds a mark to a recording that another process is writing. A
    /// recording that has ended takes no mark.
    static func appendMark(_ mark: LabMark, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_APPEND)
        guard descriptor >= 0 else { throw LabError.cannotWrite(url.path) }
        defer { close(descriptor) }
        guard isBeingRecorded(url) else { throw LabError.noRecording }
        writeAll(try LabFormat.line(LabLine(mark: mark)), to: descriptor)
    }
}
