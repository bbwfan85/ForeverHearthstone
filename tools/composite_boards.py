"""Build Hearthstone's classic boards by compositing onto the aligned reference.

Hearthstone picks a board at random each match. The four launch boards --
Stormwind, Orgrimmar, Stranglethorn and Pandaria -- share one table: the stone
rim, the hero alcoves and their wings, the rails, the mana trough, the End Turn
plaque and the deck slots are the same art on every board. Only the SCENERY
in the four corners and the margins around the table differ.

The only clean copy of that table we have is the Orgrimmar concept board the
layout is measured against (org_clean_board.jpg); its corner scenery is
uncoloured sketch. The boards themselves exist only as gameplay screenshots,
with heroes, minions, both hands, mana readouts and UI printed over the table.
So each board is built as:

    the clean table          from the reference, with its deck slots emptied
  + that board's corners     from its screenshot, warped onto the reference
  + that board's margins     likewise, where the screenshot is clean

REGISTRATION. The screenshots are rendered through Hearthstone's tilted camera,
so the table is slightly keystoned relative to the flat concept art: separate
x/y scales leave ~15px of error across the board. A perspective transform
(homography) fitted to ~50 feature matches on the shared table structure
aligns every board to within ~2px, and the build fails loudly if one does not.

EMPTY DECK SLOTS. The reference has a gold and a silver deck painted into its
slots. The client draws a live stack that thins as you draw, so the painted
decks are removed: the recess is rebuilt as a stadium whose rim is the real
rim's colour profile read off its clean side, and the banner behind the decks'
overhang is interpolated from the clean rows above and below.

Run by tools/fetch_art.py; standalone: `python tools/composite_boards.py`.
Sources, their hashes and each board's fit are recorded in art-report.json.
"""
import hashlib
import io
import json
from pathlib import Path
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_art  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
W, H = 2048, 1024
WIKI = "https://static.wikia.nocookie.net/"

# name -> screenshot, a starting calibration (tools/board_calibration.json
# semantics) close enough for feature matching to lock on, and where that
# screenshot's hand begins (canonical x), which the bottom-left corner stops at.
SOURCES = {
    "orgrimmar": {"url": WIKI + "hearthstone/images/6/67/OrgrimmarHSGameboard.jpg/revision/latest?cb=20130324192630",
                  "start": [0.17, 0.8425, 0.284, 0.525], "hand": 0.3},
    "stormwind": {"url": WIKI + "hearthstone/images/5/5b/StormwindHSGameboard.jpg/revision/latest?cb=20130324192630",
                  "start": [0.17, 0.8425, 0.285, 0.525], "hand": 0.26},
    "stranglethorn": {"url": WIKI + "hearthstone/images/1/14/STVBoard.jpg/revision/latest?cb=20130524180052",
                      "start": [0.19, 0.8225, 0.3175, 0.545], "hand": 0.31},
}
MAX_RESIDUAL = 2.0   # median feature residual allowed, in half-resolution pixels

# ---------------------------------------------------------------- deck slots

