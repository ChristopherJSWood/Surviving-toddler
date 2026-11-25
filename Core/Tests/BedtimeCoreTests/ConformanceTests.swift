import XCTest
@testable import BedtimeCore

/// Replays week traces recorded from the JavaScript reference engine
/// (tools/golden.mjs). Passing proves the Swift engine implements the same
/// rules, RNG draw order and content semantics, step for step, and the test
/// itself checks that the traces reach every card and every ending.
final class ConformanceTests: XCTestCase {
    struct Golden: Decodable {
        struct RNGSamples: Decodable {
            let seed0: [Double]
            let seedMax: [Double]
        }

        struct ClockCase: Decodable {
            let minutes: Int
            let text: String

            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                minutes = try c.decode(Int.self)
                text = try c.decode(String.self)
            }
        }

        struct Step: Decodable {
            let e: String
            let n: Int
            /// Bitmask of the unlocked visible choices.
            let u: Int
            let c: Int
            let o: Int
            let s: Int
            let d: Int
            let p: Int
            let t: Int
            let m: [Int]
        }

        struct Ledger: Decodable {
            let you: [String: Int]
            let partner: [String: Int]
        }

        struct Snapshot: Decodable {
            let day: Int
            let phase: String
            let clock: Int
            let meters: [String: Int]
            let flags: [String]
            let counters: [String: Int]
            let ledger: Ledger
            let tasks: [String]
            let step: Int
            let lostDays: Int
            let endingId: String?
        }

        struct Trace: Decodable {
            let policy: String
            let seed: UInt32
            let steps: [Step]
            let finalState: Snapshot

            enum CodingKeys: String, CodingKey {
                case policy, seed, steps
                case finalState = "final"
            }
        }

        let meters: [String]
        let rng: RNGSamples
        let clockFormat: [ClockCase]
        let minSnaps: Int
        let traces: [Trace]
    }

    private func loadGolden() throws -> Golden {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures"),
            "Fixtures/golden.json missing from the test bundle"
        )
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testMeterOrderMatchesReference() throws {
        XCTAssertEqual(try loadGolden().meters, Meter.allCases.map(\.rawValue))
    }

    func testRandomNumberGeneratorMatchesReference() throws {
        let golden = try loadGolden()
        var zero = SeededRandom(seed: 0)
        for expected in golden.rng.seed0 { XCTAssertEqual(zero.next(), expected, accuracy: 1e-15) }
        var top = SeededRandom(seed: .max)
        for expected in golden.rng.seedMax { XCTAssertEqual(top.next(), expected, accuracy: 1e-15) }
    }

    func testClockFormatMatchesReference() throws {
        for testCase in try loadGolden().clockFormat {
            XCTAssertEqual(Clock.format(testCase.minutes), testCase.text, "minutes \(testCase.minutes)")
        }
    }

    func testGoldenWeeksReplayIdentically() throws {
        let content = try GameContent.bundled()
        let golden = try loadGolden()
        XCTAssertGreaterThanOrEqual(golden.traces.count, 30)

        var cardsSeen = Set<String>()
        var endingsSeen = Set<String>()
        var snaps = 0
        for trace in golden.traces {
            let replayed = try replay(trace, content: content)
            cardsSeen.formUnion(replayed.cards)
            if let ending = replayed.ending { endingsSeen.insert(ending) }
            snaps += replayed.snaps
        }

        // Coverage is checked here, not trusted from the fixture: a truncated or
        // stale golden.json fails this test even if every step it holds matches.
        let allCards = Set(content.events.map(\.id))
        XCTAssertEqual(allCards.subtracting(cardsSeen).sorted(), [], "cards no trace reaches")
        XCTAssertEqual(Set(content.endings.keys).subtracting(endingsSeen).sorted(), [], "endings no trace reaches")
        XCTAssertGreaterThanOrEqual(snaps, golden.minSnaps, "snap outcomes replayed")
    }

    private func replay(_ trace: Golden.Trace, content: GameContent) throws -> (cards: Set<String>, ending: String?, snaps: Int) {
        var engine = GameEngine(content: content, seed: trace.seed)
        var cards = Set<String>()
        var snaps = 0
        for (i, expected) in trace.steps.enumerated() {
            let here = "\(trace.policy) seed \(trace.seed) step \(i)"
            guard let event = engine.currentEvent else {
                XCTFail("\(here): Swift engine ended early")
                return (cards, nil, snaps)
            }
            guard event.id == expected.e else {
                XCTFail("\(here): event \(event.id), reference \(expected.e)")
                return (cards, nil, snaps)
            }
            cards.insert(event.id)
            let visible = engine.visibleChoices()
            XCTAssertEqual(visible.count, expected.n, "\(here): visible choices")
            let mask = visible.indices.reduce(0) { engine.isLocked(visible[$1]) ? $0 : $0 | (1 << $1) }
            XCTAssertEqual(mask, expected.u, "\(here): unlocked choices")
            guard visible.indices.contains(expected.c), !engine.isLocked(visible[expected.c]) else {
                XCTFail("\(here): reference pick \(expected.c) is not an unlocked visible choice")
                return (cards, nil, snaps)
            }

            let result = try engine.choose(expected.c)
            if result.snapped { snaps += 1 }
            XCTAssertEqual(result.outcomeIndex, expected.o, "\(here): outcome")
            XCTAssertEqual(result.snapped ? 1 : 0, expected.s, "\(here): snap")
            XCTAssertEqual(engine.state.day, expected.d, "\(here): day")
            XCTAssertEqual(engine.state.phase == .night ? 1 : 0, expected.p, "\(here): phase")
            XCTAssertEqual(engine.state.clock, expected.t, "\(here): clock")
            guard engine.state.meters.values == expected.m else {
                XCTFail("\(here): meters \(engine.state.meters.values), reference \(expected.m)")
                return (cards, nil, snaps)
            }
        }

        let snap = trace.finalState
        let here = "\(trace.policy) seed \(trace.seed) final"
        XCTAssertTrue(engine.isOver, "\(here): reference ended, Swift did not")
        XCTAssertEqual(engine.state.endingID, snap.endingId, here)
        XCTAssertEqual(engine.state.day, snap.day, here)
        XCTAssertEqual(engine.state.phase.rawValue, snap.phase, here)
        XCTAssertEqual(engine.state.clock, snap.clock, here)
        XCTAssertEqual(engine.state.step, snap.step, here)
        XCTAssertEqual(engine.state.lostDays, snap.lostDays, here)
        XCTAssertEqual(engine.state.flags, Set(snap.flags), here)
        XCTAssertEqual(engine.state.counters, snap.counters, here)
        XCTAssertEqual(engine.state.ledgerYou, snap.ledger.you, here)
        XCTAssertEqual(engine.state.ledgerPartner, snap.ledger.partner, here)
        XCTAssertEqual(engine.state.tasks.map { "\($0.id):\($0.status.rawValue)" }, snap.tasks, here)
        for meter in Meter.allCases {
            XCTAssertEqual(engine.state.meters[meter], snap.meters[meter.rawValue], "\(here): \(meter)")
        }
        return (cards, engine.state.endingID, snaps)
    }
}
