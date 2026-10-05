import SwiftUI

private struct RobotUnitKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// One unit of the robot's 100 x 100 drawing, in points.
    var robotUnit: CGFloat {
        get { self[RobotUnitKey.self] }
        set { self[RobotUnitKey.self] = newValue }
    }
}
