"""Import Hearthstone's rarity gems, each in its own frame socket.

The card's rarity gem was a generated flat diamond (gem.tga), tinted per
rarity and drawn above the name banner -- and on Basic cards too, which have
no gem in Hearthstone. HearthSim's Sunwell card renderer (MIT) ships the
real gems already set in their sockets, one per card type and rarity; this
fetches them, records their hashes, and packages them as TGAs.

Where they go on the card is Sunwell's own placement (its MinionCard /
SpellCard / WeaponCard rarityGemCoords), carried onto our Joust frame canvas
(256x512) by the mapping the painted cost, attack and health badges define --
fitted in docs/14 and checked by eye; see Client/UI/Widgets.lua GEM_SOCKET.

    python tools/import_rarity_gems.py
"""
from pathlib import Path
import hashlib
import io
import json
import urllib.request

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
BASE = "https://raw.githubusercontent.com/HearthSim/sunwell/master/"
KINDS = {"minion": (128, 64), "spell": (128, 64), "weapon": (128, 128)}
RARITIES = ("common", "rare", "epic", "legendary")


def fetch(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "ForeverHearthstone-local-art-import/1.0"})
    return urllib.request.urlopen(req, timeout=60).read()


def main():
    report = {"source": BASE, "license": "MIT (HearthSim/sunwell LICENSE, copied to Art/rarity-gems-LICENSE.txt)",
              "files": {}}
    for kind, size in KINDS.items():
        for rarity in RARITIES:
            src = f"assets/rarity-{kind}-{rarity}.png"
            data = fetch(src)
            im = Image.open(io.BytesIO(data)).convert("RGBA")
            name = f"rarity-{kind}-{rarity}"
            im.resize(size, Image.Resampling.LANCZOS).save(ART / (name + ".tga"))
            report["files"][name] = {"source": BASE + src, "sha256": hashlib.sha256(data).hexdigest(),
                                     "source_size": im.size, "texture_size": size}
            print(name, im.size, "->", size)
    (ART / "rarity-gems-LICENSE.txt").write_bytes(fetch("LICENSE"))
    (ART / "rarity-gems-report.json").write_text(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
