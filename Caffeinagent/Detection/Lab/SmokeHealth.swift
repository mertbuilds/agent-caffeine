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
    /// Processor time of the process over the whole run, in percent of
    /// one core. With the start of the app, so it is not judged.
    var cpuPercent: Double = 0
    /// The same for each whole second of the run, the first one first.
    var cpuBySecond: [Double] = []
    /// The seconds of the run, from 0, in which the test itself hid and
    /// showed the icon or opened Preferences.
    var stepSeconds: [Int] = []
    /// The seconds of the run, from 0, in which the menu was open.
    var panelSeconds: [Int] = []
    /// Clicks on the icon or a window that the test kept from the app.
    var clicksIgnored = 0
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
    /// The menu was shown, with a robot that floats and agents at work.
    /// Skipped in a run that is too short for it.
    var panel = Step.notRun
}

/// Whether a build that starts also runs. Pure, so the limits are tested.
enum SmokeHealth {
    static let tickInterval: TimeInterval = 0.1
    static let minTickShare = 0.8
    static let maxStallMs = 500
    /// The first seconds of the run are the start of the app.
    static let launchSeconds = 2
    /// The steps run early, so the seconds after them are steady.
    static let iconToggleAt: TimeInterval = 1
    static let settingsWindowAt: TimeInterval = 2.4
    static let minSteadySeconds = 2
    /// For the median of the steady seconds: one busy second is no loop.
    static let maxCPUPercent: Double = 15
    /// For their mean: a loop that runs in less than half of them.
    static let maxMeanCPUPercent: Double = 40
    static let maxSceneEvaluationsPerSecond: Double = 50
    /// The menu is open for the last seconds of the run: one to open it,
    /// then the ones it is judged by.
    static let panelSeconds: TimeInterval = 6
    /// A shorter run has no steady seconds left before the menu opens.
    static let minSecondsWithPanel: TimeInterval = 12
    /// For the median of the seconds with the menu open. Its motion runs
    /// in the render server, so the app has next to nothing to do. A
    /// motion that the app works out for each frame takes 20% or more.
    static let maxPanelCPUPercent: Double = 12
    static let minSamples = 2
    /// A main thread that is silent this long ends the process.
    static let hangSeconds: TimeInterval = 3

    static func expectedTicks(seconds: Double) -> Int {
        Int(seconds / tickInterval)
    }

    static func sceneEvaluationsPerSecond(_ m: SmokeMeasurements) -> Double {
        m.seconds > 0 ? Double(m.sceneEvaluations) / m.seconds : 0
    }

    /// When the menu opens in a run of this length. Nil for a run that is
    /// too short.
    static func panelOpensAt(seconds: TimeInterval) -> TimeInterval? {
        seconds >= minSecondsWithPanel ? seconds - panelSeconds : nil
    }

    /// The seconds the processor time is judged by: not the start of the
    /// app, not the ones the test itself worked in, and not the ones with
    /// the menu open.
    static func steadyCPU(_ m: SmokeMeasurements) -> [Double] {
        m.cpuBySecond.enumerated()
            .filter { $0.offset >= launchSeconds && !m.stepSeconds.contains($0.offset) && !m.panelSeconds.contains($0.offset) }
            .map(\.element)
    }

    /// The seconds with the menu open, without the one it opened in.
    static func panelCPU(_ m: SmokeMeasurements) -> [Double] {
        m.cpuBySecond.enumerated().filter { m.panelSeconds.contains($0.offset) && !m.stepSeconds.contains($0.offset) }.map(\.element)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    private static func rounded(_ percent: Double) -> Double {
        (percent * 10).rounded() / 10
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
        let steady = steadyCPU(m)
        if steady.count < minSteadySeconds {
            failures.append("\(steady.count) steady seconds to judge the processor time by, expected \(minSteadySeconds) or more")
        } else {
            let median = median(steady), mean = steady.reduce(0, +) / Double(steady.count)
            if median >= maxCPUPercent {
                failures.append("used \(rounded(median))% of one core in the median steady second")
            }
            if mean >= maxMeanCPUPercent {
                failures.append("used \(rounded(mean))% of one core over the steady seconds")
            }
        }
        if m.panel == .ok {
            let open = panelCPU(m)
            if open.count < minSteadySeconds {
                failures.append("\(open.count) seconds with the menu open to judge the processor time by, expected \(minSteadySeconds) or more")
            } else if median(open) >= maxPanelCPUPercent {
                failures.append("used \(rounded(median(open)))% of one core in the median second with the menu open")
            }
        } else if m.panel == .failed || m.panel == .notRun {
            failures.append("showing the menu: \(m.panel.rawValue)")
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
