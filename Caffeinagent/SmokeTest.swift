import AppKit
import Combine
import SwiftUI

/// `caffeinagent --smoke-test <seconds>`: the real app starts, with its
/// scenes, its aggregator and the engine that reads this Mac, measures
/// itself, prints one line of JSON and leaves with 0 when it is healthy.
/// `scripts/smoke-test.sh` runs it, and no release is made without it: the
/// unit tests never start the app, so they pass on a build that hangs.
///
/// It runs next to a copy that is installed and touches nothing of it. It
/// takes no power assertion, registers no keyboard shortcut, takes no click, leaves the displays alone, never reaches or registers the helper, reads
/// no license from the Keychain and never calls Polar, starts no Sparkle,
/// shows no setup window and no offer to move, sends no notification, and
/// keeps its settings, and those AppKit writes for it, under a bundle
/// identifier of its own that it removes at the end.
enum SmokeTest {
    private(set) static var isActive = false
    /// The parts of the aggregator for this run. Nil in the app.
    @MainActor private(set) static var parts: AggregatorParts?

    static let label = "agent caffeine smoke test"
    private static let domain = "com.caffeinagent.app.smoke-test"
    private static let settingsWindowID = "com_apple_SwiftUI_Settings_window"

    private static let meter = Meter()
    private static var seconds: TimeInterval = 0
    private static var timers: [Timer] = []
    private static var cancellable: AnyCancellable?
    private static var clickMonitor: Any?
    private static var iconToggle = SmokeMeasurements.Step.notRun
    private static var settingsWindow = SmokeMeasurements.Step.notRun

    /// Called before the app starts.
    @MainActor
    static func prepare(seconds: TimeInterval) {
        isActive = true
        self.seconds = seconds
        let defaults = ownSettings()
        parts = AggregatorParts(
            defaults: defaults,
            license: LicenseManager(client: NoLicenseAPI(), store: MemoryStore(), defaults: defaults),
            sleepFlag: SleepFlagController(service: NoHelperService(), helper: NoHelper(), sudoers: NoSudoers(), defaults: defaults),
            power: NoPower(),
            hotKeys: NoHotKeys(),
            display: nil,
            notify: { _ in },
            notifier: nil
        )
        meter.start()
        every(SmokeHealth.tickInterval) { meter.tick() }
        after(seconds) { finish() }
        startWatchdog()
    }

    /// Gives the process a bundle identifier of its own before anything
    /// reads the settings, and returns the settings that go with it.
    /// AppKit keeps the place and the visibility of the status item and
    /// the frame of Preferences under the bundle identifier, so with the
    /// real one the test would change them for the copy that is installed.
    /// The run ends before the app starts when the settings are still the
    /// real ones, and nothing was written to them.
    private static func ownSettings() -> UserDefaults {
        let probe = "SmokeTest.ownSettings"
        if let info = CFBundleGetInfoDictionary(CFBundleGetMainBundle()) {
            CFDictionarySetValue(
                unsafeDowncast(info, to: CFMutableDictionary.self),
                Unmanaged.passUnretained(kCFBundleIdentifierKey).toOpaque(),
                Unmanaged.passUnretained(domain as CFString).toOpaque()
            )
        }
        CFPreferencesSetAppValue(probe as CFString, kCFBooleanTrue, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        guard Bundle.main.bundleIdentifier == domain, UserDefaults.standard.bool(forKey: probe) else {
            CFPreferencesSetAppValue(probe as CFString, nil, domain as CFString)
            CFPreferencesAppSynchronize(domain as CFString)
            FileHandle.standardError.write(Data("agent caffeine smoke test: could not get settings of its own, so it did not run.\n".utf8))
            exit(4)
        }
        // Also what a run that was cut left behind.
        UserDefaults.standard.removePersistentDomain(forName: domain)
        return .standard
    }

    /// Called for every time SwiftUI works out the scenes.
    static func countSceneEvaluation() {
        if isActive { meter.countSceneEvaluation() }
    }

    @MainActor
    static func appDidLaunch() {
        cancellable = StateAggregator.shared.objectWillChange.sink { meter.countPublish() }
        statusButton()?.toolTip = label
        ignoreClicks()
        after(SmokeHealth.iconToggleAt) { hideIcon() }
        after(SmokeHealth.settingsWindowAt) { openSettings() }
    }

    /// A click on the icon opens the menu, and the robot in an open menu
    /// moves: that takes a quarter of a core for as long as the menu is
    /// open, and the run would be judged by it. So no click reaches the
    /// app, whoever clicks while it runs.
    private static func ignoreClicks() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { event in
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { meter.countIgnoredClick() }
            return nil
        }
    }

