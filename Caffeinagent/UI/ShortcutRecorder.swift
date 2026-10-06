import AppKit
import SwiftUI

/// One row of Preferences that holds a keyboard shortcut. A click on the
/// field records the next key combination. Escape leaves the shortcut as
/// it is, and the Delete key clears it.
struct ShortcutRecorder: View {
    let title: String
    let shortcut: Shortcut?
    var problem: ShortcutProblem?
    let set: (Shortcut?) -> Void
    /// While a row records, the shortcuts are off: the keys of a shortcut
    /// that is set must reach the field, not do their work.
    let setRecording: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    if shortcut != nil, !recording {
                        Button { set(nil) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Self.clear)
                        .help(Self.clear)
                    }
                    Button(action: { recording ? stop() : start() }) {
                        Text(recording ? Self.recording : shortcut?.display ?? Self.record)
                            .frame(minWidth: 104)
                    }
                    .accessibilityLabel(title)
                    .accessibilityValue(recording ? Self.recording : shortcut?.display ?? Self.none)
                }
            }
            if let problem {
                Text(problem.text)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    static let record = "Record shortcut"
    static let recording = "Press the keys"
    static let clear = "Clear shortcut"
    static let none = "None"

    private func start() {
        guard monitor == nil else { return }
        recording = true
        setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = Shortcut.Modifiers(event.modifierFlags)
            switch (event.keyCode, modifiers.isEmpty) {
            case (53, true):
                stop()
            case (51, true), (117, true):
                stop()
                set(nil)
            default:
                // A key without a name, such as a dead key, is waited out.
                guard let shortcut = Shortcut(
                    keyCode: event.keyCode, modifiers: modifiers, characters: event.characters(byApplyingModifiers: [])
                ) else { return nil }
                stop()
                set(shortcut)
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        recording = false
        setRecording(false)
    }
}

extension Shortcut.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}
