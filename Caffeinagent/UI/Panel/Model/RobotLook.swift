import Foundation

/// What one pose of the robot is drawn from. The robot itself is the
/// picture of the app icon. Its eyes, its steam and the light of its
/// antenna are drawn on top and change with the pose.
struct RobotLook: Equatable {
    enum Eyes: Equatable {
        /// The arcs of the icon.
        case happy
        /// Round, they look at the user.
        case open
        /// Flat lines.
        case closed
        /// The arcs of the icon, faint.
        case dim
        /// Two red crosses.
        case dead
    }

    enum Antenna: Equatable {
        /// The light blue of the icon, it breathes.
        case glowing
        /// It breathes in amber.
        case amber
        case dark
        /// Red, and still.
        case red
    }

    var eyes = Eyes.happy
    var antenna = Antenna.glowing
    var wisps = 0
    /// Of the picture: 1 is the full colour, 0 is grey.
    var saturation: Double = 1
    /// Of the picture: 0 to 1, towards black.
    var dimming: Double = 0
    /// Of the picture: 1 is the full contrast.
    var contrast: Double = 1
    var snoozes = false
    var blinks = false
    /// How far the robot bobs, in points.
    var bob: CGFloat = 0
    /// An SF Symbol at the lower right.
    var badge: String?

    init(pose: HeroPose) {
        switch pose {
        case .awake(let count):
            wisps = count
            blinks = true
            bob = 1.25
        case .attentive:
            eyes = .open
            antenna = .amber
            blinks = true
            bob = 1.25
        case .asleep:
            eyes = .closed
            antenna = .dark
            saturation = 0.6
            dimming = 0.08
            snoozes = true
        case .off:
            eyes = .dim
            antenna = .dark
            saturation = 0
            dimming = 0.04
            contrast = 0.8
        case .safetyStop(let kind):
            knockOut()
            badge = kind == .battery ? "battery.25" : "thermometer.high"
        case .helperOff:
            knockOut()
        }
    }

    private mutating func knockOut() {
        eyes = .dead
        antenna = .red
        saturation = 0.5
        dimming = 0.1
    }
}

/// When the robot blinks while it is awake: now and then, never in a
/// steady beat.
enum RobotBlink {
    /// From one blink to the next, in turn.
    static let gaps: [TimeInterval] = [4.6, 6.3, 5.1, 6.8, 4.2, 5.7]
    static let duration: TimeInterval = 0.12

    /// 0 while the eyes are open, 1 when they are shut.
    static func closure(at time: TimeInterval) -> CGFloat {
        var left = time.truncatingRemainder(dividingBy: gaps.reduce(0, +))
        for gap in gaps {
            if left < gap {
                let into = left - (gap - duration)
                return into < 0 ? 0 : CGFloat(1 - abs(2 * into / duration - 1))
            }
            left -= gap
        }
        return 0
    }
}
