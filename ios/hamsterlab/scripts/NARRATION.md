# Localized narration

The app has four short spoken prompts in each of its eleven languages. Text is
authored in `locales/*.json` under `lab.welcome`, `lab.begin`, `lab.win` and
`lab.finish`. An installed AVSpeechSynthesizer voice of the same language is
preferred. The matching bundled AAC recording is used when that voice is absent.
Russian or English speech is never substituted for Belarusian.

## Regeneration

Install [eSpeak NG](https://github.com/espeak-ng/espeak-ng) 1.52 or later as a
development tool. On macOS, run from the repository root:

```sh
ESPEAK_NG=/path/to/espeak-ng pnpm hamsterlab:narration
pnpm hamsterlab:generate
```

The initial recordings were synthesized with eSpeak NG 1.52.0, voice variant
`f3`, pitch 68 and speed 170 words/minute. English uses `en-us`, Portuguese uses
`pt-pt`, and the remaining languages use their corresponding language code.
macOS `afconvert` encodes mono AAC at 48 kbit/s. No exported Apple voice recordings
are included. eSpeak NG is only a development tool; the app contains the generated
recordings and does not embed or link the synthesizer executable or library.

`Resources/narration-manifest.json` records generator settings, clip durations,
and SHA-256 fingerprints of the exact UTF-8 source text and encoded audio.
`hamsterlab:sync` checks all 44 fingerprints, so stale speech fails the build
preparation step. Native localization tests also decode every clip from the
compiled app and verify the selected language bundle and voice selection policy.

The fallback voice is deliberately synthetic. For richer acting, replace clips
with original licensed recordings, update the manifest with the same text/audio
fingerprints, and retain the existing language and file names.
