import SwiftUI

/// An agent's mark in its rounded box. An agent without a mark, and a
/// tool the user added, gets a plain terminal glyph.
struct AgentLogoView: View {
    let agentID: String

    var body: some View {
        RoundedRectangle(cornerRadius: PanelMetrics.logoBoxRadius, style: .continuous)
            .fill(.primary.opacity(0.07))
            .frame(width: PanelMetrics.logoBox, height: PanelMetrics.logoBox)
            .overlay {
                if let mark = AgentLogo.mark(forAgentID: agentID), let paths = Self.paths[agentID] {
                    Canvas { context, size in
                        Self.draw(mark, paths: paths, in: &context, size: size)
                    }
                    .padding(PanelMetrics.logoPadding)
                } else {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
    }

    /// Read once: path data is text.
    private static let paths: [String: [Path]] = AgentLogo.markByAgentID.compactMapValues { name in
        AgentLogo.marks[name]?.layers.map { Path(SVGPath.cgPath($0.path)) }
    }

    private static func draw(_ mark: AgentLogo, paths: [Path], in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width, size.height) / AgentLogo.canvas
        context.scaleBy(x: scale, y: scale)
        for (layer, path) in zip(mark.layers, paths) {
            context.opacity = layer.opacity
            context.fill(path, with: shading(layer.fill), style: FillStyle(eoFill: layer.evenOdd))
        }
    }

    private static func shading(_ fill: AgentLogo.Fill) -> GraphicsContext.Shading {
        switch fill {
        case .current:
            return .foreground
        case .hex(let value):
            return .color(color(value))
        case .linear(let stops, let from, let to):
            return .linearGradient(gradient(stops), startPoint: from, endPoint: to)
        case .radial(let stops, let center, let radius):
            return .radialGradient(gradient(stops), center: center, startRadius: 0, endRadius: radius)
        }
    }

    private static func gradient(_ stops: [(CGFloat, UInt32)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: color($0.1), location: $0.0) })
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
