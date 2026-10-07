import AppKit

/// The tooltip of the item in the menu bar: the state in words, the same
/// that VoiceOver reads. The menu bar scene gives its status item no
/// tooltip, so it is set on the button, which AppKit keeps in a window of
/// its own.
@MainActor
enum MenuBarToolTip {
    static func update(_ aggregator: StateAggregator) {
        let input = aggregator.panelInput
        let text = MenuModel.menuBarAccessibilityLabel(input) ?? MenuBarLook(pose: MenuModel.pose(input)).accessibilityLabel
        guard let button, button.toolTip != text else { return }
        button.toolTip = text
    }

    private static var button: NSStatusBarButton? {
        NSApp.windows.lazy
            .filter { String(describing: type(of: $0)).contains("StatusBar") }
            .compactMap { firstButton(in: $0.contentView) }
            .first
    }

    private static func firstButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(firstButton).first
    }
}
