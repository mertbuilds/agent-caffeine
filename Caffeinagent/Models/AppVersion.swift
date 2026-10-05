import Foundation

enum AppVersion {
    /// "Version 0.2.3 (13)" for the running app.
    static var current: String {
        display(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    /// "0.2.3 (13)", the form in which the root helper reports its own version.
    static var helperForm: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    static func display(version: String?, build: String?) -> String {
        let version = version ?? "unknown"
        guard let build, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}
