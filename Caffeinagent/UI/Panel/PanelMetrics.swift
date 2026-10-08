import SwiftUI

/// The measures of the menu, on a 4 point grid.
enum PanelMetrics {
    static let width: CGFloat = 320
    static let gutter: CGFloat = 16
    /// The side of the tile the robot sits on.
    static let robotSize: CGFloat = 56
    /// Between the tile and the headline next to it.
    static let robotGap: CGFloat = 12
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
    /// Under the pointer, a line that goes to its agent: the fill, how far
    /// it reaches into the gutter, and its corners.
    static let rowHoverOpacity = 0.07
    static let rowHoverOutset: CGFloat = 5
    static let rowHoverRadius: CGFloat = 12
    static let childHoverRadius: CGFloat = 6
    /// The list scrolls when it is taller.
    static let listMaxHeight: CGFloat = 300
    static let controlHeight: CGFloat = 28
    /// The body of the battery mark, without its cap.
    static let batteryGlyph = CGSize(width: 20, height: 10)
    /// Between the subtitle and the line of the battery.
    static let batteryLineTop: CGFloat = 4
    /// How far the mark hangs below the baseline of its line.
    static let batteryGlyphDrop: CGFloat = 1

    /// The ring's slot, which also holds the box.
    static var logoSlot: CGFloat { logoBox + 2 * ringGap }
    /// From the leading edge of an agent's name to the trailing edge of the list.
    static var childWidth: CGFloat { width - 2 * (gutter - ringGap) - logoSlot - 8 }
    /// Nested corners share one centre.
    static var ringRadius: CGFloat { logoBoxRadius + ringGap }

    static func disclosure(opening: Bool) -> Animation { opening ? disclose : conceal }

    static let stateChange = Animation.spring(response: stateChangeSpring.response, dampingFraction: stateChangeSpring.dampingFraction)
    /// The same spring for the layers Core Animation moves.
    static let stateChangeSpring: (response: Double, dampingFraction: Double) = (0.35, 0.86)
    /// A part that opens below its header, and one that closes a little faster.
    static let disclose = Animation.easeOut(duration: 0.26)
    static let conceal = Animation.easeInOut(duration: 0.22)
    static let waitingAmber = Color(red: 0.96, green: 0.62, blue: 0.04)
}
