import Foundation

/// What "Save" came to, for the line below the fields.
enum HotspotSaveNote: Equatable {
    /// The name or the password is missing.
    case incomplete
    case keychainFailed
    /// The Keychain did not remove the password. It is still there.
    case removeFailed
    /// Saved, and what macOS says about the names of Wi-Fi networks.
    case saved(LocationPermission)
}

/// What Settings, the menu and the state for the tests show of "Join
/// your iPhone hotspot".
struct HotspotView: Equatable {
    var settings = HotspotSettings()
    var state = HotspotHop.State.idle
    /// The Mac had a way to the network at the last sample.
    var online = true
    var permission = LocationPermission.notAsked
    var saveNote: HotspotSaveNote?

    /// The feature is on, or a password is still in the Keychain: there
    /// is something to forget.
    var somethingSaved: Bool { settings.on || settings.passwordSaved }

    /// Since when the Mac is on the hotspot because of a hop, for the
    /// line in the menu.
    var onHotspotSince: Date? {
        guard settings.on, online, case .joined(let at) = state else { return nil }
        return at
    }
}

/// A switch that is read off the main thread.
private final class HopGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    func set(_ open: Bool) {
        lock.lock()
        self.open = open
        lock.unlock()
    }
}

/// Runs `HotspotHop`: asks it with every sample, runs the action it
/// wants off the main thread, and keeps the settings. It has no timer of
/// its own.
///
/// While the feature is off it reads nothing: not the Wi-Fi, not the
/// Keychain and not the permission.
@MainActor
final class HotspotHopLoop {
    /// Runs `work` off the main thread and gives what it came to back on
    /// the main actor. A test runs it at once.
    typealias Perform = (_ work: @escaping () -> HotspotHop.Outcome, _ done: @escaping @MainActor (HotspotHop.Outcome) -> Void) -> Void

    private(set) var view = HotspotView()
    /// Called when `view` changed.
    var onChange: (() -> Void)?

    private var hop = HotspotHop()
    private let wifi: WiFiAccess
    private let passwords: HotspotPasswordStoring
    private let location: LocationAsking
    private let defaults: UserDefaults
    private let isOnline: () -> Bool
    private let now: () -> SampleTime
    private let perform: Perform
    private let gate = HopGate()

    /// - Parameters:
    ///   - isOnline: the way to the network right now. Asked off the
    ///     main thread, right before a join.
    init(
        wifi: WiFiAccess, passwords: HotspotPasswordStoring, location: LocationAsking, defaults: UserDefaults,
        isOnline: @escaping () -> Bool,
        now: @escaping () -> SampleTime = { SampleTime(at: Date(), awake: SampleGap.awakeSeconds()) },
        perform: @escaping Perform
    ) {
        self.wifi = wifi
        self.passwords = passwords
        self.location = location
        self.defaults = defaults
        self.isOnline = isOnline
        self.now = now
        self.perform = perform
        view.settings = HotspotSettingsStore.load(from: defaults)
        if view.settings.on { view.permission = location.permission }
    }

    // MARK: Samples

    /// One sample of the engine.
    func sampled(decision: HoldDecision, context: FrameContext, at time: SampleTime) {
        var next = view
        next.online = !context.offline
        let settings = view.settings
        if settings.on { next.permission = location.permission }
        let input = HotspotHop.Input(
            on: settings.on, name: settings.isSetUp ? settings.name : nil, saves: settings.saves, hopBack: settings.hopBack,
            agentHolds: HotspotHop.agentHolds(decision), stopped: decision.headline.isStop, online: !context.offline,
            permissionDenied: next.permission == .denied, lidClosed: context.lidClosed, onBattery: context.onBattery
        )
        gate.set(input.on && input.agentHolds && !input.stopped)
        let action = hop.update(input, at: time)
        next.state = hop.state
        publish(next)
        if let action { run(action) }
    }

    private func run(_ action: HotspotHop.Action) {
        perform(Self.work(action, wifi: wifi, passwords: passwords, gate: gate, isOnline: isOnline), { [weak self] outcome in
            guard let self else { return }
            self.hop.finished(action, outcome, at: self.now())
            var next = self.view
            next.state = self.hop.state
            self.publish(next)
        })
    }

    /// Made outside the main actor: it runs off the main thread.
    private nonisolated static func work(
        _ action: HotspotHop.Action, wifi: WiFiAccess, passwords: HotspotPasswordStoring, gate: HopGate, isOnline: @escaping () -> Bool
    ) -> () -> HotspotHop.Outcome {
        { HotspotJob.run(action, wifi: wifi, password: passwords.load, mayJoin: { gate.isOpen && !isOnline() }) }
    }

    private func publish(_ next: HotspotView) {
        guard next != view else { return }
        view = next
        onChange?()
    }

    // MARK: Settings

    /// Off forgets the hotspot: the name goes from the settings and the
    /// password from the Keychain.
    func setOn(_ on: Bool) {
        guard on != view.settings.on else { return }
        guard on else { return forget() }
        var settings = view.settings
        settings.on = true
        var next = view
        next.saveNote = nil
        store(settings, in: next)
    }

    func setHopBack(_ on: Bool) {
        var settings = view.settings
        settings.hopBack = on
        store(settings)
    }

    /// "Save". An empty password keeps the one that is saved. This is
    /// the only place that asks macOS for the permission.
    func save(name: String, password: String) {
        var settings = view.settings
        guard settings.on else { return }
        guard let name = HotspotName.cleaned(name), !password.isEmpty || settings.passwordSaved else {
            return note(.incomplete)
        }
        if !password.isEmpty {
            guard passwords.save(password) else { return note(.keychainFailed) }
            settings.passwordSaved = true
        }
        settings.name = name
        settings.saves += 1
        store(settings)
        // The answer of macOS can take as long as the user takes.
        note(.saved(location.permission))
        location.ask { [weak self] permission in
            guard let self, self.view.settings.on else { return }
            var next = self.view
            next.permission = permission
            next.saveNote = .saved(permission)
            self.publish(next)
        }
    }

    /// Takes the name and the password away, and switches the feature
    /// off. The Mac stays on the network it is on. When the Keychain
    /// does not remove the password, the settings go on saying that one
    /// is saved, with a line, so the user can try again.
    func forget() {
        let removed = passwords.remove()
        gate.set(false)
        var settings = HotspotSettings()
        // A later save is a new one for the rules.
        settings.saves = view.settings.saves
        settings.passwordSaved = !removed
        var next = HotspotView()
        next.online = view.online
        if !removed { next.saveNote = .removeFailed }
        store(settings, in: next)
    }

    /// Called when Settings opens: the user can change the permission in
    /// System Settings at any time.
    func refresh() {
        guard view.settings.on else { return }
        var next = view
        next.permission = location.permission
        publish(next)
    }

    private func note(_ note: HotspotSaveNote) {
        var next = view
        next.saveNote = note
        publish(next)
    }

    private func store(_ settings: HotspotSettings, in view: HotspotView? = nil) {
        var next = view ?? self.view
        next.settings = settings
        HotspotSettingsStore.save(settings, to: defaults)
        publish(next)
    }
}
