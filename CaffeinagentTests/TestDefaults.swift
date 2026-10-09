import XCTest

/// Settings of their own for one test, kept in memory. A real suite leaves a
/// file in ~/Library/Preferences: the system writes an empty one after the
/// values are removed, and again after the file is deleted.
final class TestDefaults: UserDefaults, @unchecked Sendable {
    static let prefix = "caffeinagent-tests-"

    static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Preferences")
    }

    private let lock = NSLock()
    private var values: [String: Any] = [:]

    /// The suite under it is never read or written. It has the name of a
    /// test, so a call that is not handled here shows up in `TestDefaultsGuard`.
    init() {
        super.init(suiteName: Self.prefix + UUID().uuidString)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { values }
    }
}

/// Fails the last test of a class when the class left a settings file of a
/// test in ~/Library/Preferences. It reads the names in the folder and
/// changes nothing. The test bundle names it as its principal class.
@objc(TestDefaultsGuard)
final class TestDefaultsGuard: NSObject, XCTestObservation {
    private var known: Set<String> = []
    private var lastOfClass: XCTestCase?

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    /// `caffeinagent-tests-<UUID>.plist`, and `<Name>Tests.<UUID>.plist` that
    /// a test writes when it makes a suite by hand.
    static func isTestFile(_ name: String) -> Bool {
        name.range(of: #"^(caffeinagent-tests-|[A-Za-z]+Tests\.)[0-9A-F-]{36}\.plist$"#, options: .regularExpression) != nil
    }

    private static func testFiles() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: TestDefaults.directory.path)) ?? []
        return Set(names.filter(isTestFile))
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        known = Self.testFiles()
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        if let last = testSuite.tests.last as? XCTestCase { lastOfClass = last }
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard testCase === lastOfClass else { return }
        // Added first, so it runs after the blocks the test adds.
        testCase.addTeardownBlock { [self] in
            let found = Self.testFiles()
            let left = found.subtracting(known).sorted()
            known = found
            XCTAssertEqual(left, [], "\(type(of: testCase)) left settings files in ~/Library/Preferences. Use TestDefaults().")
        }
    }
}
