import Foundation

/// What is known about the displays at one moment.
struct DisplayInputs: Equatable {
    var lidClosed = false
    /// agent caffeine keeps the Mac awake.
    var holding = false
    /// A display that is not the built-in one is connected.
    var externalDisplay = false
    var builtinOnline = true
    /// The built-in display sleeps, as after the display sleep timer.
    var builtinAsleep = false
    /// Of the built-in display, 0 to 1. Nil when it cannot be read.
    var brightness: Float?
    /// Seconds since the last key or pointer event, also from afar.
    var idle: TimeInterval?
}

struct DisplayMemory: Equatable {
    /// When the lid was first seen closed. Nil while it is open.
    var lidClosedAt: Date?
    var lastSleepAt: Date?
    /// Requests for display sleep since the display last slept.
    var sleepRequests = 0
    var lastDimAt: Date?
    /// Tries to dim that did not work, one after the other.
    var dimFailures = 0
    /// agent caffeine set the brightness of the built-in display to zero
    /// and has the user's value to put back.
    var dimmed = false
}

enum DisplayAction: Equatable {
    /// All displays go to sleep, as with the display sleep timer.
    case sleepDisplays(reason: String)
    /// Only the built-in display: its brightness goes to zero.
    case dimBuiltin(reason: String)
    /// The user's brightness comes back.
    case restoreBuiltin(reason: String)

    var reason: String {
        switch self {
        case .sleepDisplays(let reason), .dimBuiltin(let reason), .restoreBuiltin(let reason): return reason
        }
    }
}

/// Keeps the built-in display dark under a closed lid while agent
/// caffeine keeps the Mac awake. Pure: the caller keeps the memory and
/// passes the time.
///
/// Without an external display, the displays are put to sleep, and again
/// when something wakes them under the lid. When sleep does not hold, the
/// brightness goes to zero as well. With an external display, display sleep
/// would take the display the user works on, so only the brightness of the
/// built-in one goes to zero.
enum DisplayRules {
    /// The same request is not made more often than this.
    static let retryAfter: TimeInterval = 5
    /// At or below this the built-in display counts as dark.
    static let darkLevel: Float = 0.02
    /// After this many tries in a row that did not work, dimming stops
    /// until the lid was open.
    static let dimTries = 3
    /// Keys or a pointer that moved under a closed lid come from someone
    /// who uses the Mac from afar. Display sleep would lock them out, so
    /// for this long after such an event the display is only dimmed.
    static let remoteUseGrace: TimeInterval = 60

    static func decide(_ inputs: DisplayInputs, enabled: Bool, memory: DisplayMemory, now: Date) -> ([DisplayAction], DisplayMemory) {
        var memory = memory
        if !inputs.lidClosed {
            memory.lidClosedAt = nil
            memory.lastSleepAt = nil
            memory.sleepRequests = 0
            memory.lastDimAt = nil
            memory.dimFailures = 0
        } else if memory.lidClosedAt == nil {
            memory.lidClosedAt = now
        }
        guard enabled, inputs.lidClosed, inputs.holding, let lidClosedAt = memory.lidClosedAt else {
            return (restore(inputs, enabled: enabled, memory: memory), memory)
        }

        let asleep = inputs.builtinOnline && inputs.builtinAsleep
        let awake = inputs.builtinOnline && !inputs.builtinAsleep
        // Without a brightness to read, a display that is on counts as lit
        // until it was dimmed.
        let lit = !asleep && (inputs.brightness.map { $0 > darkLevel } ?? (awake && !memory.dimmed))
        let mayDim = lit && memory.dimFailures < dimTries && due(memory.lastDimAt, now: now)
        var actions: [DisplayAction] = []
        func dim(_ reason: String) {
            actions.append(.dimBuiltin(reason: reason))
            memory.lastDimAt = now
        }

        if inputs.externalDisplay {
            if mayDim { dim("the lid is closed and the built-in display is lit next to an external display") }
            return (actions, memory)
        }
        guard awake else {
            memory.sleepRequests = 0
            return (actions, memory)
        }
        let usedFromAfar = inputs.idle.map { $0 < remoteUseGrace && now.addingTimeInterval(-$0) > lidClosedAt } ?? false
        if usedFromAfar {
            if mayDim { dim("the lid is closed and someone uses the Mac from afar") }
            return (actions, memory)
        }
        let askedBefore = memory.sleepRequests > 0
        if due(memory.lastSleepAt, now: now) {
            actions.append(.sleepDisplays(reason: askedBefore ? "the built-in display is still on under the closed lid" : "the lid is closed and the built-in display is on"))
            memory.lastSleepAt = now
            memory.sleepRequests += 1
            if askedBefore, mayDim { dim("display sleep did not hold under the closed lid") }
        }
        return (actions, memory)
    }

    /// The user's brightness comes back when the lid opens and when the
    /// setting goes off. It also comes back when the hold ends without an
    /// external display: the Mac then sleeps, and wakes with its own
    /// brightness. With an external display the Mac stays awake at the
    /// desk, so the built-in display stays dark until the lid opens.
    private static func restore(_ inputs: DisplayInputs, enabled: Bool, memory: DisplayMemory) -> [DisplayAction] {
        guard memory.dimmed else { return [] }
        if !inputs.lidClosed { return [.restoreBuiltin(reason: "the lid is open")] }
        if !enabled { return [.restoreBuiltin(reason: "the setting is off")] }
        if !inputs.externalDisplay { return [.restoreBuiltin(reason: "agent caffeine no longer keeps the Mac awake")] }
        return []
    }

    private static func due(_ last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        // A clock that was set back must not stop the requests.
        let passed = now.timeIntervalSince(last)
        return passed >= retryAfter || passed < 0
    }
}