SLOT_AXIS, SLOT_HALF, SLOT_RIM = 1776.5, 25.5, 10
SLOT_PROFILE_ROW, PILLAR_EDGE, OVERHANG = 320, 1813, 1830
SLOTS = [{"top": 246, "bot": 397, "stack": (251, 395)},
         {"top": 531, "bot": 691, "stack": (543, 680)}]


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def empty_deck_slots(img):
    a = np.asarray(img.convert("RGB")).astype(np.float64)
    out = a.copy()
    rng = np.random.default_rng(7)
    profile = [a[SLOT_PROFILE_ROW, int(SLOT_AXIS - SLOT_HALF) - d] for d in range(SLOT_RIM + 4)]
    for s in SLOTS:
        yc0, yc1 = s["top"] + SLOT_HALF, s["bot"] - SLOT_HALF
        cap = a[s["top"] + 2: s["top"] + 6, int(SLOT_AXIS - 12): int(SLOT_AXIS + 12)].reshape(-1, 3)
        dark = np.percentile(cap, 30, axis=0)
        for y in range(s["top"] - SLOT_RIM - 3, s["bot"] + SLOT_RIM + 4):
            for x in range(int(SLOT_AXIS - SLOT_HALF - SLOT_RIM - 3), PILLAR_EDGE):
                cy = min(max(y, yc0), yc1)
                d = np.hypot(x - SLOT_AXIS, y - cy) - SLOT_HALF       # < 0 inside the recess
                if d >= SLOT_RIM + 3:
                    continue
                shade = 0.50 + 0.50 * _smooth(0, 14, max(0.0, -d))   # shadow at the walls
                shade *= 0.85 + 0.15 * _smooth(yc0 - SLOT_HALF, yc0 + 40, y)
                inner = dark * shade + rng.normal(0, 2.0, 3)
                w = 1 - _smooth(SLOT_RIM - 1, SLOT_RIM + 3, d)
                rim = profile[min(max(int(d), 0), len(profile) - 1)] * w + a[y, x] * (1 - w)
                k = _smooth(-0.8, 0.8, d)                            # anti-alias the wall
                out[y, x] = inner * (1 - k) + rim * k
        y0, y1 = s["stack"][0] - 3, s["stack"][1] + 3
        for y in range(y0 + 1, y1):
            t = (y - y0) / (y1 - y0)
            for x in range(int(SLOT_AXIS + SLOT_HALF + SLOT_RIM - 1), OVERHANG):
                if x >= PILLAR_EDGE - 2 or not (s["top"] - SLOT_RIM <= y <= s["bot"] + SLOT_RIM):
                    out[y, x] = a[y0, x] * (1 - t) + a[y1, x] * t + rng.normal(0, 1.2, 3)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))

# ------------------------------------------------------------- registration

HALF, P, R = 2, 20, 28     # match at half resolution; patch half-size; search radius
ZONES = [(0.33, 0.67, 0.00, 0.20), (0.33, 0.67, 0.78, 0.95),   # alcove wings
         (0.095, 0.16, 0.25, 0.80), (0.84, 0.91, 0.14, 0.86)]  # rails
HOLES = [(0.44, 0.56, 0.0, 0.22), (0.44, 0.56, 0.76, 1.0),     # heroes
         (0.56, 0.66, 0.05, 0.20), (0.56, 0.66, 0.78, 0.93),   # hero powers
         (0.105, 0.155, 0.28, 0.72),                           # history icons
         (0.85, 0.905, 0.22, 0.38), (0.85, 0.905, 0.52, 0.68), # deck stacks
         (0.86, 0.9, 0.44, 0.52)]                              # plaque lettering


def _inside(fx, fy, boxes):
    return any(x0 <= fx <= x1 and y0 <= fy <= y1 for x0, x1, y0, y1 in boxes)


def _grad(img):
    g = np.asarray(img.convert("L").filter(ImageFilter.GaussianBlur(1))).astype(np.float64)
    gx = np.zeros_like(g); gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]; gy[1:-1] = g[2:] - g[:-2]
    return np.hypot(gx, gy)


def _norm(p):
    c = p.mean(axis=0); s = np.sqrt(2) / np.mean(np.hypot(*(p - c).T))
    return np.array([[s, 0, -s * c[0]], [0, s, -s * c[1]], [0, 0, 1]])


def _homography(src, dst):
    Ts, Td = _norm(src), _norm(dst)
    a = np.c_[src, np.ones(len(src))] @ Ts.T
    b = np.c_[dst, np.ones(len(dst))] @ Td.T
    rows = []
    for (x, y, _), (u, v, _) in zip(a, b):
        rows.append([-x, -y, -1, 0, 0, 0, u * x, u * y, u])
        rows.append([0, 0, 0, -x, -y, -1, v * x, v * y, v])
    _, _, vt = np.linalg.svd(np.array(rows))
    Hm = np.linalg.inv(Td) @ vt[-1].reshape(3, 3) @ Ts
    return Hm / Hm[2, 2]


def _apply(Hm, pts):
    p = np.c_[pts, np.ones(len(pts))] @ Hm.T
    return p[:, :2] / p[:, 2:3]


