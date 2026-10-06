import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.graphics
import IOKit.ps
import ObjectiveC
import os

/// The built-in display of this Mac. macOS can take it off the list of
/// displays while the lid is closed, so the last id that was seen is kept.
enum BuiltinDisplay {
    private static var lastSeen: CGDirectDisplayID?

    static func online() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func id(among online: [CGDirectDisplayID] = online()) -> CGDirectDisplayID? {
        if let id = online.first(where: { CGDisplayIsBuiltin($0) != 0 }) { lastSeen = id }
        return lastSeen
    }
}

struct SystemDisplayReader: DisplayReading {
    func read() -> DisplayInputs {
        let online = BuiltinDisplay.online()
        let builtin = online.first { CGDisplayIsBuiltin($0) != 0 }
        _ = BuiltinDisplay.id(among: online)
        // `kCGAnyInputEventType`.
        let idle = CGEventType(rawValue: ~0).map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
        return DisplayInputs(
            externalDisplay: online.contains { CGDisplayIsBuiltin($0) == 0 },
            builtinOnline: builtin != nil,
            builtinAsleep: builtin.map { CGDisplayIsAsleep($0) != 0 } ?? false,
            idle: idle
        )
    }
}

/// Display sleep without a privilege: the request `pmset displaysleepnow`
/// makes, and that command itself when the request is refused.
struct SystemDisplaySleep: DisplaySleeping {
    private static let log = Logger(subsystem: "com.caffeinagent.app", category: "Display")

    func sleepDisplays() -> Bool {
        let wrangler = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
        if wrangler != 0 {
            defer { IOObjectRelease(wrangler) }
            let result = IORegistryEntrySetCFProperty(wrangler, "IORequestIdle" as CFString, kCFBooleanTrue)
            if result == KERN_SUCCESS { return true }
            Self.log.error("IORequestIdle failed: \(result)")
        }
        return Self.pmset()
    }

    /// Not waited for. One that hangs is ended after 5 seconds.
    private static func pmset() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("pmset displaysleepnow did not start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }
        return true
    }
}

// MARK: Brightness

/// `DisplayServices`, the private framework the brightness keys use. The
/// way that works on Apple silicon.
struct DisplayServicesBrightness: BuiltinBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let get = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let set = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    let name = "DisplayServices"

    func level() -> Float? {
        guard let get = Self.get, let id = BuiltinDisplay.id() else { return nil }
        var level: Float = 0
        guard get(id, &level) == 0, level.isFinite else { return nil }
        return level
    }

    func set(_ level: Float) -> Bool {
        guard let set = Self.set, let id = BuiltinDisplay.id() else { return false }
        return set(id, level) == 0
    }
}

/// The public call of IOKit. It finds a display on an Intel Mac. An Apple
/// silicon Mac has no `IODisplayConnect` service, so there it does nothing.
struct IODisplayBrightness: BuiltinBrightness {
    let name = "IODisplay"

    func level() -> Float? {
        withService { service in
            var level: Float = 0
            return IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess ? level : nil
        }
    }

    func set(_ level: Float) -> Bool {
        withService { IODisplaySetFloatParameter($0, 0, kIODisplayBrightnessKey as CFString, level) == kIOReturnSuccess ? true : nil } ?? false
    }

    /// The first display that has a brightness: the built-in one.
    private func withService<T>(_ work: (io_service_t) -> T?) -> T? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var level: Float = 0
            guard IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess else { continue }
            return work(service)
        }
        return nil
    }
}

