import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var aggregator: StateAggregator
    @ObservedObject var updater: Updater

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
        .tint(.brand)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("agent caffeine")
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
            licenseRow
            Picker("Keep the Mac awake", selection: $aggregator.mode) {
                ForEach(AwakeMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            batteryRow
        }
    }

    @ViewBuilder
    private var licenseRow: some View {
        switch aggregator.entitlement {
        case .licensed:
            EmptyView()
        case .trial(let daysLeft):
            HStack(spacing: 6) {
                Text("Trial: \(daysLeft) \(daysLeft == 1 ? "day" : "days") left")
                    .foregroundStyle(daysLeft <= 2 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                // Whoever has a key already bought one.
                if license.record.key == nil {
                    Button("Buy") { NSWorkspace.shared.open(license.config.checkoutURL) }
                        .buttonStyle(.borderless)
                }
            }
            .font(.caption)
        case .expired(.trialOver):
            HStack(spacing: 8) {
                Button("Buy agent caffeine · $9") { NSWorkspace.shared.open(license.config.checkoutURL) }
                    .buttonStyle(.borderedProminent)
                settingsButton("Enter key…")
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        case .expired(.unverified):
            Button("Check now") { Task { await license.checkNow() } }
                .buttonStyle(.borderedProminent)
                .disabled(license.busy)
                .controlSize(.small)
        case .expired(.activationRemoved):
            HStack(spacing: 8) {
                Button("Activate again") {
                    guard let key = license.record.key else { return }
                    Task { await license.activate(key: key) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(license.busy)
                settingsButton("Enter key…")
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    private var license: LicenseManager { aggregator.license }

    @ViewBuilder
    private var batteryRow: some View {
        if aggregator.onBattery {
            if aggregator.battery.sudoersInstalled {
                if aggregator.battery.overrideActive {
                    Label("On battery: override active", systemImage: "battery.100.bolt")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else if aggregator.assertionHeld {
                HStack(spacing: 6) {
                    Label("On battery: closing the lid will sleep this Mac", systemImage: "battery.50")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Turn on override…") { aggregator.battery.install() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        // Shown on AC too: a leftover sleep override keeps the Mac awake anywhere.
        if let err = aggregator.battery.lastError {
            Text(err)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    // Ticks only while the menu is open, so the times stay current without a
    // redraw on every poll.
    private var agentList: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            agentRows(now: context.date)
        }
    }

    private func agentRows(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if aggregator.allAgents.isEmpty {
                Text("No agents running")
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
                            Text("\(agent.source.rawValue) · \(agent.state.displayName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(timeAgo(agent.lastActivity, now: now))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            settingsButton("Preferences…")
                .buttonStyle(.borderless)
            Button("Check for updates…") { updater.checkForUpdates() }
                .buttonStyle(.borderless)
                .disabled(!updater.canCheckForUpdates)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.callout)
    }

    // The `openSettings` environment action is macOS 14+; the legacy
    // responder-chain selector still works on 13 but stopped opening the
    // SwiftUI Settings scene on newer macOS.
    @ViewBuilder
    private func settingsButton(_ title: String) -> some View {
        if #available(macOS 14.0, *) {
            SettingsOpenButton(title: title)
        } else {
            Button(title) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                MenuBarView.bringSettingsFront()
            }
        }
    }

    static func bringSettingsFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
            }) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    private var statusLine: String {
        if case .expired(let reason) = aggregator.entitlement { return reason.text }
        if !aggregator.enabled { return "Paused" }
        if aggregator.assertionHeld { return "Keeping the Mac awake" }
        if aggregator.shouldHold { return "Active, but the Mac may sleep" }
        if aggregator.allAgents.isEmpty { return "No agent is running. The Mac may sleep" }
        return "Agents are idle. The Mac may sleep"
    }

    private func color(for state: AgentState) -> Color {
        switch state {
        case .active: return .green
        case .waitingForInput: return .yellow
        case .idle: return .gray
        }
    }

    private func timeAgo(_ date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 5 { return "now" }
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m" }
        return "\(s/3600)h"
    }
}

extension Color {
    static let brand = Color(red: 0.165, green: 0.451, blue: 0.910)
}

@available(macOS 14.0, *)
private struct SettingsOpenButton: View {
    let title: String
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(title) {
            openSettings()
            MenuBarView.bringSettingsFront()
        }
    }
}
