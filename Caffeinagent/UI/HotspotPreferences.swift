import SwiftUI

/// "Join your iPhone hotspot (Beta)" in the tab General. Drawn from
/// plain values, so a preview needs no Wi-Fi and no Keychain.
struct HotspotPreferences: View {
    var hotspot = HotspotView()
    /// "Ask to join hotspots" of macOS. Nil when it could not be read.
    var autoJoin: HotspotAutoJoin?
    /// This macOS has the choice Automatic.
    var offersAutomatic = false
    var setOn: (Bool) -> Void = { _ in }
    var setHopBack: (Bool) -> Void = { _ in }
    var save: (_ name: String, _ password: String) -> Void = { _, _ in }
    var openPrivacy: () -> Void = {}
    var openWiFi: () -> Void = {}

    @State private var name = ""
    @State private var password = ""

    var body: some View {
        Section(PanelText.hotspotTitle) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(PanelText.hotspotSwitch, isOn: Binding(get: { hotspot.settings.on }, set: setOn))
                Text(PanelText.hotspotExplained)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if hotspot.settings.on {
                fields
                // No row while there is nothing to say. The line names
                // the day of a result that is not of today.
                if PanelText.hotspotStatus(hotspot, now: Date()) != nil {
                    TimelineView(.everyMinute) { context in
                        if let status = PanelText.hotspotStatus(hotspot, now: context.date) { statusLine(status) }
                    }
                }
                limit
                Text(PanelText.hotspotLeaves)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(PanelText.hotspotHopBack, isOn: Binding(get: { hotspot.settings.hopBack }, set: setHopBack))
                    Text(PanelText.hotspotHopBackExplained)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(PanelText.hotspotForgets)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if hotspot.saveNote == .removeFailed {
                // Off, and the password is still in the Keychain.
                Text(PanelText.hotspotSaveNote(.removeFailed))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { name = hotspot.settings.name ?? "" }
        .onChange(of: hotspot.settings.name) { name = $0 ?? "" }
    }

    @ViewBuilder
    private var fields: some View {
        TextField(PanelText.hotspotName, text: $name, prompt: Text(PanelText.hotspotNamePrompt))
            .autocorrectionDisabled()
        SecureField(
            PanelText.hotspotPassword, text: $password,
            prompt: hotspot.settings.passwordSaved ? Text(PanelText.hotspotPasswordSaved) : nil
        )
        HStack {
            if let note = hotspot.saveNote {
                Text(PanelText.hotspotSaveNote(note))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(PanelText.hotspotSave) {
                save(name, password)
                // A save with no name saves nothing, and the password stays to be sent again.
                if HotspotName.cleaned(name) != nil { password = "" }
            }
        }
    }

    private func statusLine(_ status: HotspotStatusLine) -> some View {
        HStack {
            Label(status.text, systemImage: status.opensPrivacy ? "location.slash" : "wifi")
                .foregroundStyle(status.opensPrivacy ? Color.orange : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if status.opensPrivacy { Button(PanelText.hotspotOpenPrivacy, action: openPrivacy) }
        }
    }

    private var limit: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(PanelText.hotspotLimit(offersAutomatic: offersAutomatic))
                if let autoJoin { Text(PanelText.hotspotAutoJoin(autoJoin)) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if offersAutomatic { Button(PanelText.hotspotOpenWiFi, action: openWiFi) }
        }
    }
}
