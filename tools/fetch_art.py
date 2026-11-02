"""Download local Hearthstone textures; WoW cannot load HTTP, JPG or PNG art.

Run with Python + Pillow. Sources and hashes are recorded in art-report.json.
Only illustration pixels and empty UI frames are imported; card rules/text
continue to come from the pinned PrintedCards.lua, never a latest-card render.
"""
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import re
import time
import urllib.error
import urllib.request

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "ForeverHearthstone" / "Art"
CACHE = ROOT / "tools" / "art-cache"
CARDS = ROOT / "ForeverHearthstone" / "Data" / "PrintedCards.lua"
ART = "https://art.hearthstonejson.com/v1/256x/"
JOUST = "https://raw.githubusercontent.com/HearthSim/Joust/main/assets/images/"
# Hearthstone picks a board at the start of every match. Every board this
# source has is imported and the addon randomises between whichever ones are
# actually installed (Client/UI/Board.lua: SetBoardArt), so adding a file here
# is the whole of adding a board. NONE OF THESE IS ONE OF THE ORIGINAL FOUR
# (Stormwind, Orgrimmar, Pandaria, Stranglethorn) -- this source does not carry
# them. Drop Art/board4.tga in beside the others and it joins the rotation.
BOARD_BASE = "https://raw.githubusercontent.com/Rymedy/hearthstone-web/master/src/images/"
BOARDS = ["board1.jpg", "board2.jpg", "board3.jpg"]

# Boards supplied as local files rather than downloaded: <key> -> path, relative
# to the addon folder. THE CLEAN ORGRIMMAR BOARD IS THE REFERENCE the layout is
# measured against -- it is the only one whose sockets are empty, so it shows
# where the hero alcoves, the mana trough and the End Turn plaque actually are
# rather than what somebody's finished screenshot happened to have in them.
#
# `rotation` is what a match may actually be played on. The COLOURED Orgrimmar
# board is imported but kept out of it: it is somebody's screenshot, with two
# hero portraits, two "30"s and a "0/1" mana readout painted into the sockets.
# Those are exactly the things we draw live, so playing on it would show two
# heroes and two health totals at once. It stays because it is the reference
# that says where the sockets ARE -- the clean board shows their shape, and the
# coloured one shows what belongs in them.
LOCAL_BOARDS = {
    "orgrimmar_clean": {"file": "org_clean_board.jpg", "rotation": True},
    "orgrimmar":       {"file": "orgrimar_board.jpg",  "rotation": False},
}


# Composited boards kept out of the match rotation; see main().
# Pandaria was removed entirely (docs/13): its only source screenshot is cropped
# too tight to fill the board. Nothing is currently built but not played.
NOT_PLAYED = set()

CALIBRATION = json.loads((Path(__file__).resolve().parent / "board_calibration.json").read_text(encoding="utf-8"))


def normalise_board(image, key):
    """Crop a board so its painted table lands where the layout expects it.

    Each board is cropped differently at source, so the playing surface, the
    seam, the End Turn plaque and the deck slots sit at different places in
    each image. Stretching the raw image to the window and hoping the layout
    agrees is what put a live End Turn button next to the painted one and left
    the deck pips floating off their slots.

    Two measured anchors per board (see board_calibration.json) are enough: the
    left and right edges of the playing surface fix the horizontal scale and
    offset, and the seam across its middle fixes the vertical. The crop keeps
    the source's aspect so nothing is stretched, and it may fall outside the
    image -- a board cropped tight at source has to be PADDED to sit correctly,
    which is why the canvas is built first and the source pasted into it.
    """
    board = CALIBRATION["boards"].get(key)
    if not board:
        return image
    target = CALIBRATION["canonical"]
    W, H = image.size

    # Horizontal: the two edges of the playing surface.
    span = (board["surface_x1"] - board["surface_x0"]) * W
    crop_w = span / (target["surface_x1"] - target["surface_x0"])
    left = board["surface_x0"] * W - target["surface_x0"] * crop_w

    # Vertical: the surface's bottom edge and the seam. TWO anchors, because
    # one plus a preserved aspect ratio means the crop height is dictated by
    # the width -- and on a board taller than the output aspect that cropped
    # away whatever was furthest from the seam, which is the mana trough along
    # the very bottom. The axes scale independently; these are all the same
    # underlying artwork at different crops, so the difference is slight, and
    # a socket landing where the layout expects it matters more.
    v_span = (board["seam_y"] - board["surface_y0"]) * H
    crop_h = v_span / (target["seam_y"] - target["surface_y0"])
    # Pillow's origin is top-left; the calibration measures y from the bottom.
    seam_top = (1.0 - board["seam_y"]) * H
    top = seam_top - (1.0 - target["seam_y"]) * crop_h

    # The crop can reach outside the source, so pad with the edge colour rather
    # than letting Pillow fill black -- a black bar reads as a rendering fault,
    # a continuation of the surrounding scenery does not.
    pad = int(max(0, -left, -top, (left + crop_w) - W, (top + crop_h) - H)) + 2
    canvas = Image.new("RGB", (W + pad * 2, H + pad * 2), image.getpixel((2, 2)))
    canvas.paste(image.resize((W + pad * 2, H + pad * 2), Image.Resampling.LANCZOS), (0, 0))
    canvas.paste(image, (pad, pad))
    return canvas.crop((int(left) + pad, int(top) + pad,
                        int(left + crop_w) + pad, int(top + crop_h) + pad))


