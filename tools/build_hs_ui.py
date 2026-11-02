"""Hearthstone-style interface art for the match and menus (docs/13).

Two kinds of output:

* EXTRACTED from Hearthstone's own board art. The clean Orgrimmar reference
  (Art/orgrimmar_clean.tga, the table every composited board shares) has the
  End Turn button painted into its socket, with "Waiting..." lettered on it.
  That button is cut out, its lettering removed, and re-coloured into the three
  states Hearthstone uses, so the live button IS Hearthstone's button, sitting
  exactly where the socket expects it.

      endturn-yellow   your turn, with plays left       ("END TURN")
      endturn-green    your turn, nothing left to do    ("END TURN")
      endturn-grey     the opponent's turn               ("ENEMY TURN")

* GENERATED, original procedural art in the Hearthstone manner where no source
  asset exists (the wiki hosts screenshots only and is not a source we ship):

      hs-tooltip       parchment keyword panel with a dark bevelled rim (9-slice)
      hs-button        the tavern menu button, gold rim and cream face (3-slice)
      hs-ribbon        the end-of-game banner ribbon, red, gold-edged
      hs-ribbon-dark   the same ribbon for a defeat
      hs-nameplate     the small name tag beside a portrait
      hs-round         small round gilded button (close, mute)
      fx-dust          a soft dust puff for clicks on the board

Output: ForeverHearthstone/Art/*.tga; provenance: Art/hs-ui-report.json.
"""
from pathlib import Path
import json, math, random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
report = {}

# The End Turn button on the 2048x1024 reference board: the crop (including its
# dark outline), and inside it the gold face. Measured on orgrimmar_clean.tga;
# Client/UI/Layout.lua positions the live button on exactly this rect.
BTN = (1601, 428, 1793, 510)          # x0, y0, x1, y1 on the board
FACE_POLY = [(38, 27), (162, 27), (172, 30), (177, 38), (177, 63), (172, 70), (162, 73),
             (38, 73), (32, 70), (29, 63), (29, 38), (32, 30)]
OUTER_POLY = [(46, 13), (150, 13), (176, 18), (189, 28), (190, 67), (182, 78), (150, 85),
              (46, 85), (18, 78), (11, 67), (12, 29), (20, 18)]
# columns of clean gold either side of the lettering, for rebuilding the face
LEFT_SAMPLE, RIGHT_SAMPLE = (33, 43), (160, 174)


def save(im, name, source, note=""):
    im.save(ART / (name + ".tga"))
    report[name] = {"source": source, "texture_size": im.size, "note": note}


def poly_mask(size, pts, offset=(0, 0), feather=0.8):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([(x - offset[0], y - offset[1]) for x, y in pts], fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather)) if feather else m


