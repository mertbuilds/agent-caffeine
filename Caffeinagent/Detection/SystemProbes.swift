import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// Which processes ask the Mac to stay awake right now.
protocol PowerAssertionListing {
    /// The pids that hold an assertion against sleep. Empty when the list
    /// cannot be read.
    func assertingPIDs() -> Set<Int32>
}

/// Battery, lid and heat. `remoteAccessDetected` is not filled here.
protocol PowerContextReading {
    func context() -> FrameContext
}

/// The sleep timer of macOS, as System Settings and `pmset -g` show it.
protocol SleepTimerReading: Sendable {
    /// Minutes without input until the Mac sleeps on this power source. 0
    /// is never. Nil when it cannot be read.
    func sleepTimerMinutes(onBattery: Bool) -> Int?
}

/// What a process of the same user has open.
protocol OpenFileListing {
    /// The paths of the files a process has open, nil when the list cannot
    /// be read (the process is gone, or belongs to another user).
    func openFilePaths(of pid: Int32) -> [String]?
    func workingDirectory(of pid: Int32) -> String?
}

/// `IOPMCopyAssertionsByProcess`, about 0.06 ms per call on the test Mac.
struct SystemPowerAssertions: PowerAssertionListing {
    /// The types that stop idle sleep. A display assertion stops it too.
    static let sleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion",
        "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion",
    ]

    func assertingPIDs() -> Set<Int32> {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess,
              let byProcess = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var pids: Set<Int32> = []
        for (pid, assertions) in byProcess {
            let holds = assertions.contains { ($0[kIOPMAssertionTypeKey] as? String).map(Self.sleepTypes.contains) ?? false }
            if holds { pids.insert(pid.int32Value) }
        }
        return pids
    }
}

/// `IOPMCopyActivePMPreferences`, which reads and needs no permission. It
/// asks powerd and took about 13 ms on the test Mac, so the caller keeps
/// it off the main thread. IOKit has it and its header does not, so it is
/// looked up by name: a macOS without it gives nil.
struct SystemSleepTimer: SleepTimerReading {
    private typealias Copy = @convention(c) () -> Unmanaged<CFDictionary>?
    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let copy = handle.flatMap { dlsym($0, "IOPMCopyActivePMPreferences") }.map { unsafeBitCast($0, to: Copy.self) }

    func sleepTimerMinutes(onBattery: Bool) -> Int? {
        guard let preferences = Self.copy?()?.takeRetainedValue() as? [String: Any] else { return nil }
        return Self.sleepTimerMinutes(in: preferences, onBattery: onBattery)
    }

    /// One dictionary per power source. A Mac without a battery has "AC
    /// Power" only. "Display Sleep Timer" is not read: a dark display is
    /// not a sleeping Mac.
    static func sleepTimerMinutes(in preferences: [String: Any], onBattery: Bool) -> Int? {
        let source = preferences[onBattery ? "Battery Power" : "AC Power"] as? [String: Any]
        return (source?["System Sleep Timer"] as? NSNumber)?.intValue
    }
}

/// Power source and battery level from IOPS (about 0.03 ms), the lid from
/// `AppleClamshellState` on IOPMrootDomain (about 3 microseconds).
final class SystemPowerContext: PowerContextReading {
    private let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))

    deinit {
        if rootDomain != 0 { IOObjectRelease(rootDomain) }
    }

    func context() -> FrameContext {
        let battery = Self.battery()
        return FrameContext(
            onBattery: battery.onBattery,
            batteryPercent: battery.percent,
            lidClosed: lidClosed(),
            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            charging: battery.charging
        )
    }

    /// False on a Mac without a lid, where the property is missing.
    private func lidClosed() -> Bool {
        guard rootDomain != 0,
              let value = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return false }
        return value as? Bool ?? false
    }

    private static func battery() -> (onBattery: Bool, percent: Int?, charging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return (false, nil, false) }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTransportTypeKey] as? String == kIOPSInternalType else { continue }
            let onBattery = info[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            var percent: Int?
            if let current = info[kIOPSCurrentCapacityKey] as? Int, let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 {
                percent = current * 100 / max
            }
            return (onBattery, percent, info[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return (false, nil, false)
    }
}

/// `proc_pidinfo` and `proc_pidfdinfo`, about 0.05 ms for a process with
/// 100 descriptors. Same-user processes only.
struct SystemOpenFiles: OpenFileListing {
    func openFilePaths(of pid: Int32) -> [String]? {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return nil }
        // Slack for descriptors opened between the two calls.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 32)
        let used = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return nil }
        var paths: [String] = []
        var info = vnode_fdinfowithpath()
        let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        for descriptor in descriptors.prefix(Int(used) / stride) where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { continue }
            let path = Self.string(from: &info.pvip.vip_path)
            if !path.isEmpty { paths.append(path) }
        }
        return paths
    }

    func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = Self.string(from: &info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// The kernel fills a fixed `MAXPATHLEN` buffer and ends the path with NUL.
    private static func string<Buffer>(from buffer: inout Buffer) -> String {
        withUnsafeBytes(of: &buffer) { bytes in
            let end = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[..<end]), as: UTF8.self)
        }
    }
}
