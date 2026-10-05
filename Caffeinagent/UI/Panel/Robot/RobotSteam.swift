import SwiftUI

/// The steam over the cup. Each wisp rises and fades in a loop of its own
/// phase. Without a time the wisps stand still, part of the way up.
struct RobotSteam: View {
    static let period: TimeInterval = 3.4

    let wisps: Int
    let time: TimeInterval?

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RobotSteamWisp(originX: Self.origin(index, of: max(wisps, 1)), originY: 66 - 6 * phase(index), sway: sway(index))
                    .stroke(.white, style: StrokeStyle(lineWidth: unit * 2.8, lineCap: .round))
                    .opacity(index < wisps ? strength(index) : 0)
            }
        }
        .blur(radius: unit * 0.7)
    }

    @Environment(\.robotUnit) private var unit

    private static func origin(_ index: Int, of count: Int) -> CGFloat {
        switch count {
        case 1: return 50.5
        case 2: return index == 0 ? 46.5 : 54
        default: return [45, 50.5, 56][min(index, 2)]
        }
    }

    /// 0 at the cup, 1 where the wisp is gone.
    private func phase(_ index: Int) -> CGFloat {
        guard let time else { return [0.42, 0.6, 0.3][index] }
        let shifted = time / Self.period + Double(index) * 0.37
        return CGFloat(shifted - shifted.rounded(.down))
    }

    private func strength(_ index: Int) -> Double {
        0.9 * sin(.pi * Double(phase(index)))
    }

    private func sway(_ index: Int) -> CGFloat {
        guard let time else { return 0 }
        return CGFloat(0.8 * sin(time * 2 * .pi / 4.6 + Double(index) * 1.7))
    }
}
