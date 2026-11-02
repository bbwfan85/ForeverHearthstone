"""Draw the computed layout over a board texture, so misalignment is visible.

    lua tools/layout_preview.lua 1600 900 > layout.json
    python tools/layout_preview.py layout.json board1 out.png

The layout solver is fully unit-tested for its own invariants, but no test can
say whether its rects line up with the painted table underneath -- the playing
surface, the hero sockets, the deck slots and the End Turn plaque are all part
of the board illustration. This is the loop that answers that without launching
WoW. Needs Pillow, like tools/fetch_art.py.
"""
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"

# Colour per element, so the overlay is readable rather than a box of lines.
COLOURS = {
    "field": (255, 255, 255, 90),
    "hero": (80, 220, 120, 255),
    "foeHero": (255, 110, 90, 255),
    "heroPower": (120, 200, 255, 255),
    "foeHeroPower": (255, 170, 120, 255),
    "weapon": (200, 180, 90, 255),
    "foeWeapon": (200, 180, 90, 255),
    "deck": (170, 130, 255, 255),
    "foeDeck": (170, 130, 255, 255),
    "endTurn": (255, 230, 60, 255),
    "rope": (255, 90, 40, 255),
    "boardSlots": (90, 230, 140, 255),
    "foeBoardSlots": (255, 120, 100, 255),
    "handSlots": (120, 200, 255, 255),
    "foeHandSlots": (200, 140, 200, 255),
    "manaCrystals": (70, 140, 255, 255),
    "secrets": (240, 220, 90, 255),
    "foeSecrets": (240, 180, 90, 255),
}
SKIP_LABEL = {"dropZones", "secrets", "foeSecrets"}


def main():
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    board = sys.argv[2] if len(sys.argv) > 2 else "board1"
    out = Path(sys.argv[3] if len(sys.argv) > 3 else "layout-preview.png")

    W, H = data["width"], data["height"]
    src = ART / (board + ".tga")
    if src.exists():
        base = Image.open(src).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
    else:
        base = Image.new("RGBA", (W, H), (20, 18, 16, 255))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    def box(r, colour, label=None):
        # Lua's origin is bottom-left; Pillow's is top-left.
        x0, y0 = r["x"], H - r["y"] - r["h"]
        draw.rectangle([x0, y0, x0 + r["w"], y0 + r["h"]], outline=colour, width=2)
        if label:
            draw.text((x0 + 3, y0 + 2), label, fill=colour)

    for name, value in data.items():
        if name in ("width", "height"):
            continue
        colour = COLOURS.get(name, (255, 255, 255, 160))
        if isinstance(value, dict):
            box(value, colour, name)
        else:
            for i, r in enumerate(value):
                box(r, colour, None if name in SKIP_LABEL else ("%s%d" % (name[:4], i + 1)))

    Image.alpha_composite(base, layer).convert("RGB").save(out)
    print("wrote %s (%dx%d over %s)" % (out, W, H, board))


if __name__ == "__main__":
    main()