def fetch(job):
    key, url, size, alpha = job[:4]
    crop = job[4] if len(job) > 4 else None
    cached = CACHE / (hashlib.sha256(url.encode()).hexdigest() + ".image")
    for attempt in range(3):
        try:
            if cached.exists():
                data = cached.read_bytes()
            else:
                request = urllib.request.Request(url, headers={"User-Agent": "ForeverHearthstone-local-art-import/1.0"})
                with urllib.request.urlopen(request, timeout=25) as response:
                    data = response.read()
            image = Image.open(io.BytesIO(data))
            image.load()  # Reject a bad response before caching or publishing.
            cached.write_bytes(data)
            image = image.convert("RGBA" if alpha else "RGB")
            if crop:
                image = image.crop(crop)
            if key.startswith("board"):
                image = normalise_board(image, key)
            image = image.resize(size, Image.Resampling.LANCZOS)
            target = DEST / (key + ".tga")
            image.save(target, compression=None)
            with Image.open(target) as check:
                assert check.size == size and check.format == "TGA"
            return key, {"source": url, "sha256": hashlib.sha256(data).hexdigest(), "size": list(size)}
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return key, {"source": url, "error": "HTTP 404"}
            error = str(exc)
        except Exception as exc:
            error = str(exc)
        time.sleep(attempt + 1)
    return key, {"source": url, "error": error}


