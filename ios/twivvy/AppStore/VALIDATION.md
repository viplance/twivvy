# Validation — 17 September 2026

## Localization follow-up — 19 October 2026

Corrected browser/tab/page instructions in five status/error messages for all
eleven languages. Nine privacy translations previously fell back to English;
all eleven now have authored iOS privacy text. Invitation examples and timer
second units are localized. These overrides live in `scripts/ios-locales.json`
and survive regeneration from the web catalogs.

`pnpm ios:generate` passed, including validation of 115 keys per language,
placeholders, localized display names, unexpected English fallback and 89 literal
UI/bridge key references. `/tmp/twivvy-ios-locales.xcresult` passed one bundled
localization test across all eleven languages and two UI tests: local invitation
validation plus Russian/French/Turkish timer and privacy screens. No production
room was created. The earlier release checks below describe the September build.

## Original release validation

Validated locally with Xcode 26.6 and iOS SDK 26.5.

| Check | Outcome |
|---|---|
| Browser tests | 86 engine/transport tests + 24 UI tests passed |
| Browser production build | Passed; existing large-bundle advisory remains |
| Native parity against browser | 45 seeded matches, 1,337 rounds; every state equal |
| Native edge cases | Collisions, cancelled rotations/cooldown, early win, legal bots and invitation parsing passed |
| Bundled WebKit | Scripts load; CryptoKit SHA-256 known vector; WebRTC data channel offer; canonical command ordering passed |
| iPhone 16 Pro Max / iOS 18.6 | Native tests and menu/settings/training/rotation/exit scenario passed |
| iPad Pro 13-inch M4 / iOS 18.6 | Native tests and portrait/landscape UI scenario passed |
| iPhone 17 Pro Max / iOS 26.5 | Native tests, touch selection, turn, rotation, complete game and rematch passed |
| Live private network test | Two synthetic clients: room/join, commit/reveal, equal results, next round, cold bridge recovery and rematch passed |
| Final private network test | Passed after adding timer-only persistence coalescing |
| App icon | 1024 × 1024 RGB PNG, no alpha |
| Localizations / metadata | 11 locale resources, no duplicate keys; App Store text limits checked |
| Device package | arm64; minimum OS 18.0; device families [1,2]; iOS 26.5 SDK; all audio, locale, privacy and protocol resources present |
| Release archive / App Store export | Both succeeded with automatic provisioning |
| Exported signature | Verified against Apple Distribution: Dzmitry Sharko (W37L5728Y6), Apple WWDR and Apple Root CA |

Live tests used private rooms only, with the user's explicit authorization. No public matchmaking opponents were contacted. App Store / TestFlight upload was not performed. The support/privacy pages and AASA file were subsequently published with user authorization; see `website-verification.json` for public HTTPS checks.

Two integration defects were found and fixed during testing: the initial generated project omitted resources, and native dictionaries changed JSON property order compared with the browser's serialized history. The final project includes the resources. Commands are canonicalized and recovery preserves the original JSON bytes, with a regression assertion for key ordering. UI test waits were also adjusted for orientation transitions.

Artifacts:

- `../build/Twivvy.xcarchive` — signed archive.
- `../build/AppStore/Twivvy.ipa` — locally exported App Store package.
- `Screenshots/en-US/` — actual iPhone 6.9-inch and iPad 13-inch screenshots.
- `../build/validation/` — integrity hashes and release build log.

Original Xcode reports for this workspace session are in `/tmp/twivvy-ios18-final.xcresult`, `/tmp/twivvy-ipad3.xcresult`, `/tmp/twivvy-ios26.xcresult`, and `/tmp/twivvy-network-final.xcresult`. They are machine-local test artifacts, not source files.

No physical iPhone/iPad, TURN relay, App Store review, App Store Connect privacy submission, or physical-device Universal Link handling was validated by this run. See `RELEASE.md` for the remaining publication steps.
