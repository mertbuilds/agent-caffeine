import SwiftUI

/// The letters that drift up from a sleeping robot.
struct RobotSnooze: View {
    static let period: TimeInterval = 4.4

    let time: TimeInterval?
    @Environment(\.robotUnit) private var unit

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(0..<2, id: \.self) { index in
                let phase = phase(index)
                Text(verbatim: "z")
                    .font(.system(size: unit * (index == 0 ? 15 : 11), weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(Double(sin(CGFloat.pi * phase)))
                    .offset(x: unit * (80 + 6 * phase - CGFloat(index) * 9), y: unit * (12 - 12 * phase + CGFloat(index) * 12))
            }
        }
        .accessibilityHidden(true)
    }

    private func phase(_ index: Int) -> CGFloat {
        guard let time else { return index == 0 ? 0.62 : 0.3 }
        let shifted = time / Self.period + Double(index) * 0.45
        return CGFloat(shifted - shifted.rounded(.down))
    }
}
