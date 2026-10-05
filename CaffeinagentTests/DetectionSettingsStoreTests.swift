import XCTest

final class DetectionSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "caffeinagent-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testFreshInstallGivesDefaults() {
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), DetectionSettings())
        XCTAssertNil(defaults.data(forKey: DetectionSettingsStore.key))
    }

    func testSaveAndLoad() {
        var settings = DetectionSettings()
        settings.releaseAfterState = 600
        settings.batteryFloorPercent = 35
        settings.stayAwakeLidClosedOnBattery = false
        settings.agentRules = ["pi": .ignore, "codex": .alwaysWorkingWhileOpen]
        settings.userAgentNames = ["mytool"]
        DetectionSettingsStore.save(settings, to: defaults)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), settings)
    }

    func testMissingKeysKeepTheirDefaults() {
        defaults.set(Data(#"{"waitingHold":60}"#.utf8), forKey: DetectionSettingsStore.key)
        var want = DetectionSettings()
        want.waitingHold = 60
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), want)
    }

    func testUnreadableSettingsGiveDefaults() {
        defaults.set(Data("not json".utf8), forKey: DetectionSettingsStore.key)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), DetectionSettings())
        defaults.set(Data(#"{"waitingHold":"long"}"#.utf8), forKey: DetectionSettingsStore.key)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), DetectionSettings())
    }

    func testMigrationKeepsOnlyUnknownNames() {
        let migrated = DetectionSettingsStore.migrated(allowlist: ["claude", "Codex", "mytool", "gemini-cli", "other-agent", "mytool"], knownDefaults: nil)
        XCTAssertEqual(migrated.userAgentNames, ["mytool", "other-agent"])
        XCTAssertEqual(migrated.agentRules, [:])
    }

    func testMigrationIgnoresAnAgentTheUserTookOffTheList() {
        let known = ["claude", "codex", "pi", "gemini", "gemini-cli", "trae", "trae-cn"]
        let migrated = DetectionSettingsStore.migrated(allowlist: ["codex", "gemini-cli", "mytool"], knownDefaults: known)
        XCTAssertEqual(migrated.userAgentNames, ["mytool"])
        // Gemini keeps one of its names. Claude Code was found without the
        // list. Agents the old build never offered are new, not removed.
        XCTAssertEqual(migrated.agentRules, ["pi": .ignore, "trae": .ignore])
    }

    func testOldAllowlistIsMigratedOnce() {
        defaults.set(["claude", "mytool"], forKey: DetectionSettingsStore.legacyAllowlistKey)
        defaults.set(["claude", "pi"], forKey: DetectionSettingsStore.legacyKnownDefaultsKey)
        let first = DetectionSettingsStore.load(from: defaults)
        XCTAssertEqual(first.userAgentNames, ["mytool"])
        XCTAssertEqual(first.agentRules, ["pi": .ignore])
        XCTAssertNil(defaults.object(forKey: DetectionSettingsStore.legacyAllowlistKey))
        XCTAssertNil(defaults.object(forKey: DetectionSettingsStore.legacyKnownDefaultsKey))
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), first)
    }

    func testSavedSettingsWinOverALeftOverAllowlist() {
        var settings = DetectionSettings()
        settings.userAgentNames = ["kept"]
        DetectionSettingsStore.save(settings, to: defaults)
        defaults.set(["mytool"], forKey: DetectionSettingsStore.legacyAllowlistKey)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults).userAgentNames, ["kept"])
        XCTAssertNil(defaults.object(forKey: DetectionSettingsStore.legacyAllowlistKey))
    }
}
