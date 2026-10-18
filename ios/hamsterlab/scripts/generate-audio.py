#!/usr/bin/env python3
"""Original hamster chatter, glass ticks and toy-lab foley; no external samples."""
import math, random, struct, wave
from pathlib import Path

output = Path(__file__).resolve().parent.parent / 'HamsterLab/Resources/Audio'
output.mkdir(parents=True, exist_ok=True)
rate = 44100
rng = random.Random(7731)
for name, duration in [('turn', .32), ('delivery', .48), ('select', .10), ('win', 1.05), ('countdown', .12), ('crawl', .40), ('chirp', .45), ('happy', .55)]:
    samples = []
    for i in range(int(rate * duration)):
        t = i / rate
        p = t / duration
        envelope = min(1, p * 25) * (1-p)**1.7
        if name in ['chirp', 'happy']:
            # Whistling, voiced syllables with formants rather than human samples.
            pitch = 1250 + 520 * math.sin(p*math.pi) + 170*math.sin(p*math.pi*8)
            syllables = max(0, math.sin(p*math.pi* (3 if name == 'happy' else 2)))
            phase = 2*math.pi*(1250*t + 520*duration/math.pi*(1-math.cos(p*math.pi)))
            signal = (math.sin(phase)+.23*math.sin(phase*2))*syllables*.46
        elif name == 'crawl':
            signal = (rng.uniform(-1, 1)*.1 + math.sin(2*math.pi*260*t)*.06) * (.4+.6*abs(math.sin(t*math.pi*25)))
        elif name == 'turn':
            signal = rng.uniform(-1,1)*.06 + math.sin(2*math.pi*(260*t+220*t*t))*.22
        else:
            notes = {'select':[880], 'countdown':[690], 'delivery':[784,1047,1319], 'win':[523.25,659.25,783.99,1046.5]}[name]
            note = notes[min(len(notes)-1,int(p*len(notes)))]
            signal = math.sin(2*math.pi*note*t)*.3 + math.sin(2*math.pi*note*2.76*t)*.08*math.exp(-18*t)
        samples.append(struct.pack('<h',int(max(-1,min(1,signal*envelope))*23000)))
    with wave.open(str(output/f'{name}.wav'),'wb') as stream:
        stream.setparams((1,2,rate,0,'NONE','not compressed')); stream.writeframes(b''.join(samples))
print('Generated eight original hamster/laboratory sound effects.')
