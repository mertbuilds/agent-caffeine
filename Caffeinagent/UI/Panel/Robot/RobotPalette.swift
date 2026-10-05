import SwiftUI

/// The colours of the app icon's robot, muted for a robot that sleeps or
/// is off. The colours are mixed here, not with a filter over the view,
/// so a change of pose blends from one set to the next.
struct RobotPalette {
    /// 1 is the full colour, 0 is grey.
    var saturation: Double = 1
    /// 0 to 1, towards black.
    var dimming: Double = 0

    var discTop: Color { color(0.42, 0.69, 1.0) }
    var discBottom: Color { color(0.10, 0.36, 0.84) }
    var shellTop: Color { color(1, 1, 1) }
    var shellBottom: Color { color(0.80, 0.87, 0.97) }
    var shellShade: Color { color(0.68, 0.79, 0.95) }
    var visorTop: Color { color(0.15, 0.22, 0.45) }
    var visorBottom: Color { color(0.06, 0.10, 0.25) }
    var eye: Color { color(0.68, 0.88, 1.0) }
    var glow: Color { color(0.36, 0.74, 1.0) }
    var cupTop: Color { color(1.0, 0.97, 0.91) }
    var cupBottom: Color { color(0.91, 0.84, 0.73) }
    var coffee: Color { color(0.36, 0.21, 0.12) }
    var antenna: Color { color(0.80, 0.93, 1.0) }
    var amber: Color { color(1.0, 0.72, 0.20) }

    var shell: LinearGradient { LinearGradient(colors: [shellTop, shellBottom], startPoint: .top, endPoint: .bottom) }
    var body: LinearGradient { LinearGradient(colors: [shellBottom, shellShade], startPoint: .top, endPoint: .bottom) }
    var visor: LinearGradient { LinearGradient(colors: [visorTop, visorBottom], startPoint: .top, endPoint: .bottom) }
    var cup: LinearGradient { LinearGradient(colors: [cupTop, cupBottom], startPoint: .top, endPoint: .bottom) }
    var disc: LinearGradient { LinearGradient(colors: [discTop, discBottom], startPoint: .topTrailing, endPoint: .bottomLeading) }

    private func color(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        let grey = 0.299 * red + 0.587 * green + 0.114 * blue
        func mixed(_ channel: Double) -> Double {
            (grey + (channel - grey) * saturation) * (1 - dimming)
        }
        return Color(red: mixed(red), green: mixed(green), blue: mixed(blue))
    }
}
