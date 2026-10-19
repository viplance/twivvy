import AVFoundation
import UIKit

@MainActor final class AudioEngine: NSObject {
    static let shared = AudioEngine()
    private let preferences: UserDefaults
    var musicEnabled: Bool {
        // Retain the saved preference from the former Sound toggle.
        get { preferences.object(forKey:"sound") as? Bool ?? true }
        set {
            preferences.set(newValue,forKey:"sound")
            if newValue { if musicRequested { startGameMusic() } }
            else { music.fadeOut() }
        }
    }
    var voices: Bool {
        get { preferences.object(forKey:"hamsterVoices") as? Bool ?? true }
        set { preferences.set(newValue,forKey:"hamsterVoices"); if !newValue { stopEffects() } }
    }
    var haptics: Bool {
        get { preferences.object(forKey:"haptics") as? Bool ?? true }
        set { preferences.set(newValue,forKey:"haptics") }
    }
    private(set) var players: [String:AVAudioPlayer] = [:]
    private var samplePlayers: [HamsterSound:[AVAudioPlayer]] = [:]
    private var lastSample: [HamsterSound:Int] = [:]
    private var sampleQueue: [HamsterSound] = []
    private var sampleTask: Task<Void,Never>?
    private(set) var currentSample: AVAudioPlayer?
    private var currentSound: HamsterSound?
    let music=GameMusic()
    private var musicRequested=false
    init(preferences: UserDefaults = .standard) {
        self.preferences=preferences
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
        guard voices,!UIAccessibility.isVoiceOverRunning,!ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
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
        guard voices,!UIAccessibility.isVoiceOverRunning,!ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        guard samplePlayers[sound]?.isEmpty == false else { return }
        if sound.isResult {
            sampleTask?.cancel(); sampleTask=nil
            currentSample?.stop(); currentSample=nil; currentSound=nil
            sampleQueue.removeAll()
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
    private func stopSamples() {
        sampleTask?.cancel(); sampleTask=nil
        sampleQueue.removeAll(); currentSample?.stop(); currentSample=nil; currentSound=nil
    }
    private func stopEffects() {
        stopSamples()
        players.values.forEach { $0.stop() }
    }
    func startGameMusic() {
        musicRequested=true
        guard musicEnabled,!UIAccessibility.isVoiceOverRunning,!ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        music.start()
    }
    func endGameMusic() {
        musicRequested=false
        music.fadeOut()
    }
    func stop() {
        music.fadeOut()
        stopEffects()
    }
}
