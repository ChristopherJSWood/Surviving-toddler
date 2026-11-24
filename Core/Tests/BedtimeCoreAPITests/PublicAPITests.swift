import BedtimeCore // deliberately NOT @testable: this file sees what the app sees
import Foundation
import XCTest

// The other test targets use `@testable import`, which can reach internal
// symbols the iOS app can't. This target touches every BedtimeCore type,
// member and conformance the app uses (App/*.swift), the way the app uses it,
// so a missing `public` fails on Linux CI instead of in Xcode.

private struct ProbeSave: Codable { var contentVersion: Int; var state: GameState } // GameStore: SavedGame
private enum ProbeScreen: Equatable { case title, outcome(StepResult) } // GameStore: Screen

extension Meter { // Theme.swift: exhaustive switch from outside the module
    fileprivate var probeSymbol: String {
        switch self {
        case .energy: return "e"
        case .rel: return "r"
        case .mood: return "m"
        case .sleepy: return "s"
        case .debt: return "d"
        case .home: return "h"
        case .rep: return "p"
        }
    }
}

extension GameContent { // Theme.swift: eyebrow(for:)
    fileprivate func probeEyebrow(for event: GameEvent) -> String? {
        if event.phase == .night { return "night" }
        if event.hazard == .catastrophe || event.hazard == .sting { return "hazard" }
        if event.moment { return "moment" }
        if events.contains(where: { $0.tell == event.id }) { return "tell" }
        if tasks.contains(where: { $0.expire == event.id }) { return "task" }
        if event.forced, !event.endsWeek { return "payback" }
        return nil
    }
}

private func needsEquatable<T: Equatable>(_: T.Type) {}
private func needsHashable<T: Hashable>(_: T.Type) {}
private func needsCodable<T: Codable>(_: T.Type) {}
private func needsIdentifiable<T: Identifiable>(_: [T]) {}

final class PublicAPITests: XCTestCase {
    func testEverythingTheAppUsesIsPublic() throws {
        needsEquatable(StepResult.self)
        needsEquatable(DayTransition.self)
        needsEquatable(Phase.self)
        needsEquatable(HazardSeverity.self)
        needsEquatable(Ending.Kind.self)
        needsEquatable(TaskState.Status.self)
        needsHashable(Meter.self)
        needsCodable(GameState.self)
        let zero: [Meter: Int] = Dictionary(uniqueKeysWithValues: Meter.allCases.map { ($0, 0) })
        XCTAssertEqual(zero.count, 7)
        XCTAssertEqual(Meter.allCases.map(\.probeSymbol).count, 7)

        let content = try GameContent.bundled()
        _ = (content.version, content.config.bedtime.threshold, content.name(of: .energy))
        _ = (content.lifeline.title, content.lifeline.text, content.lifeline.effects)
        needsIdentifiable(content.counters)
        needsIdentifiable(content.tasks)
        for c in content.counters { _ = (c.id, c.label) }
        for d in content.days { _ = (d.name, d.tasks) }
        for t in content.tasks { _ = content.task(withID: t.id).map { ($0.label, $0.dueDay, $0.expire) } }
        for e in content.events { _ = (content.probeEyebrow(for: e), e.title, e.text) }

        let seed: UInt32 = 7 // the app draws a random UInt32 (GameStore.newWeek)
        var engine = GameEngine(content: content, seed: seed)
        _ = (engine.isOver, engine.score, engine.dayDefinition.name, engine.content.version)
        _ = engine.modifier.map { ($0.title, $0.text, $0.effects.isEmpty) }
        _ = engine.style.map { ($0.title, $0.text) }
        _ = engine.ending.map { ($0.kind == .win, $0.title, $0.text) }
        for item in engine.upcoming.prefix(2) { _ = (item.event.title, Clock.format(item.at % 1440)) }

        let s = engine.state
        let m = s.meters
        _ = (m.energy, m.rel, m.mood, m.sleepy, m.debt, m.home, m.rep, m[.energy])
        _ = (Clock.format(s.clock), s.step, s.lostDays, s.endingID, s.phase == .night)
        _ = (s.counters["x"] ?? 0, s.ledgerYou["night"] ?? 0, s.ledgerPartner.values.reduce(0, +))
        for t in s.tasks { _ = (t.id, t.due % 1440, t.status == .open, t.status == .done, t.status == .expired) }
        if let r = s.report { _ = (r.nightYou, r.nightPartner, r.refill, r.debtBefore, r.debtAfter, r.partnerDid) }

        let event = try XCTUnwrap(engine.currentEvent)
        _ = engine.event(withID: event.id)?.title
        _ = engine.visibleChoices()
        let choices = engine.visibleChoices(for: event)
        for c in choices { _ = (c.label, c.duration, c.minEnergy, engine.isLocked(c)) }
        let index = try XCTUnwrap(choices.firstIndex { !engine.isLocked($0) })
        let result = try engine.choose(index)
        _ = (result.eventID, result.snapped, result.text, result.deltas[.energy], result.minutes, result.endingID)
        switch result.transition {
        case .night, .lifeline, .morning, .none: break
        }
        XCTAssertEqual(ProbeScreen.outcome(result), .outcome(result))

        // Save and resume, as GameStore does.
        let data = try JSONEncoder().encode(ProbeSave(contentVersion: content.version, state: engine.state))
        let saved = try JSONDecoder().decode(ProbeSave.self, from: data)
        let restored = GameEngine(content: content, restoring: saved.state)
        XCTAssertTrue(restored.isOver || restored.currentEvent != nil)
        XCTAssertEqual(restored.state.step, engine.state.step)
    }
}
