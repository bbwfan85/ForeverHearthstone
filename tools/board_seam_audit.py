"""Audit the composited boards corner by corner against their own screenshots.

For each board in composite_boards.SOURCES this registers the screenshot onto
the reference exactly as the build does, warps it into the board's frame, and
writes, for each corner and rail, the shipped texture beside the warped
screenshot -- so a seam, a clipped overhang or a patch of the reference's
Orgrimmar ground showing through is visible at a glance (docs/24).

    python tools/board_seam_audit.py            -> tools/board-audit/<board>.png

Grey in the screenshot column is where the screenshot has no pixels.
"""
from pathlib import Path
import io, sys
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import composite_boards as C  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "board-audit"
REGIONS = {  # (x0, x1, y0, y1) fractions of the 2048x1024 canvas, y from the top
    "top-left": (0.0, 0.40, 0.0, 0.36),
    "top-right": (0.60, 1.0, 0.0, 0.36),
    "bottom-left": (0.0, 0.40, 0.60, 1.0),
    "bottom-right": (0.60, 1.0, 0.60, 1.0),
    "left-rail": (0.0, 0.20, 0.20, 0.80),
    "right-rail": (0.80, 1.0, 0.20, 0.80),
}


def warped_source(name, base):
    spec = C.SOURCES[name]
    source = Image.open(io.BytesIO(C._download(spec["url"]))).convert("RGB")
    G, fit = C.register(base, source, spec["start"])
    grey = Image.new("RGBA", (C.W, C.H), (90, 90, 90, 255))
    warped = source.convert("RGBA").transform((C.W, C.H), Image.Transform.PERSPECTIVE, tuple(G.flatten()[:8]),
                                              resample=Image.Resampling.BICUBIC)
    grey.alpha_composite(warped)
    return grey.convert("RGB"), fit


def main(names):
    OUT.mkdir(exist_ok=True)
    base = C.empty_deck_slots(Image.open(C.ART / "orgrimmar_clean.tga"))
    for name in names or C.SOURCES:
        shipped = Image.open(C.ART / f"board_{name}.tga").convert("RGB")
        src, fit = warped_source(name, base)
        tiles = []
        for label, (x0, x1, y0, y1) in REGIONS.items():
            box = (int(x0 * C.W), int(y0 * C.H), int(x1 * C.W), int(y1 * C.H))
            a, b = shipped.crop(box), src.crop(box)
            t = Image.new("RGB", (a.width * 2 + 12, a.height + 24), (20, 14, 10))
            t.paste(a, (0, 24)); t.paste(b, (a.width + 12, 24))
            ImageDraw.Draw(t).text((4, 4), f"{name} {label}: shipped | screenshot", fill=(255, 210, 120))
            tiles.append(t)
        w = max(t.width for t in tiles)
        sheet = Image.new("RGB", (w, sum(t.height + 8 for t in tiles)), (0, 0, 0))
        y = 0
        for t in tiles:
            sheet.paste(t, (0, y)); y += t.height + 8
        sheet.save(OUT / f"{name}.png")
        print(name, fit, OUT / f"{name}.png")


if __name__ == "__main__":
    main(sys.argv[1:])
