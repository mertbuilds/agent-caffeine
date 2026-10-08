import Foundation

/// What the robot in the menu bar is drawn from. It comes from the look of
/// the robot in the menu, so the two always show the same state.
struct MenuBarLook: Equatable, Hashable {
    enum Eyes: Equatable, Hashable {
        /// The arcs of the icon.
        case happy
        /// Round, they look at the user.
        case open
        /// Flat lines.
        case closed
        /// Two crosses.
        case dead
    }

    /// Why the app holds nothing. All three are drawn alike, grey with
    /// closed eyes, and each is said to VoiceOver as its own state.
    enum Rest: Equatable, Hashable {
        case canSleep
        case paused
        case off
    }

    /// Of the whole picture while the app holds nothing.
    static let restingOpacity = 0.45

    var eyes: Eyes
    /// A solid head while the Mac is kept awake, an outline when it is not.
    var solid: Bool
    /// Nil while the Mac is kept awake, and after a stop.
    var rest: Rest?

    /// Of the whole picture.
    var opacity: Double { rest == nil ? 1 : Self.restingOpacity }

    init(look: RobotLook) {
        switch look.eyes {
        case .happy: self.init(eyes: .happy, solid: true)
        case .open: self.init(eyes: .open, solid: true)
        case .closed: self.init(eyes: .closed, solid: false, rest: .canSleep)
        case .dim: self.init(eyes: .closed, solid: false, rest: .off)
        case .dead: self.init(eyes: .dead, solid: false)
        }
    }

    init(pose: HeroPose) {
        self.init(look: RobotLook(pose: pose))
        if pose == .paused { rest = .paused }
    }

    init(eyes: Eyes, solid: Bool, rest: Rest? = nil) {
        self.eyes = eyes
        self.solid = solid
        self.rest = rest
    }

    /// What VoiceOver says for the item in the menu bar, and its tooltip.
    var accessibilityLabel: String {
        switch eyes {
        case .happy: return PanelText.menuBarAwake
        case .open: return PanelText.menuBarWaiting
        case .closed:
            switch rest {
            case .paused: return PanelText.menuBarPaused
            case .off: return PanelText.menuBarOff
            case .canSleep, nil: return PanelText.menuBarCanSleep
            }
        case .dead: return PanelText.menuBarNeedsAttention
        }
    }
}
