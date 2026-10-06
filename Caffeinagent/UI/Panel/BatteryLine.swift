import SwiftUI

/// The charge of the battery on one quiet line below the headline: a small
/// mark, the number, and what follows from it.
struct BatteryLine: View {
    let battery: PanelBattery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            glyph
            Text(battery.charge)
                .foregroundStyle(accent)
                .contentTransition(.numericText())
            Text(PanelText.batterySeparator)
                .foregroundStyle(.tertiary)
            Text(battery.consequence)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: battery)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.accessibilityLabel)
    }

    private var glyph: some View {
        BatteryGlyph(fill: battery.fill, outline: battery.tone == .red ? accent : .secondary, level: accent)
            // Centred on the capitals and digits of the text next to it.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - PanelMetrics.batteryGlyphDrop }
    }

    private var accent: Color {
        switch battery.tone {
        case .quiet: return .secondary
        case .amber: return PanelMetrics.waitingAmber
        case .red: return .red
        }
    }
}

/// A battery drawn as a path, so its level has no steps and takes a colour.
struct BatteryGlyph: View {
    /// 0 to 1.
    var fill: Double
    var outline: Color
    var level: Color

    private static let stroke: CGFloat = 1
    /// Between the outline and the level.
    private static let gap: CGFloat = 1
    private static let radius: CGFloat = 3
    private static let cap = CGSize(width: 1.5, height: 4)
    private static let capGap: CGFloat = 1

    var body: some View {
        let body = PanelMetrics.batteryGlyph
        let inset = Self.stroke + Self.gap
        let inner = CGSize(width: body.width - 2 * inset, height: body.height - 2 * inset)
        HStack(spacing: Self.capGap) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(outline, lineWidth: Self.stroke)
                BatteryLevel(fill: fill)
                    .fill(level)
                    .frame(width: inner.width, height: inner.height)
                    .clipShape(RoundedRectangle(cornerRadius: Self.radius - inset, style: .continuous))
                    .padding(.leading, inset)
            }
            .frame(width: body.width, height: body.height)
            UnevenRoundedRectangle(bottomTrailingRadius: 1, topTrailingRadius: 1)
                .fill(outline)
                .frame(width: Self.cap.width, height: Self.cap.height)
        }
        .accessibilityHidden(true)
    }
}

/// The filled part, from the leading edge. Its width follows the charge
/// smoothly when the charge changes.
private struct BatteryLevel: Shape {
    var fill: Double

    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // A battery that is not empty always shows a sliver.
        let width = fill > 0 ? max(1, rect.width * min(fill, 1)) : 0
        return Path(CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
    }
}
