"""Rasterize full-canvas UVs exported by badge_preview.lua (no WoW renderer).

luajit tools/badge_preview.lua > tools/badge-preview.tsv
python tools/badge_preview.py
"""
import csv
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
rows = list(csv.DictReader((root/'tools/badge-preview.tsv').open(encoding='utf-8-sig'), delimiter='\t'))
out = Image.new('RGBA', (1120, 1140), '#33312c')
groups = {}
for row in rows:
    groups.setdefault(int(row['sample']), []).append(row)
for sample, layers in groups.items():
    angle = float(layers[0]['angle'])
    card = None
    for row in layers:
        path = root / row['texture'].replace('Interface\\AddOns\\', '').replace('\\','/')
        source = Image.open(path).convert('RGBA')
        w,h = int(float(row['width'])),int(float(row['height']))
        l,r,t,b = (float(row[k]) for k in ('left','right','top','bottom'))
        layer = source.transform((w,h), Image.Transform.AFFINE,
            ((r-l)*source.width/w,0,l*source.width,0,(b-t)*source.height/h,t*source.height),
            resample=Image.Resampling.BICUBIC)
        # Rotate regions individually, as well as testing shared bounds in Lua.
        layer = layer.rotate(angle*180/3.141592653589793, Image.Resampling.BICUBIC, expand=True)
        if card is None:
            card = Image.new('RGBA', layer.size)
        card.alpha_composite(layer)
    x,y = ((sample-1)%4)*280,((sample-1)//4)*380
    out.alpha_composite(card,(x+(280-card.width)//2,y+25))
    ImageDraw.Draw(out).text((x+20,y+355),f"{layers[0]['card']}  {angle:+.2f} rad",fill='white')
out.convert('RGB').save(root/'tools/badge-preview.png')

# Transparent borders guarantee UV overflow cannot repeat another digit.
for i in range(11):
    alpha=Image.open(root/f'ForeverHearthstone/Art/card-digit-{i}.tga').getchannel('A')
    box=alpha.getbbox()
    assert box and box[0]>0 and box[1]>0 and box[2]<alpha.width and box[3]<alpha.height
    assert abs((box[0]+box[2])/2-alpha.width/2)<=0.5
    assert abs((box[1]+box[3])/2-alpha.height/2)<=0.5
print('Rendered 12 card/rotation cases; all 11 glyph files have centered ink and transparent margins.')
