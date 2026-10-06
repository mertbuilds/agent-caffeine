import SwiftUI

/// Opens a part below its header. The part stays in the view tree, so its
/// height and the lines below it move as one, frame by frame.
struct RevealModifier: ViewModifier, Animatable {
    let isOpen: Bool
    var natural: CGFloat
    var progress: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(natural, progress) }
        set {
            natural = newValue.first
            progress = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let reveal = Reveal(natural: natural, progress: progress, opening: isOpen)
        content
            .frame(height: max(0, natural), alignment: .top)
            .opacity(reveal.opacity)
            .frame(height: reveal.height, alignment: .top)
            .clipped()
            .allowsHitTesting(!reveal.isOutOfReach)
            .accessibilityHidden(reveal.isOutOfReach)
    }
}

extension View {
    /// - Parameter height: of the part when it is open, known before the layout.
    func reveal(isOpen: Bool, height: CGFloat) -> some View {
        modifier(RevealModifier(isOpen: isOpen, natural: height, progress: isOpen ? 1 : 0))
    }
}
