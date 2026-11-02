"""Build the player-facing release: dist/ForeverHearthstone-<version>.zip.

The repo keeps every texture as uncompressed TGA, because the build tools write
TGA and regenerate the Lua that names them. The release converts them instead,
on a copy, and rewrites the paths in the copy's Lua to match:

* opaque card art (the Art root's card ids) and the deck-list strips
  (Art/DeckTile) -> JPEG, quality 95, no chroma subsampling;
* every other texture (anything with transparency: frames, masks, baked card
  text, UI) -> PNG, lossless.

WoW loads JPEG, PNG and TGA through SetTexture (PNG since 10.0.7; Forever is on
the 12.x API), all at the same power-of-two sizes. Also left out of the
release: the development files (tools/, tests/, docs/ are outside the addon
folder anyway), preview renders, the painting sources, and the textures no
code draws (PRUNE). Audio is shipped as it is.

Then it CHECKS the copy: no TGA left, every texture path written out in its
Lua and .toc exists, every runtime-built family still has its files, nothing
refers to a pruned file, and every Lua file still parses (luajit, when found).
The build fails on any of it.

    python tools/package_release.py [--version 0.1.0-beta.1]

Run with the Pillow + numpy Python (see memory: tooling quirks).
"""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ForeverHearthstone"
DIST = ROOT / "dist"

# Textures no code draws (checked for docs/26): the stand-in and reference
# boards (the rotation is HearthstoneArt.boards, the three board_* files), the
# old End Turn states, and UI sheets superseded by later passes.
PRUNE = {
    "board.tga", "board1.tga", "board2.tga", "board3.tga", "orgrimmar.tga", "orgrimmar_clean.tga",
    "menu-pack-room.tga", "endturn-green.tga", "endturn-grey.tga", "endturn-yellow.tga",
    "hs-ribbon.tga", "hs-ribbon-dark.tga", "menu-nav.tga", "card-digits.tga",
}
# Files that are development material, not the addon.
# Import reports, provenance notes and the art README are for whoever rebuilds
# the art; WoW reads none of them. Licence texts (.txt) ship.
SKIP_SUFFIX = ("-preview.png", ".json", ".md")
SKIP_ROOT = {"orgrimar_board.jpg", "org_clean_board.jpg"}
# Lua that is in the tree but not in the .toc: loaded by nothing.
SKIP_REL = {"Data/Effects/Examples.lua"}

# Texture families whose paths are assembled at runtime: after conversion,
# each must still exist under its new extension.
FAMILIES = [("Art", r"^fx-.*\.png$"), ("Art", r"^class-.*\.png$"), ("Art", r"^card-digit-\d+\.png$"),
            ("Art", r"^rarity-.*\.png$"), ("Art", r"^mask-.*\.png$"), ("Art", r"^inhand_.*\.png$"),
            ("Art/CardText", r"-n\.png$"), ("Art/DeckTile", r"\.jpg$")]


def version_from_toc():
    for line in (SRC / "ForeverHearthstone.toc").read_text(encoding="utf-8").splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    raise SystemExit("no ## Version in the .toc")


def is_card_art(rel):
    """Opaque art: the Art root's card ids (upper-case ids) and the deck strips."""
    parts = rel.parts
    if parts[:2] == ("Art", "DeckTile"):
        return True
    return len(parts) == 2 and parts[0] == "Art" and parts[1][:2].isupper()


def convert(src, dst_base, jpeg):
    im = Image.open(src)
    im.load()
    if jpeg:
        if im.mode == "RGBA" and im.getchannel("A").getextrema()[0] < 255:
            jpeg = False                 # it has transparency after all: stay lossless
        else:
            out = dst_base.with_suffix(".jpg")
            im.convert("RGB").save(out, "JPEG", quality=95, subsampling=0, optimize=True)
            return out
    if im.mode not in ("RGB", "RGBA", "L", "LA"):
        im = im.convert("RGBA")
    out = dst_base.with_suffix(".png")
    im.save(out, "PNG", optimize=True)
    return out


def rewrite_lua(text, renamed):
    """Point every texture path at its converted file.

    `renamed` maps a repo-relative TGA path (backslashes, as the Lua writes
    them) to its new one. Fully written-out paths are looked up exactly; what
    is left is a runtime-built name ending ".tga" (fx-, class-, masks, the
    baked card text...), which is PNG -- except the deck strips, the one
    runtime-built family that is JPEG."""
    # [[Interface\AddOns\ForeverHearthstone\Art\X.tga]] (long strings: single backslashes)
    text = re.sub(r"Interface\\AddOns\\ForeverHearthstone\\((?:Art\\)[^\]\"'\s]*?\.tga)",
                  lambda m: "Interface\\AddOns\\ForeverHearthstone\\" + renamed.get(m.group(1), m.group(1)), text)
    # "Interface\\AddOns\\ForeverHearthstone\\Art\\X.tga" (quoted strings: doubled backslashes)
    def quoted(m):
        rel = m.group(1).replace("\\\\", "\\")
        return "Interface\\\\AddOns\\\\ForeverHearthstone\\\\" + renamed.get(rel, rel).replace("\\", "\\\\")
    text = re.sub(r"Interface\\\\AddOns\\\\ForeverHearthstone\\\\((?:Art\\\\)[^\"'\s]*?\.tga)", quoted, text)
    # the deck strips: ART.."DeckTile\\"..id..".tga"
    text, n = re.subn(r'("DeckTile\\\\"\s*\.\.\s*id\s*\.\.\s*")\.tga"', r'\1.jpg"', text)
    # whatever else is left is a PNG
    text = text.replace(".tga", ".png")
    return text, n


