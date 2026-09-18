import XCTest

final class TwivvyUITests: XCTestCase {
    @MainActor func testJoinHighlightsEmptyCodeAndClearsErrorWhenEditing() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.join"].waitForExistence(timeout:8))
        app.buttons["menu.join"].tap()
        let field = app.textFields["setup.code"]
        let error = app.staticTexts["setup.code.error"]
        XCTAssertTrue(field.waitForExistence(timeout:3))
        XCTAssertFalse(error.exists)
        app.buttons["setup.start"].tap()
        XCTAssertTrue(error.waitForExistence(timeout:3))
        XCTAssertTrue(field.exists)
        XCTAssertEqual(app.alerts.count,0)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:3))
        capture("join-empty-code")
        field.typeText("   ")
        app.buttons["setup.start"].tap()
        XCTAssertTrue(error.waitForExistence(timeout:3))
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:3) + "ABCD7")
        XCTAssertFalse(error.exists)
        // Validation stays local: do not submit a made-up room to the live server.
        app.buttons["sheet.done"].tap()
        XCTAssertTrue(app.buttons["menu.join"].waitForExistence(timeout:3))
    }
    @MainActor func testDragRotatesWithoutSelectingFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting","--training","-AppleLanguages","(en)"]
        app.launch()
        let next = app.buttons["game.next"]
        XCTAssertTrue(next.waitForExistence(timeout:8))
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:next)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:8),.completed)
        for identifier in ["game.cw","game.ccw","game.skip"] { XCTAssertFalse(app.buttons[identifier].exists) }
        let platform = app.descendants(matching:.any)["platform.4"]
        platform.tap()
        XCTAssertTrue(app.staticTexts["Drag a platform to rotate it. Tap any platform to reset your move."].exists)
        let start = platform.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5))
        let end = platform.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.85))
        start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.staticTexts["Platform 5 · your move is hidden"].waitForExistence(timeout:3))
        for target in [platform,app.descendants(matching:.any)["platform.0"]] {
            target.tap()
            XCTAssertTrue(app.staticTexts["Drag a platform to rotate it. Tap any platform to reset your move."].exists)
            start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
            XCTAssertTrue(app.staticTexts["Platform 5 · your move is hidden"].waitForExistence(timeout:3))
        }
        capture("drag-quarter-turn")
        start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.staticTexts["You can rotate a platform only once per round."].waitForExistence(timeout:3))
        capture("second-turn-hint")
        end.press(forDuration:0.05,thenDragTo:start,withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.staticTexts["Drag a platform to rotate it. Tap any platform to reset your move."].waitForExistence(timeout:3))
        XCTAssertFalse(app.staticTexts["You can rotate a platform only once per round."].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 30"].waitForExistence(timeout:5))
    }
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
        let platform = app.descendants(matching:.any)["platform.0"]
        XCTAssertTrue(platform.exists)
        let start = platform.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5))
        let end = platform.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.85))
        start.press(forDuration:0.05,thenDragTo:end)
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
