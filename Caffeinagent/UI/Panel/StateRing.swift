import SwiftUI

/// The ring round an agent's mark. An arc that sweeps round means work,
/// a whole ring that breathes in amber means the agent waits. An idle
/// agent has none, so the state never rests on colour alone.
struct StateRing: View {
    static let sweepPeriod: TimeInterval = 1.4
    static let pulsePeriod: TimeInterval = 2
    static let arc: CGFloat = 0.75

    let state: PanelRow.State

    var body: some View {
        MotionClock { time in
            ZStack {
                switch state {
                case .working:
                    let start = Self.turn(at: time)
                    ring.trim(from: start, to: min(1, start + Self.arc))
                        .stroke(Color.brand, style: stroke)
                    // The part of the arc that passed the start of the outline.
                    ring.trim(from: 0, to: max(0, start + Self.arc - 1))
                        .stroke(Color.brand, style: stroke)
                case .waiting:
                    ring.stroke(PanelMetrics.waitingAmber, style: stroke)
                        .opacity(Self.pulse(at: time))
                case .idle:
                    EmptyView()
                }
            }
        }
        .frame(width: PanelMetrics.logoSlot, height: PanelMetrics.logoSlot)
        .accessibilityHidden(true)
    }

    private var ring: some Shape {
        RoundedRectangle(cornerRadius: PanelMetrics.ringRadius - PanelMetrics.ringWidth / 2, style: .continuous)
            .inset(by: PanelMetrics.ringWidth / 2)
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: PanelMetrics.ringWidth, lineCap: .round)
    }

    /// Where the arc starts, as a share of the outline.
    static func turn(at time: TimeInterval?) -> CGFloat {
        guard let time else { return 0.125 }
        let turns = time / sweepPeriod
        return CGFloat(turns - turns.rounded(.down))
    }

    /// Between 0.4 and 1.
    static func pulse(at time: TimeInterval?) -> Double {
        guard let time else { return 1 }
        return 0.7 + 0.3 * sin(time * 2 * .pi / pulsePeriod)
    }
}
