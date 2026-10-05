import Foundation

enum AppVersion {
    /// "Version 0.2.3 (13)" for the running app.
    static var current: String {
        display(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static func display(version: String?, build: String?) -> String {
        let version = version ?? "unknown"
        guard let build, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}
