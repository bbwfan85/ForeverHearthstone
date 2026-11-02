"""The last pass over the composited boards: the seams round each corner (docs/14).

composite_boards.py and repair_board_corners.py leave three kinds of seam that
read as "missing sections" on the real table:

  * THE BOTTOM-LEFT RIM. Every screenshot has your hand over it, so it is
    half screenshot (a different colour) and half reference (washed out,
    carrying the reference's grey sketch claws), with a hard rectangular cut
    where the corner's scenery stops at the hand.
  * THE LEFT MARGIN beside the bottom-left scenery, where the screenshot ran
    out and its edge was stretched sideways into streaks.
  * GHOST SKETCH along the bottom-right rim, where a feathered corner let
    the reference's uncoloured sketch show through.

The table is mirror-symmetric (repair_board_corners.AXIS2), and its rim,
trough and margins are the same art on both sides, so each seam is replaced
by the board's own mirror image -- except where the pixel is real painted
scenery overhanging it, which is kept exactly. "Real" is decided per region:
anything that differs from the mirror AND carries detail across the row (a
stretched smear carries none), or, over the rim, anything the screenshot
itself painted. Every region is feathered.

Run once over freshly composited boards (composite_boards.py rebuilds them
before calling it); re-running over its own output shifts the shared profile.
Run by composite_boards.py; standalone: python tools/polish_boards.py
"""
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import repair_board_corners as rbc

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
W, H = 2048, 1024

# Where each screenshot's hand began (composite_boards.SOURCES "hand"), in
# canvas pixels, less the corner's feather: right of this the bottom-left rim
# was only ever the reference, so nothing there is kept.
HAND_CUT = {"board_orgrimmar": 578, "board_stormwind": 520, "board_stranglethorn": 620}
# What counts as scenery over the rim, per board: its colour. Orgrimmar's
# claws and banner are warm; Stormwind's blocks are slate BLUE, which is not
# very saturated; Stranglethorn's rim picked up a green haze from the
# rainbow and lies in deep shadow, so only strongly coloured rock and leaf
# count there, and a dark outline is not taken as scenery.
RIM_SCENERY = {"board_orgrimmar": {"sat": 52, "dark": 70}, "board_stormwind": {"sat": 52, "blue": 10, "dark": 70},
               "board_stranglethorn": {"sat": 68, "dark": 0}}

# The bottom-left rim and the wood beneath it, below the corner's scenery.
RIM_BL = [(212, 903), (752, 903), (752, 1004), (212, 1004)]
# The straight run of that rim, whose every column is the same profile. The
# mirror carries the RIGHT-hand corner's own overhang into it (Orgrimmar's
# claws, Stranglethorn's crate and its shadow), so there the rim is rebuilt
# from one profile shared by all three boards -- the median, per row, of their
# mirrored straight runs, which no single board's overhang can move.
RIM_ROWS = (900, 1004)
RIM_STRAIGHT = (245, 600)
PROFILE_COLS = (250, 600)
# The right-hand mana gem's pill, mirrored onto the left trough, where it has
# no twin: painted with the shared profile, inside its own socket.
GEM_PILL = (2016 - 1406, 932, 2016 - 1296, 980)
# The left margin, out to the rim's outer edge, below the clean curtain.
MARGIN_L = [(0, 520), (208, 520), (208, 1024), (0, 1024)]
MARGIN_FEATHER_ROWS = (520, 580)        # the mirror fades in over these rows
# Scenery that really does overhang the left margin (the rest of what is
# there is the screenshot's edge stretched sideways). Hand-traced per board.
MARGIN_KEEP = {
    "board_orgrimmar": [[(196, 748), (212, 742), (212, 832), (194, 826)]],
    "board_stormwind": [[(200, 698), (212, 696), (212, 908), (194, 908), (168, 852),
                         (162, 816), (186, 800), (199, 760)]],
    "board_stranglethorn": [[(172, 700), (212, 688), (212, 928), (176, 922), (158, 880),
                             (150, 800), (156, 742)]],
}
# docs/24: the seam audit (tools/board_seam_audit.py) showed the traced keeps
# above clipping real overhangs -- Orgrimmar's cannon barrel and its smoke,
# Stormwind's lowest blocks -- flat against the rail. The screenshots are
# clean in the whole margin down to the player badge in the corner (JUNK in
# composite_boards.py), whose stretched fill is the only smear; so every board
# keeps its own margin above that, and the mirror fills only the rows below.
MARGIN_OWN_ROWS = 905
for _name in MARGIN_KEEP:
    MARGIN_KEEP[_name] = MARGIN_KEEP[_name] + [[(0, 520), (212, 520), (212, MARGIN_OWN_ROWS - 12), (0, MARGIN_OWN_ROWS - 12)]]
