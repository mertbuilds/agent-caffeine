import Carbon
import os

/// Registers the shortcuts with macOS, so the smoke test can run the app
/// without them.
@MainActor
protocol HotKeyRegistering: AnyObject {
    /// The shortcuts that are switched on in System Settings.
    var systemShortcuts: Set<Shortcut.Keys> { get }
    /// Replaces what was registered for the action. Nil removes it.
    /// False when macOS refused the shortcut.
    func register(_ shortcut: Shortcut?, for action: ShortcutAction, onPress: @escaping () -> Void) -> Bool
    func unregisterAll()
}

/// Shortcuts that work in every app, through Carbon's
/// `RegisterEventHotKey`. It needs no permission: macOS tells the app only
/// about its own shortcuts, never about other keys.
@MainActor
final class GlobalHotKey: HotKeyRegistering {
    private struct Registration {
        var ref: EventHotKeyRef
        var onPress: () -> Void
    }

    /// "acaf", so the hot key ids are ours.
    private static let signature: OSType = 0x6163_6166
    private var registrations: [UInt32: Registration] = [:]
    private var handler: EventHandlerRef?
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "GlobalHotKey")

    var systemShortcuts: Set<Shortcut.Keys> {
        var out: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&out) == noErr, let list = out?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var keys: Set<Shortcut.Keys> = []
        for item in list where item[kHISymbolicHotKeyEnabled as String] as? Bool == true {
            guard let code = item[kHISymbolicHotKeyCode as String] as? Int, (0...Int(UInt16.max)).contains(code),
                  let modifiers = item[kHISymbolicHotKeyModifiers as String] as? Int, modifiers >= 0 else { continue }
            keys.insert(Shortcut.Keys(keyCode: UInt16(code), modifiers: Shortcut.Modifiers(carbon: UInt32(truncatingIfNeeded: modifiers))))
        }
        return keys
    }

    func register(_ shortcut: Shortcut?, for action: ShortcutAction, onPress: @escaping () -> Void) -> Bool {
        let id = Self.id(of: action)
        if let old = registrations.removeValue(forKey: id) { UnregisterEventHotKey(old.ref) }
        guard let shortcut else { return true }
        guard installHandler() else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.modifiers.carbon, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey for \(action.rawValue, privacy: .public) failed: \(status)")
            return false
        }
        registrations[id] = Registration(ref: ref, onPress: onPress)
        log.info("registered the shortcut for \(action.rawValue, privacy: .public)")
        return true
    }

    func unregisterAll() {
        for registration in registrations.values { UnregisterEventHotKey(registration.ref) }
        registrations.removeAll()
    }

    private static func id(of action: ShortcutAction) -> UInt32 {
        UInt32((ShortcutAction.allCases.firstIndex(of: action) ?? 0) + 1)
    }

    /// One handler for all shortcuts, installed with the first one.
    private func installHandler() -> Bool {
        if handler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr, let context else { return OSStatus(eventNotHandledErr) }
            let pressed = id
            // Carbon calls on the main thread, where the app's run loop is.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().pressed(pressed)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { log.error("InstallEventHandler failed: \(status)") }
        return status == noErr
    }

    private func pressed(_ id: EventHotKeyID) {
        guard id.signature == Self.signature else { return }
        registrations[id.id]?.onPress()
    }
}
