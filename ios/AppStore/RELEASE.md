# Release package — Twivvy 1.0.4 (6)

Build 6 was uploaded to App Store Connect for TestFlight on 25 September 2026 at 16:58 UTC.
Xcode confirmed `Upload succeeded` and `EXPORT SUCCEEDED`; Apple had started
processing the package. App Review submission was not performed.
The uploaded archive is `../build/Twivvy-1.0.4-6.xcarchive`.
See `upload-1.0.4-6.json` for the upload receipt. Receipts for builds 2 to 5
are retained alongside it.

This build fixes the game board turning into a blank light rectangle after a
rotation on wide iPhones, where the game switches between the wide and narrow
layouts. Each SpriteKit scene now keeps one view for its whole life, and that view
moves between layouts instead of re-presenting the scene. The menu artwork uses
the same mechanism. All 24 native tests and six UI tests passed on
iPhone 16 Pro Max / iOS 26, including the new rotation test.

## Prepared

- Swift 6 / SwiftUI / SpriteKit app, iOS 18.0+, device families iPhone and iPad.
- Three maps, complete rule parity, three bots, private rooms, public matchmaking, commit/reveal, rematches and Keychain-backed recovery.
- Eleven interface languages, VoiceOver controls, Reduce Motion, orientation and window-size adaptation.
- 1024 × 1024 opaque RGB icon. Source: `../scripts/draw-icon.swift`; it extends the existing maze/ball visual identity using native vector drawing.
- Original turn and delivery sounds; procedurally generated selection, countdown and victory tones. Audio uses ambient mixing and respects Silent Mode.
- Automatic signing: team `W37L5728Y6`; bundle ID `com.enotix.twivvy`.
- App Store metadata in `metadata.json` (English and Russian). All field lengths checked.
- Privacy manifest, required-reason UserDefaults declaration (`CA92.1`), and encryption declaration in the app.
- Support and privacy HTML pages plus Universal Link association file in `../../public/`.
- Local archive / export automation, with no upload step: `../scripts/release.sh`.

## App Store Connect entries

Create the app record for `com.enotix.twivvy`, attach the distribution build, use the metadata file, and upload the screenshots in `Screenshots/` for iPhone 6.9-inch and iPad 13-inch. Choose Games → Puzzle / Strategy. The app includes no purchases, subscriptions or advertising. Set price and availability in the owner's account.

App Privacy should disclose **Name** (nickname), **User ID** (temporary room/matchmaking credentials), and **Other Data Types** (connection/IP information retained by service infrastructure), for App Functionality. The manifest conservatively marks these as linked within the session. No tracking or advertising purposes. Do not select “Data Not Collected”: the signaling service retains nicknames and room information. Reconfirm infrastructure log retention in the owner's Google Cloud account before submitting those disclosures.

Complete Apple's current age-rating questionnaire based on the shipped app: no violence, sexual content, gambling, medical content, advertising, unrestricted browser, chat or media uploads. Online players can supply a short nickname. Do not mark it as a Kids Category app. App Store Connect computes the rating from these answers; an exact rating is not asserted here.

Privacy URL: `https://twivvy.e-notix.com/privacy.html`.
Support URL: `https://twivvy.e-notix.com/support.html`.
Contact address found in the owner's existing website: `privacy@e-notix.com`. Supply the owner's current App Review phone number and contact details in App Store Connect; none are invented in this repository.

## Review notes (copy into App Store Connect)

Twivvy is a maze puzzle duel. No account, sign-in, purchase, subscription, camera or microphone permission is needed. To test without another player: tap Training, enter a nickname, choose any difficulty and start. Drag a platform to rotate it; tap any platform to reset the planned move. The move resolves after 30 seconds, or tap Next round in training. Seven points wins early; otherwise the match ends after 30 rounds. Rematch starts another game.

To test multiplayer: on one device choose Play with a friend and create a room. On a second device choose Have an invite? and enter the displayed code. The same room can also be joined from the browser game at https://twivvy.e-notix.com/. The host and guest choose hidden moves that are verified with SHA-256 commitments. Both peers need internet access; restrictive networks may block the direct WebRTC connection. Return to the app to recover a suspended game. Waiting rooms and games with an absent player expire after 30 minutes.

The entire interface, rendering and local gameplay are native SwiftUI/SpriteKit/Swift. A bundled, noninteractive WebKit component provides the existing browser-compatible WebRTC session protocol. No web interface or remote executable code is loaded. HTTPS signaling and SHA-256 hashing are native. Online results are checked by the Swift rules engine before display.

## Website deployment

Published on 17 September 2026: privacy policy, support page, and the Universal Link association file at `twivvy.e-notix.com`. Repeat this deployment with `pnpm run deploy:app-pages` from the repository root. Explicit content types and `Cache-Control: public, max-age=300, no-transform` preserve JSON delivery and prevent Cloudflare from injecting analytics into the two static pages. Public response checks are recorded in `website-verification.json`.

## Remaining account steps

1. After Apple finishes processing build 6, make it available to the intended TestFlight group. For App Store release, select it for version 1.0.4 in App Store Connect. Complete owner contact information, privacy questionnaire, age questionnaire, territories and price.
2. Check an actual iPhone/iPad for final sound, haptic and adverse-network behavior; simulator checks do not replace physical-device testing. If broad connectivity behind restrictive NAT is required, configure a TURN service; the current web service also has no TURN relay.
3. Submit for Apple review. Signing and a successful export do not constitute App Store review approval.

## Sources checked

- [Apple SDK submission requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Privacy details and transient data](https://developer.apple.com/app-store/app-privacy-details/)
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [App Store screenshot dimensions](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)

Validation outcomes and artifact paths are recorded in `VALIDATION.md`.
