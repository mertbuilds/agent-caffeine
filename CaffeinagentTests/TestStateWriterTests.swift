import XCTest

final class TestStateWriterTests: XCTestCase {
    private var directory: URL!
    private var store: HoldStore!
    private var defaults: TestDefaults!
    private var lock: HoldStore.AppLock?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("test-state-\(UUID().uuidString)/holds")
        store = HoldStore(directory: directory)
        defaults = TestDefaults()
        lock = HoldStore.AppLock(store: store)
    }

    override func tearDownWithError() throws {
        lock = nil
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private var file: URL { store.home.appendingPathComponent(HoldStore.stateName) }
    private var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    private func state(at seconds: TimeInterval = 0) -> TestState {
        TestState(
            at: 1_791_200_000 + seconds, app: TestState.App(version: "1.0.3", build: "17", path: "/Applications/Agent Caffeine.app", pid: 1),
            on: true, mode: "agentWorking", entitlement: "licensed",
            decision: TestState.Decision(hold: false, headline: "noAgents", reason: nil, stop: false, assertion: false),
            flag: TestState.Flag(wanted: false, helper: "enabled", setup: "ready", set: false), gate: "open", agents: [], holds: [],
            jobs: TestState.Jobs(on: false, status: "off", found: 0, enabled: 0, alarm: nil, holds: [], history: []), notices: []
        )
    }

    private var tools: HoldTools {
        HoldTools(store: store, stateForTests: { [unowned self] in self.defaults.bool(forKey: HoldStore.stateSwitchKey) })
    }

    // MARK: Gate

    func testNothingIsWrittenWhileTheSwitchIsOff() {
        let writer = TestStateWriter(store: store, defaults: defaults)
        var asked = 0
        XCTAssertFalse(writer.update {
            asked += 1
            return state()
        })
        XCTAssertFalse(writer.isOn)
        XCTAssertFalse(exists)
        XCTAssertEqual(asked, 0, "The state is not even made")
    }

    func testTheSwitchIsReadAtEveryCall() throws {
        let writer = TestStateWriter(store: store, defaults: defaults)
        defaults.set(true, forKey: TestState.defaultsKey)
        XCTAssertTrue(writer.update { state() })
        XCTAssertEqual(try JSONDecoder().decode(TestState.self, from: Data(contentsOf: file)), state())
        XCTAssertTrue(writer.update { state(at: 5) })
        XCTAssertEqual(try JSONDecoder().decode(TestState.self, from: Data(contentsOf: file)).at, 1_791_200_005)
        defaults.set(false, forKey: TestState.defaultsKey)
        XCTAssertFalse(writer.update { state(at: 10) })
        XCTAssertFalse(exists, "Off removes the file")
        defaults.set(true, forKey: TestState.defaultsKey)
        XCTAssertTrue(writer.update { state(at: 15) })
        XCTAssertTrue(exists)
        writer.remove()
        XCTAssertFalse(exists)
    }

    func testAFileOfAnEarlierRunGoesWhenTheSwitchIsOff() throws {
        XCTAssertTrue(store.writeState(Data("{}".utf8)))
        XCTAssertTrue(exists)
        TestStateWriter(store: store, defaults: defaults).update { state() }
        XCTAssertFalse(exists)
    }

    func testTheFileIsForTheUserAlone() throws {
        defaults.set(true, forKey: TestState.defaultsKey)
        TestStateWriter(store: store, defaults: defaults).update { state() }
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode, 0o600)
        let folder = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int)
        XCTAssertEqual(folder, 0o700)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.home.path)
        XCTAssertEqual(names.filter { $0.hasPrefix(".draft-") }, [], "Written whole and renamed")
    }

    // MARK: Command line

    func testStatusWithDetailPrintsTheState() throws {
        defaults.set(true, forKey: HoldStore.stateSwitchKey)
        TestStateWriter(store: store, defaults: defaults).update { state() }
        let line = HoldCommands.status(json: true, detail: true, tools: tools).out[0]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["stateForTests"] as? Bool, true)
        XCTAssertNil(object["detailNote"])
        let detail = try XCTUnwrap(object["detail"] as? [String: Any])
        XCTAssertEqual(detail["gate"] as? String, "open")
        XCTAssertEqual((detail["app"] as? [String: Any])?["build"] as? String, "17")
        XCTAssertEqual(HoldCommands.status(json: false, detail: true, tools: tools).out.count, 3)
    }

    func testStatusSaysPlainlyWhyThereIsNoState() throws {
        func note(json: Bool = true) throws -> String? {
            let out = HoldCommands.status(json: json, detail: true, tools: tools).out
            guard json else { return out.last }
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out[0].utf8)) as? [String: Any])
            XCTAssertNil(object["detail"])
            return object["detailNote"] as? String
        }
        XCTAssertEqual(try note(), HoldCommands.stateSwitchOff)
        XCTAssertEqual(try note(json: false), HoldCommands.stateSwitchOff)
        XCTAssertTrue(HoldCommands.stateSwitchOff.contains("defaults write com.caffeinagent.app StateForTests -bool true"))
        defaults.set(true, forKey: HoldStore.stateSwitchKey)
        XCTAssertEqual(try note(), HoldCommands.stateNotWritten, "A build with no state export")
        lock = nil
        XCTAssertEqual(try note(), HoldCommands.stateNeedsApp)
        XCTAssertNil(store.stateData())
    }

    func testStatusWithoutDetailIsAsItWas() throws {
        defaults.set(true, forKey: HoldStore.stateSwitchKey)
        TestStateWriter(store: store, defaults: defaults).update { state() }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(HoldCommands.status(json: true, tools: tools).out[0].utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["appRunning", "holds", "line"])
        XCTAssertEqual(try? HoldArguments.parse(["status", "--json", "--detail"]).get(), .status(json: true, detail: true))
        XCTAssertEqual(try? HoldArguments.parse(["status", "--detail"]).get(), .status(json: false, detail: true))
    }
}
