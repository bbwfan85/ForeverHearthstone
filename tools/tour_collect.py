"""Gather one FHTour run's screenshots into tools/tour/run-<N>/, named by scene.

The tour (FHTour/Tour.lua) labels every capture with a strip of squares in
the top-left corner: a magenta marker, then 16 bits of Tour.Hash(name). This
reads the label back, matches it against the scene names in Tour.lua, paints
the strip out, and writes <index>-<scene>.jpg plus index.json, and the judges' crops into
judge-input/ -- the only folder a judge is given.

    python tools/tour_collect.py 3               # shots from the last 20 min
    python tools/tour_collect.py 3 --since 1730480000

Needs Pillow: use the Python noted in the project memory (tooling quirks).
"""
import argparse
import json
import re
import shutil
import time
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHOTS = Path(r"C:\Program Files (x86)\World of Warcraft\_retail_\Screenshots")
TOUR = ROOT / "FHTour" / "Tour.lua"
PX, BITS = 10, 16


def lua_hash(name):
    h = 0
    for ch in name.encode("utf-8"):
        h = (h * 31 + ch) % 65521
    return h


def scene_names():
    src = TOUR.read_text(encoding="utf-8")
    names = set(re.findall(r'(?:add|fromHub)\("([a-z0-9-]+)"', src))
    names.update(f"live-{i:02d}" for i in range(1, 31))
    names.update({"live-result", "live-result-settled"})
    table = {}
    for n in sorted(names):
        h = lua_hash(n)
        if h in table:
            raise SystemExit(f"label collision: {n} and {table[h]} -- rename one")
        table[h] = n
    return table


def read_label(img):
    rgb = img.convert("RGB")
    def px(i):
        return rgb.getpixel((i * PX + PX // 2, PX // 2))
    r, g, b = px(0)
    if not (r > 170 and g < 100 and b > 170):
        return None
    h = 0
    for i in range(1, BITS + 1):
        h = h * 2 + (1 if sum(px(i)) / 3 > 127 else 0)
    return h


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run", type=int)
    ap.add_argument("--since", type=float, default=None, help="epoch seconds; default 20 min ago")
    ap.add_argument("--shots", type=Path, default=SHOTS)
    args = ap.parse_args()
    since = args.since if args.since is not None else time.time() - 20 * 60
    names = scene_names()
    out = ROOT / "tools" / "tour" / f"run-{args.run}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    judge = out / "judge-input"
    judge.mkdir()
    index, unknown = [], []
    files = sorted((p for p in args.shots.glob("WoWScrnShot_*.*") if p.stat().st_mtime >= since),
                   key=lambda p: p.stat().st_mtime)
    for n, path in enumerate(files, 1):
        img = Image.open(path)
        h = read_label(img)
        name = names.get(h) if h is not None else None
        if not name:
            unknown.append(path.name)
            continue
        img = img.convert("RGB")
        ImageDraw.Draw(img).rectangle([0, 0, PX * (BITS + 1) + 1, PX + 1], fill=(0, 0, 0))
        dest = out / f"{len(index) + 1:02d}-{name}.jpg"
        img.save(dest, quality=92)
        # what a judge sees, and ALL it sees (docs/39): the centred window,
        # full height so the overhanging hands stay in, nothing from other runs
        W, H = img.size
        cw = min(W, int(H * 1.9))
        img.crop(((W - cw) // 2, 0, (W + cw) // 2, H)).save(judge / dest.name, quality=92)
        index.append({"scene": name, "file": dest.name, "source": path.name, "size": img.size})
    (out / "index.json").write_text(json.dumps({"run": args.run, "shots": index, "unlabelled": unknown},
                                               indent=1), encoding="utf-8")
    print(f"{len(index)} scenes -> {out}  ({len(unknown)} unlabelled screenshots ignored)")


if __name__ == "__main__":
    main()
