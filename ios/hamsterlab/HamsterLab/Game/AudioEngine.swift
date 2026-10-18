import AVFoundation
import UIKit

@MainActor final class AudioEngine: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioEngine()
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey:"sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue,forKey:"sound"); if !newValue { stop() } }
    }
    var voices: Bool {
        get { UserDefaults.standard.object(forKey:"hamsterVoices") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue,forKey:"hamsterVoices"); if !newValue { speech.stopSpeaking(at:.immediate); narrationPlayer?.stop() } }
    }
    var haptics: Bool {
        get { UserDefaults.standard.object(forKey:"haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue,forKey:"haptics") }
    }
    private var players: [String:AVAudioPlayer] = [:]
    private let speech=AVSpeechSynthesizer()
    private var narrationPlayer: AVAudioPlayer?
    private override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default,options:[.mixWithOthers])
        for name in ["turn","delivery","select","win","countdown","crawl","chirp","happy"] {
            if let url=Bundle.main.url(forResource:name,withExtension:"wav"),let player=try? AVAudioPlayer(contentsOf:url) {
                player.volume = ["turn","crawl"].contains(name) ? 0.24 : 0.52
                player.prepareToPlay(); players[name]=player
            }
        }
    }
    func play(_ name: String) {
        if haptics && !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            if ["delivery","win"].contains(name) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            else if name == "turn" { UIImpactFeedbackGenerator(style:.soft).impactOccurred() }
            else if name == "select" { UISelectionFeedbackGenerator().selectionChanged() }
        }
        guard enabled,!UIAccessibility.isVoiceOverRunning else { return }
        if ["chirp","happy"].contains(name),!voices { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if let player=players[name] { player.currentTime=0; player.play() }
    }
    func say(_ prompt: NarrationPrompt) {
        guard enabled,voices,!UIAccessibility.isVoiceOverRunning,!ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        speech.stopSpeaking(at:.immediate); narrationPlayer?.stop()
        let language=NarrationCatalog.language(for:Bundle.main.preferredLocalizations.first ?? "en")
        let available=AVSpeechSynthesisVoice.speechVoices()
        let voiceLanguage=NarrationCatalog.preferredVoiceLanguage(for:language,available:available.map(\.language))
        if let voiceLanguage,let voice=available.filter({ $0.language==voiceLanguage }).max(by:{ $0.quality.rawValue < $1.quality.rawValue }) {
            let line=AVSpeechUtterance(string:NarrationCatalog.text(for:prompt,language:language))
            line.voice=voice; line.rate=0.48; line.pitchMultiplier=1.28; line.volume=0.68
            speech.speak(line)
        } else if let url=NarrationCatalog.audioURL(for:prompt,language:language),let player=try? AVAudioPlayer(contentsOf:url) {
            try? AVAudioSession.sharedInstance().setActive(true)
            narrationPlayer=player; player.volume=0.68; player.play()
        }
    }
    func stop() {
        players.values.forEach { $0.stop() }
        speech.stopSpeaking(at:.immediate); narrationPlayer?.stop()
    }
}
