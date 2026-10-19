import AVFoundation
import XCTest
@testable import HamsterLab

final class AudioTests: XCTestCase {
    @MainActor func testFirstLaunchEnablesMusicAndVoicesAndPreservesSavedChoices() throws {
        let suite="HamsterLab.FirstLaunch." + UUID().uuidString
        let preferences=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { preferences.removePersistentDomain(forName:suite) }
        XCTAssertNil(preferences.object(forKey:"sound"))
        XCTAssertNil(preferences.object(forKey:"hamsterVoices"))
        let firstLaunch=AudioEngine(preferences:preferences)
        XCTAssertTrue(firstLaunch.musicEnabled)
        XCTAssertTrue(firstLaunch.voices)
        firstLaunch.musicEnabled=false; firstLaunch.voices=false
        let nextLaunch=AudioEngine(preferences:preferences)
        XCTAssertFalse(nextLaunch.musicEnabled)
        XCTAssertFalse(nextLaunch.voices)
        preferences.removePersistentDomain(forName:suite)
        let cleanInstall=AudioEngine(preferences:preferences)
        XCTAssertTrue(cleanInstall.musicEnabled)
        XCTAssertTrue(cleanInstall.voices)
    }
    @MainActor func testMusicAndAllEffectsHaveIndependentSwitches() async throws {
        let suite="HamsterLab.AudioTests." + UUID().uuidString
        let preferences=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { preferences.removePersistentDomain(forName:suite) }
        // A saved Sound=false now mutes only music; voices default to enabled.
        preferences.set(false,forKey:"sound")
        let audio=AudioEngine(preferences:preferences)
        audio.haptics=false
        XCTAssertFalse(audio.musicEnabled)
        XCTAssertTrue(audio.voices)
        audio.startGameMusic()
        XCTAssertNil(audio.music.player)
        for playerName in audio.players.keys {
            audio.play(playerName)
            XCTAssertTrue(try XCTUnwrap(audio.players[playerName]).isPlaying,playerName)
        }
        audio.playSample(.turnaround)
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertTrue(try XCTUnwrap(audio.currentSample).isPlaying)
        audio.musicEnabled=true
        XCTAssertTrue(try XCTUnwrap(audio.music.player).isPlaying)
        audio.voices=false
        XCTAssertNil(audio.currentSample)
        XCTAssertTrue(audio.players.values.allSatisfy { !$0.isPlaying })
        XCTAssertTrue(try XCTUnwrap(audio.music.player).isPlaying,"Disabling effects must leave music playing")
        audio.play("select"); audio.playSample(.oops)
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertNil(audio.currentSample)
        XCTAssertTrue(audio.players.values.allSatisfy { !$0.isPlaying })
        audio.voices=true
        audio.play("select"); audio.playSample(.turnaround)
        try await Task.sleep(for:.milliseconds(30))
        let sample=try XCTUnwrap(audio.currentSample)
        XCTAssertTrue(sample.isPlaying)
        audio.musicEnabled=false
        XCTAssertTrue(sample.isPlaying,"Disabling music must leave vocal samples playing")
        XCTAssertTrue(try XCTUnwrap(audio.players["select"]).isPlaying,"Disabling music must leave WAV effects playing")
        await audio.music.fadeTask?.value
        XCTAssertNil(audio.music.player)
        audio.voices=false
        audio.play("select"); audio.playSample(.oops)
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertNil(audio.currentSample)
        XCTAssertTrue(audio.players.values.allSatisfy { !$0.isPlaying })
        XCTAssertNil(audio.music.player)
        audio.stop()
    }
    func testAllThreeMusicTracksDecode() throws {
        let tracks=GameMusic.files()
        XCTAssertEqual(tracks.count,3)
        for url in tracks {
            let player=try AVAudioPlayer(contentsOf:url)
            XCTAssertGreaterThan(player.duration,0,url.lastPathComponent)
            XCTAssertTrue(player.prepareToPlay())
        }
        XCTAssertEqual(20*log10(Double(GameAudioLevels.music/GameAudioLevels.effect)),-6,accuracy:0.0001)
    }
    @MainActor func testMusicFadesToSilenceAndRestartCancelsTheOldFade() async throws {
        let music=GameMusic()
        music.start()
        let first=try XCTUnwrap(music.player)
        XCTAssertTrue(first.isPlaying)
        XCTAssertEqual(first.volume,GameAudioLevels.music,accuracy:0.0001)
        let interruptedFade=try XCTUnwrap(music.fadeOut())
        music.start()
        await interruptedFade.value
        XCTAssertTrue(music.player === first)
        XCTAssertTrue(first.isPlaying,"A cancelled fade must not stop music in a resumed game")
        XCTAssertEqual(first.volume,GameAudioLevels.music,accuracy:0.0001)
        let started=ContinuousClock.now
        let resultFade=try XCTUnwrap(music.fadeOut())
        XCTAssertTrue(first.isPlaying,"Fade should ramp down rather than stopping immediately")
        await resultFade.value
        XCTAssertGreaterThanOrEqual(started.duration(to:.now),.seconds(GameAudioLevels.fadeDuration))
        XCTAssertFalse(first.isPlaying)
        XCTAssertNil(music.player,"Result samples can start only after the outgoing music has stopped")
        music.start()
        XCTAssertTrue(try XCTUnwrap(music.player).isPlaying)
        XCTAssertNotEqual(music.player?.url,first.url,"The next track should be a different random choice")
        await music.fadeOut()?.value
    }
    func testAllEventSamplesAreBundledAndDecode() throws {
        let counts: [HamsterSound:Int] = [.loss:3,.minusPoint:2,.plusPoint:2,.turnaround:5,.win:3,.oops:3]
        for sound in HamsterSound.allCases {
            let files=sound.files()
            XCTAssertEqual(files.count,counts[sound],sound.rawValue)
            for url in files {
                let player=try AVAudioPlayer(contentsOf:url)
                XCTAssertGreaterThan(player.duration,0,url.lastPathComponent)
                XCTAssertTrue(player.prepareToPlay(),url.lastPathComponent)
            }
        }
    }
    func testCaptureSoundsFollowThePlayersSide() {
        var before=BoardState(); before.tick=2
        before.cells[0][0]=5; before.cells[5][5]=5
        before.balls=[Ball(id:1,row:0,col:0,exit:0)]
        var after=before
        let top=Rules.resolve(&after,top:nil,bottom:nil)
        XCTAssertEqual(HamsterSound.deliveries(top,side:.top),[.plusPoint])
        XCTAssertEqual(HamsterSound.deliveries(top,side:.bottom),[.minusPoint])
        before.balls.append(Ball(id:2,row:5,col:5,exit:2)); after=before
        let both=Rules.resolve(&after,top:nil,bottom:nil)
        XCTAssertEqual(HamsterSound.deliveries(both,side:.top),[.plusPoint,.minusPoint])
        XCTAssertEqual(HamsterSound.deliveries(both,side:.bottom),[.plusPoint,.minusPoint])
        XCTAssertEqual(HamsterSound.result(own:7,opponent:3),.win)
        XCTAssertEqual(HamsterSound.result(own:3,opponent:7),.loss)
        XCTAssertNil(HamsterSound.result(own:3,opponent:3))
    }
    func testThinkingCueOccursOnlyOnceEverySevenToFifteenRounds() throws {
        var schedule=ThinkingSoundSchedule(), previous=0, cues=0
        for round in 1...150 {
            let expected=round == schedule.nextRound
            schedule.begin(round:round,remaining:30)
            if expected {
                XCTAssertTrue((7...15).contains(round-previous))
                let threshold=try XCTUnwrap(schedule.remainingAtCue)
                XCTAssertTrue((3...25).contains(threshold))
                XCTAssertFalse(schedule.takeCue(remaining:threshold+0.1))
                XCTAssertTrue(schedule.takeCue(remaining:threshold))
                schedule.begin(round:round,remaining:20)
                XCTAssertFalse(schedule.takeCue(remaining:1),"Repeated timer/restore messages cannot repeat the cue")
                XCTAssertTrue((7...15).contains(schedule.nextRound-round))
                previous=round; cues += 1
            } else {
                XCTAssertNil(schedule.remainingAtCue)
                XCTAssertFalse(schedule.takeCue(remaining:1))
            }
        }
        XCTAssertGreaterThan(cues,8)
    }
    func testThinkingCueNeverFiresAfterTheTimerExpires() {
        var schedule=ThinkingSoundSchedule()
        schedule.begin(round:schedule.nextRound,remaining:30)
        XCTAssertFalse(schedule.takeCue(remaining:0))
    }
}
