import XCTest

/// Plays a whole week through the real UI, tapping the first choice that's
/// available. Fails on a crash or a stuck screen; saves screenshots of each
/// new kind of screen. Screenshots also go to $SCREENSHOT_DIR on the Mac when
/// it's set (xcodebuild passes TEST_RUNNER_SCREENSHOT_DIR through).
final class PlaythroughUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shots = Set<String>()
    private var cards = 0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-resetForUITests"]
        app.launch()
    }

    func testPlayAWeek() throws {
        tap("start")
        snap("01-names")
        type("Juno", into: "kid")
        type("Robin", into: "partner")
        app.buttons["Papa"].tap()
        tap("saveHousehold")

        for _ in 0..<600 {
            if app.buttons["tryAgain"].exists {
                sleep(2)
                snap("90-ending")
                print("PLAYTHROUGH: finished the week after \(cards) cards")
                return
            }
            if app.buttons["startDay"].exists {
                snap("02-morning")
                app.buttons["startDay"].tap()
                continue
            }
            if app.buttons["goToBed"].exists {
                snap("80-lifeline")
                app.buttons["goToBed"].tap()
                continue
            }
            if app.buttons["continue"].exists {
                outcomeShots()
                app.buttons["continue"].tap()
                continue
            }
            if app.buttons["choice-0"].waitForExistence(timeout: 8) {
                cards += 1
                cardShots()
                try chooseFirstAvailable()
                continue
            }
            if app.buttons["continue"].exists || app.buttons["tryAgain"].exists { continue }
            XCTFail("Stuck: no button to press after \(cards) cards")
            snap("99-stuck")
            return
        }
        XCTFail("The week didn't end within 600 screens")
    }

    // MARK: - Helpers

    private func chooseFirstAvailable() throws {
        // Chat cards reveal their buttons after the thread; give them time.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            for i in 0..<4 {
                let button = app.buttons["choice-\(i)"]
                if button.exists, button.isEnabled, button.isHittable {
                    button.tap()
                    return
                }
            }
            // A panic card may have timed out and moved on by itself.
            if app.buttons["continue"].exists { return }
            usleep(200_000)
        }
        XCTFail("No choice became available on card \(cards)")
    }

    /// Any element whose accessibility label matches (stamps, countdown and
    /// lights-out combine their children into one label).
    private func labeled(_ format: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch.exists
    }

    private func cardShots() {
        if labeled("label ENDSWITH 'seconds to decide'") { snap("10-panic") }
        else if cards == 1 { snap("03-first-card") }
        else if cards == 12 { snap("04-card-12") }
    }

    private func outcomeShots() {
        sleep(1) // let the stamp land
        if labeled("label == 'Lights out'") { snap("20-lights-out") }
        else if labeled("label BEGINSWITH 'Verdict:'") { snap("05-stamp") }
        else if cards == 3 { snap("06-outcome") }
    }

    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "missing button \(id)")
        button.tap()
    }

    private func type(_ text: String, into id: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "missing field \(id)")
        field.tap()
        field.typeText(text)
    }

    /// One screenshot per name: attached to the test, and written to disk if asked.
    private func snap(_ name: String) {
        guard !shots.contains(name) else { return }
        shots.insert(name)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
