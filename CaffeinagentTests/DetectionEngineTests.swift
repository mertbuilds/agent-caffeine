import XCTest

private final class FakeCollector: EvidenceCollecting {
    var next: () -> EvidenceSample = { EvidenceSample(frame: EvidenceFrame(at: Date(timeIntervalSince1970: 0), agents: [])) }
    private(set) var userNames: [[String]] = []
    var samples: Int { userNames.count }

    func collect(userNames: [String]) -> EvidenceSample {
        self.userNames.append(userNames)
        return next()
    }
}

/// Time that moves only when the test says so. Work for the sampling queue
/// and for the main actor both run on the test's thread, in order.
private final class FakeScheduler: DetectionScheduling {
    private final class Item: DetectionCancellable {
        let due: TimeInterval
        let work: () -> Void
        var cancelled = false

        init(due: TimeInterval, work: @escaping () -> Void) {
            self.due = due
            self.work = work
        }

        func cancel() { cancelled = true }
    }

    private(set) var time: TimeInterval = 0
    private(set) var delays: [TimeInterval] = []
    private(set) var leeways: [TimeInterval] = []
    /// Keeps main-actor work back, as when the main thread is busy.
    var holdsMain = false
    private var items: [Item] = []
    private var main: [@MainActor () -> Void] = []

    func schedule(after delay: TimeInterval, leeway: TimeInterval, _ work: @escaping () -> Void) -> DetectionCancellable {
        delays.append(delay)
        leeways.append(leeway)
        let item = Item(due: time + delay, work: work)
        items.append(item)
        return item
    }

    func onMain(_ work: @escaping @MainActor () -> Void) {
        main.append(work)
    }

    @MainActor
    func drainMain() {
        while !main.isEmpty { main.removeFirst()() }
    }

    @MainActor
    func advance(by seconds: TimeInterval) {
        let end = time + seconds
        while true {
            if !holdsMain { drainMain() }
            guard let item = items.filter({ !$0.cancelled && $0.due <= end }).min(by: { $0.due < $1.due }) else { break }
            items.removeAll { $0 === item }
            time = item.due
            item.work()
        }
        time = end
    }
}

private final class FakeWatcher: DetectionWatching {
    private(set) var files: Set<String> = []
    private(set) var processes: Set<ProcessIdentity> = []
    private(set) var onEvent: (() -> Void)?
    private(set) var stops = 0

    func watch(files: Set<String>, processes: Set<ProcessIdentity>, onEvent: @escaping () -> Void) {
        self.files = files
        self.processes = processes
        self.onEvent = onEvent
    }

    func stop() {
        stops += 1
        onEvent = nil
    }
}

