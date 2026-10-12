import AppKit
import Combine
import os

/// What the aggregator reaches the Mac through. The app passes the real
/// parts. The smoke test passes parts that do nothing, so it can start
/// the app next to a copy that is installed (see `SmokeTest`).
@MainActor
struct AggregatorParts {
    var defaults: UserDefaults
    var sleepFlag: SleepFlagController
    var power: PowerHolding
    var hotKeys: HotKeyRegistering
    /// Nil leaves the displays alone.
    var display: DisplayController?
    var notify: (String) -> Void
    /// Nil sends no agent notification and asks macOS nothing.
    var notifier: AgentNotifying?
    /// Nil finds the app of no agent, so no row goes to one.
    var hosts: AgentHostFinding?
    var loginItem: LoginItemManaging
    /// Nil reads no sleep timer of macOS.
    var sleepTimer: SleepTimerReading?
    /// Nil sees no other app that keeps the Mac awake.
    var assertions: PowerAssertionListing?
    /// Nil plays no sound when the lid closes.
    var chime: LidChimePlaying?
    /// The keyboard layouts the default shortcuts are looked up in, asked
    /// again when the user selects another layout. With none, the defaults
    /// stay on the keys of the American layout.
    var keyLayouts: () -> [KeyLayout] = { [] }
    /// Nil reads no scheduled job: not the launchd agents, not the
    /// crontab and not the jobs of Hermes Agent.
    var jobAccess: JobSourceAccess?
    /// Nil looks for the job of no hold among the processes.
    var jobProbe: JobRunProbing?

