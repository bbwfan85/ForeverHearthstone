"""Build bright frame silhouettes and an outlined combat impact badge."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math

art = Path(__file__).resolve().parents[1] / 'ForeverHearthstone/Art'
for path in list(art.glob('inhand_*.tga')) + [art / 'inplay_minion.tga']:
    # Legendary dragons and the mulligan cross are overlays on a frame, never a
    # frame of their own, so they have no silhouette to glow.
    if path.stem.endswith('-glow') or 'legendary' in path.stem or 'mulligan' in path.stem:
        continue
    alpha = Image.open(path).convert('RGBA').getchannel('A')
    solid = alpha.point(lambda a: 255 if a > 32 else 0)
    halo = solid.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(3))
    glow = Image.new('RGBA', alpha.size, 'white')
    glow.putalpha(ImageChops.lighter(solid, halo))
    glow.save(path.with_name(path.stem + '-glow.tga'))

im = Image.new('RGBA', (256, 256))
points = []
for i in range(24):
    angle = i * math.pi / 12
    radius = 119 if i % 2 == 0 else 88
    points.append((128 + math.cos(angle)*radius, 128 + math.sin(angle)*radius))
d = ImageDraw.Draw(im)
d.polygon(points, fill=(255, 206, 62, 255))
d.line(points + points[:1], fill=(65, 29, 12, 255), width=10, joint='curve')
im.save(art / 'hit-splat.tga')

shield = Image.new('RGBA',(128,128))
d = ImageDraw.Draw(shield)
points=[(12,15),(64,3),(116,15),(109,77),(90,103),(64,124),(38,103),(19,77)]
d.polygon(points,fill=(155,166,177,255))
d.line(points+points[:1],fill=(41,47,56,255),width=9,joint='curve')
d.line([(23,23),(64,13),(105,23)],fill=(238,242,246,255),width=5)
shield.save(art/'hero-armor.tga')

# The deck's page edges: gilded card edges seen side-on, as the painted decks
# in the reference board's slots show them. Tiled across the stack's thickness
# by the client, so the striations run vertically and the ends are bevelled.
import random
rng = random.Random(3)
pages = Image.new('RGBA', (64, 256))
px = pages.load()
cols = [0.82 + 0.18 * rng.random() for _ in range(64)]
for x in range(64):
    # every 3-4 columns a darker gap between cards
    if x % 4 == 0:
        cols[x] *= 0.72
for x in range(64):
    for y in range(256):
        v = cols[x]
        if y < 6:
            v *= 1.12 - 0.02 * y          # lit top bevel
        elif y > 246:
            v *= 0.72 + 0.02 * (255 - y)  # shadowed foot
        r, g, b = 226 * v, 186 * v, 78 * v
        px[x, y] = (min(255, int(r)), min(255, int(g)), min(255, int(b)), 255)
pages = pages.filter(ImageFilter.GaussianBlur(0.6))
pages.save(art / 'deck-pages.tga')
