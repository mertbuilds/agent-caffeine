import AppKit
import Combine

/// What the last license action, or a background check, has to tell the user.
enum LicenseMessage: Equatable {
    case limitReached
    case notFound
    case revoked
    case unavailable
    case activationGone

    var text: String {
        switch self {
        case .limitReached: return "This key is in use on as many Macs as it allows. Choose Deactivate this Mac on one of them, or remove one in Manage in Polar, then try again."
        case .notFound: return "Polar does not recognize this key. Check it for typos."
        case .revoked: return "This key was turned off."
        case .unavailable: return "agent caffeine could not reach Polar. Check your connection and try again."
        case .activationGone: return "This Mac is no longer activated for this key. Activate it again."
        }
    }
}

/// The trial, the key and this Mac's activation of it, and what they allow.
///
/// The record lives in a `LicenseStore` (the login Keychain in the app). The
/// trial clock and the date of the last good validation are mirrored in
/// `UserDefaults`, so a Keychain that cannot be read neither restarts the trial
/// nor locks a paying user out at once: the mirrored validation keeps counting
/// toward the 30 day offline grace.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var entitlement: Entitlement = .expired(.trialOver)
    @Published private(set) var record: LicenseRecord
    @Published private(set) var busy = false
    @Published private(set) var message: LicenseMessage?
    @Published private(set) var storageError: String?

    let config: LicenseConfig
    private let client: LicenseAPI
    private let store: LicenseStore
    private let defaults: UserDefaults
    private let label: String
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var lastRefreshUptime: TimeInterval?
    private var storeReadable: Bool
    private var lastAttempt: Date?
    private var lastAttemptFailed = false
    private var validation: (activationID: String?, token: UUID, task: Task<LicenseValidation?, Never>)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private static let trialStartKey = "License.trialStart"
    private static let latestSeenKey = "License.latestSeen"
    private static let lastValidatedKey = "License.lastValidated"

    init(
        client: LicenseAPI,
        store: LicenseStore,
        defaults: UserDefaults = .standard,
        config: LicenseConfig = .current,
        label: String = LicenseManager.deviceLabel,
        now: @escaping () -> Date = Date.init,
        uptime: @escaping () -> TimeInterval = LicenseManager.monotonicNow
    ) {
        self.client = client
        self.store = store
        self.defaults = defaults
        self.config = config
        self.label = label
        self.now = now
        self.uptime = uptime

        var loaded = LicenseRecord()
        var loadError: String?
        do {
            loaded = try store.load() ?? LicenseRecord()
            storeReadable = true
        } catch {
            storeReadable = false
            loadError = (error as? LicenseStoreError)?.message ?? error.localizedDescription
            loaded.lastValidated = defaults.object(forKey: Self.lastValidatedKey) as? Date
        }
        loaded.trialStart = Self.earliest(loaded.trialStart, defaults.object(forKey: Self.trialStartKey) as? Date)
        loaded.latestSeen = Self.latest(loaded.latestSeen, defaults.object(forKey: Self.latestSeenKey) as? Date)
        record = loaded
        storageError = loadError
        refresh()
    }

    /// The Mac's model identifier, such as `MacBookPro18,3`. Never the
    /// computer's name, which often holds a person's name.
    nonisolated static var deviceLabel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        let model = String(cString: buffer)
        return model.isEmpty ? "Mac" : model
    }

    // CLOCK_MONOTONIC keeps counting while the Mac sleeps, and setting the
    // wall clock does not change it.
    nonisolated static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    /// Validates now, then checks every hour whether a validation is due and
    /// whether the trial ran out, and again after the Mac wakes.
    func start() {
        Task { await validate() }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Returns the validation it started or joined, so a caller can wait for it.
    @discardableResult
    func tick() -> Task<LicenseValidation?, Never>? {
        if !storeReadable { reloadStore() }
        refresh()
        return validationDue ? startValidation() : nil
    }

    /// Once a day, or every hour while Polar could not be reached.
    var validationDue: Bool {
        guard let lastAttempt else { return true }
        let elapsed = now().timeIntervalSince(lastAttempt)
        return elapsed < 0 || elapsed >= LicenseRules.day || (lastAttemptFailed && elapsed >= 3600)
    }

    // MARK: - Actions

    func activate(key: String) async {
        let key = LicenseClient.cleaned(key)
        guard !key.isEmpty, !busy else { return }
        busy = true
        message = nil
        defer { busy = false }

        // A key already activated here asks whether its activation still
        // holds, rather than asking for a second one it would be refused.
        if key == record.key, record.activationID != nil {
            switch await validate() {
            case .valid:
                return
            case .unavailable:
                message = .unavailable
                return
            case .notFound, .revoked, nil:
                break
            }
        }

        switch await client.activate(key: key, label: label) {
        case .activated(let id, let macs):
            record.key = key
            record.activationID = id
            record.macLimit = macs
            record.lastValidated = currentTime
            message = nil
        case .limitReached:
            message = .limitReached
        case .notFound:
            message = .notFound
        case .revoked:
            message = .revoked
        case .unavailable:
            message = .unavailable
        }
        persist()
        recompute()
    }

    /// Asks Polar about this Mac's activation. Nothing is asked without one:
    /// a validation without an activation id proves nothing.
    @discardableResult
    func validate() async -> LicenseValidation? {
        await startValidation().value
    }

    /// At most one validation is in flight. A caller joins the running one
    /// unless the activation changed since it started, since its answer is
    /// then thrown away.
    private func startValidation() -> Task<LicenseValidation?, Never> {
        if let running = validation, running.activationID == record.activationID {
            return running.task
        }
        let token = UUID()
        let task = Task {
            defer { if validation?.token == token { validation = nil } }
            return await performValidation()
        }
        validation = (record.activationID, token, task)
        return task
    }

    private func performValidation() async -> LicenseValidation? {
        guard let key = record.key, let id = record.activationID else { return nil }
        lastAttempt = now()
        let result = await client.validate(key: key, activationID: id)
        // The activation changed while Polar was asked; the answer is stale.
        guard record.activationID == id else { return nil }
        lastAttemptFailed = result == .unavailable
        switch result {
        case .valid:
            record.lastValidated = currentTime
            message = nil
        case .notFound:
            forgetActivation()
            message = .activationGone
        case .revoked:
            forgetActivation()
            message = .revoked
        case .unavailable:
            // Nothing is known; the offline grace decides.
            break
        }
        persist()
        recompute()
        return result
    }

    /// A validation the user asked for, which says so when Polar could not be
    /// reached.
    func checkNow() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        if await validate() == .unavailable { message = .unavailable }
    }

    /// Frees the key for another Mac.
    func deactivate() async {
        guard let key = record.key, let id = record.activationID, !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        switch await client.deactivate(key: key, activationID: id) {
        case .deactivated, .notFound:
            forgetActivation()
        case .unavailable:
            message = .unavailable
        }
        persist()
        recompute()
    }

    // MARK: - State

    /// When the trial ends or ended. Nil before the first launch is stored.
    var trialEnd: Date? {
        record.trialStart.map { $0.addingTimeInterval(LicenseRules.trialLength) }
    }

    private var currentTime: Date {
        LicenseRules.effectiveNow(now(), latestSeen: record.latestSeen)
    }

    /// Keeps the key text so the user can activate again in one click.
    private func forgetActivation() {
        record.activationID = nil
        record.lastValidated = nil
    }

    private func refresh() {
        let measured = uptime()
        let elapsed = lastRefreshUptime.map { measured - $0 }
        lastRefreshUptime = measured
        let current = LicenseRules.latestSeen(previous: record.latestSeen, now: now(), elapsed: elapsed)
        record.latestSeen = current
        if record.trialStart == nil { record.trialStart = current }
        persist()
        recompute()
    }

    private func recompute() {
        // While the stored activation cannot be read, the mirrored validation
        // date stands in for it.
        let activationKnown = record.activationID != nil || !storeReadable
        let value = LicenseRules.entitlement(record: record, activationKnown: activationKnown, now: now())
        if entitlement != value { entitlement = value }
    }

    private func persist() {
        defaults.set(record.trialStart, forKey: Self.trialStartKey)
        defaults.set(record.latestSeen, forKey: Self.latestSeenKey)
        if record.activationID != nil {
            defaults.set(record.lastValidated, forKey: Self.lastValidatedKey)
        } else if storeReadable {
            defaults.removeObject(forKey: Self.lastValidatedKey)
        }
        // Writing over a record that could not be read would lose it.
        guard storeReadable else { return }
        do {
            try store.save(record)
            if storageError != nil { storageError = nil }
        } catch {
            storageError = (error as? LicenseStoreError)?.message ?? error.localizedDescription
        }
    }

    private func reloadStore() {
        guard let loaded = try? store.load() ?? LicenseRecord() else { return }
        storeReadable = true
        storageError = nil
        // An activation made while the store was unreadable wins over the
        // stored one.
        if record.activationID == nil {
            record.key = loaded.key ?? record.key
            record.activationID = loaded.activationID
            record.lastValidated = loaded.lastValidated
        }
        record.trialStart = Self.earliest(record.trialStart, loaded.trialStart)
        record.latestSeen = Self.latest(record.latestSeen, loaded.latestSeen)
    }

    private static func earliest(_ a: Date?, _ b: Date?) -> Date? {
        guard let a, let b else { return a ?? b }
        return min(a, b)
    }

    private static func latest(_ a: Date?, _ b: Date?) -> Date? {
        guard let a, let b else { return a ?? b }
        return max(a, b)
    }
}
