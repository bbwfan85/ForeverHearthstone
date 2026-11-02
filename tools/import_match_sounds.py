"""Import the match's remaining Hearthstone sounds (docs/12); retain provenance.

Same two sources the rest of the audio came from:

* HearthSFX's bucket (hearthstonesounds.s3.amazonaws.com) -- the card-audio
  source of tools/import_presentation_media.py -- for underlays chosen by name
  from tools/audio-catalog-names.json:
      Fuse_Underlay_Play           the rope's burning fuse (4.3s of steady sizzle)
      UNG_Egg_Cracks               a dying hero's portrait cracking
      GlassShatter_Underlay_Death  ...and shattering
      Dagger_Underlay_Play         Dagger Mastery
* Rymedy/hearthstone-web -- the source of the UI sounds -- for
      heropower.mp3                Hearthstone's hero-power activation
      bigattack.mp3                the heavy hit under a hero's destruction

No Hearthstone rope, defeat or per-spell recording exists in either source
(docs/12 §audio); the defeat cue reuses a Hearthstone stinger already on disk,
and since docs/13 the heroes' own "Out of Time" and Death lines carry the
rope and the defeat.
"""
from pathlib import Path
import hashlib, json, urllib.request

ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "ForeverHearthstone" / "Art" / "Sounds"
S3 = "https://hearthstonesounds.s3.amazonaws.com/"
RYMEDY = "https://raw.githubusercontent.com/Rymedy/hearthstone-web/master/src/sounds/"
JOBS = [(S3 + n + ".wav", SOUNDS / "Cards" / (n + ".wav")) for n in
        ("Fuse_Underlay_Play", "UNG_Egg_Cracks", "GlassShatter_Underlay_Death", "Dagger_Underlay_Play")]
JOBS += [(RYMEDY + n, SOUNDS / "UI" / n) for n in ("heropower.mp3", "bigattack.mp3")]


def main():
    report = {}
    for url, dest in JOBS:
        if not dest.exists():
            req = urllib.request.Request(url, headers={"User-Agent": "ForeverHearthstone-local-import/1.0"})
            data = urllib.request.urlopen(req, timeout=60).read()
            if dest.suffix == ".wav" and not data.startswith(b"RIFF"):
                raise SystemExit(f"{url} is not a WAV file")
            dest.write_bytes(data)
        data = dest.read_bytes()
        report[str(dest.relative_to(SOUNDS)).replace("\\", "/")] = {
            "source": url, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    (ROOT / "ForeverHearthstone" / "Art" / "match-sounds-report.json").write_text(json.dumps(report, indent=2))
    print("imported", len(report), "sounds")


if __name__ == "__main__":
    main()
