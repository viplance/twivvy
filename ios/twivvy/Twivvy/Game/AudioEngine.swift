import AVFoundation
import UIKit

@MainActor final class AudioEngine {
    static let shared = AudioEngine()
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sound"); if !newValue { players.values.forEach { $0.stop() } } }
    }
    var haptics: Bool {
        get { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "haptics") }
    }
    private var players: [String: AVAudioPlayer] = [:]
    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        for (name, file, ext) in [("turn","rising_wind","mp3"),("delivery","magic_hole_in","mp3"),("select","select","wav"),("win","win","wav"),("countdown","countdown","wav")] {
            if let url = Bundle.main.url(forResource: file, withExtension: ext), let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = name == "turn" ? 0.35 : 0.65
                player.prepareToPlay(); players[name] = player
            }
        }
    }
    func play(_ name: String) {
        if haptics && !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            if name == "delivery" || name == "win" { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            else if name == "select" { UISelectionFeedbackGenerator().selectionChanged() }
            else if name == "turn" { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        guard enabled, !UIAccessibility.isVoiceOverRunning, !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = players[name] else { return }
        player.currentTime = 0; player.play()
    }
    func stop() { players.values.forEach { $0.stop() } }
}