    static func system() -> AggregatorParts {
        AggregatorParts(
            defaults: .standard,
            sleepFlag: SleepFlagController(),
            power: PowerKeeper(),
            hotKeys: GlobalHotKey(),
            display: DisplayController(
                reader: SystemDisplayReader(), sleeper: SystemDisplaySleep(),
                dimmer: BuiltinDimmer(methods: BuiltinDimmer.systemMethods, defaults: .standard), watcher: SystemDisplayWatcher(),
                lid: SystemLidAngle(), ticker: SystemLidTicker(), trace: DisplayTraceRecorder(defaults: .standard)
            ),
            notify: Notifier.post,
            notifier: Notifier.shared,
            hosts: SystemAgentHosts(),
            loginItem: SystemLoginItem(),
            sleepTimer: SystemSleepTimer(),
            assertions: SystemPowerAssertions(),
            chime: SystemLidChimePlayer(),
            keyLayouts: SystemKeyLayout.inUse,
            jobAccess: SystemJobSourceAccess(),
            jobProbe: SystemJobRunProbe()
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
            updateJobWake()
        }
    }
    /// Until when Agent Caffeine acts as if it were off. The end is saved,
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
            updateJobWake()
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
    /// The last agent notifications, for Preferences.
    @PublishedOnChange private(set) var noticeHistory = AgentNoticeHistory()
    /// The robot in the menu bar. Hiding it changes nothing else. The
    /// menu bar scene writes this back all the time, so a write of the
    /// same value must publish nothing and save nothing.
    @PublishedOnChange var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            MenuBarVisibility.set(showMenuBarIcon, in: defaults)
        }
    }
    /// What the user did with the keyboard shortcuts that work in every
    /// app. An action the user never changed has its default.
    @PublishedOnChange private(set) var shortcutChoices: ShortcutChoices
    var shortcuts: [ShortcutAction: Shortcut] { shortcutChoices.shortcuts }
    /// Why the shortcut of an action was not taken or does not work.
    @PublishedOnChange private(set) var shortcutProblems: [ShortcutAction: ShortcutProblem] = [:]
    /// The tab Preferences shows, so the menu can open one.
    @PublishedOnChange var preferencesTab = PreferencesTab.general
    /// The menu asked for "Other tools" of the tab Agents. The tab clears
    /// it once it is there.
    @PublishedOnChange var showsOtherTools = false
    /// "Open Agent Caffeine at login", as macOS has it.
    @PublishedOnChange private(set) var loginItem = LoginItemState.unavailable
    @PublishedOnChange private(set) var loginItemError: String?
    /// Why the Mac slept under an agent, until the user dismisses it or
    /// the Mac sleeps again.
    @PublishedOnChange private(set) var sleepNote: SleepNote?
    @PublishedOnChange private(set) var decision: HoldDecision
    /// The folder of each session that works or waits, for the menu.
    @PublishedOnChange private(set) var sessionLabels: [ProcessIdentity: String] = [:]
    /// What tells sessions with the same name and folder apart, for the
    /// menu. It is shown only, never logged.
    @PublishedOnChange private(set) var sessionHints: [ProcessIdentity: SessionHint] = [:]
    /// The name of the app each agent is shown in, for a click on its row.
    /// Nil for an agent with no app to go to.
    @PublishedOnChange private(set) var agentHosts: [ProcessIdentity: String?] = [:]
    /// Since when each agent is in its state, for the menu.
    @PublishedOnChange private(set) var stateClock = StateClock()
    /// The user closed the menu's hint to set up "lid closed on battery".
    @PublishedOnChange var lidClosedHintDismissed: Bool {
        didSet {
            guard lidClosedHintDismissed != oldValue else { return }
            defaults.set(lidClosedHintDismissed, forKey: Self.lidClosedHintKey)
        }
    }
    /// False on a Mac without a battery, where a closed lid needs no helper.
    @PublishedOnChange private(set) var hasBattery = true
    /// For the line of the battery in the menu.
    @PublishedOnChange private(set) var onBattery = false
    @PublishedOnChange private(set) var batteryPercent: Int?
    /// For what the menu says below an agent that waits. See `SleepOutlook`.
    @PublishedOnChange private(set) var macSleep = MacSleepState()
    @PublishedOnChange private(set) var helperError: String?
    /// By hook agent id. Read at launch and when Preferences opens, and
    /// never changed without the user's word, but for a file that is all
    /// ours: see `updateOwnHookFiles`.
    @PublishedOnChange private(set) var hookStatuses: [String: HookStatus] = [:]
    @PublishedOnChange private(set) var hookErrors: [String: String] = [:]
    /// "Set up for agents": the skill per agent and the link to the tool.
    /// Read at launch and when Preferences opens, and never changed
    /// without the user's word, but for what is ours already: see
    /// `updateOwnSkill`.
    @PublishedOnChange private(set) var agentSetup = AgentSetupModel()
    /// What the user chose for "Wake for jobs". Off, and every job off,
    /// until the user says otherwise.
    @PublishedOnChange var jobSettings: JobSettings {
        didSet {
            guard jobSettings != oldValue else { return }
            JobSettingsStore.save(jobSettings, to: defaults)
            syncJobStore()
            updateJobWake()
        }
    }
    /// The jobs that were found, the alarm that is set and the history,
    /// for Settings and the menu.
    @PublishedOnChange private(set) var jobWake = JobWakeView()

    let sleepFlag: SleepFlagController
    let canSetUpHelper = AppRelocator.isInSystemApplications
    /// False on a Mac without a lid angle sensor, where the display cannot
    /// follow the lid.
    var hasLidAngleSensor: Bool { display?.hasLidAngleSensor ?? false }
    /// The hooks are written with the path of the install as it is named
    /// on disk: see `AppInstall`.
    private let hookInstaller = HookInstaller(appPath: AppInstall.running.stablePath, spellings: AppInstall.running.spellings)
    /// Nil when the skill is not in the bundle.
    private let skillInstaller: SkillInstaller? = {
        let running = AppInstall.running
        return SkillCatalog.bundledSkill(appPath: running.path).map {
            SkillInstaller(
                skill: $0, toolPath: CommandLineSetup(appPath: running.path).toolPath,
                stableToolPath: CommandLineSetup(appPath: running.stablePath).toolPath
            )
        }
    }()
    private var askedForShellPath = false
    private let engine: DetectionEngine
    /// How many samples the engine gave. For the smoke test.
    private(set) var samples = 0
    private let defaults: UserDefaults
    private let power: PowerHolding
    private let hotKeys: HotKeyRegistering
    private let keyLayouts: () -> [KeyLayout]
    private var recordingShortcut = false
    private let display: DisplayController?
    private let notify: (String) -> Void
    private let notifier: AgentNotifying?
    private let hosts: AgentHostFinding?
    private let loginItemService: LoginItemManaging
    private let sleepTimer: SleepTimerReading?
    private let assertions: PowerAssertionListing?
    private let sleepTimerQueue = DispatchQueue(label: "com.caffeinagent.sleep-timer", qos: .utility)
    /// The last answer, and what it was asked for.
    private var sleepTimerRead: (onBattery: Bool, at: Date, minutes: Int?)?
    /// Taken when macOS says the Mac goes to sleep, read when it wakes.
    private var sleepSnapshot: SleepSnapshot?
    private let powerContext = SystemPowerContext()
    private var agentNotices = AgentNoticeReducer()
    /// The app each session runs in, looked up once. 0 for none.
    private var sessionOwners: [ProcessIdentity: Int32] = [:]
    private let openFiles = SystemOpenFiles()
    private var safetyMonitor = SafetyMonitor()
    private var closedLidLimit = ClosedLidLimit()
    private var noLimitWarning = NoLimitBatteryWarning()
    private var flagRequest = SleepFlagRequest()
    private var hiddenNotice: HiddenNotice?
    private let lidChimer: LidChimer
    private var lidChimeTimer: Timer?
    private var lastHelperRefresh = Date.distantPast
    private var napActivity: NSObjectProtocol?
    private var pauseTimer: Timer?
    private var reachableTimer: Timer?
    /// The folder of the holds from the command line.
    private let holdStore = HoldStore()
    /// Tells the command line tool that the app runs. Nil in the smoke
    /// test, which runs next to a copy that is installed.
    private var holdLock: HoldStore.AppLock?
    private lazy var holdStatus = HoldStore.StatusWriter(store: holdStore)
    /// The state for the tests, while its hidden switch is on. See `TestState`.
    private lazy var testState = TestStateWriter(store: holdStore, defaults: defaults)
    private var testStateTimer: Timer?
    private var testNotices = TestNoticeLog()
    private var chimePlayedAt: Date?
    /// The loop of "Wake for jobs". See `JobWake` for its rules.
    private let jobLoop: JobWakeLoop
    private let jobStore: JobStore?
    /// What the store read last. Empty while the feature is off.
    private var jobReadings: [JobSourceReading] = []
    private var jobTimer: Timer?
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
    /// The user can change the sleep timer in System Settings at any time.
    private static let sleepTimerRefreshInterval: TimeInterval = 30
    /// While a closed lid waits for the helper's answer. See `LidChime`.
    private static let lidChimeLookInterval: TimeInterval = 0.25
    /// After the time of an alarm or the end of a hold, so the turn finds
    /// it passed.
    private static let jobTimerSlack: TimeInterval = 0.05
    /// The state for the tests is never older than 5 seconds.
    private static let testStateInterval: TimeInterval = 4

    init(parts: AggregatorParts) {
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
            mode: mode, enabled: enabled, pausedUntil: pause.until, reachableUntil: reachable.until, settings: settings
        )
        self.sleepFlag = parts.sleepFlag
        self.defaults = defaults
        self.power = parts.power
        self.hotKeys = parts.hotKeys
        self.keyLayouts = parts.keyLayouts
        self.display = parts.display
        self.notify = parts.notify
        self.notifier = parts.notifier
        self.hosts = parts.hosts
        self.loginItemService = parts.loginItem
        self.sleepTimer = parts.sleepTimer
        self.assertions = parts.assertions
        self.lidChimer = LidChimer(player: parts.chime)
        self.engine = engine
        self.enabled = enabled
        self.pause = pause
        self.reachable = reachable
        var shortcutChoices = ShortcutStore.load(from: defaults)
        shortcutChoices.defaults = ShortcutDefaults.resolve(in: parts.keyLayouts())
        self.shortcutChoices = shortcutChoices
        self.mode = mode
        self.settings = settings
        self.notices = AgentNoticeSettings.load(from: defaults)
        self.lidClosedHintDismissed = defaults.bool(forKey: Self.lidClosedHintKey)
        self.showMenuBarIcon = MenuBarVisibility.isShown(in: defaults)
        self.decision = engine.decision
        self.jobSettings = JobSettingsStore.load(from: defaults)
        self.jobLoop = JobWakeLoop(sender: parts.sleepFlag, probe: parts.jobProbe, defaults: defaults)
        self.jobStore = parts.jobAccess.map { JobStore(access: $0) }
        safetyMonitor.batteryFloorPercent = settings.batteryFloorPercent
        safetyMonitor.batteryFloorEnabled = settings.batteryFloorEnabled

        engine.$decision
            .dropFirst()
            .sink { [weak self] decision in self?.apply(decision) }
            .store(in: &cancellables)
        engine.onSample = { [weak self] sample in self?.sampled(sample) }
        notifier?.onPermission = { [weak self] permission in self?.notificationPermission = permission }
        notifier?.onDelivery = { [weak self] id, delivery in self?.noticeHistory.delivered(id, delivery) }
        notifier?.onOpen = { [weak self] target in
            // The pid of the app can belong to another process by now.
            let owner = target.ownerPid.flatMap { target.ownerIsStill(startTime: SystemProcessCensus.row(of: $0)?.startTime) ? $0 : nil }
            self?.goToAgent(target.agent, else: owner)
        }
        // Asks the user nothing, and puts the permission in the log.
        notifier?.readPermission()

        // The menu and Preferences read the helper's state through this
        // object.
        sleepFlag.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // The snapshot is taken before the wake below settles a pause that
        // ended while the Mac slept.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.macWillSleep() } }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.macDidWake() } }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.wokeInFull() } }
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
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Agent Caffeine watches for agents"
        )

        if !SmokeTest.isActive {
            holdLock = HoldStore.AppLock(store: holdStore)
            writeHoldStatus()
        }
        engine.start()
        updateOwnHookFiles()
        refreshHookStatuses()
        updateOwnSkill()
        refreshAgentSetup()
        refreshLoginItem()
        syncSleepFlag()
        registerShortcuts()
        // The loop takes its first turn with the first sample.
        jobLoop.onChange = { [weak self] in self?.jobWakeChanged() }
        syncJobStore()
        DistributedNotificationCenter.default().publisher(for: SystemKeyLayout.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.keyLayoutChanged() }
            .store(in: &cancellables)
        // The display controller acts on a lid that closes by itself and at
        // once. The sample is for the rest of the app.
        display?.start { [weak self] in
            self?.lookAtLidForChime()
            self?.engine.requestSample()
        }
        // On its own, so a helper that gives no answer holds nothing up.
        // The alarm of a helper that was replaced went with it.
        Task {
            if await sleepFlag.replaceHelper(ifNot: AppVersion.helperForm) { jobLoop.helperReplaced() }
        }
    }

    /// What the menu is worked out from.
    var panelInput: PanelInput {
        PanelInput(
            decision: decision,
            mode: mode,
            labels: sessionLabels,
            hints: sessionHints,
            hosts: agentHosts.compactMapValues { $0 },
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
            macSleep: macSleep,
            batteryPercent: batteryPercent,
            sleepNote: sleepNote,
            wakeAlarm: jobWake.alarm
        )
    }

    // MARK: Sleep note

    /// macOS posts both on the main thread.
    private func macWillSleep() {
        sleepNote = nil
        let settings = settings
        sleepSnapshot = SleepSnapshot(
            at: Date(),
            headline: decision.headline,
            agentActive: !decision.manualHolds.isEmpty || decision.perAgent.contains {
                $0.reading.verdict.state != .idle && settings.rule(for: $0.reading.agentID) != .ignore
            },
            lidClosed: powerContext.context().lidClosed,
            onBattery: onBattery,
            helperSetUp: sleepFlag.helperStatus == .enabled,
            lidClosedWanted: settings.stayAwakeLidClosedOnBattery,
            waitingHold: settings.waitingHold,
            working: decision.working(settings),
            offlineLimit: engine.offlineRule.limit ?? 0
        )
        display?.willSleep()
        engine.willSleep()
        // A Mac that is awake needs no alarm for a job that is near. One
        // that goes to sleep does, and the alarm is with the helper
        // before macOS is told that the app is ready for the sleep. The
        // power source is read now: a Mac that was unplugged and closed
        // within one sample keeps no alarm that is for power only.
        if samples > 0 { jobLoop.willSleep(jobWakeInput.withPower(of: powerContext.context())) }
    }

    private func macDidWake() {
        lidChimer.forget()
        wokeInFull()
        sleepNote = sleepSnapshot.flatMap(SleepNote.init)
        sleepSnapshot = nil
    }

    /// macOS says so, or the displays came on: both only happen at a full
    /// wake, never while a sleeping Mac wakes by itself with the display off.
    private func wokeInFull() {
        display?.didWake()
        engine.didWake()
        // The power source is read now, as at "will sleep": the Mac may
        // have been unplugged while it slept, and a hold can open here.
        jobLoop.wokeInFull(samples > 0 ? jobWakeInput.withPower(of: powerContext.context()) : nil)
    }

    func dismissSleepNote() {
        sleepNote = nil
    }

    // MARK: Agent rules

    /// From the menu of a row. `.automatic` takes the rule away.
    func setRule(_ rule: AgentRule, for agentID: String) {
        settings.agentRules[agentID] = rule == .automatic ? nil : rule
    }

    // MARK: Go to an agent

    /// Called when the menu opens, for every agent: a tmux client can come
    /// and go while its agent runs.
    /// - Parameter again: false asks only about the agents that are new.
    func refreshAgentHosts(again: Bool = true) {
        guard let hosts else { return }
        let readings = decision.perAgent.map(\.reading)
        let asked = readings.filter { again || agentHosts[$0.identity] == nil }
        let found = asked.isEmpty ? [] : hosts.hosts(of: asked.map { ($0.identity.pid, $0.kind) })
        var next: [ProcessIdentity: String?] = [:]
        for reading in readings {
            next.updateValue(agentHosts[reading.identity] ?? nil, forKey: reading.identity)
        }
        for (reading, host) in zip(asked, found) {
            next.updateValue(host.flatMap { hosts.name(ofApp: $0.appPid) }, forKey: reading.identity)
        }
        if agentHosts != next { agentHosts = next }
    }

    /// Brings the app of an agent to the front. The app is looked up now,
    /// not when the row or the notification was made.
    /// - Parameter fallback: the app the agent ran in, for an agent that
    ///   is gone.
    /// - Returns: false when there is no app to bring to the front.
    @discardableResult
    func goToAgent(_ identity: ProcessIdentity, else fallback: Int32? = nil) -> Bool {
        guard let hosts else { return false }
        let reading = decision.perAgent.map(\.reading).first { $0.identity == identity }
        let found = reading.flatMap { hosts.hosts(of: [($0.identity.pid, $0.kind)]).first ?? nil }
        if let app = found?.appPid ?? fallback, hosts.bringForward(app: app) { return true }
        // The row is no button any more.
        refreshAgentHosts()
        return false
    }

    // MARK: Open at login

    /// Called at launch and when Settings opens: the user can change it
    /// in System Settings at any time.
    func refreshLoginItem() {
        loginItem = LoginItemState.state(status: loginItemService.status, inApplications: canSetUpHelper)
    }

    func setOpenAtLogin(_ on: Bool) {
        // macOS refuses to register what is registered already.
        guard loginItem != .unavailable, loginItem != (on ? .on : .off) else { return }
        do {
            if on {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }

    // MARK: Pause

    /// Nothing to pause while Agent Caffeine is off. A pause ends "stay
    /// reachable". See `TimedModes`.
    func startPause(_ choice: PauseChoice) {
        guard enabled else { return }
        var next = TimedModes(pause: pause, reachable: reachable)
        next.startPause(choice, now: Date(), calendar: .current)
        (reachable, pause) = (next.reachable, next.pause)
    }

    /// Not while Agent Caffeine is off. "Stay reachable" ends a pause.
    func startReachable(_ choice: ReachableChoice) {
        guard enabled else { return }
        var next = TimedModes(pause: pause, reachable: reachable)
        next.startReachable(choice, now: Date())
        (pause, reachable) = (next.pause, next.reachable)
    }

    /// "Stop" on the line of a hold from the command line. The file goes,
    /// and the sample that follows lets go. A command that holds runs on.
    func stopHold(id: String) {
        holdStore.remove(id: id)
        engine.requestSample()
    }

    /// "Stop" on the line of a job hold of "Wake for jobs". The job
    /// itself runs on.
    func stopJobHold(id: String) {
        jobLoop.stopHold(id: id)
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
            // A default of another action gives way, so it does not count.
            let others = shortcutChoices.recorded.filter { $0.key != action }.map(\.value)
            if let problem = ShortcutRules.problem(shortcut, system: hotKeys.systemShortcuts, others: others) {
                shortcutProblems[action] = problem
                return
            }
        }
        shortcutChoices.set(shortcut, for: action)
        shortcutsChanged()
    }

    /// Back to the default shortcut of the action.
    func resetShortcut(for action: ShortcutAction) {
        shortcutChoices.reset(action)
        shortcutsChanged()
    }

    /// All of them: a change of one can take or give back the default of
    /// the other.
    private func shortcutsChanged() {
        ShortcutStore.save(shortcutChoices, to: defaults)
        registerShortcuts()
    }

    /// While Preferences records a shortcut, none of them is registered.
    func setShortcutRecording(_ recording: Bool) {
        recordingShortcut = recording
        if recording {
            hotKeys.unregisterAll()
            shortcutProblems = [:]
        } else {
            registerShortcuts()
        }
    }

    /// The letter of a default shortcut stands on another key now, so the
    /// default moves there. A shortcut the user recorded stays on its key.
    private func keyLayoutChanged() {
        let resolved = ShortcutDefaults.resolve(in: keyLayouts())
        guard resolved != shortcutChoices.defaults else { return }
        shortcutChoices.defaults = resolved
        // The end of the recording registers them.
        if !recordingShortcut { registerShortcuts() }
    }

    private func registerShortcuts() {
        ShortcutAction.allCases.forEach(register)
    }

    private func register(_ action: ShortcutAction) {
        // A default that macOS uses is not registered. Preferences says why.
        let problem = shortcutChoices.defaultProblem(for: action, system: hotKeys.systemShortcuts)
        let registered = hotKeys.register(problem == nil ? shortcuts[action] : nil, for: action) { [weak self] in
            switch action {
            case .toggle: self?.toggleEnabled()
            case .pauseOneHour: self?.startPause(.oneHour)
            }
        }
        shortcutProblems[action] = problem ?? (registered ? nil : .usedByAnotherApp)
    }

    // MARK: Engine

    private func apply(_ decision: HoldDecision) {
        // A rule for agents ended a hold, and nothing else keeps the Mac
        // awake: the user is told why. Not while another hold goes on:
        // the Mac is not let go then.
        if self.decision.hold, case .agentsStopped(let stop) = decision.headline {
            let working = decision.working(settings)
            switch stop {
            case .offline:
                testNotices.note(.offline, at: Date())
                notify(PanelText.offlineNotice(limit: engine.offlineRule.limit ?? 0, working: working))
            case .closedLid(let stop):
                testNotices.note(.closedLidLimit, at: Date())
                notify(PanelText.closedLidNotice(stop, working: working))
            }
        }
        self.decision = decision
        refreshRows()
        writeHoldStatus()
        updatePower()
        syncSleepFlag()
        // A stop gives the brightness back at once, not at the next sample.
        display?.update(holding: decision.hold, now: Date())
        writeTestState()
    }

    private func sampled(_ sample: DetectionSample) {
        samples += 1
        let context = sample.frame.context
        if sessionHints != sample.sessionHints { sessionHints = sample.sessionHints }
        if hasBattery != (context.batteryPercent != nil) { hasBattery = context.batteryPercent != nil }
        if onBattery != context.onBattery { onBattery = context.onBattery }
        if batteryPercent != context.batteryPercent { batteryPercent = context.batteryPercent }
        // The limits are read at each sample: the tests set one with a
        // hidden default while the app runs.
        let limits = settings.closedLidLimits(testSeconds: ClosedLidLimit.testSeconds(in: defaults))
        closedLidLimit.timeLimit = limits.time
        closedLidLimit.dropLimit = limits.drop
        engine.offlineTestSeconds = OfflineRule.testSeconds(in: defaults)
        // Whoever holds: the battery does not care. The stop is for the
        // agents alone, and `apply` tells the user when it ends a hold.
        let lidStop = closedLidLimit.update(context, holding: power.held, at: sample.frame.time, afterGap: sample.afterGap)
        let stop = safetyMonitor.update(context.safetyInputs, afterGap: sample.afterGap)
        if let begun = SafetyStop.toAnnounce(previous: engine.safety, current: stop, wasHolding: power.held) {
            testNotices.note(.safetyStop, at: sample.frame.at)
            notify(begun.notificationText)
        }
        let warned = noLimitWarning.update(
            context.safetyInputs, drainingOnPower: safetyMonitor.drainingOnPower, floorEnabled: settings.batteryFloorEnabled, holding: power.held
        )
        if let percent = warned {
            testNotices.note(.batteryWarning, at: sample.frame.at)
            notify(NoLimitBatteryWarning.notificationText(percent: percent))
        }
        engine.safety = stop
        engine.closedLidStop = lidStop
        // The power source, the battery and a stop move the wake alarm.
        updateJobWake()
        sleepFlag.sampleCompleted()
        // The notification above says why. The time does not come back
        // with the power.
        if stop != nil, reachable.until != nil {
            var next = TimedModes(pause: pause, reachable: reachable)
            next.safetyStopped()
            reachable = next.reachable
        }
        announceHiddenNotice()
        updateMacSleep(context, at: sample.frame.at)
        announceAgents(sample)
        // After the hold of this sample is applied and its flag asked for.
        if sample.afterGap { lidChimer.forget() }
        observeLidForChime(lidClosed: context.lidClosed, onBattery: context.onBattery)
        // The hold of the decision as it is now: a stop from this sample
        // is in it.
        display?.update(
            lidClosed: context.lidClosed, holding: decision.hold, enabled: settings.displayOffLidClosed,
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
        writeTestState()
    }

    /// The lid and the power source come with the sample. The sleep timer
    /// of macOS is read on a queue of its own, when the power source
    /// changes and every half minute, and is in the state one sample later.
    private func updateMacSleep(_ context: FrameContext, at now: Date) {
        if let sleepTimer {
            let last = sleepTimerRead
            if last?.onBattery != context.onBattery || now.timeIntervalSince(last?.at ?? .distantPast) >= Self.sleepTimerRefreshInterval {
                let onBattery = context.onBattery
                // Kept until the answer comes, unless it is for the other
                // power source.
                sleepTimerRead = (onBattery, now, last?.onBattery == onBattery ? last?.minutes : nil)
                sleepTimerQueue.async { [weak self] in
                    let minutes = sleepTimer.sleepTimerMinutes(onBattery: onBattery)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, self.sleepTimerRead?.onBattery == onBattery else { return }
                            self.sleepTimerRead?.minutes = minutes
                        }
                    }
                }
            }
        }
        let others = assertions?.assertingPIDs().subtracting([ProcessInfo.processInfo.processIdentifier]) ?? []
        let state = MacSleepState(
            lidClosed: context.lidClosed, onBattery: context.onBattery, flagInUse: sleepFlag.sleepDisabled,
            sleepTimerMinutes: sleepTimerRead?.minutes, otherAppHolds: !others.isEmpty
        )
        if macSleep != state { macSleep = state }
    }

    /// With the icon hidden, the menu's word that Agent Caffeine cannot do
    /// its work reaches nobody, so it is told once as a notification.
    private func announceHiddenNotice() {
        let current = HiddenNotice.current(
            flagLeftOn: sleepFlag.flagLeftOn,
            helperNotResponding: MenuModel.helperNotResponding(
                notResponding: sleepFlag.setup == .notResponding, wanted: settings.stayAwakeLidClosedOnBattery, hasBattery: hasBattery
            )
        )
        if let begun = HiddenNotice.toAnnounce(previous: hiddenNotice, current: current, iconHidden: !showMenuBarIcon) {
            testNotices.note(.hidden, at: Date())
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
            active: enabled && pause.until == nil
        )
        // For the whole Mac at this moment, as the menu says it.
        let outlook = SleepOutlook(sample.decision, mac: macSleep, now: sample.frame.at)
        let told = agentNotices.update(input, now: sample.frame.at)
        var history = noticeHistory
        for decision in agentNotices.decisions {
            Notifier.log.notice("\(decision.logLine, privacy: .public)")
            history.note(decision, at: sample.frame.at)
        }
        for notice in told {
            if notice.kind == .waiting { Notifier.log.notice("\(outlook.logLine, privacy: .public)") }
            let content = AgentNoticeText.content(notice, outlook: outlook, now: sample.frame.at)
            history.posted(content, at: sample.frame.at)
            testNotices.note(notice.kind == .waiting ? .waiting : .finished, at: sample.frame.at)
            notifier.post(content)
        }
        if noticeHistory != history { noticeHistory = history }
    }

    /// Called when Preferences opens: the user can change the permission
    /// in System Settings at any time.
    func refreshNotificationPermission() {
        notifier?.readPermission()
    }

    func openNotificationSettings() {
        notifier?.openSystemSettings()
    }

    // MARK: Lid chime

    /// The lid or the displays changed: the lid is read here and now, so
    /// the sound comes with the lid and not with the next sample.
    private func lookAtLidForChime() {
        let context = powerContext.context()
        observeLidForChime(lidClosed: context.lidClosed, onBattery: context.onBattery)
    }

    /// The sound that says the Mac stays awake with the lid closed. While
    /// the helper's answer is still to come, the state is looked at again
    /// a few times, for no longer than `LidChime.confirmationWait`.
    private func observeLidForChime(lidClosed: Bool, onBattery: Bool) {
        let inputs = LidChimeInputs(
            lidClosed: lidClosed, enabled: settings.chimeOnLidClose, holding: decision.hold && power.held, onBattery: onBattery,
            flagWanted: decision.lidClosedFlag, helperEnabled: sleepFlag.helperStatus == .enabled, flagConfirmed: sleepFlag.sleepDisabled
        )
        if lidChimer.observe(inputs, sound: settings.lidChimeSound, detail: decision.headline.text, now: Self.uptime) == .played {
            chimePlayedAt = Date()
        }
        guard lidChimer.isWaiting != (lidChimeTimer != nil) else { return }
        lidChimeTimer?.invalidate()
        lidChimeTimer = nil
        guard lidChimer.isWaiting else { return }
        let timer = Timer(timeInterval: Self.lidChimeLookInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookAtLidForChime() }
        }
        RunLoop.main.add(timer, forMode: .common)
        lidChimeTimer = timer
    }

    /// "Play" in Preferences.
    func playLidChime() {
        lidChimer.preview(settings.lidChimeSound)
    }

    /// What `status` of the command line tool says. Only the copy that
    /// holds the lock writes it.
    private func writeHoldStatus() {
        guard holdLock != nil else { return }
        let headline = PanelText.headline(decision.headline)
        holdStatus.write(HoldStore.Status(
            awake: decision.hold, line: "\(headline.title): \(headline.subtitle)", stopped: decision.headline.isStop
        ))
    }

    /// What the test runner reads. Only the copy that holds the lock
    /// writes it, and only while the hidden switch is on. A timer keeps
    /// the file young between two samples.
    private func writeTestState() {
        guard holdLock != nil else { return }
        testState.update { TestState(testStateInput) }
        guard testState.isOn != (testStateTimer != nil) else { return }
        testStateTimer?.invalidate()
        testStateTimer = nil
        guard testState.isOn else { return }
        let timer = Timer(timeInterval: Self.testStateInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeTestState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        testStateTimer = timer
    }

    private var testStateInput: TestStateInput {
        let info = Bundle.main.infoDictionary
        return TestStateInput(
            at: Date(),
            version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown",
            bundlePath: AppInstall.running.path,
            pid: ProcessInfo.processInfo.processIdentifier,
            enabled: enabled, pausedUntil: pause.until, reachableUntil: reachable.until, mode: mode,
            decision: decision, frame: engine.frame, assertionHeld: power.held,
            helper: sleepFlag.helperStatus, setup: sleepFlag.setup, flagSet: sleepFlag.sleepDisabled,
            lidAngle: display?.lidAngle, safety: engine.safety, closedLid: closedLidLimit, offline: engine.offlineRule, gate: engine.gateCode,
            wakeForJobs: jobSettings.wakeForJobs, jobs: jobWake, notices: testNotices.events, chimeAt: chimePlayedAt
        )
    }

    private func updatePower() {
        if decision.hold, let reason = decision.headline.awakeReason {
            power.hold(reason: "Agent Caffeine: \(reason)")
        } else {
            power.release()
        }
    }

    /// The folder of each session that works or waits, so the menu can tell
    /// two sessions of one agent apart. It is shown only, never logged.
    /// The Claude app has a process for each session of its Code tab.
    private func refreshRows() {
        let readings = decision.perAgent.map(\.reading)
        var next: [ProcessIdentity: String] = [:]
        for reading in readings where reading.verdict.state != .idle && (reading.kind == .cli || reading.agentID == AgentCatalog.claudeDesktopID) {
            next[reading.identity] = sessionLabels[reading.identity]
                ?? MenuModel.sessionLabel(workingDirectory: openFiles.workingDirectory(of: reading.identity.pid))
        }
        if sessionLabels != next { sessionLabels = next }
        let clock = stateClock.updated(with: readings, now: Date())
        if stateClock != clock { stateClock = clock }
        refreshAgentHosts(again: false)
    }

    // MARK: Helper

    /// Called when the menu or Preferences opens, and on a timer.
    func refreshHelperStatus() {
        lastHelperRefresh = Date()
        sleepFlag.refreshStatus()
        syncSleepFlag()
        updateJobWake()
    }

    /// The controller's heartbeat keeps the flag alive, so the helper is
    /// called only when the wanted value changes, and again after a call
    /// that did not get through.
    private func syncSleepFlag() {
        // Whatever the helper's state is: a helper that is not enabled gets
        // no request below, and its heartbeats must stop all the same.
        if !decision.lidClosedFlag { sleepFlag.stopWanting() }
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

    /// No wake alarm stays behind a helper that is removed.
    func removeHelper() {
        runHelperAction {
            self.jobLoop.cancelNow()
            try await self.sleepFlag.uninstall()
        }
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
            updateJobWake()
        }
    }

    // MARK: Wake for jobs

    /// The jobs are read only while the feature is on, so nothing of the
    /// crontab or the launchd agents is looked at before the user asks.
    private func syncJobStore() {
        guard let jobStore else { return }
        if jobSettings.wakeForJobs {
            jobStore.start { [weak self] readings in
                MainActor.assumeIsolated {
                    guard let self, self.jobSettings.wakeForJobs else { return }
                    self.jobReadings = readings
                    // A switch never waits for a line that can be another
                    // command tomorrow.
                    let kept = self.jobLoop.forgetSwitches(ofUnclear: readings.flatMap(\.jobs), in: self.jobSettings)
                    if kept != self.jobSettings { self.jobSettings = kept }
                    self.updateJobWake()
                }
            }
        } else {
            jobStore.stop()
            jobReadings = []
        }
    }

    /// The user closed the line that says a switch went off by itself,
    /// or changed a switch of a job.
    func closeJobSwitchNotice() {
        jobLoop.closeSwitchNotice()
    }

    /// Called when Settings opens: the crontab has no file to watch.
    func refreshJobs() {
        if jobSettings.wakeForJobs { jobStore?.refresh() }
    }

    /// What the loop is told. Only the copy in the Applications folder
    /// sends an alarm: the helper takes calls from that copy alone.
    private var jobWakeInput: JobWakeInput {
        JobWakeInput(
            readings: jobReadings, settings: jobSettings,
            context: JobPlanContext(
                enabled: enabled, pausedUntil: pause.until, safety: engine.safety,
                onBattery: onBattery, batteryPercent: batteryPercent,
                batteryFloorEnabled: settings.batteryFloorEnabled, batteryFloorPercent: settings.batteryFloorPercent
            ),
            inApplications: AppInstall.running.isStableInstall, helperEnabled: sleepFlag.helperStatus == .enabled
        )
    }

    /// One turn of the loop: on every change of what it is told, and
    /// with every sample, which also renews the lease of the alarm. Not
    /// before the first sample: until then the power source and the
    /// battery are not known, and an alarm could be set on battery.
    /// - Parameter powerNow: the power source and the battery are read
    ///   now and not taken from the last sample. For the turn of the
    ///   timer: at the alarm the Mac may have been unplugged while it
    ///   slept, and no sample has seen that yet.
    private func updateJobWake(powerNow: Bool = false) {
        guard samples > 0 else { return }
        jobLoop.run(powerNow ? jobWakeInput.withPower(of: powerContext.context()) : jobWakeInput)
    }

    /// The job holds go to the engine, where `HoldPolicy` decides what
    /// they are worth, and the timer is set for the next turn.
    private func jobWakeChanged() {
        if jobWake != jobLoop.view { jobWake = jobLoop.view }
        engine.wakeAlarm = jobLoop.view.alarm?.at
        engine.jobHolds = jobLoop.holds
        armJobTimer()
    }

    /// At the time of the alarm and at the end of each hold. A timer
    /// whose time passed while the Mac slept fires when it wakes, so the
    /// hold opens with the wake and not with the next sample.
    private func armJobTimer() {
        jobTimer?.invalidate()
        jobTimer = nil
        guard let next = jobLoop.nextTurn else { return }
        let timer = Timer(fire: next.addingTimeInterval(Self.jobTimerSlack), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateJobWake(powerNow: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        jobTimer = timer
    }

    // MARK: Hooks

    /// The hook entries point at the copy in the Applications folder, so
    /// they are offered only when the hook command is there.
    var hooksAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: HookCatalog.executablePath(appPath: AppInstall.running.stablePath))
    }

    /// At launch: see `HookInstaller.updateOwnFiles`. Only the copy in the
    /// Applications folder does it, because the files point at its hook
    /// command, and never the smoke test.
    private func updateOwnHookFiles() {
        guard !SmokeTest.isActive, AppInstall.running.isStableInstall else { return }
        hookInstaller.updateOwnFiles()
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

    // MARK: Set up for agents

    /// At launch: see `SkillInstaller.updateOwn`. Only the copy in the
    /// Applications folder does it, so a build that runs from another
    /// folder never moves the link, and never the smoke test.
    private func updateOwnSkill() {
        guard !SmokeTest.isActive, AppInstall.running.isStableInstall else { return }
        skillInstaller?.updateOwn()
    }

    /// Only reads. `errors` nil keeps the ones that are shown.
    func refreshAgentSetup(errors: [String: String]? = nil) {
        guard let skillInstaller else {
            agentSetup = AgentSetupModel(available: false)
            return
        }
        var next = agentSetup
        next.snapshot = skillInstaller.snapshot()
        next.errors = errors ?? next.errors
        agentSetup = next
        checkShellPath()
    }

    /// Once per launch, when the link is there, and off the main thread:
    /// it reads the files of the login shell. See `ShellPath`.
    private func checkShellPath() {
        guard agentSetup.isLinked, !askedForShellPath, !SmokeTest.isActive else { return }
        askedForShellPath = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let shell = ShellPath.loginShell()
            let onPath = shell.flatMap { ShellPath.localBinIsOnPath(shell: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                var next = self.agentSetup
                next.localBinOnPath = onPath
                next.startupFile = shell.flatMap(ShellPath.startupFile)
                self.agentSetup = next
            }
        }
    }

    /// True when nothing went wrong.
    @discardableResult
    func setUpForAgents() -> Bool {
        guard let skillInstaller else { return false }
        let errors = skillInstaller.setUp()
        refreshAgentSetup(errors: errors)
        return errors.isEmpty
    }

    func installSkill(for entry: SkillCatalogEntry) {
        guard let skillInstaller else { return }
        var errors = agentSetup.errors
        do {
            try skillInstaller.install(for: entry)
            errors[entry.id] = nil
        } catch {
            var place = entry.places[0]
            switch agentSetup.snapshot.agents.first(where: { $0.id == entry.id })?.status {
            case .outdated(let known), .foreign(let known): place = known
            case .installed, .notInstalled, nil: break
            }
            errors[entry.id] = (error as? SkillInstallError ?? .writeFailed).message(place: place)
        }
        refreshAgentSetup(errors: errors)
    }

    func linkTool() {
        guard let skillInstaller else { return }
        var errors = agentSetup.errors
        do {
            try skillInstaller.link()
            errors[SkillInstaller.linkKey] = nil
        } catch {
            errors[SkillInstaller.linkKey] = (error as? SkillInstallError ?? .writeFailed).linkMessage
        }
        refreshAgentSetup(errors: errors)
    }

    func removeAgentSetup() {
        guard let skillInstaller else { return }
        refreshAgentSetup(errors: skillInstaller.removeAll())
    }

    // MARK: Quit

    // Safe to call more than once. The sleep flag is cleared before this
    // returns, or the wait for the helper ran out.
    func shutdown() {
        engine.stop()
        pauseTimer?.invalidate()
        reachableTimer?.invalidate()
        lidChimeTimer?.invalidate()
        jobTimer?.invalidate()
        testStateTimer?.invalidate()
        jobStore?.stop()
        hotKeys.unregisterAll()
        display?.stop()
        // An app that does not run wakes the Mac for nothing.
        jobLoop.cancelNow()
        sleepFlag.clearForQuit(timeout: 2)
        power.release()
        if holdLock != nil {
            holdStatus.remove()
            testState.remove()
            holdLock = nil
        }
        if let napActivity {
            ProcessInfo.processInfo.endActivity(napActivity)
            self.napActivity = nil
        }
    }
}
