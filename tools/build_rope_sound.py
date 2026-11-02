"""Build Art/Sounds/UI/rope-burn.wav: the rope's burning hiss, as ONE sound.

WoW cannot loop a sound file, so the rope used to re-light Hearthstone's
4.3s fuse recording (Cards/Fuse_Underlay_Play.wav) every 4.1s -- and that
recording is a strike, a sizzle, and a fade to silence. Every four seconds
the rope struck a new match: it "kept replaying" rather than burning.

This keeps the recording's own sound but makes it continuous and as long as
a rope: the strike once, then its steady sizzle (0.45-2.1s of the original)
for the rope's length, built by overlap-adding randomly chosen stretches of
it with long equal-power crossfades so no repeat is audible, then the
original's own fade. Deterministic (fixed seed).

    python tools/build_rope_sound.py
"""
from pathlib import Path
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ForeverHearthstone" / "Art" / "Sounds" / "Cards" / "Fuse_Underlay_Play.wav"
OUT = ROOT / "ForeverHearthstone" / "Art" / "Sounds" / "UI" / "rope-burn.wav"
HOLD = 16.0                     # seconds of sizzle: a full rope and a little more
STRIKE_END = 0.45               # the ignition, played once
STEADY = (0.45, 2.10)           # the part that burns evenly
TAIL = (2.10, 3.80)             # the original's own dying fade
GRAIN, FADE = 0.9, 0.35         # grain length and crossfade, seconds


def read(path):
    with wave.open(str(path)) as w:
        rate, ch = w.getframerate(), w.getnchannels()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64)
    return data.reshape(-1, ch).mean(axis=1), rate


def build():
    src, rate = read(SRC)
    rng = np.random.default_rng(1507)
    s = lambda t: int(t * rate)
    strike = src[: s(STRIKE_END)]
    steady = src[s(STEADY[0]): s(STEADY[1])]
    tail = src[s(TAIL[0]): s(TAIL[1])]
    grain, fade = s(GRAIN), s(FADE)
    ramp = np.sin(np.linspace(0, np.pi / 2, fade)) ** 2       # equal-power pair
    body = np.zeros(s(HOLD) + grain)
    pos = 0
    while pos < s(HOLD):
        start = rng.integers(0, len(steady) - grain)
        g = steady[start: start + grain].copy()
        g[:fade] *= np.sqrt(ramp)
        g[-fade:] *= np.sqrt(ramp[::-1])
        body[pos: pos + grain] += g
        pos += grain - fade
    body = body[: s(HOLD)]
    # splice strike -> body -> tail with short crossfades
    x = s(0.12)
    xf = np.linspace(0, 1, x)
    out = np.concatenate([strike[:-x], strike[-x:] * (1 - xf) + body[:x] * xf,
                          body[x:-x], body[-x:] * (1 - xf) + tail[:x] * xf, tail[x:]])
    out = np.clip(out, -32768, 32767).astype("<i2")
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(out.tobytes())
    print(f"wrote {OUT.relative_to(ROOT)}: {len(out) / rate:.1f}s")


if __name__ == "__main__":
    build()
