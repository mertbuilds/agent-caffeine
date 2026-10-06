import AppKit
import Combine
import os

/// What the aggregator reaches the Mac through. The app passes the real
/// parts. The smoke test passes parts that do nothing, so it can start
/// the app next to a copy that is installed (see `SmokeTest`).
@MainActor
struct AggregatorParts {
    var defaults: UserDefaults
    var license: LicenseManager
    var sleepFlag: SleepFlagController
    var power: PowerHolding
    var notify: (String) -> Void

    static func system() -> AggregatorParts {
        AggregatorParts(
            defaults: .standard,
            license: LicenseManager(client: LicenseClient(), store: KeychainLicenseStore()),
            sleepFlag: SleepFlagController(),
            power: PowerKeeper(),
            notify: SafetyNotifier.post
        )
    }
}

/// Joins the detection engine to what it drives: the power assertions, the
/// root helper's sleep flag, the notification of a safety stop, and the
/// state the menu and Preferences show.
@MainActor
final class StateAggregator: ObservableObject {
    // Every property is published only when it changes: a sample that
    // changes nothing must not make SwiftUI work out the scenes and the
    // menu bar label again.
    /// One for the app: the scenes and the setup window share it.
    static let shared = StateAggregator(parts: SmokeTest.parts ?? .system())

