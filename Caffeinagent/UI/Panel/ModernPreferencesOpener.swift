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
