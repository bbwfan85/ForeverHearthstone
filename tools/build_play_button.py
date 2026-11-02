"""Build play-button.tga: Hearthstone's glowing amber Play plaque (docs/24).

The Play / Choose Deck button was a generated amber pill in a flat brown rim,
the one control on the screens not drawn in the tavern's own art. This takes
the carved plaque every other button uses (tavern-button.tga: gilded caps, a
wooden frame, a pale stone face) and turns its stone face to Hearthstone's
lit amber -- top-lit, keeping the stone's grain and cracks -- so Play reads
as the same button, made primary. Same canvas and geometry as
tavern-button.tga, so it is drawn with the same 3-slice (Widgets.lua).

    python tools/build_play_button.py
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ART = Path(__file__).resolve().parents[1] / "ForeverHearthstone" / "Art"
src = Image.open(ART / "tavern-button.tga").convert("RGBA")
a = np.asarray(src).astype(np.float64)
rgb, alpha = a[..., :3], a[..., 3]
H, W = alpha.shape
lum = rgb.mean(axis=2)
sat = rgb.max(axis=2) - rgb.min(axis=2)

# The stone face: pale and unsaturated, inside the frame.
face = (lum > 150) & (sat < 80)
ys, xs = np.mgrid[0:H, 0:W]
face &= (xs > 70) & (xs < W - 70) & (ys > 40) & (ys < H - 40)
core = Image.fromarray((face * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
# ...and its bevelled rim and chamfered corners, which are the same stone
# lit and shaded: anything unsaturated within a few pixels of the face.
near = np.asarray(core.filter(ImageFilter.MaxFilter(13))) > 0
face = np.asarray(core) > 0
bevel = near & (sat < 70) & (lum > 95)
m = Image.fromarray(((face | bevel) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
k = np.asarray(m).astype(np.float64)[..., None] / 255

# Amber, lit from above: pale gold at the top of the face to deep orange at
# its foot, carrying the stone's own light and shade (its grain and cracks).
rows = ys[face]
top, bottom = rows.min(), rows.max()
t = np.clip((ys - top) / max(1, bottom - top), 0, 1)[..., None]
light = np.array([255, 224, 110], np.float64)
deep = np.array([214, 118, 22], np.float64)
amber = light * (1 - t) + deep * t
detail = (lum / np.median(lum[face]))[..., None]
amber = amber * (0.55 + 0.45 * detail)
# a soft sheen across the upper third, as on Hearthstone's own button
sheen = np.exp(-((t[..., 0] - 0.22) / 0.14) ** 2)[..., None] * 60
amber = np.clip(amber + sheen, 0, 255)

out = rgb * (1 - k) + amber * k
Image.fromarray(np.dstack([out, alpha]).astype(np.uint8), "RGBA").save(ART / "play-button.tga", compression=None)
print("ok: play-button.tga from tavern-button.tga")
