"""Import Hearthstone's deck-list tile art (docs/24).

A deck being built lists each card as a strip: its cost, its name, and a slice
of its art fading in from the right. The addon cut that slice from the square
card art itself, which never framed the subject the way Hearthstone's own
strips do. HearthstoneJSON publishes those strips (art.hearthstonejson.com
/v1/tiles/<id>.png, 256x59); this fetches one per collectible card.

    python tools/import_deck_tiles.py

Writes Art/DeckTile/<id>.tga (256x64: the strip, top-aligned, 59/64 of the
height), Client/Assets/DeckTiles.lua (the ids that have one) and
Art/deck-tiles-report.json (source, sha256 per file). Downloads are cached in
tools/art-cache like every other import.
"""
from pathlib import Path
import hashlib, io, json, re, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
OUT = ART / "DeckTile"
CACHE = ROOT / "tools" / "art-cache"
BASE = "https://art.hearthstonejson.com/v1/tiles/"


def collectible():
    src = (ROOT / "ForeverHearthstone" / "Data" / "PrintedCards.lua").read_text(encoding="utf-8")
    return sorted(set(re.findall(r'^P\["([^"]+)"\]=\{[^\n]*collectible=true', src, re.M)))


def fetch(cid):
    url = BASE + cid + ".png"
    cached = CACHE / (hashlib.sha256(url.encode()).hexdigest() + ".image")
    try:
        if cached.exists():
            data = cached.read_bytes()
        else:
            req = urllib.request.Request(url, headers={"User-Agent": "ForeverHearthstone-local-art-import/1.0"})
            data = urllib.request.urlopen(req, timeout=60).read()
            Image.open(io.BytesIO(data)).load()
            cached.write_bytes(data)
        im = Image.open(io.BytesIO(data)).convert("RGB")
        canvas = Image.new("RGB", (256, 64), (0, 0, 0))
        canvas.paste(im.resize((256, 59), Image.Resampling.LANCZOS) if im.size != (256, 59) else im, (0, 0))
        canvas.save(OUT / f"{cid}.tga", compression=None)
        return cid, {"source": url, "sha256": hashlib.sha256(data).hexdigest(), "original_size": list(im.size)}
    except Exception as e:  # noqa: BLE001 -- a missing tile falls back to the art crop
        return cid, {"source": url, "error": str(e)}


def main():
    OUT.mkdir(exist_ok=True); CACHE.mkdir(exist_ok=True)
    ids = collectible()
    with ThreadPoolExecutor(8) as pool:
        results = dict(pool.map(fetch, ids))
    ok = sorted(cid for cid, r in results.items() if "error" not in r)
    lines = ["-- GENERATED FILE -- DO NOT EDIT BY HAND.",
             "-- Regenerate with: python tools/import_deck_tiles.py (docs/24)",
             "-- The cards with Hearthstone's deck-list tile art at Art/DeckTile/<id>.tga",
             "-- (256x64; the strip fills the top 59/64).",
             "local ADDON, ns = ...", "ns.DeckTiles = {"]
    lines += ['  ["%s"] = true,' % cid for cid in ok]
    lines += ["}", ""]
    (ROOT / "ForeverHearthstone" / "Client" / "Assets" / "DeckTiles.lua").write_text("\n".join(lines), encoding="utf-8")
    (ART / "deck-tiles-report.json").write_text(json.dumps({"license_note": "Hearthstone card art, via HearthstoneJSON",
                                                            "files": results}, indent=1))
    print(f"{len(ok)}/{len(ids)} tiles; missing: {[c for c in ids if c not in ok]}")


if __name__ == "__main__":
    main()
