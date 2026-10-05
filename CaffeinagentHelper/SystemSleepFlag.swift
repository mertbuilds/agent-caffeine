import Foundation
import IOKit
import os

// The kernel's SleepDisabled flag, the one `pmset disablesleep` sets. It is
// system wide, survives reboot, and also blocks low-battery and thermal sleep.
struct SystemSleepFlag: SleepFlagAccessing {
    private static let key = "SleepDisabled"
    private static let attempts = 20
    private static let attemptDelay: TimeInterval = 0.1
    private let log = Logger(subsystem: SleepFlagHelper.label, category: "SystemSleepFlag")

    // IOPMSetSystemPowerSetting is what pmset itself calls. It is not in the
    // public headers, so it is looked up at run time and pmset is the fallback.
    private typealias SetSystemPowerSetting = @convention(c) (CFString, CFTypeRef) -> IOReturn
    private static let setSystemPowerSetting: SetSystemPowerSetting? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "IOPMSetSystemPowerSetting") else { return nil }
        return unsafeBitCast(symbol, to: SetSystemPowerSetting.self)
    }()

    func read() -> Bool? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        let value = IORegistryEntryCreateCFProperty(entry, Self.key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return value as? Bool
    }

    // The write only stores a preference and notifies powerd, which sets the
    // kernel flag a moment later, so the kernel value is polled and the write
    // repeated until it matches.
    func set(_ on: Bool) -> Bool {
        if read() == on { return on }
        for attempt in 0..<Self.attempts {
            if attempt % 5 == 0 { write(on) }
            Thread.sleep(forTimeInterval: Self.attemptDelay)
            if read() == on { return on }
        }
        log.error("SleepDisabled did not become \(on)")
        return !on
    }

    private func write(_ on: Bool) {
        if let setSystemPowerSetting = Self.setSystemPowerSetting {
            let value: CFBoolean = on ? kCFBooleanTrue : kCFBooleanFalse
            let result = setSystemPowerSetting(Self.key as CFString, value)
            if result == kIOReturnSuccess { return }
            log.error("IOPMSetSystemPowerSetting failed: \(result)")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-a", "disablesleep", on ? "1" : "0"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                log.error("pmset exited with \(task.terminationStatus)")
            }
        } catch {
            log.error("pmset did not run: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// Says "the helper set SleepDisabled" across a helper restart and a reboot.
// The directory is created by root, so no other user can plant or remove it.
struct MarkerFile: MarkerStoring {
    private static let directory = "/Library/Application Support/\(SleepFlagHelper.appBundleID)"
    private static let path = directory + "/sleep-flag-set"

    var exists: Bool { FileManager.default.fileExists(atPath: Self.path) }

    func write() -> Bool {
        do {
            try FileManager.default.createDirectory(
                atPath: Self.directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        } catch {
            return false
        }
        return FileManager.default.createFile(atPath: Self.path, contents: nil, attributes: [.posixPermissions: 0o644])
    }

    // Takes the directory too, so nothing is left behind after an uninstall.
    func remove() {
        try? FileManager.default.removeItem(atPath: Self.path)
        rmdir(Self.directory)
    }
}
