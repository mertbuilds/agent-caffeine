import Foundation

/// Where the app sends the user outside itself.
enum AppLinks {
    static let help = URL(string: "https://caffeinagent.com/?utm_source=agent-caffeine-app&utm_medium=app&utm_campaign=help#faq")!
    static let contactAddress = "hi@caffeinagent.com"
    static let contact = URL(string: "mailto:\(contactAddress)")!
    /// The offer of the source code that the license asks for.
    static let sourceCode = URL(string: "https://github.com/mertbuilds/agent-caffeine")!
    static let support = URL(string: "https://caffeinagent.com/support?utm_source=app&utm_medium=about")!
    /// The notices of what the app carries from other people.
    static let acknowledgements = URL(string: "\(sourceCode.absoluteString)/blob/main/THIRD_PARTY_NOTICES.md")!
}
