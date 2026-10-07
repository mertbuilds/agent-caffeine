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

extension ShortcutAction {
    /// The shortcut of an action that the user never changed, on a
    /// keyboard layout like the American one. Three modifiers, so it takes
    /// no key that another app or macOS uses. `ShortcutDefaults` moves it
    /// to the key that types the same letter in the user's layout.
    var defaultShortcut: Shortcut {
        switch self {
        case .toggle: return Shortcut(keyCode: 8, modifiers: [.control, .option, .command], key: "C")
        case .pauseOneHour: return Shortcut(keyCode: 35, modifiers: [.control, .option, .command], key: "P")
        }
    }
}

/// What the keys type in one keyboard layout.
protocol KeyLayout {
    /// What the key types with no modifier held. Nil for a key that types
    /// nothing.
    func characters(keyCode: UInt16) -> String?
}

/// The default shortcuts mean the letters C and P, not two places on the
/// keyboard: on Dvorak the place of the American C types J. So each
/// default goes to the key that types its letter.
enum ShortcutDefaults {
    /// The defaults on a keyboard layout like the American one.
    static let american = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })

    /// The key codes of a keyboard.
    static let keyCodes: ClosedRange<UInt16> = 0...127

    /// The defaults in the first layout that has a key for every letter.
    /// A layout that lacks one letter gives none: its other letter could
    /// stand on the key the American default of the first one takes.
    /// - Parameter layouts: the layout in use first, then the ones to fall
    ///   back on. With none of them, the American defaults.
    static func resolve(in layouts: [KeyLayout]) -> [ShortcutAction: Shortcut] {
        for layout in layouts {
            var found: [ShortcutAction: Shortcut] = [:]
            for (action, shortcut) in american {
                guard let keyCode = keyCode(typing: shortcut.key, in: layout, preferred: shortcut.keyCode) else { break }
                found[action] = Shortcut(keyCode: keyCode, modifiers: shortcut.modifiers, key: shortcut.key)
            }
            if found.count == american.count { return found }
        }
        return american
    }

    /// The key that types the letter. The preferred key when it does, else
    /// the first one.
    static func keyCode(typing letter: String, in layout: KeyLayout, preferred: UInt16) -> UInt16? {
        let letter = letter.lowercased()
        return ([preferred] + Array(keyCodes)).first { layout.characters(keyCode: $0)?.lowercased() == letter }
    }
}

/// What the user did with the shortcuts. An action that is in neither
/// part was never changed and has its default.
struct ShortcutChoices: Equatable {
    /// The shortcuts the user recorded.
    var recorded: [ShortcutAction: Shortcut] = [:]
    /// The actions whose shortcut the user cleared.
    var cleared: Set<ShortcutAction> = []
    /// The default of each action in the user's keyboard layout. Never
    /// stored: see `ShortcutStore`.
    var defaults = ShortcutDefaults.american

    /// Nil clears the shortcut.
    mutating func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        recorded[action] = shortcut
        if shortcut == nil { cleared.insert(action) } else { cleared.remove(action) }
    }

    /// Back to the default.
    mutating func reset(_ action: ShortcutAction) {
        recorded[action] = nil
        cleared.remove(action)
    }

    /// True when the user recorded or cleared the shortcut of the action.
    func isChanged(_ action: ShortcutAction) -> Bool {
        recorded[action] != nil || cleared.contains(action)
    }

    /// The shortcut of each action. A default gives way to a shortcut the
    /// user recorded for another action with the same keys.
    var shortcuts: [ShortcutAction: Shortcut] {
        var shortcuts = recorded
        for action in ShortcutAction.allCases where !isChanged(action) {
            guard let fallback = defaults[action] else { continue }
            if !recorded.values.contains(where: { $0.keys == fallback.keys }) { shortcuts[action] = fallback }
        }
        return shortcuts
    }

    /// Why the default of an action must not be registered. Nil for a
    /// shortcut the user recorded: the rules checked it when it was set.
    /// - Parameter system: the shortcuts that are switched on in System Settings.
    func defaultProblem(for action: ShortcutAction, system: Set<Shortcut.Keys>) -> ShortcutProblem? {
        guard !isChanged(action), let shortcut = shortcuts[action] else { return nil }
        return ShortcutRules.problem(shortcut, system: system)
    }
}

/// What the user did with the shortcuts, in UserDefaults: the recorded
/// ones as one JSON value, the cleared actions as a list of names. A
/// default is never written, so a later default reaches every user who
/// did not change the shortcut.
enum ShortcutStore {
    static let key = "Shortcuts"
    static let clearedKey = "ShortcutsCleared"

    static func load(from defaults: UserDefaults) -> ShortcutChoices {
        var choices = ShortcutChoices()
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (name, shortcut) in stored {
                if let action = ShortcutAction(rawValue: name) { choices.recorded[action] = shortcut }
            }
        }
        for name in defaults.stringArray(forKey: clearedKey) ?? [] {
            if let action = ShortcutAction(rawValue: name), choices.recorded[action] == nil { choices.cleared.insert(action) }
        }
        return choices
    }

    static func save(_ choices: ShortcutChoices, to defaults: UserDefaults) {
        if choices.cleared.isEmpty {
            defaults.removeObject(forKey: clearedKey)
        } else {
            defaults.set(choices.cleared.map(\.rawValue).sorted(), forKey: clearedKey)
        }
        guard !choices.recorded.isEmpty else { return defaults.removeObject(forKey: key) }
        let stored = Dictionary(uniqueKeysWithValues: choices.recorded.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }
}
