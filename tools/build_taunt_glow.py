"""Build inplay_minion_taunt-glow.tga: the "can attack" / target glow for a
minion wearing a taunt shield (docs/16).

The ordinary glow (inplay_minion-glow.tga) is a soft ring round the oval
portrait frame. A taunt minion's shield stands out past that oval -- above
it, and down to a point below -- and is drawn over the glow, so the ring was
hidden behind the shield and read as no glow at all. Hearthstone's glow follows
the shield. This one is the same soft ring, traced round the union of the
shield and the frame. The shield's point runs to the frame's own edge, so the
glow's canvas is the frame's 256x256 grown by 32px on every side (320/256 =
1.25 of the frame's size, centred on it), stored at 512x512.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

ART = Path(__file__).resolve().parents[1] / 'ForeverHearthstone' / 'Art'
frame = Image.open(ART / 'inplay_minion.tga').convert('RGBA').getchannel('A')
shield = Image.open(ART / 'inplay_minion_taunt.tga').convert('RGBA').getchannel('A').resize((256, 256), Image.Resampling.LANCZOS)
PAD = 32
sil = Image.new('L', (256 + 2 * PAD, 256 + 2 * PAD), 0)
sil.paste(ImageChops.lighter(frame, shield).point(lambda v: 255 if v > 60 else 0), (PAD, PAD))
# the stock glow reaches ~9px past the frame and fades over ~5px
outer = sil.filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(4))
inner = sil.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(2))
ring = ImageChops.subtract(outer, inner)
glow = Image.new('RGBA', sil.size, (255, 255, 255, 0))
glow.putalpha(ring)
glow.resize((512, 512), Image.Resampling.LANCZOS).save(ART / 'inplay_minion_taunt-glow.tga')
print('ok', ring.getbbox())
