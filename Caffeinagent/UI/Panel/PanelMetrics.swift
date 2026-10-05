import SwiftUI

/// The measures of the menu, on a 4 point grid.
enum PanelMetrics {
    static let width: CGFloat = 320
    static let gutter: CGFloat = 16
    static let robotSize: CGFloat = 92
    /// The rounded box behind an agent's mark.
    static let logoBox: CGFloat = 28
    static let logoBoxRadius: CGFloat = 8
    static let logoPadding: CGFloat = 5
    /// Between the box and the ring that shows work.
    static let ringGap: CGFloat = 3
    static let ringWidth: CGFloat = 1.5
    static let activeRowHeight: CGFloat = 44
    static let idleRowHeight: CGFloat = 36
    /// The list scrolls when it is taller.
    static let listMaxHeight: CGFloat = 300
    static let controlHeight: CGFloat = 28

    /// The ring's slot, which also holds the box.
    static var logoSlot: CGFloat { logoBox + 2 * ringGap }
    /// Nested corners share one centre.
    static var ringRadius: CGFloat { logoBoxRadius + ringGap }

    static let stateChange = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let waitingAmber = Color(red: 0.96, green: 0.62, blue: 0.04)
}
