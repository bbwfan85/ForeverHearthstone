#!/usr/bin/env python3
"""
Forever Hearthstone - ranked ladder art (docs/45).

Draws, with Pillow + numpy (the Pillow python in docs/tooling):
  Art/rank-medal.tga       256x256 gilded medal ring, hollow, for a rank medal
                           (the minion's portrait shows through the middle)
  Art/rank-medal-legend.tga  the same ring in Legend's orange-gold with flared
                           wings
  Art/rank-star.tga        64x64 lit gold star (a won star)
  Art/rank-star-empty.tga  64x64 dark star socket (a star still to win)

The classic ranked medals were a minion's portrait in a round, bevelled gold
setting with the stars along the bottom; these are drawn from scratch to that
recipe rather than imported (no medal art exists in the sources we use).
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(HERE), "ForeverHearthstone", "Art")
SS = 4  # supersample


def gold_ramp(t, legend=False):
    # t in 0..1 across the bevel: dark rim -> bright crest -> mid
    stops = [(0.0, (92, 56, 18)), (0.35, (214, 168, 74)), (0.55, (255, 236, 160)),
             (0.75, (196, 140, 52)), (1.0, (110, 66, 20))]
    if legend:
        stops = [(0.0, (110, 40, 8)), (0.35, (232, 132, 40)), (0.55, (255, 222, 140)),
                 (0.75, (214, 110, 30)), (1.0, (120, 44, 10))]
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if t <= b:
            u = (t - a) / (b - a)
            return tuple(int(ca[i] + (cb[i] - ca[i]) * u) for i in range(3))
    return stops[-1][1]


def ring(size, inner, outer, legend=False):
    n = size * SS
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2
    dx, dy = x - c, y - c
    r = np.sqrt(dx * dx + dy * dy) / SS
    ang = np.arctan2(dy, dx)
    img = np.zeros((n, n, 4), np.float32)
    band = (r >= inner) & (r <= outer)
    t = np.clip((r - inner) / (outer - inner), 0, 1)
    # light from the top-left: brighten the upper-left half of the band
    light = 0.82 + 0.25 * np.cos(ang + math.pi * 0.75)
    for i in range(3):
        lut = np.array([gold_ramp(k / 255.0, legend)[i] for k in range(256)], np.float32)
        img[..., i] = lut[(t * 255).astype(np.int32)] * light
    # a fine engraved groove two thirds of the way out
    groove = np.abs(t - 0.66) < 0.035
    img[..., :3][groove] *= 0.55
    # studs every 30 degrees on the outer band
    for k in range(12):
        a = k * math.pi / 6
        sx, sy = c + math.cos(a) * (inner + (outer - inner) * 0.66) * SS, c + math.sin(a) * (inner + (outer - inner) * 0.66) * SS
        d = np.sqrt((x - sx) ** 2 + (y - sy) ** 2) / SS
        stud = d < (outer - inner) * 0.16
        img[..., :3][stud & band] = np.array(gold_ramp(0.55, legend), np.float32) * 1.0
    img[..., 3] = np.where(band, 255, 0)
    # soft dark inner lip so the portrait sits under the metal
    lip = (r >= inner - 3) & (r < inner)
    img[..., 3] = np.where(lip, 150 * (r - (inner - 3)) / 3, img[..., 3])
    img = np.clip(img, 0, 255).astype(np.uint8)
    out = Image.fromarray(img, "RGBA").resize((size, size), Image.LANCZOS)
    return out


def wings(size):
    """Legend's flared points behind the ring."""
    n = size * SS
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n / 2
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        tip = (c + math.cos(a) * n * 0.49, c + math.sin(a) * n * 0.49)
        l = (c + math.cos(a - 0.22) * n * 0.36, c + math.sin(a - 0.22) * n * 0.36)
        r = (c + math.cos(a + 0.22) * n * 0.36, c + math.sin(a + 0.22) * n * 0.36)
        d.polygon([l, tip, r, (c, c)], fill=(230, 120, 30, 255), outline=(110, 40, 8, 255))
    im = im.resize((size, size), Image.LANCZOS)
    # only the points outside the ring: the middle is the portrait's
    a = np.array(im)
    yy, xx = np.mgrid[0:size, 0:size]
    rr = np.sqrt((xx - (size - 1) / 2) ** 2 + (yy - (size - 1) / 2) ** 2)
    a[..., 3] = np.where(rr < size * 0.44, 0, a[..., 3])
    return Image.fromarray(a, "RGBA")


def star(size, lit):
    n = size * SS
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n / 2
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = n * (0.47 if k % 2 == 0 else 0.2)
        pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr * 0.98 + n * 0.02))
    if lit:
        d.polygon(pts, fill=(120, 70, 10, 255))
        inner = [(c + (px - c) * 0.80, c + (py - c) * 0.80) for px, py in pts]
        d.polygon(inner, fill=(255, 206, 70, 255))
        hi = [(c + (px - c) * 0.42, c - n * 0.05 + (py - c) * 0.42) for px, py in pts]
        d.polygon(hi, fill=(255, 246, 190, 255))
    else:
        d.polygon(pts, fill=(70, 50, 30, 255))
        inner = [(c + (px - c) * 0.78, c + (py - c) * 0.78) for px, py in pts]
        d.polygon(inner, fill=(28, 20, 14, 235))
    im = im.resize((size, size), Image.LANCZOS)
    glow = im.filter(ImageFilter.GaussianBlur(2)) if lit else None
    if glow is not None:
        base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        base.alpha_composite(glow)
        base.alpha_composite(im)
        im = base
    return im


def main():
    ring(256, 100, 127).save(os.path.join(ART, "rank-medal.tga"))
    leg = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    leg.alpha_composite(wings(256))
    leg.alpha_composite(ring(256, 96, 118, legend=True).resize((256, 256)))
    leg.save(os.path.join(ART, "rank-medal-legend.tga"))
    star(64, True).save(os.path.join(ART, "rank-star.tga"))
    star(64, False).save(os.path.join(ART, "rank-star-empty.tga"))
    prev = Image.new("RGBA", (256 * 2 + 128, 256), (40, 40, 40, 255))
    prev.alpha_composite(Image.open(os.path.join(ART, "rank-medal.tga")), (0, 0))
    prev.alpha_composite(Image.open(os.path.join(ART, "rank-medal-legend.tga")), (256, 0))
    prev.alpha_composite(Image.open(os.path.join(ART, "rank-star.tga")), (512, 0))
    prev.alpha_composite(Image.open(os.path.join(ART, "rank-star-empty.tga")), (576, 0))
    prev.save(os.path.join(HERE, "rank-art-preview.png"))
    print("wrote rank-medal(.tga, -legend), rank-star(-empty)")


if __name__ == "__main__":
    main()
