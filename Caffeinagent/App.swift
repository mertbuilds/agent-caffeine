import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.onTerminate?()
    }
}

@main
struct CaffeinagentApp: App {
    @StateObject private var aggregator = StateAggregator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(aggregator: aggregator)
                .onAppear { wireShutdown() }
        } label: {
            MenuBarLabel(state: aggregator.globalState, enabled: aggregator.enabled, held: aggregator.assertionHeld)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(aggregator: aggregator)
        }
    }

    private func wireShutdown() {
        let agg = aggregator
        AppDelegate.onTerminate = { agg.shutdown() }
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
