"""Build Art/Sounds/UI/draw.wav: the sound of a card sliding off the deck.

The draw used Hearthstone's whoosh.ogg, which is mastered as a full-scale
transition sweep -- right for a pack opening, far too loud and harsh for
something that happens every turn (and twice, when both players draw). WoW's
PlaySoundFile has no volume argument, so the quiet has to be in the file.

This is a soft paper swish: noise, band-passed around where card stock hisses
(1.5-6 kHz), its centre sweeping upward as the card slides, with a quick
attack and a long smooth tail, peaking at -18 dBFS -- about the level of the
other short cues (card.wav, summon.wav). Deterministic (fixed seed).

    python tools/build_draw_sound.py
"""
from pathlib import Path
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "ForeverHearthstone" / "Art" / "Sounds" / "UI" / "draw.wav"
RATE = 44100
LENGTH = 0.30          # seconds
PEAK = 10 ** (-18 / 20)


def band(noise, lo, hi):
    spec = np.fft.rfft(noise)
    f = np.fft.rfftfreq(len(noise), 1 / RATE)
    # soft-edged band (raised cosine skirts an octave wide), no ringing
    gain = np.clip((np.log2(np.maximum(f, 1) / (lo / 2))), 0, 1) * np.clip(np.log2((hi * 2) / np.maximum(f, 1)), 0, 1)
    return np.fft.irfft(spec * gain, len(noise))


def build():
    rng = np.random.default_rng(20260924)
    n = int(RATE * LENGTH)
    t = np.arange(n) / RATE
    noise = rng.normal(0, 1, n)
    # a sweep: crossfade a low band into a high band across the slide
    low, high = band(noise, 1500, 3500), band(noise, 3000, 6000)
    sweep = np.clip(t / (LENGTH * 0.8), 0, 1)
    s = low * (1 - sweep) + high * sweep * 0.8
    # 25 ms attack, then a smooth fall to silence
    attack = np.clip(t / 0.025, 0, 1) ** 2
    decay = np.cos(np.clip((t - 0.025) / (LENGTH - 0.025), 0, 1) * np.pi / 2) ** 2
    s = s * attack * decay
    s = s / np.abs(s).max() * PEAK
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((s * 32767).astype("<i2").tobytes())
    print(f"wrote {OUT.relative_to(ROOT)}: {LENGTH}s, peak {20 * np.log10(PEAK):.0f} dBFS")


if __name__ == "__main__":
    build()
