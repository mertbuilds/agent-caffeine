import QuartzCore
import SwiftUI

/// The robot of the app icon: its tile, the robot over it, and on top the
/// parts that move. The tile stays still. The robot floats over it while
/// the menu is open. Everything that moves is a layer that Core Animation
/// moves, see `RobotLayerView`.
struct RobotFigure: View {
    let look: RobotLook
    /// How many blinks the user asked for.
    var taps = 0
    /// When the float began, on the clock of Core Animation. The robot
    /// and what is drawn over it float as one.
    @State private var floatBegan: CFTimeInterval?
    @Environment(\.robotUnit) private var unit
    @Environment(\.panelIsOpen) private var isOpen
    @Environment(\.panelFrozenTime) private var frozenTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = unit * 100
        let tile = RoundedRectangle(cornerRadius: side * RobotGeometry.corner, style: .continuous)
        let scene = RobotScene(
            look: look, moves: isOpen && !reduceMotion && frozenTime == nil, frozenTime: frozenTime, floatBegan: floatBegan, taps: taps
        )
        ZStack {
            ZStack {
                Image("RobotTile")
                    .resizable()
                    .interpolation(.high)
                RobotBodyLayers(scene: scene)
            }
            .saturation(look.saturation)
            .contrast(look.contrast)
            .brightness(-look.dimming)
            RobotOverlayLayers(scene: scene)
        }
        // The pictures are a little larger than the tile's rounded square.
        .frame(width: side * RobotGeometry.shownScale, height: side * RobotGeometry.shownScale)
        .frame(width: side, height: side)
        .clipShape(tile)
        .overlay(tile.strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) { badge }
        .onAppear { float(floats) }
        .onChange(of: floats) { float($0) }
    }

    private var floats: Bool {
        RobotFloat.runs(travel: look.bob, isOpen: isOpen, reduceMotion: reduceMotion, frozen: frozenTime != nil)
    }

    /// The loop is on the layers only while the robot floats, so a closed
    /// menu animates nothing.
    private func float(_ on: Bool) {
        floatBegan = on ? CACurrentMediaTime() : nil
    }

    private static let smallestBadgeUnit: CGFloat = 0.72

    @ViewBuilder
    private var badge: some View {
        if let symbol = look.badge {
            // On a small tile the badge keeps a size that reads.
            let unit = max(unit, Self.smallestBadgeUnit)
            Image(systemName: symbol)
                .font(.system(size: unit * 13, weight: .medium))
                .foregroundStyle(symbol.hasPrefix("battery") ? Color.red : Color.orange)
                .frame(width: unit * 28, height: unit * 28)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
                .offset(x: unit * 7, y: unit * 5)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}
