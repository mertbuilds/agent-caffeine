import Foundation

/// The disk and the crontab of this Mac, for the readers of scheduled jobs.
///
/// `crontab()` starts a process and waits for it, so no call comes from
/// the main thread: `JobStore` reads on a queue of its own.
///
/// Privacy: what is read is handed to the reader and kept nowhere else.
/// A failure says which step failed and never what the file or the
/// command gave.
struct SystemJobSourceAccess: JobSourceAccess {
    /// A plist or a jobs file above this is not read, and what crontab
    /// prints is cut there.
    static let maxBytes = 1_048_576
    static let crontabTimeout: TimeInterval = 5

    /// A test passes a script of its own, so it never reads the crontab
    /// of the person who runs it.
    var crontabCommand = URL(fileURLWithPath: "/usr/bin/crontab")
    var timeout = SystemJobSourceAccess.crontabTimeout

    func fileNames(in folder: URL) -> JobSourceRead<[String]> {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder) else { return .missing }
        guard isFolder.boolValue, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return .failed("The folder could not be read")
        }
        return .found(names)
    }

    func data(at file: URL) -> JobSourceRead<Data> {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return .missing }
        guard attributes[.type] as? FileAttributeType == .typeRegular, let size = attributes[.size] as? Int else {
            return .failed("It is no file")
        }
        guard size <= Self.maxBytes else { return .failed("The file is too large") }
        guard let data = try? Data(contentsOf: file) else { return .failed("The file could not be read") }
        return .found(data)
    }

    func crontab() -> JobSourceRead<String> {
        let process = Process()
        process.executableURL = crontabCommand
        process.arguments = ["-l"]
        let output = Pipe(), errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return .failed("crontab could not be started")
        }
        // Both pipes are read while the command runs: a pipe that is full
        // would stop it.
        let texts = Texts()
        let reading = DispatchGroup()
        for (pipe, isOutput) in [(output, true), (errors, false)] {
            reading.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile().prefix(Self.maxBytes)
                texts.set(String(decoding: data, as: UTF8.self), isOutput: isOutput)
                reading.leave()
            }
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return .failed("crontab gave no answer")
        }
        guard reading.wait(timeout: .now() + timeout) == .success else { return .failed("crontab gave no answer") }
        return CrontabJobReader.output(status: process.terminationStatus, stdout: texts.output, stderr: texts.errors)
    }

    /// What the two readers got, each on its own thread.
    private final class Texts: @unchecked Sendable {
        private let lock = NSLock()
        private var out = ""
        private var err = ""

        var output: String { lock.withLock { out } }
        var errors: String { lock.withLock { err } }

        func set(_ text: String, isOutput: Bool) {
            lock.withLock {
                if isOutput { out = text } else { err = text }
            }
        }
    }
}
