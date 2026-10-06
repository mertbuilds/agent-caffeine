import AppKit
import SwiftUI

@available(macOS 14.0, *)
struct ModernPreferencesOpener<Content: View>: View {
    @ViewBuilder let content: (@escaping () -> Void) -> Content
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        content {
            openSettings()
            PreferencesOpener<Content>.bringSettingsFront()
        }
    }
}

/// The `openSettings` action outside the scenes. Only a view can read it
/// from the environment, so a view that is never shown reads it.
@available(macOS 14.0, *)
@MainActor
enum SettingsAction {
    private static var action: OpenSettingsAction?
    private static var host: NSView?

    static func open() {
        if action == nil {
            let host = NSHostingView(rootView: Reader { action = $0 })
            // The body runs when the view is laid out.
            _ = host.fittingSize
            host.layoutSubtreeIfNeeded()
            self.host = host
        }
        action?()
    }

    private struct Reader: View {
        @Environment(\.openSettings) private var openSettings
        let read: (OpenSettingsAction) -> Void

        var body: some View {
            let _ = read(openSettings)
            Color.clear
        }
    }
}