def _crop_box(size, p):
    """normalise_board's crop of a source image, as (left, top, width, height)."""
    fetch_art.CALIBRATION["boards"]["_probe"] = dict(zip(("surface_x0", "surface_x1", "surface_y0", "seam_y"), p))
    b, t = fetch_art.CALIBRATION["boards"]["_probe"], fetch_art.CALIBRATION["canonical"]
    Ws, Hs = size
    crop_w = (b["surface_x1"] - b["surface_x0"]) * Ws / (t["surface_x1"] - t["surface_x0"])
    left = b["surface_x0"] * Ws - t["surface_x0"] * crop_w
    crop_h = (b["seam_y"] - b["surface_y0"]) * Hs / (t["seam_y"] - t["surface_y0"])
    top = (1.0 - b["seam_y"]) * Hs - (1.0 - t["seam_y"]) * crop_h
    return int(left), int(top), int(left + crop_w) - int(left), int(top + crop_h) - int(top)


def register(reference, source, start):
    """Perspective map from reference pixels to source pixels, and its fit."""
    fetch_art.CALIBRATION["boards"]["_probe"] = dict(zip(("surface_x0", "surface_x1", "surface_y0", "seam_y"), start))
    rough = fetch_art.normalise_board(source, "_probe").resize((W, H), Image.Resampling.LANCZOS)
    A = _grad(reference.resize((W // HALF, H // HALF)))
    B = _grad(rough.resize((W // HALF, H // HALF)))
    h, w = A.shape
    cands = []
    for y in range(P + R, h - P - R, 12):
        for x in range(P + R, w - P - R, 12):
            if _inside(x / w, y / h, ZONES) and not _inside(x / w, y / h, HOLES):
                cands.append((A[y - P:y + P, x - P:x + P].std(), x, y))
    cands.sort(reverse=True)
    pts = []
    for _, x, y in cands[:160]:
        t = A[y - P:y + P, x - P:x + P]; t = (t - t.mean()) / (t.std() + 1e-6)
        win = B[y - P - R:y + P + R, x - P - R:x + P + R]
        best, bx, by = -1.0, 0, 0
        for dy in range(2 * R + 1):
            for dx in range(2 * R + 1):
                s = win[dy:dy + 2 * P, dx:dx + 2 * P]
                c = float(np.mean(t * (s - s.mean()) / (s.std() + 1e-6)))
                if c > best:
                    best, bx, by = c, dx - R, dy - R
        if best > 0.55:
            pts.append((x, y, x + bx, y + by))
    pts = np.array(pts, dtype=np.float64)
    # an affine start keeps the trimming from chasing a bad first guess
    M, *_ = np.linalg.lstsq(np.c_[pts[:, :2], np.ones(len(pts))], pts[:, 2:], rcond=None)
    Hm = np.eye(3); Hm[:2, :] = M.T
    r = np.hypot(*(_apply(Hm, pts[:, :2]) - pts[:, 2:]).T)
    keep = r < max(2.0, np.percentile(r, 70) * 1.5)
    for _ in range(8):
        Hm = _homography(pts[keep, :2], pts[keep, 2:])
        r = np.hypot(*(_apply(Hm, pts[:, :2]) - pts[:, 2:]).T)
        keep = r < max(1.0, np.percentile(r[keep], 75) * 1.5)
    median = float(np.median(r[keep]))
    # compose: reference px -> rough px (full res) -> source px
    S2 = np.diag([HALF, HALF, 1.0])
    Hf = S2 @ Hm @ np.linalg.inv(S2)
    left, top, cw, ch = _crop_box(source.size, start)
    A2 = np.array([[cw / W, 0, left], [0, ch / H, top], [0, 0, 1]])
    G = A2 @ Hf
    return G / G[2, 2], {"matches": int(len(pts)), "inliers": int(keep.sum()), "residual": round(median, 3)}

# --------------------------------------------------------------- compositing


def _poly(polys, feather):
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon([(x * W, y * H) for x, y in p], fill=255)
    return np.asarray(m.filter(ImageFilter.GaussianBlur(feather))).astype(np.float64) / 255


# What each board takes from its SCREENSHOT, in (x, y-from-top) fractions of
# the canonical board: its four corners of scenery -- sized to cover the
# reference's own sketched corners completely -- and the margins either side
# of the table. Everything else is the reference's clean table. The corners
# stop short of what a screenshot has printed over the table: the history
# rail's icons, both hero powers, the enemy's mana readout, the deck stacks,
# your mana trough and both hands.
def scenery(hand_x, name=None):
    """`hand_x` is where that screenshot's hand begins; the bottom-left corner
    stops just short of it."""
    return BR_EXTEND.get(name, []) + [
        # top-left, down to the first history icon
        # (stops where the red alcove wing begins, so the wing is one colour,
        # with a tongue under it for the reference sketch's spike tip)
        [(0.0, 0.0), (0.342, 0.0), (0.342, 0.125), (0.362, 0.125), (0.372, 0.24), (0.372, 0.265),
         (0.30, 0.305), (0.16, 0.31), (0.155, 0.265), (0.0, 0.265)],
        # top-right, clear of the enemy mana readout and hero power, over the top skull
        # (over the rail it stops higher: the screenshots' decks overhang the
        # top of the slot, and the feathered edge would pick up their gold)
        [(0.67, 0.0), (1.0, 0.0), (1.0, 0.235), (0.90, 0.235), (0.90, 0.212), (0.845, 0.212), (0.845, 0.30),
         (0.70, 0.295), (0.645, 0.245), (0.645, 0.065), (0.67, 0.065)],
        # bottom-left, below the history icons, stopping at your hand
        [(0.0, 0.66), (0.155, 0.66), (0.17, 0.62), (0.31, 0.64), (0.355, 0.72), (0.355, 0.86),
         (hand_x - 0.01, 0.86), (hand_x - 0.01, 1.0), (0.0, 1.0)],
        # bottom-right, below the deck rail, above the mana trough
        [(0.66, 0.64), (0.845, 0.64), (0.845, 0.69), (0.905, 0.69), (0.905, 0.915), (0.66, 0.915)],
        # the margins beside the table
        [(0.0, 0.0), (0.098, 0.0), (0.098, 1.0), (0.0, 1.0)],
        [(0.905, 0.0), (1.0, 0.0), (1.0, 0.93), (0.905, 0.93)],
    ]
# Stormwind's hero power sits left of x=0.632 in its screenshot, so right of
# it, below the power, the screenshot's own bricks and the purple wing's edge
# are clean. Taking them there replaces the reference's bare, flat basin floor
# (a smooth brown crescent beside the bricks; docs/25).
BR_EXTEND = {"stormwind": [[(0.64, 0.70), (0.67, 0.70), (0.67, 0.915), (0.64, 0.915)]]}
# How far from its own surface sand a screenshot pixel may be and still count as
# sand. Stormwind's screenshot has an orange haze on the sand above its
# bottom-left bricks, which the default let through as a pink blotch: the
# colour fit's red gain on sand only partly swapped for the reference's (docs/25).
SAND_SIGMA = {"stormwind": 60.0}
# The inside of the mana trough is always the reference's: every screenshot
# has its crystals printed there, and the corner's feather used to carry their
# ghosts into the trough of every composited board.
TROUGH = [(0.684, 0.912), (0.885, 0.912), (0.885, 0.958), (0.684, 0.958)]
# The screenshot's UI printed in its margins (player badge, clock, options
# gear, debug labels): treated as missing, so its surroundings fill it.
JUNK = [(0.0, 0.05, 0.9, 1.0), (0.0, 0.04, 0.0, 0.04), (0.88, 1.0, 0.93, 1.0)]
# The one patch of the reference's sketched scenery a screenshot cannot
# replace, because every screenshot has your hand over it. Inpainted instead.
SKETCH_UNDER_HAND = (0.255, 0.362, 0.815, 0.93)
# Where a screenshot has no pixels near the reference's corner notice, the
# screenshot's own edge is extended rather than the reference shown through.
OWN_EDGE = (0.0, 0.2, 0.85, 1.0)


def _inpaint(rgb, box, iterations=400):
    """Fill a box from its border by repeated neighbour averaging, with grain."""
    x0, x1, y0, y1 = (int(box[0] * W), int(box[1] * W), int(box[2] * H), int(box[3] * H))
    out = rgb.copy()
    region = out[y0 - 1:y1 + 1, x0 - 1:x1 + 1]
    inner = np.zeros(region.shape[:2], bool); inner[1:-1, 1:-1] = True
    region[inner] = region[~inner].mean(axis=0)
    for _ in range(iterations):
        avg = (np.roll(region, 1, 0) + np.roll(region, -1, 0) + np.roll(region, 1, 1) + np.roll(region, -1, 1)) / 4
        region[inner] = avg[inner]
    rng = np.random.default_rng(11)
    region[inner] += rng.normal(0, 2.5, region[inner].shape)
    # feather the box edge so the fill has no outline
    k = np.ones(region.shape[:2])
    ramp = 8
    for i in range(ramp):
        w = i / ramp
        k[i, :] = np.minimum(k[i, :], w); k[-1 - i, :] = np.minimum(k[-1 - i, :], w)
        k[:, i] = np.minimum(k[:, i], w); k[:, -1 - i] = np.minimum(k[:, -1 - i], w)
    orig = rgb[y0 - 1:y1 + 1, x0 - 1:x1 + 1]
    out[y0 - 1:y1 + 1, x0 - 1:x1 + 1] = region * k[..., None] + orig * (1 - k[..., None])
    return out


def _structure(cover):
    m = np.zeros((H, W), bool)
    for x0, x1, y0, y1 in ((0.36, 0.44, 0.02, 0.2), (0.56, 0.64, 0.02, 0.2),
                           (0.36, 0.44, 0.78, 0.92), (0.56, 0.64, 0.78, 0.92)):
        m[int(y0 * H):int(y1 * H), int(x0 * W):int(x1 * W)] = True
    return m & cover


def _colour_fit(src, base, m):
    """Per-channel GAIN only, from medians over the shared structure. A fitted
    offset as well regresses toward the mean and washes the scenery out."""
    out = src.copy()
    for c in range(3):
        g = np.median(base[..., c][m]) / max(1.0, np.median(src[..., c][m]))
        out[..., c] = src[..., c] * float(np.clip(g, 0.85, 1.15))
    return out


def _extend(rgb, cover):
    """Fill uncovered pixels from the nearest covered ones (repeated dilation)."""
    out, have = rgb.copy(), cover.copy()
    for _ in range(200):
        if have.all():
            break
        acc = np.zeros_like(out); n = np.zeros(have.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh = np.roll(np.roll(have, dy, 0), dx, 1)
            acc += np.roll(np.roll(out, dy, 0), dx, 1) * sh[..., None]
            n += sh
        grow = ~have & (n > 0)
        out[grow] = acc[grow] / n[grow][:, None]
        have = have | grow
    return out


def _sandness(img, box, sigma=34.0):
    """How much each pixel looks like this image's own playing-surface sand."""
    x0, x1, y0, y1 = box
    ref = np.median(img[int(y0 * H):int(y1 * H), int(x0 * W):int(x1 * W)].reshape(-1, 3), axis=0)
    d2 = np.sum((img - ref) ** 2, axis=-1)
    return np.exp(-d2 / (2 * sigma * sigma))


def composite(base_img, source, G, hand_x, name=None):
    base = np.asarray(base_img.convert("RGB")).astype(np.float64)
    warped = source.convert("RGBA").transform((W, H), Image.Transform.PERSPECTIVE, tuple(G.flatten()[:8]),
                                              resample=Image.Resampling.BICUBIC)
    # the screenshots are lower resolution than the reference; restore a little bite
    warped = warped.filter(ImageFilter.UnsharpMask(radius=1.6, percent=60, threshold=2))
    wa = np.asarray(warped).astype(np.float64)
    src, cover = wa[..., :3], wa[..., 3] > 250
    for x0, x1, y0, y1 in JUNK:
        cover[int(y0 * H):int(y1 * H), int(x0 * W):int(x1 * W)] = False
    src = _colour_fit(src, base, _structure(cover))
    # only what this screenshot's hand actually hides is inpainted
    base = _inpaint(base, (hand_x - 0.008,) + SKETCH_UNDER_HAND[1:])
    x0, x1, y0, y1 = OWN_EDGE
    own = np.zeros((H, W), bool); own[int(y0 * H):int(y1 * H), int(x0 * W):int(x1 * W)] = True
    src = np.where((own & ~cover)[..., None], _extend(src, cover), src)
    present = (cover | own).astype(np.float64)
    present = np.asarray(Image.fromarray((present * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9))
                         .filter(ImageFilter.GaussianBlur(4))).astype(np.float64) / 255
    k = np.clip(_poly(scenery(hand_x, name), 10), 0, 1) * present * (1 - _poly([TROUGH], 2))
    # Where BOTH are bare sand, keep the reference's: the screenshots' sand is
    # a warmer orange, and a corner reaching onto the surface would show as a
    # blotch. Scenery on either side (a vine, a sketched spike) still swaps.
    surface = (0.3, 0.7, 0.35, 0.65)
    both_sand = _sandness(base, surface) * _sandness(src, surface, SAND_SIGMA.get(name, 34.0))
    if name in SAND_SIGMA:
        # sand that is sand in both counts fully: a partial blend still carried
        # the colour fit's red gain onto the reference's sand
        both_sand = np.clip((both_sand - 0.25) / 0.35, 0, 1)
    both_sand = np.asarray(Image.fromarray((both_sand * 255).astype(np.uint8))
                           .filter(ImageFilter.GaussianBlur(3))).astype(np.float64) / 255
    k = (k * (1 - both_sand))[..., None]
    out = base * (1 - k) + src * k
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def _download(url):
    cached = fetch_art.CACHE / (hashlib.sha256(url.encode()).hexdigest() + ".image")
    if cached.exists():
        data = cached.read_bytes()
    else:
        req = urllib.request.Request(url, headers={"User-Agent": "ForeverHearthstone-local-art-import/1.0"})
        data = urllib.request.urlopen(req, timeout=60).read()
        Image.open(io.BytesIO(data)).load()
        cached.write_bytes(data)
    return data


def build(reference):
    """reference: the normalised clean board (2048x1024). Returns report entries."""
    base = empty_deck_slots(reference)
    report = {}
    for name, spec in SOURCES.items():
        data = _download(spec["url"])
        source = Image.open(io.BytesIO(data)).convert("RGB")
        G, fit = register(base, source, spec["start"])
        if fit["residual"] > MAX_RESIDUAL:
            raise SystemExit(f"board {name}: registration residual {fit['residual']} > {MAX_RESIDUAL}")
        key = "board_" + name
        composite(base, source, G, spec["hand"], name).save(ART / (key + ".tga"), compression=None)
        report[key] = {"source": spec["url"], "sha256": hashlib.sha256(data).hexdigest(),
                       "size": [W, H], "composited_on": "orgrimmar_clean", **fit}
        print(f"board {name}: {fit['inliers']}/{fit['matches']} matches, residual {fit['residual']} px")
    # the smeared corner patches the screenshots could not cover (docs/13)
    import repair_board_corners
    for key, frac in repair_board_corners.main().items():
        if key in report:
            report[key]["corner_repair_fraction"] = frac
    # ...and the seams round the corners: rim, margin, rail (docs/14)
    import polish_boards
    for key, frac in polish_boards.main().items():
        if key in report:
            report[key]["polish_fraction"] = frac
    # ...and Orgrimmar from its own full-resolution painting, keeping only the
    # composite's emptied sockets (docs/24)
    import build_orgrimmar_board
    if "board_orgrimmar" in report:
        report["board_orgrimmar"]["from_painting_fraction"] = build_orgrimmar_board.main()
    return report


if __name__ == "__main__":
    ref = Image.open(ART / "orgrimmar_clean.tga")
    print(json.dumps(build(ref), indent=2))
