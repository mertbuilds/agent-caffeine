import Foundation
import Combine
import os

@MainActor
final class StateAggregator: ObservableObject {
    @Published private(set) var globalState: AgentState = .idle
    @Published private(set) var allAgents: [DetectedAgent] = []
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            updateAssertion()
        }
    }

    let claude: ClaudeCodeWatcher
    let processes: ProcessWatcher
    private let power = PowerKeeper()
    private var cancellables = Set<AnyCancellable>()
    private static let enabledKey = "StateAggregator.enabled"
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "StateAggregator")

    init() {
        let claude = ClaudeCodeWatcher()
        let processes = ProcessWatcher()
        self.claude = claude
        self.processes = processes
        self.enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true

        Publishers.CombineLatest(claude.$agents, processes.$agents)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] claudeAgents, procAgents in
                self?.recompute(claude: claudeAgents, processes: procAgents)
            }
            .store(in: &cancellables)
    }

    var assertionHeld: Bool { power.held }

    private func recompute(claude: [DetectedAgent], processes: [DetectedAgent]) {
        let combined = claude + processes
        allAgents = combined.sorted { $0.lastActivity > $1.lastActivity }
        globalState = combined.map(\.state).max() ?? .idle
        updateAssertion()
    }

    private func updateAssertion() {
        guard enabled else {
            power.release()
            return
        }
        if globalState == .active {
            power.acquire(reason: "caffeinagent: agent active")
        } else {
            power.release()
        }
    }
}