def build_end_turn():
    board = Image.open(ART / "orgrimmar_clean.tga").convert("RGB")
    # the measurement polygons are in the coordinates of a (1596, 420) crop
    ox, oy = BTN[0] - 1596, BTN[1] - 420
    crop = board.crop(BTN)
    w, h = crop.size
    a = np.asarray(crop).astype(np.float64)

    # --- remove the lettering: rebuild the face row by row from clean gold
    face = np.asarray(poly_mask((w, h), FACE_POLY, (ox, oy), 0)) > 0
    rng = np.random.default_rng(7)
    rebuilt = a.copy()
    lx = slice(LEFT_SAMPLE[0] - ox, LEFT_SAMPLE[1] - ox)
    rx = slice(RIGHT_SAMPLE[0] - ox, RIGHT_SAMPLE[1] - ox)
    samples = {}
    def golden(c):
        return (c.max() - c.min()) / (c.max() + 1e-6) > 0.45
    for y in range(h):
        left, right = np.median(a[y, lx], axis=0), np.median(a[y, rx], axis=0)
        if golden(left) and golden(right):
            samples[y] = (left, right)
    # rows at the face's rim sample the silver bevel instead; borrow the
    # nearest row that really is gold
    rows = sorted(samples)
    for y in range(h):
        row = face[y]
        if not row.any():
            continue
        near = min(rows, key=lambda r: abs(r - y))
        left, right = samples[near]
        xs = np.nonzero(row)[0]
        for x in xs:
            t = (x - xs[0]) / max(1, xs[-1] - xs[0])
            rebuilt[y, x] = left * (1 - t) + right * t
    # row medians leave streaks; smooth the rebuilt face in both directions
    # (normalised: only face pixels contribute, so the silver never bleeds in)
    fm = face.astype(np.float64)
    def blur(ch):
        return np.asarray(Image.fromarray(ch.clip(0, 255).astype("uint8"))
                          .filter(ImageFilter.GaussianBlur(2.2))).astype(np.float64)
    wsum = np.asarray(Image.fromarray((fm * 255).astype("uint8"))
                      .filter(ImageFilter.GaussianBlur(2.2))).astype(np.float64) / 255 + 1e-6
    smooth = np.stack([blur(rebuilt[..., c] * fm) / wsum for c in range(3)], axis=2)
    rebuilt[face] = smooth[face]
    # the painted face has a soft grain; put a little back so it is not flat
    grain = rng.normal(0, 4.0, (h, w, 1))
    grain = np.asarray(Image.fromarray(((grain[..., 0] + 128).clip(0, 255)).astype("uint8"))
                       .filter(ImageFilter.GaussianBlur(0.8))).astype(np.float64)[..., None] - 128
    rebuilt[face] = (rebuilt + grain)[face]
    # a soft top highlight, as on the painted plaque
    for y in range(h):
        k = max(0.0, 1 - abs(y - (27 - oy + 9)) / 10.0) * 16
        rebuilt[y][face[y]] += k
    rebuilt = rebuilt.clip(0, 255)
    # blend the rebuilt face in with a feathered edge so the silver bevel stays
    fmask = np.asarray(poly_mask((w, h), FACE_POLY, (ox, oy), 1.2)).astype(np.float64)[..., None] / 255
    clean = a * (1 - fmask) + rebuilt * fmask
    alpha = poly_mask((w, h), OUTER_POLY, (ox, oy), 0.9)

    def variant(fn):
        out = clean.copy()
        out = out * (1 - fmask) + fn(clean) * fmask
        im = Image.fromarray(out.clip(0, 255).astype("uint8"), "RGB").convert("RGBA")
        im.putalpha(alpha)
        return im.resize((512, 256), Image.Resampling.LANCZOS)

    def green(c):
        # Hearthstone's "nothing left to do" green: the same plaque, hue-shifted
        lum = c.mean(axis=2, keepdims=True)
        return np.concatenate([lum * 0.45, lum * 1.12 + 10, lum * 0.35], axis=2)

    def grey(c):
        lum = c.mean(axis=2, keepdims=True)
        return np.concatenate([lum * 0.62, lum * 0.60, lum * 0.58], axis=2)

    note = ("Hearthstone's own End Turn plaque, cut from the clean Orgrimmar board "
            "(orgrimmar_clean.tga), lettering removed")
    save(variant(lambda c: c), "endturn-yellow", "extracted from Art/orgrimmar_clean.tga", note)
    save(variant(green), "endturn-green", "extracted from Art/orgrimmar_clean.tga", note + ", hue-shifted")
    save(variant(grey), "endturn-grey", "extracted from Art/orgrimmar_clean.tga", note + ", desaturated")
    report["endturn-rect"] = {"board_px": BTN,
                              "face_uv": [(30 - ox) / w, (27 - oy) / h, (176 - ox) / w, (72 - oy) / h]}


# ---------------------------------------------------------------- generated

GOLD_HI, GOLD, GOLD_LO, BRONZE = (255, 236, 170), (214, 164, 72), (140, 90, 30), (62, 38, 14)


def vgrad(size, top, bottom):
    w, h = size
    col = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        col.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    return col.resize(size)


def noise(size, amount, blur, seed):
    rng = np.random.default_rng(seed)
    n = rng.normal(128, amount, (size[1], size[0])).clip(0, 255).astype("uint8")
    return Image.fromarray(n, "L").filter(ImageFilter.GaussianBlur(blur))


def textured(size, top, bottom, amount=10, seed=1):
    base = vgrad(size, top, bottom)
    n = noise(size, amount, 1.2, seed)
    arr = np.asarray(base).astype(np.float64)
    arr[..., :3] += (np.asarray(n).astype(np.float64)[..., None] - 128) * 0.6
    return Image.fromarray(arr.clip(0, 255).astype("uint8"), "RGBA")


def rr(size, box, radius, feather=0.7):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather)) if feather else m


def layer(base, fill, mask):
    f = fill.copy()
    f.putalpha(ImageChops.multiply(f.getchannel("A"), mask))
    return Image.alpha_composite(base, f)


