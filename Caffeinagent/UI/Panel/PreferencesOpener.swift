import AppKit
import SwiftUI

/// Gives its content a way to open Preferences. The `openSettings`
/// environment action is macOS 14+; the legacy responder-chain selector
/// still works on 13 but stopped opening the SwiftUI Settings scene on
/// newer macOS.
struct PreferencesOpener<Content: View>: View {
    @ViewBuilder let content: (@escaping () -> Void) -> Content

    var body: some View {
        if #available(macOS 14.0, *) {
            ModernPreferencesOpener(content: content)
        } else {
            content {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                Self.bringSettingsFront()
            }
        }
    }

    static func bringSettingsFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
            }) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}
