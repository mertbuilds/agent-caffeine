import SwiftUI

/// The measures of the menu, on a 4 point grid.
enum PanelMetrics {
    static let width: CGFloat = 320
    static let gutter: CGFloat = 16
    /// The side of the tile the robot sits on.
    static let robotSize: CGFloat = 96
    /// The rounded box behind an agent's mark.
    static let logoBox: CGFloat = 28
    static let logoBoxRadius: CGFloat = 8
    static let logoPadding: CGFloat = 5
    /// Between the box and the ring that shows work.
    static let ringGap: CGFloat = 3
    static let ringWidth: CGFloat = 1.5
    static let activeRowHeight: CGFloat = 44
    static let idleRowHeight: CGFloat = 36
    /// A session below the name of its agent.
    static let childRowHeight: CGFloat = 24
    /// With the state on a line of its own.
    static let childTwoLineHeight: CGFloat = 40
    /// Between a session's name and its state on one line.
    static let childGap: CGFloat = 12
    /// The slot of the chevron of a group that opens.
    static let chevronWidth: CGFloat = 10
    /// Below the last session of an open group.
    static let childrenBottom: CGFloat = 4
    /// The list scrolls when it is taller.
    static let listMaxHeight: CGFloat = 300
    static let controlHeight: CGFloat = 28

    /// The ring's slot, which also holds the box.
    static var logoSlot: CGFloat { logoBox + 2 * ringGap }
    /// From the leading edge of an agent's name to the trailing edge of the list.
    static var childWidth: CGFloat { width - 2 * (gutter - ringGap) - logoSlot - 8 }
    /// Nested corners share one centre.
    static var ringRadius: CGFloat { logoBoxRadius + ringGap }

    static let stateChange = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let waitingAmber = Color(red: 0.96, green: 0.62, blue: 0.04)
}
