import XCTest

final class ManualHoldTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)

    private var directory: URL!
    private var store: HoldStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("holds-\(UUID().uuidString)/holds")
        store = HoldStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    private func timed(_ id: String = "aaaa0001", length: TimeInterval = 1800, reason: String? = nil, from seconds: TimeInterval = 0) -> ManualHold {
        .timed(id: id, length: length, reason: reason, now: at(seconds))
    }

    private func command(_ id: String = "bbbb0001", pid: Int32 = 500, pidStart: TimeInterval = 1_791_199_000, name: String = "/opt/homebrew/bin/ffmpeg") -> ManualHold {
        .command(id: id, holder: ProcessIdentity(pid: pid, startTime: pidStart), command: name, now: at(0))
    }

    private func setModified(_ id: String, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.appendingPathComponent("\(id).json").path)
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
    }

    // MARK: The length

    func testTheLengthIsSecondsMinutesOrHours() {
        XCTAssertEqual(HoldDuration.parse("90s"), 90)
        XCTAssertEqual(HoldDuration.parse("30m"), 1800)
        XCTAssertEqual(HoldDuration.parse("2h"), 7200)
        XCTAssertEqual(HoldDuration.parse("2H"), 7200)
        XCTAssertEqual(HoldDuration.parse("1h30m"), 5400)
    }

    func testWhatIsNoLength() {
        for text in ["", "30", "m", "30x", "-5m", "1.5h", "0m", "0s", "30 m", "h2", "9999999h"] {
            XCTAssertNil(HoldDuration.parse(text), text)
        }
    }

    // MARK: The text

    func testAReasonIsOneShortLine() {
        XCTAssertEqual(ManualHold.clean("  Nightly \n backup\t\u{1b}[31m ", limit: 80), "Nightly backup [31m")
        XCTAssertEqual(ManualHold.clean(String(repeating: "a", count: 200), limit: 80)?.count, 80)
        XCTAssertNil(ManualHold.clean(" \n ", limit: 80))
        XCTAssertNil(ManualHold.clean(nil, limit: 80))
        XCTAssertEqual(timed(reason: "render\nthe film").reason, "render the film")
    }

    func testTheCommandIsNamedWithoutItsFolder() {
        XCTAssertEqual(command().command, "ffmpeg")
        XCTAssertEqual(command().title, "ffmpeg")
        XCTAssertEqual(command().subject, "ffmpeg")
        XCTAssertEqual(timed().title, "Command line")
        XCTAssertEqual(timed().subject, "A command")
        XCTAssertEqual(timed(reason: "Nightly backup").title, "Nightly backup")
    }

    func testAnIDIsAFileName() {
        XCTAssertTrue(ManualHold.isValidID(ManualHold.newID()))
        XCTAssertEqual(ManualHold.newID().count, 8)
        for id in ["", "../x", "a/b", "A1", "a.json", String(repeating: "a", count: 33)] {
            XCTAssertFalse(ManualHold.isValidID(id), id)
        }
    }

    // MARK: The time

    func testATimedHoldEndsAtItsTime() {
        let hold = timed(length: 1800)
        XCTAssertTrue(hold.isTimely(now: at(0)))
        XCTAssertTrue(hold.isTimely(now: at(1799)))
        XCTAssertFalse(hold.isTimely(now: at(1800)), "Over at the second it names")
        XCTAssertFalse(hold.isTimely(now: at(86_400)))
    }

    func testNoHoldLastsLongerThanItsCap() {
        XCTAssertTrue(timed(length: ManualHold.timedCap).isTimely(now: at(0)))
        XCTAssertFalse(timed(length: ManualHold.timedCap + 1).isTimely(now: at(0)))
        var hold = command()
        XCTAssertEqual(hold.end - hold.start, ManualHold.commandCap)
        XCTAssertTrue(hold.isTimely(now: at(0)))
        hold.end += 1
        XCTAssertFalse(hold.isTimely(now: at(0)))
    }

    /// The end would be further away than the hold was asked for.
    func testAHoldFromBeforeTheClockWasSetBackIsOver() {
        let hold = timed(length: 1800, from: 3600)
        XCTAssertFalse(hold.isTimely(now: at(0)))
        XCTAssertTrue(hold.isTimely(now: at(3600 - 30)), "A clock that differs by seconds is no clock that was set")
    }

    func testAnotherVersionAndABadIDAreNeverTimely() {
        var hold = timed()
        hold.v = 2
        XCTAssertFalse(hold.isTimely(now: at(0)))
        hold = timed()
        hold.id = "../../x"
        XCTAssertFalse(hold.isTimely(now: at(0)))
        hold = timed()
        hold.end = .infinity
        XCTAssertFalse(hold.isTimely(now: at(0)))
    }

    // MARK: The holder

    func testACommandHoldLivesWithItsHolder() {
        let hold = command(pid: 500, pidStart: 1000)
        XCTAssertTrue(hold.holderIsAlive { $0 == 500 ? 1000 : nil })
        XCTAssertTrue(hold.holderIsAlive { _ in 1000.0005 }, "Two readings of one start time")
        XCTAssertFalse(hold.holderIsAlive { _ in nil }, "The holder is gone")
        XCTAssertFalse(hold.holderIsAlive { _ in 2000 }, "The pid belongs to another process now")
    }

    func testAHoldWhoseHolderIsStoppedIsNotLiveAndKeepsItsFile() throws {
        store.write(command(pid: 500, pidStart: 1000))
        store.write(timed())
        try setModified("bbbb0001", to: at(0))
        let live = store.live(now: at(1799), startTime: { _ in 1000 }, stopped: { $0 == 500 })
        XCTAssertEqual(live.map(\.id), ["aaaa0001"], "A timed hold has no holder that can be stopped")
        XCTAssertEqual(files(), ["aaaa0001.json", "bbbb0001.json"])
        XCTAssertEqual(store.live(now: at(1799), startTime: { _ in 1000 }).map(\.id), ["aaaa0001", "bbbb0001"], "Continued")
        XCTAssertFalse(timed().holderIsStopped { _ in true })
        XCTAssertTrue(ProcessCensus.isStopped(status: Int8(SSTOP)))
        XCTAssertFalse(ProcessCensus.isStopped(status: Int8(SRUN)))
        XCTAssertFalse(ProcessCensus.isStopped(status: Int8(SZOMB)))
    }

    func testACommandHoldWithNoHolderIsDead() {
        var hold = command()
        hold.pid = nil
        XCTAssertFalse(hold.holderIsAlive { _ in 1000 })
        hold = command(pid: 1)
        XCTAssertFalse(hold.holderIsAlive { _ in hold.pidStart }, "launchd holds nothing")
        XCTAssertTrue(timed().holderIsAlive { _ in nil }, "A timed hold has no holder")
    }

    // MARK: The folder

    func testTheFolderIsInTheAppsOwnFolder() {
        XCTAssertTrue(HoldStore.directory(environment: [:]).path.hasSuffix("/Library/Application Support/com.caffeinagent.app/holds"))
        XCTAssertEqual(HoldStore.directory(environment: [HoldStore.homeOverrideKey: "/tmp/x"]).path, "/tmp/x/holds")
        XCTAssertEqual(HoldStore.bundleID, HookEvents.bundleID)
    }

    func testAHoldComesBackAsItWasWritten() throws {
        let holds = [timed(reason: "Nightly backup"), command()]
        for hold in holds { XCTAssertTrue(store.write(hold)) }
        XCTAssertEqual(store.live(now: at(10), startTime: { _ in 1_791_199_000 }), holds)
        XCTAssertEqual(files(), ["aaaa0001.json", "bbbb0001.json"])
    }

    func testTheFolderAndTheFilesAreForTheUserAlone() throws {
        XCTAssertTrue(store.write(timed()))
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        let file = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("aaaa0001.json").path)[.posixPermissions] as? Int
        XCTAssertEqual(folder, 0o700)
        XCTAssertEqual(file, 0o600)
    }

    func testAHoldWhoseTimeIsOverIsRemoved() {
        store.write(timed(length: 60))
        XCTAssertEqual(store.live(now: at(59), startTime: { _ in nil }).count, 1)
        XCTAssertEqual(store.live(now: at(60), startTime: { _ in nil }), [])
        XCTAssertEqual(files(), [])
    }

    /// The collector takes its time before it reads the folder.
    func testAHoldOfTheFullCapThatIsWrittenWhileASampleRunsStays() {
        let holds = [timed(length: ManualHold.timedCap), command()]
        for hold in holds { store.write(hold) }
        XCTAssertEqual(store.live(now: at(-0.02), startTime: { _ in 1_791_199_000 }), holds)
        XCTAssertEqual(files(), ["aaaa0001.json", "bbbb0001.json"])
    }

    func testAHoldThatIsNotOverAndDoesNotCountIsRemovedOnlyOnceItIsOld() throws {
        store.write(timed(length: 1800, from: 3600))
        XCTAssertEqual(store.live(now: at(0), startTime: { _ in nil }), [], "It starts an hour ahead of the clock")
        try setModified("aaaa0001", to: at(0))
        XCTAssertEqual(files(), ["aaaa0001.json"], "A young file stays")
        XCTAssertEqual(store.live(now: at(HoldStore.removalAge), startTime: { _ in nil }), [])
        XCTAssertEqual(files(), [])
    }

    func testAHoldWhoseHolderIsGoneNeverCountsAndIsRemoved() throws {
        store.write(command())
        XCTAssertEqual(store.live(now: at(5), startTime: { _ in nil }), [], "Dead at once")
        try setModified("bbbb0001", to: at(0))
        XCTAssertEqual(files(), ["bbbb0001.json"], "The file of a young hold stays: its holder may be newer than the process table")
        XCTAssertEqual(store.live(now: at(HoldStore.removalAge), startTime: { _ in nil }), [])
        XCTAssertEqual(files(), [])
    }

    func testAPidThatIsUsedAgainKeepsNoHoldAlive() throws {
        store.write(command(pid: 500, pidStart: 1000))
        try setModified("bbbb0001", to: at(0))
        XCTAssertEqual(store.live(now: at(60), startTime: { $0 == 500 ? 5000 : nil }), [])
        XCTAssertEqual(files(), [])
    }

    func testReadingAloneRemovesNothing() {
        store.write(timed(length: 60))
        XCTAssertEqual(store.live(now: at(120), startTime: { _ in nil }, removeDead: false), [])
        XCTAssertEqual(files(), ["aaaa0001.json"])
    }

    func testAFileThatIsNoHoldIsNotRead() throws {
        store.prepare()
        try Data("{".utf8).write(to: directory.appendingPathComponent("cccc0001.json"))
        // The id inside is not the name of the file.
        try JSONEncoder().encode(timed("dddd0001")).write(to: directory.appendingPathComponent("eeee0001.json"))
        try Data(String(repeating: " ", count: HoldStore.maxFileBytes + 1).utf8).write(to: directory.appendingPathComponent("ffff0001.json"))
        try Data("x".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        XCTAssertEqual(store.live(now: at(0), startTime: { _ in nil }), [])
    }

    func testATextInAFileIsCleanedAgain() throws {
        var hold = timed()
        hold.reason = "two\nlines " + String(repeating: "x", count: 200)
        store.prepare()
        try JSONEncoder().encode(hold).write(to: directory.appendingPathComponent("aaaa0001.json"))
        let read = try XCTUnwrap(store.live(now: at(0), startTime: { _ in nil }).first)
        XCTAssertEqual(read.reason?.count, ManualHold.reasonLimit)
        XCTAssertEqual(read.reason?.hasPrefix("two lines"), true)
    }

    func testTheOldestHoldsCountWhenThereAreTooMany() {
        for index in 0..<(HoldStore.maxHolds + 3) {
            store.write(timed(String(format: "aaaa%04d", index), from: TimeInterval(index)))
        }
        let live = store.live(now: at(100), startTime: { _ in nil })
        XCTAssertEqual(live.count, HoldStore.maxHolds)
        XCTAssertEqual(live.first?.id, "aaaa0000")
    }

    func testRemove() {
        store.write(timed())
        XCTAssertTrue(store.remove(id: "aaaa0001"))
        XCTAssertFalse(store.remove(id: "aaaa0001"))
        XCTAssertFalse(store.remove(id: "../holds/aaaa0001"))
        XCTAssertFalse(store.write(ManualHold(id: "../x", kind: .timed, start: 0, end: 1)))
    }

    // MARK: The app

    func testTheLockSaysThatTheAppRuns() {
        XCTAssertFalse(store.appIsRunning)
        var lock = HoldStore.AppLock(store: store)
        XCTAssertNotNil(lock)
        XCTAssertTrue(store.appIsRunning)
        XCTAssertNil(HoldStore.AppLock(store: store), "One copy of the app holds it")
        lock = nil
        XCTAssertFalse(store.appIsRunning)
    }

    func testTheStatusCountsOnlyWhileTheAppRuns() {
        let status = HoldStore.Status(awake: true, line: "Your Mac stays awake: ffmpeg asked for it", stopped: false)
        XCTAssertTrue(store.write(status))
        XCTAssertNil(store.status(), "What a dead app wrote last says nothing")
        let lock = HoldStore.AppLock(store: store)
        XCTAssertEqual(store.status(), status)
        store.removeStatus()
        XCTAssertNil(store.status())
        _ = lock
        XCTAssertEqual(store.live(now: at(0), startTime: { _ in nil }), [], "The lock and the status are no holds")
    }

    /// The app watches the holds folder, and what it writes there itself
    /// would bring one more sample.
    func testTheLockAndTheStatusAreNotInTheFolderTheAppWatches() throws {
        let lock = HoldStore.AppLock(store: store)
        XCTAssertTrue(store.write(HoldStore.Status(awake: false, line: "Your Mac can sleep: No agent is open", stopped: false)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path).sorted(), [".app", ".status", "holds"]
        )
        XCTAssertNotNil(store.status())
        _ = lock
    }

    func testAStatusThatSaysNothingNewIsNotWrittenAgain() throws {
        let writer = HoldStore.StatusWriter(store: store)
        let lock = HoldStore.AppLock(store: store)
        let asleep = HoldStore.Status(awake: false, line: "Your Mac can sleep: No agent is open", stopped: false)
        let awake = HoldStore.Status(awake: true, line: "Your Mac stays awake: ffmpeg asked for it", stopped: false)
        let path = directory.deletingLastPathComponent().appendingPathComponent(HoldStore.statusName).path
        func file() throws -> UInt64? { (try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? NSNumber)?.uint64Value }
        XCTAssertTrue(writer.write(asleep))
        let first = try file()
        XCTAssertFalse(writer.write(asleep))
        XCTAssertEqual(try file(), first, "The file is the one that was there")
        XCTAssertTrue(writer.write(awake))
        XCTAssertNotEqual(try file(), first, "A new file took its place")
        XCTAssertEqual(store.status(), awake)
        writer.remove()
        XCTAssertNil(store.status())
        XCTAssertTrue(writer.write(awake), "Written again after it was removed")
        XCTAssertEqual(store.status(), awake)
        _ = lock
    }

    // MARK: Policy

    private func working(_ name: String = "Claude Code") -> AgentReading {
        AgentReading(
            agentID: "claude", displayName: name, level: .state, identity: ProcessIdentity(pid: 1, startTime: 1),
            verdict: AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy)
        )
    }

    private func decide(
        _ holds: [ManualHold], readings: [AgentReading] = [], at seconds: TimeInterval = 0, enabled: Bool = true, pausedUntil: Date? = nil,
        safety: SafetyStop? = nil, settings: DetectionSettings = DetectionSettings(), mayHold: Bool = true
    ) -> HoldDecision {
        HoldPolicy.decide(
            readings: readings, memory: PolicyMemory(), mode: .agentWorking, enabled: enabled, pausedUntil: pausedUntil, holds: holds,
            safety: safety, settings: settings, context: FrameContext(), mayHold: mayHold, now: at(seconds)
        ).0
    }

    func testAHoldAloneKeepsTheMacAwake() {
        let decision = decide([command()])
        XCTAssertTrue(decision.hold)
        XCTAssertTrue(decision.lidClosedFlag, "Also with the lid closed, as for an agent")
        XCTAssertEqual(decision.headline, .manualHold(.one("ffmpeg")))
        XCTAssertEqual(decision.headline.awakeReason, "ffmpeg asked for it")
        XCTAssertEqual(decision.manualHolds.map(\.id), ["bbbb0001"])
    }

    func testTheLidClosedSettingCountsForAHoldToo() {
        var settings = DetectionSettings()
        settings.stayAwakeLidClosedOnBattery = false
        let decision = decide([timed()], settings: settings)
        XCTAssertTrue(decision.hold)
        XCTAssertFalse(decision.lidClosedFlag)
    }

    func testSeveralHoldsAreCounted() {
        let decision = decide([timed(reason: "Nightly backup"), command()])
        XCTAssertEqual(decision.headline, .manualHold(.many(2)))
        XCTAssertEqual(decision.headline.text, "Awake: 2 commands asked for it")
    }

    func testNoHoldAndNoAgentLetsTheMacSleep() {
        let decision = decide([])
        XCTAssertFalse(decision.hold)
        XCTAssertEqual(decision.headline, .noAgents)
    }

    func testAHoldEndsInThePolicyAtItsTime() {
        let hold = timed(length: 600)
        XCTAssertTrue(decide([hold], at: 599).hold)
        let over = decide([hold], at: 600)
        XCTAssertFalse(over.hold)
        XCTAssertFalse(over.lidClosedFlag)
        XCTAssertEqual(over.headline, .noAgents)
        XCTAssertEqual(over.manualHolds, [])
    }

    func testEveryStopBeatsAHold() {
        let holds = [timed(), command()]
        let stops: [(HoldDecision, HoldHeadline)] = [
            (decide(holds, safety: .batteryLow(percent: 18)), .safetyStop(.batteryLow(percent: 18))),
            (decide(holds, safety: .tooHot), .safetyStop(.tooHot)),
            (decide(holds, pausedUntil: at(3600)), .paused(until: at(3600))),
            (decide(holds, enabled: false), .switchedOff),
        ]
        for (decision, headline) in stops {
            XCTAssertFalse(decision.hold, "\(headline)")
            XCTAssertFalse(decision.lidClosedFlag, "\(headline)")
            XCTAssertEqual(decision.headline, headline)
            XCTAssertTrue(decision.headline.isStop)
            XCTAssertEqual(decision.manualHolds.count, 2, "Still listed, so the menu can show and stop them")
        }
        XCTAssertFalse(HoldHeadline.manualHold(.many(2)).isStop)
    }

    /// See `WakeGate`.
    func testAHoldStartsNothingWhileTheMacGoesToSleep() {
        let decision = decide([timed()], mayHold: false)
        XCTAssertFalse(decision.hold)
        XCTAssertFalse(decision.lidClosedFlag)
        XCTAssertEqual(decision.headline, .noAgents)
    }

    func testAnAgentAtWorkIsNamedBeforeAHold() {
        let decision = decide([timed()], readings: [working()])
        XCTAssertTrue(decision.hold)
        XCTAssertEqual(decision.headline, .working(.one("Claude Code")))
        XCTAssertEqual(decision.manualHolds.count, 1)
    }

    func testAHoldIsNamedBeforeStayReachable() {
        let (decision, _) = HoldPolicy.decide(
            readings: [], memory: PolicyMemory(), mode: .agentWorking, enabled: true, reachableUntil: at(3600), holds: [timed()],
            safety: nil, settings: DetectionSettings(), context: FrameContext(), now: at(0)
        )
        XCTAssertEqual(decision.headline, .manualHold(.one("A command")))
    }

    // MARK: The frame

    func testTheFrameCarriesTheHoldsAndAnOldLineHasNone() throws {
        let frame = EvidenceFrame(at: at(0), agents: [], holds: [timed(reason: "Nightly backup"), command()])
        let data = try LabFormat.encoder().encode(frame)
        XCTAssertEqual(try LabFormat.decoder().decode(EvidenceFrame.self, from: data), frame)
        let empty = String(decoding: try LabFormat.encoder().encode(EvidenceFrame(at: at(0), agents: [])), as: UTF8.self)
        XCTAssertFalse(empty.contains("holds"), "A line with no hold is as it was")
        XCTAssertEqual(try LabFormat.decoder().decode(EvidenceFrame.self, from: Data(empty.utf8)).holds, [])
    }

    func testARecordingKeepsNoReason() {
        let frame = EvidenceFrame(at: at(0), agents: [], holds: [timed(reason: "the secret film"), command()])
        let line = LabFormat.sample(frame: frame, decision: decide([frame.holds[0]]), cost: nil)
        XCTAssertEqual(line.frame?.holds.map(\.reason), [nil, nil])
        XCTAssertEqual(line.frame?.holds.map(\.command), [nil, "ffmpeg"])
        XCTAssertEqual(line.hold?.headline, "Awake: a hold from the command line")
        XCTAssertEqual(line.hold?.on, true)
    }

    func testAReplayHoldsForARecordedHold() {
        var recording = LabRecording()
        recording.samples = [0, 2, 4].map { LabSample(frame: EvidenceFrame(at: at($0), agents: [], holds: $0 < 4 ? [command()] : [])) }
        XCTAssertEqual(LabReplay.steps(of: recording).map(\.decision.hold), [true, true, false])
    }

    // MARK: The menu

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func input(_ decision: HoldDecision) -> PanelInput {
        var input = PanelInput(decision: decision)
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        return input
    }

    func testTheWordsOfAHold() {
        let locale = Locale(identifier: "en_GB")
        // 1_791_200_000 is 08:53:20 UTC, so half an hour later is 12:03.
        XCTAssertEqual(PanelText.hold(timed(), holding: true, now: at(0), calendar: calendar, locale: locale), "Keeps your Mac awake until 12:03")
        XCTAssertEqual(PanelText.hold(command(), holding: true, now: at(30), calendar: calendar, locale: locale), "Keeps your Mac awake while it runs")
        XCTAssertEqual(
            PanelText.hold(command(), holding: true, now: at(12 * 60), calendar: calendar, locale: locale),
            "Keeps your Mac awake while it runs, for 12 minutes"
        )
        XCTAssertEqual(PanelText.hold(timed(), holding: false, now: at(0), calendar: calendar, locale: locale), "Asked to keep your Mac awake until 12:03")
        XCTAssertEqual(
            PanelText.hold(command(), holding: false, now: at(12 * 60), calendar: calendar, locale: locale), "Asked to keep your Mac awake while it runs"
        )
    }

    func testTheHeadlineOfAHold() {
        let one = PanelText.headline(.manualHold(.one("ffmpeg")))
        XCTAssertEqual(one.title, PanelText.awakeTitle)
        XCTAssertEqual(one.subtitle, "ffmpeg asked for it")
        XCTAssertEqual(PanelText.headline(.manualHold(.many(3))).subtitle, "3 commands asked for it")
        XCTAssertEqual(MenuModel.pose(for: .manualHold(.one("ffmpeg"))), .awake(wisps: 2))
        XCTAssertEqual(MenuBarLook(pose: MenuModel.pose(for: .manualHold(.one("ffmpeg")))), MenuBarLook(pose: .awake(wisps: 2)))
    }

    func testEachHoldHasALineWithAWayToStopIt() {
        let state = MenuModel.state(input(decide([timed(reason: "Nightly backup"), command()])), now: at(12 * 60))
        XCTAssertNil(state.emptyText, "A hold is something to show")
        XCTAssertEqual(state.title, PanelText.awakeTitle)
        XCTAssertEqual(state.subtitle, "2 commands asked for it")
        XCTAssertEqual(state.groups.map(\.header.title), ["Nightly backup", "ffmpeg"])
        XCTAssertEqual(state.groups.map(\.header.detail), ["Keeps your Mac awake until 12:03", "Keeps your Mac awake while it runs, for 12 minutes"])
        XCTAssertEqual(state.groups.map(\.stop), [.stopHold(id: "aaaa0001"), .stopHold(id: "bbbb0001")])
        XCTAssertEqual(state.groups.map(\.header.state), [.working, .working])
        XCTAssertEqual(state.groups.map(\.canToggle), [false, false])
        XCTAssertEqual(PanelAction.stopHold(id: "aaaa0001").title, "Stop")
        XCTAssertNil(AgentLogo.mark(forAgentID: state.groups[0].header.agentID), "No mark, so the terminal glyph")
    }

    func testAHoldStandsBelowTheAgentsAtWorkAndAboveTheIdleOnes() {
        let idle = AgentReading(
            agentID: "codex", displayName: "Codex", level: .state, identity: ProcessIdentity(pid: 2, startTime: 1),
            verdict: AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt)
        )
        let state = MenuModel.state(input(decide([command()], readings: [idle, working()])), now: at(60))
        XCTAssertEqual(state.groups.map(\.header.name), ["Claude Code", "ffmpeg", "Codex"])
        XCTAssertEqual(state.subtitle, "Claude Code is working")
    }

    func testInAStopAHoldIsOnlyAskedFor() {
        let state = MenuModel.state(input(decide([timed()], pausedUntil: at(3600))), now: at(60))
        XCTAssertEqual(state.title, PanelText.pausedTitle)
        XCTAssertEqual(state.groups.map(\.header.detail), ["Asked to keep your Mac awake until 12:03"])
        XCTAssertEqual(state.groups.map(\.header.state), [.idle])
        XCTAssertEqual(state.groups.map(\.stop), [.stopHold(id: "aaaa0001")])
    }

    // MARK: Settings

    func testWhatSettingsShowsOfTheCommandLineTool() {
        let setup = CommandLineSetup(appPath: HookCatalog.stableAppPath)
        XCTAssertEqual(setup.toolPath, "/Applications/Agent Caffeine.app/Contents/MacOS/agent-caffeine")
        XCTAssertEqual(
            setup.installCommand,
            "mkdir -p ~/.local/bin && ln -sf '/Applications/Agent Caffeine.app/Contents/MacOS/agent-caffeine' ~/.local/bin/agent-caffeine"
        )
        XCTAssertEqual(setup.mcpConfig, #"{"command": "/Applications/Agent Caffeine.app/Contents/MacOS/agent-caffeine", "args": ["mcp"]}"#)
        // An install that was updated from 1.0.1 shows the name it has on disk.
        XCTAssertEqual(CommandLineSetup(appPath: AppInstall.knownPaths[1]).toolPath, "/Applications/agent caffeine.app/Contents/MacOS/agent-caffeine")
        let odd = CommandLineSetup(appPath: #"/Users/o'neil/"x".app"#)
        XCTAssertTrue(odd.installCommand.contains(#"'/Users/o'\''neil/"x".app/Contents/MacOS/agent-caffeine'"#))
        let config = try? JSONSerialization.jsonObject(with: Data(odd.mcpConfig.utf8)) as? [String: Any]
        XCTAssertEqual(config?["command"] as? String, odd.toolPath)
    }

    func testTheTextsOfTheSectionFollowTheHouseStyle() {
        for text in [PanelText.commandLineInSettings, PanelText.commandLineExplained, PanelText.commandLineInstallExplained, PanelText.commandLineMCPExplained, PanelText.holdHint] {
            XCTAssertFalse(text.contains("agent caffeine"), text)
            XCTAssertFalse(text.contains("\u{2014}"), text)
        }
    }
}