    // MARK: Steps

    /// Through the binding the menu bar scene has, as the switch in
    /// Preferences does it. Skipped when this macOS does not give the
    /// status item of the scene.
    @MainActor
    private static func hideIcon() {
        let inserted = CaffeinagentApp.menuBarIconInserted(.shared)
        guard let item = statusItem() else {
            iconToggle = .skipped
            return
        }
        guard item.isVisible else {
            iconToggle = .failed
            return
        }
        meter.markStep()
        inserted.wrappedValue = false
        after(0.6) {
            meter.markStep()
            let hidden = !item.isVisible
            inserted.wrappedValue = true
            after(0.6) {
                meter.markStep()
                iconToggle = hidden && item.isVisible ? .ok : .failed
            }
        }
    }

    /// The window opens behind the app in front and takes no focus. Before
    /// macOS 14 only the responder chain opens it, which needs the app to
    /// be active.
    @MainActor
    private static func openSettings() {
        guard #available(macOS 14.0, *) else {
            settingsWindow = .skipped
            return
        }
        meter.markStep()
        SettingsAction.open()
        after(0.8) {
            meter.markStep()
            let window = NSApp.windows.first { $0.identifier?.rawValue == settingsWindowID }
            settingsWindow = window?.isVisible == true ? .ok : .failed
            window?.close()
        }
    }

    private static var statusWindows: [NSWindow] {
        NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
    }

    /// The button of the menu bar scene's status item, in its own window.
    @MainActor
    private static func statusButton() -> NSStatusBarButton? {
        statusWindows.lazy.compactMap { firstButton(in: $0.contentView) }.first
    }

    /// The status item itself, which AppKit gives only through its window.
    @MainActor
    private static func statusItem() -> NSStatusItem? {
        statusWindows.lazy
            .filter { $0.responds(to: NSSelectorFromString("statusItem")) }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
            .first
    }

    private static func firstButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(firstButton).first
    }

    /// True when the button has an image with something drawn in it.
    @MainActor
    private static func hasImage(_ button: NSStatusBarButton) -> Bool {
        guard let image = button.image, image.size.width > 0, image.size.height > 0,
              button.frame.width > 0, button.frame.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let width = cgImage.width, height = cgImage.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &alpha, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return alpha.contains { $0 > 0 }
    }

    // MARK: End

    @MainActor
    private static func finish() -> Never {
        var m = meter.measurements()
        let button = statusButton()
        m.statusItem = button != nil
        m.statusItemImage = button.map(hasImage) ?? false
        m.samples = StateAggregator.shared.samples
        m.iconToggle = iconToggle
        m.settingsWindow = settingsWindow
        StateAggregator.shared.shutdown()
        UserDefaults.standard.removePersistentDomain(forName: domain)
        print(SmokeHealth.line(m))
        fflush(stdout)
        exit(SmokeHealth.failures(m).isEmpty ? 0 : 1)
    }

    /// Off the main thread: a main thread that hangs never comes to
    /// `finish`, and the test itself must not hang.
    private static func startWatchdog() {
        let limit = SmokeHealth.hangSeconds
        let thread = Thread {
            while true {
                Thread.sleep(forTimeInterval: 0.05)
                meter.readCPU()
                guard meter.silence() > limit else { continue }
                let line = SmokeHealth.line(
                    meter.measurements(), hang: "main thread gave no sign for more than \(Int(limit)) s, the run was cut"
                )
                print(line)
                fflush(stdout)
                FileHandle.standardError.write(Data("agent caffeine smoke test: the main thread hangs.\n".utf8))
                _exit(3)
            }
        }
        thread.name = "smoke test watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    // MARK: Timers

    private static func every(_ interval: TimeInterval, _ work: @escaping () -> Void) {
        schedule(Timer(timeInterval: interval, repeats: true) { _ in work() })
    }

    private static func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        schedule(Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated(work) })
    }

    /// In the common modes, so an open menu or window holds no timer up.
    private static func schedule(_ timer: Timer) {
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }
}

/// The numbers the main thread writes and the watchdog reads.
private final class Meter: @unchecked Sendable {
    private let lock = NSLock()
    private var began: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var ticks = 0
    private var longestStall: TimeInterval = 0
    private var sceneEvaluations = 0
    private var publishes = 0
    private var cpuBySecond: [Double] = []
    private var secondBegan: TimeInterval = 0
    private var cpuAtSecondBegan: TimeInterval = 0
    private var stepSeconds: Set<Int> = []
    private var clicksIgnored = 0

