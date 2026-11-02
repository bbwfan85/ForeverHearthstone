"""The minimap button's icon: Art/minimap-icon.tga (64x64).

The Hearthstone medallion -- the blue swirl in its gold ring -- cut from the
centre of the classic card back (Art/cardback.tga) as a disc. The button draws
WoW's own round minimap border over it, so the icon is only the face.

The medallion's centre is found from the swirl itself (its bright cyan-blue
pixels), not measured by hand. Provenance: Art/minimap-icon-report.json.
"""
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
SIZE = 64
S = 4                     # supersampling for the disc's edge

back = Image.open(ART / "cardback.tga").convert("RGBA")
a = np.asarray(back).astype(np.float32)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
# the glowing cyan swirl (the card's own blue field is duller and greyer),
# looked for only in the middle of the card, where the medallion is
swirl = (b > 200) & (g > 150) & (r < 110) & (b - r > 120)
X0, Y0, X1, Y1 = 78, 200, 178, 320
ys, xs = np.nonzero(swirl[Y0:Y1, X0:X1])
# the card is symmetric, so the medallion is on its centre line; the swirl
# (which curls to one side) gives only the height
cx, cy = back.width / 2, ys.mean() + Y0
# the swirl's own extent sizes the crop: the gold ring sits just outside it
rad = 1.3 * max(xs.max() - xs.min(), ys.max() - ys.min()) / 2

box = (cx - rad, cy - rad, cx + rad, cy + rad)
face = back.crop(tuple(round(v) for v in box)).resize((SIZE * S, SIZE * S), Image.Resampling.LANCZOS)
mask = Image.new("L", face.size, 0)
ImageDraw.Draw(mask).ellipse((S, S, SIZE * S - S, SIZE * S - S), fill=255)
face.putalpha(mask)
icon = face.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
icon.save(ART / "minimap-icon.tga")

report = {"minimap-icon.tga": {"source": "Art/cardback.tga (classic Hearthstone card back)",
                               "centre_px": [round(float(cx), 1), round(float(cy), 1)],
                               "radius_px": round(float(rad), 1), "size": [SIZE, SIZE]}}
(ART / "minimap-icon-report.json").write_text(json.dumps(report, indent=2) + "\n")
prev = Image.new("RGBA", (SIZE * 3, SIZE * 3), (40, 40, 40, 255))
prev.alpha_composite(icon.resize((SIZE * 3, SIZE * 3), Image.Resampling.LANCZOS))
prev.save(ROOT / "tools" / "minimap-icon-preview.png")
print(report)
