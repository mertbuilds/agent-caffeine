import XCTest

extension ProcessInfoRow {
    /// A row with the fields the pure helpers and the catalog look at.
    static func fixture(
        _ pid: Int32, ppid: Int32 = 1, start: TimeInterval = 1_791_000_000,
        path: String = "/usr/bin/true", args: [String] = [],
        tty: Int32 = ProcessInfoRow.noTTY, pgid: Int32? = nil, tpgid: Int32 = 0,
        cpu: TimeInterval = 0, energy: UInt64? = nil, instructions: UInt64? = nil,
        writes: UInt64? = nil, wakeups: UInt64? = nil
    ) -> ProcessInfoRow {
        ProcessInfoRow(
            pid: pid, ppid: ppid, startTime: start, executablePath: path, arguments: args,
            uid: 501, tty: tty, pgid: pgid ?? pid, tpgid: tpgid, cpuTime: cpu,
            energyNanojoules: energy, instructions: instructions, logicalWriteBytes: writes, wakeups: wakeups
        )
    }
}

final class ProcessCensusTests: XCTestCase {
    typealias Row = ProcessInfoRow

    /// A buffer as `sysctl KERN_PROCARGS2` fills it.
    private func procargs(argc: Int32, path: String, padding: Int = 3, strings: [String], terminated: Bool = true) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(path.utf8) + [0]
        bytes += [UInt8](repeating: 0, count: padding)
        for (index, string) in strings.enumerated() {
            bytes += Array(string.utf8)
            if terminated || index < strings.count - 1 { bytes.append(0) }
        }
        return bytes
    }

    private func parse(_ bytes: [UInt8]) -> ProcessCensus.ProcessArguments? {
        bytes.withUnsafeBytes { ProcessCensus.parseArguments(procargs2: $0) }
    }

    // MARK: parseArguments

    func testParseArguments() {
        let cases: [(name: String, bytes: [UInt8], path: String, arguments: [String])] = [
            ("claude session, env not read",
             procargs(argc: 2, path: "/Users/me/.local/bin/claude", strings: ["claude", "--dangerously-skip-permissions", "HOME=/Users/me", "TERM=xterm"]),
             "/Users/me/.local/bin/claude", ["claude", "--dangerously-skip-permissions"]),
            ("no padding",
             procargs(argc: 2, path: "/bin/sleep", padding: 0, strings: ["sleep", "20"]),
             "/bin/sleep", ["sleep", "20"]),
            ("long padding",
             procargs(argc: 1, path: "/bin/zsh", padding: 7, strings: ["-zsh", "PATH=/usr/bin"]),
             "/bin/zsh", ["-zsh"]),
            ("empty argument stays",
             procargs(argc: 4, path: "/bin/zsh", strings: ["zsh", "-c", "", "echo", "A=1"]),
             "/bin/zsh", ["zsh", "-c", "", "echo"]),
            ("argument with spaces and JSON",
             procargs(argc: 5, path: "/Users/me/.local/bin/claude", strings: ["claude", "daemon", "run", "--spawned-by", "{\"label\":\"claude\",\"pid\":93968}"]),
             "/Users/me/.local/bin/claude", ["claude", "daemon", "run", "--spawned-by", "{\"label\":\"claude\",\"pid\":93968}"]),
            ("argc larger than the buffer",
             procargs(argc: 9, path: "/bin/ls", strings: ["ls", "-la"]),
             "/bin/ls", ["ls", "-la"]),
            ("last argument cut off",
             procargs(argc: 2, path: "/bin/ls", strings: ["ls", "/Users/me/pro"], terminated: false),
             "/bin/ls", ["ls", "/Users/me/pro"]),
            ("no arguments",
             procargs(argc: 0, path: "/bin/ls", strings: ["A=1"]),
             "/bin/ls", []),
        ]
        for testCase in cases {
            let parsed = parse(testCase.bytes)
            XCTAssertEqual(parsed?.executablePath, testCase.path, testCase.name)
            XCTAssertEqual(parsed?.arguments, testCase.arguments, testCase.name)
        }
    }

    func testParseArgumentsRejectsBadBuffers() {
        XCTAssertNil(parse([]))
        XCTAssertNil(parse([1, 0, 0, 0]))
        XCTAssertNil(parse(procargs(argc: -1, path: "/bin/ls", strings: ["ls"])))
    }

    // MARK: tick conversion

    func testTickConversion() {
        // Apple silicon: one tick is 125/3 nanoseconds.
        XCTAssertEqual(ProcessCensus.nanoseconds(machTicks: 3, numer: 125, denom: 3), 125)
        XCTAssertEqual(ProcessCensus.nanoseconds(machTicks: 24_000_000, numer: 125, denom: 3), 1_000_000_000)
        // Intel: ticks are nanoseconds.
        XCTAssertEqual(ProcessCensus.nanoseconds(machTicks: 1_234_567, numer: 1, denom: 1), 1_234_567)
        // Measured on a Claude Code session: these raw user and system ticks
        // were 5617.27 seconds in `ps`.
        let ticks: UInt64 = 118_662_164_199 + 16_152_338_585
        XCTAssertEqual(ProcessCensus.seconds(machTicks: ticks, numer: 125, denom: 3), 5617.27, accuracy: 0.01)
        XCTAssertEqual(ProcessCensus.seconds(machTicks: ticks, numer: 1, denom: 1), 134.81, accuracy: 0.01)
    }

    func testTickConversionEdges() {
        XCTAssertEqual(ProcessCensus.nanoseconds(machTicks: 0, numer: 125, denom: 3), 0)
        XCTAssertEqual(ProcessCensus.nanoseconds(machTicks: 42, numer: 125, denom: 0), 42)
        // The product does not fit in 64 bits, the result does.
        XCTAssertEqual(ProcessCensus.nanoseconds(machTicks: 300_000_000_000_000_000, numer: 125, denom: 3), 12_500_000_000_000_000_000)
        XCTAssertEqual(ProcessCensus.nanoseconds(machTicks: .max, numer: 125, denom: 3), .max)
    }

    // MARK: tree

    private let tree: [Row] = [
        .fixture(0, ppid: 0),
        .fixture(1, ppid: 0),
        .fixture(100, ppid: 1),
        .fixture(110, ppid: 100),
        .fixture(111, ppid: 110),
        .fixture(120, ppid: 100),
        .fixture(200, ppid: 1),
    ]

    func testChildrenIndex() {
        let children = ProcessCensus.childrenIndex(of: tree)
        XCTAssertEqual(children[0]?.map(\.pid), [1])
        XCTAssertEqual(children[1]?.map(\.pid), [100, 200])
        XCTAssertEqual(children[100]?.map(\.pid), [110, 120])
        XCTAssertNil(children[111])
    }

    func testSubtree() {
        let children = ProcessCensus.childrenIndex(of: tree)
        XCTAssertEqual(ProcessCensus.subtree(of: tree[2], in: children).map(\.pid), [100, 110, 111, 120])
        XCTAssertEqual(ProcessCensus.subtree(of: tree[6], in: children).map(\.pid), [200])
        XCTAssertEqual(ProcessCensus.subtree(of: tree[2], in: children, stoppingAt: [110]).map(\.pid), [100, 120])
        // The root itself is never stopped.
        XCTAssertEqual(ProcessCensus.subtree(of: tree[3], in: children, stoppingAt: [110]).map(\.pid), [110, 111])
    }

    func testSubtreeSurvivesParentCycle() {
        let rows: [Row] = [.fixture(10, ppid: 11), .fixture(11, ppid: 10)]
        let children = ProcessCensus.childrenIndex(of: rows)
        XCTAssertEqual(ProcessCensus.subtree(of: rows[0], in: children).map(\.pid), [10, 11])
    }

    // MARK: delta

    func testSubtreeDelta() {
        let before: [Row] = [
            .fixture(100, cpu: 10, energy: 1000, instructions: 500, writes: 50, wakeups: 7),
            .fixture(110, ppid: 100, cpu: 2, energy: 200, instructions: 100, writes: 0, wakeups: 1),
            // Exits before the next snapshot.
            .fixture(120, ppid: 100, cpu: 30, energy: 9000, instructions: 9000, writes: 900, wakeups: 90),
        ]
        let after: [Row] = [
            .fixture(100, cpu: 10.5, energy: 1500, instructions: 800, writes: 60, wakeups: 9),
            .fixture(110, ppid: 100, cpu: 3, energy: 300, instructions: 150, writes: 0, wakeups: 1),
            // Started since the previous snapshot.
            .fixture(130, ppid: 110, start: 1_791_000_100, cpu: 0.25, energy: 40, instructions: 20, writes: 5, wakeups: 2),
            .fixture(900, cpu: 99, energy: 99, instructions: 99, writes: 99, wakeups: 99),
        ]
        let delta = ProcessCensus.subtreeDelta(of: after[0], in: ProcessCensus.childrenIndex(of: after), since: ProcessCensus.identityIndex(of: before))
        XCTAssertEqual(delta.cpuTime, 1.75, accuracy: 1e-9)
        XCTAssertEqual(delta.energyNanojoules, 640)
        XCTAssertEqual(delta.instructions, 370)
        XCTAssertEqual(delta.logicalWriteBytes, 15)
        XCTAssertEqual(delta.wakeups, 4)
        XCTAssertEqual(delta.startedProcesses, 1)
    }

    func testReusedPidIsNewProcess() {
        let before: [Row] = [.fixture(100, start: 1_791_000_000, cpu: 50, energy: 5000)]
        // Same pid, later start time, less CPU than the old process had.
        let reused: Row = .fixture(100, start: 1_791_000_300.25, cpu: 4, energy: 400)
        let delta = ProcessCensus.delta(of: [reused], since: ProcessCensus.identityIndex(of: before))
        XCTAssertEqual(delta.cpuTime, 4, accuracy: 1e-9)
        XCTAssertEqual(delta.energyNanojoules, 400)
        XCTAssertEqual(delta.startedProcesses, 1)
        // Same pid with more CPU is still a new process, counted in full.
        let busier: Row = .fixture(100, start: 1_791_000_300.25, cpu: 80, energy: 8000)
        XCTAssertEqual(ProcessCensus.delta(of: [busier], since: ProcessCensus.identityIndex(of: before)).cpuTime, 80, accuracy: 1e-9)
    }

    func testDeltaWithMissingCounters() {
        let before: [Row] = [.fixture(100, cpu: 1), .fixture(110, cpu: 1, instructions: 10)]
        let after: [Row] = [.fixture(100, cpu: 2), .fixture(110, cpu: 1, instructions: 25)]
        let delta = ProcessCensus.delta(of: after, since: ProcessCensus.identityIndex(of: before))
        XCTAssertEqual(delta.cpuTime, 1, accuracy: 1e-9)
        XCTAssertNil(delta.energyNanojoules)
        XCTAssertEqual(delta.instructions, 15)
        XCTAssertEqual(delta.startedProcesses, 0)
        XCTAssertEqual(ProcessCensus.delta(of: [], since: [:]), ProcessDelta())
    }

    func testDeltaNeverGoesNegative() {
        let before: [Row] = [.fixture(100, cpu: 5, energy: 500)]
        let after: [Row] = [.fixture(100, cpu: 4, energy: 400)]
        let delta = ProcessCensus.delta(of: after, since: ProcessCensus.identityIndex(of: before))
        XCTAssertEqual(delta.cpuTime, 0)
        XCTAssertEqual(delta.energyNanojoules, 0)
    }

    func testForegroundJob() {
        XCTAssertTrue(Row.fixture(2422, tty: 0x1000_0001, pgid: 2422, tpgid: 2422).isForegroundJob)
        // The shell behind a foreground agent.
        XCTAssertFalse(Row.fixture(2514, tty: 0x1000_0001, pgid: 2514, tpgid: 2422).isForegroundJob)
        XCTAssertFalse(Row.fixture(20909, pgid: 0, tpgid: 0).isForegroundJob)
    }

    // MARK: live

    func testLiveSnapshotFindsThisProcess() throws {
        // Use some CPU first, so a wrong tick conversion cannot hide in rounding.
        var usage = rusage()
        var sink: UInt64 = 0
        repeat {
            for value in 0..<2_000_000 as Range<UInt64> { sink = sink &* 31 &+ value }
            getrusage(RUSAGE_SELF, &usage)
        } while usage.ru_utime.tv_sec == 0 && usage.ru_utime.tv_usec < 300_000
        XCTAssertNotEqual(sink, 1)

        let rows = SystemProcessCensus().snapshot()
        getrusage(RUSAGE_SELF, &usage)
        let expected = TimeInterval(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + TimeInterval(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let own = try XCTUnwrap(rows.first { $0.pid == getpid() })
        XCTAssertEqual(own.ppid, getppid())
        XCTAssertEqual(own.uid, getuid())
        XCTAssertTrue(own.executablePath.hasPrefix("/"))
        XCTAssertEqual(own.arguments, ProcessInfo.processInfo.arguments)
        XCTAssertGreaterThan(own.cpuTime, expected * 0.5)
        XCTAssertLessThan(own.cpuTime, expected * 1.5)
        let now = Date().timeIntervalSince1970
        XCTAssertLessThanOrEqual(own.startTime, now)
        XCTAssertGreaterThan(own.startTime, now - 86400)
        XCTAssertNotNil(own.wakeups)
        XCTAssertTrue(rows.allSatisfy { $0.uid == getuid() })
        XCTAssertEqual(Set(rows.map(\.identity)).count, rows.count)
    }

    func testZombieStatusIsNotRunning() {
        XCTAssertFalse(ProcessCensus.isRunning(status: Int8(SZOMB)))
        for status in [SIDL, SRUN, SSLEEP, SSTOP] {
            XCTAssertTrue(ProcessCensus.isRunning(status: Int8(status)), "\(status)")
        }
    }

    /// A killed child that nobody reaped stays in the process table, and
    /// the census has its path from before. It must not stay in the census.
    func testLiveSnapshotLeavesOutAZombie() throws {
        var pid: pid_t = 0
        let arguments: [UnsafeMutablePointer<CChar>?] = [strdup("sleep"), strdup("60"), nil]
        defer { arguments.forEach { free($0) } }
        XCTAssertEqual(posix_spawn(&pid, "/bin/sleep", nil, nil, arguments, nil), 0)
        defer {
            kill(pid, SIGKILL)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
        func status() -> Int32? {
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            var entry = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            guard sysctl(&mib, 4, &entry, &size, nil, 0) == 0, size > 0 else { return nil }
            return Int32(entry.kp_proc.p_stat)
        }
        func wait(for condition: () -> Bool) -> Bool {
            for _ in 0..<500 where !condition() { usleep(10_000) }
            return condition()
        }

        let census = SystemProcessCensus()
        // The spawn returns before the exec is done.
        XCTAssertTrue(wait { census.snapshot().contains { $0.pid == pid && $0.executablePath == "/bin/sleep" } })
        XCTAssertNotNil(SystemProcessCensus.row(of: pid))

        kill(pid, SIGKILL)
        XCTAssertTrue(wait { status() == SZOMB }, "The child is a zombie until it is reaped")
        XCTAssertFalse(census.snapshot().contains { $0.pid == pid })
        XCTAssertNil(SystemProcessCensus.row(of: pid))
        XCTAssertEqual(status(), SZOMB, "Still not reaped after the snapshot")
    }

    func testLiveSnapshotTiming() {
        func time(_ body: () -> Int) -> (count: Int, seconds: TimeInterval) {
            let start = DispatchTime.now().uptimeNanoseconds
            let count = body()
            return (count, TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
        }
        let census = SystemProcessCensus()
        // The first snapshot reads the path and argv of every process.
        let first = time { census.snapshot().count }
        var times: [TimeInterval] = []
        for _ in 0..<20 { times.append(time { census.snapshot().count }.seconds) }
        times.sort()
        let median = times[times.count / 2]
        print(String(format: "census: %d rows, first %.2f ms, then median %.2f ms, min %.2f ms, max %.2f ms", first.count, first.seconds * 1000, median * 1000, times[0] * 1000, times[times.count - 1] * 1000))
        XCTAssertGreaterThan(first.count, 0)
        // The target is under 5 ms. Real time depends on what else the Mac
        // does, so the limits are checked only when asked for:
        // TEST_RUNNER_CAFFEINAGENT_TIMING=1 xcodebuild test ...
        guard ProcessInfo.processInfo.environment["CAFFEINAGENT_TIMING"] == "1" else { return }
        XCTAssertLessThan(median, 0.025)
        XCTAssertLessThan(first.seconds, 0.25)
    }

    func testSecondSnapshotKeepsPathAndArguments() throws {
        let census = SystemProcessCensus()
        let first = try XCTUnwrap(census.snapshot().first { $0.pid == getpid() })
        let second = try XCTUnwrap(census.snapshot().first { $0.pid == getpid() })
        XCTAssertEqual(second.identity, first.identity)
        XCTAssertEqual(second.executablePath, first.executablePath)
        XCTAssertEqual(second.arguments, ProcessInfo.processInfo.arguments)
        XCTAssertGreaterThanOrEqual(second.cpuTime, first.cpuTime)
    }
}
