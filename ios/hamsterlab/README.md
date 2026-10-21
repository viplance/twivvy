# HamsterLab / ХомаЛаб

A standalone iOS 18+ SwiftUI / RealityKit game: small, expressive hamsters crawl
through transparent tubes on a miniature laboratory workbench. Russian display
name: **ХомаЛаб**. Bundle ID: `com.enotix.hamsterlab`; version 1.0.1, build 5.
Open `HamsterLab.xcodeproj` and choose the **HamsterLab** scheme.

The interface uses a white canvas, dark slate text, teal/berry accents, sunshine
buttons and mint/peach secondary buttons. `App/LabTheme.swift` defines the palette;
active text/background pairs have at least 5.6:1 contrast. Rounded system type
supports all sixteen languages and Dynamic Type. Sheets also use the light theme.
The menu displays a bundled static watercolor illustration of three hamsters in
laboratory tubes, without an active 3D renderer. See [scripts/MENU-ART.md](scripts/MENU-ART.md)
for the asset path and generation prompt.

## Build and run

Requires Xcode 27.1+ (iOS SDK 27.1+ for full iPhone Duo display support),
XcodeGen, Node.js and pnpm. The minimum supported OS remains iOS 18.0.
From the repository root:

```sh
pnpm hamsterlab:generate # sync protocol, fixtures, locales; generate Xcode project
pnpm hamsterlab:build    # unsigned simulator build
pnpm hamsterlab:test     # native and UI tests on iPhone 16 Pro Max / iOS 18.6
pnpm hamsterlab:release  # signed archive and locally exported IPA
pnpm hamsterlab:upload   # archive, export, then upload to App Store Connect
```

Set `HAMSTERLAB_DESTINATION` to test another installed simulator, for example
`HAMSTERLAB_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.6' pnpm hamsterlab:test`.
Tests run sequentially so multiple rendering simulators do not compete for resources.

For iPhone Duo, run
`HAMSTERLAB_DESTINATION='platform=iOS Simulator,name=iPhone Duo,OS=27.1' pnpm hamsterlab:test`.
Also check folding and unfolding during a round, an unfinished board drag, setup
with the keyboard visible, settings, and the result screen. Repeat in both
orientations and with larger text. A fold must preserve the current game and
selection; an unfinished drag is cancelled because its projection has changed.
The native resize regression exercises the same renderer at several window sizes
without a rotation, checks projected corner hit areas, and verifies that a resize
cannot commit a turn. Physical fold transitions still need the Duo simulator or
a device. The release script rejects SDKs older than 27.1.

Build output is in `ios/hamsterlab/build/` and is excluded from Git. Release
commands need the owner's Xcode signing account for team `W37L5728Y6`, a registered
bundle ID and an App Store Connect app record. Upload is separate from App Review.
Increase `CURRENT_PROJECT_VERSION` before uploading another build. Upload records
are kept in `AppStore/upload-*.json`; upload does not submit the app for review.

## Gameplay and interoperability

The rules and bots compile **directly from `../twivvy/Twivvy/Engine/`**. There is no
second rules implementation to drift. All three maps, thirty rounds, one secret
quarter-turn, cooldown, simultaneous rotation combination, spawns, collisions,
seven-point early victory, training, private rooms, matchmaking, recovery and
rematches retain the original behavior. Internal protocol objects still use the
word `ball`; the presentation shows hamsters.

The native `OnlineBridge.swift` is also shared with Twivvy. The bundled bridge
adapter is unchanged; `scripts/sync-web.mjs` regenerates `protocol.js` from the
same `js/rules.js`, `js/net.js` and `js/session.js`. HTTPS signaling uses
`https://us-central1-enotix.cloudfunctions.net/twivvy-signal`; gameplay remains a
peer WebRTC connection with native SHA-256 commit/reveal verification. HamsterLab
players can play Twivvy and browser players using the existing server.

Saved matches use a separate Keychain service, `com.enotix.hamsterlab.session`.
Existing `https://twivvy.e-notix.com/ABCDE` invitations and `twivvy://` invitations
can be pasted, alongside `hamsterlab://join?code=ABCDE`. HamsterLab registers only
its own URL scheme so it does not take over Twivvy's scheme. Universal Links use
the same domain; the repository's AASA now includes both app IDs. Publishing that
file with `pnpm deploy:app-pages` and Apple's cache refresh are required before
HTTPS links can launch the new app. This task does not publish website changes.