    /// Processor time of the process so far, in seconds.
    private static var cpu: TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        lock.lock()
        began = Self.uptime
        lastTick = began
        secondBegan = began
        cpuAtSecondBegan = Self.cpu
        lock.unlock()
    }

    /// Called many times per second, off the main thread: closes each
    /// second of the run that is over with the processor time it took.
    func readCPU() {
        let now = Self.uptime, cpu = Self.cpu
        lock.lock()
        defer { lock.unlock() }
        guard now - secondBegan >= 1 else { return }
        closeSecond(now: now, cpu: cpu)
    }

    /// The reading is a little late, so the second is a little long.
    private func closeSecond(now: TimeInterval, cpu: TimeInterval) {
        cpuBySecond.append(((cpu - cpuAtSecondBegan) / (now - secondBegan) * 1000).rounded() / 10)
        secondBegan = now
        cpuAtSecondBegan = cpu
    }

    /// The test itself works in this second of the run.
    func markStep() {
        lock.lock()
        stepSeconds.insert(cpuBySecond.count)
        lock.unlock()
    }

    func tick() {
        let now = Self.uptime
        lock.lock()
        ticks += 1
        // The first second is the start of the app.
        if lastTick - began >= 1 { longestStall = max(longestStall, now - lastTick) }
        lastTick = now
        lock.unlock()
    }

    func countSceneEvaluation() {
        lock.lock()
        sceneEvaluations += 1
        lock.unlock()
    }

    func countPublish() {
        lock.lock()
        publishes += 1
        lock.unlock()
    }

    func countIgnoredClick() {
        lock.lock()
        clicksIgnored += 1
        lock.unlock()
    }

    /// Seconds since the last tick.
    func silence() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Self.uptime - lastTick
    }

    func measurements() -> SmokeMeasurements {
        let cpu = Self.cpu
        let now = Self.uptime
        lock.lock()
        defer { lock.unlock() }
        let seconds = now - began
        // The run ends in the middle of the reading that would close its last second.
        if now - secondBegan >= 0.5 { closeSecond(now: now, cpu: cpu) }
        // A stall that still goes on counts with what it has so far.
        let stall = max(longestStall, lastTick - began >= 1 || now - began >= 1 ? now - lastTick : 0)
        return SmokeMeasurements(
            seconds: (seconds * 10).rounded() / 10,
            ticks: ticks,
            longestStallMs: Int(stall * 1000),
            cpuPercent: seconds > 0 ? (cpu / seconds * 1000).rounded() / 10 : 0,
            cpuBySecond: cpuBySecond,
            stepSeconds: stepSeconds.sorted(),
            clicksIgnored: clicksIgnored,
            sceneEvaluations: sceneEvaluations,
            publishes: publishes
        )
    }
}

// MARK: Parts that do nothing

private struct NoLicenseAPI: LicenseAPI {
    func activate(key: String, label: String) async -> LicenseActivation { .unavailable }
    func validate(key: String, activationID: String) async -> LicenseValidation { .unavailable }
    func deactivate(key: String, activationID: String) async -> LicenseDeactivation { .unavailable }
}

/// Starts empty, so the run is the first day of a trial.
private final class MemoryStore: LicenseStore {
    private var record: LicenseRecord?

    func load() throws -> LicenseRecord? { record }
    func save(_ record: LicenseRecord) throws { self.record = record }
}

private struct NoHelperService: HelperServiceManaging {
    var status: HelperStatus { .notRegistered }
    func register() throws {}
    func unregister() async throws {}
    func openLoginItemsSettings() {}
}

private struct NoHelper: SleepFlagHelperConnecting {
    func onConnectionLost(_ handler: @escaping () -> Void) {}
    func reconnect() {}
    func setSleepDisabled(_ on: Bool) async throws -> Bool { throw HelperCallError.connectionLost }
    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String) { throw HelperCallError.connectionLost }
    func heartbeat() async throws -> Bool { throw HelperCallError.connectionLost }
}

private struct NoSudoers: SudoersCleaning {
    var entryExists: Bool { false }
    func remove() async throws {}
}

@MainActor
private final class NoHotKeys: HotKeyRegistering {
    var systemShortcuts: Set<Shortcut.Keys> { [] }
    func register(_ shortcut: Shortcut?, for action: ShortcutAction, onPress: @escaping () -> Void) -> Bool { true }
    func unregisterAll() {}
}

/// Remembers what was asked, and holds nothing.
@MainActor
private final class NoPower: PowerHolding {
    private(set) var held = false

    func hold(reason: String) { held = true }
    func release() { held = false }
}
