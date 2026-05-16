import SwiftUI

struct MenuBarView: View {
    @ObservedObject var aggregator: StateAggregator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            agentList
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Caffeinagent")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $aggregator.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Text(statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
            if onBattery {
                Label("on battery — lid close will sleep this Mac",
                      systemImage: "battery.50")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var agentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if aggregator.allAgents.isEmpty {
                Text("no agents detected")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(aggregator.allAgents) { agent in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: agent.state))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(agent.label)
                                .font(.callout)
                            Text("\(agent.source.rawValue) · \(agent.state.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(timeAgo(agent.lastActivity))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("preferences…") { openSettings() }
                .buttonStyle(.borderless)
            Spacer()
            Button("quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.callout)
    }

    private var statusLine: String {
        if !aggregator.enabled { return "paused" }
        switch aggregator.globalState {
        case .active: return aggregator.assertionHeld ? "keeping mac awake" : "active (assertion not held)"
        case .waitingForInput: return "waiting for input — mac may sleep"
        case .idle: return "idle — mac may sleep"
        }
    }

    private var onBattery: Bool {
        guard aggregator.enabled, aggregator.globalState == .active else { return false }
        return PowerSource.isOnBattery()
    }

    private func color(for state: AgentState) -> Color {
        switch state {
        case .active: return .green
        case .waitingForInput: return .yellow
        case .idle: return .gray
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "now" }
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m" }
        return "\(s/3600)h"
    }
}