/// `CoreDisplay`, the older private way. The last one to try.
struct CoreDisplayBrightness: BuiltinBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID) -> Double
    private typealias Set = @convention(c) (CGDirectDisplayID, Double) -> Void

    private static let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    private static let get = handle.flatMap { dlsym($0, "CoreDisplay_Display_GetUserBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let set = handle.flatMap { dlsym($0, "CoreDisplay_Display_SetUserBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    let name = "CoreDisplay"

    func level() -> Float? {
        guard let get = Self.get, let id = BuiltinDisplay.id() else { return nil }
        let level = get(id)
        return level.isFinite ? Float(level) : nil
    }

    func set(_ level: Float) -> Bool {
        guard let set = Self.set, let id = BuiltinDisplay.id() else { return false }
        set(id, Double(level))
        return true
    }
}

extension BuiltinDimmer {
    /// In the order they are tried.
    static let systemMethods: [BuiltinBrightness] = [DisplayServicesBrightness(), IODisplayBrightness(), CoreDisplayBrightness()]
}

// MARK: Watch

/// The lid, from the power root domain, and the list of displays, from
/// Core Graphics. Both call on the main thread.
final class SystemDisplayWatcher: DisplayWatching {
    /// `kIOPMMessageClamshellStateChange`, a macro Swift does not import:
    /// `iokit_family_msg(sub_iokit_powermanagement, 0x100)`.
    static let clamshellStateChange: UInt32 = 0xE034_0100

    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var onChange: (() -> Void)?
    private var watchesDisplays = false

    deinit {
        stop()
    }

    func start(onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if root != 0, let port = IONotificationPortCreate(kIOMainPortDefault) {
            IONotificationPortSetDispatchQueue(port, .main)
            let result = IOServiceAddInterestNotification(port, root, "IOGeneralInterest", { context, _, type, _ in
                guard type == SystemDisplayWatcher.clamshellStateChange, let context else { return }
                Unmanaged<SystemDisplayWatcher>.fromOpaque(context).takeUnretainedValue().onChange?()
            }, context, &notifier)
            if result == KERN_SUCCESS {
                self.port = port
            } else {
                IONotificationPortDestroy(port)
            }
        }
        if root != 0 { IOObjectRelease(root) }
        watchesDisplays = CGDisplayRegisterReconfigurationCallback(Self.displaysChanged, context) == .success
    }

    func stop() {
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
        if watchesDisplays {
            CGDisplayRemoveReconfigurationCallback(Self.displaysChanged, Unmanaged.passUnretained(self).toOpaque())
            watchesDisplays = false
        }
        onChange = nil
    }

    private static let displaysChanged: CGDisplayReconfigurationCallBack = { _, flags, context in
        guard !flags.contains(.beginConfigurationFlag), let context else { return }
        Unmanaged<SystemDisplayWatcher>.fromOpaque(context).takeUnretainedValue().onChange?()
    }
}

// MARK: Probe

/// `caffeinagent --display-probe <seconds>`: prints once per second what
/// the lid and the displays do, for a test by hand with the lid closed. It
/// only reads. It starts no app, takes no hold, and sets nothing.
enum DisplayProbe {
    private typealias KeyboardFloat = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KeyboardBool = @convention(c) (AnyObject, Selector, UInt64) -> Bool

    static func run(seconds: TimeInterval) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm:ss"
        let methods = BuiltinDimmer.systemMethods
        let keyboard = Keyboard()
        print((["time", "lidClosed", "sleepDisabled", "power", "displays"] + methods.map { "brightness\($0.name)" }
            + ["backlightMicroAmps", "keyboardBrightness", "keyboardLevel", "keyboardSuppressed", "idleSeconds", "event"]).joined(separator: "\t"))
        let end = Date().addingTimeInterval(seconds)
        var wasAwake: [CGDirectDisplayID: Bool] = [:]
        while Date() < end {
            let root = properties("IOPMrootDomain")
            let online = BuiltinDisplay.online()
            _ = BuiltinDisplay.id(among: online)
            var events: [String] = []
            var displays: [String] = []
            for id in online {
                let builtin = CGDisplayIsBuiltin(id) != 0
                let awake = CGDisplayIsAsleep(id) == 0
                displays.append("\(builtin ? "builtin" : "external")#\(id):\(awake ? "awake" : "asleep")")
                if let before = wasAwake[id], before != awake { events.append("\(builtin ? "builtin" : "external") \(awake ? "woke" : "slept")") }
                if wasAwake[id] == nil, !wasAwake.isEmpty { events.append("\(builtin ? "builtin" : "external") came online") }
            }
            for id in wasAwake.keys where !online.contains(id) { events.append("display #\(id) went offline") }
            wasAwake = Dictionary(uniqueKeysWithValues: online.map { ($0, CGDisplayIsAsleep($0) == 0) })
            let backlight = (properties("AppleARMBacklight")?["IODisplayParameters"] as? [String: Any])?["BrightnessMicroAmps"] as? [String: Any]
            let idle = CGEventType(rawValue: ~0).map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            var row = [clock.string(from: Date()), text(root?["AppleClamshellState"]), text(root?["SleepDisabled"]), power()]
            row.append(displays.isEmpty ? "none" : displays.joined(separator: ","))
            row += methods.map { $0.level().map { String(format: "%.3f", $0) } ?? "-" }
            row += [text(backlight?["value"]), keyboard.float("brightnessForKeyboard:"), keyboard.float("backlightLevelForKeyboard:"), keyboard.bool("isBacklightSuppressedOnKeyboard:")]
            row += [idle.map { String(format: "%.0f", $0) } ?? "-", events.joined(separator: "; ")]
            print(row.joined(separator: "\t"))
            Thread.sleep(forTimeInterval: 1)
        }
        exit(0)
    }

    private static func text(_ value: Any?) -> String {
        switch value {
        case let flag as Bool: return flag ? "yes" : "no"
        case let value?: return "\(value)"
        case nil: return "-"
        }
    }

    private static func properties(_ className: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var out: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &out, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return out?.takeRetainedValue() as? [String: Any]
    }

    private static func power() -> String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else { return "-" }
        return type == kIOPSBatteryPowerValue ? "battery" : "power adapter"
    }

    /// The keyboard backlight, read through CoreBrightness. Every step is
    /// checked, and a method with another shape than the one that was seen
    /// on macOS 26 is not called.
    private struct Keyboard {
        private let client: NSObject?
        private let id: UInt64?

        init() {
            _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
            guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
                client = nil
                id = nil
                return
            }
            let client = type.init()
            self.client = client
            let list = NSSelectorFromString("copyKeyboardBacklightIDs")
            let ids = client.responds(to: list) ? client.perform(list)?.takeRetainedValue() as? [NSNumber] : nil
            id = ids?.first?.uint64Value
        }

        func float(_ name: String) -> String {
            guard let implementation = implementation(name, encoding: "f24@0:8Q16"), let client, let id else { return "-" }
            return String(format: "%.3f", unsafeBitCast(implementation, to: KeyboardFloat.self)(client, NSSelectorFromString(name), id))
        }

        func bool(_ name: String) -> String {
            guard let implementation = implementation(name, encoding: "B24@0:8Q16"), let client, let id else { return "-" }
            return unsafeBitCast(implementation, to: KeyboardBool.self)(client, NSSelectorFromString(name), id) ? "yes" : "no"
        }

        private func implementation(_ name: String, encoding: String) -> IMP? {
            guard let client, let method = class_getInstanceMethod(type(of: client), NSSelectorFromString(name)),
                  let types = method_getTypeEncoding(method), String(cString: types) == encoding else { return nil }
            return method_getImplementation(method)
        }
    }
}