def build_tooltip():
    """Hearthstone's keyword tooltip: warm parchment, a dark brown bevelled rim,
    a thin inner gold line, soft drop shadow. 128x128, drawn as a 9-slice with
    24px corners (Widgets.HSPanel)."""
    s = 128
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow = rr((s, s), (6, 8, s - 3, s - 1), 18, 4)
    im = layer(im, Image.new("RGBA", (s, s), (0, 0, 0, 150)), shadow)
    im = layer(im, textured((s, s), (72, 44, 22, 255), (44, 26, 12, 255), 8, 3), rr((s, s), (3, 3, s - 6, s - 6), 16))
    im = layer(im, textured((s, s), (120, 80, 40, 255), (84, 54, 26, 255), 6, 4), rr((s, s), (5, 5, s - 8, s - 8), 14))
    im = layer(im, Image.new("RGBA", (s, s), GOLD + (255,)), rr((s, s), (9, 9, s - 12, s - 12), 11))
    im = layer(im, textured((s, s), (246, 230, 196, 255), (226, 204, 160, 255), 9, 5), rr((s, s), (11, 11, s - 14, s - 14), 9))
    # faint vignette on the parchment
    vig = Image.new("L", (s, s), 0)
    ImageDraw.Draw(vig).rounded_rectangle((11, 11, s - 14, s - 14), radius=9, fill=60)
    inner = Image.new("L", (s, s), 0)
    ImageDraw.Draw(inner).rounded_rectangle((20, 20, s - 23, s - 23), radius=6, fill=60)
    vig = ImageChops.subtract(vig, inner).filter(ImageFilter.GaussianBlur(5))
    im = layer(im, Image.new("RGBA", (s, s), (120, 80, 30, 255)), vig)
    save(im, "hs-tooltip", "generated by tools/build_hs_ui.py", "9-slice, 24px corners")


def build_button():
    """The tavern menu button: a cream stone face in a gilded rim with a bronze
    outline, rounded ends. 512x128, a 3-slice with 64px caps."""
    w, h = 512, 128
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im = layer(im, Image.new("RGBA", (w, h), (0, 0, 0, 120)), rr((w, h), (6, 12, w - 2, h - 2), 52, 5))
    im = layer(im, Image.new("RGBA", (w, h), BRONZE + (255,)), rr((w, h), (4, 6, w - 6, h - 10), 54))
    im = layer(im, vgrad((w, h), GOLD_HI + (255,), GOLD_LO + (255,)), rr((w, h), (8, 10, w - 10, h - 14), 50))
    im = layer(im, Image.new("RGBA", (w, h), BRONZE + (255,)), rr((w, h), (18, 20, w - 20, h - 24), 42))
    im = layer(im, textured((w, h), (248, 238, 214, 255), (206, 188, 152, 255), 7, 9), rr((w, h), (21, 23, w - 23, h - 27), 39))
    hi = rr((w, h), (30, 27, w - 32, 58), 30, 3)
    im = layer(im, Image.new("RGBA", (w, h), (255, 255, 255, 70)), hi)
    save(im, "hs-button", "generated by tools/build_hs_ui.py", "3-slice, 64px caps")


def ribbon(dark):
    """The end-of-game ribbon: a banner with swallow-tail ends folded behind,
    gold-edged. Victory is crimson, defeat a dark slate."""
    w, h = 1024, 256
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    face_top = (70, 74, 86, 255) if dark else (196, 38, 30, 255)
    face_bot = (34, 36, 44, 255) if dark else (118, 18, 14, 255)
    tail_top = (46, 48, 58, 255) if dark else (140, 24, 20, 255)
    tail_bot = (24, 25, 32, 255) if dark else (84, 12, 10, 255)
    tails = [[(0, 70), (150, 70), (150, 206), (0, 206), (50, 138)],
             [(w, 70), (w - 150, 70), (w - 150, 206), (w, 206), (w - 50, 138)]]
    sh = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(sh)
    for t in tails:
        d.polygon([(x + 4, y + 8) for x, y in t], fill=130)
    d.rounded_rectangle((104, 44, w - 104, 222), radius=10, fill=150)
    im = layer(im, Image.new("RGBA", (w, h), (0, 0, 0, 255)), sh.filter(ImageFilter.GaussianBlur(6)))
    for t in tails:
        m = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m).polygon(t, fill=255)
        im = layer(im, Image.new("RGBA", (w, h), GOLD_LO + (255,)), m.filter(ImageFilter.GaussianBlur(0.8)))
        inner = Image.new("L", (w, h), 0)
        cx = sum(x for x, _ in t) / len(t)
        ImageDraw.Draw(inner).polygon([(x + (6 if x < cx else -6), y + (6 if y < 138 else -6)) for x, y in t], fill=255)
        im = layer(im, textured((w, h), tail_top, tail_bot, 8, 11), inner.filter(ImageFilter.GaussianBlur(0.8)))
        # the fold shadow where the tail meets the banner
    fold = Image.new("L", (w, h), 0)
    ImageDraw.Draw(fold).rectangle((110, 64, 170, 212), fill=140)
    ImageDraw.Draw(fold).rectangle((w - 170, 64, w - 110, 212), fill=140)
    im = layer(im, Image.new("RGBA", (w, h), (0, 0, 0, 255)), fold.filter(ImageFilter.GaussianBlur(12)))
    # main banner: bronze outline, gold edge, cloth face
    im = layer(im, Image.new("RGBA", (w, h), BRONZE + (255,)), rr((w, h), (96, 36, w - 96, 222), 12))
    im = layer(im, vgrad((w, h), GOLD_HI + (255,), GOLD_LO + (255,)), rr((w, h), (100, 40, w - 100, 218), 10))
    im = layer(im, Image.new("RGBA", (w, h), BRONZE + (255,)), rr((w, h), (112, 52, w - 112, 206), 8))
    im = layer(im, textured((w, h), face_top, face_bot, 9, 13), rr((w, h), (115, 55, w - 115, 203), 7))
    # a sheen across the cloth and a darker lower band, like a curved ribbon
    im = layer(im, Image.new("RGBA", (w, h), (255, 255, 255, 60)), rr((w, h), (130, 62, w - 130, 100), 18, 8))
    im = layer(im, Image.new("RGBA", (w, h), (0, 0, 0, 70)), rr((w, h), (120, 172, w - 120, 203), 6, 8))
    save(im, "hs-ribbon-dark" if dark else "hs-ribbon", "generated by tools/build_hs_ui.py",
         "text area: x 0.14-0.86, y 0.23-0.78")