def check(out):
    problems = []
    # Fail closed on unexpected files and common credential/personal-path leaks.
    allowed = {'.lua', '.toc', '.txt', '.png', '.jpg', '.ogg', '.mp3', '.wav', '.ttf', '.otf', '.blp'}
    sensitive = re.compile(rb'(?i)(?:[A-Z]:\\{1,2}Users\\{1,2}|/(?:Users|home)/|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-|ant-)[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')
    for path in out.rglob('*'):
        if not path.is_file():
            continue
        if path.suffix.lower() not in allowed or any(part.startswith('.') for part in path.relative_to(out).parts):
            problems.append(f'Unexpected release file: {path.relative_to(out)}')
        if sensitive.search(path.read_bytes()):
            problems.append(f'Potential private data in: {path.relative_to(out)}')
    tgas = list(out.rglob("*.tga"))
    if tgas:
        problems.append(f"{len(tgas)} TGA files left, e.g. {tgas[0]}")
    names = {p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()}
    toc = (out / 'ForeverHearthstone.toc').read_text(encoding='utf-8')
    if not re.search(r'^## Author: bbwfan85\s*$', toc, re.M):
        problems.append('Release author must be bbwfan85')
    for line in toc.splitlines():
        entry = line.strip().replace('\\', '/')
        if entry and not entry.startswith('#') and entry not in names:
            problems.append(f'TOC entry missing or wrong case: {entry}')
    texts = [(p, p.read_text(encoding="utf-8", errors="replace")) for p in out.rglob("*.lua")]
    texts.append((out / "ForeverHearthstone.toc", (out / "ForeverHearthstone.toc").read_text(encoding="utf-8")))
    pat = re.compile(r"Interface\\{1,2}AddOns\\{1,2}ForeverHearthstone\\{1,2}([^\]\"'\s]+?\.(?:png|jpg|tga|blp))")
    art_rel = re.compile(r'ART\s*\.\.\s*"([A-Za-z0-9_\-\\]+\.(?:png|jpg))"')
    seen = 0
    for p, t in texts:
        for m in pat.finditer(t):
            rel = re.sub(r"\\+", "/", m.group(1))
            seen += 1
            if rel not in names:
                problems.append(f"{p.name}: {rel} is not in the package")
        for m in art_rel.finditer(t):
            rel = "Art/" + re.sub(r"\\+", "/", m.group(1))
            seen += 1
            if rel not in names:
                problems.append(f"{p.name}: {rel} is not in the package")
        for pruned in PRUNE:
            stem = pruned[:-4]
            if re.search(r'["\\]' + re.escape(stem) + r'\.(png|jpg|tga)', t):
                problems.append(f"{p.name}: still refers to pruned {pruned}")
    for folder, rx in FAMILIES:
        d = out / folder
        if not any(re.search(rx, f.name) for f in d.iterdir() if f.is_file()):
            problems.append(f"no files left in family {folder}/{rx}")
    luajit = shutil.which("luajit") or str(Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/LuaJIT/bin/luajit.exe")
    if Path(luajit).exists():
        for p, _ in texts:
            if p.suffix == ".lua":
                r = subprocess.run([luajit, "-bl", str(p)], capture_output=True, text=True)
                if r.returncode != 0:
                    problems.append(f"{p.name} does not parse: {r.stderr.strip()[:200]}")
    else:
        problems.append("luajit not found: the Lua in the package could not be checked")
    return problems, seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default=None, help="version for the packaged .toc and zip name")
    args = ap.parse_args()
    version = args.version or version_from_toc()
    if not re.fullmatch(r'[0-9][A-Za-z0-9._+-]*', version):
        raise SystemExit('version must be a filename-safe version starting with a digit')
    if "dev" in version.lower():
        raise SystemExit(f"refusing to package a development version ({version}): pass --version "
                         "or set the release number in the .toc")

    stage = DIST / f"ForeverHearthstone-{version}"
    if stage.resolve() != DIST.resolve() / stage.name:
        raise SystemExit('refusing a staging path redirected outside its intended location')
    out = stage / "ForeverHearthstone"
    if stage.exists():
        shutil.rmtree(stage)
    out.mkdir(parents=True)

    renamed = {}
    counts = {"jpg": 0, "png": 0, "pruned": 0, "copied": 0, "skipped": 0}
    for src in sorted(SRC.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(SRC)
        if ((len(rel.parts) == 1 and rel.name in SKIP_ROOT) or rel.name.endswith(SKIP_SUFFIX)
                or rel.as_posix() in SKIP_REL):
            counts["skipped"] += 1
            continue
        if rel.parts[0] == "Art" and len(rel.parts) == 2 and rel.name in PRUNE:
            counts["pruned"] += 1
            continue
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if src.suffix.lower() == ".tga":
            new = convert(src, dst, is_card_art(rel))
            counts[new.suffix[1:]] += 1
            renamed["\\".join(rel.parts)] = "\\".join(new.relative_to(out).parts)
        else:
            shutil.copy2(src, dst)
            counts["copied"] += 1

    # the generated art table: drop the pruned entries, then rewrite every path
    ha = out / "Client" / "Assets" / "HearthstoneArt.lua"
    lines = [ln for ln in ha.read_text(encoding="utf-8").splitlines(keepends=True)
             if not any(("Art\\" + p) in ln for p in PRUNE)]
    ha.write_text("".join(lines), encoding="utf-8")

    decktile_hits = 0
    for lua in list(out.rglob("*.lua")) + [out / "ForeverHearthstone.toc"]:
        text = lua.read_text(encoding="utf-8")
        new, n = rewrite_lua(text, renamed)
        decktile_hits += n
        if lua.suffix == ".toc":
            new = re.sub(r"^## Version:.*$", f"## Version: {version}", new, flags=re.M)
        if new != text:
            lua.write_text(new, encoding="utf-8", newline="")
    if decktile_hits != 1:
        raise SystemExit(f"expected one runtime-built DeckTile path, rewrote {decktile_hits}")

    (out / "README.txt").write_text(PLAYER_README.format(version=version), encoding="utf-8")

    problems, seen = check(out)
    if problems:
        for p in problems[:40]:
            print("  PROBLEM:", p)
        raise SystemExit(f"{len(problems)} problem(s): the package is not usable")

    zpath = DIST / f"ForeverHearthstone-{version}.zip"
    if zpath.exists():
        zpath.unlink()
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(out.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(stage).as_posix())

    def mb(p):
        return sum(f.stat().st_size for f in p.rglob("*") if f.is_file()) / 1e6
    print(f"version {version}: {counts['jpg']} JPEG, {counts['png']} PNG, {counts['pruned']} pruned, "
          f"{counts['skipped']} dev files left out, {counts['copied']} copied")
    print(f"checked {seen} texture paths in the Lua and .toc")
    print(f"addon folder {mb(SRC):.0f} MB -> {mb(out):.0f} MB installed, {zpath.stat().st_size / 1e6:.0f} MB zip")
    print(zpath)


PLAYER_README = """Forever Hearthstone {version}
=============================

Hearthstone's Basic, Classic, Naxxramas and Goblins vs Gnomes sets, played in
World of Warcraft: against a practice bot, or against another player near you.

INSTALL
  1. Quit World of Warcraft completely.
  2. Unzip into the AddOns folder of the game client you play:
       ...\\World of Warcraft\\<client folder>\\Interface\\AddOns\\ForeverHearthstone
     where <client folder> is that client's own folder (_retail_ for retail).
     The folder holding ForeverHearthstone.toc must be directly inside AddOns.
  3. Start the game and make sure "Forever Hearthstone" is enabled in the AddOns list.
  Updating: delete the old ForeverHearthstone folder first, then unzip the new one,
  and restart the game fully (a /reload does not pick up new art).

PLAYING
  Click the Hearthstone button on the minimap (or type /fh) for the main menu.
  Left-click: main menu. Right-click: your collection. Drag it to move it.
  It is also in the Addon Compartment, the addon list by the minimap.

DUELLING ANOTHER PLAYER
  Stand next to them (about trade distance), target them, and type /fh duel --
  or right-click their portrait and choose "Challenge to Hearthstone".
  They need Forever Hearthstone too, and the same version as you: if one of
  you is out of date, chat says who needs to update.
  After acceptance, both players choose a deck and press Ready to start.
  Who may challenge you is on the main menu (anyone, friends & group, or nobody).

COMMANDS
  /fh duel        challenge your current target
  /fh accept      accept a challenge        /fh decline   decline it
  /fh practice    play the practice bot
  /fh collection  your cards                /fh open classic  open a pack
  /fh music       music on/off              /fh mute      sound on/off
  /fh minimap     hide or show the minimap button
  /fh help        every command

IF SOMETHING GOES WRONG
  The chat window usually says what. Please send that message, and what you
  were doing, to the author:
  https://github.com/bbwfan85/ForeverHearthstone/issues

Hearthstone and World of Warcraft are trademarks of Blizzard Entertainment.
This is an unofficial fan project, not made or endorsed by Blizzard.
"""

if __name__ == "__main__":
    main()
