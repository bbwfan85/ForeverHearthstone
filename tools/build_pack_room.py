"""Build pack-room.tga: Hearthstone's Open Packs room, whole (docs/16).

The source (tools/menu-assets/openpacksbackground.png, from
Rymedy/hearthstone-web -- see Art/menu-media-report.json) is the real room:
the purple tray your packs sit in, the wooden frame, the painted "Open Packs"
plaque and the stone well you drop a pack into. The addon used only the well,
cropped, over a tavern backdrop; this keeps the room and removes the two
things in it the addon does not have:

* the Shop button at the foot of the tray -- the tray above it is plain, so
  it is copied down over it (feathered);
* a sliver of the Back button along the bottom-right edge.

Stored at 2048x1024 (power of two); drawn over the whole window. The well's
centre is at (0.593, 0.517) of the image, which is where cards are dealt.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
src = Image.open(ROOT / 'tools' / 'menu-assets' / 'openpacksbackground.png').convert('RGB')
im = src.copy()


def cover(box, dy):
    """Copy the patch `dy` rows above `box` over it, feathered."""
    x0, y0, x1, y1 = box
    patch = src.crop((x0, y0 - dy, x1, y1 - dy))
    mask = Image.new('L', patch.size, 0)
    ImageDraw.Draw(mask).rectangle((4, 4, patch.width - 5, patch.height - 5), fill=255)
    im.paste(patch, (x0, y0), mask.filter(ImageFilter.GaussianBlur(3)))


cover((12, 640, 205, 840), 240)        # the Shop button
im.paste(src.crop((1120, 850, 1293, 872)), (1120, 877))   # the Back button's top edge (image foot: no feather)
im.resize((2048, 1024), Image.Resampling.LANCZOS).save(ROOT / 'ForeverHearthstone' / 'Art' / 'pack-room.tga')
im.resize((646, 449)).save(ROOT / 'tools' / 'pack-room-preview.png')
print('ok')
