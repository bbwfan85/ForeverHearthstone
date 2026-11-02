"""Download the open-licensed stand-ins for Hearthstone's typefaces.

Hearthstone sets names and titles in Belwe, rules text in ITC Franklin Gothic
and numbers in Belwe's heavy lining figures. Both are commercial ITC faces and
are not ours to ship, so the addon uses SIL Open Font License faces chosen by
eye against the card frames (see docs/11):

  TITLE   Vollkorn Black      -- soft, heavy wedge serifs, closest to Belwe Bold
  BODY    Libre Franklin      -- a revival of Franklin Gothic itself
  NUMBER  Coustard Black      -- chunky LINING digits; Vollkorn's are old-style,
                                 and WoW cannot switch on the lnum feature

Each font's licence is saved beside it. Provenance: Art/Fonts/fonts-report.json.
"""
import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "ForeverHearthstone/Art/Fonts"
FONTS = {
    "Vollkorn-Black.ttf": "https://raw.githubusercontent.com/FAlthausen/Vollkorn-Typeface/master/fonts/ttf/Vollkorn-Black.ttf",
    "LibreFranklin-SemiBold.ttf": "https://raw.githubusercontent.com/impallari/Libre-Franklin/master/fonts/TTF/LibreFranklin-SemiBold.ttf",
    # the heavier weight Hearthstone's rules text sets its keywords in (Taunt, Battlecry:)
    "LibreFranklin-ExtraBold.ttf": "https://raw.githubusercontent.com/impallari/Libre-Franklin/master/fonts/TTF/LibreFranklin-ExtraBold.ttf",
    "Coustard-Black.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/coustard/Coustard-Black.ttf",
}
LICENCES = {
    "Vollkorn-OFL.txt": "https://raw.githubusercontent.com/FAlthausen/Vollkorn-Typeface/master/OFL.txt",
    "LibreFranklin-OFL.txt": "https://raw.githubusercontent.com/impallari/Libre-Franklin/master/OFL.txt",
    "Coustard-OFL.txt": "https://raw.githubusercontent.com/google/fonts/main/ofl/coustard/OFL.txt",
}


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, url in {**FONTS, **LICENCES}.items():
        data = urllib.request.urlopen(url, timeout=60).read()
        if name.endswith(".ttf") and data[:4] not in (b"\x00\x01\x00\x00", b"true"):
            raise SystemExit(f"{name}: not a TrueType file")
        (DEST / name).write_bytes(data)
        report[name] = {"source": url, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    (DEST / "fonts-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Fonts:", ", ".join(FONTS))


if __name__ == "__main__":
    main()
