import XCTest

final class LegacyBatteryOverrideTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = TestDefaults()
    }

    private var remembered: Bool { defaults.bool(forKey: LegacyBatteryOverride.flagKey) }

    /// - Returns: how often the command ran.
    private func clear(entryExists: Bool, exit code: Int32?) -> Int {
        var runs = 0
        LegacyBatteryOverride.clearLeftover(defaults: defaults, entryExists: { entryExists }) {
            runs += 1
            return code
        }
        return runs
    }

    func testWithNoFlagLeftOnNothingRuns() {
        XCTAssertEqual(clear(entryExists: true, exit: 0), 0)
    }

    func testTheFlagIsForgottenWhenTheCommandEndedWell() {
        defaults.set(true, forKey: LegacyBatteryOverride.flagKey)
        XCTAssertEqual(clear(entryExists: true, exit: 0), 1)
        XCTAssertFalse(remembered)
        XCTAssertEqual(clear(entryExists: true, exit: 0), 0, "Once")
    }

    /// The old code forgot the flag before it knew that the command worked,
    /// so a flag that stayed on was never cleared.
    func testACommandThatFailedIsTriedAgainAtTheNextLaunch() {
        defaults.set(true, forKey: LegacyBatteryOverride.flagKey)
        for code in [1, nil] as [Int32?] {
            XCTAssertEqual(clear(entryExists: true, exit: code), 1)
            XCTAssertTrue(remembered, "\(String(describing: code))")
        }
        XCTAssertEqual(clear(entryExists: true, exit: 0), 1)
        XCTAssertFalse(remembered)
    }

    func testWithoutTheSudoersEntryTheCommandCannotRunAndTheFlagIsForgotten() {
        defaults.set(true, forKey: LegacyBatteryOverride.flagKey)
        XCTAssertEqual(clear(entryExists: false, exit: 0), 0)
        XCTAssertFalse(remembered)
    }
}
