import XCTest
import UIKit

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
        verifyDragLayout(language:"en")
    }
    @MainActor func testRussianHintsKeepTheBoardInPlace() {
        verifyDragLayout(language:"ru")
    }
    @MainActor private func verifyDragLayout(language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting","--training","-AppleLanguages","(\(language))"]
        app.launch()
        let idleHint = language == "ru"
            ? "Поверни платформу движением пальца."
            : "Drag a platform to rotate it."
        let selectedHint = language == "ru" ? "Платформа повёрнута. Ждём ход соперника." : "Platform rotated. Waiting for the opponent’s move."
        let limitHint = language == "ru" ? "Можно повернуть платформу только один раз за раунд" : "You can rotate a platform only once per round."
        let next = app.buttons["game.next"]
        XCTAssertTrue(next.waitForExistence(timeout:8))
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:next)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:8),.completed)
        for identifier in ["game.cw","game.ccw","game.skip"] { XCTAssertFalse(app.buttons[identifier].exists) }
        let platform = app.descendants(matching:.any)["platform.4"]
        let trackedPlatforms = [0,4,8].map { app.descendants(matching:.any)["platform.\($0)"] }
        let originalFrames = trackedPlatforms.map(\.frame)
        func assertBoardStaysInPlace(file: StaticString = #filePath, line: UInt = #line) {
            for (element,original) in zip(trackedPlatforms,originalFrames) {
                let frame = element.frame
                XCTAssertEqual(frame.minX,original.minX,accuracy:0.5,file:file,line:line)
                XCTAssertEqual(frame.minY,original.minY,accuracy:0.5,file:file,line:line)
                XCTAssertEqual(frame.width,original.width,accuracy:0.5,file:file,line:line)
                XCTAssertEqual(frame.height,original.height,accuracy:0.5,file:file,line:line)
            }
        }
        platform.tap()
        XCTAssertTrue(app.staticTexts[idleHint].exists)
        assertBoardStaysInPlace()
        let start = platform.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5))
        let end = platform.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.85))
        start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.staticTexts[selectedHint].waitForExistence(timeout:3))
        assertBoardStaysInPlace()
        for target in [platform,app.descendants(matching:.any)["platform.0"]] {
            target.tap()
            XCTAssertTrue(app.staticTexts[idleHint].exists)
            assertBoardStaysInPlace()
            start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
            XCTAssertTrue(app.staticTexts[selectedHint].waitForExistence(timeout:3))
            assertBoardStaysInPlace()
        }
        capture("drag-quarter-turn")
        start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.staticTexts[limitHint].waitForExistence(timeout:3))
        assertBoardStaysInPlace()
        capture("second-turn-hint")
        end.press(forDuration:0.05,thenDragTo:start,withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.staticTexts[idleHint].waitForExistence(timeout:3))
        XCTAssertFalse(app.staticTexts[limitHint].exists)
        assertBoardStaysInPlace()
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
        XCTAssertTrue(app.staticTexts["Platform rotated. Waiting for the opponent’s move."].exists)
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
        Thread.sleep(forTimeInterval:0.5)
        capture("05-menu-after-game")
        try assertNoGrayScenePlaceholder()
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
    @MainActor func testBoardRendersAfterRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting","--training","-AppleLanguages","(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["game.next"].waitForExistence(timeout:8))
        Thread.sleep(forTimeInterval:1)
        try assertNoGrayScenePlaceholder()
        for orientation in [UIDeviceOrientation.landscapeLeft,.portrait,.landscapeRight,.portrait] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval:1.5)
            capture("rotation-\(orientation.rawValue)")
            try assertNoGrayScenePlaceholder()
        }
    }
    @MainActor private func assertNoGrayScenePlaceholder() throws {
        let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating:0,count:width*height*4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data:bytes.baseAddress,width:width,height:height,
                bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        // A failed SpriteKit surface is a large, uniform light-gray rectangle.
        // Normal text/controls can have a few gray pixels, but not 1% of the screen.
        let grayPixels = stride(from:0,to:pixels.count,by:4).filter { index in
            let r = Int(pixels[index]), g = Int(pixels[index+1]), b = Int(pixels[index+2])
            return r >= 170 && abs(r-g) <= 1 && abs(r-b) <= 1
        }.count
        XCTAssertLessThan(Double(grayPixels)/Double(width*height),0.01,"The board must render instead of a blank SpriteKit surface")
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
