import SwiftUI

/// Gives its content the time once a second while the menu is open, so
/// the durations count on. A closed menu gets no ticks.
struct PanelClock<Content: View>: View {
    let isOpen: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if isOpen {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(Date())
        }
    }
}
