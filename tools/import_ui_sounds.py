"""Import Hearthstone's interface sounds and music; retain provenance.

Source: Rymedy/hearthstone-web, the same community project the menu scenes and
boards come from (tools/import_menu_media.py, tools/fetch_art.py). These are
the game's own UI cues -- the turn chime, the End Turn click, pack and rarity
stingers, the innkeeper -- which no card-sound catalog carries.

WoW plays MP3 and Ogg Vorbis directly, so files are stored as downloaded.
Music is imported here but only ever played when the player opts in
(`/fh music`), per docs/06 §6.3.

Writes ForeverHearthstone/Art/Sounds/UI/*, Art/Sounds/Music/* and
Art/ui-sounds-report.json (source URL + sha256 per file).
"""
import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "ForeverHearthstone/Art"
BASE = "https://raw.githubusercontent.com/Rymedy/hearthstone-web/master/src/"
UI = ["sounds/" + n for n in (
    "playerturn.mp3", "endturn.mp3", "cardhover.mp3", "cardplace.mp3", "flipcard.mp3",
    "openpack.mp3", "rare.mp3", "epic.mp3", "legendary.mp3", "goldencommon.mp3",
    "goldenrare.mp3", "goldenepic.mp3", "goldenlegendary.mp3", "menubtnpress.mp3",
    "menuselect.mp3", "openmenu.mp3", "victory.mp3", "whoosh.ogg")]
UI += ["voiceovers/innkeeper_%d.mp3" % i for i in (1, 2, 3)]
MUSIC = ["ost/mainmenu.mp3", "ost/mulligan.mp3", "ost/duel.mp3"]


def looks_like_audio(data):
    return data[:3] == b"ID3" or data[:4] == b"OggS" or (data[0] == 0xFF and data[1] & 0xE0 == 0xE0)


def main():
    report = {}
    for group, folder in ((UI, "UI"), (MUSIC, "Music")):
        dest = ART / "Sounds" / folder
        dest.mkdir(parents=True, exist_ok=True)
        for rel in group:
            url = BASE + rel
            data = urllib.request.urlopen(url, timeout=90).read()
            if not looks_like_audio(data):
                raise SystemExit(f"{rel}: not an MP3 or Ogg file")
            name = rel.rsplit("/", 1)[1]
            (dest / name).write_bytes(data)
            report[folder + "/" + name] = {"source": url, "sha256": hashlib.sha256(data).hexdigest(),
                                           "bytes": len(data)}
    (ART / "ui-sounds-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"UI sounds: {len(UI)}; music: {len(MUSIC)}")


if __name__ == "__main__":
    main()
