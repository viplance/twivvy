import XCTest
@testable import Twivvy

final class LocalizationTests: XCTestCase {
    func testEveryLanguageHasCompleteBundledTranslations() throws {
        let languages = ["en","be","es","ru","uk","it","pt","pl","fr","de","tr"]
        let english = try strings("en")
        for language in languages {
            let localized = try strings(language)
            XCTAssertEqual(Set(localized.keys), Set(english.keys), language)
            for (key, value) in localized {
                XCTAssertFalse(value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, "\(language)/\(key)")
            }
            let seconds = try XCTUnwrap(localized["native.seconds"])
            XCTAssertTrue(seconds.contains("{seconds}"), language)
            if language != "en" {
                for key in ["native.privacyText","status.storageUnavailable","status.startupFailed","error.oldVersion","error.occupied","error.connectFailed"] {
                    XCTAssertNotEqual(localized[key], english[key], "\(language)/\(key)")
                }
            }
        }
    }
    private func strings(_ language: String) throws -> [String:String] {
        let app = Bundle(for:GameModel.self)
        let folder = try XCTUnwrap(app.url(forResource:language,withExtension:"lproj"))
        let bundle = try XCTUnwrap(Bundle(url:folder))
        let url = try XCTUnwrap(bundle.url(forResource:"Localizable",withExtension:"strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil) as? [String:String])
    }
}
