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
    var hotKeys: HotKeyRegistering
    /// Nil leaves the displays alone.
    var display: DisplayController?
    var notify: (String) -> Void
    /// Nil sends no agent notification and asks macOS nothing.
    var notifier: AgentNotifying?

    static func system() -> AggregatorParts {
        AggregatorParts(
            defaults: .standard,
            license: LicenseManager(client: LicenseClient(), store: KeychainLicenseStore()),
            sleepFlag: SleepFlagController(),
            power: PowerKeeper(),
            hotKeys: GlobalHotKey(),
            display: DisplayController(
                reader: SystemDisplayReader(), sleeper: SystemDisplaySleep(),
                dimmer: BuiltinDimmer(methods: BuiltinDimmer.systemMethods, defaults: .standard), watcher: SystemDisplayWatcher(),
                lid: SystemLidAngle(), ticker: SystemLidTicker(), trace: DisplayTraceRecorder(defaults: .standard)
            ),
            notify: Notifier.post,
            notifier: Notifier.shared
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
            // Off ends a pause. See `PauseSwitch`.
            resumeNow()
            if !enabled { stopReachable() }
        }
    }
    /// Until when agent caffeine acts as if it were off. The end is saved,
    /// so a pause lasts over a restart of the app and a sleep of the Mac.
    @PublishedOnChange private(set) var pause: Pause {
        didSet {
            guard pause != oldValue else { return }
            if let until = pause.until {
                defaults.set(until, forKey: Self.pausedUntilKey)
            } else {
                defaults.removeObject(forKey: Self.pausedUntilKey)
            }
            engine.pausedUntil = pause.until
            armPauseTimer()
        }
    }
    /// Until when the Mac stays awake with no agent at work. Saved like
    /// the end of a pause.
    @PublishedOnChange private(set) var reachable: Reachable {
        didSet {
            guard reachable != oldValue else { return }
            if let until = reachable.until {
                defaults.set(until, forKey: Self.reachableUntilKey)
            } else {
                defaults.removeObject(forKey: Self.reachableUntilKey)
            }
            engine.reachableUntil = reachable.until
            armReachableTimer()
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
            safetyMonitor.batteryFloorEnabled = settings.batteryFloorEnabled
            engine.settings = settings
            // The display and a battery stop follow a switch at once, not at
            // the next sample.
            if settings.displayOffLidClosed != oldValue.displayOffLidClosed || settings.dimAsLidCloses != oldValue.dimAsLidCloses
                || settings.batteryFloorEnabled != oldValue.batteryFloorEnabled {
                engine.requestSample()
            }
        }
    }
    /// Which agent notifications the user wants. Switching one on asks
    /// macOS for permission, so the question comes with a reason.
    @PublishedOnChange var notices: AgentNoticeSettings {
        didSet {
            guard notices != oldValue else { return }
            notices.save(to: defaults)
            if notices.waiting && !oldValue.waiting || notices.finished && !oldValue.finished { notifier?.requestPermission() }
        }
    }
    @PublishedOnChange private(set) var notificationPermission = NotificationPermission.notAsked
    /// The robot in the menu bar. Hiding it changes nothing else. The
    /// menu bar scene writes this back all the time, so a write of the
    /// same value must publish nothing and save nothing.
    @PublishedOnChange var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            MenuBarVisibility.set(showMenuBarIcon, in: defaults)
        }
    }
    /// The keyboard shortcuts that work in every app. None until the user
    /// records one.
    @PublishedOnChange private(set) var shortcuts: [ShortcutAction: Shortcut]
    /// Why the shortcut of an action was not taken or does not work.
    @PublishedOnChange private(set) var shortcutProblems: [ShortcutAction: ShortcutProblem] = [:]
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
    /// For the battery bar of the menu.
    @PublishedOnChange private(set) var onBattery = false
    @PublishedOnChange private(set) var batteryPercent: Int?
    @PublishedOnChange private(set) var helperError: String?
    /// By hook agent id. Read at launch and when Preferences opens, and
    /// never changed without the user's word.
    @PublishedOnChange private(set) var hookStatuses: [String: HookStatus] = [:]
    @PublishedOnChange private(set) var hookErrors: [String: String] = [:]

    let license: LicenseManager
    let sleepFlag: SleepFlagController
    let canSetUpHelper = AppRelocator.isInSystemApplications
    /// False on a Mac without a lid angle sensor, where the display cannot
    /// follow the lid.
    var hasLidAngleSensor: Bool { display?.hasLidAngleSensor ?? false }
    private let hookInstaller = HookInstaller()
    private let engine: DetectionEngine
    /// How many samples the engine gave. For the smoke test.
    private(set) var samples = 0
    private let defaults: UserDefaults
    private let power: PowerHolding
    private let hotKeys: HotKeyRegistering
    private let display: DisplayController?
    private let notify: (String) -> Void
    private let notifier: AgentNotifying?
    private var agentNotices = AgentNoticeReducer()
    /// The app each session runs in, looked up once. 0 for none.
    private var sessionOwners: [ProcessIdentity: Int32] = [:]
    private let openFiles = SystemOpenFiles()
    private var safetyMonitor = SafetyMonitor()
    private var noLimitWarning = NoLimitBatteryWarning()
    private var flagRequest = SleepFlagRequest()
    private var hiddenNotice: HiddenNotice?
    private var lastHelperRefresh = Date.distantPast
    private var napActivity: NSObjectProtocol?
    private var pauseTimer: Timer?
    private var reachableTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var sigtermSource: DispatchSourceSignal?
    private static let enabledKey = "StateAggregator.enabled"
    private static let modeKey = "StateAggregator.mode"
    private static let pausedUntilKey = "StateAggregator.pausedUntil"
    private static let reachableUntilKey = "StateAggregator.reachableUntil"
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
        let pause = Pause(stored: defaults.object(forKey: Self.pausedUntilKey) as? Date, now: Date())
        if pause.until == nil { defaults.removeObject(forKey: Self.pausedUntilKey) }
        // A pause that was saved wins: the two never run together.
        let reachable = pause.until == nil && enabled
            ? Reachable(stored: defaults.object(forKey: Self.reachableUntilKey) as? Date, now: Date()) : Reachable()
        if reachable.until == nil { defaults.removeObject(forKey: Self.reachableUntilKey) }
        let engine = DetectionEngine.system(
            mode: mode, enabled: enabled, pausedUntil: pause.until, reachableUntil: reachable.until,
            entitlement: license.entitlement, settings: settings
        )
        self.license = license
        self.sleepFlag = parts.sleepFlag
        self.defaults = defaults
        self.power = parts.power
        self.hotKeys = parts.hotKeys
        self.display = parts.display
        self.notify = parts.notify
        self.notifier = parts.notifier
        self.engine = engine
        self.entitlement = license.entitlement
        self.enabled = enabled
        self.pause = pause
        self.reachable = reachable
        self.shortcuts = ShortcutStore.load(from: defaults)
        self.mode = mode
        self.settings = settings
        self.notices = AgentNoticeSettings.load(from: defaults)
        self.lidClosedHintDismissed = defaults.bool(forKey: Self.lidClosedHintKey)
        self.showMenuBarIcon = MenuBarVisibility.isShown(in: defaults)
        self.decision = engine.decision
        safetyMonitor.batteryFloorPercent = settings.batteryFloorPercent
        safetyMonitor.batteryFloorEnabled = settings.batteryFloorEnabled

        engine.$decision
            .dropFirst()
            .sink { [weak self] decision in self?.apply(decision) }
            .store(in: &cancellables)
        engine.onSample = { [weak self] sample in self?.sampled(sample) }
        notifier?.onPermission = { [weak self] permission in self?.notificationPermission = permission }

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

        // A timer does not run while the Mac sleeps, and a clock that was
        // set moves the end of a pause.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemClockDidChange))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settlePause() }
            .store(in: &cancellables)
        armPauseTimer()
        armReachableTimer()

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
        registerShortcuts()
        // The display controller acts on a lid that closes by itself and at
        // once. The sample is for the rest of the app.
        display?.start { [weak self] in self?.engine.requestSample() }
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
            pausedUntil: pause.until,
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
            lidClosedHintDismissed: lidClosedHintDismissed,
            reachableUntil: reachable.until,
            enabled: enabled,
            onBattery: onBattery,
            batteryPercent: batteryPercent
        )
    }

    // MARK: Pause

    /// Nothing to pause while agent caffeine is off. A pause ends "stay
    /// reachable". See `TimedModes`.
    func startPause(_ choice: PauseChoice) {
        guard enabled else { return }
        var next = TimedModes(pause: pause, reachable: reachable)
        next.startPause(choice, now: Date(), calendar: .current)
        (reachable, pause) = (next.reachable, next.pause)
    }

    /// Not while agent caffeine is off or may not keep the Mac awake.
    /// "Stay reachable" ends a pause.
    func startReachable(_ choice: ReachableChoice) {
        guard enabled, entitlement.allowsHolding else { return }
        var next = TimedModes(pause: pause, reachable: reachable)
        next.startReachable(choice, now: Date())
        (pause, reachable) = (next.pause, next.reachable)
    }

    func stopReachable() {
        var next = reachable
        next.stop()
        reachable = next
    }

    func resumeNow() {
        var next = pause
        next.resume()
        pause = next
    }

    /// Ends a pause and a "stay reachable" whose time has come, and sets
    /// the timers for what goes on: after a sleep the old timer is late.
    private func settlePause() {
        var next = TimedModes(pause: pause, reachable: reachable)
        next.settle(now: Date())
        (pause, reachable) = (next.pause, next.reachable)
        armPauseTimer()
        armReachableTimer()
    }

    private func armReachableTimer() {
        reachableTimer?.invalidate()
        reachableTimer = nil
        guard let until = reachable.until else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settlePause() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reachableTimer = timer
    }

    private func armPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        guard let until = pause.until else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settlePause() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    // MARK: Shortcuts

    /// The same as the switch, from the keyboard. A pause ends.
    func toggleEnabled() {
        var state = PauseSwitch(enabled: enabled, pause: pause)
        state.toggle(now: Date())
        if state.enabled != enabled {
            enabled = state.enabled
        } else {
            pause = state.pause
        }
    }

    /// Nil clears the shortcut. One that cannot be taken leaves the old
    /// one as it is, and Preferences says why.
    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        if let shortcut {
            let others = shortcuts.filter { $0.key != action }.map(\.value)
            if let problem = ShortcutRules.problem(shortcut, system: hotKeys.systemShortcuts, others: others) {
                shortcutProblems[action] = problem
                return
            }
        }
        shortcuts[action] = shortcut
        ShortcutStore.save(shortcuts, to: defaults)
        register(action)
    }

    /// While Preferences records a shortcut, none of them is registered.
    func setShortcutRecording(_ recording: Bool) {
        if recording {
            hotKeys.unregisterAll()
            shortcutProblems = [:]
        } else {
            registerShortcuts()
        }
    }

    private func registerShortcuts() {
        ShortcutAction.allCases.forEach(register)
    }

    private func register(_ action: ShortcutAction) {
        let registered = hotKeys.register(shortcuts[action], for: action) { [weak self] in
            switch action {
            case .toggle: self?.toggleEnabled()
            case .pauseOneHour: self?.startPause(.oneHour)
            }
        }
        shortcutProblems[action] = registered ? nil : .usedByAnotherApp
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
        if onBattery != context.onBattery { onBattery = context.onBattery }
        if batteryPercent != context.batteryPercent { batteryPercent = context.batteryPercent }
        let stop = safetyMonitor.update(context.safetyInputs)
        if let begun = SafetyStop.toAnnounce(previous: engine.safety, current: stop, wasHolding: power.held) {
            notify(begun.notificationText)
        }
        if let percent = noLimitWarning.update(context.safetyInputs, floorEnabled: settings.batteryFloorEnabled, holding: power.held) {
            notify(NoLimitBatteryWarning.notificationText(percent: percent))
        }
        engine.safety = stop
        // The notification above says why. The time does not come back
        // with the power.
        if stop != nil, reachable.until != nil {
            var next = TimedModes(pause: pause, reachable: reachable)
            next.safetyStopped()
            reachable = next.reachable
        }
        announceHiddenNotice()
        announceAgents(sample)
        display?.update(
            lidClosed: context.lidClosed, holding: sample.decision.hold, enabled: settings.displayOffLidClosed,
            fade: settings.dimAsLidCloses, now: sample.frame.at
        )
        // In case a timer is late.
        if pause.until != nil, !pause.isPaused(now: Date()) { settlePause() }
        if reachable.until != nil, !reachable.isOn(now: Date()) { settlePause() }
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

    /// An agent that waits for the user or finished, as a notification.
    /// The names of the sessions are shown there and go nowhere else.
    private func announceAgents(_ sample: DetectionSample) {
        guard let notifier else { return }
        guard notices.wantsAny else {
            // What is there when a switch goes on is no news.
            agentNotices = AgentNoticeReducer()
            sessionOwners = [:]
            return
        }
        var owners: [ProcessIdentity: Int32] = [:]
        var apps: Set<Int32>?
        for reading in sample.readings {
            if let known = sessionOwners[reading.identity] {
                owners[reading.identity] = known
            } else {
                let running = apps ?? AgentOwner.runningApps()
                apps = running
                owners[reading.identity] = AgentOwner.resolve(pid: reading.identity.pid, apps: running) ?? 0
            }
        }
        sessionOwners = owners
        let away = notices.onlyWhenAway
        let input = AgentNoticeInput(
            readings: sample.readings,
            labels: sessionLabels.merging(sample.sessionHints.compactMapValues(\.name)) { _, name in name },
            owners: owners.filter { $0.value > 0 },
            frontmostPid: away ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil,
            userActive: away && AgentOwner.userIsActive(),
            settings: notices,
            active: enabled && pause.until == nil && entitlement.allowsHolding
        )
        // In the other modes, after a stop, and while the Mac stays awake
        // for phone access, the waiting hold does not decide when the Mac
        // sleeps.
        let context = sample.frame.context
        let staysAwake = reachable.until != nil
            || settings.stayAwakeForRemoteAccess && context.remoteAccessDetected && !context.onBattery
        let waitingHold = mode == .agentWorking && sample.decision.hold && !staysAwake ? settings.waitingHold : nil
        for notice in agentNotices.update(input, now: sample.frame.at) {
            notifier.post(AgentNoticeText.content(notice, waitingHold: waitingHold, now: sample.frame.at))
        }
    }

    /// Called when Preferences opens: the user can change the permission
    /// in System Settings at any time.
    func refreshNotificationPermission() {
        notifier?.readPermission()
    }

    func openNotificationSettings() {
        notifier?.openSystemSettings()
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
        pauseTimer?.invalidate()
        reachableTimer?.invalidate()
        hotKeys.unregisterAll()
        display?.stop()
        sleepFlag.clearForQuit(timeout: 2)
        power.release()
        if let napActivity {
            ProcessInfo.processInfo.endActivity(napActivity)
            self.napActivity = nil
        }
    }
}
