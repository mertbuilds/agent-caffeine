import Foundation

/// What the smoke test measured while the app ran. See `SmokeTest`.
struct SmokeMeasurements: Codable, Equatable {
    enum Step: String, Codable {
        case ok
        case failed
        /// The step cannot be done on this macOS.
        case skipped
        /// The run ended before the step.
        case notRun
    }

    /// Seconds the app ran.
    var seconds: Double = 0
    /// The ticks of the 100 ms timer on the main run loop.
    var ticks = 0
    /// The longest time between two ticks after the first second.
    var longestStallMs = 0
    /// Processor time of the process, in percent of one core.
    var cpuPercent: Double = 0
    /// How often SwiftUI worked out the scenes of the app.
    var sceneEvaluations = 0
    /// How often the aggregator said that it changes.
    var publishes = 0
    /// The samples of the detection engine.
    var samples = 0
    var statusItem = false
    /// The status item has an image that is not empty, in a frame.
    var statusItemImage = false
    /// The icon was hidden and shown again through the scene's binding.
    var iconToggle = Step.notRun
    /// Preferences was opened and closed.
    var settingsWindow = Step.notRun
}

/// Whether a build that starts also runs. Pure, so the limits are tested.
enum SmokeHealth {
    static let tickInterval: TimeInterval = 0.1
    static let minTickShare = 0.8
    static let maxStallMs = 500
    static let maxCPUPercent: Double = 15
    static let maxSceneEvaluationsPerSecond: Double = 50
    static let minSamples = 2
    /// A main thread that is silent this long ends the process.
    static let hangSeconds: TimeInterval = 3

    static func expectedTicks(seconds: Double) -> Int {
        Int(seconds / tickInterval)
    }

    static func sceneEvaluationsPerSecond(_ m: SmokeMeasurements) -> Double {
        m.seconds > 0 ? Double(m.sceneEvaluations) / m.seconds : 0
    }

    /// What is wrong, in words. Empty for a healthy run.
    static func failures(_ m: SmokeMeasurements) -> [String] {
        var failures: [String] = []
        let expected = expectedTicks(seconds: m.seconds)
        if Double(m.ticks) < Double(expected) * minTickShare {
            failures.append("main run loop ticked \(m.ticks) times, expected about \(expected)")
        }
        if m.longestStallMs >= maxStallMs {
            failures.append("main thread stalled for \(m.longestStallMs) ms")
        }
        if m.cpuPercent >= maxCPUPercent {
            failures.append("used \(m.cpuPercent) percent of one core")
        }
        let rate = sceneEvaluationsPerSecond(m)
        if rate >= maxSceneEvaluationsPerSecond {
            failures.append("scenes worked out \(Int(rate)) times per second")
        }
        if !m.statusItem {
            failures.append("no status item")
        } else if !m.statusItemImage {
            failures.append("status item has no image")
        }
        if m.samples < minSamples {
            failures.append("engine gave \(m.samples) samples, expected \(minSamples) or more")
        }
        if m.iconToggle == .failed || m.iconToggle == .notRun {
            failures.append("hiding and showing the icon: \(m.iconToggle.rawValue)")
        }
        if m.settingsWindow == .failed || m.settingsWindow == .notRun {
            failures.append("opening Preferences: \(m.settingsWindow.rawValue)")
        }
        return failures
    }

    /// One line of JSON: the measurements, `healthy` and `failures`.
    /// `hang` is set when the main thread stopped and the run was cut.
    static func line(_ m: SmokeMeasurements, hang: String? = nil) -> String {
        var failures = failures(m)
        if let hang { failures.insert(hang, at: 0) }
        let report = Report(
            measurements: m, sceneEvaluationsPerSecond: (sceneEvaluationsPerSecond(m) * 10).rounded() / 10,
            healthy: failures.isEmpty, failures: failures
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) else {
            return "{\"healthy\":false,\"failures\":[\"the report could not be written\"]}"
        }
        return text
    }

    private struct Report: Encodable {
        var measurements: SmokeMeasurements
        var sceneEvaluationsPerSecond: Double
        var healthy: Bool
        var failures: [String]

        private enum Key: String, CodingKey {
            case sceneEvaluationsPerSecond, healthy, failures
        }

        func encode(to encoder: Encoder) throws {
            try measurements.encode(to: encoder)
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(sceneEvaluationsPerSecond, forKey: .sceneEvaluationsPerSecond)
            try container.encode(healthy, forKey: .healthy)
            try container.encode(failures, forKey: .failures)
        }
    }
}
