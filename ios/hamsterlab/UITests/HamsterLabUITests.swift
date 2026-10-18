import XCTest
import UIKit

final class HamsterLabUITests: XCTestCase {
    @MainActor func testMenuSettingsAndRussianBrand() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","-AppleLanguages","(ru)","-AppleLocale","ru_RU"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["ХомаЛаб"].firstMatch.exists)
        capture("01-menu-ru")
        app.buttons["menu.settings"].tap()
        XCTAssertTrue(app.switches["settings.sound"].waitForExistence(timeout:5))
        XCTAssertTrue(app.switches["settings.voices"].exists)
        app.buttons["sheet.done"].tap()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:5))
    }
    @MainActor func testTrainingRotationRevealAndLandscape() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--training","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        let next=app.buttons["game.next"]
        XCTAssertTrue(next.waitForExistence(timeout:20))
        waitUntilReady(app)
        let platform=app.descendants(matching:.any)["platform.4"]
        XCTAssertTrue(platform.exists)
        let start=platform.coordinate(withNormalizedOffset:CGVector(dx:0.86,dy:0.5))
        let end=platform.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.87))
        start.press(forDuration:0.06,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.staticTexts["Platform 5 is ready. Your twist stays secret until reveal!"].waitForExistence(timeout:5))
        capture("02-private-twist")
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 30"].waitForExistence(timeout:5))
        waitUntilReady(app)
        assertBoardRendered(app)
        capture("03-hamsters-in-tubes")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(next.waitForExistence(timeout:5))
        assertBoardRendered(app)
        capture("04-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(next.waitForExistence(timeout:5))
        app.buttons["game.leave"].tap()
        let confirm=app.buttons.matching(identifier:"Leave game").allElementsBoundByIndex
        XCTAssertGreaterThan(confirm.count,1)
        confirm.last?.tap()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:8))
        capture("05-back-to-menu")
    }
    @MainActor func testJoinCodeValidationDoesNotContactServer() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","-AppleLanguages","(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.join"].waitForExistence(timeout:20))
        app.buttons["menu.join"].tap()
        XCTAssertTrue(app.buttons["setup.start"].waitForExistence(timeout:5))
        app.buttons["setup.start"].tap()
        XCTAssertTrue(app.staticTexts["setup.code.error"].waitForExistence(timeout:5))
        app.textFields["setup.code"].typeText("ABCD7")
        XCTAssertFalse(app.staticTexts["setup.code.error"].exists)
    }
    @MainActor func testThirtyRoundTrainingCanRematch() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--autoplay","-AppleLanguages","(en)"]
        app.launch()
        let rematch=app.buttons["game.rematch"]
        XCTAssertTrue(rematch.waitForExistence(timeout:180)); capture("06-result")
        rematch.tap()
        XCTAssertTrue(app.staticTexts["1 / 30"].waitForExistence(timeout:10))
    }
    @MainActor func testTranslatedTrainingAndVoiceSettings() {
        let cases = [
            ("be", "Павярні платформу рухам пальца. Праводзь хамякоў у свой домік унізе.", "Хамячыныя галасы і падказкі"),
            ("de", "Ziehe an einer Plattform, um die Röhren zu drehen. Führe die Hamster in dein Häuschen unten.", "Hamsterstimmen und Sprachhinweise"),
            ("tr", "Boruları döndürmek için bir platformu sürükle. Hamsterları aşağıdaki evine götür.", "Hamster sesleri ve sesli ipuçları")
        ]
        for (language, hint, voices) in cases {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting", "--training", "-AppleLanguages", "(\(language))"]
            app.launch()
            XCTAssertTrue(app.buttons["game.next"].waitForExistence(timeout:20), language)
            XCTAssertTrue(app.staticTexts[hint].waitForExistence(timeout:5), language)
            capture("localized-training-\(language)")
            app.buttons["menu.settings"].tap()
            let toggle = app.switches["settings.voices"]
            XCTAssertTrue(toggle.waitForExistence(timeout:5), language)
            XCTAssertEqual(toggle.label, voices)
            capture("localized-voices-\(language)")
            app.terminate()
        }
    }
    @MainActor private func waitUntilReady(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Time for a little twist!"].waitForExistence(timeout:20))
    }
    @MainActor private func capture(_ name: String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func assertBoardRendered(_ app: XCUIApplication) {
        // AX elements can remain present even when RealityKit loses its camera.
        // Verify actual pixels in the middle platform, in both orientations.
        let frame=app.descendants(matching:.any)["platform.4"].frame
        guard let screen=XCUIScreen.main.screenshot().image.cgImage,frame.width>0,frame.height>0 else {
            XCTFail("No board image or projected platform frame"); return
        }
        let sx=CGFloat(screen.width)/app.frame.width, sy=CGFloat(screen.height)/app.frame.height
        let rect=CGRect(x:(frame.minX-app.frame.minX)*sx,y:(frame.minY-app.frame.minY)*sy,width:frame.width*sx,height:frame.height*sy)
        guard let crop=screen.cropping(to:rect) else { XCTFail("Platform outside the screenshot"); return }
        var pixels=[UInt8](repeating:0,count:32*32*4)
        let drawn=pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:32,height:32,bitsPerComponent:8,bytesPerRow:32*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop,in:CGRect(x:0,y:0,width:32,height:32)); return true
        }
        XCTAssertTrue(drawn)
        var darkest=765, brightest=0
        for index in 0..<1024 {
            let offset=index*4
            let red=Int(pixels[offset]), green=Int(pixels[offset+1]), blue=Int(pixels[offset+2])
            let brightness=red+green+blue
            darkest=min(darkest,brightness); brightest=max(brightest,brightness)
        }
        XCTAssertGreaterThan(brightest-darkest,40,"The board must contain visible geometry, not a uniform empty render target")
    }
}
