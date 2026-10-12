import Darwin
import Foundation

/// A pid is reused after its process exits, so a process is identified by
/// its pid together with its start time.
struct ProcessIdentity: Hashable {
    let pid: Int32
    let startTime: TimeInterval
}

struct ProcessInfoRow: Equatable {
    let pid: Int32
    let ppid: Int32
    /// Seconds since the epoch, with microseconds.
    let startTime: TimeInterval
    /// The resolved binary from `proc_pidpath`. For Claude Code this ends in
    /// its version number, not in `claude`. With `executableGone` it is the
    /// path the process was started with, which can be a link
    /// (`~/.local/bin/claude`). Nothing may read the file at this path.
    let executablePath: String
    /// argv as the process was started, or as it rewrote it (process title).
    let arguments: [String]
    let uid: UInt32
    /// Device number of the controlling terminal, `noTTY` without one.
    let tty: Int32
    let pgid: Int32
    /// Foreground process group of the controlling terminal.
    let tpgid: Int32
    /// User plus system CPU time.
    let cpuTime: TimeInterval
    /// Nil when the kernel's rusage version has no energy counter.
    let energyNanojoules: UInt64?
    let instructions: UInt64?
    /// Bytes handed to the file system, counted at write time.
    let logicalWriteBytes: UInt64?
    /// Package idle plus interrupt wakeups.
    let wakeups: UInt64?
    /// Stopped by a signal, as with `kill -STOP` or Ctrl-Z, until it is
    /// continued. See `ProcessCensus.isStopped`.
    var isStopped = false
    /// The file of the binary was deleted or replaced while the process
    /// runs, as an update does: `proc_pidpath` gave nothing. See
    /// `ProcessCensus.executable`.
    var executableGone = false

    static let noTTY: Int32 = -1

    var identity: ProcessIdentity { ProcessIdentity(pid: pid, startTime: startTime) }
    var hasTTY: Bool { tty != Self.noTTY }
    /// False for a job that runs under `&` or was suspended with Ctrl-Z.
    var isForegroundJob: Bool { hasTTY && pgid == tpgid }
}

protocol ProcessCensusing {
    /// Nil when the process table could not be read. That is not the same
    /// as a table with no agent in it.
    func snapshot() -> [ProcessInfoRow]?
}

/// What a set of processes used between two snapshots.
struct ProcessDelta: Equatable {
    var cpuTime: TimeInterval = 0
    var energyNanojoules: UInt64?
    var instructions: UInt64?
    var logicalWriteBytes: UInt64?
    var wakeups: UInt64?
    /// Processes that were not in the previous snapshot.
    var startedProcesses = 0
}

enum ProcessCensus {
    struct ProcessArguments: Equatable {
        /// The path as invoked, which may be a symlink (`~/.local/bin/claude`).
        let executablePath: String
        let arguments: [String]
    }

    /// Parses a `sysctl KERN_PROCARGS2` buffer: a 32-bit argc, the executable
    /// path, NUL padding up to the next word, then argc NUL-terminated
    /// arguments, then the environment. Only the padding is skipped, so an
    /// empty argument after argv[0] stays an empty argument. A buffer that
    /// ends early gives the arguments read so far.
    static func parseArguments(procargs2 buffer: UnsafeRawBufferPointer) -> ProcessArguments? {
        let argcSize = MemoryLayout<Int32>.size
        guard buffer.count > argcSize else { return nil }
        let argc = Int(buffer.loadUnaligned(as: Int32.self))
        guard argc >= 0 else { return nil }
        var index = argcSize
        func nextString() -> String? {
            guard index < buffer.count else { return nil }
            let start = index
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            let text = String(decoding: UnsafeRawBufferPointer(rebasing: buffer[start..<index]), as: UTF8.self)
            index += 1
            return text
        }
        guard let path = nextString() else { return nil }
        while index < buffer.count && buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        arguments.reserveCapacity(min(argc, 64))
        while arguments.count < argc, let argument = nextString() {
            arguments.append(argument)
        }
        return ProcessArguments(executablePath: path, arguments: arguments)
    }

