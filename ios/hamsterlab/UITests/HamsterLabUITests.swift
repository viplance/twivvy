import XCTest
import UIKit

final class HamsterLabUITests: XCTestCase {
    @MainActor func testTrainingControlsAndBoardFitWithoutScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--training", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        XCTAssertTrue(app.buttons["game.next"].waitForExistence(timeout:20))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            waitUntilReady(app)
            let next = app.buttons["game.next"]
            let timer = app.descendants(matching:.any)["game.timer"]
            XCTAssertTrue(next.isHittable)
            XCTAssertTrue(app.frame.contains(next.frame), "Next round must fit without scrolling")
            XCTAssertTrue(app.frame.contains(timer.frame))
            for index in [0,2,6,8] {
                let tile = app.descendants(matching:.any)["platform.\(index)"]
                XCTAssertTrue(tile.isHittable)
                XCTAssertTrue(app.frame.contains(tile.frame), "Corner platform \(index) must fit")
                if orientation == .portrait {
                    XCTAssertGreaterThanOrEqual(tile.frame.minY, timer.frame.maxY)
                    XCTAssertLessThanOrEqual(tile.frame.maxY, next.frame.minY)
                }
            }
            assertBoardRendered(app)
            capture(orientation == .portrait ? "training-fit-portrait" : "training-fit-landscape")
        }
    }
    @MainActor func testTrainingMissingNameFocusesVisibleField() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--empty-name", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:20))
        app.buttons["menu.training"].tap()
        let hard = app.buttons["setup.difficulty.hard"]
        XCTAssertTrue(hard.waitForExistence(timeout:5))
        hard.tap()
        let start = app.buttons["setup.start"]
        if !start.isHittable { app.swipeUp() }
        start.tap()
        let field = app.textFields["setup.name"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(field.isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture("training-empty-name-visible")
        field.typeText("Mila\n")
        XCTAssertEqual(field.value as? String, "Mila")
        XCTAssertFalse(app.staticTexts["setup.name.error"].exists)
        if !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["game.next"].waitForExistence(timeout:20))
    }
    @MainActor func testArabicPersianLayoutAndSettings() {
        let cases = [
            ("ar", "ساعد الهامسترات في العثور على طريق العودة إلى البيت!", "الجولة التالية", "الموسيقى", "أصوات الهامستر"),
            ("fa", "به همسترها کمک کن راه خانه را پیدا کنند!", "دور بعدی", "موسیقی", "صدای همسترها")
        ]
        for (language, slogan, next, music, voices) in cases {
            let app=XCUIApplication()
            app.launchArguments=["--uitesting","-AppleLanguages","(\(language))"]
            app.launch()
            XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:20),language)
            XCTAssertTrue(app.staticTexts[slogan].isHittable,language)
            capture("rtl-menu-\(language)")
            app.terminate()
            app.launchArguments.insert("--training",at:1)
            app.launch()
            let button=app.buttons["game.next"]
            XCTAssertTrue(button.waitForExistence(timeout:20),language)
            XCTAssertTrue(button.isHittable,language)
            XCTAssertEqual(button.label,next,language)
            for p in [0,2,6,8] {
                let platform=app.descendants(matching:.any)["platform.\(p)"]
                XCTAssertTrue(platform.isHittable,language)
                XCTAssertTrue(app.frame.contains(platform.frame),language)
            }
            capture("rtl-training-\(language)")
            app.buttons["menu.settings"].tap()
            let toggle=app.switches["settings.sound"]
            XCTAssertTrue(toggle.waitForExistence(timeout:5),language)
            XCTAssertEqual(toggle.label,music,language)
            XCTAssertEqual(app.switches["settings.voices"].label,voices,language)
            capture("rtl-settings-\(language)")
            app.terminate()
        }
    }
    @MainActor func testChineseJapaneseHindiTrainingAndSettings() {
        let cases = [
            ("zh-Hans", "下一回合", "音乐", "仓鼠叫声"),
            ("ja", "次のラウンド", "音楽", "ハムスターの声"),
            ("hi", "अगला दौर", "संगीत", "हैम्स्टर की आवाज़ें")
        ]
        for (language, next, music, voices) in cases {
            let app=XCUIApplication()
            app.launchArguments=["--uitesting","--training","-AppleLanguages","(\(language))"]
            app.launch()
            let button=app.buttons["game.next"]
            XCTAssertTrue(button.waitForExistence(timeout:20),language)
            XCTAssertTrue(button.isHittable,language)
            XCTAssertEqual(button.label,next,language)
            capture("training-\(language)")
            app.buttons["menu.settings"].tap()
            let toggle=app.switches["settings.sound"]
            XCTAssertTrue(toggle.waitForExistence(timeout:5),language)
            XCTAssertEqual(toggle.label,music,language)
            XCTAssertEqual(app.switches["settings.voices"].label,voices,language)
            capture("settings-\(language)")
            app.terminate()
        }
    }
    @MainActor func testMusicLabelInEveryLanguage() {
        let labels=[("en","Music"),("be","Музыка"),("es","Música"),("ru","Музыка"),
                    ("uk","Музика"),("it","Musica"),("pt","Música"),("pl","Muzyka"),
                    ("fr","Musique"),("de","Musik"),("tr","Müzik"),
                    ("zh-Hans","音乐"),("ja","音楽"),("hi","संगीत"),
                    ("ar","الموسيقى"),("fa","موسیقی")]
        for (language,label) in labels {
            let app=XCUIApplication()
            app.launchArguments=["--uitesting","-AppleLanguages","(\(language))"]
            app.launch()
            XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout:20),language)
            app.buttons["menu.settings"].tap()
            let toggle=app.switches["settings.sound"]
            XCTAssertTrue(toggle.waitForExistence(timeout:5),language)
            XCTAssertEqual(toggle.label,label,language)
            XCTAssertTrue(app.switches["settings.voices"].exists,language)
            app.terminate()
        }
    }
    @MainActor func testIllustratedDifficultySelection() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","-AppleLanguages","(ru)","-AppleLocale","ru_RU"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:20))
        app.buttons["menu.training"].tap()
        let easy=app.buttons["setup.difficulty.easy"], hard=app.buttons["setup.difficulty.hard"]
        XCTAssertTrue(easy.waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["setup.difficulty.medium"].isHittable)
        hard.tap()
        XCTAssertTrue(hard.isSelected)
        XCTAssertTrue(app.segmentedControls["setup.difficulty"].buttons["Сложно"].isSelected)
        capture("difficulty-hard")
        app.segmentedControls["setup.difficulty"].buttons["Легко"].tap()
        XCTAssertTrue(easy.isSelected)
        XCTAssertFalse(hard.isSelected)
        capture("difficulty-easy")
        app.buttons["setup.start"].tap()
        XCTAssertTrue(app.buttons["game.next"].waitForExistence(timeout:20))
    }
    @MainActor func testDeliveredHamstersRunAndSitInTheHomes() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--home-arrival","-AppleLanguages","(ru)","-AppleLocale","ru_RU"]
        app.launch()
        XCTAssertTrue(app.buttons["game.next"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["4 / 30"].waitForExistence(timeout:5))
        capture("home-arrival-start")
        Thread.sleep(forTimeInterval:1.3)
        capture("home-arrival-running")
        Thread.sleep(forTimeInterval:1.8)
        assertBoardRendered(app)
        capture("home-arrival-seated")
    }
    @MainActor func testMenuSettingsAndRussianBrand() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","-AppleLanguages","(ru)","-AppleLocale","ru_RU"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["ХомаЛаб"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Помоги хомячкам найти дорогу домой!"].exists)
        capture("01-menu-ru")
        app.buttons["menu.settings"].tap()
        XCTAssertTrue(app.switches["settings.sound"].waitForExistence(timeout:5))
        XCTAssertTrue(app.switches["settings.voices"].exists)
        app.buttons["sheet.done"].tap()
        XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:5))
    }
    @MainActor func testMenuSloganInEveryLanguage() {
        let slogans = [
            ("en", "Help the hamsters find their way home!"),
            ("be", "Дапамажы хамячкам знайсці дарогу дадому!"),
            ("es", "¡Ayuda a los hámsteres a encontrar el camino a casa!"),
            ("ru", "Помоги хомячкам найти дорогу домой!"),
            ("uk", "Допоможи хом’ячкам знайти дорогу додому!"),
            ("it", "Aiuta i criceti a trovare la strada di casa!"),
            ("pt", "Ajuda os hamsters a encontrar o caminho para casa!"),
            ("pl", "Pomóż chomikom znaleźć drogę do domu!"),
            ("fr", "Aide les hamsters à retrouver le chemin de leur maison !"),
            ("de", "Hilf den Hamstern, den Weg nach Hause zu finden!"),
            ("tr", "Hamsterların evlerinin yolunu bulmasına yardım et!"),
            ("zh-Hans", "帮仓鼠找到回家的路！"),
            ("ja", "ハムスターがおうちに帰るのを手伝おう！"),
            ("hi", "हैम्स्टर को घर का रास्ता खोजने में मदद करो!"),
            ("ar", "ساعد الهامسترات في العثور على طريق العودة إلى البيت!"),
            ("fa", "به همسترها کمک کن راه خانه را پیدا کنند!")
        ]
        for (language, slogan) in slogans {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting", "-AppleLanguages", "(\(language))"]
            app.launch()
            XCTAssertTrue(app.buttons["menu.training"].waitForExistence(timeout:20), language)
            let label = app.staticTexts[slogan]
            XCTAssertTrue(label.exists, language)
            XCTAssertTrue(label.isHittable, "Slogan must be visible: \(language)")
            capture("menu-slogan-\(language)")
            app.terminate()
        }
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
        XCTAssertTrue(app.staticTexts["Move made. Your twist stays secret until reveal!"].waitForExistence(timeout:5))
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
        XCTAssertTrue(rematch.waitForExistence(timeout:180))
        let title=app.staticTexts["game.result"], newGame=app.buttons["game.newGame"]
        let visible=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            rematch.isHittable && newGame.isHittable && title.isHittable && app.frame.contains(newGame.frame) && app.frame.contains(title.frame)
        },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[visible],timeout:5),.completed,"Results and both actions must be visible without a manual swipe")
        capture("06-result")
        rematch.tap()
        XCTAssertTrue(app.staticTexts["1 / 30"].waitForExistence(timeout:10))
    }
    @MainActor func testTranslatedTrainingAndVoiceSettings() {
        let cases = [
            ("be", "Павярні платформу рухам пальца. Праводзь хамякоў у свой домік унізе.", "Хамячыныя галасы"),
            ("de", "Ziehe an einer Plattform, um die Röhren zu drehen. Führe die Hamster in dein Häuschen unten.", "Hamsterstimmen"),
            ("tr", "Boruları döndürmek için bir platformu sürükle. Hamsterları aşağıdaki evine götür.", "Hamster sesleri")
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
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:app.buttons["game.next"])
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:20),.completed)
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
