import XCTest
@testable import BedtimeCore

final class EngineTests: XCTestCase {
    private var content: GameContent!

    override func setUpWithError() throws {
        content = try GameContent.bundled()
    }

    /// Plays a whole week, picking unlocked choices with a separate seeded RNG.
    @discardableResult
    private func playWeek(seed: UInt32, maxSteps: Int = 1000) throws -> GameEngine {
        var engine = GameEngine(content: content, seed: seed)
        var picker = SeededRandom(seed: seed ^ 0x9E37_79B9)
        var steps = 0
        while !engine.isOver {
            steps += 1
            XCTAssertLessThan(steps, maxSteps, "seed \(seed): week never ended")
            if steps >= maxSteps { break }
            let visible = engine.visibleChoices()
            let unlocked = visible.indices.filter { !engine.isLocked(visible[$0]) }
            XCTAssertFalse(unlocked.isEmpty, "seed \(seed): \(engine.currentEvent?.id ?? "nil") has no available choice")
            try engine.choose(unlocked[Int(picker.next() * Double(unlocked.count))])
        }
        return engine
    }

    func testKnownFirstValueOfMulberry32() {
        var rng = SeededRandom(seed: 0)
        XCTAssertEqual(rng.next(), 0.26642920868471265, accuracy: 1e-15)
    }

    func testMetersClampOnEveryWrite() {
        var meters = Meters(energy: 150, rel: -20, mood: 50, sleepy: 0, debt: 0)
        XCTAssertEqual(meters.energy, 100)
        XCTAssertEqual(meters.rel, 0)
        meters[.mood] += 500
        meters[.debt] -= 500
        XCTAssertEqual(meters.mood, 100)
        XCTAssertEqual(meters.debt, 0)
        XCTAssertEqual(meters.rested, 100)
    }

    func testWeekStartsMondayMorning() {
        let engine = GameEngine(content: content, seed: 1)
        XCTAssertEqual(engine.state.day, 0)
        XCTAssertEqual(engine.state.phase, .day)
        XCTAssertEqual(engine.state.clock, content.config.wake[engine.debtBand])
        XCTAssertNotNil(engine.currentEvent)
        XCTAssertEqual(engine.modifier?.id, content.days[0].modifier)
        XCTAssertFalse(engine.state.tasks.isEmpty, "Monday adds mental-load tasks")
    }

    func testSameSeedAndChoicesGiveSameWeek() throws {
        let a = try playWeek(seed: 777)
        let b = try playWeek(seed: 777)
        XCTAssertEqual(a.state, b.state)
    }

    func testEveryWeekTerminatesWithAKnownEnding() throws {
        for seed in UInt32(0)..<150 {
            let engine = try playWeek(seed: seed &* 2_654_435_761)
            let id = try XCTUnwrap(engine.state.endingID)
            XCTAssertNotNil(content.endings[id], "unknown ending \(id)")
            for meter in Meter.allCases {
                XCTAssertTrue(Meters.range.contains(engine.state.meters[meter]))
            }
        }
    }

    func testLockedChoiceCannotBeChosen() throws {
        for seed in UInt32(0)..<200 {
            var engine = GameEngine(content: content, seed: seed)
            var picker = SeededRandom(seed: seed)
            var guardSteps = 0
            while !engine.isOver, guardSteps < 1000 {
                guardSteps += 1
                let visible = engine.visibleChoices()
                if let locked = visible.indices.first(where: { engine.isLocked(visible[$0]) }) {
                    let before = engine.state
                    XCTAssertThrowsError(try engine.choose(locked)) { error in
                        XCTAssertEqual(error as? GameError, .lockedChoice(locked))
                    }
                    XCTAssertEqual(engine.state, before)
                    return
                }
                let unlocked = visible.indices.filter { !engine.isLocked(visible[$0]) }
                try engine.choose(unlocked[Int(picker.next() * Double(unlocked.count))])
            }
        }
        XCTFail("no locked choice appeared in 200 weeks; the Energy gate is untested")
    }

    func testInvalidChoiceThrowsAndChangesNothing() {
        var engine = GameEngine(content: content, seed: 3)
        let before = engine.state
        XCTAssertThrowsError(try engine.choose(99)) { error in
            XCTAssertEqual(error as? GameError, .invalidChoice(99))
        }
        XCTAssertEqual(engine.state, before)
    }

    func testChoosingAfterTheEndThrows() throws {
        var engine = try playWeek(seed: 5)
        XCTAssertThrowsError(try engine.choose(0)) { error in
            XCTAssertEqual(error as? GameError, .gameOver)
        }
    }

    func testSaveAndRestoreContinuesIdentically() throws {
        var uninterrupted = GameEngine(content: content, seed: 2024)
        var interrupted = GameEngine(content: content, seed: 2024)
        var picker = SeededRandom(seed: 1)
        func nextPick(_ engine: GameEngine) -> Int {
            let visible = engine.visibleChoices()
            let unlocked = visible.indices.filter { !engine.isLocked(visible[$0]) }
            return unlocked[Int(picker.next() * Double(unlocked.count))]
        }
        for _ in 0..<40 where !uninterrupted.isOver {
            let i = nextPick(uninterrupted)
            try uninterrupted.choose(i)
            try interrupted.choose(i)
        }
        let saved = try JSONEncoder().encode(interrupted.state)
        var restored = GameEngine(content: content, restoring: try JSONDecoder().decode(GameState.self, from: saved))
        XCTAssertEqual(restored.state, uninterrupted.state)
        while !uninterrupted.isOver {
            let i = nextPick(uninterrupted)
            XCTAssertEqual(try uninterrupted.choose(i), try restored.choose(i))
        }
        XCTAssertEqual(restored.state, uninterrupted.state)
    }

    func testNightsAndMorningsHappen() throws {
        var sawNight = false
        var sawMorningReport = false
        for seed in UInt32(0)..<50 {
            var engine = GameEngine(content: content, seed: seed)
            var picker = SeededRandom(seed: seed)
            while !engine.isOver {
                let visible = engine.visibleChoices()
                let unlocked = visible.indices.filter { !engine.isLocked(visible[$0]) }
                let result = try engine.choose(unlocked[Int(picker.next() * Double(unlocked.count))])
                if engine.state.phase == .night { sawNight = true }
                if result.transition == .morning {
                    sawMorningReport = true
                    XCTAssertEqual(engine.state.report?.day, engine.state.day)
                }
            }
        }
        XCTAssertTrue(sawNight)
        XCTAssertTrue(sawMorningReport)
    }

    func testClockFormatting() {
        XCTAssertEqual(Clock.format(358), "5:58 AM")
        XCTAssertEqual(Clock.format(725), "12:05 PM")
        XCTAssertEqual(Clock.format(1170), "7:30 PM")
        XCTAssertEqual(Clock.format(-1), "11:59 PM")
    }
}
