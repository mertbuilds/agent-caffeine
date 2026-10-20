import SwiftUI

/// The (i) at the end of a row of Settings: a click shows the longer
/// text of the row in a popover.
struct InfoButton: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Button { isShown.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel("More info")
        .popover(isPresented: $isShown) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)
                .padding()
        }
    }
}
