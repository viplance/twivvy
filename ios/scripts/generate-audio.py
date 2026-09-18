#!/usr/bin/env python3
"""Original short PCM effects, generated without external samples or libraries."""
import math
import struct
import wave
from pathlib import Path

output = Path(__file__).resolve().parent.parent / 'Twivvy/Resources/Audio'
for name, notes, duration in [
    ('select', [880, 1174], .09),
    ('countdown', [660], .12),
    ('win', [523.25, 659.25, 783.99, 1046.5], .75),
]:
    with wave.open(str(output / f'{name}.wav'), 'w') as stream:
        rate = 44100
        stream.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
        samples = []
        for index in range(int(duration * rate)):
            time = index / rate
            note = notes[min(len(notes) - 1, int(time / duration * len(notes)))]
            local = (time % (duration / len(notes))) / (duration / len(notes))
            envelope = min(1, local * 15) * (1 - local) ** 1.5
            signal = math.sin(2 * math.pi * note * time) + .15 * math.sin(4 * math.pi * note * time)
            samples.append(struct.pack('<h', int(9500 * envelope * signal)))
        stream.writeframes(b''.join(samples))
