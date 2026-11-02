"""Render every preview scene and tile them into one contact sheet.

    luajit tools/collection_preview.lua            # export the scenes (JSON)
    python tools/review_sheet.py <label>           # render + tile -> tools/review/<label>.jpg
    python tools/review_sheet.py <label> --compare <other-label>

With --compare, each scene is shown as a before/after pair so a UI pass can be
checked scene by scene. The sheet is an approximation of the live client (see
collection_preview.py); it is for layout, alignment and style drift, not pixels.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import shutil, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools'
SCENES = [
    'hearth-menu', 'hearth-compact', 'hearth-wide', 'practice-new', 'practice-decks', 'practice-decks-compact', 'practice-wide',
    'collection-wide', 'collection-short', 'deck-wide', 'deck-compact', 'deck-hover', 'decks-browser', 'decks-page-two',
    'packs-new', 'packs-wide', 'pack-reveal', 'disenchant-confirm',
    'board-orgrimmar', 'board-stormwind', 'board-stranglethorn', 'board-tall', 'board-wide', 'board-hand', 'board-profiles', 'board-states',
    'hero-emote-menu', 'match-hero-power', 'match-turn-banner', 'match-emotes', 'match-targeting', 'match-spells',
    'match-holy-nova', 'match-hero-cracking', 'match-hero-shatter', 'match-postgame',
]
TILE_W = 640


def render(label):
    out = TOOLS / 'review' / label
    out.mkdir(parents=True, exist_ok=True)
    scenes = [s for s in SCENES if (TOOLS / f'{s}.json').exists()]
    subprocess.run([sys.executable, str(TOOLS / 'collection_preview.py'), *scenes], check=True, cwd=ROOT)
    for s in scenes:
        shutil.copyfile(TOOLS / f'{s}.png', out / f'{s}.png')
    return out, scenes


def thumb(path):
    im = Image.open(path).convert('RGB')
    return im.resize((TILE_W, round(im.height * TILE_W / im.width)), Image.Resampling.LANCZOS)


def sheet(label, compare=None):
    out, scenes = render(label)
    font = ImageFont.load_default()
    cols = 2 if compare else 3
    cells = []
    for s in scenes:
        if compare:
            before = TOOLS / 'review' / compare / f'{s}.png'
            cells.append((f'{s}  [{compare}]', thumb(before) if before.exists() else None))
            cells.append((f'{s}  [{label}]', thumb(out / f'{s}.png')))
        else:
            cells.append((s, thumb(out / f'{s}.png')))
    rows = [cells[i:i + cols] for i in range(0, len(cells), cols)]
    heights = [max((c[1].height if c[1] else 100) for c in r) + 24 for r in rows]
    im = Image.new('RGB', (cols * (TILE_W + 12) + 12, sum(heights) + 12), (18, 12, 9))
    d = ImageDraw.Draw(im)
    y = 12
    for r, h in zip(rows, heights):
        for i, (name, t) in enumerate(r):
            x = 12 + i * (TILE_W + 12)
            d.text((x, y), name, fill=(255, 212, 118), font=font)
            if t: im.paste(t, (x, y + 18))
            else: d.text((x, y + 40), '(no capture)', fill=(200, 80, 80), font=font)
        y += h
    dest = TOOLS / 'review' / (f'{compare}-vs-{label}.jpg' if compare else f'{label}.jpg')
    im.save(dest, quality=85)
    print(dest)


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    compare = args[args.index('--compare') + 1] if '--compare' in args else None
    sheet(args[0], compare)
