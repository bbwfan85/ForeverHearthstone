"""Build the turn rope and its burning end (docs/24).

turn-rope.tga  512x32  Hearthstone's rope: a two-strand twisted fuse of
                       brown hemp, lit from above, with fibre grain. It was a
                       flat stripe pattern that the urgency tint turned into a
                       red-and-white candy cane; the real rope never changes
                       colour -- the flame at its end does the warning.
rope-ember.tga 64x64   the flame at the burning end (additive).

Drawn at 4x and reduced, so the twist is anti-aliased. Tiles along x
(the pitch divides 512), so the rope can be any length.

    python tools/build_rope.py
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image

ART = Path(__file__).resolve().parents[1] / 'ForeverHearthstone' / 'Art'
SS = 4
W, H = 512 * SS, 32 * SS
PITCH = 16 * SS               # one twist; 512 / 16 = 32 twists per tile
CY, R = H / 2, 6.2 * SS       # rope centre and radius

rng = np.random.default_rng(3)
ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
v = (ys - CY) / R                          # -1..1 across the rope
inside = np.abs(v) <= 1
# The two strands: the rope's surface is divided by helical grooves. Across a
# twist, a point's phase along the helix decides which strand it lies on and
# how far it is from that strand's crest.
phase = (xs / PITCH + v * 0.42) % 1.0      # slanted lay of the strands
strand = np.where(phase < 0.5, 0, 1)
t = (phase % 0.5) / 0.5                    # 0..1 across one strand
crest = np.sin(t * math.pi)                # 1 at the strand's middle, 0 in the groove
# Light from above: the top of the rope is brighter, and each strand is round.
light = 0.55 + 0.45 * np.sqrt(np.clip(1 - v * v, 0, 1)) - 0.25 * v
shade = light * (0.45 + 0.55 * crest ** 0.7)
# fibre grain running along each strand
grain = 1 + 0.10 * np.sin((xs / SS) * 2.3 + v * 9 + strand * 1.7) + rng.normal(0, 0.05, (H, W))
base = np.array([150, 104, 58], np.float64)          # hemp
alt = np.array([138, 92, 50], np.float64)            # the other strand, a shade darker
col = np.where(strand[..., None] == 0, base, alt) * (shade * grain)[..., None]
# a dark core line in each groove
col *= (0.55 + 0.45 * np.clip(crest * 3, 0, 1))[..., None]
alpha = np.clip((1 - np.abs(v)) * R / SS * 1.6, 0, 1) * inside
img = np.dstack([np.clip(col, 0, 255), alpha * 255]).astype(np.uint8)
Image.fromarray(img, 'RGBA').resize((512, 32), Image.Resampling.LANCZOS).save(ART / 'turn-rope.tga', compression=None)

# The flame: a hot white core in orange, fading out; additive, so black is clear.
E = 64 * SS
ey, ex = np.mgrid[0:E, 0:E].astype(np.float64)
dx, dy = (ex - E / 2) / (E * 0.36), (ey - E * 0.55) / (E * 0.42)
r = np.hypot(dx, dy * (1.0 if True else 1))
core = np.clip(1 - r, 0, 1) ** 1.6
flick = 1 + 0.12 * np.sin(np.arctan2(dy, dx) * 7)
a = np.clip(core * flick, 0, 1)
rgb = np.dstack([255 * np.ones_like(a), 90 + 165 * a ** 0.6, 20 + 235 * a ** 2.2])
ember = np.dstack([rgb * a[..., None], a * 255]).astype(np.uint8)
Image.fromarray(ember, 'RGBA').resize((64, 64), Image.Resampling.LANCZOS).save(ART / 'rope-ember.tga', compression=None)
print('ok')
