import Foundation

/// The name of a Wi-Fi network as the user types it and as the air has
/// it. iOS names a hotspot "Mert’s iPhone" with the typographic
/// apostrophe U+2019, and a keyboard of a Mac types the straight one
/// unless smart quotes are on. A scan looks for the exact bytes, so a
/// name is compared and looked for in both spellings.
///
/// Network names are private. Nothing here is logged, and no name goes
/// into the state for the tests or into a recording.
enum HotspotName {
    private static let straight: Character = "'"
    private static let curly: Character = "\u{2019}"
    /// What counts as an apostrophe: U+0027, U+2019 and U+2018.
    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{2018}"]

    /// Without the spaces around it. Nil for a name that is empty then.
    static func cleaned(_ name: String?) -> String? {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func spelled(_ name: String, with apostrophe: Character) -> String {
        String(name.map { apostrophes.contains($0) ? apostrophe : $0 })
    }

    /// The same name, whatever apostrophe each has.
    static func matches(_ one: String, _ other: String) -> Bool {
        spelled(one, with: straight) == spelled(other, with: straight)
    }

    /// The names to scan for: as typed first, then with the apostrophe of
    /// iOS, then with the straight one. One entry for a name without an
    /// apostrophe.
    static func spellings(of name: String) -> [String] {
        var all: [String] = []
        for spelling in [name, spelled(name, with: curly), spelled(name, with: straight)] where !all.contains(spelling) {
            all.append(spelling)
        }
        return all
    }
}
