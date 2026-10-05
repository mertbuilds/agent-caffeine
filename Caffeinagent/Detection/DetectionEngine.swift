import Combine
import Foundation

/// One turn of the engine: what was seen, the verdicts, and the decision.
struct DetectionSample: Equatable {
    var frame: EvidenceFrame
    var readings: [AgentReading]
    var decision: HoldDecision
    /// Seconds the sample cost: collecting plus deciding.
    var cost: TimeInterval
}

protocol DetectionCancellable {
    func cancel()
}

/// Time for the engine, so a test can run the loop without sleeping.
protocol DetectionScheduling: AnyObject {
    /// Runs `work` once, `delay` seconds from now, on the sampling queue.
    func schedule(after delay: TimeInterval, leeway: TimeInterval, _ work: @escaping () -> Void) -> DetectionCancellable
    /// Runs `work` on the main actor, in the order of the calls.
    func onMain(_ work: @escaping @MainActor () -> Void)
}

/// Tells the engine that something changed before the timer would.
protocol DetectionWatching: AnyObject {
    /// Replaces what is watched. `onEvent` can run on any thread, when one
    /// of the files is written, replaced or removed, or one of the
    /// processes exits.
    func watch(files: Set<String>, processes: Set<ProcessIdentity>, onEvent: @escaping () -> Void)
    func stop()
}

/// Samples the agents and decides whether the Mac stays awake. It owns the
/// collector and the memory of the pure rules, and nothing else: it takes no
/// power assertion and draws no UI.
///
/// The timer runs every 2 seconds while an agent instance exists and every
/// 5 seconds while none does. A write to a watched state file and the exit
/// of an agent bring the next sample forward, 200 ms after the event.
@MainActor
final class DetectionEngine: ObservableObject {
    static let activeInterval: TimeInterval = 2
    static let idleInterval: TimeInterval = 5
    static let resampleDelay: TimeInterval = 0.2
    /// Lets the kernel join the timer with other wakeups.
    static let leewayShare = 0.1

    @Published private(set) var decision: HoldDecision
    /// Nil until the first sample.
    @Published private(set) var frame: EvidenceFrame?
    private(set) var readings: [AgentReading] = []
    private(set) var isRunning = false

    var mode: AwakeMode { didSet { if mode != oldValue { decideAgain() } } }
    var enabled: Bool { didSet { if enabled != oldValue { decideAgain() } } }
    /// Nil means there is no license to check.
    var entitlement: Entitlement? { didSet { if entitlement != oldValue { decideAgain() } } }
    /// New agent names need a new look at the process table.
    var settings: DetectionSettings {
        didSet {
            guard settings != oldValue else { return }
            decideAgain()
            if settings.userAgentNames != oldValue.userAgentNames { requestSample() }
        }
    }
    var safety: SafetyStop? { didSet { if safety != oldValue { decideAgain() } } }

    /// Gets every sample while it records.
    var recorder: LabRecorder?
    /// Called on the main actor after each sample.
    var onSample: ((DetectionSample) -> Void)?

    private let collector: EvidenceCollecting
    private let scheduler: DetectionScheduling
    private let watcher: DetectionWatching
    private var agentMemory: [ProcessIdentity: AgentMemory] = [:]
    private var policyMemory = PolicyMemory()
    private var tick: DetectionCancellable?
    /// A sample that an event asked for is on its way.
    private var resamplePending = false
    /// Raised by `stop`, so a sample that was under way is dropped.
    private var generation = 0

    init(
        collector: EvidenceCollecting, scheduler: DetectionScheduling, watcher: DetectionWatching,
        mode: AwakeMode = .agentWorking, enabled: Bool = true, entitlement: Entitlement? = nil,
        settings: DetectionSettings = DetectionSettings(), safety: SafetyStop? = nil
    ) {
        self.collector = collector
        self.scheduler = scheduler
        self.watcher = watcher
        self.mode = mode
        self.enabled = enabled
        self.entitlement = entitlement
        self.settings = settings
        self.safety = safety
        decision = HoldPolicy.decide(
            readings: [], memory: PolicyMemory(), mode: mode, enabled: enabled, entitlement: entitlement,
            safety: safety, settings: settings, context: FrameContext(), now: Date()
        ).0
    }

    /// The engine that reads this Mac.
    static func system(
        mode: AwakeMode = .agentWorking, enabled: Bool = true, entitlement: Entitlement? = nil,
        settings: DetectionSettings = DetectionSettings(), safety: SafetyStop? = nil
    ) -> DetectionEngine {
        DetectionEngine(
            collector: EvidenceCollector(), scheduler: DispatchDetectionScheduler(), watcher: SystemDetectionWatcher(),
            mode: mode, enabled: enabled, entitlement: entitlement, settings: settings, safety: safety
        )
    }

