"""Build the end-of-game art from Hearthstone's own victory screen (docs/16).

Source: the Hearthstone wiki's "Play mode victory" screenshot (2014, the
classic client): your hero in a gilded arch under a crown, laurels, two
trumpets and two blue banners, a wooden plaque reading "Victory!" across its
foot, over the drained table.

The screen behind the ornament is grey (Hearthstone desaturates the board), so
the gold and blue key out on saturation. Outputs:

  result-ornament.tga    crown, laurels, trumpets, banners and the portrait's
                         arch frame, with a transparent window for the portrait
  result-frame.tga       the arch frame alone (a defeat has no laurels)
  mask-result-arch.tga   the portrait window's shape, for a MaskTexture
  result-plaque.tga      the wooden plaque, its lettering removed
  result-art.json        where the window and plaque sit (UV of the ornament)

Run with the Pillow + numpy Python (see memory: tooling quirks).
"""
from pathlib import Path
import hashlib, json, urllib.request
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'ForeverHearthstone' / 'Art'
URL = ('https://static.wikia.nocookie.net/hearthstone_gamepedia/images/f/f3/'
       'Play_mode_victory.jpg/revision/latest?cb=20140614135606')
CACHE = ROOT / 'tools' / 'menu-assets' / 'Play_mode_victory.jpg'
if not CACHE.exists():
    CACHE.write_bytes(urllib.request.urlopen(URL, timeout=60).read())
data = CACHE.read_bytes()
src = Image.open(CACHE).convert('RGB')
a = np.asarray(src).astype(np.float32) / 255
H, W = a.shape[:2]

BOX = (80, 80, 790, 760)                   # the ornament, screenshot px
CX, CY = 436, 300                          # the arch's centre of curvature
RX, RY = 118, 102                          # window: half width, arch rise
WIN_BOTTOM = 484                           # the window runs under the plaque
RING = 22                                  # the gilded frame round it
PLAQUE = [(241, 489), (616, 489), (643, 498), (638, 540), (645, 583), (619, 595),
          (251, 595), (231, 585), (236, 540), (229, 498)]
LETTERS = (352, 518, 524, 566)
STEM_SEEDS = [(y, x) for y in range(600, 660, 4) for x in range(380, 500, 4)]


def arch(grow):
    """Window (grow=0) or frame outline (grow=RING) as a boolean image."""
    yy, xx = np.mgrid[0:H, 0:W]
    rx, ry = RX + grow, RY + grow
    side = (abs(xx - CX) <= rx) & (yy >= CY) & (yy <= WIN_BOTTOM + grow)
    top = (((xx - CX) / rx) ** 2 + ((yy - CY) / ry) ** 2 <= 1) & (yy < CY)
    return side | top


def connected(mask, seed):
    """The part of `mask` 8-connected to `seed` (row, col), grown by 2px."""
    im = Image.fromarray(mask.astype(np.uint8) * 128).copy()   # fromarray shares a read-only buffer
    ImageDraw.floodfill(im, (seed[1], seed[0]), 255, thresh=0)
    keep = np.asarray(im) == 255
    return np.asarray(Image.fromarray(keep.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0


# ---- the level badge on the frame's lower left: mirror the right side over it
fixed = a.copy()
for y in range(430, 494):
    for x in range(292, 332):
        fixed[y, x] = a[y, 2 * CX - x]

# ---- key: saturated gold and blue in, the grey table out
mx, mn = fixed.max(-1), fixed.min(-1)
sat = (mx - mn) / (mx + 1e-6)
alpha = np.clip((sat - 0.24) / 0.16, 0, 1)
alpha[(mn > 0.5) & (sat < 0.4)] = 0        # the pale glow behind the ornament
alpha[alpha < 0.3] = 0
win, ring = arch(0), arch(RING)
alpha[ring] = 1                            # the frame is dark and silver in places
alpha[win] = 0                             # the portrait shows through
alpha[750:] = 0                            # rewards and "Click to continue"
am = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(3))
alpha = np.asarray(am).astype(np.float32) / 255
alpha[win] = 0
# stray glow is not attached to the ornament; the crossed stems under the
# plaque are their own piece, so they get a seed of their own
keyed = alpha > 0.3
body = connected(keyed, (CY - RY - RING + 3, CX))
for seed in STEM_SEEDS:
    if keyed[seed]:
        body |= connected(keyed, seed)
alpha *= body
# pinholes where a highlight was too pale to key (a closing: small holes only)
solid = Image.fromarray((alpha > 0.3).astype(np.uint8) * 255)
closed = np.asarray(solid.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MinFilter(11))) > 0
alpha[closed & ~win] = np.maximum(alpha[closed & ~win], 1)
rgba = np.dstack([fixed, alpha])
orn = Image.fromarray((rgba * 255).astype(np.uint8), 'RGBA')

