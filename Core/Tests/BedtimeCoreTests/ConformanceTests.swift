import XCTest
@testable import BedtimeCore

/// Replays week traces recorded from the JavaScript reference engine
/// (tools/golden.mjs). Passing proves the Swift engine implements the same
/// rules, RNG draw order and content semantics, step for step.
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
            let seed: UInt32
            let steps: [Step]
            let finalState: Snapshot

            enum CodingKeys: String, CodingKey {
                case seed, steps
                case finalState = "final"
            }
        }

        let meters: [String]
        let rng: RNGSamples
        let clockFormat: [ClockCase]
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
        XCTAssertGreaterThanOrEqual(golden.traces.count, 10)
        for trace in golden.traces {
            try replay(trace, content: content)
        }
    }

    private func replay(_ trace: Golden.Trace, content: GameContent) throws {
        var engine = GameEngine(content: content, seed: trace.seed)
        for (i, expected) in trace.steps.enumerated() {
            let here = "seed \(trace.seed) step \(i)"
            guard let event = engine.currentEvent else {
                return XCTFail("\(here): Swift engine ended early")
            }
            guard event.id == expected.e else {
                return XCTFail("\(here): event \(event.id), reference \(expected.e)")
            }
            let visible = engine.visibleChoices()
            XCTAssertEqual(visible.count, expected.n, "\(here): visible choices")
            let unlocked = visible.indices.filter { !engine.isLocked(visible[$0]) }
            let pick = unlocked[(Int(trace.seed) + engine.state.step * 31) % unlocked.count]
            XCTAssertEqual(pick, expected.c, "\(here): policy pick")

            let result = try engine.choose(pick)
            XCTAssertEqual(result.outcomeIndex, expected.o, "\(here): outcome")
            XCTAssertEqual(result.snapped ? 1 : 0, expected.s, "\(here): snap")
            XCTAssertEqual(engine.state.day, expected.d, "\(here): day")
            XCTAssertEqual(engine.state.phase == .night ? 1 : 0, expected.p, "\(here): phase")
            XCTAssertEqual(engine.state.clock, expected.t, "\(here): clock")
            guard engine.state.meters.values == expected.m else {
                return XCTFail("\(here): meters \(engine.state.meters.values), reference \(expected.m)")
            }
        }

        let snap = trace.finalState
        let here = "seed \(trace.seed) final"
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
    }
}
