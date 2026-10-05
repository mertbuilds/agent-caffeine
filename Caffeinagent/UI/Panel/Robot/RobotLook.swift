import SwiftUI

/// The numbers one pose of the robot is drawn from. A change of pose
/// animates from one set to the next.
struct RobotLook: Equatable {
    enum Antenna: Equatable {
        case glowing
        case amber
        case dim
    }

    /// 1 is a happy arc, 0 a flat line.
    var eyeCurve: CGFloat = 1
    /// Above 0 the inner ends of the eyes rise.
    var eyeSlant: CGFloat = 0
    /// 1 turns the eyes into round ones that look at the user.
    var eyeRound: CGFloat = 0
    var eyeBrightness: Double = 1
    /// How far the cup is raised, in units of the drawing.
    var cupLift: CGFloat = 0
    /// Of the head, in degrees.
    var tilt: Double = 0
    var wisps = 0
    var antenna = Antenna.glowing
    var saturation: Double = 1
    var dimming: Double = 0
    var snoozes = false
    /// How far the robot bobs, in units of the drawing, and how long one
    /// bob takes.
    var bob: CGFloat = 0
    var bobPeriod: TimeInterval = 3.6
    /// An SF Symbol at the lower right.
    var badge: String?

    init(pose: HeroPose) {
        switch pose {
        case .awake(let count):
            wisps = count
            bob = 1.1
        case .attentive:
            eyeRound = 1
            cupLift = 2.5
            tilt = -5
            antenna = .amber
            bob = 0.5
            bobPeriod = 4.8
        case .asleep:
            eyeCurve = 0
            eyeBrightness = 0.75
            cupLift = -3
            antenna = .dim
            saturation = 0.45
            dimming = 0.1
            snoozes = true
            bob = 0.5
            bobPeriod = 5.2
        case .off:
            eyeCurve = 0
            eyeBrightness = 0.35
            cupLift = -3
            antenna = .dim
            saturation = 0
            dimming = 0.12
        case .safetyStop(let kind):
            eyeCurve = 0
            eyeSlant = 1.7
            eyeBrightness = 0.8
            cupLift = -3
            antenna = .dim
            saturation = 0.6
            dimming = 0.06
            badge = kind == .battery ? "battery.25" : "thermometer.high"
        }
    }
}
