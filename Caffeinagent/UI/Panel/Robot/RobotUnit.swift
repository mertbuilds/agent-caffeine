import SwiftUI

private struct RobotUnitKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// A hundredth of the side of the robot's tile, in points.
    var robotUnit: CGFloat {
        get { self[RobotUnitKey.self] }
        set { self[RobotUnitKey.self] = newValue }
    }
}
