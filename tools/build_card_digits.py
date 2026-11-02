"""Build the numeric card atlas. Only raster glyphs are shipped, not the font.

Run with Pillow and a TrueType font path; defaults to the shipped Coustard Black
(tools/fetch_fonts.py), whose heavy LINING figures stand in for Hearthstone's.
Each glyph occupies one 64x128 cell in a 1024x128 power-of-two texture.
Standalone transparent-edged cells support full-card UV overlays at runtime.
"""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
font_path = sys.argv[1] if len(sys.argv) > 1 else str(root / 'ForeverHearthstone/Art/Fonts/Coustard-Black.ttf')
font = ImageFont.truetype(font_path, 82)
atlas = Image.new('RGBA', (1024, 128))
for i, ch in enumerate('0123456789-'):
    glyph = Image.new('RGBA', (128, 160))
    ImageDraw.Draw(glyph).text((12, 8), ch, font=font, fill='white', stroke_width=6,
                              stroke_fill=(20, 15, 10, 255))
    glyph = glyph.crop(glyph.getbbox())
    # Old-style numerals (Georgia's) differ in height; center actual ink and
    # normalize digit height, not font metric boxes, whatever the face.
    height = 64 if ch != '-' else 10
    width = min(50, round(glyph.width * height / glyph.height))
    glyph = glyph.resize((width, height), Image.Resampling.LANCZOS)
    atlas.alpha_composite(glyph, (i*64+(64-glyph.width)//2, (128-glyph.height)//2))
out = root / 'ForeverHearthstone/Art/card-digits.tga'
atlas.save(out)
for i in range(11):
    atlas.crop((i*64, 0, (i+1)*64, 128)).save(out.with_name(f'card-digit-{i}.tga'))
print(out)