    /// The path of the binary of a process. `proc_pidpath` gives nothing
    /// for a binary whose file is gone: Claude Code deletes the file of an
    /// old version while sessions of that version still run
    /// (docs/research/01-oss-detection.md, section 10). The path the
    /// process was started with stays in its arguments buffer, so it is
    /// taken then. Nil when neither gives a path.
    static func executable(resolved: String?, started: ProcessArguments?) -> (path: String, gone: Bool)? {
        if let resolved, !resolved.isEmpty { return (resolved, false) }
        if let path = started?.executablePath, !path.isEmpty { return (path, true) }
        return nil
    }

    /// CPU times from libproc are mach absolute time ticks. One tick is
    /// numer/denom nanoseconds: 1/1 on Intel, 125/3 on Apple silicon.
    static func nanoseconds(machTicks ticks: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        guard denom != 0 else { return ticks }
        let product = ticks.multipliedFullWidth(by: UInt64(numer))
        guard product.high < UInt64(denom) else { return .max }
        return UInt64(denom).dividingFullWidth(product).quotient
    }

    static func seconds(machTicks ticks: UInt64, numer: UInt32, denom: UInt32) -> TimeInterval {
        TimeInterval(nanoseconds(machTicks: ticks, numer: numer, denom: denom)) / 1_000_000_000
    }

    /// False for a zombie: a process that ended and that its parent has
    /// not reaped. The kernel still lists it and still answers for its
    /// usage, and it does no work any more. `status` is `p_stat`.
    static func isRunning(status: Int8) -> Bool {
        Int32(status) != SZOMB
    }

    /// True for a process that a signal stopped: it is still there and
    /// does nothing until it is continued. `status` is `p_stat`.
    static func isStopped(status: Int8) -> Bool {
        Int32(status) == SSTOP
    }

    /// Children by parent pid. The kernel task is its own parent and is left out.
    static func childrenIndex(of rows: [ProcessInfoRow]) -> [Int32: [ProcessInfoRow]] {
        Dictionary(grouping: rows.filter { $0.pid != $0.ppid }, by: \.ppid)
    }

