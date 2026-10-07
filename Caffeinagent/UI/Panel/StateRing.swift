import AppKit
import SwiftUI

/// The ring round an agent's mark. An arc that sweeps round means work,
/// a whole ring that breathes in amber means the agent waits. An idle
/// agent has none, so the state never rests on colour alone.
struct StateRing: View {
    let state: PanelRow.State
    @Environment(\.panelIsOpen) private var isOpen
    @Environment(\.panelFrozenTime) private var frozenTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if state != .idle {
                RingLayer(state: state, moves: isOpen && !reduceMotion && frozenTime == nil, frozenTime: frozenTime)
            }
        }
        .frame(width: PanelMetrics.logoSlot, height: PanelMetrics.logoSlot)
        .accessibilityHidden(true)
    }
}

/// The ring as a layer. Core Animation sweeps it and lets it breathe.
private struct RingLayer: NSViewRepresentable {
    let state: PanelRow.State
    let moves: Bool
    let frozenTime: TimeInterval?

    func makeNSView(context: Context) -> RingView { RingView() }

    func updateNSView(_ view: RingView, context: Context) {
        view.show(state, moves: moves, frozenTime: frozenTime)
    }
}

private final class RingView: MotionView {
    private let ring = CAShapeLayer()
    /// The length of the outline, in points.
    private var length: CGFloat = 0
    private var shown: (state: PanelRow.State, moves: Bool, frozenTime: TimeInterval?)?

    override init() {
        super.init()
        ring.fillColor = nil
        ring.lineWidth = PanelMetrics.ringWidth
        ring.lineCap = .round
        layer?.addSublayer(ring)
    }

    func show(_ state: PanelRow.State, moves: Bool, frozenTime: TimeInterval?) {
        if let shown, shown == (state, moves, frozenTime) { return }
        let changes = shown.map { $0.state != state } ?? false
        shown = (state, moves, frozenTime)
        guard length > 0 else { return }
        withoutActions { draw(fading: changes && moves) }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, ring.frame != bounds else { return }
        let outline = RoundedRectangle(cornerRadius: PanelMetrics.ringRadius - PanelMetrics.ringWidth / 2, style: .continuous)
            .inset(by: PanelMetrics.ringWidth / 2)
            .path(in: bounds).cgPath
        withoutActions {
            ring.frame = bounds
            ring.path = outline
            length = outline.length
            draw(fading: false)
        }
    }

    private func draw(fading: Bool) {
        guard let shown else { return }
        ring.endLoops()
        if fading {
            let fade = CATransition()
            fade.type = .fade
            ring.add(fade, forKey: "state")
        }
        switch shown.state {
        case .working:
            // The dash is the arc, and the gap the rest of the outline.
            ring.strokeColor = NSColor(Color.brand).cgColor
            ring.lineDashPattern = [RingMotion.arc * length, (1 - RingMotion.arc) * length].map { NSNumber(value: $0) }
            ring.lineDashPhase = phase(turn: shown.frozenTime.map(RingMotion.turn.value(at:)) ?? RingMotion.restTurn)
            ring.opacity = 1
            if shown.moves { ring.loop(RingMotion.turn, on: "lineDashPhase") { self.phase(turn: $0) } }
        case .waiting:
            ring.strokeColor = NSColor(PanelMetrics.waitingAmber).cgColor
            ring.lineDashPattern = nil
            ring.opacity = Float(shown.frozenTime.map(RingMotion.pulse.value(at:)) ?? 1)
            if shown.moves { ring.loop(RingMotion.pulse, on: "opacity") }
        case .idle:
            ring.strokeColor = nil
        }
    }

    /// The phase of the dashes that starts the arc at a share of the outline.
    private func phase(turn: Double) -> CGFloat {
        length * (1 - turn)
    }
}

private extension CGPath {
    /// The length of the path, with its curves as short lines.
    var length: CGFloat {
        var length: CGFloat = 0
        var start = CGPoint.zero
        var last = CGPoint.zero
        flattened(threshold: 0.01).applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                start = points[0]
                last = start
            case .addLineToPoint:
                length += hypot(points[0].x - last.x, points[0].y - last.y)
                last = points[0]
            case .closeSubpath:
                length += hypot(start.x - last.x, start.y - last.y)
                last = start
            default:
                break
            }
        }
        return length
    }
}
