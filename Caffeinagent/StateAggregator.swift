import AppKit
import Combine
import os

/// Joins the detection engine to what it drives: the power assertions, the
/// root helper's sleep flag, the notification of a safety stop, and the
/// state the menu and Preferences show.
@MainActor
final class StateAggregator: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            engine.enabled = enabled
        }
    }
    @Published var mode: AwakeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            engine.mode = mode
        }
    }
    @Published var settings: DetectionSettings {
        didSet {
            guard settings != oldValue else { return }
            DetectionSettingsStore.save(settings, to: .standard)
            safetyMonitor.batteryFloorPercent = settings.batteryFloorPercent
            engine.settings = settings
        }
    }
    /// The tab Preferences shows, so the menu can open one.
    @Published var preferencesTab = PreferencesTab.general
    @Published private(set) var decision: HoldDecision
    @Published private(set) var agentRows: [MenuAgentRow] = []
    @Published private(set) var entitlement: Entitlement
    /// False on a Mac without a battery, where a closed lid needs no helper.
    @Published private(set) var hasBattery = true
    @Published private(set) var helperError: String?
    /// By hook agent id. Read at launch and when Preferences opens, and
    /// never changed without the user's word.
    @Published private(set) var hookStatuses: [String: HookStatus] = [:]
    @Published private(set) var hookErrors: [String: String] = [:]

    let license: LicenseManager
    let sleepFlag: SleepFlagController
    let canSetUpHelper = AppRelocator.isInSystemApplications
    private let hookInstaller = HookInstaller()
    private let engine: DetectionEngine
    private let power = PowerKeeper()
    private let openFiles = SystemOpenFiles()
    private var safetyMonitor = SafetyMonitor()
    private var flagRequest = SleepFlagRequest()
    /// The helper gets no call before its version was checked at launch.
    private var helperChecked = false
    private var lastHelperRefresh = Date.distantPast
    private var labels: [ProcessIdentity: String] = [:]
    private var napActivity: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var sigtermSource: DispatchSourceSignal?
    private static let enabledKey = "StateAggregator.enabled"
    private static let modeKey = "StateAggregator.mode"
    /// System Settings tells nobody when the user allows or removes the
    /// helper, so its state is read again this often.
    private static let helperRefreshInterval: TimeInterval = 30

    init() {
        let license = LicenseManager(client: LicenseClient(), store: KeychainLicenseStore())
        let enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        let mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(AwakeMode.init(rawValue:)) ?? .agentWorking
        let settings = DetectionSettingsStore.load(from: .standard)
        LegacyBatteryOverride.clearLeftover()
        let engine = DetectionEngine.system(mode: mode, enabled: enabled, entitlement: license.entitlement, settings: settings)
        self.license = license
        self.sleepFlag = SleepFlagController()
        self.engine = engine
        self.entitlement = license.entitlement
        self.enabled = enabled
        self.mode = mode
        self.settings = settings
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
        Task {
            await sleepFlag.replaceHelper(ifNot: AppVersion.helperForm)
            helperChecked = true
            syncSleepFlag()
        }
    }

    var lidClosedStatus: LidClosedStatus {
        MenuModel.lidClosedStatus(helper: sleepFlag.helperStatus, wanted: settings.stayAwakeLidClosedOnBattery)
    }

    // MARK: Engine

    private func apply(_ decision: HoldDecision) {
        self.decision = decision
        refreshRows()
        updatePower()
        syncSleepFlag()
    }

    private func sampled(_ sample: DetectionSample) {
        let context = sample.frame.context
        if hasBattery != (context.batteryPercent != nil) { hasBattery = context.batteryPercent != nil }
        let stop = safetyMonitor.update(context.safetyInputs)
        if let begun = SafetyStop.toAnnounce(previous: engine.safety, current: stop, wasHolding: power.held) {
            SafetyNotifier.post(begun.notificationText)
        }
        engine.safety = stop
        // Also keeps the assertions for another timeout.
        updatePower()
        if sample.frame.at.timeIntervalSince(lastHelperRefresh) >= Self.helperRefreshInterval { refreshHelperStatus() }
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
        var next: [ProcessIdentity: String] = [:]
        for reading in decision.perAgent.map(\.reading) where reading.verdict.state != .idle && reading.kind == .cli {
            next[reading.identity] = labels[reading.identity]
                ?? MenuModel.sessionLabel(workingDirectory: openFiles.workingDirectory(of: reading.identity.pid))
        }
        labels = next
        let rows = MenuModel.rows(for: decision.perAgent, labels: labels)
        if agentRows != rows { agentRows = rows }
    }

    // MARK: Helper

    /// Called when the menu or Preferences opens, and on a timer.
    func refreshHelperStatus() {
        lastHelperRefresh = Date()
        sleepFlag.refreshStatus()
        syncSleepFlag()
    }

    /// The controller's heartbeat keeps the flag alive, so the helper is
    /// called only when the wanted value changes.
    private func syncSleepFlag() {
        guard helperChecked,
              let value = flagRequest.next(wanted: decision.lidClosedFlag, helperEnabled: sleepFlag.helperStatus == .enabled)
        else { return }
        Task { _ = await sleepFlag.setSleepDisabled(value) }
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
