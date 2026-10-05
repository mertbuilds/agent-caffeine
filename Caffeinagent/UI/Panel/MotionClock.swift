import SwiftUI

/// Gives its content the time of the looping motion, 60 times a second,
/// only while the menu is open and motion is allowed. Otherwise the time
/// is nil and the content holds a still pose.
struct MotionClock<Content: View>: View {
    /// False when nothing in the content moves now, so it needs no clock.
    var runs = true
    @Environment(\.panelIsOpen) private var isOpen
    @Environment(\.panelFrozenTime) private var frozenTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: (TimeInterval?) -> Content

    var body: some View {
        if let frozenTime {
            content(frozenTime)
        } else if reduceMotion || !isOpen || !runs {
            content(nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                content(context.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}
