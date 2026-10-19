# Twivvy for iOS

Native Swift 6 / SwiftUI / SpriteKit game for every iPhone and iPad capable of running iOS 18 or newer. Open `Twivvy.xcodeproj` and select the **Twivvy** scheme. No third-party native dependencies are required.

## Build

Requires Xcode 26 or newer. The deployment target remains iOS 18.0. Apple requires the iOS 26 SDK or later for submissions from 28 April 2026; see [Apple's current requirements](https://developer.apple.com/news/upcoming-requirements/).

```sh
# From the repository root; generated project is already checked in.
node ios/twivvy/scripts/sync-web.mjs
xcodegen generate --spec ios/twivvy/project.yml
xcodebuild -project ios/twivvy/Twivvy.xcodeproj -scheme Twivvy \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.6' test

# Unsigned simulator build.
pnpm run ios:build

# Signed local archive and App Store IPA.
pnpm run ios:release

# Build and upload to App Store Connect / TestFlight.
pnpm run ios:upload
```

Automatic signing uses team **W37L5728Y6**, matching the owner's neighbouring projects. Bundle ID: **com.enotix.twivvy**. Version 1.0.5, build 7 (see `project.yml`). Certificates and private keys are not copied into the repository. Change the build number before uploading a subsequent build.

The iOS project root is `ios/twivvy/`; source code, tests, scripts, signing options,
App Store materials and local build products all live there. Paths in `project.yml`
and the generated Xcode project are relative to this directory.

From the repository root, `pnpm run ios:sync` regenerates web resources and fixtures,
and `pnpm run ios:generate` also regenerates the Xcode project. The build and release
commands perform both steps automatically. You can also run `./scripts/release.sh`
or `./scripts/release.sh --upload` directly from `ios/twivvy/`.

Local archives are written to `ios/twivvy/build/Twivvy.xcarchive`, exported IPAs to
`ios/twivvy/build/AppStore/`, and simulator build products to
`ios/twivvy/build/DerivedData/`. Upload uses a temporary copy of `ExportOptions.plist`
with `destination=upload`; the checked-in options continue to export locally.
Xcode must have the team's signing credentials and an Apple account authorized
for App Store Connect. Increase `CURRENT_PROJECT_VERSION` in `project.yml` before
uploading another build. Upload does not submit the app for App Review.

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

Native error wording, localized invitation examples, privacy text and timer units
are maintained in `scripts/ios-locales.json`, applied after importing web strings.
Every sync validates all eleven catalogs, placeholders, display names and literal
UI/bridge references, and rejects unexpected English fallback text. Run
`pnpm ios:validate-locales` to check existing generated resources separately.

## Tests

The **Twivvy** scheme runs native rule/browser parity tests, local WebKit/hash/data-channel capability tests, and UI flows. UI tests disable network presence checks. Screenshots are retained in `.xcresult` attachments.

The separate **TwivvyLive** scheme is opt-in. It creates two synthetic clients in a private room on the production signaling service; it never enters the public matchmaking queue. It tests commit/reveal, state agreement, cold bridge recovery and rematch, then leaves the room. Only run it when use of the production service is authorized.

## App Store materials

See `AppStore/RELEASE.md` for metadata, privacy disclosures, screenshots and release status. `ExportOptions.plist` exports locally using App Store distribution signing. `AppStore/Screenshots` contains actual simulator captures, not mockups.

Website files are in `../../public/privacy.html`, `../../public/support.html` and `../../public/.well-known/apple-app-site-association`; all three were published on `twivvy.e-notix.com` on 17 September 2026. Run `pnpm run deploy:app-pages` from the repository root to publish updates. The script sets explicit HTML/JSON content types and disables response transformation for these files. Apple may cache the Universal Link association independently; opening links on an installed physical device still needs a release check. Code/link paste and the custom URL scheme work independently of AASA.

## Practical limits

The inherited WebRTC configuration has Google STUN servers and **no TURN relay**. Some restrictive networks cannot establish a peer connection. This limitation also exists in the current browser version; provisioning TURN requires separate service credentials. iOS pauses online play while backgrounded and attempts verified recovery on return; it does not claim background gameplay. Waiting rooms and matches with an absent player expire after 30 minutes.

iPad supports portrait, upside-down portrait, landscape and resizable windows. iPhone supports portrait and both landscape orientations. No `UIRequiresFullScreen` restriction is set. Device family is iPhone + iPad; minimum deployment version is the sole OS floor. Physical-device audio/haptic quality and poor-network behavior should also be checked before release.
