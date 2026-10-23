import SwiftUI

/// The one thing that needs the user, below the headline.
struct AttentionLine: View {
    let attention: PanelAttention
    var busy = false
    let perform: (PanelAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                message
                    .fixedSize()
                Spacer(minLength: 0)
                actions
            }
            if attention.actions == [.dismissSleepNote] {
                // The cross stays next to a text of two lines.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    message
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    actions
                }
            } else {
                // The actions stand below the text, on its leading edge.
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attention.text)
                            .fixedSize(horizontal: false, vertical: true)
                        actions
                    }
                } icon: {
                    Image(systemName: symbol)
                }
                .labelStyle(AttentionLabelStyle(tint: tint))
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var message: some View {
        Label(attention.text, systemImage: symbol)
            .labelStyle(AttentionLabelStyle(tint: tint))
    }

    @ViewBuilder
    private var actions: some View {
        if !attention.actions.isEmpty {
            HStack(spacing: 10) {
                ForEach(attention.actions, id: \.title) { action in
                    if action == .dismissLidClosedHint || action == .dismissSleepNote {
                        Button { perform(action) } label: {
                            Label(action.title, systemImage: "xmark")
                                .labelStyle(.iconOnly)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action.title) { perform(action) }
                            .buttonStyle(.link)
                            .disabled(busy && (action == .checkLicense || action == .activateAgain))
                    }
                }
            }
        }
    }

    private var symbol: String {
        switch attention.kind {
        case .safetyStop, .helperSwitchedOff, .helperNotResponding, .helperLost, .closedLidLimit: return "exclamationmark.triangle.fill"
        case .license: return "key.fill"
        case .lidClosedNotSetUp, .reachableNeedsLidClosed: return "laptopcomputer"
        case .sleptAnyway: return "moon.zzz"
        case .agentsOffline: return "wifi.slash"
        }
    }

    private var tint: Color {
        switch attention.kind {
        case .safetyStop, .helperNotResponding, .helperLost, .license, .reachableNeedsLidClosed, .closedLidLimit: return .orange
        case .helperSwitchedOff: return .red
        case .lidClosedNotSetUp, .sleptAnyway, .agentsOffline: return .secondary
        }
    }
}
