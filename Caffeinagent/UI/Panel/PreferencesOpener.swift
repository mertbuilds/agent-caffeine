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
        PreferencesWindow.bringFront()
    }
}

/// The window of the Settings scene.
enum PreferencesWindow {
    /// Opens Preferences with no view to ask: from the app delegate, when
    /// the user opens the app again.
    @MainActor
    static func show() {
        if #available(macOS 14.0, *) {
            SettingsAction.open()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        bringFront()
    }

    /// Seconds between the tries of `bringFront`.
    static let tries: [TimeInterval] = [0, 0.1, 0.3]

    /// Makes Preferences the key window of the active app. A window that
    /// is not key draws its switches grey. The window can be made a turn of
    /// the run loop later, and the menu that closes can take the key state
    /// back, so this asks again until the window is key.
    static func bringFront(try index: Int = 0) {
        guard index < tries.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + tries[index]) {
            let window = NSApp.windows.first {
                $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
            }
            if index > 0, NSApp.isActive, window?.isKeyWindow == true { return }
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
            bringFront(try: index + 1)
        }
    }
}