frame_only = np.dstack([fixed, (ring & ~win).astype(np.float32)])
frame_only = Image.fromarray((frame_only * 255).astype(np.uint8), 'RGBA')

# ---- the plaque, lettering replaced by the planks either side of it
pl = np.asarray(src).astype(np.float32).copy()
x0, y0, x1, y1 = LETTERS
mid = (x0 + x1) // 2
patch = pl.copy()
patch[y0:y1, x0:mid] = pl[y0:y1, x0 - 82:mid - 82]
patch[y0:y1, mid:x1] = pl[y0:y1, x0 + 82 + (mid - x0):x1 + 82]
feather = Image.new('L', (W, H), 0)
ImageDraw.Draw(feather).rectangle((x0 + 2, y0 + 2, x1 - 3, y1 - 3), fill=255)
feather = np.asarray(feather.filter(ImageFilter.GaussianBlur(2)))[..., None] / 255
pl = pl * (1 - feather) + patch * feather
pmask = Image.new('L', (W, H), 0)
ImageDraw.Draw(pmask).polygon(PLAQUE, fill=255)
pmask = pmask.filter(ImageFilter.GaussianBlur(0.8))
plaque = Image.fromarray(pl.clip(0, 255).astype(np.uint8)).convert('RGBA')
plaque.putalpha(pmask)
pbox = pmask.getbbox()
plaque = plaque.crop(pbox)

# ---- write
bw, bh = BOX[2] - BOX[0], BOX[3] - BOX[1]
orn.crop(BOX).resize((1024, 1024), Image.Resampling.LANCZOS).save(ART / 'result-ornament.tga')
frame_only.crop(BOX).resize((1024, 1024), Image.Resampling.LANCZOS).save(ART / 'result-frame.tga')
plaque.resize((512, 128), Image.Resampling.LANCZOS).save(ART / 'result-plaque.tga')
wx0, wx1, wy0, wy1 = CX - RX, CX + RX, CY - RY, WIN_BOTTOM
m = Image.fromarray((win[wy0:wy1, wx0:wx1] * 255).astype(np.uint8))
white = Image.new('RGBA', m.size, (255, 255, 255, 255)); white.putalpha(m)
white.resize((256, 256), Image.Resampling.LANCZOS).save(ART / 'mask-result-arch.tga')


def uv(x, y):
    return round((x - BOX[0]) / bw, 4), round((y - BOX[1]) / bh, 4)


info = {
    'source': URL, 'sha256': hashlib.sha256(data).hexdigest(),
    'ornament_aspect': round(bw / bh, 4),
    'window': [*uv(wx0, wy0), *uv(wx1, wy1)],
    'plaque': [*uv(pbox[0], pbox[1]), *uv(pbox[2], pbox[3])],
    'letters': [*uv(x0, y0), *uv(x1, y1)],
}
(ART / 'result-art.json').write_text(json.dumps(info, indent=2))
print(json.dumps(info, indent=2))
prev = Image.new('RGBA', (bw, bh), (70, 70, 74, 255))
prev.alpha_composite(orn.crop(BOX))
prev.alpha_composite(plaque, (pbox[0] - BOX[0], pbox[1] - BOX[1]))
prev.convert('RGB').save(ROOT / 'tools' / 'result-art-preview.png')
