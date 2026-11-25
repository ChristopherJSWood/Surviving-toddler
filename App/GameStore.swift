import BedtimeCore
import Foundation
import Observation

/// Lifetime totals shown on the title screen.
struct PlayerStats: Codable, Equatable {
    var weeksPlayed = 0
    var weeksWon = 0
    var bestScore = 0
    var endingsSeen: Set<String> = []
}

/// A saved in-progress week. `contentVersion` lets us drop saves made with
/// incompatible content after an update instead of crashing on them.
private struct SavedGame: Codable {
    var contentVersion: Int
    var state: GameState
}

/// App state: owns the engine, drives screen flow and persistence.
/// All rules live in BedtimeCore; this type only orchestrates.
@MainActor
@Observable
final class GameStore {
    enum Screen: Equatable {
        case title
        case morning
        case event
        case outcome(StepResult)
        case lifeline
        case ending
    }

    let content: GameContent?
    let loadError: String?
    private(set) var engine: GameEngine?
    private(set) var screen: Screen = .title
    private(set) var stats: PlayerStats
    private(set) var hasSavedGame: Bool
    /// Names filled into the text. Set on the title screen before the first week.
    private(set) var household: Household
    /// Panic cards count down unless this is off (VoiceOver also turns them off).
    private(set) var timersEnabled: Bool
    /// Playtest: show the 😂/😴 buttons on outcomes and log the taps.
    private(set) var reactionsEnabled: Bool
    private(set) var reactions: [Reaction]

