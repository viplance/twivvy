import XCTest
import AVFoundation
@testable import HamsterLab

final class LocalizationTests: XCTestCase {
    func testEveryLanguageHasCompleteBundledTextAndAllFourDecodablePrompts() throws {
        let english = try strings("en")
        for language in NarrationCatalog.supportedLanguages {
            let localized = try strings(language)
            XCTAssertEqual(Set(localized.keys), Set(english.keys), language)
            for (key, value) in localized {
                XCTAssertFalse(value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, "\(language)/\(key)")
            }
            XCTAssertTrue(try XCTUnwrap(localized["native.selected"]).contains("{platform}"))
            for prompt in NarrationPrompt.allCases {
                let text = NarrationCatalog.text(for:prompt,language:language)
                XCTAssertEqual(text,localized[prompt.key])
                XCTAssertNotEqual(text,prompt.key)
                if language != "en" { XCTAssertNotEqual(text,english[prompt.key],language) }
                let url = try XCTUnwrap(NarrationCatalog.audioURL(for:prompt,language:language))
                XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent,"\(language).lproj")
                let player = try AVAudioPlayer(contentsOf:url)
                XCTAssertGreaterThan(player.duration,0.2,"\(language)/\(prompt)")
                XCTAssertTrue(player.prepareToPlay())
            }
        }
    }
    func testRegionNormalizationAndVoiceSelectionNeverSubstituteAnotherLanguage() {
        XCTAssertEqual(NarrationCatalog.language(for:"de_DE"),"de")
        XCTAssertEqual(NarrationCatalog.language(for:"pt-BR"),"pt")
        XCTAssertEqual(NarrationCatalog.language(for:"be-BY"),"be")
        XCTAssertEqual(NarrationCatalog.language(for:"ja-JP"),"en")
        XCTAssertNil(NarrationCatalog.preferredVoiceLanguage(for:"be",available:["ru-RU","en-US"]))
        XCTAssertNil(NarrationCatalog.preferredVoiceLanguage(for:"en",available:["ar-SA"]))
        XCTAssertEqual(NarrationCatalog.preferredVoiceLanguage(for:"pt",available:["pt-BR","pt-PT"]),"pt-PT")
        XCTAssertEqual(NarrationCatalog.preferredVoiceLanguage(for:"en",available:["en-GB"]),"en-GB")
        XCTAssertEqual(NarrationCatalog.preferredVoiceLanguage(for:"be",available:["ru-RU","be-BY"]),"be-BY")
    }
    private func strings(_ language: String) throws -> [String:String] {
        let bundle = try XCTUnwrap(NarrationCatalog.localizedBundle(for:language))
        let url = try XCTUnwrap(bundle.url(forResource:"Localizable",withExtension:"strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil) as? [String:String])
    }
}
