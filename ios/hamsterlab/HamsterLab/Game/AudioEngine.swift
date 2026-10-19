import AVFoundation
import UIKit

@MainActor final class AudioEngine: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioEngine()
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey:"sound") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue,forKey:"sound")
            if newValue { if musicRequested { startGameMusic() } }
            else { stop() }
        }
    }
    var voices: Bool {
        get { UserDefaults.standard.object(forKey:"hamsterVoices") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue,forKey:"hamsterVoices"); if !newValue { speech.stopSpeaking(at:.immediate); narrationPlayer?.stop(); stopSamples() } }
    }
    var haptics: Bool {
        get { UserDefaults.standard.object(forKey:"haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue,forKey:"haptics") }
    }
    private var players: [String:AVAudioPlayer] = [:]
    private let speech=AVSpeechSynthesizer()
    private var narrationPlayer: AVAudioPlayer?
    private var samplePlayers: [HamsterSound:[AVAudioPlayer]] = [:]
    private var lastSample: [HamsterSound:Int] = [:]
    private var sampleQueue: [HamsterSound] = []
    private var sampleTask: Task<Void,Never>?
    private var currentSample: AVAudioPlayer?
    private var currentSound: HamsterSound?
    private let music=GameMusic()
    private var musicRequested=false
    private override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default,options:[.mixWithOthers])
        for name in ["turn","delivery","select","countdown","crawl","chirp","happy"] {
            if let url=Bundle.main.url(forResource:name,withExtension:"wav"),let player=try? AVAudioPlayer(contentsOf:url) {
                player.volume = ["turn","crawl"].contains(name) ? 0.24 : 0.52
                player.prepareToPlay(); players[name]=player
            }
        }
        for sound in HamsterSound.allCases {
            samplePlayers[sound]=sound.files().compactMap { url in
                guard let player=try? AVAudioPlayer(contentsOf:url) else { return nil }
                player.volume=GameAudioLevels.effect; player.prepareToPlay()
                return player
            }
        }
    }
    func play(_ name: String) {
        if haptics && !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            if ["delivery","win"].contains(name) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            else if name == "turn" { UIImpactFeedbackGenerator(style:.soft).impactOccurred() }
            else if name == "select" { UISelectionFeedbackGenerator().selectionChanged() }
        }
        guard enabled,!UIAccessibility.isVoiceOverRunning,!ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        if ["chirp","happy"].contains(name),!voices { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if let player=players[name] { player.currentTime=0; player.play() }
    }
    /// Serialize voice samples so simultaneous captures remain intelligible.
    /// Results take priority over any queued capture or thinking reactions.
    func playSample(_ sound: HamsterSound) {
        if sound.isResult { endGameMusic() }
        if haptics,!ProcessInfo.processInfo.arguments.contains("--uitesting"),sound == .win {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        guard enabled,voices,!UIAccessibility.isVoiceOverRunning,!ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        guard samplePlayers[sound]?.isEmpty == false else { return }
        if sound.isResult {
            sampleTask?.cancel(); sampleTask=nil
            currentSample?.stop(); currentSample=nil; currentSound=nil
            sampleQueue.removeAll()
            speech.stopSpeaking(at:.immediate); narrationPlayer?.stop()
        }
        if sampleQueue.last != sound { sampleQueue.append(sound) }
        startSampleQueue()
    }
    private func startSampleQueue() {
        guard sampleTask == nil else { return }
        sampleTask=Task { [weak self] in
            while let self, !Task.isCancelled, !self.sampleQueue.isEmpty {
                let event=self.sampleQueue.removeFirst()
                if event.isResult {
                    await self.music.fadeOut()?.value
                    guard !Task.isCancelled else { return }
                }
                guard let variants=self.samplePlayers[event],!variants.isEmpty else { continue }
                let choices=variants.indices.filter { variants.count == 1 || $0 != self.lastSample[event] }
                guard let index=choices.randomElement() else { continue }
                self.lastSample[event]=index
                let player=variants[index]
                self.currentSample=player; self.currentSound=event; player.currentTime=0
                try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
                do { try await Task.sleep(for:.seconds(player.duration+0.08)) }
                catch { return }
            }
            self?.currentSample=nil; self?.currentSound=nil; self?.sampleTask=nil
        }
    }
    func stopThinkingSample() {
        sampleQueue.removeAll { $0 == .oops }
        guard currentSound == .oops else { return }
        sampleTask?.cancel(); sampleTask=nil
        currentSample?.stop(); currentSample=nil; currentSound=nil
        startSampleQueue()
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
    private func stopSamples() {
        sampleTask?.cancel(); sampleTask=nil
        sampleQueue.removeAll(); currentSample?.stop(); currentSample=nil; currentSound=nil
    }
    func startGameMusic() {
        musicRequested=true
        guard enabled,!UIAccessibility.isVoiceOverRunning,!ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        music.start()
    }
    func endGameMusic() {
        musicRequested=false
        music.fadeOut()
    }
    func stop() {
        music.fadeOut()
        stopSamples()
        players.values.forEach { $0.stop() }
        speech.stopSpeaking(at:.immediate); narrationPlayer?.stop()
    }
}
