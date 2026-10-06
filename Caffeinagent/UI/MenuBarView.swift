import AppKit
import SwiftUI

/// The menu of the running app: the panel over the aggregator's state.
struct MenuBarView: View {
    @ObservedObject var aggregator: StateAggregator
    @State private var isOpen = false

    var body: some View {
        PreferencesOpener { openPreferences in
            PanelClock(isOpen: isOpen) { now in
                PanelView(
                    state: MenuModel.state(aggregator.panelInput, now: now),
                    enabled: $aggregator.enabled,
                    mode: $aggregator.mode,
                    busy: aggregator.license.busy,
                    perform: { perform($0, openPreferences: openPreferences) },
                    openPreferences: openPreferences,
                    quit: { NSApp.terminate(nil) }
                )
            }
        }
        .environment(\.panelIsOpen, isOpen)
        .background(WindowVisibility(isVisible: $isOpen))
        .onAppear(perform: aggregator.refreshHelperStatus)
        .onChange(of: isOpen) { open in
            if open { aggregator.refreshHelperStatus() }
        }
    }

    private func perform(_ action: PanelAction, openPreferences: () -> Void) {
        let license = aggregator.license
        switch action {
        case .openLoginItems:
            aggregator.sleepFlag.openLoginItemsSettings()
        case .tryHelperAgain:
            aggregator.repairHelper()
        case .buy:
            NSWorkspace.shared.open(license.config.checkoutURL)
        case .enterKey:
            aggregator.preferencesTab = .license
            openPreferences()
        case .checkLicense:
            Task { await license.checkNow() }
        case .activateAgain:
            guard let key = license.record.key else { return }
            Task { await license.activate(key: key) }
        case .setUpLidClosed:
            aggregator.preferencesTab = .lidClosed
            openPreferences()
        case .dismissLidClosedHint:
            aggregator.lidClosedHintDismissed = true
        case .pause(let choice):
            aggregator.startPause(choice)
        case .resume:
            aggregator.resumeNow()
        case .stayReachable(let choice):
            aggregator.startReachable(choice)
        case .stopReachable:
            aggregator.stopReachable()
        }
    }
}
