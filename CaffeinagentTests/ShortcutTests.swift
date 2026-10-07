import Carbon
import XCTest

final class ShortcutTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "caffeinagent-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func shortcut(_ modifiers: Shortcut.Modifiers, _ key: String, keyCode: UInt16 = 37) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: modifiers, key: key)
    }

    func testDisplayPutsTheModifiersInTheOrderOfMacOS() {
        XCTAssertEqual(shortcut([.command, .option], "L").display, "⌥⌘L")
        XCTAssertEqual(shortcut([.command, .shift, .option, .control], "L").display, "⌃⌥⇧⌘L")
        XCTAssertEqual(shortcut(.control, "F5", keyCode: 96).display, "⌃F5")
        XCTAssertEqual(shortcut([.control, .option], "Space", keyCode: 49).display, "⌃⌥Space")
    }

    func testTheNameOfAKey() {
        let cases: [(keyCode: UInt16, characters: String?, name: String?)] = [
            (37, "l", "L"),
            (18, "1", "1"),
            (41, "ö", "Ö"),
            (47, ".", "."),
            (49, " ", "Space"),
            (36, "\r", "↩"),
            (96, "\u{F708}", "F5"),
            (126, "\u{F700}", "↑"),
            // No name: a modifier alone, a dead key, a key of a keypad that types nothing.
            (55, nil, nil),
            (33, "", nil),
            (10, "\u{F747}", nil),
            (37, "ll", nil),
        ]
        for c in cases {
            XCTAssertEqual(Shortcut.keyName(keyCode: c.keyCode, characters: c.characters), c.name, "\(c.keyCode)")
        }
        XCTAssertEqual(Shortcut(keyCode: 37, modifiers: [.option, .command], characters: "l"), shortcut([.option, .command], "L"))
        XCTAssertNil(Shortcut(keyCode: 55, modifiers: .command, characters: nil))
    }

    func testCarbonModifiersGoBothWays() {
        // controlKey, optionKey, shiftKey and cmdKey of Carbon.
        XCTAssertEqual(Shortcut.Modifiers.control.carbon, 0x1000)
        XCTAssertEqual(Shortcut.Modifiers.option.carbon, 0x0800)
        XCTAssertEqual(Shortcut.Modifiers.shift.carbon, 0x0200)
        XCTAssertEqual(Shortcut.Modifiers.command.carbon, 0x0100)
        for raw in 0..<16 {
            let modifiers = Shortcut.Modifiers(rawValue: raw)
            XCTAssertEqual(Shortcut.Modifiers(carbon: modifiers.carbon), modifiers)
        }
        // Caps lock and the like are left out.
        XCTAssertEqual(Shortcut.Modifiers(carbon: 0x0100 | 0x0400), .command)
    }

    func testAShortcutNeedsCommandControlOrOption() {
        XCTAssertEqual(ShortcutRules.problem(shortcut([], "L")), .needsModifier)
        XCTAssertEqual(ShortcutRules.problem(shortcut(.shift, "L")), .needsModifier)
        XCTAssertEqual(ShortcutRules.problem(shortcut([], "F5", keyCode: 96)), .needsModifier)
        for modifiers in [Shortcut.Modifiers.command, .control, .option, [.shift, .option]] {
            XCTAssertNil(ShortcutRules.problem(shortcut(modifiers, "L")), "\(modifiers)")
        }
    }

    func testShortcutsOfTheSystemAreRefused() {
        let taken = [
            shortcut(.command, "Q"), shortcut(.command, "C"), shortcut(.command, "V"), shortcut(.command, "W"),
            shortcut(.command, "Space", keyCode: 49), shortcut(.command, "⇥", keyCode: 48), shortcut([.shift, .command], "4"),
            shortcut([.option, .command], "⎋", keyCode: 53), shortcut([.control, .command], "Q"), shortcut(.control, "↑", keyCode: 126),
        ]
        for shortcut in taken {
            XCTAssertEqual(ShortcutRules.problem(shortcut), .usedBySystem, shortcut.display)
        }
        XCTAssertNil(ShortcutRules.problem(shortcut([.option, .command], "L")))
        XCTAssertNil(ShortcutRules.problem(shortcut([.control, .option], "Q")))
        // What System Settings has switched on, by key and modifiers.
        let system: Set<Shortcut.Keys> = [Shortcut.Keys(keyCode: 37, modifiers: [.option, .command])]
        XCTAssertEqual(ShortcutRules.problem(shortcut([.option, .command], "L"), system: system), .usedBySystem)
        XCTAssertNil(ShortcutRules.problem(shortcut([.control, .command], "L"), system: system))
    }

    func testTwoActionsCannotShareTheKeys() {
        let other = shortcut([.option, .command], "L")
        XCTAssertEqual(ShortcutRules.problem(shortcut([.option, .command], "L"), others: [other]), .usedTwice)
        XCTAssertNil(ShortcutRules.problem(shortcut([.option, .command], "P", keyCode: 35), others: [other]))
    }

    func testTheWordsOfAProblem() {
        XCTAssertEqual(ShortcutProblem.usedByAnotherApp.text, "This shortcut is already used by another app")
        for problem in [ShortcutProblem.needsModifier, .usedBySystem, .usedTwice, .usedByAnotherApp] {
            XCTAssertFalse(problem.text.hasSuffix("."), problem.text)
            XCTAssertFalse(problem.text.contains("\u{2014}"), problem.text)
        }
        XCTAssertEqual(ShortcutAction.toggle.title, "Turn agent caffeine on or off")
        XCTAssertEqual(ShortcutAction.pauseOneHour.title, "Pause for 1 hour")
    }

    // MARK: Defaults

    private let toggleDefault = Shortcut(keyCode: 8, modifiers: [.control, .option, .command], key: "C")
    private let pauseDefault = Shortcut(keyCode: 35, modifiers: [.control, .option, .command], key: "P")

    func testTheDefaults() {
        XCTAssertEqual(ShortcutAction.toggle.defaultShortcut, toggleDefault)
        XCTAssertEqual(ShortcutAction.pauseOneHour.defaultShortcut, pauseDefault)
        XCTAssertEqual(toggleDefault.display, "⌃⌥⌘C")
        XCTAssertEqual(pauseDefault.display, "⌃⌥⌘P")
        XCTAssertEqual(Set(ShortcutAction.allCases.map(\.defaultShortcut.keys)).count, ShortcutAction.allCases.count)
        for action in ShortcutAction.allCases {
            XCTAssertNil(ShortcutRules.problem(action.defaultShortcut), action.rawValue)
        }
    }

    // MARK: Defaults in the user's keyboard layout

    private struct Layout: KeyLayout {
        var keys: [UInt16: String]
        /// The keys with Command held, when they are not the same.
        var commandKeys: [UInt16: String]?
        func characters(keyCode: UInt16, command: Bool) -> String? { (command ? commandKeys ?? keys : keys)[keyCode] }
    }

    /// The letter keys of the American layout, and of Dvorak on the same keys.
    private let qwerty = Layout(keys: [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e",
        15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 41: ";", 45: "n", 46: "m",
    ])
    private let dvorak = Layout(keys: [
        0: "a", 1: "o", 2: "e", 3: "u", 4: "d", 5: "i", 6: ";", 7: "q", 8: "j", 9: "k", 11: "x", 12: "'", 13: ",", 14: ".",
        15: "p", 16: "f", 17: "y", 31: "r", 32: "g", 34: "c", 35: "l", 37: "n", 38: "h", 40: "t", 41: "s", 45: "b", 46: "m",
    ])

    func testTheDefaultsOfTheAmericanLayout() {
        XCTAssertEqual(ShortcutDefaults.resolve(in: [qwerty]), [.toggle: toggleDefault, .pauseOneHour: pauseDefault])
        XCTAssertEqual(ShortcutDefaults.resolve(in: []), [.toggle: toggleDefault, .pauseOneHour: pauseDefault])
        XCTAssertEqual(ShortcutDefaults.american, [.toggle: toggleDefault, .pauseOneHour: pauseDefault])
    }

    /// The label and the key agree: C is where Dvorak has its C.
    func testTheDefaultsGoToTheKeysThatTypeTheirLetters() {
        let defaults = ShortcutDefaults.resolve(in: [dvorak, qwerty])
        XCTAssertEqual(defaults[.toggle], Shortcut(keyCode: 34, modifiers: [.control, .option, .command], key: "C"))
        XCTAssertEqual(defaults[.pauseOneHour], Shortcut(keyCode: 15, modifiers: [.control, .option, .command], key: "P"))
        XCTAssertEqual(defaults[.toggle]?.display, "⌃⌥⌘C")
        for (action, shortcut) in defaults {
            XCTAssertEqual(dvorak.characters(keyCode: shortcut.keyCode, command: true)?.uppercased(), shortcut.key, action.rawValue)
            XCTAssertNil(ShortcutRules.problem(shortcut), action.rawValue)
        }
    }

    /// "Dvorak - QWERTY ⌘" types Dvorak, and the American letters while
    /// Command is held. The defaults hold Command, so macOS sends the
    /// American keys for them.
    func testALayoutWithOtherLettersUnderCommandGivesTheKeysOfTheShortcut() {
        let dvorakQwertyCommand = Layout(keys: dvorak.keys, commandKeys: qwerty.keys)
        XCTAssertEqual(ShortcutDefaults.resolve(in: [dvorakQwertyCommand]), [.toggle: toggleDefault, .pauseOneHour: pauseDefault])
        XCTAssertEqual(ShortcutDefaults.keyCode(typing: "C", in: dvorakQwertyCommand, preferred: 8, command: false), 34)
    }

    /// The layouts of macOS itself, read and not selected.
    func testTheLayoutsOfMacOS() throws {
        func keys(_ id: String) throws -> [ShortcutAction: UInt16] {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first,
                  let layout = SystemKeyLayout(source) else { throw XCTSkip("\(id) is not on this Mac") }
            return ShortcutDefaults.resolve(in: [layout]).mapValues(\.keyCode)
        }
        XCTAssertEqual(try keys("com.apple.keylayout.US"), [.toggle: 8, .pauseOneHour: 35])
        XCTAssertEqual(try keys("com.apple.keylayout.Dvorak"), [.toggle: 34, .pauseOneHour: 15])
        XCTAssertEqual(try keys("com.apple.keylayout.DVORAK-QWERTYCMD"), [.toggle: 8, .pauseOneHour: 35])
    }

    func testALayoutThatTypesCapitalsCounts() {
        let capitals = Layout(keys: [20: "C", 21: "P"])
        XCTAssertEqual(ShortcutDefaults.resolve(in: [capitals]).mapValues(\.keyCode), [.toggle: 20, .pauseOneHour: 21])
    }

    func testALayoutWithoutTheLettersGivesWayToTheNextOne() {
        let cyrillic = Layout(keys: [8: "с", 35: "з"])
        XCTAssertEqual(ShortcutDefaults.resolve(in: [cyrillic, dvorak]).mapValues(\.keyCode), [.toggle: 34, .pauseOneHour: 15])
        XCTAssertEqual(ShortcutDefaults.resolve(in: [cyrillic]), ShortcutDefaults.american)
    }

    /// One letter alone is not taken: here C types on the key the American
    /// P takes, and both defaults would have the same key.
    func testALayoutWithOneLetterOnlyGivesNone() {
        let half = Layout(keys: [35: "c"])
        XCTAssertEqual(ShortcutDefaults.keyCode(typing: "C", in: half, preferred: 8, command: true), 35)
        XCTAssertNil(ShortcutDefaults.keyCode(typing: "P", in: half, preferred: 35, command: true))
        XCTAssertEqual(ShortcutDefaults.resolve(in: [half]), ShortcutDefaults.american)
    }

    func testAResolvedDefaultIsUsedAndNeverStored() {
        var choices = ShortcutStore.load(from: defaults)
        choices.defaults = ShortcutDefaults.resolve(in: [dvorak])
        XCTAssertEqual(choices.shortcuts.mapValues(\.keyCode), [.toggle: 34, .pauseOneHour: 15])
        XCTAssertFalse(choices.isChanged(.toggle))
        ShortcutStore.save(choices, to: defaults)
        XCTAssertNil(defaults.object(forKey: ShortcutStore.key))
        XCTAssertNil(defaults.object(forKey: ShortcutStore.clearedKey))
        XCTAssertEqual(ShortcutStore.load(from: defaults).shortcuts, [.toggle: toggleDefault, .pauseOneHour: pauseDefault])

        // A shortcut the user recorded on the key of a default takes it.
        choices.set(Shortcut(keyCode: 34, modifiers: [.control, .option, .command], key: "C"), for: .pauseOneHour)
        XCTAssertEqual(choices.shortcuts.mapValues(\.keyCode), [.pauseOneHour: 34])
    }

    func testAnActionTheUserNeverChangedHasItsDefault() {
        let choices = ShortcutStore.load(from: defaults)
        XCTAssertEqual(choices, ShortcutChoices())
        XCTAssertEqual(choices.shortcuts, [.toggle: toggleDefault, .pauseOneHour: pauseDefault])
        XCTAssertFalse(choices.isChanged(.toggle))
    }

    func testARecordedShortcutStaysAndTheOtherActionHasItsDefault() {
        // What a build without defaults wrote.
        defaults.set(Data(#"{"toggle":{"keyCode":37,"modifiers":10,"key":"L"}}"#.utf8), forKey: ShortcutStore.key)
        let choices = ShortcutStore.load(from: defaults)
        XCTAssertEqual(choices.shortcuts, [.toggle: shortcut([.option, .command], "L"), .pauseOneHour: pauseDefault])
        XCTAssertTrue(choices.isChanged(.toggle))
        XCTAssertFalse(choices.isChanged(.pauseOneHour))
    }

    func testAClearedShortcutStaysCleared() {
        var choices = ShortcutChoices()
        choices.set(nil, for: .toggle)
        XCTAssertEqual(choices.shortcuts, [.pauseOneHour: pauseDefault])
        ShortcutStore.save(choices, to: defaults)
        XCTAssertNil(defaults.object(forKey: ShortcutStore.key))
        XCTAssertEqual(defaults.stringArray(forKey: ShortcutStore.clearedKey), ["toggle"])
        let loaded = ShortcutStore.load(from: defaults)
        XCTAssertEqual(loaded, choices)
        XCTAssertEqual(loaded.shortcuts, [.pauseOneHour: pauseDefault])
        // A cleared shortcut that was recorded before.
        choices.set(shortcut([.option, .command], "L"), for: .pauseOneHour)
        choices.set(nil, for: .pauseOneHour)
        ShortcutStore.save(choices, to: defaults)
        XCTAssertEqual(ShortcutStore.load(from: defaults).shortcuts, [:])
    }

    func testADefaultIsNeverWritten() {
        var choices = ShortcutStore.load(from: defaults)
        ShortcutStore.save(choices, to: defaults)
        XCTAssertNil(defaults.object(forKey: ShortcutStore.key))
        XCTAssertNil(defaults.object(forKey: ShortcutStore.clearedKey))
        choices.set(shortcut([.option, .command], "L"), for: .toggle)
        ShortcutStore.save(choices, to: defaults)
        XCTAssertEqual(ShortcutStore.load(from: defaults).recorded, [.toggle: shortcut([.option, .command], "L")])
        XCTAssertEqual(ShortcutStore.load(from: defaults).shortcuts[.pauseOneHour], pauseDefault)
    }

    func testResetGivesTheDefaultBack() {
        var choices = ShortcutChoices()
        choices.set(shortcut([.option, .command], "L"), for: .toggle)
        choices.set(nil, for: .pauseOneHour)
        choices.reset(.toggle)
        choices.reset(.pauseOneHour)
        XCTAssertEqual(choices, ShortcutChoices())
        ShortcutStore.save(choices, to: defaults)
        XCTAssertNil(defaults.object(forKey: ShortcutStore.key))
        XCTAssertNil(defaults.object(forKey: ShortcutStore.clearedKey))
    }

    func testRecordingAfterAClearTakesTheActionOutOfTheClearedOnes() {
        var choices = ShortcutChoices()
        choices.set(nil, for: .toggle)
        choices.set(shortcut([.option, .command], "L"), for: .toggle)
        XCTAssertEqual(choices.cleared, [])
        // A list that names an action with a recorded shortcut is not believed.
        ShortcutStore.save(choices, to: defaults)
        defaults.set(["toggle", "later"], forKey: ShortcutStore.clearedKey)
        XCTAssertEqual(ShortcutStore.load(from: defaults), choices)
    }

    func testADefaultGivesWayToTheShortcutOfTheUser() {
        var choices = ShortcutChoices()
        // The keys count, not what stands on the key.
        choices.set(Shortcut(keyCode: 35, modifiers: [.control, .option, .command], key: "L"), for: .toggle)
        XCTAssertEqual(choices.shortcuts, [.toggle: Shortcut(keyCode: 35, modifiers: [.control, .option, .command], key: "L")])
        XCTAssertNil(choices.defaultProblem(for: .pauseOneHour, system: []))
        // The rule for a new shortcut looks at the recorded ones alone, so
        // the default of the other action does not stand in the way.
        XCTAssertNil(ShortcutRules.problem(pauseDefault, others: Array(ShortcutChoices().recorded.values)))
        choices.set(nil, for: .toggle)
        XCTAssertEqual(choices.shortcuts, [.pauseOneHour: pauseDefault])
        // A reset does not take the keys of the user either.
        choices = ShortcutChoices()
        choices.set(toggleDefault, for: .pauseOneHour)
        XCTAssertEqual(choices.shortcuts, [.pauseOneHour: toggleDefault])
    }

    func testADefaultThatMacOSUsesIsNotRegistered() {
        let system: Set<Shortcut.Keys> = [toggleDefault.keys]
        var choices = ShortcutChoices()
        XCTAssertEqual(choices.defaultProblem(for: .toggle, system: system), .usedBySystem)
        XCTAssertNil(choices.defaultProblem(for: .pauseOneHour, system: system))
        XCTAssertNil(choices.defaultProblem(for: .toggle, system: []))
        // The field still shows it.
        XCTAssertEqual(choices.shortcuts[.toggle], toggleDefault)
        // Not a default any more: recorded or cleared.
        choices.set(toggleDefault, for: .toggle)
        XCTAssertNil(choices.defaultProblem(for: .toggle, system: system))
        choices.set(nil, for: .toggle)
        XCTAssertNil(choices.defaultProblem(for: .toggle, system: system))
    }

    func testSaveAndLoad() {
        let shortcuts: [ShortcutAction: Shortcut] = [.toggle: shortcut([.option, .command], "L"), .pauseOneHour: shortcut([.control, .option], "P", keyCode: 35)]
        ShortcutStore.save(ShortcutChoices(recorded: shortcuts), to: defaults)
        XCTAssertEqual(ShortcutStore.load(from: defaults).shortcuts, shortcuts)
        ShortcutStore.save(ShortcutChoices(recorded: [.toggle: shortcut(.control, "F5", keyCode: 96)]), to: defaults)
        XCTAssertEqual(ShortcutStore.load(from: defaults).recorded, [.toggle: shortcut(.control, "F5", keyCode: 96)])
        ShortcutStore.save(ShortcutChoices(), to: defaults)
        XCTAssertNil(defaults.object(forKey: ShortcutStore.key))
    }

    func testWhatCannotBeReadGivesTheDefaults() {
        defaults.set(Data("no json".utf8), forKey: ShortcutStore.key)
        XCTAssertEqual(ShortcutStore.load(from: defaults), ShortcutChoices())
        // An action that this build does not know is left out.
        defaults.set(Data(#"{"later":{"keyCode":37,"modifiers":8,"key":"L"},"toggle":{"keyCode":35,"modifiers":10,"key":"P"}}"#.utf8), forKey: ShortcutStore.key)
        XCTAssertEqual(ShortcutStore.load(from: defaults).recorded, [.toggle: shortcut([.option, .command], "P", keyCode: 35)])
    }
}
