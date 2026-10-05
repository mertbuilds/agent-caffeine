import CoreGraphics

/// The mark of one agent: filled paths on a 24 x 24 canvas, bottom layer first.
struct AgentLogo {
    enum Fill {
        /// Takes the colour of the text around it.
        case current
        case hex(UInt32)
        case linear([(CGFloat, UInt32)], from: CGPoint, to: CGPoint)
        case radial([(CGFloat, UInt32)], center: CGPoint, radius: CGFloat)
    }

    struct Layer {
        /// SVG path data.
        var path: String
        var fill: Fill
        var evenOdd = false
    }

    static let canvas: CGFloat = 24

    var layers: [Layer]

    /// Nil for an agent without a mark, and for a tool the user added.
    static func mark(forAgentID id: String) -> AgentLogo? {
        markByAgentID[id].flatMap { marks[$0] }
    }
}
