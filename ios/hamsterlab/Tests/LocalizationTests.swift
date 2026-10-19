import XCTest
@testable import HamsterLab

final class LocalizationTests: XCTestCase {
    func testEveryLanguageHasCompleteBundledText() throws {
        let english = try strings("en")
        for language in ["en","be","es","ru","uk","it","pt","pl","fr","de","tr"] {
            let localized = try strings(language)
            XCTAssertEqual(Set(localized.keys), Set(english.keys), language)
            for (key, value) in localized {
                XCTAssertFalse(value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, "\(language)/\(key)")
            }
            XCTAssertFalse(try XCTUnwrap(localized["native.selected"]).contains("{platform}"), language)
            let tagline = try XCTUnwrap(localized["lab.tagline"])
            XCTAssertFalse(tagline.contains("\n"), language)
            XCTAssertNil(localized["tagline.first"], language)
            XCTAssertNil(localized["tagline.second"], language)
            if language != "en" { XCTAssertNotEqual(tagline, english["lab.tagline"], language) }
        }
    }
    private func strings(_ language: String) throws -> [String:String] {
        let folder = try XCTUnwrap(Bundle.main.url(forResource:language,withExtension:"lproj"))
        let bundle = try XCTUnwrap(Bundle(url:folder))
        let url = try XCTUnwrap(bundle.url(forResource:"Localizable",withExtension:"strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil) as? [String:String])
    }
}
