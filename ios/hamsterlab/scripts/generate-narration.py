#!/usr/bin/env python3
"""Build offline fallback prompts from the exact localized source text.

Development-only tools: eSpeak NG 1.52+ and macOS afconvert. No synthesizer
library or executable is shipped with the app, only the resulting AAC clips.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import wave

project = Path(__file__).resolve().parent.parent
espeak = os.environ.get('ESPEAK_NG') or shutil.which('espeak-ng')
if not espeak:
    raise SystemExit('Set ESPEAK_NG to an eSpeak NG executable, then run this script again.')
converter = shutil.which('afconvert')
if not converter:
    raise SystemExit('macOS afconvert is required to encode the bundled AAC clips.')
version = subprocess.check_output([espeak, '--version'], text=True).splitlines()[0].split(' Data at:')[0]
locales = ['en', 'be', 'es', 'ru', 'uk', 'it', 'pt', 'pl', 'fr', 'de', 'tr']
prompts = ['welcome', 'begin', 'win', 'finish']
# Align European Portuguese with the app's existing pt translations.
espeak_voices = {'pt': 'pt-pt', 'en': 'en-us'}
manifest = {'version': 1, 'generator': version, 'voiceVariant': 'f3', 'pitch': 68, 'wordsPerMinute': 170, 'clips': []}
with tempfile.TemporaryDirectory(prefix='hamsterlab-narration-') as temp:
    for locale in locales:
        translations = json.loads((project / f'scripts/locales/{locale}.json').read_text())
        output = project / f'HamsterLab/Resources/{locale}.lproj'
        output.mkdir(parents=True, exist_ok=True)
        for prompt in prompts:
            text = translations[f'lab.{prompt}']
            wav = Path(temp) / f'{locale}-{prompt}.wav'
            target = output / f'narration-{prompt}.m4a'
            voice = espeak_voices.get(locale, locale) + '+f3'
            subprocess.run([espeak, '-v', voice, '-p', '68', '-s', '170', '-w', str(wav), text], check=True)
            with wave.open(str(wav)) as stream:
                duration = stream.getnframes() / stream.getframerate()
                if duration < 0.2:
                    raise RuntimeError(f'{locale}/{prompt}: empty generated narration')
            target.unlink(missing_ok=True)
            subprocess.run([converter, '-f', 'm4af', '-d', 'aac ', '-b', '48000', str(wav), str(target)], check=True)
            manifest['clips'].append({
                'language': locale, 'prompt': prompt,
                'textSHA256': hashlib.sha256(text.encode()).hexdigest(),
                'audioSHA256': hashlib.sha256(target.read_bytes()).hexdigest(),
                'durationSeconds': round(duration, 3),
            })
        print(f'{locale}: four localized narration clips generated.')
(project / 'HamsterLab/Resources/narration-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
print('Generated and fingerprinted 44 offline narration clips.')
