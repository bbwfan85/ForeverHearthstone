"""Rebuild the Orgrimmar board from its full-resolution painting (docs/24).

The composited Orgrimmar board (composite_boards.py) took its corners from a
2013 gameplay screenshot, blended onto the uncoloured concept sketch: a soft
cut down the bottom-left banner, a red smear beside it, and the sketch's grey
spike showing through beside the enemy's mana (reported with screenshots).

But the repository holds Orgrimmar ITSELF at full resolution -- orgrimmar.tga
(from orgrimar_board.jpg, 3840x2281), the same painting as the clean reference
and normalised by the same calibration, so the two register to within a couple
of pixels. It is coloured and whole; only its sockets are filled in for a
match in progress: two heroes, two mana readouts and a crystal, two decks and
"Waiting..." on the plaque.

So the board is that painting, with just those sockets taken from the
composited board (where the heroes' alcoves are bare, the deck slots emptied
and the readouts blank -- the client draws all of those live). Feathered.
The painting's copyright notice is left exactly as it is.

Run after composite_boards.py (which calls it):  python tools/build_orgrimmar_board.py
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ART = Path(__file__).resolve().parents[1] / "ForeverHearthstone" / "Art"
W, H = 2048, 1024
# The sockets the client fills live, in canvas pixels (x0, y0, x1, y1).
SOCKETS = [
    (898, 76, 1126, 268),      # the enemy hero's alcove
    (898, 684, 1126, 882),     # yours
    (1262, 18, 1392, 68),      # the enemy's mana readout
    (1286, 928, 1500, 990),    # your mana readout and the first crystal
    (1726, 222, 1846, 416),    # the enemy's deck slot
    (1726, 508, 1846, 712),    # yours
    (1612, 436, 1792, 506),    # the End Turn plaque ("Waiting..." painted on it)
]


def main():
    painting = Image.open(ART / "orgrimmar.tga").convert("RGB")
    composited = Image.open(ART / "board_orgrimmar.tga").convert("RGB")
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    for box in SOCKETS:
        d.rounded_rectangle(box, radius=10, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(4))
    out = Image.composite(composited, painting, mask)
    out.save(ART / "board_orgrimmar.tga", compression=None)
    changed = float((np.abs(np.asarray(out).astype(int) - np.asarray(composited).astype(int)).sum(2) > 12).mean())
    print(f"board_orgrimmar: rebuilt from the painting ({changed:.1%} of the canvas changed)")
    return round(changed, 5)


if __name__ == "__main__":
    main()
