"""Repair the bare, smeared corner patches on the composited boards (docs/13).

tools/composite_boards.py builds each board from a gameplay screenshot warped
onto the clean reference table. Where a screenshot runs out, or had the hand
printed over it, the compositor could only stretch or inpaint, and three
defects are baked into every board:

  * a flat grey smudge under your hand's left edge, between the corner scenery
    and your hero's alcove (the inpainted SKETCH_UNDER_HAND patch);
  * a stretched blur across the left margin beside the bottom-left scenery,
    where the screenshot's edge was extended outward;
  * blocky orange stair-steps in the extreme bottom-left corner.

The table is mirror-symmetric about x = 1008 on the 2048x1024 canvas (measured
by correlating the reference's rim, left against right), and the right-hand
side of every board is clean in those rows. So each defect is replaced by its
MIRROR IMAGE from the right, but only where the pixels are actually smeared --
measured as low local detail -- and with a feathered edge, so the detailed
scenery that overhangs those regions is left exactly as it was.

Idempotent: a repaired region is detailed, so a second run changes nothing.
Run by composite_boards.py after compositing; standalone:
    python tools/repair_board_corners.py
"""
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
AXIS2 = 2016                         # twice the mirror axis, in canvas pixels
BOARDS = ["board_orgrimmar", "board_stormwind", "board_stranglethorn"]

# (x0, y0, x1, y1) regions to repair, and the detail below which a pixel is
# counted as smeared. The corner junk is replaced regardless of detail.
REGIONS = [
    {"name": "under-hand smudge", "box": (460, 850, 730, 955), "detail": 7.0},
    {"name": "left margin blur", "box": (0, 600, 250, 1024), "detail": 5.0},
]
FORCED = [(0, 870, 90, 1024)]        # the stair-step junk
# the right-hand mana readout gem (x on the right, before mirroring), and how
# far along the straight trough its replacement is sampled
GEM_ROWS, GEM_COLS, GEM_SHIFT = (905, 972), (1282, 1412), 135


def detail_map(rgb):
    """Local detail: the blurred magnitude of a Laplacian. A smear or an
    inpainted fill is near zero; painted scenery and the stone rim are not."""
    grey = Image.fromarray(rgb.mean(axis=2).astype("uint8"))
    lap = np.asarray(grey.filter(ImageFilter.Kernel((3, 3), [0, 1, 0, 1, -4, 1, 0, 1, 0], 1, 128))) \
        .astype(np.float64) - 128
    mag = Image.fromarray(np.abs(lap).clip(0, 255).astype("uint8"))
    return np.asarray(mag.filter(ImageFilter.GaussianBlur(6))).astype(np.float64)


def repair(path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.float64)
    h, w, _ = a.shape
    det = detail_map(a)
    mask = np.zeros((h, w))
    for r in REGIONS:
        x0, y0, x1, y1 = r["box"]
        sub = det[y0:y1, x0:x1]
        mask[y0:y1, x0:x1] = np.maximum(mask[y0:y1, x0:x1], (sub < r["detail"]).astype(np.float64))
    for x0, y0, x1, y1 in FORCED:
        mask[y0:y1, x0:x1] = 1
    # close small holes, then feather, so the seam is invisible
    m = Image.fromarray((mask * 255).astype("uint8"))
    m = m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(5))
    k = np.asarray(m).astype(np.float64)[..., None] / 255
    xs = np.clip(AXIS2 - np.arange(w), 0, w - 1)
    mirrored = a[:, xs, :]
    #  Mirrored, the rim under the smudge carries the right-hand mana readout's
    #  blue gem, which has no twin on the left. The trough it sits in runs
    #  straight, so the gem's columns are taken from the plain trough just
    #  beyond it instead.
    src = mirrored.copy()
    gy0, gy1 = GEM_ROWS
    gx0, gx1 = GEM_COLS
    for x in range(w):
        mx = AXIS2 - x
        if gx0 <= mx < gx1:
            src[gy0:gy1, x] = a[gy0:gy1, min(w - 1, mx + GEM_SHIFT)]
    out = a * (1 - k) + src * k
    changed = float((k[..., 0] > 0.5).mean())
    Image.fromarray(out.clip(0, 255).astype("uint8"), "RGB").save(path)
    return changed


def main():
    report = {}
    for name in BOARDS:
        p = ART / (name + ".tga")
        if p.exists():
            report[name] = round(repair(p), 5)
    print("repaired (fraction of canvas replaced):", json.dumps(report))
    return report


if __name__ == "__main__":
    main()
