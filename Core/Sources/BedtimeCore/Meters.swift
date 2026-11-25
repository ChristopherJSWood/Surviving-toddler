import Foundation

/// The five gauges the game tracks. Every value is an integer clamped to 0...100.
/// Players see four: Bandwidth (`energy`), Relationship (`rel`), Mood and
/// Sleep (how rested the toddler is, 100 - `debt`). Today's `sleepy` is shown
/// as a bedtime word, not a bar.
///
/// The declaration order is significant: it matches `METERS` in
/// `tools/engine.mjs`, and golden traces store meters in this order.
public enum Meter: String, CaseIterable, Codable, Sendable {
    case energy, rel, mood, sleepy, debt

    public static let parent: [Meter] = [.energy, .rel]
    public static let toddler: [Meter] = [.mood, .sleepy, .debt]
}

/// A full set of meter values. Writes go through the subscript, which clamps,
/// so no code path can push a meter outside 0...100.
public struct Meters: Codable, Equatable, Sendable {
    public private(set) var energy: Int
    public private(set) var rel: Int
    public private(set) var mood: Int
    public private(set) var sleepy: Int
    public private(set) var debt: Int

    public static let range = 0...100

    public init(energy: Int, rel: Int, mood: Int, sleepy: Int, debt: Int) {
        self.energy = Self.clamp(energy)
        self.rel = Self.clamp(rel)
        self.mood = Self.clamp(mood)
        self.sleepy = Self.clamp(sleepy)
        self.debt = Self.clamp(debt)
    }

    /// How rested the toddler is this week: the Sleep bar (high is good).
    public var rested: Int { 100 - debt }

    public subscript(meter: Meter) -> Int {
        get {
            switch meter {
            case .energy: return energy
            case .rel: return rel
            case .mood: return mood
            case .sleepy: return sleepy
            case .debt: return debt
            }
        }
        set {
            let value = Self.clamp(newValue)
            switch meter {
            case .energy: energy = value
            case .rel: rel = value
            case .mood: mood = value
            case .sleepy: sleepy = value
            case .debt: debt = value
            }
        }
    }

    /// Values in `Meter.allCases` order (the golden-trace format).
    public var values: [Int] { Meter.allCases.map { self[$0] } }

    static func clamp(_ value: Int) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, value))
    }
}
