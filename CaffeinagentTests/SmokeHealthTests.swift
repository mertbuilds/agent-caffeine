import XCTest

final class SmokeHealthTests: XCTestCase {
    /// A run of 8 seconds as a good build gives it: the start of the
    /// app, then the icon and Preferences, then nothing.
    private var good: SmokeMeasurements {
        SmokeMeasurements(
            seconds: 8, ticks: 79, longestStallMs: 104, cpuPercent: 5.9, cpuBySecond: [13.3, 2.1, 19.2, 5.6, 1.8, 0.1, 2.7, 0.1],
            stepSeconds: [1, 2, 3], sceneEvaluations: 9, publishes: 6, samples: 3,
            statusItem: true, statusItemImage: true, iconToggle: .ok, settingsWindow: .ok
        )
    }

    private func failures(_ change: (inout SmokeMeasurements) -> Void) -> [String] {
        var m = good
        change(&m)
        return SmokeHealth.failures(m)
    }

    func testGoodRunIsHealthy() {
        XCTAssertEqual(SmokeHealth.failures(good), [])
        XCTAssertEqual(SmokeHealth.expectedTicks(seconds: 8), 80)
    }

    func testEachLimit() {
        XCTAssertEqual(failures { $0.ticks = 64 }, [])
        XCTAssertEqual(failures { $0.ticks = 63 }, ["main run loop ticked 63 times, expected about 80"])
        XCTAssertEqual(failures { $0.longestStallMs = 499 }, [])
        XCTAssertEqual(failures { $0.longestStallMs = 500 }, ["main thread stalled for 500 ms"])
        XCTAssertEqual(failures { $0.sceneEvaluations = 399 }, [])
        XCTAssertEqual(failures { $0.sceneEvaluations = 400 }, ["scenes worked out 50 times per second"])
        XCTAssertEqual(failures { $0.samples = 1 }, ["engine gave 1 samples, expected 2 or more"])
        XCTAssertEqual(failures { $0.statusItem = false }, ["no status item"])
        XCTAssertEqual(failures { $0.statusItemImage = false }, ["status item has no image"])
        XCTAssertEqual(failures { $0.iconToggle = .failed }, ["hiding and showing the icon: failed"])
        XCTAssertEqual(failures { $0.iconToggle = .notRun }, ["hiding and showing the icon: notRun"])
        XCTAssertEqual(failures { $0.settingsWindow = .failed }, ["opening Preferences: failed"])
        // An older macOS cannot open Preferences without taking the focus.
        XCTAssertEqual(failures { $0.settingsWindow = .skipped }, [])
        XCTAssertEqual(failures { $0.iconToggle = .skipped }, [])
    }

    private func cpuFailures(_ cpuBySecond: [Double], steps: [Int] = [1, 2, 3]) -> [String] {
        failures {
            $0.cpuBySecond = cpuBySecond
            $0.stepSeconds = steps
        }
    }

    func testTheProcessorTimeIsJudgedByTheSteadySeconds() {
        XCTAssertEqual(SmokeHealth.steadyCPU(good), [1.8, 0.1, 2.7, 0.1])
        XCTAssertEqual(SmokeHealth.median([3, 1, 2]), 2)
        XCTAssertEqual(SmokeHealth.median([4, 1, 2, 3]), 2.5)
        // The start of the app and the steps of the test are not judged.
        XCTAssertEqual(cpuFailures([95, 80, 60, 45, 2, 1, 3, 1, 2, 1]), [])
        // One busy second in the middle of the run.
        XCTAssertEqual(cpuFailures([12, 1, 19, 6, 2, 1, 90, 1, 2, 1]), [])
        XCTAssertEqual(cpuFailures([12, 1, 19, 6, 14.9, 14.9, 14.9, 14.9, 14.9, 14.9]), [])
    }

    func testALoopFails() {
        XCTAssertEqual(
            cpuFailures(Array(repeating: 100, count: 10)),
            ["used 100.0% of one core in the median steady second", "used 100.0% of one core over the steady seconds"]
        )
        XCTAssertEqual(cpuFailures(Array(repeating: 20, count: 10)), ["used 20.0% of one core in the median steady second"])
        XCTAssertEqual(cpuFailures([12, 1, 19, 6, 15, 15, 15, 15, 15, 15]), ["used 15.0% of one core in the median steady second"])
        // A loop in less than half of the steady seconds.
        XCTAssertEqual(cpuFailures([12, 1, 19, 6, 2, 1, 2, 1, 120, 120]), ["used 41.0% of one core over the steady seconds"])
        // A step in every second leaves nothing to judge by.
        XCTAssertEqual(
            cpuFailures([12, 1, 19, 6, 2, 1], steps: [1, 2, 3, 4]),
            ["1 steady seconds to judge the processor time by, expected 2 or more"]
        )
    }

    /// The hang of the menu bar scene on macOS 26, as it was measured.
    func testTheMenuBarLoopFails() {
        let hung = SmokeMeasurements(seconds: 3.1, ticks: 1, longestStallMs: 3000, cpuPercent: 99.2, sceneEvaluations: 60000, publishes: 60000)
        XCTAssertGreaterThanOrEqual(SmokeHealth.failures(hung).count, 6)
    }

    func testLineIsOneLineOfJSON() throws {
        let line = SmokeHealth.line(good)
        XCTAssertFalse(line.contains("\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["healthy"] as? Bool, true)
        XCTAssertEqual(object["failures"] as? [String], [])
        XCTAssertEqual(object["ticks"] as? Int, 79)
        XCTAssertEqual(object["longestStallMs"] as? Int, 104)
        XCTAssertEqual(object["cpuPercent"] as? Double, 5.9)
        XCTAssertEqual(object["cpuBySecond"] as? [Double], [13.3, 2.1, 19.2, 5.6, 1.8, 0.1, 2.7, 0.1])
        XCTAssertEqual(object["stepSeconds"] as? [Int], [1, 2, 3])
        XCTAssertEqual(object["clicksIgnored"] as? Int, 0)
        XCTAssertEqual(object["sceneEvaluationsPerSecond"] as? Double, 1.1)
        XCTAssertEqual(object["iconToggle"] as? String, "ok")
        XCTAssertEqual(object["settingsWindow"] as? String, "ok")
        XCTAssertEqual(object["samples"] as? Int, 3)
    }

    func testAHangIsTheFirstFailure() throws {
        let line = SmokeHealth.line(good, hang: "main thread gave no sign for 3 s")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["healthy"] as? Bool, false)
        XCTAssertEqual(object["failures"] as? [String], ["main thread gave no sign for 3 s"])
    }
}
