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

    func testNoShortcutIsSetUntilTheUserRecordsOne() {
        XCTAssertEqual(ShortcutStore.load(from: defaults), [:])
    }

    func testSaveAndLoad() {
        let shortcuts: [ShortcutAction: Shortcut] = [.toggle: shortcut([.option, .command], "L"), .pauseOneHour: shortcut([.control, .option], "P", keyCode: 35)]
        ShortcutStore.save(shortcuts, to: defaults)
        XCTAssertEqual(ShortcutStore.load(from: defaults), shortcuts)
        ShortcutStore.save([.toggle: shortcut(.control, "F5", keyCode: 96)], to: defaults)
        XCTAssertEqual(ShortcutStore.load(from: defaults), [.toggle: shortcut(.control, "F5", keyCode: 96)])
        ShortcutStore.save([:], to: defaults)
        XCTAssertNil(defaults.object(forKey: ShortcutStore.key))
    }

    func testWhatCannotBeReadGivesNoShortcut() {
        defaults.set(Data("no json".utf8), forKey: ShortcutStore.key)
        XCTAssertEqual(ShortcutStore.load(from: defaults), [:])
        // An action that this build does not know is left out.
        defaults.set(Data(#"{"later":{"keyCode":37,"modifiers":8,"key":"L"},"toggle":{"keyCode":35,"modifiers":10,"key":"P"}}"#.utf8), forKey: ShortcutStore.key)
        XCTAssertEqual(ShortcutStore.load(from: defaults), [.toggle: shortcut([.option, .command], "P", keyCode: 35)])
    }
}
