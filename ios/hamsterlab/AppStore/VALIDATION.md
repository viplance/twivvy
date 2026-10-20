# HamsterLab validation — 19 October 2026

Built with Xcode 26.6 / iOS SDK 26.5. Minimum deployment target: iOS 18.0.

Light interface, 19 October: `/tmp/hamsterlab-light-theme.xcresult` passed four UI
scenarios covering the Russian menu/settings, local join validation, training
gesture/reveal/orientation/exit and Belarusian/German/Turkish training/settings.
Screenshots were inspected for the static watercolor menu artwork, white
backgrounds, readable text and visible tube geometry in both orientations.
`App/LabTheme.swift` uses normal text/background contrast ratios of 5.63:1 or
higher (11.38:1 for body text on white). Sheets and system controls use the light
color scheme; rounded system typography supports the app's eleven languages.
The static menu no longer creates or subscribes an animated 3D showcase.

| Check | Outcome |
|---|---|
| Simulator app build | Passed for iPhone/iPad, bundle `com.enotix.hamsterlab` |
| Shared deterministic rules | 45 seeded browser matches / 1,337 resolved rounds agree |
| Native tests on iPhone 16 Pro Max / iOS 18.6 | 22 passed across the full suite and final renderer regression run |
| Native tests on iPad Pro 13-inch M4 / iOS 18.6 | 15 passed |
| Actual RealityKit render loop | Round animation completes without manual time advancement; final hamster IDs and positions match authoritative rules |
| Tube geometry | Every compatible adjacent tube pair is continuous; quarter-turns keep resting points on the rotated tubes |
| Private preview | Entire hamster rig rides its platform; clearing the preview restores the original position |
| Rig | Face, two eyes and four paws present; traversal squeezes/stretches the body and restores the resting pose |
| Bundled protocol | Native SHA-256 known vector, local WebRTC data-channel offer and canonical command serialization passed |
| iPhone UI | All four scenarios passed: local code validation, Russian menu/settings, training/gesture/reveal/rotation/exit, complete training match and rematch |
| iPad UI | Three scenarios passed: local code validation, Russian menu/settings, training/gesture/reveal/rotation/exit |
| Rematch | Final targeted run passes; simulator autopilot is limited to its original match generation |
| Resource package | WAV effects, eighteen MP3 event samples, three MP3 music tracks, bridge, privacy manifest, eleven locale folders and original opaque 1024px icon included |
| Complete localization | All eleven languages have 116 UI keys each, including the single-phrase homecoming slogan; HamsterLab-specific copy, rules and privacy translated; placeholders and localized display names validated; connection errors use app/device wording instead of browser tabs/pages |
| Speech removal | System speech synthesis, all 44 synthesized recordings and their generation tooling removed; vocal audio uses supplied MP3 samples |
| Localization tests | Complete bundled text checked for all eleven languages; Belarusian/German/Turkish training/voice-settings UI scenarios cover the sample-only voice labels |
| Optimized rendering | Twelve-hamster workload reduced from 3,334 to 805 models; approximately 60 scene updates/second; full state refresh approximately 24 ms |
| Final performance UI checks | All five scenarios passed, including complete game/rematch; final host-lifecycle run also passed Russian menu and training/gesture/orientation/exit |
| Metadata / scripts | Draft field lengths, unique localization keys, plist syntax and release script syntax checked |
| Repository layout | Build products ignored; existing `ios/twivvy` source unchanged |

Character redesign, 19 October: the full iPhone native suite passed all 24 tests,
plus Russian menu/settings and training/gesture/orientation/exit UI scenarios in
`/tmp/hamsterlab-characters-review.xcresult`. After refining the ears, eyes and
offline fur textures, all 14 affected native tests and the same two UI scenarios
passed again in `/tmp/hamsterlab-characters-final.xcresult`. Front, three-quarter,
profile, rear and squeeze renders are attached to the character test. Repeated
crawl/reset cycles preserve finite transforms, unit rotations and neutral poses.
That character-review busy-board measurement was 697 models, 59.5 scene callbacks/second,
18.43 ms p95 interval and 20.33 ms mean full state refresh. The eleven coat PNGs
and one shared normal map load from the compiled app, including all five coats.

