import XCTest

final class TwivvyUITests: XCTestCase {
    @MainActor func testTrainingAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:10))
        capture("01-menu")
        app.buttons["menu.settings"].tap()
        XCTAssertTrue(app.switches["settings.sound"].waitForExistence(timeout:3))
        app.buttons["sheet.done"].tap()
        app.buttons["menu.training"].tap()
        XCTAssertTrue(app.buttons["setup.start"].waitForExistence(timeout:3))
        app.buttons["setup.start"].tap()
        let next = app.buttons["game.next"]
        XCTAssertTrue(next.waitForExistence(timeout:8))
        let enabled = NSPredicate(format:"enabled == true")
        expectation(for:enabled,evaluatedWith:next)
        waitForExpectations(timeout:8)
        let platform = app.buttons["platform.0"]
        XCTAssertTrue(platform.exists)
        platform.tap()
        XCTAssertTrue(app.buttons["game.cw"].isEnabled)
        app.buttons["game.cw"].tap()
        XCTAssertTrue(app.staticTexts["Platform 1 · your move is hidden"].exists)
        capture("02-game")
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 30"].waitForExistence(timeout:5))
        Thread.sleep(forTimeInterval:1.4)
        capture("02b-balls")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        capture("03-landscape")
        XCTAssertTrue(app.buttons["game.leave"].isHittable)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval:1.5)
        app.buttons["game.leave"].tap()
        let confirmation = app.buttons.matching(identifier:"Leave game").allElementsBoundByIndex
        XCTAssertGreaterThan(confirmation.count,1)
        confirmation.last!.tap()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:5))
    }
    @MainActor func testTrainingCompletesAndRematches() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting","--training","-AppleLanguages","(en)"]
        app.launch()
        for _ in 0..<30 {
            if app.buttons["game.rematch"].exists { break }
            let next = app.buttons["game.next"]
            XCTAssertTrue(next.waitForExistence(timeout:8))
            let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:next)
            XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:8),.completed)
            next.tap()
            // A real resolve animation must finish before another command is accepted.
            Thread.sleep(forTimeInterval:1.35)
        }
        XCTAssertTrue(app.buttons["game.rematch"].waitForExistence(timeout:8))
        capture("04-result")
        app.buttons["game.rematch"].tap()
        XCTAssertTrue(app.staticTexts["1 / 30"].waitForExistence(timeout:8))
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