## Original models and animation

`Rendering/HamsterSculpt.swift` builds original organic body/head/cheek surfaces,
cupped ears, soft four-fingered paws and curved whiskers. Five natural coat colors,
cream bellies, a forehead blaze, subtle fur normals and silhouette tufts give the
residents a soft cartoon appearance. `Rendering/HamsterRig.swift` articulates the
body, head, paws, ears, cheeks, brows, nose, mouth and eyes. Glossy pupils move
inside warm white eyes; the smile contains two incisors and a pink tongue.
Meshes and materials are shared between residents. The original textures in
`HamsterLab/Resources/HamsterCoats` are baked offline, so spawning a new coat color
does not generate images on the main thread. There are no downloaded models,
asset-store licenses, remote assets or third-party native dependencies.

RealityKit's `AnimationResource` / `FromToByAnimation` handles breathing and head
motion outside tubes; `Entity.move` handles platform rotation. Constant-radius
circular elbows and straight bores share one arc-length path for glass,
residents and traversal. Characters face the tangent, turn their heads along
the curve and shorten slightly on bends to keep their pouches and ears inside.
Two alternating stride cycles per crossing coordinate foot contact,
recovery, shoulder sway and head motion. Cheeks puff, ears fold and the mouth
opens as the body squeezes through couplings. Independent glances, blinks, nose
sniffs, ear twitches and occasional paw lifts animate resting characters.
Matching ports across a platform seam have transparent sleeves; crossing stays
on the tube axis without a vertical hop. Sleeves retract during private rotation.
Visual interpolation never changes the integer game state.

Delivered hamsters keep their original rig and coat. After leaving the tube they
run along the home pad to a stable centre-out seat, turn towards the viewer and
settle on their haunches with planted paws and a tucked tail. Residents continue
blinking and breathing; the next round can proceed during an arrival. Both homes
face the camera for either player. Recovery reconstructs seated residents from
the authoritative scores; a new game clears all seats. Reduce Motion displays
the final seated pose without the arrival animation.

`HamsterMotion.speed` is 0.75: tube traversal, running, sitting, spawning and
idle character motion play 25% slower. The native and online bridge round waits
are both 1450 ms so the longer traversal completes before another move starts.

Regenerate the twelve original 512×256 coat/normal PNGs from the repository root:

```sh
swift ios/hamsterlab/scripts/generate-character-textures.swift
```

`HamsterCharacterTests` checks repeated squeeze/reset cycles and valid pivot
rotations, and saves front, three-quarter, profile, rear and squeeze renders in
the local `.xcresult` attachments. These review screenshots are not app resources.

`Rendering/LabGeometry.swift` generates hollow, open-ended tube meshes with inner
walls, blue translucent PBR glass, highlights and colored coupling rings. Elbows
have 28 longitudinal segments and 24 vertices around each inner/outer ring. All tubes
and hamster resting points use `TubePath`; rotations carry the whole rig and
spawn markers on the platform. A perspective camera, soft shadows, colored
lights, specimen vials and a flask create a toy laboratory. Shared mesh resources
and cached tube assemblies reduce repeated geometry allocation.

Collars and highlights are batched meshes; unchanged platforms and hamster rigs
are retained between rounds. Offscreen renderers are paused, and countdown
updates are isolated from the board UI. See [AppStore/PERFORMANCE.md](AppStore/PERFORMANCE.md)
for the simulator comparison and repeatable benchmark.

Reduce Motion disables nonessential animation and resolves directly to the final
state. VoiceOver exposes platform descriptions and adjustable rotation actions.
Audio respects Silent Mode. Music, hamster voices/effects and haptics have independent switches; both audio switches default to on.

## Sound and localization

Eighteen supplied MP3 samples in `sound/` are bundled as a folder reference.
Keep that directory when building or archiving; no conversion or network access
is needed. `Game/GameSounds.swift` discovers numbered variants by event prefix:

| Prefix | Event |
| --- | --- |
| `loose_` | Defeat (no defeat cue for a draw) |
| `win_` | Victory |
| `plus_point_` | Hamsters reach the player's receiver |
| `minus_point_` | Hamsters reach the opponent's receiver |
| `return_` | Reversal in a tube, on a half-turning platform or before sitting at home |
| `oops_` | A random thinking-time reaction once every 3–8 rounds |

Each event chooses a random variant without immediately repeating the previous
one. Simultaneous receiver events play in sequence; the result cue takes priority.
Thinking cues occur at a random time with 3–25 seconds remaining and are cancelled
when thinking ends. Oops requires a hamster still in a tube, checked both before
queueing and immediately before playback; seated home residents do not qualify.
Actual oops playback starts green smoke behind a tube resident, fading over
2.7 seconds within the bore. Other samples do not start smoke.
Pause, backgrounding and leaving stop pending playback.
The Hamster voices switch controls all MP3 event samples and WAV effects; muting
music does not mute these sounds. Samples respect Silent Mode and yield to VoiceOver.
The existing generated PCM effects remain for rotation, crawling, selection,
countdown and spawn chatter; `scripts/generate-audio.py` does not modify MP3s.

During a match, `Game/GameMusic.swift` randomly plays
`sound/HamsterLab_01.mp3`, `HamsterLab_02.mp3` or `HamsterLab_03.mp3`.
When a track finishes, another random track starts without immediately repeating
the previous one. Music gain is `0.7 × 10^(-6/20)` (approximately 0.351),
6 dB below the MP3 event sample gain. Music stops with a 0.3-second fade at
match end, on exit, pause or backgrounding, and when Music is disabled.
Victory/defeat playback waits until that fade completes; draws also stop music.
Returning to an active game or re-enabling Music resumes music. The Music switch
controls only the three HamsterLab_ tracks; disabling Hamster voices leaves music
playing. The former Sound preference is retained as the Music preference.

All sixteen languages have translated HamsterLab interface copy, rules
and privacy text: English, Belarusian, Spanish, Russian, Ukrainian, Italian,
Portuguese, Polish, French, German, Turkish, Simplified Chinese (`zh-Hans`),
Japanese (`ja`), Hindi (`hi`), Arabic (`ar`) and Persian (`fa`). There is no speech synthesis or
pre-generated spoken narration. Character voices use only the supplied MP3
samples; no microphone access is required.

`scripts/locales/*.json` contains the HamsterLab-specific translations.
`scripts/hamster-locales.mjs` applies them after syncing shared controls.
Chinese, Japanese, Hindi, Arabic and Persian have complete native catalogs in these JSON files
and do not depend on translations from the web version.
Every sync validates complete key sets, nonempty strings, placeholders and display
names.

```sh
pnpm hamsterlab:validate-locales
pnpm hamsterlab:generate
```

The app icon is a hand-drawn-style hamster illustration, stored as an opaque
1024 × 1024 PNG in the asset catalog. Xcode derives the iPhone/iPad icon sizes
from this universal source. See [scripts/ICON-ART.md](scripts/ICON-ART.md) for its
generation prompt and replacement instructions. Regenerate local audio with:

```sh
python3 ios/hamsterlab/scripts/generate-audio.py
```

## Verification and release preparation

See [AppStore/VALIDATION.md](AppStore/VALIDATION.md) for the implementation checks.
The fixture suite compares 45 browser games / 1,337 resolved rounds. Additional
checks cover every compatible tube pair, rotation geometry, face/limb rig,
private previews, immediate online state events, invitation parsing and the
bundled WebKit hashing/data-channel bridge. UI tests cover Russian branding,
settings, local training, gesture input, landscape/portrait, local invitation
validation and a complete game/rematch. UI tests suppress network presence calls.

For deterministic screenshots, launch with `--uitesting --lab-preview`; this
creates four local example hamsters without contacting the server.
`--uitesting --autoplay` runs a complete real training match at animation speed
for UI verification or video capture.

App Store metadata is a draft in `AppStore/metadata.json`. HamsterLab needs its
own app record and store screenshots. Shared signaling has no TURN relay, so
restrictive NAT can still prevent direct peer connections. Real-device render
performance, sound/haptics and adverse-network behavior need device checks.