@MainActor
final class DetectionEngineTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)
    private static let processStart: TimeInterval = 1_791_196_400

    private var collector: FakeCollector!
    private var scheduler: FakeScheduler!
    private var watcher: FakeWatcher!
    private var engine: DetectionEngine!
    /// What the fake collector reports next.
    private var state: ReportedState? = .idle

    override func setUp() async throws {
        collector = FakeCollector()
        scheduler = FakeScheduler()
        watcher = FakeWatcher()
        state = .idle
        slept = 0
        collector.next = { [unowned self] in self.sample() }
        engine = DetectionEngine(collector: collector, scheduler: scheduler, watcher: watcher)
    }

    /// Seconds the Mac slept: time that passed and that no timer saw.
    private var slept: TimeInterval = 0
    private var now: Date { Self.start.addingTimeInterval(scheduler.time + slept) }
    private let identity = ProcessIdentity(pid: 100, startTime: DetectionEngineTests.processStart)

    /// One Claude Code session in `state`, or no agent at all for nil.
    private func sample() -> EvidenceSample {
        guard let state else { return EvidenceSample(frame: EvidenceFrame(at: now, agents: []), cost: 0.001) }
        let report = StateReport(state: state, since: nil, observedAt: now, source: .claudeSessionFile, detail: nil)
        let agent = AgentEvidence(agentID: "claude", displayName: "Claude Code", level: .state, pid: identity.pid, startTime: identity.startTime, reported: report)
        return EvidenceSample(frame: EvidenceFrame(at: now, agents: [agent]), watchedFiles: ["/sessions/100.json"], roots: [identity], cost: 0.001)
    }

    func testNothingRunsBeforeStart() {
        scheduler.advance(by: 60)
        XCTAssertEqual(collector.samples, 0)
        XCTAssertNil(engine.frame)
        XCTAssertEqual(engine.decision.headline, .noAgents)
        XCTAssertFalse(engine.isRunning)
    }

    func testSamplesEveryTwoSecondsWhileAnAgentExists() {
        engine.start()
        scheduler.advance(by: 0)
        XCTAssertEqual(collector.samples, 1, "The first sample comes at once")
        XCTAssertEqual(engine.frame?.at, Self.start)
        scheduler.advance(by: 1.9)
        XCTAssertEqual(collector.samples, 1)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(collector.samples, 2)
        scheduler.advance(by: 10)
        XCTAssertEqual(collector.samples, 7)
        XCTAssertEqual(Set(scheduler.delays.dropFirst()), [DetectionEngine.activeInterval])
        XCTAssertEqual(scheduler.leeways.last, DetectionEngine.activeInterval * DetectionEngine.leewayShare)
    }

    func testSamplesEveryFiveSecondsWhileNoAgentExists() {
        state = nil
        engine.start()
        scheduler.advance(by: 10)
        XCTAssertEqual(collector.samples, 3, "At 0, 5 and 10 seconds")
        XCTAssertEqual(engine.decision.headline, .noAgents)

        state = .working
        scheduler.advance(by: 5)
        XCTAssertEqual(collector.samples, 4)
        scheduler.advance(by: 2)
        XCTAssertEqual(collector.samples, 5, "An agent is there, so the next sample came after 2 seconds")
    }

    func testFrameBecomesReadingsAndADecision() {
        var published: [Bool] = []
        let subscription = engine.$decision.sink { published.append($0.hold) }
        defer { subscription.cancel() }
        engine.start()
        scheduler.advance(by: 4)
        XCTAssertFalse(engine.decision.hold)
        XCTAssertEqual(engine.decision.headline.text, "Mac can sleep: Claude Code is idle")
        XCTAssertEqual(engine.readings.map(\.verdict.state), [.idle])

        state = .working
        scheduler.advance(by: 2)
        XCTAssertTrue(engine.decision.hold)
        XCTAssertTrue(engine.decision.lidClosedFlag)
        XCTAssertEqual(engine.decision.headline, .working(.one("Claude Code")))
        XCTAssertEqual(engine.readings.map(\.verdict.reason), [.reportsBusy])

        // The policy memory lasts from sample to sample: the release time runs.
        state = .idle
        scheduler.advance(by: 2)
        XCTAssertEqual(engine.decision.headline, .finishedRecently(.one("Claude Code")))
        scheduler.advance(by: DetectionSettings().releaseAfterState)
        XCTAssertEqual(engine.decision.headline, .idle(.one("Claude Code")))
        XCTAssertFalse(engine.decision.hold)

        state = nil
        scheduler.advance(by: 2)
        XCTAssertEqual(engine.decision.headline, .noAgents)
        XCTAssertEqual(published, [false, false, true, true, false, false], "Published only when it changes")
    }

    func testReleaseTimeDoesNotRunWhileTheMacSleeps() {
        state = .working
        engine.start()
        scheduler.advance(by: 4)
        state = .idle
        scheduler.advance(by: 2)
        XCTAssertEqual(engine.decision.headline, .finishedRecently(.one("Claude Code")))

        slept = 360
        scheduler.advance(by: 2)
        XCTAssertEqual(engine.frame?.at, Self.start.addingTimeInterval(368))
        XCTAssertEqual(engine.decision.headline, .finishedRecently(.one("Claude Code")), "The sleep is no part of the release time")
        scheduler.advance(by: DetectionSettings().releaseAfterState - 6)
        XCTAssertTrue(engine.decision.hold)
        scheduler.advance(by: 4)
        XCTAssertEqual(engine.decision.headline, .idle(.one("Claude Code")))
    }

    func testEventBringsTheNextSampleForward() {
        engine.start()
        scheduler.advance(by: 1)
        XCTAssertEqual(watcher.files, ["/sessions/100.json"])
        XCTAssertEqual(watcher.processes, [identity])

        state = .working
        watcher.onEvent?()
        watcher.onEvent?()
        scheduler.advance(by: 0.1)
        watcher.onEvent?()
        XCTAssertEqual(collector.samples, 1)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(collector.samples, 2, "Three events within the delay give one sample")
        XCTAssertTrue(engine.decision.hold)
        XCTAssertEqual(scheduler.delays, [0, 2, DetectionEngine.resampleDelay, 2])

        scheduler.advance(by: 1.9)
        XCTAssertEqual(collector.samples, 2, "The timer starts again from the early sample")
        scheduler.advance(by: 0.1)
        XCTAssertEqual(collector.samples, 3)
    }

    /// The process exits: the watcher fires, and the hold ends with the
    /// sample that no longer has the instance.
    func testExitOfTheAgentReleasesWithinTheDelay() {
        state = .working
        engine.start()
        scheduler.advance(by: 0.5)
        XCTAssertTrue(engine.decision.hold)
        state = nil
        watcher.onEvent?()
        scheduler.advance(by: DetectionEngine.resampleDelay)
        XCTAssertFalse(engine.decision.hold)
        XCTAssertEqual(engine.decision.headline, .noAgents)
        XCTAssertEqual(watcher.files, [])
        XCTAssertEqual(watcher.processes, [])
    }

    func testEventDuringASampleIsNotLost() {
        engine.start()
        scheduler.advance(by: 1)
        // The timer fired and the sample is collected, and the main thread
        // has not taken it yet when the event comes.
        scheduler.holdsMain = true
        scheduler.advance(by: 1)
        XCTAssertEqual(collector.samples, 2)
        state = .working
        engine.requestSample()
        scheduler.holdsMain = false
        scheduler.advance(by: 0)
        XCTAssertFalse(engine.decision.hold, "The sample from before the event")
        scheduler.advance(by: DetectionEngine.resampleDelay)
        XCTAssertEqual(collector.samples, 3)
        XCTAssertTrue(engine.decision.hold)
        scheduler.advance(by: 2)
        XCTAssertEqual(collector.samples, 4, "One timer runs, not two")
    }

    func testStayReachableChangesTheDecisionAtOnce() {
        state = .idle
        engine.start()
        scheduler.advance(by: 0)
        XCTAssertFalse(engine.decision.hold)
        let until = Date.distantFuture
        engine.reachableUntil = until
        XCTAssertEqual(engine.decision.headline, .reachable(until: until))
        XCTAssertTrue(engine.decision.hold)
        XCTAssertTrue(engine.decision.lidClosedFlag)
        engine.pausedUntil = until
        XCTAssertEqual(engine.decision.headline, .paused(until: until))
        engine.pausedUntil = nil
        engine.reachableUntil = nil
        XCTAssertFalse(engine.decision.hold)
        XCTAssertEqual(collector.samples, 1, "No input took a sample")
    }

    func testInputsChangeTheDecisionAtOnce() {
        state = .working
        engine.start()
        scheduler.advance(by: 0)
        XCTAssertTrue(engine.decision.hold)

        engine.enabled = false
        XCTAssertEqual(engine.decision.headline, .switchedOff)
        XCTAssertEqual(engine.decision.perAgent.map(\.cause), [nil])
        engine.enabled = true
        XCTAssertEqual(engine.decision.headline, .working(.one("Claude Code")))

        let until = Date.distantFuture
        engine.pausedUntil = until
        XCTAssertEqual(engine.decision.headline, .paused(until: until))
        XCTAssertFalse(engine.decision.lidClosedFlag)
        engine.pausedUntil = nil
        XCTAssertEqual(engine.decision.headline, .working(.one("Claude Code")))

        engine.safety = .tooHot
        XCTAssertEqual(engine.decision.headline, .safetyStop(.tooHot))
        engine.safety = nil
        engine.entitlement = .expired(.trialOver)
        XCTAssertFalse(engine.decision.hold)
        engine.entitlement = .licensed

        var settings = DetectionSettings()
        settings.agentRules = ["claude": .ignore]
        settings.userAgentNames = ["myagent"]
        engine.settings = settings
        XCTAssertFalse(engine.decision.hold)
        engine.mode = .always
        XCTAssertEqual(engine.decision.headline, .alwaysOn)
        XCTAssertEqual(collector.samples, 1, "No input took a sample")

        scheduler.advance(by: 2)
        XCTAssertEqual(collector.userNames.last, ["myagent"], "The user's names reach the collector with the next sample")
    }

    func testStopEndsTheLoopAndDropsASampleUnderWay() {
        engine.start()
        scheduler.advance(by: 1)
        scheduler.holdsMain = true
        scheduler.advance(by: 1)
        XCTAssertEqual(collector.samples, 2)
        let frame = engine.frame
        engine.stop()
        scheduler.holdsMain = false
        scheduler.advance(by: 60)
        XCTAssertEqual(collector.samples, 2)
        XCTAssertEqual(engine.frame, frame)
        XCTAssertEqual(watcher.stops, 1)
        XCTAssertFalse(engine.isRunning)

        engine.start()
        scheduler.advance(by: 0)
        XCTAssertEqual(collector.samples, 3)
    }

    func testEverySampleReachesTheRecorderAndTheCallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("engine-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LabRecorder(directory: directory)
        let header = LabHeader(label: "engine", startedAt: Self.start, app: "test", os: "test", model: "test", mode: engine.mode.rawValue, settings: engine.settings)
        let url = try recorder.start(label: "engine", header: header)
        var seen: [DetectionSample] = []
        engine.recorder = recorder
        engine.onSample = { seen.append($0) }
        state = .working
        engine.start()
        scheduler.advance(by: 4)
        recorder.stop()

        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(seen.map(\.decision.hold), [true, true, true])
        XCTAssertGreaterThanOrEqual(seen[0].cost, 0.001, "The collector's cost plus the deciding")
        let recording = try LabFormat.recording(at: url)
        XCTAssertEqual(recording.samples.map(\.frame), seen.map(\.frame))
        XCTAssertEqual(recording.samples.map(\.hold?.on), [true, true, true])
        XCTAssertEqual(recording.samples.first?.verdicts, [LabVerdict(id: "claude", pid: 100, state: .working, why: "reportsBusy", hold: "working")])
    }
}
