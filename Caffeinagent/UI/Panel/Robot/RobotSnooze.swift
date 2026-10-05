import SwiftUI

/// The letters that drift up from a sleeping robot.
struct RobotSnooze: View {
    static let period: TimeInterval = 4.4

    let time: TimeInterval?

    private static let color = Color(red: 0.88, green: 0.95, blue: 1.0)
    private static let glow = Color(red: 0.55, green: 0.80, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(0..<2, id: \.self) { index in
                    let phase = phase(index)
                    Text(verbatim: "z")
                        .font(.system(size: side * (index == 0 ? 0.13 : 0.095), weight: .semibold, design: .rounded))
                        .foregroundStyle(Self.color)
                        .shadow(color: Self.glow.opacity(0.8), radius: side * 0.015)
                        .opacity(Double(sin(CGFloat.pi * phase)))
                        .offset(x: side * (0.77 + 0.05 * phase - CGFloat(index) * 0.07), y: side * (0.17 - 0.11 * phase + CGFloat(index) * 0.09))
                }
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