The subsequent tube/character fit update passed 17 native tests and the
gesture/round/orientation UI scenario in `/tmp/hamsterlab-tube-fit-verified.xcresult`.
It checks constant-radius elbows and axial port tangents, continuous arc-length
travel, and sampled real mesh vertices inside every compatible straight/elbow
pair with and without platform gaps. Repeated resting poses keep finite
transforms and unit quaternions. Five rendered elbow close-ups verify the blue
glass and head articulation. Busy-board results after adding connecting sleeves:
704 models, 60.0 scene callbacks/second, 16.96 ms p95 interval and 22.53 ms mean
full state refresh on the same iPhone simulator. Callback rate is not GPU FPS.

Home arrivals were subsequently verified in
`/tmp/hamsterlab-home-arrivals-release-check.xcresult`: four native tests and the
arrival UI scenario passed. Live deliveries retain the original rigs, seats
remain stable across state refreshes, and both homes face the viewer for either
player. Seated-pose tests check proportions and actual mesh vertices against
the floor, plus the transition back to running. UI attachments show the real
game before, during and after an arrival. The complete thirty-round/rematch UI
scenario also passed in `/tmp/hamsterlab-home-arrivals-complete.xcresult`.
Twelve seated residents measured 692 models and approximately 60 scene update
callbacks/second on the same simulator.

`/tmp/hamsterlab-slower-motion.xcresult` passed four native tests and two UI
scenarios after lowering character speed to 0.75. At the former crossing time,
a character is now exactly 75% along the route. Arrival, renderer-driven round
completion, immediate online state updates and portrait/landscape interaction
remain covered. The offline and bundled bridge round waits are both 1450 ms.

Blocked hamsters now turn over the existing crossing interval, gathering their
bodies and alternating paw steps. `/tmp/hamsterlab-turnaround.xcresult` passed
two tests covering frame-to-frame orientation continuity and sampled mesh
clearance in all six tube shapes, both exits and both turn directions.
`/tmp/hamsterlab-turnaround-visual.xcresult` passed the rendered elbow/turn
inspection and the portrait/landscape training UI scenario. Start, midpoint
and final turn screenshots were inspected; the round duration is unchanged.

The supplied MP3 event bank is covered by `/tmp/hamsterlab-mp3-final.xcresult`:
six native tests and a complete-match/rematch UI test passed. All eighteen
bundled files decode and prepare for playback. Receiver cues are checked for
both player sides, draws emit neither victory nor defeat, thinking reactions
have 7–15-round intervals with one cue per selected round, and tube/home
reversals emit one event rather than repeating it each frame. UI tests mute
playback without changing the user's sound preference.

`/tmp/hamsterlab-music-checked.xcresult` passed all six audio tests after
adding background music. All three music tracks decode and prepare for playback.
The player gain is checked against the event gain for an exact -6 dB difference.
A real-player test verifies the 0.3-second fade, silence after completion,
cancelling an old fade on resume, and choosing a different track on restart.
Result sample playback awaits the music fade; all match endings, including
draws, fade the music even when vocal samples are disabled.

Speech synthesis was subsequently removed entirely.
`/tmp/hamsterlab-no-speech.xcresult` passed six audio tests, one complete-text
localization test and the Belarusian/German/Turkish voice-settings UI scenario.
The built app contains all 21 supplied MP3s and zero synthesized narration
recordings. Locale validation passes 116 keys in each of eleven languages.
Earlier narration test reports below describe the former implementation.

`/tmp/hamsterlab-audio-switches.xcresult` passed seven audio tests, complete-text
localization and the Music-label UI scenario in all eleven languages. Real
players verify that muting music leaves WAV/MP3 effects playing, muting hamster
voices stops all effects while music continues, and both can be disabled
together. The former Sound preference is retained for Music; the switches
default independently to enabled.