    @PublishedOnChange var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: Self.enabledKey)
            engine.enabled = enabled
        }
    }
    @PublishedOnChange var mode: AwakeMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            engine.mode = mode
        }
    }
    @PublishedOnChange var settings: DetectionSettings {
        didSet {
            guard settings != oldValue else { return }
            DetectionSettingsStore.save(settings, to: defaults)
            safetyMonitor.batteryFloorPercent = settings.batteryFloorPercent
            engine.settings = settings
        }
    }
    /// The robot in the menu bar. Hiding it changes nothing else. The
    /// menu bar scene writes this back all the time, so a write of the
    /// same value must publish nothing and save nothing.
    @PublishedOnChange var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            MenuBarVisibility.set(showMenuBarIcon, in: defaults)
        }
    }
    /// The tab Preferences shows, so the menu can open one.
    @PublishedOnChange var preferencesTab = PreferencesTab.general
    @PublishedOnChange private(set) var decision: HoldDecision
    /// The folder of each session that works or waits, for the menu.
    @PublishedOnChange private(set) var sessionLabels: [ProcessIdentity: String] = [:]
    /// What tells sessions with the same name and folder apart, for the
    /// menu. It is shown only, never logged.
    @PublishedOnChange private(set) var sessionHints: [ProcessIdentity: SessionHint] = [:]
    /// Since when each agent is in its state, for the menu.
    @PublishedOnChange private(set) var stateClock = StateClock()
    /// The user closed the menu's hint to set up "lid closed on battery".
    @PublishedOnChange var lidClosedHintDismissed: Bool {
        didSet {
            guard lidClosedHintDismissed != oldValue else { return }
            defaults.set(lidClosedHintDismissed, forKey: Self.lidClosedHintKey)
        }
    }
    @PublishedOnChange private(set) var entitlement: Entitlement
    /// False on a Mac without a battery, where a closed lid needs no helper.
    @PublishedOnChange private(set) var hasBattery = true
    @PublishedOnChange private(set) var helperError: String?
    /// By hook agent id. Read at launch and when Preferences opens, and
    /// never changed without the user's word.
    @PublishedOnChange private(set) var hookStatuses: [String: HookStatus] = [:]
    @PublishedOnChange private(set) var hookErrors: [String: String] = [:]

    let license: LicenseManager
    let sleepFlag: SleepFlagController
    let canSetUpHelper = AppRelocator.isInSystemApplications
    private let hookInstaller = HookInstaller()
    private let engine: DetectionEngine
    /// How many samples the engine gave. For the smoke test.
    private(set) var samples = 0
    private let defaults: UserDefaults
    private let power: PowerHolding
    private let notify: (String) -> Void
    private let openFiles = SystemOpenFiles()
    private var safetyMonitor = SafetyMonitor()
    private var flagRequest = SleepFlagRequest()
    private var hiddenNotice: HiddenNotice?
    private var lastHelperRefresh = Date.distantPast
    private var napActivity: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var sigtermSource: DispatchSourceSignal?
    private static let enabledKey = "StateAggregator.enabled"
    private static let modeKey = "StateAggregator.mode"
    private static let lidClosedHintKey = "StateAggregator.lidClosedHintDismissed"
    /// System Settings tells nobody when the user allows or removes the
    /// helper, so its state is read again this often.
    private static let helperRefreshInterval: TimeInterval = 30

    init(parts: AggregatorParts) {
        let license = parts.license
        let defaults = parts.defaults
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let mode = defaults.string(forKey: Self.modeKey).flatMap(AwakeMode.init(rawValue:)) ?? .agentWorking
        let settings = DetectionSettingsStore.load(from: defaults)
        LegacyBatteryOverride.clearLeftover(defaults: defaults)
        let engine = DetectionEngine.system(mode: mode, enabled: enabled, entitlement: license.entitlement, settings: settings)
        self.license = license
        self.sleepFlag = parts.sleepFlag
        self.defaults = defaults
        self.power = parts.power
        self.notify = parts.notify
        self.engine = engine
        self.entitlement = license.entitlement
        self.enabled = enabled
        self.mode = mode
        self.settings = settings
        self.lidClosedHintDismissed = defaults.bool(forKey: Self.lidClosedHintKey)
        self.showMenuBarIcon = MenuBarVisibility.isShown(in: defaults)
        self.decision = engine.decision
        safetyMonitor.batteryFloorPercent = settings.batteryFloorPercent

        engine.$decision
            .dropFirst()
            .sink { [weak self] decision in self?.apply(decision) }
            .store(in: &cancellables)
        engine.onSample = { [weak self] sample in self?.sampled(sample) }

        // An expired trial goes through the same release path as switching off,
        // so the assertions and the sleep flag both end.
        license.$entitlement
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entitlement in
                self?.entitlement = entitlement
                self?.engine.entitlement = entitlement
            }
            .store(in: &cancellables)

        // The menu and Preferences read the license and the helper's state
        // through this object.
        license.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sleepFlag.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.shutdown() }
            .store(in: &cancellables)

        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { [weak self] in
            self?.shutdown()
            exit(0)
        }
        sigterm.resume()
        sigtermSource = sigterm

        // A menu bar app with no window and no assertion is what App Nap
        // slows down, and a slowed timer would see an agent start late.
        // This option keeps App Nap off and still lets the Mac sleep.
        napActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "agent caffeine watches for agents"
        )

        license.start()
        engine.start()
        refreshHookStatuses()
        syncSleepFlag()
        // On its own, so a helper that gives no answer holds nothing up.
        Task { await sleepFlag.replaceHelper(ifNot: AppVersion.helperForm) }
    }

    /// What the menu is worked out from.
    var panelInput: PanelInput {
        PanelInput(
            decision: decision,
            mode: mode,
            entitlement: entitlement,
            hasLicenseKey: license.record.key != nil,
            labels: sessionLabels,
            hints: sessionHints,
            clock: stateClock,
            settings: settings,
            flagLeftOn: sleepFlag.flagLeftOn,
            lidClosedNeedsSetup: MenuModel.lidClosedNeedsSetup(
                setup: sleepFlag.setup, wasSetUp: sleepFlag.wasSetUp, wanted: settings.stayAwakeLidClosedOnBattery, hasBattery: hasBattery
            ),
            helperNotResponding: MenuModel.helperNotResponding(
                notResponding: sleepFlag.setup == .notResponding, wanted: settings.stayAwakeLidClosedOnBattery, hasBattery: hasBattery
            ),
            helperRepairTried: sleepFlag.repairTried,
            helperLost: MenuModel.helperLost(
                setup: sleepFlag.setup, wasSetUp: sleepFlag.wasSetUp, wanted: settings.stayAwakeLidClosedOnBattery, hasBattery: hasBattery
            ),
            lidClosedHintDismissed: lidClosedHintDismissed
        )
    }

    // MARK: Engine

    private func apply(_ decision: HoldDecision) {
        self.decision = decision
        refreshRows()
        updatePower()
        syncSleepFlag()
    }

    private func sampled(_ sample: DetectionSample) {
        samples += 1
        let context = sample.frame.context
        if sessionHints != sample.sessionHints { sessionHints = sample.sessionHints }
        if hasBattery != (context.batteryPercent != nil) { hasBattery = context.batteryPercent != nil }
        let stop = safetyMonitor.update(context.safetyInputs)
        if let begun = SafetyStop.toAnnounce(previous: engine.safety, current: stop, wasHolding: power.held) {
            notify(begun.notificationText)
        }
        engine.safety = stop
        announceHiddenNotice()
        // Also keeps the assertions for another timeout.
        updatePower()
        sleepFlag.refreshHealth()
        if sleepFlag.repairIsDue {
            Task {
                await sleepFlag.retryRepairIfDue()
                syncSleepFlag()
            }
        }
        // Sends again what did not get through.
        syncSleepFlag()
        if sample.frame.at.timeIntervalSince(lastHelperRefresh) >= Self.helperRefreshInterval { refreshHelperStatus() }
    }

    /// With the icon hidden, the menu's word that agent caffeine cannot do
    /// its work reaches nobody, so it is told once as a notification.
    private func announceHiddenNotice() {
        let current = HiddenNotice.current(
            flagLeftOn: sleepFlag.flagLeftOn,
            helperNotResponding: MenuModel.helperNotResponding(
                notResponding: sleepFlag.setup == .notResponding, wanted: settings.stayAwakeLidClosedOnBattery, hasBattery: hasBattery
            ),
            entitlement: entitlement
        )
        if let begun = HiddenNotice.toAnnounce(previous: hiddenNotice, current: current, iconHidden: !showMenuBarIcon) {
            notify(begun.notificationText)
        }
        hiddenNotice = current
    }

    private func updatePower() {
        if decision.hold, let reason = decision.headline.awakeReason {
            power.hold(reason: "agent caffeine: \(reason)")
        } else {
            power.release()
        }
    }

    /// The folder of each session that works or waits, so the menu can tell
    /// two sessions of one agent apart. It is shown only, never logged.
    private func refreshRows() {
        let readings = decision.perAgent.map(\.reading)
        var next: [ProcessIdentity: String] = [:]
        for reading in readings where reading.verdict.state != .idle && reading.kind == .cli {
            next[reading.identity] = sessionLabels[reading.identity]
                ?? MenuModel.sessionLabel(workingDirectory: openFiles.workingDirectory(of: reading.identity.pid))
        }
        if sessionLabels != next { sessionLabels = next }
        let clock = stateClock.updated(with: readings, now: Date())
        if stateClock != clock { stateClock = clock }
    }

    // MARK: Helper

    /// Called when the menu or Preferences opens, and on a timer.
    func refreshHelperStatus() {
        lastHelperRefresh = Date()
        sleepFlag.refreshStatus()
        syncSleepFlag()
    }

    /// The controller's heartbeat keeps the flag alive, so the helper is
    /// called only when the wanted value changes, and again after a call
    /// that did not get through.
    private func syncSleepFlag() {
        guard let value = flagRequest.next(
            wanted: decision.lidClosedFlag, helperEnabled: sleepFlag.helperStatus == .enabled, now: Self.uptime
        ) else { return }
        Task {
            _ = await sleepFlag.setSleepDisabled(value)
            if sleepFlag.lastSetFailed { flagRequest.didFail(now: Self.uptime) }
        }
    }

    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// "Try again" in the menu and in Preferences.
    func repairHelper() {
        runHelperAction { await self.sleepFlag.repairHelper() }
    }

    func setUpHelper() {
        runHelperAction { try await self.sleepFlag.install() }
    }

    func removeHelper() {
        runHelperAction { try await self.sleepFlag.uninstall() }
    }

    func removeSudoersEntry() {
        runHelperAction { try await self.sleepFlag.removeSudoersEntry() }
    }

    /// A helper that waits for approval is no error: Preferences shows what
    /// to do from the helper's state.
    private func runHelperAction(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                helperError = nil
            } catch SleepFlagError.requiresApproval {
                helperError = nil
            } catch {
                helperError = error.localizedDescription
            }
            syncSleepFlag()
        }
    }

    // MARK: Hooks

    /// The hook entries point at the copy in the Applications folder, so
    /// they are offered only when the hook command is there.
    var hooksAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: HookCatalog.executablePath())
    }

    /// Entries with another path or from an older build read as outdated.
    /// They are shown, and rewritten only when the user asks.
    func refreshHookStatuses() {
        let next = Dictionary(uniqueKeysWithValues: HookCatalog.entries.map { ($0.id, hookInstaller.status(of: $0)) })
        if hookStatuses != next { hookStatuses = next }
    }

    func setHooks(_ entry: HookCatalogEntry, on: Bool) {
        do {
            if on {
                try hookInstaller.install(entry)
            } else {
                try hookInstaller.uninstall(entry)
            }
            hookErrors[entry.id] = nil
        } catch {
            let known = error as? HookInstallError ?? .writeFailed
            hookErrors[entry.id] = known.message(file: hookInstaller.displayPath(for: entry))
        }
        refreshHookStatuses()
    }

    // MARK: Quit

    // Safe to call more than once. The sleep flag is cleared before this
    // returns, or the wait for the helper ran out.
    func shutdown() {
        engine.stop()
        sleepFlag.clearForQuit(timeout: 2)
        power.release()
        if let napActivity {
            ProcessInfo.processInfo.endActivity(napActivity)
            self.napActivity = nil
        }
    }
}