# The lower half of the left rail, smudged where the screenshot ran out. Its
# art is the reference's, which is clean there.
RAIL_L = [(207, 560), (281, 560), (281, 668), (207, 668)]
# The bottom-right rim, above the trough, where sketch claws ghost through.
RIM_BR = [(1296, 898), (1800, 898), (1800, 922), (1296, 922)]
# ...except under Stormwind's gryphon nest, whose real shadow the ghost test
# took for sketch and swapped for mirrored wood (a dark wedge; docs/24).
RIM_BR_RIGHT = {"board_stormwind": 1735}
# Stormwind's bottom-right corner is its screenshot's own bricks from the
# purple wing to the rail (composite_boards.BR_EXTEND): there is no sketch to
# chase, and its mortar is exactly what the ghost and flat-floor tests take for
# sketch, so both passes replaced real bricks with mirrored plain wood -- a
# brown crescent by the wing and a smooth band under the bricks (docs/25).
BR_OWN = {"board_stormwind"}
# ...but the reference's sketch claws still reach down onto the rail below the
# bricks there. The rail is plain stone, so the ghost test is safe on it alone,
# and it runs level, so each row is refilled from that row's own clean run
# (the mirror there carries the bottom-left corner's blue blocks).
RAIL_BR = [(1296, 921), (1800, 921), (1800, 948), (1296, 948)]
RAIL_BR_CLEAN = (1420, 1480)
# Stormwind: the tip of a reference sketch claw left over the bottom-left rim's
# corner (every screenshot has the history icons there). Hand-traced, and
# filled from its surroundings; its mirror does not line up (docs/25).
SKETCH_TIPS = {"board_stormwind": [[(294, 643), (302, 642), (315, 650), (328, 664), (323, 672),
                                    (310, 672), (303, 661), (295, 653)]]}
REFERENCE = ART / "orgrimmar_clean.tga"
# The left end of the bottom-right corner's recess. Every screenshot had your
# hero power there, so the corner stopped at x=1352 and the reference's bare,
# flat floor showed through. Its mirror is the bottom-left corner's painted
# floor. Only flat pixels are replaced, and never the sand of the table.
BR_RECESS = [(1282, 735), (1375, 735), (1375, 905), (1282, 905)]
SURFACE = (900, 1100, 480, 600)
# On Orgrimmar the bottom-right recess's mirror carries a scrap of the
# bottom-left corner's red Horde banner. Its red is re-dyed to the recess's
# own floor, keeping its light and shade, so it reads as floor.
DYE = {"board_orgrimmar": {"box": [(1318, 832), (1392, 832), (1392, 890), (1318, 890)],
                           "floor": (1395, 1440, 775, 805)}}
# The left end of the TOP-right corner's recess: the enemy's mana readout sat
# there in every screenshot, so the reference's grey sketch shows through. Its
# mirror is the top-left corner's painted end. Grey (sketch) pixels only.
TR_RECESS = [(1284, 72), (1352, 72), (1352, 250), (1284, 250)]       # x0, x1, y0, y1: bare sand, for its colour


def poly_mask(polys, feather):
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon(p, fill=255)
    if feather:
        m = m.filter(ImageFilter.GaussianBlur(feather))
    return np.asarray(m).astype(np.float64) / 255


def blur(a, r):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r))).astype(np.float64) / 255


