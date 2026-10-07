import SwiftUI

/// Makes the line of one agent go to the app that agent runs in. A line
/// with no app to go to stays as it is: no click, and no change under
/// the pointer.
struct GoToRow: ViewModifier {
    let action: PanelAction?
    let radius: CGFloat
    let perform: (PanelAction) -> Void
    @State private var isUnderPointer = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.primary.opacity(action != nil && isUnderPointer ? PanelMetrics.rowHoverOpacity : 0))
                    // Into the gutter, so the text keeps its place.
                    .padding(.horizontal, -PanelMetrics.rowHoverOutset)
            }
            .onHover { isUnderPointer = $0 }
            .onTapGesture {
                if let action { perform(action) }
            }
            .accessibilityActions {
                if let action {
                    Button(action.title) { perform(action) }
                }
            }
    }
}

extension View {
    /// `reveal` cuts at the edges of its part. This one cuts where the
    /// fill of a line under the pointer ends, and the lines keep their place.
    func revealWithRowHover(isOpen: Bool, height: CGFloat) -> some View {
        padding(.horizontal, PanelMetrics.rowHoverOutset)
            .reveal(isOpen: isOpen, height: height)
            .padding(.horizontal, -PanelMetrics.rowHoverOutset)
    }

    func goTo(_ action: PanelAction?, radius: CGFloat, perform: @escaping (PanelAction) -> Void) -> some View {
        modifier(GoToRow(action: action, radius: radius, perform: perform))
    }
}
