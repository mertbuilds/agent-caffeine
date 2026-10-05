import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var aggregator: StateAggregator

    var body: some View {
        MenuContent(
            headline: aggregator.decision.headline.text,
            enabled: $aggregator.enabled,
            mode: $aggregator.mode,
            rows: aggregator.agentRows,
            lidClosed: aggregator.hasBattery ? aggregator.lidClosedStatus : nil,
            flagLeftOn: aggregator.sleepFlag.flagLeftOn,
            openLoginItems: { aggregator.sleepFlag.openLoginItemsSettings() },
            settingsButton: { title, tab in AnyView(settingsButton(title, tab: tab)) }
        ) {
            licenseRow
        }
        .onAppear { aggregator.refreshHelperStatus() }
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
                Button("Buy agent caffeine for $9") { NSWorkspace.shared.open(license.config.checkoutURL) }
                    .buttonStyle(.borderedProminent)
                settingsButton("Enter key…", tab: .license)
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
                settingsButton("Enter key…", tab: .license)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    private var license: LicenseManager { aggregator.license }

    // The `openSettings` environment action is macOS 14+; the legacy
    // responder-chain selector still works on 13 but stopped opening the
    // SwiftUI Settings scene on newer macOS. A tab opens Preferences there.
    @ViewBuilder
    private func settingsButton(_ title: String, tab: PreferencesTab?) -> some View {
        if #available(macOS 14.0, *) {
            SettingsOpenButton(title: title) { select(tab) }
        } else {
            Button(title) {
                select(tab)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                MenuBarView.bringSettingsFront()
            }
        }
    }

    private func select(_ tab: PreferencesTab?) {
        if let tab { aggregator.preferencesTab = tab }
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
}

/// The menu, drawn from plain values so a preview needs no running app.
struct MenuContent<LicenseRow: View>: View {
    let headline: String
    @Binding var enabled: Bool
    @Binding var mode: AwakeMode
    let rows: [MenuAgentRow]
    /// Nil on a Mac without a battery.
    let lidClosed: LidClosedStatus?
    let flagLeftOn: Bool
    let openLoginItems: () -> Void
    /// A button that opens Preferences, at a tab when one is given.
    let settingsButton: (String, PreferencesTab?) -> AnyView
    @ViewBuilder let licenseRow: LicenseRow

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
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            licenseRow
            HStack {
                Picker("Keep the Mac awake", selection: $mode) {
                    ForEach(AwakeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                Spacer()
                Toggle("agent caffeine", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            lidClosedRow
        }
    }

    @ViewBuilder
    private var lidClosedRow: some View {
        if let lidClosed {
            HStack(spacing: 6) {
                Label(lidClosed.text, systemImage: "laptopcomputer")
                    .foregroundStyle(.secondary)
                Spacer()
                if lidClosed == .notSetUp {
                    settingsButton("Set up…", .lidClosed)
                        .buttonStyle(.borderless)
                }
            }
            .font(.caption)
        }
        // Shown on wall power too: a sleep flag that stays on keeps the Mac
        // awake anywhere.
        if flagLeftOn {
            VStack(alignment: .leading, spacing: 4) {
                Text("agent caffeine was switched off in Login Items while it kept the Mac awake with the lid closed. The Mac may not sleep until you allow it again in System Settings > General > Login Items.")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings", action: openLoginItems)
                    .buttonStyle(.borderless)
            }
            .font(.caption)
        }
    }

    private var agentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if rows.isEmpty {
                Text("No agent is open")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: row.state))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.title)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(row.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            settingsButton("Preferences…", nil)
                .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.callout)
    }

    private func color(for state: MenuAgentRow.State) -> Color {
        switch state {
        case .working: return .green
        case .waiting: return .yellow
        case .idle: return .gray
        }
    }
}

extension Color {
    static let brand = Color(red: 0.165, green: 0.451, blue: 0.910)
}

@available(macOS 14.0, *)
private struct SettingsOpenButton: View {
    let title: String
    let beforeOpening: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(title) {
            beforeOpening()
            openSettings()
            MenuBarView.bringSettingsFront()
        }
    }
}

#if DEBUG
private struct MenuPreview: View {
    let headline: HoldHeadline
    let rows: [MenuAgentRow]
    var lidClosed: LidClosedStatus? = .on
    var flagLeftOn = false
    @State private var enabled = true
    @State private var mode = AwakeMode.agentWorking

    var body: some View {
        MenuContent(
            headline: headline.text, enabled: $enabled, mode: $mode, rows: rows, lidClosed: lidClosed,
            flagLeftOn: flagLeftOn, openLoginItems: {},
            settingsButton: { title, _ in AnyView(Button(title) {}) }
        ) {
            Text("Trial: 5 days left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func holds(_ entries: [(id: String, name: String, state: WorkState, reason: VerdictReason)]) -> [AgentHold] {
        entries.enumerated().map { index, entry in
            AgentHold(
                reading: AgentReading(
                    agentID: entry.id, displayName: entry.name, level: .state,
                    identity: ProcessIdentity(pid: Int32(100 + index), startTime: 0),
                    verdict: AgentVerdict(state: entry.state, confidence: .reported, reason: entry.reason)
                ),
                cause: nil
            )
        }
    }

    static let idleClaude = (id: "claude", name: "Claude Code", state: WorkState.idle, reason: VerdictReason.atPrompt)
    static let working = holds([
        ("claude", "Claude Code", .working, .reportsBusy),
        ("claude", "Claude Code", .working, .runningCommand(2)),
        ("codex", "Codex", .idle, .atPrompt),
    ])
    static let labels = [
        ProcessIdentity(pid: 100, startTime: 0): "caffeinagent",
        ProcessIdentity(pid: 101, startTime: 0): "website",
    ]
}

#Preview("Working") {
    MenuPreview(headline: .working(.many(2)), rows: MenuModel.rows(for: MenuPreview.working, labels: MenuPreview.labels))
}

#Preview("Many idle") {
    MenuPreview(
        headline: .idle(.many(12)),
        rows: MenuModel.rows(for: MenuPreview.holds(
            Array(repeating: MenuPreview.idleClaude, count: 9)
                + [("codex", "Codex", .idle, .atPrompt), ("opencode", "opencode", .idle, .noActivity(minutes: 14))]
        ))
    )
}

#Preview("Waiting") {
    MenuPreview(
        headline: .waitingHeld(.one("Claude Code")),
        rows: MenuModel.rows(
            for: MenuPreview.holds([("claude", "Claude Code", .waitingForUser, .asksPermission), MenuPreview.idleClaude, MenuPreview.idleClaude]),
            labels: MenuPreview.labels
        ),
        lidClosed: .off
    )
}

#Preview("Safety stop") {
    MenuPreview(
        headline: .safetyStop(.batteryLow(percent: 20)),
        rows: MenuModel.rows(for: MenuPreview.working, labels: MenuPreview.labels)
    )
}

#Preview("Helper not set up") {
    MenuPreview(headline: .noAgents, rows: [], lidClosed: .notSetUp)
}

#Preview("Helper switched off") {
    MenuPreview(headline: .alwaysOn, rows: [], lidClosed: .notSetUp, flagLeftOn: true)
}
#endif
