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

    var eyes: Eyes
    /// A solid head while the Mac is kept awake, an outline when it is not.
    var solid: Bool
    /// Of the whole picture. Less than 1 when the app is off.
    var opacity: Double = 1
    /// Drawn like "can sleep", and said to VoiceOver as its own state.
    var paused = false

    init(look: RobotLook) {
        switch look.eyes {
        case .happy: self.init(eyes: .happy, solid: true)
        case .open: self.init(eyes: .open, solid: true)
        case .closed: self.init(eyes: .closed, solid: false)
        case .dim: self.init(eyes: .closed, solid: false, opacity: 0.45)
        case .dead: self.init(eyes: .dead, solid: false)
        }
    }

    init(pose: HeroPose) {
        self.init(look: RobotLook(pose: pose))
        paused = pose == .paused
    }

    init(eyes: Eyes, solid: Bool, opacity: Double = 1, paused: Bool = false) {
        self.eyes = eyes
        self.solid = solid
        self.opacity = opacity
        self.paused = paused
    }

    /// What VoiceOver says for the item in the menu bar.
    var accessibilityLabel: String {
        switch eyes {
        case .happy, .open: return "agent caffeine, Mac stays awake"
        case .closed where paused: return "agent caffeine, paused"
        case .closed: return opacity < 1 ? "agent caffeine, off" : "agent caffeine, Mac can sleep"
        case .dead: return "agent caffeine, needs attention"
        }
    }
}
