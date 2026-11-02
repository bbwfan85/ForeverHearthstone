"""Original quiet tactile menu cues; deterministic PCM, no borrowed recordings."""
import math, random, struct, wave
from pathlib import Path

out = Path(__file__).resolve().parents[1] / 'ForeverHearthstone/Art/Sounds'
rate = 22050
for name, duration, volume in [('menu_hover', .09, .12), ('menu_click', .22, .25),
                                ('menu_page', .4, .18), ('menu_open', .85, .16)]:
    rng = random.Random(name)
    data = bytearray()
    low = 0
    for i in range(int(rate * duration)):
        t = i / rate
        noise = rng.uniform(-1, 1)
        low = .84 * low + .16 * noise
        attack = min(1, t / .004)
        if name == 'menu_page':
            signal = (noise * .25 + low) * math.sin(math.pi*t/duration)**2
        elif name == 'menu_open':
            signal = sum(math.sin(2*math.pi*f*t)*math.exp(-t*(4+j))
                         for j,f in enumerate([196,294,392,588])) / 4
            signal += low * math.exp(-t*12)
        else:
            f = 540 if name == 'menu_hover' else 175
            signal = (.65*math.sin(2*math.pi*f*t) + .3*math.sin(2*math.pi*f*2.73*t)
                      + low*.7) * math.exp(-t*(55 if name=='menu_hover' else 24))
        sample = signal * attack * volume * min(1,(duration-t)/.02)
        data.extend(struct.pack('<h', round(max(-1,min(1,sample))*32767)))
    with wave.open(str(out/(name+'.wav')), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate); f.writeframes(data)