def build_nameplate():
    """A small dark name tag with a gold hairline, Hearthstone's in-match name
    label. 256x64, a 3-slice with 24px caps."""
    w, h = 256, 64
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im = layer(im, Image.new("RGBA", (w, h), (0, 0, 0, 110)), rr((w, h), (3, 6, w - 1, h - 1), 16, 3))
    im = layer(im, Image.new("RGBA", (w, h), GOLD_LO + (255,)), rr((w, h), (2, 2, w - 4, h - 6), 16))
    im = layer(im, vgrad((w, h), GOLD_HI + (255,), GOLD + (255,)), rr((w, h), (3, 3, w - 5, h - 7), 15))
    im = layer(im, textured((w, h), (46, 30, 20, 240), (22, 14, 9, 240), 6, 17), rr((w, h), (5, 5, w - 7, h - 9), 13))
    save(im, "hs-nameplate", "generated by tools/build_hs_ui.py", "3-slice, 24px caps")


def build_round():
    """A small round gilded button face (close, mute): bronze ring, gold bevel,
    dark enamel centre. 64x64."""
    s = 64
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    def circ(r, feather=0.7):
        m = Image.new("L", (s, s), 0)
        ImageDraw.Draw(m).ellipse((s / 2 - r, s / 2 - r, s / 2 + r, s / 2 + r), fill=255)
        return m.filter(ImageFilter.GaussianBlur(feather))
    im = layer(im, Image.new("RGBA", (s, s), (0, 0, 0, 120)), circ(31, 2))
    im = layer(im, Image.new("RGBA", (s, s), BRONZE + (255,)), circ(29))
    im = layer(im, vgrad((s, s), GOLD_HI + (255,), GOLD_LO + (255,)), circ(27))
    im = layer(im, Image.new("RGBA", (s, s), BRONZE + (255,)), circ(21))
    im = layer(im, vgrad((s, s), (78, 40, 24, 255), (36, 16, 10, 255)), circ(19.5))
    im = layer(im, Image.new("RGBA", (s, s), (255, 255, 255, 50)), rr((s, s), (18, 14, 46, 26), 8, 3))
    save(im, "hs-round", "generated by tools/build_hs_ui.py")


def build_dust():
    """A dust puff: a soft, clumpy ring of pale sand-coloured smoke. Drawn
    additively-safe (alpha only carries the shape; colour is warm grey). 128x128."""
    s = 128
    rng = random.Random(21)
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    for _ in range(26):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(22, 40)
        x, y = s / 2 + math.cos(a) * r, s / 2 + math.sin(a) * r * 0.8
        rad = rng.uniform(9, 17)
        d.ellipse((x - rad, y - rad, x + rad, y + rad), fill=rng.randint(90, 170))
    m = m.filter(ImageFilter.GaussianBlur(6))
    im = Image.new("RGBA", (s, s), (226, 208, 176, 255))
    im.putalpha(m)
    save(im, "fx-dust", "generated by tools/build_hs_ui.py")


def main():
    build_end_turn()
    build_tooltip()
    build_button()
    ribbon(False)
    ribbon(True)
    build_nameplate()
    build_round()
    build_dust()
    (ART / "hs-ui-report.json").write_text(json.dumps(report, indent=2))
    print("built", len(report), "entries")


if __name__ == "__main__":
    main()
