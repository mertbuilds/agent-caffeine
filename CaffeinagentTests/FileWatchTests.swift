import XCTest

final class FileWatchTests: XCTestCase {
    private let queue = DispatchQueue(label: "com.caffeinagent.tests.filewatch")
    private var directory: URL!
    /// An event comes within milliseconds, and a wait ends when it comes.
    /// The long limit is for a Mac that is busy with other work.
    private static let patience: TimeInterval = 10

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// Collects events on the callback queue and lets a test wait for one.
    private final class Recorder {
        private let lock = NSLock()
        private var events: [FileWatch.Event] = []
        private var waiting: [(FileWatch.Event, XCTestExpectation)] = []

        func record(_ event: FileWatch.Event) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
            waiting.removeAll { wanted, expectation in
                guard wanted == event else { return false }
                expectation.fulfill()
                return true
            }
        }

        /// Fulfilled by the next `event` after this call.
        func next(_ event: FileWatch.Event) -> XCTestExpectation {
            let expectation = XCTestExpectation(description: "\(event)")
            lock.lock()
            defer { lock.unlock() }
            waiting.append((event, expectation))
            return expectation
        }

        var all: [FileWatch.Event] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testWriteCallsBack() throws {
        let url = directory.appendingPathComponent("session.jsonl")
        try Data("one\n".utf8).write(to: url)
        let recorder = Recorder()
        let watch = FileWatch(url: url, queue: queue) { recorder.record($0) }
        watch.start()
        defer { watch.cancel() }

        let written = recorder.next(.written)
        try append("two\n", to: url)
        wait(for: [written], timeout: Self.patience)
    }

    func testWriteWhileWriterKeepsTheFileOpen() throws {
        let url = directory.appendingPathComponent("held.jsonl")
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let recorder = Recorder()
        let watch = FileWatch(url: url, queue: queue) { recorder.record($0) }
        watch.start()
        defer { watch.cancel() }

        for line in ["one\n", "two\n"] {
            let written = recorder.next(.written)
            try handle.write(contentsOf: Data(line.utf8))
            wait(for: [written], timeout: Self.patience)
        }
    }

    func testAtomicReplaceKeepsWatching() throws {
        let url = directory.appendingPathComponent("4242.json")
        try Data(#"{"status":"idle"}"#.utf8).write(to: url)
        let recorder = Recorder()
        let watch = FileWatch(url: url, queue: queue) { recorder.record($0) }
        watch.start()
        defer { watch.cancel() }

        for status in ["busy", "idle"] {
            let replaced = recorder.next(.replaced)
            try Data(#"{"status":"\#(status)"}"#.utf8).write(to: url, options: .atomic)
            wait(for: [replaced], timeout: Self.patience)
        }
        let written = recorder.next(.written)
        try append("\n", to: url)
        wait(for: [written], timeout: Self.patience)
    }

    func testDeleteThenRecreate() throws {
        let url = directory.appendingPathComponent("4242.json")
        try Data("{}".utf8).write(to: url)
        let recorder = Recorder()
        let watch = FileWatch(url: url, queue: queue, retryInterval: 0.05) { recorder.record($0) }
        watch.start()
        defer { watch.cancel() }

        let removed = recorder.next(.removed)
        try FileManager.default.removeItem(at: url)
        wait(for: [removed], timeout: Self.patience)

        let replaced = recorder.next(.replaced)
        try Data("{}".utf8).write(to: url)
        wait(for: [replaced], timeout: Self.patience)

        let written = recorder.next(.written)
        try append("\n", to: url)
        wait(for: [written], timeout: Self.patience)
    }

    func testFileThatAppearsLater() throws {
        let url = directory.appendingPathComponent("later.json")
        let recorder = Recorder()
        let watch = FileWatch(url: url, queue: queue, retryInterval: 0.05) { recorder.record($0) }
        watch.start()
        defer { watch.cancel() }

        let appeared = recorder.next(.replaced)
        try Data("{}".utf8).write(to: url)
        wait(for: [appeared], timeout: Self.patience)
    }

    func testCancelStopsCallbacks() throws {
        let url = directory.appendingPathComponent("session.jsonl")
        try Data("one\n".utf8).write(to: url)
        let recorder = Recorder()
        let watch = FileWatch(url: url, queue: queue) { recorder.record($0) }
        watch.start()
        watch.cancel()
        watch.cancel()
        watch.start()

        try append("two\n", to: url)
        let quiet = XCTestExpectation(description: "quiet")
        queue.asyncAfter(deadline: .now() + 0.3) { quiet.fulfill() }
        wait(for: [quiet], timeout: Self.patience)
        XCTAssertEqual(recorder.all, [])
    }

    func testReleasedWatchStops() throws {
        let url = directory.appendingPathComponent("session.jsonl")
        try Data("one\n".utf8).write(to: url)
        let recorder = Recorder()
        var watch: FileWatch? = FileWatch(url: url, queue: queue) { recorder.record($0) }
        watch?.start()
        watch = nil

        try append("two\n", to: url)
        let quiet = XCTestExpectation(description: "quiet")
        queue.asyncAfter(deadline: .now() + 0.3) { quiet.fulfill() }
        wait(for: [quiet], timeout: Self.patience)
        XCTAssertEqual(recorder.all, [])
    }

    func testDirectoryWatchSeesNewFile() throws {
        let seen = XCTestExpectation(description: "new entry")
        seen.assertForOverFulfill = false
        let watch = DirectoryWatch(url: directory, queue: queue) { seen.fulfill() }
        watch.start()
        defer { watch.cancel() }

        try Data("{}".utf8).write(to: directory.appendingPathComponent("rollout-new.jsonl"))
        wait(for: [seen], timeout: Self.patience)
    }
}
