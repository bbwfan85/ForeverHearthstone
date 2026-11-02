"""Import Hearthstone's hero-power card frame and the minion race banner (docs/24).

Hovering a hero power showed an unskinned fallback card -- a black box with a
class-coloured outline -- because there was no hero-power frame. HearthSim's
Sunwell card renderer (MIT; the same source as the rarity gems, see
import_rarity_gems.py) ships the real one: the round art window in a stone
ring, the cost gem on top, the name scroll and the text plate on a blue
banner. It also ships the small banner a minion's race ("Beast", "Murloc") is
printed on.

    python tools/import_card_extras.py

Writes Art/inhand_hero_power.tga, Art/inhand_hero_power_premium.tga (512x1024,
the frame stretched to the card's canvas like every other in-hand frame),
Art/race-banner.tga (512x128, the banner centred) and card-extras-report.json.
"""
from pathlib import Path
import hashlib, io, json, urllib.request
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone" / "Art"
BASE = "https://raw.githubusercontent.com/HearthSim/sunwell/master/"
FILES = {
    "inhand_hero_power": ("assets/hero-power-player.png", (512, 1024)),
    "inhand_hero_power_premium": ("assets/hero-power-premium-player.png", (512, 1024)),
    "race-banner": ("assets/race-banner.png", None),
}


def fetch(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "ForeverHearthstone-local-art-import/1.0"})
    return urllib.request.urlopen(req, timeout=60).read()


def main():
    report = {"source": BASE, "license": "MIT (HearthSim/sunwell LICENSE, copied to Art/rarity-gems-LICENSE.txt)",
              "files": {}}
    for key, (path, size) in FILES.items():
        data = fetch(path)
        im = Image.open(io.BytesIO(data)).convert("RGBA")
        entry = {"source": path, "sha256": hashlib.sha256(data).hexdigest(), "original_size": list(im.size)}
        if size:
            out = im.resize(size, Image.Resampling.LANCZOS)
        else:
            # the race banner, centred on a power-of-two canvas at its own shape
            out = Image.new("RGBA", (512, 128), (0, 0, 0, 0))
            scale = min(512 / im.width, 128 / im.height)
            b = im.resize((round(im.width * scale), round(im.height * scale)), Image.Resampling.LANCZOS)
            out.alpha_composite(b, ((512 - b.width) // 2, (128 - b.height) // 2))
            entry["placed"] = [(512 - b.width) / 2 / 512, (128 - b.height) / 2 / 128, b.width / 512, b.height / 128]
        out.save(ART / f"{key}.tga", compression=None)
        entry["texture_size"] = list(out.size)
        report["files"][key] = entry
        print(key, entry["original_size"], "->", entry["texture_size"])
    (ART / "card-extras-report.json").write_text(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
