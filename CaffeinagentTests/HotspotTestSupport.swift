import XCTest

/// The air of a test: which networks a scan sees, which the Mac knows
/// and which password each takes. It never reaches the Wi-Fi of the Mac.
final class FakeWiFi: WiFiAccess {
    var powered: Bool? = true
    var current: String?
    /// The names a scan can see, as the air spells them. Each takes a
    /// password, with a good signal.
    var air: Set<String> = []
    /// More networks on the air: a second one with a name of `air`, an
    /// open one, a weak one.
    var others: [WiFiSeen] = []
    /// The networks macOS knows, each as one with a password.
    var known: Set<String> = []
    /// A network macOS knows as another kind.
    var knownAs: [String: WiFiSecurity] = [:]
    /// The password each network takes. A network that is not here is
    /// joined only with no password, and only when it is known.
    var passwords: [String: String] = [:]
    /// macOS does not answer a question about the Wi-Fi.
    var readFailure: HopFailure?
    var scanFailure: HopFailure?
    var joinFailure: HopFailure?
    private(set) var scans: [String] = []
    private(set) var joins: [String] = []
    private(set) var joinPasswords: [String?] = []
    /// The network each join that worked went to.
    private(set) var joined: [WiFiSeen] = []
    /// The network of the last scan that found one.
    private let found = FoundNetwork<WiFiSeen>()

    func power() -> Result<Bool, HopFailure> {
        if let readFailure { return .failure(readFailure) }
        return powered.map { .success($0) } ?? .failure(.noWiFi)
    }

    func currentNetwork() -> Result<String?, HopFailure> {
        readFailure.map { .failure($0) } ?? .success(current)
    }

    private var seen: [WiFiSeen] {
        air.sorted().map { WiFiSeen(name: $0, sighting: WiFiSighting(rssi: -52, channel: 6), security: .personal) } + others
    }

    func scan(for name: String) -> WiFiScan {
        scans.append(name)
        found.forget()
        if let scanFailure { return .failed(scanFailure) }
        let seen = seen
        let pick = WiFiPick.hotspot(name, among: seen)
        if let index = pick.index { found.keep(seen[index]) }
        return pick.scan
    }

    func scanKnown(_ name: String) -> WiFiScan {
        scans.append(name)
        found.forget()
        if let scanFailure { return .failed(scanFailure) }
        guard let security = knownAs[name] ?? (known.contains(name) ? .personal : nil) else { return .notFound }
        let seen = seen.filter { $0.security == security }
        let pick = WiFiPick.known(name, among: seen)
        if let index = pick.index { found.keep(seen[index]) }
        return pick.scan
    }

    func associate(to name: String, password: String?) -> WiFiJoin {
        joins.append(name)
        joinPasswords.append(password)
        if let joinFailure { return .failed(joinFailure) }
        guard let found = found.take(), HotspotName.matches(found.name, name) else { return .failed(.other) }
        // An open network takes anyone, with any password.
        if found.security != .open {
            if let right = passwords[found.name] {
                guard password == right else { return .failed(.wrongPassword) }
            } else if password != nil || (knownAs[found.name] == nil && !known.contains(found.name)) {
                return .failed(.wrongPassword)
            }
        }
        current = found.name
        joined.append(found)
        return .joined
    }

    func knownSecurity(of name: String) -> Result<WiFiSecurity?, HopFailure> {
        if let readFailure { return .failure(readFailure) }
        return .success(knownAs[name] ?? (known.contains(name) ? .personal : nil))
    }
}

/// A Keychain in memory.
final class FakePasswordStore: HotspotPasswordStoring {
    var password: String?
    var refusesSave = false
    var refusesRemove = false
    /// The Keychain is locked, or gives no answer.
    var loadFailure: HopFailure?
    private(set) var loads = 0

    func save(_ password: String) -> Bool {
        guard !refusesSave else { return false }
        self.password = password
        return true
    }

    func load() -> Result<String, HopFailure> {
        loads += 1
        if let loadFailure { return .failure(loadFailure) }
        return password.map { .success($0) } ?? .failure(.noPassword)
    }

    func remove() -> Bool {
        guard !refusesRemove else { return false }
        password = nil
        return true
    }
}

/// A Mac that is sampled every 2 seconds, as the engine does it while an
/// agent runs. Each action of the hop is run at once against the fake
/// air, and a join that works gives the Mac its way to the network back.
struct HopMac {
    static let start = Date(timeIntervalSince1970: 1_791_200_000)
    static let step: TimeInterval = 2
    static let hotspot = "Mert\u{2019}s iPhone"
    static let password = "open-sesame-42"
    static let cafe = "Cafe Wi-Fi"

    var hop = HotspotHop()
    let wifi = FakeWiFi()
    var input = HotspotHop.Input(on: true, name: HopMac.hotspot, saves: 1, agentHolds: true, online: true)
    var password: String? = HopMac.password
    /// The Keychain is locked, or gives no answer.
    var passwordFailure: HopFailure?
    /// False keeps an action pending until `finish` is called.
    var runsJobsAtOnce = true
    private(set) var awake: TimeInterval = 100
    private(set) var wall: TimeInterval = 0
    /// The awake time of each scan for the hotspot.
    private(set) var tryTimes: [TimeInterval] = []
    private(set) var actions: [HotspotHop.Action] = []
    private(set) var waiting: HotspotHop.Action?

    /// On the cafe Wi-Fi, which macOS knows, with the phone on the air.
    init() {
        wifi.air = [Self.cafe, Self.hotspot]
        wifi.known = [Self.cafe]
        wifi.passwords = [Self.hotspot: Self.password]
        wifi.current = Self.cafe
    }

    var time: SampleTime { SampleTime(at: Self.start.addingTimeInterval(wall), awake: awake) }
    var now: Date { time.at }
    var state: HotspotHop.State { hop.state }

    /// The Wi-Fi goes away: the Mac is on no network and has no path.
    mutating func loseWiFi() {
        wifi.air.remove(Self.cafe)
        wifi.current = nil
        input.online = false
    }

    /// The Mac sleeps for this long. No sample is taken.
    mutating func sleep(_ seconds: TimeInterval) {
        wall += seconds
    }

    mutating func sample() {
        awake += Self.step
        wall += Self.step
        guard let action = hop.update(input, at: time) else { return }
        actions.append(action)
        if case .join = action { tryTimes.append(awake) }
        if runsJobsAtOnce {
            run(action)
        } else {
            waiting = action
        }
    }

    /// Ends the action that waits.
    mutating func finish() {
        guard let action = waiting else { return }
        waiting = nil
        run(action)
    }

    private mutating func run(_ action: HotspotHop.Action) {
        let online = input.online
        let saved: Result<String, HopFailure> = passwordFailure.map { .failure($0) } ?? password.map { .success($0) } ?? .failure(.noPassword)
        let outcome = HotspotJob.run(action, wifi: wifi, password: { saved }, mayJoin: { !online })
        if outcome == .joined || outcome == .wentBack { input.online = true }
        hop.finished(action, outcome, at: time)
    }

    mutating func run(seconds: TimeInterval) {
        for _ in 0..<Int(seconds / Self.step) { sample() }
    }
}
