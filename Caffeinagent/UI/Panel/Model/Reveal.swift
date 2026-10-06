import CoreGraphics

/// A part of the menu that opens below its header, at one moment of the
/// way: how much of its height is in view and how well it shows. The part
/// stands at the top of that height and is cut at it, so it never draws
/// over the header above it or the lines below it.
struct Reveal: Equatable {
    /// The height of the part when it is open.
    var natural: CGFloat
    /// 0 is closed, 1 is open.
    var progress: CGFloat
    /// Where it goes: true while it opens and when it is open.
    var opening: Bool

    /// The share of the way the fade in takes, and the fade out. The fade
    /// out is longer, so a tall part is not an empty box while it closes.
    static let fadeIn: CGFloat = 0.6
    static let fadeOut: CGFloat = 0.8

    /// A spring may pass its end, the part never does.
    private var clamped: CGFloat { min(1, max(0, progress)) }

    var height: CGFloat { max(0, natural) * clamped }

    /// In over the first part of the way to open, out over the first part
    /// of the way to closed.
    var opacity: CGFloat {
        opening ? min(1, clamped / Self.fadeIn) : max(0, (clamped - (1 - Self.fadeOut)) / Self.fadeOut)
    }

    /// A part that closes is out of reach from its first moment, for the
    /// pointer and for VoiceOver.
    var isOutOfReach: Bool { !opening }
}
