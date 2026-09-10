# Twivvy

[Twivvy](https://twivvy.e-notix.com/) is a short browser-based puzzle duel.
Players secretly rotate sections of a shared maze and compete to guide more
balls into their receiver.

The product specification is in
[ios-pvp-market-perekrut.md](ios-pvp-market-perekrut.md).

## Features

- A 3×3 board of rotating 2×2 platforms rendered with Three.js.
- Simultaneous hidden moves with commit/reveal verification.
- Private rooms through shareable URLs such as `/KFUEB`.
- Public matchmaking and local training against three bot difficulty levels.
- Rematches over the existing connection and match recovery after refresh.
- Eleven UI languages selected from `navigator.languages`: English,
  Belarusian, Spanish, Russian, Ukrainian, Italian, Portuguese, Polish,
  French, German, and Turkish. Unknown languages fall back to English.
- Localized game names, browser titles, status messages, and accessibility text.
- Optional sound with the preference stored in the browser.

## Game rules

- Each player may rotate one platform per round.
- Both moves are revealed together; rotations on the same platform combine.
- A rotated platform is unavailable during the next round.
- Balls appear from the two marked centre cells on scheduled rounds.
- Delivered balls remain visible in the receiver; seven points wins early.
- A match lasts at most 30 rounds.

## Stack

| Area | Technology / file |
|---|---|
| UI | Vue 3 SFCs and TypeScript — [src/App.vue](src/App.vue), [src/components/](src/components/) |
| UI state | Composables — [src/composables/](src/composables/) |
| Shared types and constants | [src/types/](src/types/), [src/constants/](src/constants/) |
| Localization | Vue I18n, one file per locale — [src/i18n.ts](src/i18n.ts), [src/locales/](src/locales/) |
| Rendering | Three.js — [js/view.js](js/view.js) |
| Rules | Deterministic simulation — [js/rules.js](js/rules.js) |
| Match lifecycle | Timers, commit/reveal, recovery — [js/session.js](js/session.js) |
| Networking | WebRTC DataChannel — [js/net.js](js/net.js) |
| Signaling | Google Cloud Function and Firestore — [tools/signal-server](tools/signal-server) |
| Build | Vite and pnpm |

Gameplay traffic goes directly between browsers over WebRTC. The signaling
service exchanges SDP/ICE data, manages room presence, and powers matchmaking;
it does not process game moves. Every online round uses a SHA-256 commit/reveal
exchange so neither player can choose after seeing the opponent's move. Local
training does not use networking or commit/reveal.

## Development

Requirements: Node.js `^20.19` or `>=22.12` and pnpm 10 for the UI. The
signaling service requires Node.js 24.

```bash
pnpm install
pnpm start          # http://localhost:8080
pnpm type-check
pnpm test           # both suites
pnpm test:engine    # rules, session, transport — node:test
pnpm test:ui        # components and composables — vitest
pnpm validate-maps
pnpm build          # output: dist/
pnpm preview
```

To test a private match locally, open two tabs, create a room in one, and open
the generated room URL in the other.

`tools/reconnect-browser.mjs` runs the recovery flow in real Chrome. Build the
app first and provide a `PUPPETEER_MODULE` path to `puppeteer-core`.

## Deployment

Deploy the static app to the `twivvy.e-notix.com` Google Cloud Storage bucket:

```bash
pnpm run deploy
```

The script builds first, uploads hashed assets, and publishes `index.html` last
with `Cache-Control: no-cache`. Existing bucket objects are retained.

Cloudflare proxies `twivvy.e-notix.com` to `c.storage.googleapis.com` with SSL
mode set to **Full**. The `twivvy-rooms` Worker uses
[cloudflare-worker.js](cloudflare-worker.js) to rewrite room paths to
`index.html`, allowing invite URLs to return HTTP 200.

The signaling service is deployed separately:

```bash
gcloud functions deploy twivvy-signal --gen2 --runtime=nodejs24 \
  --region=us-central1 --source=tools/signal-server --entry-point=twivvySignal \
  --trigger-http --allow-unauthenticated \
  --env-vars-file=../cloud-functions/twivvy-signal/.env.yaml --max-instances=3
```

## Important constraints

- Keep [js/rules.js](js/rules.js) deterministic and free of DOM, clock, and
  unseeded randomness. Both clients must derive identical state from the log.
- Match deadlines use `Date.now()` and timers, not `requestAnimationFrame`,
  because animation frames stop in background tabs.
- Do not delete a waiting room when local polling stops; the invite must remain
  valid until explicit exit or expiry.
- Asset URLs must remain root-relative so room paths can load the application.
- Configure new origins in the signaling service's `ALLOWED_ORIGINS` value.

## Limitations

- Recovery data lives in the original tab's `sessionStorage` and cannot move to
  another device.
- Waiting rooms and matches with an absent player expire after 30 minutes;
  active rooms remain available.
- There is no TURN server, so WebRTC may fail behind symmetric NAT.

## License

Proprietary. © 2026 Dzmitry Sharko. See [LICENSE](LICENSE).