def morph(a, open_px, grow_px):
    im = Image.fromarray((a * 255).astype(np.uint8))
    if open_px:
        im = im.filter(ImageFilter.MinFilter(open_px)).filter(ImageFilter.MaxFilter(open_px))
    if grow_px:
        im = im.filter(ImageFilter.MaxFilter(grow_px))
    return np.asarray(im).astype(np.float64) / 255


def fill_from_edges(img, polys):
    """Fill the traced polygons column by column, between the clean pixels
    above and below: the rail's edge there runs vertically, so it stays sharp."""
    m = poly_mask(polys, 0) > 0.5
    m = morph(m.astype(np.float64), 0, 3) > 0.5
    out = img.copy()
    for x in np.nonzero(m.any(axis=0))[0]:
        ys = np.nonzero(m[:, x])[0]
        top, bot = ys.min() - 1, ys.max() + 1
        t = ((ys - top) / (bot - top))[:, None]
        out[ys, x] = img[top, x] * (1 - t) + img[bot, x] * t
    k = poly_mask(polys, 0)
    k = blur(morph(k, 0, 5), 1.0)[..., None]
    return img * (1 - k) + out * k


def mirror_of(a):
    """The board's own mirror image about the table's axis."""
    xs = np.clip(rbc.AXIS2 - np.arange(W), 0, W - 1)
    return a[:, xs, :]


def rim_profile(mirrors):
    y0, y1 = RIM_ROWS
    c0, c1 = PROFILE_COLS
    cols = np.concatenate([m[y0:y1, c0:c1] for m in mirrors], axis=1)
    return np.median(cols, axis=1)                          # (rows, 3)


def redye(img, dye):
    """Re-dye the strongly red pixels in dye["box"] to the floor's colour
    (sampled from dye["floor"] = x0, x1, y0, y1), keeping each pixel's
    brightness relative to that floor."""
    x0, x1, y0, y1 = dye["floor"]
    floor = np.median(img[y0:y1, x0:x1].reshape(-1, 3), axis=0)
    lum = img.mean(axis=2, keepdims=True)
    dyed = np.clip(floor * (lum / max(1.0, floor.mean())), 0, 255)
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    red = ((r - g > 60) & (r - b > 60)).astype(np.float64)
    k = (poly_mask([dye["box"]], 2) * blur(morph(red, 0, 3), 1.5))[..., None]
    return img * (1 - k) + dyed * k


