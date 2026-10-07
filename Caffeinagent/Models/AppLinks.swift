import Foundation

/// Where the app sends the user outside itself.
enum AppLinks {
    static let help = URL(string: "https://caffeinagent.com/?utm_source=agent-caffeine-app&utm_medium=app&utm_campaign=help#faq")!
    static let contactAddress = "hi@caffeinagent.com"
    static let contact = URL(string: "mailto:\(contactAddress)")!
}