def make_gem():
    """Draw the rarity gem: a small diamond, white, tinted at runtime.

    Hearthstone's rarity gem is a cut diamond set into the card frame. Ours was
    a plain coloured SQUARE, because a square is what a solid ColorTexture is --
    and rotating a solid colour does nothing, since every texel is the same.
    A diamond needs an actual SHAPE, which means a texture with alpha.

    It is generated rather than downloaded: it is four straight lines and a
    highlight, nobody's art, and generating it means there is no path that can
    404 and leave the gem missing.
    """
    size = 128
    image = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    draw = ImageDraw.Draw(image)
    m, c = size * 0.06, size / 2
    draw.polygon([(c, m), (size - m, c), (c, size - m), (m, c)],
                 fill=(255, 255, 255, 255))
    # An inner facet, so the gem reads as cut rather than as a flat lozenge.
    i = size * 0.26
    draw.polygon([(c, i), (size - i, c), (c, size - i), (i, c)],
                 fill=(255, 255, 255, 140))
    image.convert("RGBA").save(DEST / "gem.tga", compression=None)
    return {"source": "generated by tools/fetch_art.py", "size": [size, size]}


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    ids = []
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        match = re.match(r'P\["([A-Za-z0-9_]+)"\]=', line)
        if match and re.search(r'type="(?:MINION|SPELL|WEAPON|HERO|HERO_POWER)"', line):
            ids.append(match.group(1))
    jobs = [(card, ART + card + ".jpg", (256, 256), False) for card in ids]
    classes = "druid hunter mage paladin priest rogue shaman warlock warrior neutral".split()
    sprites = ["inhand_" + kind + "_" + cls for kind in ("minion", "spell") for cls in classes]
    sprites += ["inhand_weapon_neutral", "cardback", "hero_frame", "hero_power", "mana_crystal", "inplay_minion"]
    for sprite in sprites:
        jobs.append((sprite, JOUST + sprite + ".png", (256, 512) if sprite.startswith("inhand_") or sprite == "cardback" else (256, 256), True))
    # Native overlays. Each shares its base frame's source canvas (290x410 for
    # hand cards, 300x350 for board minions, 280x280 for heroes, 250x250 for
    # hero powers) and is resized exactly as that base was, so the client draws
    # it over the base's own rect and it registers with no measurement at all.
    overlays = ["inhand_minion_legendary", "inhand_minion_legendary_premium",
                "inhand_spell_legendary", "inhand_minion_premium",
                "inhand_spell_premium", "inhand_weapon_premium", "inhand_mulligan"]
    overlays += ["inplay_minion_" + s for s in (
        "legendary", "legendary_premium", "premium", "taunt_premium",
        "divine_shield", "frozen", "stealth", "silenced", "immune", "enraged",
        "untargetable")]
    overlays += ["effect_sleep", "icon_deathrattle", "icon_trigger",
                 "inplay_hero_frozen", "inplay_hero_immune",
                 "hero_power_exhausted", "damage", "healing", "skull"]
    for sprite in overlays:
        jobs.append((sprite, JOUST + sprite + ".png", (256, 512) if sprite.startswith("inhand_") else (256, 256), True))
    sprites += overlays
    # Secret gems sit at one fixed spot at the top of the hero canvas; cropped
    # to that spot they can be laid out in a row like Hearthstone's.
    for cls in ("hunter", "mage", "paladin", "sheathed"):
        jobs.append(("secret_" + cls, JOUST + "secret_" + cls + ".png", (64, 64), True, (105, 1, 165, 63)))
        sprites.append("secret_" + cls)
    for index, name in enumerate(BOARDS, 1):
        jobs.append(("board%d" % index, BOARD_BASE + name, (2048, 1024), False))
    # `board` stays as the single-board fallback for a partial install. It is
    # the same image as the last board, so it takes the same calibration.
    CALIBRATION["boards"]["board"] = CALIBRATION["boards"]["board%d" % len(BOARDS)]
    jobs.append(("board", BOARD_BASE + BOARDS[-1], (2048, 1024), False))
    report = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for index, (key, result) in enumerate(pool.map(fetch, jobs), 1):
            report[key] = result
            if index % 100 == 0:
                print(f"Checked {index}/{len(jobs)} textures", flush=True)
    for key, spec in sorted(LOCAL_BOARDS.items()):
        source = ROOT / "ForeverHearthstone" / spec["file"]
        if not source.exists():
            report[key] = {"source": str(source), "error": "not present"}
            continue
        with Image.open(source) as local:
            local.load()
            normalised = normalise_board(local.convert("RGB"), key)
        normalised.resize((2048, 1024), Image.Resampling.LANCZOS).save(
            DEST / (key + ".tga"), compression=None)
        report[key] = {"source": str(source), "local": True}

    # Hearthstone's four launch boards, composited onto the clean reference
    # table (tools/composite_boards.py). They replace the reference in the
    # rotation: its corner scenery is uncoloured concept sketch.
    composited = []
    if "error" not in report.get("orgrimmar_clean", {"error": 1}):
        import composite_boards
        with Image.open(DEST / "orgrimmar_clean.tga") as clean:
            clean.load()
            boards = composite_boards.build(clean.convert("RGB"))
        report.update(boards)
        composited = sorted(boards)

    report["gem"] = make_gem()
    lines = ["-- Generated by tools/fetch_art.py. See Art/art-report.json for provenance.", "local _, ns = ...", "ns.HearthstoneArt = {"]
    for key, result in sorted(report.items()):
        if "error" not in result:
            lines.append('  ["%s"] = [[Interface\\AddOns\\ForeverHearthstone\\Art\\%s.tga]],' % (key, key))
    lines.append("}")
    # The rotation, in order, holding only boards that actually downloaded.
    # The rotation is REAL boards only. The three downloaded ones are
    # stand-ins from a fan project -- none of them is one of the originals --
    # so they are packaged and available but a match is not played on them.
    # Adding Stormwind or Stranglethorn (tools/add_board.py) puts them here.
    # Pandaria is not built at all: its only source screenshot is cropped too
    # tight to fill the corners (removed in docs/13).
    names = [n for n in composited if n not in NOT_PLAYED] or [k for k, spec in sorted(LOCAL_BOARDS.items())
                           if spec["rotation"] and "error" not in report.get(k, {"error": 1})]
    installed = [
        '  [[Interface\\AddOns\\ForeverHearthstone\\Art\\%s.tga]],' % n
        for n in names
    ]
    if installed:
        lines.append("")
        lines.append("-- Matches randomise between these; see Client/UI/Board.lua SetBoardArt.")
        lines.append("ns.HearthstoneArt.boards = {")
        lines.extend(installed)
        lines.append("}")
    (ROOT / "ForeverHearthstone/Client/Assets/HearthstoneArt.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (DEST / "art-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    missing = [key for key in ids if "error" in report[key]]
    print(f"Art: {len(ids) - len(missing)}/{len(ids)} card images; missing: {', '.join(missing)}")
    print(f"UI: {sum('error' not in report[s] for s in sprites)}/{len(sprites)} sprites; boards: {len(installed)}")


if __name__ == "__main__":
    main()
