import XCTest

final class DisplayTraceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_200_000)
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() {
        defaults = TestDefaults()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func row(_ seconds: TimeInterval, raw: Double? = 30, written: Float? = nil, read: Float? = nil) -> DisplayTraceRow {
        DisplayTraceRow(time: start.addingTimeInterval(seconds), raw: raw, estimate: 30.25, target: 0.4248, written: written, read: read)
    }

    private var names: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    func testOneLinePerStepWithTabs() {
        var trace = DisplayTrace()
        XCTAssertTrue(trace.isEmpty)
        trace.add(row(0, written: 0.4248, read: 0.4248))
        trace.add(row(1.0 / 120, raw: nil))
        XCTAssertEqual(trace.text, """
        seconds\trawAngle\tangle\ttarget\twritten\tread\tfight
        0.0000\t30\t30.250\t0.4248\t0.4248\t0.4248\t0
        0.0083\t-\t30.250\t0.4248\t-\t-\t0

        """)
        XCTAssertEqual(trace.start, start)
    }

    func testAFightIsABrightnessThatIsNotTheOneThatWasSet() {
        var trace = DisplayTrace()
        trace.add(row(0, read: 0.2))
        XCTAssertTrue(trace.lines[0].hasSuffix("\t0"), "Nothing was set yet")
        trace.add(row(0.01, written: 0.4, read: 0.405))
        XCTAssertTrue(trace.lines[1].hasSuffix("\t0"), "Half a percent is the panel's own step")
        trace.add(row(0.02, read: 0.42))
        XCTAssertTrue(trace.lines[2].hasSuffix("\t1"), "macOS moved it after the fade set it")
        trace.add(row(0.03, written: 0.39, read: 0.39))
        XCTAssertTrue(trace.lines[3].hasSuffix("\t0"))
    }

    func testATraceHasAtMost2000Lines() {
        var trace = DisplayTrace()
        for frame in 0..<2000 { XCTAssertTrue(trace.add(row(Double(frame) / 120))) }
        XCTAssertFalse(trace.add(row(20)))
        XCTAssertEqual(trace.lines.count, DisplayTrace.maxLines)
        XCTAssertEqual(trace.text.split(separator: "\n").count, 2001, "And the header")
    }

    func testTheNewestFiveFilesStay() {
        let traces = (1...7).map { "display-trace-20261007-10000\($0)-000.tsv" }
        XCTAssertEqual(DisplayTrace.stale(among: traces.shuffled() + ["lab", "display-trace-notes.txt", "hooks"]), Array(traces.prefix(2)))
        XCTAssertEqual(DisplayTrace.stale(among: Array(traces.prefix(5))), [])
        let name = DisplayTrace.fileName(start: start)
        XCTAssertTrue(name.hasPrefix("display-trace-2026"))
        XCTAssertTrue(name.hasSuffix(".tsv"))
        XCTAssertLessThan(name, DisplayTrace.fileName(start: start.addingTimeInterval(0.01)), "The names sort by time")
    }

    func testWithTheSwitchOffNothingIsWritten() {
        let recorder = DisplayTraceRecorder(defaults: defaults, directory: directory)
        XCTAssertFalse(recorder.isRecording)
        recorder.add(row(0))
        recorder.finish()
        XCTAssertEqual(names, [])
    }

    func testWithTheSwitchOnEachFadeIsAFileAndFiveAreKept() throws {
        defaults.set(true, forKey: DisplayTrace.defaultsKey)
        XCTAssertEqual(DisplayTrace.defaultsKey, "Display.debugTrace")
        let recorder = DisplayTraceRecorder(defaults: defaults, directory: directory)
        recorder.finish()
        XCTAssertEqual(names, [], "A fade with no step leaves no file")
        for fade in 0..<7 {
            recorder.add(row(Double(fade), written: 0.4, read: 0.4))
            recorder.add(row(Double(fade) + 0.01))
            XCTAssertEqual(names.count, min(fade, 5), "Written when the fade ends")
            recorder.finish()
        }
        XCTAssertEqual(names.count, 5)
        XCTAssertEqual(names.first, DisplayTrace.fileName(start: start.addingTimeInterval(2)))
        let text = try String(contentsOf: directory.appendingPathComponent(names[4]), encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 3)

        // Switched off while the app runs: the next fade leaves no file.
        defaults.set(false, forKey: DisplayTrace.defaultsKey)
        recorder.add(row(10))
        recorder.finish()
        XCTAssertEqual(names.count, 5)
    }
}
