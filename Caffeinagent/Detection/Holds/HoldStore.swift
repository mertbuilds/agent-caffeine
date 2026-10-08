import Darwin
import Foundation

/// The holds folder: `~/Library/Application Support/<bundle id>/holds`,
/// one file per hold. The command line tool writes and removes the files,
/// and the app reads the folder with every sample and watches it, as it
/// does the hooks folder. No daemon and no socket: a file that nobody
/// reads keeps nothing awake.
struct HoldStore {
    /// Stands in for the app's folder in Application Support. For tests
    /// and development, so they never write into the folder the app reads.
    static let homeOverrideKey = "AGENT_CAFFEINE_HOME"
    static let bundleID = "com.caffeinagent.app"
    /// More files than this are not read: the oldest holds count.
    static let maxHolds = 32
    static let maxFileBytes = 4096
    /// A file younger than this is never removed for its holder: the
    /// process may have started after the process table was read.
    static let removalAge: TimeInterval = 10
    /// Held by the app for as long as it runs. See `AppLock`.
    static let lockName = ".app"
    static let statusName = ".status"

    let directory: URL
    /// The folder above the holds. The lock and the status are here: the
    /// app watches the holds folder, and a status it wrote there itself
    /// would bring one more sample each time.
    var home: URL { directory.deletingLastPathComponent() }

    init(directory: URL = HoldStore.directory()) {
        self.directory = directory
    }

    static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment[homeOverrideKey], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("holds", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/\(bundleID)/holds", isDirectory: true)
    }

    /// The folder has to exist before it can be watched or written to.
    @discardableResult
    func prepare() -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return true
        } catch {
            return false
        }
    }

    private func path(of id: String) -> String {
        directory.appendingPathComponent("\(id).json").path
    }

    // MARK: Write

    /// A whole file under another name first, then renamed into place, so
    /// the app never reads half of one. False when it could not be written.
    @discardableResult
    func write(_ hold: ManualHold) -> Bool {
        guard ManualHold.isValidID(hold.id), prepare(), let data = try? JSONEncoder().encode(hold) else { return false }
        return Self.writeWhole(data, to: path(of: hold.id), in: directory)
    }

    /// False when there was no such hold.
    @discardableResult
    func remove(id: String) -> Bool {
        guard ManualHold.isValidID(id) else { return false }
        return unlink(path(of: id)) == 0
    }

    fileprivate static func writeWhole(_ data: Data, to path: String, in directory: URL) -> Bool {
        let draft = directory.appendingPathComponent(".draft-\(getpid())-\(ManualHold.newID())").path
        let descriptor = open(draft, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return false }
        let written = data.withUnsafeBytes { bytes -> Bool in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress.map { $0 + offset }, bytes.count - offset)
                if count <= 0 { return false }
                offset += count
            }
            return true
        }
        close(descriptor)
        guard written, rename(draft, path) == 0 else {
            unlink(draft)
            return false
        }
        return true
    }

    // MARK: Read

    /// The holds that count at `now`, the oldest first. A hold whose time
    /// is over, or whose holder is gone or is another process by now, is
    /// dead: it is never among them, and its file is removed. A hold
    /// whose holder is stopped is not among them either, and its file
    /// stays: it counts again when the holder is continued.
    /// - Parameters:
    ///   - startTime: of a process that runs now, nil when it is gone.
    ///   - stopped: true for a process that a signal stopped.
    ///   - removeDead: false only reads.
    func live(
        now: Date, startTime: (Int32) -> TimeInterval?, stopped: (Int32) -> Bool = { _ in false }, removeDead: Bool = true
    ) -> [ManualHold] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
        var holds: [ManualHold] = []
        for name in names {
            let path = directory.appendingPathComponent(name).path
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            let modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
            let old = now.timeIntervalSince1970 - modified >= Self.removalAge
            guard let hold = Self.read(path, size: Int(info.st_size)), "\(hold.id).json" == name else {
                // Never a half-written file: a whole one is renamed into place.
                if removeDead, old { unlink(path) }
                continue
            }
            guard hold.isTimely(now: now) else {
                // Past its end it is over for good. Any other one may only
                // look wrong to a reader whose time is a moment behind.
                if removeDead, now.timeIntervalSince1970 >= hold.end || old { unlink(path) }
                continue
            }
            guard hold.holderIsAlive(startTime: startTime) else {
                if removeDead, old { unlink(path) }
                continue
            }
            if hold.holderIsStopped(stopped) { continue }
            holds.append(hold)
        }
        holds.sort { ($0.start, $0.id) < ($1.start, $1.id) }
        return Array(holds.prefix(Self.maxHolds))
    }

    private static func read(_ path: String, size: Int) -> ManualHold? {
        guard size > 0, size <= maxFileBytes, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let hold = try? JSONDecoder().decode(ManualHold.self, from: data) else { return nil }
        return hold.cleaned
    }

    // MARK: The app

    /// How the command line tool knows that the app runs: the app holds a
    /// lock on a file next to the folder, and the lock is gone with the app,
    /// also when it is killed. The same as `LabRecorder` does for a
    /// recording.
    final class AppLock {
        private let descriptor: Int32

        /// Nil when another copy of the app holds it, or the folder
        /// cannot be written.
        init?(store: HoldStore) {
            guard store.prepare() else { return nil }
            let opened = open(store.home.appendingPathComponent(HoldStore.lockName).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            guard opened >= 0 else { return nil }
            guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
                close(opened)
                return nil
            }
            descriptor = opened
        }

        deinit {
            close(descriptor)
        }
    }

    var appIsRunning: Bool {
        let descriptor = open(home.appendingPathComponent(Self.lockName).path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_SH | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }

    // MARK: Status

    /// What the app decided, for `status` of the command line tool: the
    /// tool sees the holds, and only the app knows whether a stop is
    /// stronger than they are.
    struct Status: Codable, Equatable {
        var v = 1
        /// Agent Caffeine keeps the Mac awake.
        var awake: Bool
        /// The headline of the menu on one line: "Your Mac stays awake:
        /// ffmpeg asked for it".
        var line: String
        /// A safety stop, the switch, a pause or the license lets the Mac
        /// sleep whatever asks for a hold.
        var stopped: Bool
    }

    @discardableResult
    func write(_ status: Status) -> Bool {
        guard prepare(), let data = try? JSONEncoder().encode(status) else { return false }
        return Self.writeWhole(data, to: home.appendingPathComponent(Self.statusName).path, in: home)
    }

    func removeStatus() {
        unlink(home.appendingPathComponent(Self.statusName).path)
    }

    /// Writes the status for the app, and only one that differs from the
    /// one it wrote last: most decisions change nothing the tool says.
    final class StatusWriter {
        private let store: HoldStore
        private var written: Status?

        init(store: HoldStore) {
            self.store = store
        }

        /// False when nothing was written.
        @discardableResult
        func write(_ status: Status) -> Bool {
            guard status != written, store.write(status) else { return false }
            written = status
            return true
        }

        func remove() {
            store.removeStatus()
            written = nil
        }
    }

    /// Nil when the app does not run: what it wrote last says nothing then.
    func status() -> Status? {
        guard appIsRunning, let data = try? Data(contentsOf: home.appendingPathComponent(Self.statusName)),
              data.count <= Self.maxFileBytes, let status = try? JSONDecoder().decode(Status.self, from: data), status.v == 1 else { return nil }
        return status
    }
}