    static func identityIndex(of rows: [ProcessInfoRow]) -> [ProcessIdentity: ProcessInfoRow] {
        Dictionary(rows.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The root and all its descendants, root first. A pid in `stopAt` is
    /// left out together with everything below it, unless it is the root.
    static func subtree(of root: ProcessInfoRow, in children: [Int32: [ProcessInfoRow]], stoppingAt stopAt: Set<Int32> = []) -> [ProcessInfoRow] {
        var result: [ProcessInfoRow] = []
        var visited: Set<Int32> = []
        var stack = [root]
        while let row = stack.popLast() {
            guard visited.insert(row.pid).inserted else { continue }
            result.append(row)
            for child in (children[row.pid] ?? []).reversed() where !stopAt.contains(child.pid) {
                stack.append(child)
            }
        }
        return result
    }

    /// What the rows used since the previous snapshot. A row with no previous
    /// row of the same identity (a new process, or a reused pid) counts with
    /// all it used so far. Processes that exited in between drop out, so the
    /// sum never goes negative. A counter is nil when no row carries it.
    static func delta(of rows: [ProcessInfoRow], since previous: [ProcessIdentity: ProcessInfoRow]) -> ProcessDelta {
        var delta = ProcessDelta()
        func add(_ total: inout UInt64?, _ now: UInt64?, _ before: UInt64?) {
            guard let now else { return }
            let before = before ?? 0
            total = (total ?? 0) &+ (now >= before ? now - before : 0)
        }
        for row in rows {
            let old = previous[row.identity]
            if old == nil { delta.startedProcesses += 1 }
            delta.cpuTime += max(0, row.cpuTime - (old?.cpuTime ?? 0))
            add(&delta.energyNanojoules, row.energyNanojoules, old?.energyNanojoules)
            add(&delta.instructions, row.instructions, old?.instructions)
            add(&delta.logicalWriteBytes, row.logicalWriteBytes, old?.logicalWriteBytes)
            add(&delta.wakeups, row.wakeups, old?.wakeups)
        }
        return delta
    }

    static func subtreeDelta(of root: ProcessInfoRow, in children: [Int32: [ProcessInfoRow]], since previous: [ProcessIdentity: ProcessInfoRow]) -> ProcessDelta {
        delta(of: subtree(of: root, in: children), since: previous)
    }
}

/// Reads the process table with sysctl and libproc, without spawning `ps`.
/// Only processes of the current user are returned: the kernel refuses the
/// per-process calls for other users (EPERM), and agents run as the user.
///
/// Reading argv is the expensive part (about 4 microseconds per process), so
/// the path and argv of a process are read once and kept until it exits. A
/// binary that is deleted after that read keeps its resolved path here. An
/// exec keeps pid and start time and changes the short name, so the short
/// name is part of the cache key. A process that execs a binary with the
/// same base name keeps its first argv here.
final class SystemProcessCensus: ProcessCensusing {
    private struct Image {
        let startTime: TimeInterval
        let name: ShortName
        let executablePath: String
        let executableGone: Bool
        let arguments: [String]
    }

    /// The 16 bytes of `p_comm`.
    private struct ShortName: Equatable {
        let low: UInt64
        let high: UInt64
    }

    private let lock = NSLock()
    private var images: [Int32: Image] = [:]

    func snapshot() -> [ProcessInfoRow]? {
        lock.lock()
        defer { lock.unlock() }
        let uid = getuid()
        guard let table = Self.processTable() else { return nil }
        var rows: [ProcessInfoRow] = []
        rows.reserveCapacity(table.count)
        var alive: [Int32: Image] = [:]
        alive.reserveCapacity(images.count)
        var pathBuffer: [CChar] = []
        var argumentBuffer: [UInt8] = []
        for entry in table {
            let pid = entry.kp_proc.p_pid
            guard pid > 0, entry.kp_eproc.e_ucred.cr_uid == uid, ProcessCensus.isRunning(status: entry.kp_proc.p_stat) else { continue }
            // A process that exited since the table was read fails here and is skipped.
            guard let usage = Self.resourceUsage(of: pid) else { continue }
            let start = entry.kp_proc.p_un.__p_starttime
            let startTime = TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
            let name = withUnsafeBytes(of: entry.kp_proc.p_comm) {
                ShortName(low: $0.loadUnaligned(as: UInt64.self), high: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
            }
            let image: Image
            if let known = images[pid], known.startTime == startTime, known.name == name {
                image = known
            } else {
                if pathBuffer.isEmpty {
                    pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                    argumentBuffer = [UInt8](repeating: 0, count: Self.argumentBufferSize)
                }
                let started = Self.arguments(of: pid, buffer: &argumentBuffer)
                guard let executable = ProcessCensus.executable(resolved: Self.executablePath(of: pid, buffer: &pathBuffer), started: started) else { continue }
                image = Image(startTime: startTime, name: name, executablePath: executable.path, executableGone: executable.gone, arguments: started?.arguments ?? [])
            }
            alive[pid] = image
            rows.append(ProcessInfoRow(
                pid: pid,
                ppid: entry.kp_eproc.e_ppid,
                startTime: startTime,
                executablePath: image.executablePath,
                arguments: image.arguments,
                uid: entry.kp_eproc.e_ucred.cr_uid,
                tty: entry.kp_eproc.e_tdev,
                pgid: entry.kp_eproc.e_pgid,
                tpgid: entry.kp_eproc.e_tpgid,
                cpuTime: usage.cpuTime,
                energyNanojoules: usage.energyNanojoules,
                instructions: usage.instructions,
                logicalWriteBytes: usage.logicalWriteBytes,
                wakeups: usage.wakeups,
                isStopped: ProcessCensus.isStopped(status: entry.kp_proc.p_stat),
                executableGone: image.executableGone
            ))
        }
        images = alive
        return rows
    }

    /// One process, for a caller that walks up from a pid. The usage
    /// counters are left at zero. Nil when the process is gone, is a zombie
    /// or belongs to another user.
    static func row(of pid: Int32) -> ProcessInfoRow? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var entry = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &entry, &size, nil, 0) == 0, size > 0, entry.kp_proc.p_pid == pid,
              ProcessCensus.isRunning(status: entry.kp_proc.p_stat) else { return nil }
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var argumentBuffer = [UInt8](repeating: 0, count: argumentBufferSize)
        let started = arguments(of: pid, buffer: &argumentBuffer)
        guard let executable = ProcessCensus.executable(resolved: executablePath(of: pid, buffer: &pathBuffer), started: started) else { return nil }
        let start = entry.kp_proc.p_un.__p_starttime
        return ProcessInfoRow(
            pid: pid,
            ppid: entry.kp_eproc.e_ppid,
            startTime: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000,
            executablePath: executable.path,
            arguments: started?.arguments ?? [],
            uid: entry.kp_eproc.e_ucred.cr_uid,
            tty: entry.kp_eproc.e_tdev,
            pgid: entry.kp_eproc.e_pgid,
            tpgid: entry.kp_eproc.e_tpgid,
            cpuTime: 0,
            energyNanojoules: nil,
            instructions: nil,
            logicalWriteBytes: nil,
            wakeups: nil,
            isStopped: ProcessCensus.isStopped(status: entry.kp_proc.p_stat),
            executableGone: executable.gone
        )
    }

    private struct ResourceUsage {
        let cpuTime: TimeInterval
        let energyNanojoules: UInt64?
        let instructions: UInt64?
        let logicalWriteBytes: UInt64?
        let wakeups: UInt64?
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    // The energy counter came with rusage V6. A kernel that does not know V6
    // refuses it, and V4 still has every other counter. V6 starts with the
    // V4 layout, so one struct serves both.
    private static let rusageFlavor: Int32 = {
        var info = rusage_info_v6()
        return readUsage(of: getpid(), flavor: RUSAGE_INFO_V6, into: &info) ? RUSAGE_INFO_V6 : RUSAGE_INFO_V4
    }()

    // The kernel never returns more than kern.argmax bytes of arguments.
    private static let argumentBufferSize: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value > 0 else { return 1 << 20 }
        return Int(value)
    }()

    /// Every process, from one `sysctl KERN_PROC_ALL`. The table can grow
    /// between asking for its size and reading it, so there is slack and a
    /// retry. Nil when the kernel gives no table.
    private static func processTable() -> [kinfo_proc]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
            let capacity = size / stride + 64
            var table = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var used = capacity * stride
            let result = table.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &used, nil, 0) }
            if result == 0 {
                table.removeLast(capacity - min(capacity, used / stride))
                return table.isEmpty ? nil : table
            }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    private static func readUsage(of pid: Int32, flavor: Int32, into info: inout rusage_info_v6) -> Bool {
        withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, flavor, $0) }
        } == 0
    }

    private static func resourceUsage(of pid: Int32) -> ResourceUsage? {
        var info = rusage_info_v6()
        let flavor = rusageFlavor
        guard readUsage(of: pid, flavor: flavor, into: &info) else { return nil }
        return ResourceUsage(
            cpuTime: ProcessCensus.seconds(machTicks: info.ri_user_time &+ info.ri_system_time, numer: timebase.numer, denom: timebase.denom),
            energyNanojoules: flavor >= RUSAGE_INFO_V6 ? info.ri_energy_nj : nil,
            instructions: info.ri_instructions,
            logicalWriteBytes: info.ri_logical_writes,
            wakeups: info.ri_pkg_idle_wkups &+ info.ri_interrupt_wkups
        )
    }

    private static func executablePath(of pid: Int32, buffer: inout [CChar]) -> String? {
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Nil when the arguments cannot be read.
    private static func arguments(of pid: Int32, buffer: inout [UInt8]) -> ProcessCensus.ProcessArguments? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buffer.count
        let result = buffer.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }
        guard result == 0, size > 0 else { return nil }
        return buffer.withUnsafeBytes {
            ProcessCensus.parseArguments(procargs2: UnsafeRawBufferPointer(rebasing: $0[..<min(size, $0.count)]))
        }
    }
}
