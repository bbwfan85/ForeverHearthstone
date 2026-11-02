"""Put a labelled 0..1 grid over an image, so a board can be measured by eye.

    python tools/grid_overlay.py stormwind.jpg stormwind-grid.png

Board calibration needs three numbers per board: the left and right edges of
the pale playing surface, and the height of the seam across its middle. There
is no reliable way to find them automatically -- the boards are illustrations,
the surface is a different colour and shape on each one, and a threshold that
works on a bright tavern floor walks off the edge of a dark one.

So the numbers come from an eye, and this makes using one cheap. Read the
labels off the lines, put them in tools/board_calibration.json, and
tools/fetch_art.py does the rest. Same discipline as `/fh icons`: where nothing
can verify it but a person, make the person's job one glance.

X labels run along the top. Y labels run up the left side and are measured from
the BOTTOM, which is the convention the calibration file and Layout.lua use.
"""
from pathlib import Path
import sys

from PIL import Image, ImageDraw

STEP = 20  # lines every 1/20, heavier every 1/4


def main():
    src = Path(sys.argv[1])
    out = Path(sys.argv[2] if len(sys.argv) > 2 else src.stem + "-grid.png")
    image = Image.open(src).convert("RGB")
    # A fixed working size keeps the labels legible whatever the source is.
    image = image.resize((1200, int(1200 * image.size[1] / image.size[0])))
    draw = ImageDraw.Draw(image)
    W, H = image.size

    for i in range(1, STEP):
        heavy = i % 5 == 0
        x = W * i / STEP
        draw.line([(x, 0), (x, H)], fill=(0, 255, 255) if heavy else (255, 0, 255))
        draw.text((x + 2, 4), "%.2f" % (i / STEP), fill=(255, 255, 0))
        y = H * i / STEP
        draw.line([(0, y), (W, y)], fill=(0, 255, 255) if heavy else (255, 0, 255))
        # y is labelled from the bottom, matching board_calibration.json
        draw.text((4, y + 2), "%.2f" % (1 - i / STEP), fill=(0, 255, 0))

    image.save(out)
    print("wrote %s" % out)
    print("Read off, for tools/board_calibration.json:")
    print("  surface_x0  left edge of the pale playing surface")
    print("  surface_x1  right edge of it")
    print("  seam_y      the seam running across its middle (measured from the bottom)")


if __name__ == "__main__":
    main()
