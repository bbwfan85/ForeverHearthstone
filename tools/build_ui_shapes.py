"""Build deterministic alpha masks and geometric UI effects (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / 'ForeverHearthstone/Art'
S = 512
def save(name, draw):
    im = Image.new('RGBA', (S, S))
    draw(ImageDraw.Draw(im))
    im.resize((128, 128), Image.Resampling.LANCZOS).save(OUT / (name + '.tga'))

save('mask-oval', lambda d: d.ellipse((2, 2, 510, 510), fill='white'))
save('mask-rect', lambda d: d.rectangle((0, 0, 512, 512), fill='white'))
def arch(d):
    d.ellipse((2, 2, 510, 420), fill='white')
    d.rectangle((2, 208, 510, 512), fill='white')
save('mask-arch', arch)
save('mask-ring', lambda d: d.rounded_rectangle((10, 10, 502, 502), radius=70, outline='white', width=13))
def shield(d):
    for width, alpha in [(32, 30), (20, 75), (8, 235)]:
        d.ellipse((8, 4, 504, 508), outline=(255, 222, 90, alpha), width=width)
save('status-shield', shield)
def taunt(d):
    pts = [(20, 42), (150, 42), (150, 14), (362, 14), (362, 42), (492, 42), (479, 400), (256, 504), (33, 400), (20, 42)]
    d.line(pts, fill=(40, 37, 32, 255), width=28, joint='curve')
    d.line(pts, fill=(175, 177, 169, 255), width=15, joint='curve')
save('status-taunt', taunt)
save('target-segment', lambda d: d.ellipse((100, 100, 412, 412), fill=(220, 12, 15, 255), outline=(255, 110, 80, 255), width=30))
def reticle(d):
    d.ellipse((95, 95, 417, 417), outline=(235, 12, 18, 255), width=36)
    for xy in [(256, 5, 256, 145), (256, 367, 256, 507), (5, 256, 145, 256), (367, 256, 507, 256)]:
        d.line(xy, fill=(255, 25, 25, 255), width=36)
save('target-reticle', reticle)

# Extract the enclosed transparent window, not the transparent outer margin.
# This follows the installed frame's actual contour instead of guessing an oval.
for name, seed in [('hero_frame', (0.5, 0.45)), ('hero_power', (0.5, 0.5))]:
    source = Image.open(OUT / (name + '.tga')).convert('RGBA')
    alpha = source.getchannel('A')
    region = alpha.point(lambda a: 0 if a < 128 else 255).convert('RGB')
    ImageDraw.floodfill(region, (int(source.width * seed[0]), int(source.height * seed[1])), (255, 0, 0))
    result = Image.new('RGBA', source.size)
    result.putdata([(255, 255, 255, 255 if p == (255, 0, 0) else 0) for p in region.getdata()])
    result.save(OUT / ('mask-' + name + '.tga'))
