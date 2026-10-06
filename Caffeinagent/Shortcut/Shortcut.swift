import Foundation

/// What a keyboard shortcut of agent caffeine does.
enum ShortcutAction: String, CaseIterable {
    /// The same as the switch. A pause ends. See `PauseSwitch`.
    case toggle
    case pauseOneHour

    var title: String {
        switch self {
        case .toggle: return "Turn agent caffeine on or off"
        case .pauseOneHour: return PanelText.title(of: .pause(.oneHour))
        }
    }
}

/// A key with its modifiers, for a shortcut that works in every app.
/// Pure: `GlobalHotKey` registers it.
struct Shortcut: Codable, Equatable {
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: Int

        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)

        /// In the order macOS writes them.
        var symbols: String {
            [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { contains($0.0) }.map(\.1).joined()
        }

        /// As Carbon's `RegisterEventHotKey` takes them: controlKey,
        /// optionKey, shiftKey and cmdKey.
        var carbon: UInt32 {
            [(Modifiers.control, UInt32(0x1000)), (.option, 0x0800), (.shift, 0x0200), (.command, 0x0100)]
                .filter { contains($0.0) }.reduce(0) { $0 | $1.1 }
        }

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        init(carbon: UInt32) {
            var modifiers: Modifiers = []
            if carbon & 0x1000 != 0 { modifiers.insert(.control) }
            if carbon & 0x0800 != 0 { modifiers.insert(.option) }
            if carbon & 0x0200 != 0 { modifiers.insert(.shift) }
            if carbon & 0x0100 != 0 { modifiers.insert(.command) }
            self = modifiers
        }
    }

    /// The key and the modifiers alone: what macOS matches.
    struct Keys: Hashable {
        var keyCode: UInt16
        var modifiers: Modifiers
    }

    /// The virtual key code, which names a place on the keyboard.
    var keyCode: UInt16
    var modifiers: Modifiers
    /// What stands on the key in the user's layout, read when the shortcut
    /// was recorded: "L", "F5", "Space".
    var key: String

    var keys: Keys { Keys(keyCode: keyCode, modifiers: modifiers) }

    /// "⌥⌘L".
    var display: String { modifiers.symbols + key }

    /// The keys that have a name and no character of their own.
    static let namedKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// Nil for a key that cannot be shown, such as a modifier alone.
    /// - Parameter characters: what the key types with no modifier held.
    static func keyName(keyCode: UInt16, characters: String?) -> String? {
        if let name = namedKeys[keyCode] { return name }
        guard let characters, characters.count == 1, let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.whitespacesAndNewlines.contains(scalar),
              // The function keys without a name here come as private characters.
              !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        return characters.uppercased()
    }

    init(keyCode: UInt16, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// From a key press. Nil when the key has no name.
    init?(keyCode: UInt16, modifiers: Modifiers, characters: String?) {
        guard let key = Self.keyName(keyCode: keyCode, characters: characters) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, key: key)
    }
}

/// Why a shortcut is not taken, or does not work.
enum ShortcutProblem: Equatable {
    case needsModifier
    case usedBySystem
    /// The other shortcut of agent caffeine has the same keys.
    case usedTwice
    /// macOS refused to register it.
    case usedByAnotherApp

    var text: String {
        switch self {
        case .needsModifier: return "Add Command, Control or Option to the shortcut"
        case .usedBySystem: return "macOS already uses this shortcut"
        case .usedTwice: return "The other shortcut of agent caffeine already uses these keys"
        case .usedByAnotherApp: return "This shortcut is already used by another app"
        }
    }
}

enum ShortcutRules {
    /// Shortcuts that every Mac app or macOS itself answers to. A shortcut
    /// that works in every app would take them away from all of them.
    static let reserved: Set<String> = {
        var all: Set<String> = []
        func add(_ modifiers: Shortcut.Modifiers, _ keys: [String]) {
            for key in keys { all.insert(modifiers.symbols + key) }
        }
        add(.command, ["Q", "W", "H", "M", "C", "V", "X", "A", "Z", "S", "N", "O", "P", "F", "T", ",", "`", "⇥", "Space"])
        add([.shift, .command], ["Z", "Q", "3", "4", "5", "⇥"])
        add([.option, .command], ["⎋", "D", "Space"])
        add([.control, .command], ["Q", "F", "Space"])
        add(.control, ["←", "→", "↑", "↓"])
        return all
    }()

    /// Nil when the shortcut can be registered.
    /// - Parameters:
    ///   - system: the shortcuts that are switched on in System Settings.
    ///   - others: the other shortcuts of agent caffeine.
    static func problem(_ shortcut: Shortcut, system: Set<Shortcut.Keys> = [], others: [Shortcut] = []) -> ShortcutProblem? {
        // Shift alone would take a capital letter away from every app.
        if shortcut.modifiers.isDisjoint(with: [.command, .control, .option]) { return .needsModifier }
        if reserved.contains(shortcut.display) || system.contains(shortcut.keys) { return .usedBySystem }
        if others.contains(where: { $0.keys == shortcut.keys }) { return .usedTwice }
        return nil
    }
}

/// The shortcuts in UserDefaults, as one JSON value. None is set until the
/// user records one.
enum ShortcutStore {
    static let key = "Shortcuts"

    static func load(from defaults: UserDefaults) -> [ShortcutAction: Shortcut] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) else { return [:] }
        var shortcuts: [ShortcutAction: Shortcut] = [:]
        for (name, shortcut) in stored {
            if let action = ShortcutAction(rawValue: name) { shortcuts[action] = shortcut }
        }
        return shortcuts
    }

    static func save(_ shortcuts: [ShortcutAction: Shortcut], to defaults: UserDefaults) {
        guard !shortcuts.isEmpty else { return defaults.removeObject(forKey: key) }
        let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }
}
