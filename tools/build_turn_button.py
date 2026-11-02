"""Build the End Turn button from the plaque painted on the table (docs/25).

Every board paints the same stone plaque on the right-hand rail, reading
"Waiting...". The button used to be lifted from an old 2048px capture of the
live table and drawn 10% wider and 34% taller than that plaque so it would hide
it: a blurry, thick-rimmed block. This cuts the plaque itself out of the full
3840x2281 painting (org_clean_board.jpg), along its own dark outline, so the
button IS the plaque, drawn exactly over it:

* the outline is found by flooding in from the crop's edges over everything
  that is not the plaque's dark rim; spurs (the crack in its top edge, the
  rail's seam below) are opened away;
* "Waiting..." (white letters with a dark edge on the gold face) is filled by
  diffusion from the surrounding gold, plus a soft mottle;
* your turn: the gold lifted to Hearthstone's bright END TURN yellow;
  their turn: the face drained to a dull grey-gold.

Outputs (512x256, the plaque filling the texture):
  turn-button.tga, turn-button-enemy.tga
and prints the plaque's rect as fractions of the picture, for Layout.lua
(ENDTURN_CX/_W/_H/_DY), and the face's box as fractions of the button, for
Board.lua's label box.

Run with the Pillow + numpy Python (see memory: tooling quirks).
"""
from collections import deque
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'ForeverHearthstone' / 'Art'
SRC = ROOT / 'ForeverHearthstone' / 'org_clean_board.jpg'
AREA = (2957, 912, 3400, 1163)          # painting px around the plaque
SEAM_Y = 0.545                          # Layout.lua: seam, from the bottom

img = Image.open(SRC).convert('RGB')
PW, PH = img.size
a = np.asarray(img.crop(AREA)).astype(np.float32)
lum = a @ np.array([.299, .587, .114], np.float32)
h, w = lum.shape

# --- the plaque: everything the outside cannot reach without crossing its rim
dark = lum < 75
seen = np.zeros((h, w), bool)
q = deque([(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)])
for y, x in q:
    seen[y, x] = True
while q:
    y, x = q.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and not dark[ny, nx]:
            seen[ny, nx] = True
            q.append((ny, nx))
mask = Image.fromarray((~seen).astype(np.uint8) * 255)
mask = mask.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.MaxFilter(9))
m = np.asarray(mask) > 127
# drop any spur left: keep rows and columns that are a real part of the body
rows = m.sum(1) > m.sum(1).max() * 0.25
cols = m.sum(0) > m.sum(0).max() * 0.25
m &= rows[:, None] & cols[None, :]
ys, xs = np.nonzero(m)
l, t, r, b = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
mask = Image.fromarray(m.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(0.9))

# --- the face and its lettering
R, G, B = a[..., 0], a[..., 1], a[..., 2]
gold = (R > 150) & (G > 95) & (B < 120) & (R - B > 80)


def fill_holes(solid):
    """Everything the crop's edge cannot reach without crossing `solid`."""
    out = np.zeros(solid.shape, bool)
    q = deque([(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)])
    for y, x in q:
        out[y, x] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not out[ny, nx] and not solid[ny, nx]:
                out[ny, nx] = True
                q.append((ny, nx))
    return ~out


# the face's hull: gold with its holes (the letters) filled
closed = np.asarray(Image.fromarray(gold.astype(np.uint8) * 255)
                    .filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))) > 127
hull = fill_holes(closed & m)
hull = np.asarray(Image.fromarray(hull.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(3))
                  .filter(ImageFilter.MaxFilter(3))) > 127
inner = np.asarray(Image.fromarray(hull.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(7))) > 127
ink = inner & ~gold
ink = np.asarray(Image.fromarray(ink.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 127
ink &= hull

fill = a.copy()
known = ~ink
for _ in range(600):
    if known.all():
        break
    acc = np.zeros_like(fill)
    cnt = np.zeros(known.shape, np.float32)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
        k = np.roll(np.roll(known, dy, 0), dx, 1)
        v = np.roll(np.roll(fill, dy, 0), dx, 1)
        acc += v * k[..., None]
        cnt += k
    grow = (~known) & (cnt > 0)
    fill[grow] = acc[grow] / cnt[grow][:, None]
    known |= grow
smooth = np.asarray(Image.fromarray(fill.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))).astype(np.float32)
fill[ink] = smooth[ink]
rng = np.random.default_rng(7)
noise = rng.normal(0, 1, ink.shape).astype(np.float32)
noise = np.asarray(Image.fromarray(((noise * 40) + 128).clip(0, 255).astype(np.uint8))
                   .filter(ImageFilter.GaussianBlur(1.4))).astype(np.float32) - 128
fill[ink] += (noise[ink] * 0.5)[:, None] * np.array([1.0, 0.85, 0.3], np.float32)

faceA = np.asarray(Image.fromarray(hull.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32)[..., None] / 255

# your turn: the painted gold lifted to END TURN's bright yellow
bright = fill * np.array([1.08, 1.13, 0.72], np.float32) + np.array([10, 8, 0], np.float32)
live = fill * (1 - faceA) + bright * faceA
# their turn: drained grey-gold
grey = fill @ np.array([.299, .587, .114], np.float32)
dull = np.stack([grey * .62 + 18, grey * .58 + 14, grey * .50 + 8], -1)
enemy = fill * (1 - faceA) + dull * faceA

box = (l, t, r, b)
for name, rgb in (('turn-button', live), ('turn-button-enemy', enemy)):
    im = Image.fromarray(rgb.clip(0, 255).astype(np.uint8)).convert('RGBA')
    im.putalpha(mask)
    im.crop(box).resize((512, 256), Image.Resampling.LANCZOS).save(ART / f'{name}.tga')

prev = Image.new('RGBA', (720, 190), (60, 45, 30, 255))
for i, name in enumerate(('turn-button', 'turn-button-enemy')):
    prev.alpha_composite(Image.open(ART / f'{name}.tga').resize((342, 171), Image.Resampling.LANCZOS), (10 + 360 * i, 10))
prev.save(ROOT / 'tools' / 'turn-button-preview.png')

X0, Y0 = AREA[0] + l, AREA[1] + t
X1, Y1 = AREA[0] + r, AREA[1] + b
cy_from_bottom = 1 - (Y0 + Y1) / 2 / PH
print('plaque px', (X0, Y0, X1, Y1))
print('ENDTURN_CX = %.4f  ENDTURN_W = %.4f  ENDTURN_H = %.4f  ENDTURN_DY = %.4f' % (
    (X0 + X1) / 2 / PW, (X1 - X0) / PW, (Y1 - Y0) / PH, cy_from_bottom - SEAM_Y))
fy, fx = np.nonzero(hull[t:b, l:r])
bw, bh = r - l, b - t
print('face box %.2f-%.2f x, %.2f-%.2f y' % (fx.min() / bw, fx.max() / bw, fy.min() / bh, fy.max() / bh))
