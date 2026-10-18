# HamsterLab validation — 18 October 2026

Built with Xcode 26.6 / iOS SDK 26.5. Minimum deployment target: iOS 18.0.

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
| Resource package | Eight original WAV effects, 44 localized AAC narration clips, bridge, privacy manifest, eleven locale folders and original opaque 1024px icon included |
| Complete localization | All eleven languages have 121 UI keys each; HamsterLab-specific copy, rules and privacy translated; placeholders and localized display names validated |
| Narration resources | All 44 clips decode from the compiled app; source text/audio SHA-256 fingerprints match; same-language voice selection and regional normalization pass |
| Localization tests | Two native tests passed; Russian menu/settings and Belarusian/German/Turkish training/voice-settings UI scenarios passed on iPhone |
| Optimized rendering | Twelve-hamster workload reduced from 3,334 to 805 models; approximately 60 scene updates/second; full state refresh approximately 24 ms |
| Final performance UI checks | All five scenarios passed, including complete game/rematch; final host-lifecycle run also passed Russian menu and training/gesture/orientation/exit |
| Metadata / scripts | Draft field lengths, unique localization keys, plist syntax and release script syntax checked |
| Repository layout | Build products ignored; existing `ios/twivvy` source unchanged |

The iPhone scenarios were verified in the native/UI run and a final targeted
complete-match/rematch run. The final iPad run passed all 15 native and three UI
tests. Reports are machine-local artifacts:

- `/tmp/hamsterlab-optimized-iphone.xcresult` — passing native and three UI scenarios.
- `/tmp/hamsterlab-rematch-iphone.xcresult` — final passing full-match/rematch scenario.
- `/tmp/hamsterlab-final-ipad.xcresult` — final passing iPad run.
- `/tmp/hamsterlab-localization-tests.xcresult` — two native localization tests and two UI tests, covering four interface languages and all eleven narration resource sets.
- `/tmp/hamsterlab-perf-verified.xcresult` — full suite: 21 native and five UI tests passed after rendering optimization.
- `/tmp/hamsterlab-perf-pause.xcresult` — final 12 renderer/performance checks and two UI scenarios passed; screenshots confirm the board remains visible after a round, orientation changes and a return to the menu.
- `/tmp/hamsterlab-perf-visible.xcresult` — final gesture/round/orientation test also verifies visible geometry by sampling actual screenshot pixels.

See [PERFORMANCE.md](PERFORMANCE.md) for the before/after workload, measurement
limits and renderer changes. The initial iPad results above predate this optimization.

Simulator screenshots are generated locally by UI tests and are not stored in
the repository. An additional manual run with the four-hamster preview fixture
verified that its hamsters remain visible and move to their resolved positions
across natural timed rounds.

Rules, bots and native networking compile from Twivvy's existing source. The
bundled bridge adapter is identical to Twivvy's, and the regenerated protocol
body uses the same web sources. UI tests disable advisory presence calls. No
production multiplayer room was created for this validation; cross-app online
play was not exercised on physical devices.

Physical-device GPU performance, voice timbre, audio/haptics and poor-network
behavior remain device checks. No signed device archive, App Store Connect
upload, App Review submission or website deployment was performed. The updated
AASA file needs publication before HTTPS invitations can launch HamsterLab.