    private let defaults: UserDefaults
    private static let saveKey = "bedtime.savedWeek.v2"
    private static let statsKey = "bedtime.stats.v2"
    private static let householdKey = "bedtime.household.v1"
    private static let timersKey = "bedtime.timers.v1"
    private static let reactionsEnabledKey = "bedtime.reactionsEnabled.v1"
    private static let reactionsKey = "bedtime.reactions.v1"
    private static let maxReactions = 5000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            content = try GameContent.bundled()
            loadError = nil
        } catch {
            content = nil
            loadError = String(describing: error)
        }
        if let data = defaults.data(forKey: Self.statsKey),
           let saved = try? JSONDecoder().decode(PlayerStats.self, from: data) {
            stats = saved
        } else {
            stats = PlayerStats()
        }
        hasSavedGame = defaults.data(forKey: Self.saveKey) != nil
        household = defaults.data(forKey: Self.householdKey)
            .flatMap { try? JSONDecoder().decode(Household.self, from: $0) } ?? Household()
        timersEnabled = defaults.object(forKey: Self.timersKey) as? Bool ?? true
        reactionsEnabled = defaults.object(forKey: Self.reactionsEnabledKey) as? Bool ?? true
        reactions = defaults.data(forKey: Self.reactionsKey)
            .flatMap { try? JSONDecoder().decode([Reaction].self, from: $0) } ?? []
    }

    // MARK: - Names and settings

    /// Content text with the household's names filled in.
    func say(_ text: String) -> String { household.fill(text) }

    func setHousehold(_ newValue: Household) {
        household = newValue.cleaned()
        if let data = try? JSONEncoder().encode(household) { defaults.set(data, forKey: Self.householdKey) }
    }

    func setTimersEnabled(_ on: Bool) {
        timersEnabled = on
        defaults.set(on, forKey: Self.timersKey)
    }

    func setReactionsEnabled(_ on: Bool) {
        reactionsEnabled = on
        defaults.set(on, forKey: Self.reactionsEnabledKey)
    }

    // MARK: - Playtest reactions

    /// The reaction already given to this outcome, if any.
    func reaction(forStep step: Int) -> Reaction.Kind? {
        reactions.last(where: { $0.step == step })?.kind
    }

    /// Tapping the same reaction again removes it; the other one replaces it.
    func react(_ kind: Reaction.Kind, to result: StepResult) {
        guard let engine else { return }
        let step = engine.state.step
        let previous = reaction(forStep: step)
        reactions.removeAll { $0.step == step }
        if previous != kind {
            let title = engine.event(withID: result.eventID).map { say($0.title) } ?? result.eventID
            reactions.append(Reaction(at: Date(), day: engine.state.day, step: step, card: result.eventID, title: title,
                                      choice: result.choiceIndex, outcome: result.outcomeIndex, kind: kind))
            if reactions.count > Self.maxReactions { reactions.removeFirst(reactions.count - Self.maxReactions) }
        }
        if let data = try? JSONEncoder().encode(reactions) { defaults.set(data, forKey: Self.reactionsKey) }
    }

    func clearReactions() {
        reactions = []
        defaults.removeObject(forKey: Self.reactionsKey)
    }

    /// One row per tap, for the playtest: which cards landed and which dragged.
    func reactionsCSV() -> String {
        let iso = ISO8601DateFormatter()
        let rows = reactions.map { r in
            [iso.string(from: r.at), "\(r.day)", r.card.csvCell, r.title.csvCell, "\(r.choice)", "\(r.outcome)", r.kind.rawValue]
                .joined(separator: ",")
        }
        return (["time,day,card,title,choice,outcome,reaction"] + rows).joined(separator: "\n")
    }

    // MARK: - Flow

    func newWeek(seed: UInt32 = .random(in: .min ... .max)) {
        guard let content else { return }
        engine = GameEngine(content: content, seed: seed)
        screen = .morning
        save()
    }

    func resume() {
        guard let content,
              let data = defaults.data(forKey: Self.saveKey),
              let saved = try? JSONDecoder().decode(SavedGame.self, from: data),
              saved.contentVersion == content.version
        else {
            discardSave()
            newWeek()
            return
        }
        let restored = GameEngine(content: content, restoring: saved.state)
        guard restored.isOver || restored.currentEvent != nil else {
            discardSave()
            newWeek()
            return
        }
        engine = restored
        screen = restored.isOver ? .ending : .event
    }

    func startDay() {
        screen = .event
    }

    func choose(_ index: Int) {
        guard var current = engine else { return }
        guard let result = try? current.choose(index) else { return }
        engine = current
        screen = .outcome(result)
        if current.isOver { record(current) }
        save()
    }

    func continueAfterOutcome() {
        guard let engine, case .outcome(let result) = screen else { return }
        if engine.isOver {
            screen = .ending
        } else if result.transition == .lifeline {
            screen = .lifeline
        } else if result.transition == .morning {
            screen = .morning
        } else {
            screen = .event
        }
    }

    func continueAfterLifeline() {
        screen = .event
    }

    func backToTitle() {
        screen = .title
    }

    // MARK: - Sharing

    func shareText() -> String {
        guard let engine, let ending = engine.ending else { return "Bedtime or Bust" }
        let m = engine.state.meters
        let verdict = ending.kind == .win ? "made it to date night" : "didn't make it to date night"
        let style = engine.style?.title ?? ""
        return """
        I \(verdict) in Bedtime or Bust: "\(say(ending.title))". My style: \(say(style)).
        Energy \(m.energy) · Relationship \(m.rel) · House \(m.home) · Reputation \(m.rep)
        """
    }

    // MARK: - Persistence

    private func record(_ finished: GameEngine) {
        stats.weeksPlayed += 1
        if finished.ending?.kind == .win {
            stats.weeksWon += 1
            stats.bestScore = max(stats.bestScore, finished.score)
        }
        if let id = finished.state.endingID { stats.endingsSeen.insert(id) }
        if let data = try? JSONEncoder().encode(stats) { defaults.set(data, forKey: Self.statsKey) }
    }

    private func save() {
        guard let engine else { return }
        if engine.isOver {
            discardSave()
            return
        }
        let saved = SavedGame(contentVersion: engine.content.version, state: engine.state)
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.saveKey)
            hasSavedGame = true
        }
    }

    private func discardSave() {
        defaults.removeObject(forKey: Self.saveKey)
        hasSavedGame = false
    }
}
