"""Add a board to the match rotation from a local image.

    python tools/grid_overlay.py ~/stormwind.png stormwind-grid.png   # measure
    python tools/add_board.py ~/stormwind.png stormwind 0.155 0.845 0.305 0.545

Arguments: <image> <name> <surface_x0> <surface_x1> <surface_y0> <seam_y>, the
four numbers read off the grid overlay: the two edges of the pale playing
surface, its bottom edge, and the seam across its middle. The image may be any format Pillow opens, from
anywhere on disk -- this does no downloading, because the boards worth having
are the ones out of your own Hearthstone install and those are already local.

What it does:
  * records the measurement in tools/board_calibration.json
  * NORMALISES the image so its surface and seam land where Layout.lua expects,
    exactly as tools/fetch_art.py does for the bundled boards
  * writes ForeverHearthstone/Art/<name>.tga
  * adds it to the rotation in Client/Assets/HearthstoneArt.lua

After that a match picks it like any other board, and the End Turn plaque and
deck slots painted on it line up with the live controls without touching a
single constant.

Removing a board is deleting its .tga and its line in HearthstoneArt.lua; the
rotation is whatever is actually installed, so nothing else needs to know.
"""
import json
from pathlib import Path
import re
import sys

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_art  # noqa: E402  (same directory, shares the normalisation)

ROOT = Path(__file__).resolve().parents[1]
ART_LUA = ROOT / "ForeverHearthstone" / "Client" / "Assets" / "HearthstoneArt.lua"
CALIBRATION = Path(__file__).resolve().parent / "board_calibration.json"
PATH_TEMPLATE = "  [[Interface\\AddOns\\ForeverHearthstone\\Art\\%s.tga]],"


def main():
    if len(sys.argv) < 7:
        print(__doc__)
        return 2
    src, name = Path(sys.argv[1]), sys.argv[2]
    x0, x1, y0, seam = (float(v) for v in sys.argv[3:7])
    if not re.match(r"^[a-z0-9_]+$", name):
        print("name must be lowercase letters, digits and underscores")
        return 2
    if not (0 <= x0 < x1 <= 1):
        print("surface_x0 must be less than surface_x1, both 0..1")
        return 2
    if not (0 <= y0 < seam <= 1):
        print("surface_y0 must be below seam_y, both 0..1")
        return 2

    data = json.loads(CALIBRATION.read_text(encoding="utf-8"))
    data["boards"][name] = {"surface_x0": x0, "surface_x1": x1,
                            "surface_y0": y0, "seam_y": seam}
    CALIBRATION.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    # fetch_art holds its own copy, loaded at import.
    fetch_art.CALIBRATION["boards"][name] = data["boards"][name]

    image = Image.open(src)
    image.load()
    image = fetch_art.normalise_board(image.convert("RGB"), name)
    target = ROOT / "ForeverHearthstone" / "Art" / (name + ".tga")
    image.resize((2048, 1024), Image.Resampling.LANCZOS).save(target, compression=None)
    print("wrote %s" % target)

    line = PATH_TEMPLATE % name
    lua = ART_LUA.read_text(encoding="utf-8")
    if line in lua:
        print("%s was already in the rotation" % name)
        return 0
    if "ns.HearthstoneArt.boards = {" not in lua:
        lua += ("\n-- Matches randomise between these; see Client/UI/Board.lua SetBoardArt.\n"
                "ns.HearthstoneArt.boards = {\n}\n")
    lua = lua.replace("ns.HearthstoneArt.boards = {\n",
                      "ns.HearthstoneArt.boards = {\n" + line + "\n", 1)
    # ...and as a named key, so anything can reference it directly.
    lua = lua.replace("\nns.HearthstoneArt.boards",
                      '\nns.HearthstoneArt["%s"] = [[Interface\\AddOns\\ForeverHearthstone\\Art\\%s.tga]]\n\nns.HearthstoneArt.boards'
                      % (name, name), 1)
    ART_LUA.write_text(lua, encoding="utf-8")
    print("added %s to the rotation -- restart WoW (new texture) and /fh" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
