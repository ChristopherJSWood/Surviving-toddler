import XCTest
@testable import BedtimeCore

final class ContentTests: XCTestCase {
    func testBundledContentLoads() throws {
        let content = try GameContent.bundled()
        XCTAssertEqual(content.version, 2)
        XCTAssertEqual(content.days.count, 5)
        XCTAssertNotNil(content.filler)
        XCTAssertTrue(content.events.contains { $0.endsDay })
        XCTAssertTrue(content.events.contains { $0.endsWeek })
        XCTAssertTrue(content.events.contains { $0.phase == .night })
        XCTAssertTrue(content.events.contains { $0.hazard == .catastrophe })
        XCTAssertFalse(content.styles.isEmpty)
        for meter in Meter.allCases { XCTAssertFalse(content.name(of: meter).isEmpty) }
    }

    func testDeclaredCountersCoverEveryCounterUsed() throws {
        let content = try GameContent.bundled()
        let declared = Set(content.counters.map(\.id))
        for event in content.events {
            for choice in event.choices {
                for outcome in choice.outcomes {
                    for key in outcome.counters.keys {
                        XCTAssertTrue(declared.contains(key), "\(event.id) uses undeclared counter \(key)")
                    }
                }
            }
        }
    }

    func testUnknownMeterIsRejected() {
        let json = #"{ "text": "x", "effects": { "patience": 5 } }"#
        XCTAssertThrowsError(try JSONDecoder().decode(Outcome.self, from: Data(json.utf8)))
    }

    func testUnknownConditionVariableIsRejected() {
        let json = #"{ "min": { "vibes": 3 } }"#
        XCTAssertThrowsError(try JSONDecoder().decode(Condition.self, from: Data(json.utf8)))
    }

    func testDefaultsApplyWhenFieldsAreOmitted() throws {
        let json = #"{ "id": "e", "title": "T", "text": "X", "window": [360, 400], "choices": [ { "label": "L", "duration": 5, "outcomes": [ { "text": "O" } ] } ] }"#
        let event = try JSONDecoder().decode(GameEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.phase, .day)
        XCTAssertEqual(event.weight, 1)
        XCTAssertNil(event.priority)
        XCTAssertFalse(event.forced)
        XCTAssertNil(event.hazard)
        XCTAssertEqual(event.window, 360...400)
        XCTAssertEqual(event.choices[0].minEnergy, 0)
        XCTAssertFalse(event.choices[0].snapRisk)
        XCTAssertTrue(event.choices[0].outcomes[0].schedule.isEmpty)
    }

    func testScheduleUsesInKey() throws {
        let json = #"{ "text": "x", "schedule": [ { "event": "screen_off", "in": 22 } ] }"#
        let outcome = try JSONDecoder().decode(Outcome.self, from: Data(json.utf8))
        XCTAssertEqual(outcome.schedule, [ScheduledEvent(event: "screen_off", delay: 22)])
    }

    func testContentWithoutFillerIsRejected() throws {
        let bundled = try XCTUnwrap(GameContent.bundledURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundled)) as? [String: Any])
        var events = try XCTUnwrap(object["events"] as? [[String: Any]])
        events.removeAll { ($0["filler"] as? Bool) == true }
        object["events"] = events
        let broken = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try GameContent.load(from: broken)) { error in
            XCTAssertEqual(error as? ContentError, .invalid("needs exactly one filler event"))
        }
    }
}
