import SwiftUI

@main
struct CaffeinagentApp: App {
    @StateObject private var aggregator = StateAggregator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(aggregator: aggregator)
        } label: {
            MenuBarLabel(state: aggregator.globalState, enabled: aggregator.enabled, held: aggregator.assertionHeld)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(aggregator: aggregator)
        }
    }
}

struct MenuBarLabel: View {
    let state: AgentState
    let enabled: Bool
    let held: Bool

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        guard enabled else { return "cup.and.saucer" }
        if held { return "cup.and.saucer.fill" }
        switch state {
        case .active: return "cup.and.saucer.fill"
        case .waitingForInput: return "cup.and.saucer"
        case .idle: return "cup.and.saucer"
        }
    }
}
