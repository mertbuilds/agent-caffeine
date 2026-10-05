import AppKit
import Combine
import os

@MainActor
final class StateAggregator: ObservableObject {
    @Published private(set) var allAgents: [DetectedAgent] = []
    @Published private(set) var onBattery = PowerSource.isOnBattery()
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            updateAssertion()
        }
    }
    @Published var mode: AwakeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            updateAssertion()
        }
    }
    @Published private(set) var assertionHeld = false

    let claude: ClaudeCodeWatcher
    let processes: ProcessWatcher
    let battery: BatteryOverride
    private let power = PowerKeeper()
    private var cancellables = Set<AnyCancellable>()
    private var sigtermSource: DispatchSourceSignal?
    private static let enabledKey = "StateAggregator.enabled"
    private static let modeKey = "StateAggregator.mode"
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "StateAggregator")

    init() {
        let claude = ClaudeCodeWatcher()
        let processes = ProcessWatcher()
        let battery = BatteryOverride()
        self.claude = claude
        self.processes = processes
        self.battery = battery
        self.enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        self.mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(AwakeMode.init(rawValue:)) ?? .agentWorking

        Publishers.CombineLatest(claude.$agents, processes.$agents)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] claudeAgents, procAgents in
                self?.recompute(claude: claudeAgents, processes: procAgents)
            }
            .store(in: &cancellables)

        // The menu reads battery state, and Preferences the allowlist, through
        // this object.
        battery.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        processes.objectWillChange
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
    }

    var shouldHold: Bool { mode.shouldHold(enabled: enabled, agents: allAgents) }

    private func recompute(claude: [DetectedAgent], processes: [DetectedAgent]) {
        let sorted = (claude + processes).sorted { $0.lastActivity > $1.lastActivity }
        if allAgents != sorted { allAgents = sorted }
        let battery = PowerSource.isOnBattery()
        if onBattery != battery { onBattery = battery }
        updateAssertion()
    }

    private func updateAssertion() {
        if shouldHold {
            power.acquire(reason: "caffeinagent: \(mode.rawValue)")
            battery.setEnabled(PowerSource.isOnBattery())
        } else {
            power.release()
            battery.setEnabled(false)
        }
        if assertionHeld != power.held { assertionHeld = power.held }
    }

    // Safe to call more than once. pmset runs synchronously, so the override
    // is off before this returns.
    func shutdown() {
        battery.setEnabled(false)
        power.release()
        assertionHeld = false
    }
}