    /// Takes the first sample at once.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        resamplePending = false
        scheduleTick(after: 0, resample: false)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        tick?.cancel()
        tick = nil
        resamplePending = false
        watcher.stop()
    }

    /// Asks for a sample soon. Many calls within the delay give one sample.
    func requestSample() {
        guard isRunning, !resamplePending else { return }
        resamplePending = true
        scheduleTick(after: Self.resampleDelay, resample: true)
    }

    private func scheduleTick(after delay: TimeInterval, resample: Bool) {
        tick?.cancel()
        let names = settings.userAgentNames
        let generation = generation
        tick = scheduler.schedule(after: delay, leeway: delay * Self.leewayShare) { [weak self, collector, scheduler] in
            let sample = collector.collect(userNames: names)
            scheduler.onMain { self?.apply(sample, generation: generation, resample: resample) }
        }
    }

    private func apply(_ sample: EvidenceSample, generation: Int, resample: Bool) {
        guard isRunning, generation == self.generation else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        if let gap = SampleGap.length(from: frame?.at, to: sample.frame.at) {
            agentMemory = agentMemory.mapValues { $0.shifted(by: gap) }
            policyMemory = policyMemory.shifted(by: gap)
        }
        let (readings, nextAgents) = VerdictRules.readings(for: sample.frame, memory: agentMemory, settings: settings)
        agentMemory = nextAgents
        self.readings = readings
        frame = sample.frame
        decide(at: sample.frame.at, context: sample.frame.context)
        let cost = sample.cost + TimeInterval(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000

        recorder?.record(frame: sample.frame, decision: decision, cost: cost)
        onSample?(DetectionSample(frame: sample.frame, readings: readings, decision: decision, cost: cost))

        watcher.watch(files: sample.watchedFiles, processes: sample.roots) { [weak self, scheduler] in
            scheduler.onMain { self?.requestSample() }
        }
        if resample { resamplePending = false }
        // A sample that an event asked for is still to come, and it sets
        // the timer again.
        if !resamplePending {
            scheduleTick(after: sample.frame.agents.isEmpty ? Self.idleInterval : Self.activeInterval, resample: false)
        }
    }

    /// The same readings under changed inputs. The verdicts are not made
    /// again: their memory counts samples.
    private func decideAgain() {
        guard let frame else {
            decide(at: Date(), context: FrameContext())
            return
        }
        decide(at: frame.at, context: frame.context)
    }

    private func decide(at now: Date, context: FrameContext) {
        let (next, memory) = HoldPolicy.decide(
            readings: readings, memory: policyMemory, mode: mode, enabled: enabled, entitlement: entitlement,
            safety: safety, settings: settings, context: context, now: now
        )
        policyMemory = memory
        if decision != next { decision = next }
    }
}

/// One-shot timers on a `.utility` queue.
final class DispatchDetectionScheduler: DetectionScheduling {
    private struct Token: DetectionCancellable {
        let timer: DispatchSourceTimer
        func cancel() { timer.cancel() }
    }

    private let queue = DispatchQueue(label: "com.caffeinagent.app.detection", qos: .utility)

    func schedule(after delay: TimeInterval, leeway: TimeInterval, _ work: @escaping () -> Void) -> DetectionCancellable {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(Int(leeway * 1000)))
        timer.setEventHandler {
            timer.cancel()
            work()
        }
        timer.resume()
        return Token(timer: timer)
    }

    func onMain(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in work() }
    }
}

/// Vnode sources on the state files and process sources on the agent roots.
/// Both cost nothing while nothing happens.
final class SystemDetectionWatcher: DetectionWatching {
    private let queue = DispatchQueue(label: "com.caffeinagent.app.detection.watch", qos: .utility)
    private let lock = NSLock()
    private var files: [String: FileWatch] = [:]
    private var processes: [ProcessIdentity: DispatchSourceProcess] = [:]
    private var onEvent: (() -> Void)?

    deinit {
        stop()
    }

    func watch(files wanted: Set<String>, processes roots: Set<ProcessIdentity>, onEvent: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.onEvent = onEvent
        for (path, watch) in files where !wanted.contains(path) {
            watch.cancel()
            files[path] = nil
        }
        for path in wanted where files[path] == nil {
            let watch = FileWatch(url: URL(fileURLWithPath: path), queue: queue) { [weak self] _ in self?.fire() }
            files[path] = watch
            watch.start()
        }
        for (identity, source) in processes where !roots.contains(identity) {
            source.cancel()
            processes[identity] = nil
        }
        for identity in roots where processes[identity] == nil {
            let source = DispatchSource.makeProcessSource(identifier: identity.pid, eventMask: .exit, queue: queue)
            source.setEventHandler { [weak self] in self?.fire() }
            processes[identity] = source
            source.resume()
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        files.values.forEach { $0.cancel() }
        files.removeAll()
        processes.values.forEach { $0.cancel() }
        processes.removeAll()
        onEvent = nil
    }

    private func fire() {
        lock.lock()
        let onEvent = onEvent
        lock.unlock()
        onEvent?()
    }
}
