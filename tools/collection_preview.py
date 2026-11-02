"""Render exported WoW stub regions. Approximation, not a live client screenshot."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageChops
import json,re,sys,textwrap,os
ROOT=Path(__file__).resolve().parents[1]
OUTPUT=Path(os.environ.get('FH_PREVIEW_DIR',str(ROOT/'tools')))
cache={}
def texture(path):
    path=path.replace('Interface\\AddOns\\','').replace('\\','/')
    p=ROOT/path
    if not p.exists(): return None
    if path not in cache: cache[path]=Image.open(p).convert('RGBA')
    return cache[path]
layers={'BACKGROUND':0,'BORDER':1,'ARTWORK':2,'OVERLAY':3,'HIGHLIGHT':4}
for name in sys.argv[1:]:
    scene=json.loads((OUTPUT/f'{name}.json').read_text(encoding='utf-8'))
    im=Image.new('RGBA',(scene['w'],scene['h']),(24,15,11,255))
    for item in sorted(scene['items'],key=lambda o:(o['level'],layers.get(o['layer'],0))):
        x,y,w,h=[round(item[k]) for k in ('x','y','w','h')]
        if w<1 or h<1:continue
        color=item['color']; opacity=item['alpha']*(color[3] if len(color)>3 else 1)
        if 'text' in item:
            if opacity <= 0.01: continue   # an invisible label (e.g. a card's plain body under its rich text)
            text=re.sub(r'\|c[0-9a-fA-F]{8}|\|r','',item.get('text',''))
            text=re.sub(r'<[^>]+>','',text)
            size=max(6,round(item['font'][1]))
            # Draw with the addon's own shipped face when it has one; the
            # client's built-in fonts are not on disk, so Georgia stands in.
            shipped=ROOT/str(item['font'][0]).replace('Interface\\AddOns\\','').replace('\\','/')
            font=ImageFont.truetype(str(shipped) if shipped.suffix.lower()=='.ttf' and shipped.exists() else (__import__('os').environ.get('FH_FALLBACK_FONT','C:/Windows/Fonts/georgia.ttf')),size)
            draw=ImageDraw.Draw(im);lines=[]
            for line in text.split('\n'):
                lines+=(textwrap.wrap(line,width=max(1,int(w/(size*.52)))) or ['']) if item.get('wrap') else [line]
            lineh=size+2;yy=y if item['valign']=='TOP' else y+max(0,(h-len(lines)*lineh)/2)
            for line in lines[:max(1,int(h/lineh))]:
                align=item['justify'];xx=x if align=='LEFT' else x+w if align=='RIGHT' else x+w/2
                anchor='lt' if align=='LEFT' else 'rt' if align=='RIGHT' else 'mt'
                outline='OUTLINE' in (item['font'][2] if len(item['font'])>2 else '')
                draw.text((xx,yy),line,font=font,fill=tuple(round(v*255) for v in color[:3]),anchor=anchor,stroke_width=1 if outline else 0,stroke_fill='#23170d');yy+=lineh
            continue
        src=texture(item['texture']) if item.get('texture') else None
        if src:
            uv=item.get('uv') or [0,1,0,1]
            if len(uv)==8:   # SetTexCoord's corner form (UL, LL, UR, LR): rotations and flips
                W_,H_=src.width,src.height
                quad=(uv[0]*W_,uv[1]*H_,uv[2]*W_,uv[3]*H_,uv[6]*W_,uv[7]*H_,uv[4]*W_,uv[5]*H_)
                piece=src.transform((w,h),Image.Transform.QUAD,quad,Image.Resampling.BICUBIC)
            else:
                uv=uv if len(uv)==4 else [0,1,0,1]
                piece=src.transform((w,h),Image.Transform.EXTENT,(uv[0]*src.width,uv[2]*src.height,uv[1]*src.width,uv[3]*src.height),Image.Resampling.BICUBIC)
            if item.get('mask'):
                m=texture(item['mask'])
                if m: piece.putalpha(ImageChops.multiply(piece.getchannel('A'),m.resize((w,h)).getchannel('A')))
            rgb=Image.new('RGBA',(w,h),tuple(round(v*255) for v in color[:3])+(255,))
            piece=ImageChops.multiply(piece,rgb)
        elif item.get('solid'):piece=Image.new('RGBA',(w,h),tuple(round(v*255) for v in color[:3])+(255,))
        else:continue
        if opacity<1:piece.putalpha(piece.getchannel('A').point(lambda a:round(a*opacity)))
        im.alpha_composite(piece,(x,y))
    im.convert('RGB').save(OUTPUT/f'{name}.png')
