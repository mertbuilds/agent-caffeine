import XCTest

final class FileActivityReaderTests: XCTestCase {
    private func file(_ path: String, _ size: UInt64, _ modified: TimeInterval) -> FileSnapshot {
        FileSnapshot(path: path, size: size, modifiedAt: Date(timeIntervalSince1970: modified))
    }

    func testActivity() {
        let cases: [(name: String, previous: [FileSnapshot]?, current: [FileSnapshot], changed: [String], delta: Int64, newest: TimeInterval?)] = [
            ("first poll sets the baseline", nil, [file("/a", 10, 100)], [], 0, 100),
            ("nothing changed", [file("/a", 10, 100)], [file("/a", 10, 100)], [], 0, 100),
            ("file grew", [file("/a", 10, 100)], [file("/a", 25, 105)], ["/a"], 15, 105),
            ("rewritten in place, same size", [file("/a", 10, 100)], [file("/a", 10, 105)], ["/a"], 0, 105),
            ("truncated", [file("/a", 4_000, 100)], [file("/a", 0, 105)], ["/a"], -4_000, 105),
            ("new file", [file("/a", 10, 100)], [file("/a", 10, 100), file("/b", 7, 104)], ["/b"], 7, 104),
            ("file gone", [file("/a", 10, 100), file("/b", 7, 104)], [file("/a", 10, 100)], ["/b"], -7, 100),
            ("several files", [file("/a", 10, 100), file("/b", 7, 104), file("/c", 1, 90)], [file("/c", 3, 110), file("/a", 10, 100), file("/b", 5, 108)], ["/b", "/c"], 0, 110),
            ("empty after empty", [], [], [], 0, nil),
            ("first file after empty", [], [file("/a", 10, 100)], ["/a"], 10, 100),
        ]
        for (name, previous, current, changed, delta, newest) in cases {
            let activity = FileActivityReader.activity(previous: previous, current: current)
            XCTAssertEqual(activity.changedPaths, changed, name)
            XCTAssertEqual(activity.sizeDelta, delta, name)
            XCTAssertEqual(activity.newestModification, newest.map(Date.init(timeIntervalSince1970:)), name)
            XCTAssertEqual(activity.hasChanged, !changed.isEmpty, name)
        }
    }

    func testReportOnlyOnChange() {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let quiet = FileActivityReader.activity(previous: [file("/a", 10, 100)], current: [file("/a", 10, 100)])
        XCTAssertNil(FileActivityReader.report(for: quiet, now: now))
        let busy = FileActivityReader.activity(previous: [file("/a", 10, 100)], current: [file("/a", 11, 101)])
        XCTAssertEqual(FileActivityReader.report(for: busy, now: now), StateReport(
            state: .working, since: nil, observedAt: now, source: .fileActivity, detail: "writing session files"
        ))
    }

    func testGlob() {
        let cases: [(name: String, glob: String, matches: Bool)] = [
            ("a1b2.db", "*.db", true),
            ("a1b2.db-wal", "*.db", false),
            ("a1b2.db-wal", "*.db*", true),
            ("opencode.db-wal", "opencode.db-wal", true),
            ("rollout-1.jsonl", "rollout-?.jsonl", true),
            ("notes.txt", "*.db", false),
        ]
        for (name, glob, matches) in cases {
            XCTAssertEqual(FileActivityReader.matches(name, glob: glob), matches, "\(name) \(glob)")
        }
    }

    func testPollsPaths() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wal = directory.appendingPathComponent("store.db-wal")
        let missing = directory.appendingPathComponent("store.db")
        try Data(count: 100).write(to: wal)

        var reader = FileActivityReader(target: .paths([wal, missing]))
        let first = reader.poll()
        XCTAssertFalse(first.hasChanged)
        XCTAssertNotNil(first.newestModification)
        XCTAssertFalse(reader.poll().hasChanged)

        try Data(count: 260).write(to: wal)
        let grown = reader.poll()
        XCTAssertEqual(grown.changedPaths, [wal.path])
        XCTAssertEqual(grown.sizeDelta, 160)

        // Same size, new modification time: an in-place update.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: wal.path)
        let touched = reader.poll()
        XCTAssertEqual(touched.changedPaths, [wal.path])
        XCTAssertEqual(touched.sizeDelta, 0)

        try Data(count: 40).write(to: missing)
        XCTAssertEqual(reader.poll().changedPaths, [missing.path])
        XCTAssertFalse(reader.poll().hasChanged)
    }

    func testPollsDirectoryGlob() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(count: 10).write(to: directory.appendingPathComponent("one.db"))
        try Data(count: 10).write(to: directory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder.db"), withIntermediateDirectories: true)

        var reader = FileActivityReader(target: .directory(directory, glob: "*.db"))
        XCTAssertFalse(reader.poll().hasChanged)
        XCTAssertEqual(reader.previous?.map(\.path), [directory.appendingPathComponent("one.db").path])

        try Data(count: 5).write(to: directory.appendingPathComponent("two.db"))
        try Data(count: 99).write(to: directory.appendingPathComponent("notes.txt"))
        let added = reader.poll()
        XCTAssertEqual(added.changedPaths, [directory.appendingPathComponent("two.db").path])
        XCTAssertEqual(added.sizeDelta, 5)

        try FileManager.default.removeItem(at: directory.appendingPathComponent("one.db"))
        XCTAssertEqual(reader.poll().sizeDelta, -10)

        var gone = FileActivityReader(target: .directory(directory.appendingPathComponent("missing"), glob: "*"))
        XCTAssertFalse(gone.poll().hasChanged)
        XCTAssertNil(gone.poll().newestModification)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
