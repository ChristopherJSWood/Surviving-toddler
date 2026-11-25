import Foundation

/// Who's in the house. Every `{placeholder}` in the content is filled from this.
/// The toddler and the partner are always "they" in the game's text.
struct Household: Codable, Equatable {
    var kid = ""
    var partner = ""
    /// What the toddler calls you: Mama, Dada, Papa...
    var me = ""

    static let callYouSuggestions = ["Mama", "Dada", "Mommy", "Daddy", "Mom", "Dad", "Papa", "Mum"]
    static let maxNameLength = 14

    var isComplete: Bool { !kid.trimmed.isEmpty && !partner.trimmed.isEmpty && !me.trimmed.isEmpty }

    /// Fills {kid} {KID} {partner} {me} {ME}. Falls back to neutral stand-ins if
    /// a name is somehow missing (old saves), so text never shows raw braces.
    func fill(_ text: String) -> String {
        guard text.contains("{") else { return text }
        let kid = self.kid.trimmed.isEmpty ? "Bean" : self.kid.trimmed
        let partner = self.partner.trimmed.isEmpty ? "your partner" : self.partner.trimmed
        let me = self.me.trimmed.isEmpty ? "Mama" : self.me.trimmed
        return text
            .replacingOccurrences(of: "{kid}", with: kid)
            .replacingOccurrences(of: "{KID}", with: kid.uppercased())
            .replacingOccurrences(of: "{partner}", with: partner)
            .replacingOccurrences(of: "{me}", with: me)
            .replacingOccurrences(of: "{ME}", with: me.uppercased())
    }

    /// Trims and caps each field.
    func cleaned() -> Household {
        func clip(_ s: String) -> String { String(s.trimmed.prefix(Self.maxNameLength)) }
        return Household(kid: clip(kid), partner: clip(partner), me: clip(me))
    }
}

/// One playtest reaction: the player tapped 😂 or 😴 on an outcome.
struct Reaction: Codable, Equatable {
    enum Kind: String, Codable { case laugh, bored }

    var at: Date
    var day: Int
    /// The engine step the outcome came from (one reaction per step).
    var step: Int
    var card: String
    var title: String
    var choice: Int
    var outcome: Int
    var kind: Kind
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Quoted for a CSV cell.
    var csvCell: String { "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
