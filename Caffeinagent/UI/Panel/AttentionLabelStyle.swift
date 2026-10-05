import SwiftUI

/// A tinted symbol, then the text in the colour of the menu.
struct AttentionLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .foregroundStyle(tint)
            configuration.title
        }
    }
}