def polish(name, a, reference, profile):
    path = ART / (name + ".tga")
    mir = mirror_of(a)
    diff = np.sqrt(((a - mir) ** 2).sum(axis=2))
    xs = np.arange(W)[None, :].repeat(H, 0)

    # the rim's source: the mirror, with the gem and any overhang replaced
    y0, y1 = RIM_ROWS
    flat = mir.copy()
    flat[y0:y1] = profile[:, None, :]
    dev = np.zeros((H, W))
    dev[y0:y1] = np.sqrt(((mir[y0:y1] - profile[:, None, :]) ** 2).sum(axis=2)) > 45
    straight = np.zeros((H, W)); straight[:, RIM_STRAIGHT[0]:RIM_STRAIGHT[1]] = 1
    gx0, gy0, gx1, gy1 = GEM_PILL
    k = np.maximum(blur(morph(dev * straight, 0, 5), 2),
                   poly_mask([[(gx0, gy0), (gx1, gy0), (gx1, gy1), (gx0, gy1)]], 3))[..., None]
    rimsrc = mir * (1 - k) + flat * k

    # the rim: keep only the screenshot's own overhanging scenery
    rim = poly_mask([RIM_BL], 3)
    # The rim is desaturated stone; the scenery over it (claws, blocks,
    # leaves, rock) is coloured, and outlined in near-black. Tinted or
    # blurred screenshot rim is neither, so it goes.
    sat = a.max(axis=2) - a.min(axis=2)
    lum = a.mean(axis=2)
    far = np.sqrt(((a - rimsrc) ** 2).sum(axis=2)) > 60
    rule = RIM_SCENERY[name]
    coloured = sat > rule["sat"]
    if "blue" in rule:
        coloured |= (a[..., 2] - a[..., 0]) > rule["blue"]
    real = (coloured | ((lum < rule["dark"]) & far)) & (xs < HAND_CUT[name])
    real = morph(real.astype(np.float64), 0, 3)            # close the outlines in
    real = np.asarray(Image.fromarray((real * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) / 255.0
    ramp = np.clip((HAND_CUT[name] - xs) / 14.0, 0, 1)       # no hard cut at the hand
    keep = blur(morph(real, 5, 0), 1.2) * ramp
    k = rim * (1 - keep)
    out = a * (1 - k[..., None]) + rimsrc * k[..., None]

    # the margin: the mirror, faded in from the clean curtain above
    fy0, fy1 = MARGIN_FEATHER_ROWS
    fade = np.clip((np.arange(H) - fy0) / (fy1 - fy0), 0, 1)[:, None]
    margin = poly_mask([MARGIN_L], 3) * fade
    keep = poly_mask(MARGIN_KEEP.get(name, []), 2)
    k = margin * (1 - keep)
    out = out * (1 - k[..., None]) + mir * k[..., None]

    # the lower left rail, from the reference
    k = poly_mask([RAIL_L], 3)[..., None]
    out = out * (1 - k) + reference * k

    # the bottom-right recess: flat reference floor, not sand, from the mirror
    x0, x1, y0, y1 = SURFACE
    sand = np.median(a[y0:y1, x0:x1].reshape(-1, 3), axis=0)
    sandlike = np.sqrt(((a - sand) ** 2).sum(axis=2)) < 38
    flat = (rbc.detail_map(a) < 9) & ~sandlike
    if name not in BR_OWN:
        k = (poly_mask([BR_RECESS], 4) * blur(morph(flat.astype(np.float64), 5, 7), 4))[..., None]
        out = out * (1 - k) + mir * k

    dye = DYE.get(name)
    if dye:
        out = redye(out, dye)

    # the top-right recess: grey sketch, not sand, from the mirror
    sat = a.max(axis=2) - a.min(axis=2)
    grey = (sat < 34) & ~sandlike
    k = (poly_mask([TR_RECESS], 4) * blur(morph(grey.astype(np.float64), 3, 9), 4))[..., None]
    out = out * (1 - k) + mir * k

    # the bottom-right rim: grey sketch is low-saturation and dark
    sat = a.max(axis=2) - a.min(axis=2)
    ghost = (sat < 28) & (a.mean(axis=2) < 140) & (diff > 40)
    right = RIM_BR_RIGHT.get(name, RIM_BR[1][0])
    rim_br = [(RIM_BR[0][0], RIM_BR[0][1]), (right, RIM_BR[1][1]), (right, RIM_BR[2][1]), (RIM_BR[3][0], RIM_BR[3][1])]
    if name in BR_OWN:
        src = out.copy()
        c0, c1 = RAIL_BR_CLEAN
        src[:, :, :] = np.median(out[:, c0:c1, :], axis=1)[:, None, :]
        zone = RAIL_BR
    else:
        src, zone = mir, rim_br
    k = (poly_mask([zone], 2) * blur(morph(ghost.astype(np.float64), 0, 5), 2))[..., None]
    out = out * (1 - k) + src * k

    if name in SKETCH_TIPS:
        out = fill_from_edges(out, SKETCH_TIPS[name])

    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB").save(path, compression=None)
    return round(float((np.abs(out - a).sum(axis=2) > 12).mean()), 5)


def main():
    report = {}
    reference = np.asarray(Image.open(REFERENCE).convert("RGB")).astype(np.float64)
    boards = {name: np.asarray(Image.open(ART / (name + ".tga")).convert("RGB")).astype(np.float64)
              for name in rbc.BOARDS if (ART / (name + ".tga")).exists()}
    profile = rim_profile([mirror_of(a) for a in boards.values()])
    for name, a in boards.items():
        report[name] = polish(name, a, reference, profile)
    print("polished (fraction of canvas changed):", json.dumps(report))
    return report


if __name__ == "__main__":
    main()
