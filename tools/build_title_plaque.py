"""Build title-plaque.tga: the stone name plaque from Hearthstone's Open Packs
room, cut out as a 3-slice so every screen can carry its title on it (docs/24).

Source: tools/menu-assets/openpacksbackground.png (Rymedy/hearthstone-web, see
Art/menu-media-report.json). The plaque there reads "Open Packs"; only its two
riveted end caps and a clean run of stone between the left cap and the
lettering are taken, so no lettering is carried over. The middle strip is
stretched at runtime (W.TitlePlaque), the caps keep their shape.

Output: 512x128 RGBA, drawn at 2x the source's pixels. The slice positions are
written to Art/title-plaque.json and mirrored in Widgets.lua (PLAQUE_*).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import json

ROOT = Path(__file__).resolve().parents[1]
src = Image.open(ROOT / 'tools' / 'menu-assets' / 'openpacksbackground.png').convert('RGBA')

# The plaque's outline in the source: an elongated octagon (angled ends).
TOP, BOTTOM, MID = 6, 59, 32
LEFT_TIP, LEFT_SHOULDER = 584, 607
RIGHT_TIP, RIGHT_SHOULDER = 960, 934
mask = Image.new('L', src.size, 0)
ImageDraw.Draw(mask).polygon([
    (LEFT_SHOULDER, TOP), (RIGHT_SHOULDER, TOP), (RIGHT_TIP, MID),
    (RIGHT_SHOULDER, BOTTOM), (LEFT_SHOULDER, BOTTOM), (LEFT_TIP, MID)], fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(0.8))
plaque = src.copy()
plaque.putalpha(mask)

CAP_L = (LEFT_TIP, 660)      # rivet and the start of the stone
MIDDLE = (660, 700)          # clean stone, before the lettering begins
CAP_R = (885, RIGHT_TIP + 1)
pieces = [plaque.crop((a, TOP - 1, b, BOTTOM + 1)) for a, b in (CAP_L, MIDDLE, CAP_R)]
h = pieces[0].height
w = sum(p.width for p in pieces)
strip = Image.new('RGBA', (w, h), (0, 0, 0, 0))
x = 0
for p in pieces:
    strip.alpha_composite(p, (x, 0))
    x += p.width

SCALE = 2
strip = strip.resize((w * SCALE, h * SCALE), Image.Resampling.LANCZOS)
canvas = Image.new('RGBA', (512, 128), (0, 0, 0, 0))
canvas.alpha_composite(strip, (0, 0))
out = ROOT / 'ForeverHearthstone' / 'Art' / 'title-plaque.tga'
canvas.save(out)

cl, mid = (CAP_L[1] - CAP_L[0]) * SCALE, (MIDDLE[1] - MIDDLE[0]) * SCALE
meta = {
    'source': 'tools/menu-assets/openpacksbackground.png (Rymedy/hearthstone-web; Art/menu-media-report.json)',
    'canvas': [512, 128],
    'u': [0, cl / 512, (cl + mid) / 512, strip.width / 512],
    'v': [0, strip.height / 128],
    'cap_aspect': cl / strip.height,
}
(ROOT / 'ForeverHearthstone' / 'Art' / 'title-plaque.json').write_text(json.dumps(meta, indent=2))
print(json.dumps(meta))
