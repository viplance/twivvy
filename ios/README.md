# Twivvy for iOS

Native Swift 6 / SwiftUI / SpriteKit game for every iPhone and iPad capable of running iOS 18 or newer. Open `Twivvy.xcodeproj` and select the **Twivvy** scheme. No third-party native dependencies are required.

## Build

Requires Xcode 26 or newer. The deployment target remains iOS 18.0. Apple requires the iOS 26 SDK or later for submissions from 28 April 2026; see [Apple's current requirements](https://developer.apple.com/news/upcoming-requirements/).

```sh
# From the repository root; generated project is already checked in.
node ios/scripts/sync-web.mjs
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/Twivvy.xcodeproj -scheme Twivvy \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.6' test

# Signed local archive and App Store IPA. Does not upload.
ios/scripts/release.sh
```

Automatic signing uses team **W37L5728Y6**, matching the owner's neighbouring projects. Bundle ID: **com.enotix.twivvy**. Version 1.0.0, build 1. Certificates and private keys are not copied into the repository. Change the build number before uploading a subsequent build.

## Feature map

| Web feature | iOS implementation |
|---|---|
| Nine rotating platforms / all three symmetric maps | `Engine/Rules.swift`, `Game/BoardScene.swift` |
| Thirty rounds, scheduled spawns, collisions, cooldown, seven-point early win | Native integer-only simulation, verified against browser fixtures |
| Hidden simultaneous moves / combined rotations | Original SHA-256 commit/reveal protocol with native CryptoKit hashing |
| Private room / shareable invitation | Native setup, ShareLink, code/link entry, `twivvy://join?code=ABCDE` |
| Universal links | Associated-domains entitlement and published AASA file |
| Public matchmaking / player presence | Existing signaling service and Matchmaker |
| Three bot levels | Native Swift bot; chooses from public state before human input |
| Rematch | Existing connection and host-selected map |
| Recovery / backgrounding | Existing replay/proof reconciliation, native Keychain storage, explicit suspend/resume |
| Eleven languages | Browser translations + native copy, selected by iOS per-app language preferences |
| Sounds | Original turn/delivery effects + generated selection/countdown/victory tones |
| Touch controls | Tap then rotate, or swipe around a platform; live private rotation preview |
| Accessibility | VoiceOver platform controls, track descriptions, Dynamic Type, Reduce Motion, optional haptics |

The interface, rendering, offline rules and bot are Swift. To preserve compatibility with existing browser players without adding a third-party WebRTC binary, **the bundled web networking and match-session code runs in a nonpersistent, noninteractive WKWebView**. It contains no web game UI and downloads no executable scripts. HTTPS signaling is performed by URLSession against a fixed host; native CryptoKit supplies SHA-256. Online resolved rounds are independently replayed in Swift and checked against the protocol result before rendering.

`Resources/Bridge/protocol.js` is generated from `js/rules.js`, `js/net.js` and `js/session.js`. Do not edit the generated file. `scripts/sync-web.mjs` regenerates it, all locales and 45 deterministic reference games (1,337 rounds). The bridge adapter lives in `Resources/Bridge/bridge.js`.

## Tests

The **Twivvy** scheme runs native rule/browser parity tests, local WebKit/hash/data-channel capability tests, and UI flows. UI tests disable network presence checks. Screenshots are retained in `.xcresult` attachments.

The separate **TwivvyLive** scheme is opt-in. It creates two synthetic clients in a private room on the production signaling service; it never enters the public matchmaking queue. It tests commit/reveal, state agreement, cold bridge recovery and rematch, then leaves the room. Only run it when use of the production service is authorized.

## App Store materials

See `AppStore/RELEASE.md` for metadata, privacy disclosures, screenshots and release status. `ExportOptions.plist` exports locally using App Store distribution signing. `AppStore/Screenshots` contains actual simulator captures, not mockups.

Website files are in `../public/privacy.html`, `../public/support.html` and `../public/.well-known/apple-app-site-association`; all three were published on `twivvy.e-notix.com` on 17 September 2026. Run `pnpm run deploy:app-pages` from the repository root to publish updates. The script sets explicit HTML/JSON content types and disables response transformation for these files. Apple may cache the Universal Link association independently; opening links on an installed physical device still needs a release check. Code/link paste and the custom URL scheme work independently of AASA.

## Practical limits

The inherited WebRTC configuration has Google STUN servers and **no TURN relay**. Some restrictive networks cannot establish a peer connection. This limitation also exists in the current browser version; provisioning TURN requires separate service credentials. iOS pauses online play while backgrounded and attempts verified recovery on return; it does not claim background gameplay. Waiting rooms and matches with an absent player expire after 30 minutes.

iPad supports portrait, upside-down portrait, landscape and resizable windows. iPhone supports portrait and both landscape orientations. No `UIRequiresFullScreen` restriction is set. Device family is iPhone + iPad; minimum deployment version is the sole OS floor. Physical-device audio/haptic quality and poor-network behavior should also be checked before release.
