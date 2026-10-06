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
        /// The light blue of the icon, and still.
        case steady
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
    /// How far the robot floats up from its tile, in hundredths of the
    /// tile's side.
    var bob: CGFloat = 0
    /// An SF Symbol at the lower right.
    var badge: String?

    init(pose: HeroPose) {
        switch pose {
        case .awake(let count):
            wisps = count
            blinks = true
            bob = RobotFloat.travel
        case .reachable:
            antenna = .steady
            wisps = 1
            blinks = true
            bob = RobotFloat.travel
        case .attentive:
            eyes = .open
            antenna = .amber
            blinks = true
            bob = RobotFloat.travel
        case .asleep, .paused:
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

/// How the robot floats over its tile: up and down again, slow at both
/// ends. The menu runs it as an animation, so it moves at the rate of the
/// display. The same curve gives a still picture of any moment.
enum RobotFloat {
    /// From the tile to the top, in hundredths of the tile's side.
    static let travel: CGFloat = 2.25
    /// The robot is this much larger at the top.
    static let growth: CGFloat = 0.008
    /// Up and down again, in seconds.
    static let period: TimeInterval = 3.2
    /// The curve of each way, close to half a sine wave.
    static let ease: (x1: Double, y1: Double, x2: Double, y2: Double) = (0.37, 0, 0.63, 1)

    /// A robot that does not float, a closed menu, Reduce Motion and a
    /// still picture all leave the robot without the loop.
    static func runs(travel: CGFloat, isOpen: Bool, reduceMotion: Bool, frozen: Bool) -> Bool {
        travel > 0 && isOpen && !reduceMotion && !frozen
    }

    /// 0 on the tile, 1 at the top.
    static func rise(at time: TimeInterval) -> CGFloat {
        let turn = time / period - (time / period).rounded(.down)
        return CGFloat(eased(turn < 0.5 ? 2 * turn : 2 - 2 * turn))
    }

    /// The curve as an animation runs it: the height of the point of the
    /// curve whose x is `share`.
    static func eased(_ share: Double) -> Double {
        func along(_ a: Double, _ b: Double, _ t: Double) -> Double {
            3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
        }
        var (low, high) = (0.0, 1.0)
        for _ in 0..<40 {
            let middle = (low + high) / 2
            if along(ease.x1, ease.x2, middle) < share { low = middle } else { high = middle }
        }
        return along(ease.y1, ease.y2, (low + high) / 2)
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
