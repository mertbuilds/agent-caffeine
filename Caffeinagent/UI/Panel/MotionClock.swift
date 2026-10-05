import SwiftUI

/// Gives its content the time of the looping motion, 30 times a second,
/// only while the menu is open and motion is allowed. Otherwise the time
/// is nil and the content holds a still pose.
struct MotionClock<Content: View>: View {
    @Environment(\.panelIsOpen) private var isOpen
    @Environment(\.panelFrozenTime) private var frozenTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: (TimeInterval?) -> Content

    var body: some View {
        if let frozenTime {
            content(frozenTime)
        } else if reduceMotion || !isOpen {
            content(nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                content(context.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}
