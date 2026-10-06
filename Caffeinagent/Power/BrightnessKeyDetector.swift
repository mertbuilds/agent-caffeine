import Foundation

/// Tells a press of a brightness key from the fade's own writes and from
/// the slow moves of auto-brightness.
///
/// A key moves the brightness by 1/16 at once. Auto-brightness moves it a
/// little at a time. So a new value counts as the user's only when it is
/// a jump from the value that stood a moment before, and only while the
/// lid rests and the fade writes nothing. A slow move is followed and is
/// never the user's.
///
/// Pure: the caller passes the time.
struct BrightnessKeyDetector: Equatable {
    /// A jump of this much is a key. One press is 0.0625.
    static let keyStep: Float = 0.05
    /// A move of less than this from one reading to the next is a drift.
    static let drift: Float = 0.02
    /// The jump has to come within this long of the value that stood.
    static let window: TimeInterval = 1

    /// The brightness that stood last, and when it was seen.
    private(set) var steady: Float?
    private var steadyAt: Date?

    /// The fade set this value: it is not the user's.
    mutating func wrote(_ level: Float, now: Date) {
        steady = level
        steadyAt = now
    }

    /// One reading of the brightness. `rested` is true while the lid
    /// rests with the user's brightness on and the fade is quiet. Gives
    /// the new value when the user set it.
    mutating func read(_ level: Float, rested: Bool, now: Date) -> Float? {
        guard rested else { return nil }
        guard let steady, let steadyAt else {
            wrote(level, now: now)
            return nil
        }
        let moved = abs(level - steady)
        let age = now.timeIntervalSince(steadyAt)
        if moved >= Self.keyStep, age >= 0, age <= Self.window {
            wrote(level, now: now)
            return level
        }
        // A drift is followed. A value in between waits for the next
        // reading, in case a key is still on its way.
        if moved < Self.drift || age > Self.window || age < 0 { wrote(level, now: now) }
        return nil
    }
}
