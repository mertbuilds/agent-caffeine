import Foundation

/// Writes the state for the tests next to the status of the command line
/// tool, and only while the hidden switch `TestState.defaultsKey` is on.
/// The switch is read at every call, so `defaults write` from a Terminal
/// turns the file on and off while the app runs. Off, the file is removed.
final class TestStateWriter {
    private let store: HoldStore
    private let defaults: UserDefaults
    /// The file was removed since the switch went off, or was never
    /// looked at: one that an earlier run left goes at the first call.
    private var removed = false

    init(store: HoldStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
    }

    var isOn: Bool { defaults.bool(forKey: TestState.defaultsKey) }

    /// - Parameter state: asked for only while the switch is on.
    /// - Returns: false when nothing was written.
    @discardableResult
    func update(_ state: () -> TestState) -> Bool {
        guard isOn else {
            if !removed { remove() }
            return false
        }
        guard let data = state().encoded(), store.writeState(data) else { return false }
        removed = false
        return true
    }

    func remove() {
        store.removeState()
        removed = true
    }
}
