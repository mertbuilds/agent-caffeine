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
        XCTAssertTrue(want.displayOffLidClosed, "On for settings of a build that did not have it")
        want.displayOffLidClosed = false
        DetectionSettingsStore.save(want, to: defaults)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), want)
    }

    func testNumbersOutOfRangeAreNotTaken() throws {
        func decode(_ json: String) throws -> DetectionSettings {
            try JSONDecoder().decode(DetectionSettings.self, from: Data(json.utf8))
        }
        let defaults = DetectionSettings()
        let bad = try decode(#"{"releaseAfterState":0,"releaseAfterActivity":-30,"waitingHold":0.5,"weakEvidenceCap":-1,"batteryFloorPercent":0}"#)
        XCTAssertEqual(bad.releaseAfterState, defaults.releaseAfterState)
        XCTAssertEqual(bad.releaseAfterActivity, defaults.releaseAfterActivity)
        XCTAssertEqual(bad.waitingHold, defaults.waitingHold)
        XCTAssertEqual(bad.weakEvidenceCap, defaults.weakEvidenceCap)
        XCTAssertEqual(bad.batteryFloorPercent, 5)

        let huge = try decode(#"{"releaseAfterState":1e300,"releaseAfterActivity":90000,"waitingHold":86400,"weakEvidenceCap":1e12,"batteryFloorPercent":100}"#)
        XCTAssertEqual(huge.releaseAfterState, 86_400)
        XCTAssertEqual(huge.releaseAfterActivity, 86_400)
        XCTAssertEqual(huge.waitingHold, 86_400)
        XCTAssertEqual(huge.weakEvidenceCap, 86_400)
        XCTAssertEqual(huge.batteryFloorPercent, 50)
        XCTAssertEqual(try decode(#"{"batteryFloorPercent":-7}"#).batteryFloorPercent, 5)

        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let odd = try decoder.decode(DetectionSettings.self, from: Data(#"{"releaseAfterState":"nan","waitingHold":"inf","weakEvidenceCap":"-inf"}"#.utf8))
        XCTAssertEqual(odd, defaults)

        let fine = try decode(#"{"releaseAfterState":1,"releaseAfterActivity":45,"waitingHold":3600,"batteryFloorPercent":35}"#)
        XCTAssertEqual(fine.releaseAfterState, 1)
        XCTAssertEqual(fine.releaseAfterActivity, 45)
        XCTAssertEqual(fine.waitingHold, 3600)
        XCTAssertEqual(fine.batteryFloorPercent, 35)

        self.defaults.set(Data(#"{"releaseAfterState":0,"batteryFloorPercent":99}"#.utf8), forKey: DetectionSettingsStore.key)
        let loaded = DetectionSettingsStore.load(from: self.defaults)
        XCTAssertEqual(loaded.releaseAfterState, defaults.releaseAfterState)
        XCTAssertEqual(loaded.batteryFloorPercent, 50)
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
