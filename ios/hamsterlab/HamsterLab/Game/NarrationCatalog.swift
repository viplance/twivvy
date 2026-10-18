import Foundation

enum NarrationPrompt: String, CaseIterable {
    case welcome, begin, win, finish
    var key: String { "lab.\(rawValue)" }
    var filename: String { "narration-\(rawValue)" }
}

/// Text, native voice and bundled recording must always use the same app language.
/// In particular, an unavailable Belarusian voice must not select Russian/English.
enum NarrationCatalog {
    static let supportedLanguages = ["en","be","es","ru","uk","it","pt","pl","fr","de","tr"]
    private static let preferredVoices = [
        "en":"en-US", "be":"be-BY", "es":"es-ES", "ru":"ru-RU", "uk":"uk-UA",
        "it":"it-IT", "pt":"pt-PT", "pl":"pl-PL", "fr":"fr-FR", "de":"de-DE", "tr":"tr-TR"
    ]
    private static func primary(_ identifier: String) -> String {
        String(identifier.replacingOccurrences(of:"_",with:"-").lowercased().split(separator:"-").first ?? "")
    }
    static func language(for identifier: String) -> String {
        let code=primary(identifier)
        return supportedLanguages.contains(code) ? code : "en"
    }
    static func preferredVoiceLanguage(for language: String, available: [String]) -> String? {
        let code=self.language(for:language)
        let matching=available.filter { primary($0)==code }
        let preferred=preferredVoices[code]!
        return matching.first { $0.caseInsensitiveCompare(preferred) == .orderedSame }
            ?? matching.sorted().first
    }
    static func localizedBundle(for language: String, in bundle: Bundle = .main) -> Bundle? {
        guard let folder=bundle.url(forResource:self.language(for:language),withExtension:"lproj") else { return nil }
        return Bundle(url:folder)
    }
    static func text(for prompt: NarrationPrompt, language: String, in bundle: Bundle = .main) -> String {
        localizedBundle(for:language,in:bundle)?.localizedString(forKey:prompt.key,value:nil,table:nil) ?? prompt.key
    }
    static func audioURL(for prompt: NarrationPrompt, language: String, in bundle: Bundle = .main) -> URL? {
        // Look only inside the selected localization; never play a different language.
        localizedBundle(for:language,in:bundle)?.url(forResource:prompt.filename,withExtension:"m4a")
    }
}
