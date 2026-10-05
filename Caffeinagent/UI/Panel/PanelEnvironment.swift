import SwiftUI

private struct PanelIsOpenKey: EnvironmentKey {
    static let defaultValue = true
}

private struct PanelFrozenTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
    /// False while the menu is closed, so nothing in it keeps a timer.
    var panelIsOpen: Bool {
        get { self[PanelIsOpenKey.self] }
        set { self[PanelIsOpenKey.self] = newValue }
    }

    /// A fixed moment of the motion, for a still picture of it.
    var panelFrozenTime: TimeInterval? {
        get { self[PanelFrozenTimeKey.self] }
        set { self[PanelFrozenTimeKey.self] = newValue }
    }
}
