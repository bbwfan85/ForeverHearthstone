"""Build small original fallback cues; no external recordings are used."""
import math, random, struct, wave
from pathlib import Path
out = Path(__file__).resolve().parents[1] / 'ForeverHearthstone' / 'Art' / 'Sounds'
out.mkdir(exist_ok=True)
rate = 22050
for name, frequency, duration, noise in [
    ('summon', 160, .20, .22), ('impact', 85, .22, .45),
    ('spell', 720, .38, .12), ('death', 110, .42, .65),
    ('card', 440, .12, .30), ('pack', 220, .65, .35),
    ('reward', 660, .65, .02), ('rope', 880, .18, .08),
    ('fire', 140, .58, .75), ('frost', 1450, .48, .22),
    ('holy', 880, .62, .04), ('shadow', 95, .65, .28),
    ('nature', 330, .52, .35), ('arcane', 1040, .44, .10),
    ('weapon', 1650, .24, .55), ('arrow', 580, .24, .80),
]:
    rng = random.Random(name)
    samples = bytearray()
    for i in range(int(rate*duration)):
        t = i/rate
        env = min(1, t/.008) * (1-t/duration)**2
        sweep = frequency*t*(1 + (.8 if name=='spell' else -.25)*t/duration)
        tone = math.sin(2*math.pi*sweep) + .25*math.sin(4*math.pi*frequency*t)
        signal = ((1-noise)*tone + noise*rng.uniform(-1,1)) * env * .38
        samples.extend(struct.pack('<h', int(max(-1,min(1,signal))*32767)))
    with wave.open(str(out/(name+'.wav')), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate); f.writeframes(samples)
