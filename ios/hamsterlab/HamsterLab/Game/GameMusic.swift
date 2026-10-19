import AVFoundation

enum GameAudioLevels {
    static let effect: Float = 0.7
    static let music = effect * Float(pow(10.0,-6.0/20.0))
    static let fadeDuration: Double = 0.3
}

/// A separate player lets the music fade without fading event samples.
@MainActor final class GameMusic: NSObject, AVAudioPlayerDelegate {
    private(set) var player: AVAudioPlayer?
    private(set) var fadeTask: Task<Void,Never>?
    private var requested=false
    private var lastTrack: URL?
    private let tracks: [URL]

    nonisolated static func files(in bundle: Bundle = .main) -> [URL] {
        (1...3).compactMap { bundle.url(forResource:String(format:"HamsterLab_%02d",$0),withExtension:"mp3",subdirectory:"sound") }
    }

    init(tracks: [URL] = GameMusic.files()) { self.tracks=tracks; super.init() }

    func start() {
        requested=true
        fadeTask?.cancel(); fadeTask=nil
        if let player,player.isPlaying {
            player.setVolume(GameAudioLevels.music,fadeDuration:0)
            return
        }
        playNext()
    }

    private func playNext() {
        guard requested else { return }
        let alternatives=tracks.filter { tracks.count == 1 || $0 != lastTrack }
        guard let url=alternatives.randomElement(),let next=try? AVAudioPlayer(contentsOf:url) else { return }
        player?.stop()
        next.delegate=self; next.volume=GameAudioLevels.music
        next.prepareToPlay()
        player=next; lastTrack=url
        try? AVAudioSession.sharedInstance().setActive(true)
        next.play()
    }

    /// Share an in-progress fade with result playback, which must await silence.
    @discardableResult func fadeOut() -> Task<Void,Never>? {
        requested=false
        if let fadeTask { return fadeTask }
        guard let outgoing=player else { return nil }
        outgoing.setVolume(0,fadeDuration:GameAudioLevels.fadeDuration)
        let task=Task { [weak self] in
            do { try await Task.sleep(for:.seconds(GameAudioLevels.fadeDuration)) }
            catch { return }
            outgoing.stop()
            guard self?.player === outgoing else { return }
            self?.player=nil; self?.fadeTask=nil
        }
        fadeTask=task
        return task
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self,self.requested,self.fadeTask == nil,self.player?.isPlaying == false else { return }
            self.playNext()
        }
    }
}