`/tmp/hamsterlab-result-scroll.xcresult` passed the complete-match/rematch UI
scenario with an explicit visibility check: the result heading, rematch button
and new-game button are all on screen without a manual swipe. The result card
automatically scrolls into view after layout, also when switching orientation;
Reduce Motion uses an immediate scroll.

The iPhone scenarios were verified in the native/UI run and a final targeted
complete-match/rematch run. The final iPad run passed all 15 native and three UI
tests. Reports are machine-local artifacts:

- `/tmp/hamsterlab-optimized-iphone.xcresult` — passing native and three UI scenarios.
- `/tmp/hamsterlab-rematch-iphone.xcresult` — final passing full-match/rematch scenario.
- `/tmp/hamsterlab-final-ipad.xcresult` — final passing iPad run.
- `/tmp/hamsterlab-localization-tests.xcresult` — two native localization tests and two UI tests, covering four interface languages and all eleven narration resource sets.
- `/tmp/hamsterlab-slogan-locales.xcresult` — two native localization tests and two UI tests passed: all eleven menu slogans are visible, Russian settings work, and all eleven bundled text/narration sets decode. The catalog validator checks 120 keys per language, placeholders, display names and all 44 audio fingerprints; a source audit found no missing literal UI/bridge keys.
- `/tmp/hamsterlab-perf-verified.xcresult` — full suite: 21 native and five UI tests passed after rendering optimization.
- `/tmp/hamsterlab-perf-pause.xcresult` — final 12 renderer/performance checks and two UI scenarios passed; screenshots confirm the board remains visible after a round, orientation changes and a return to the menu.
- `/tmp/hamsterlab-perf-visible.xcresult` — final gesture/round/orientation test also verifies visible geometry by sampling actual screenshot pixels.

See [PERFORMANCE.md](PERFORMANCE.md) for the before/after workload, measurement
limits and renderer changes. The initial iPad results above predate the rendering
optimization and character redesign.

Simulator screenshots are generated locally by UI tests and are not stored in
the repository. An additional manual run with the four-hamster preview fixture
verified that its hamsters remain visible and move to their resolved positions
across natural timed rounds.

Rules, bots and native networking compile from Twivvy's existing source. The
bundled bridge adapter uses HamsterLab's 1450 ms visual resolution pause; the
regenerated protocol body uses the same web sources. UI tests disable advisory presence calls. No
production multiplayer room was created for this validation; cross-app online
play was not exercised on physical devices.

Physical-device GPU performance, voice timbre, audio/haptics and poor-network
behavior remain device checks. No signed device archive, App Store Connect
upload, App Review submission or website deployment was performed. The updated
AASA file needs publication before HTTPS invitations can launch HamsterLab.

## Version 1.0.1 (2)

- iPhone SE 2020 / iOS 18.6: missing-name validation focuses the visible field above the keyboard; entering a name starts training.
- Training timer, corner platforms and next-round action fit without scrolling in portrait and landscape on SE 2020 and iPhone 16 Pro Max.
- Tube sides and underside use denser blue glass while the upper window stays clear. Platforms and tube outlines have stronger contrast.
- `/tmp/hamsterlab-readable-tubes.xcresult`: glass-elbow render test and both SE UI regressions passed (3 tests, no failures); render attachments inspected.

## Version 1.0.1 (3)

- Added complete Simplified Chinese, Japanese, Hindi, Arabic and Persian catalogs:
  16 supported languages, 116 keys each. Generator and bundled-text checks pass.
- Native UI tests passed on iPhone SE 2020 / iOS 18.6 for Chinese, Japanese and
  Hindi training/settings, and Arabic/Persian menu, training and settings.
- RTL navigation arrows follow reading direction; Arabic/Persian headings retain
  connected letter shaping without added tracking. Inspected native screenshots.
- Oops samples trigger a short green smoke effect behind a random tube resident
  when playback starts. Seven lightweight puffs follow the tube's actual curve,
  fade over 1.35 seconds, and clear before traversal or when the renderer hides.
- Smoke containment tests cover all six tube masks and both directions, checking
  bore clearance, open-end clearance, expiry and removal on round transitions.
  Inspected a native render of the effect inside a glass elbow.
