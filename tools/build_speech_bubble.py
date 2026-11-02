"""Hearthstone's emote speech balloon (the reply you and your opponent say).

Hearthstone's balloon is white, near-round, with a thin dark outline and a
short tail pointing back at the hero who spoke; the words are black. The
emote wheel keeps its cream plaques -- those are buttons, this is speech.

One texture, tail at the BOTTOM-LEFT (your hero is below and to the left of
your balloon). The opponent's balloon is the same file flipped top to bottom
in SetTexCoord. Original procedural artwork, drawn at 4x and downsampled.

  python tools/build_speech_bubble.py   -> ForeverHearthstone/Art/speech-bubble.tga
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "ForeverHearthstone" / "Art" / "speech-bubble.tga"
W, H, S = 512, 256, 4
# The balloon's body in the 512x256 canvas; Board.SPEECH_BODY mirrors this.
BODY = (34, 10, 502, 190)
TAIL = [(92, 160), (168, 178), (16, 246)]


def shape(grow=0):
    m = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = [v * S for v in BODY]
    d.ellipse((x0 - grow, y0 - grow, x1 + grow, y1 + grow), fill=255)
    tail = [(x * S, y * S) for x, y in TAIL]
    if grow:
        cx = sum(p[0] for p in tail) / 3; cy = sum(p[1] for p in tail) / 3
        tail = [(cx + (x - cx) * (1 + grow / 120), cy + (y - cy) * (1 + grow / 120)) for x, y in tail]
    d.polygon(tail, fill=255)
    return m


def main():
    outline = shape(grow=5 * S)          # the dark rim
    fill = shape()                       # the white face inside it
    # face: white, a soft cool shade toward the bottom, as the game lights it
    face = Image.new("RGBA", (W * S, H * S))
    fd = ImageDraw.Draw(face)
    for y in range(H * S):
        t = y / (H * S)
        c = round(255 - 22 * t ** 1.6)
        fd.line([(0, y), (W * S, y)], fill=(c, c, min(255, c + 2), 255))
    shadow = outline.filter(ImageFilter.GaussianBlur(6 * S)).point(lambda a: a * 0.45)
    im = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 255)); sh.putalpha(ImageChops.offset(shadow, 0, 3 * S))
    im.alpha_composite(sh)
    rim = Image.new("RGBA", im.size, (38, 30, 24, 255)); rim.putalpha(outline)
    im.alpha_composite(rim)
    face.putalpha(fill)
    im.alpha_composite(face)
    im = im.resize((W, H), Image.Resampling.LANCZOS)
    im.save(OUT)
    print("wrote", OUT.relative_to(ROOT), im.size)


if __name__ == "__main__":
    main()
