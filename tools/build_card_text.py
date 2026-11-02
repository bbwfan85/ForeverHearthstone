"""Bake every card's name and rules text into textures (docs/24).

WHY. A hand card leans, and a leaning FontString is drawn badly by the client:
each glyph quad is turned without smooth filtering and each word is snapped to
the pixel grid on its own, so tilted text came out jagged, its baseline
stepping, and hard to read (docs/22 fixed where the words go, not how they
look). A TEXTURE turns with bilinear filtering. So the name and the rules text
are rendered here, anti-aliased and supersampled, and drawn on the card as two
images that turn with it exactly as the frame does.

WHAT. For each minion, spell and weapon in Data/PrintedCards.lua:

    Art/CardText/<id>-n.tga   the name band   256x32
    Art/CardText/<id>-t.tga   the rules band  256x64   (absent if no text)
    Art/CardText/<id>-r.tga   the race line   256x32   (minions with a race)

and Client/Assets/CardText.lua, the rect each band covers on the card face (as
fractions of the face, y down from the top). Widgets.lua draws each band as a
full-card region with its texcoords stretched past the image (clamped to
transparent), the same trick the cost digits use, so the band shares the
card's pivot however the client turns regions.

The layout mirrors the live one in Widgets.lua (cardApplyRect / W.RichText /
W.FitText): the same boxes, the same starting sizes, the same shrink-to-fit
and greedy wrapping, so baked and live text land in the same place. Rendered
at 6x the band's pixels and reduced with Lanczos.

Fonts: the shipped OFL faces (Vollkorn Black for names, Libre Franklin
SemiBold / ExtraBold for rules text and its keywords).

    python tools/build_card_text.py            # all cards
    python tools/build_card_text.py EX1_116    # a few, for review
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, re, sys

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'ForeverHearthstone' / 'Art'
OUT = ART / 'CardText'
FONTS = ART / 'Fonts'
TITLE = FONTS / 'Vollkorn-Black.ttf'
BODY_FONT = FONTS / 'LibreFranklin-SemiBold.ttf'
BOLD_FONT = FONTS / 'LibreFranklin-ExtraBold.ttf'

CARD_ASPECT = 0.70            # face width / height, as everywhere in the addon
NAME_FILE = (256, 32)
TEXT_FILE = (256, 64)
SS = 6                        # supersampling

# Boxes on the face (fractions; y from the top), from Widgets.lua cardApplyRect.
NAME_CY, NAME_W, NAME_H, NAME_SIZE = 292 / 512, 0.70, 0.075, 0.062
BODY = {
    'MINION': dict(x=0.0, top=0.665, w=0.66, h=0.18),
    'WEAPON': dict(x=0.0, top=0.665, w=0.66, h=0.18),
    'SPELL':  dict(x=0.01, top=0.675, w=0.62, h=0.215),
}
BODY_SIZE = 0.052
# Rules text colour on each plate: dark ink on the minion and spell parchment,
# white on the weapon's dark slate (as Hearthstone prints it).
INK = {'MINION': (31, 20, 10), 'SPELL': (31, 20, 10), 'WEAPON': (255, 255, 255)}

# The band each file covers: the box plus a margin, so nothing is clipped.
NAME_BAND = (0.5 - 0.38, 0.5 + 0.38, NAME_CY - 0.04, NAME_CY + 0.04)

# A minion's race, on the small banner under its text plate (Art/race-banner.tga,
# drawn by Widgets.lua over RACE_BANNER): white, outlined, as Hearthstone prints it.
RACE_CY, RACE_SIZE = 0.893, 0.052
RACE_BAND = (0.25, 0.75, RACE_CY - 0.028, RACE_CY + 0.028)
RACE_FILE = (256, 32)
# where race-banner.tga's canvas lies on the face (its banner fills rows .16-.84)
RACE_BANNER = (0.18, 0.82, RACE_CY - 0.056, RACE_CY + 0.056)
RACES = {'BEAST': 'Beast', 'MURLOC': 'Murloc', 'DEMON': 'Demon', 'MECHANICAL': 'Mech',
         'DRAGON': 'Dragon', 'PIRATE': 'Pirate', 'TOTEM': 'Totem'}


def body_band(kind):
    b = BODY[kind]
    cx = 0.5 + b['x']
    return (cx - b['w'] / 2 - 0.025, cx + b['w'] / 2 + 0.025, b['top'] - 0.012, b['top'] + b['h'] + 0.012)


def printed_cards():
    src = (ROOT / 'ForeverHearthstone' / 'Data' / 'PrintedCards.lua').read_text(encoding='utf-8')
    cards = []
    for line in src.splitlines():
        m = re.match(r'P\["([^"]+)"\]=\{(.*)\}$', line)
        if not m:
            continue
        body = m.group(2)

        def field(name):
            f = re.search(name + r'="((?:[^"\\]|\\.)*)"', body)
            if not f:
                return None
            return f.group(1).encode('utf-8').decode('unicode_escape').encode('latin-1').decode('utf-8')
        kind = field('type')
        if kind in BODY:
            cards.append({'id': m.group(1), 'name': field('name') or '', 'type': kind, 'text': field('text') or '',
                          'race': RACES.get(field('race') or '') if kind == 'MINION' else None})
    return cards


def words(text):
    """Split rules text into words of (text, bold) pieces, as W.RichText does."""
    out, cur, bold, pos = [], None, False, 0
    def add(seg):
        nonlocal cur
        for ch in seg:
            if ch == ' ':
                cur = None
            else:
                if cur is None:
                    cur = []
                    out.append(cur)
                if cur and cur[-1][1] == bold:
                    cur[-1][0] += ch
                else:
                    cur.append([ch, bold])
    while pos < len(text):
        m = re.compile(r'<(/?)b>').search(text, pos)
        if not m:
            add(text[pos:]); break
        add(text[pos:m.start()])
        bold = m.group(1) == ''
        pos = m.end()
    for w in out:
        for piece in w:
            piece[0] = re.sub(r'<[^>]+>', '', piece[0])
    return [w for w in out if any(p[0] for p in w)]


_fonts = {}
def font(path, size):
    key = (path, int(size))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(str(path), max(1, int(size)))
    return _fonts[key]


def layout(ws, size, max_w, force=False):
    body, bold = font(BODY_FONT, size), font(BOLD_FONT, size)
    space = max(1.0, body.getlength('a a') - body.getlength('aa'))
    lines, line, line_w = [], [], 0.0
    for w in ws:
        ww = sum((bold if b else body).getlength(t) for t, b in w)
        if ww > max_w and not force:
            return None, space
        need = (space if line else 0) + ww
        if line and line_w + need > max_w:
            lines.append((line, line_w)); line, line_w = [w], ww
        else:
            line.append(w); line_w += need
    if line:
        lines.append((line, line_w))
    return lines, space


def render_name(card, H):
    """The name band at card height H (supersampled), white with a black outline."""
    W = H * CARD_ASPECT
    x0, x1, y0, y1 = NAME_BAND
    bw, bh = round((x1 - x0) * W), round((y1 - y0) * H)
    im = Image.new('RGBA', (bw, bh), (0, 0, 0, 0))
    box_w, box_h = NAME_W * W, NAME_H * H
    size = max(6, NAME_SIZE * H)
    min_size = size * 0.55
    while size > min_size and (font(TITLE, size).getlength(card['name']) > box_w or size * 1.05 > box_h):
        size -= H / 400
    f = font(TITLE, size)
    stroke = max(1, round(size * 0.085))
    d = ImageDraw.Draw(im)
    cx = (0.5 - x0) * W
    cy = (NAME_CY - y0) * H
    d.text((cx, cy), card['name'], font=f, fill=(255, 255, 255, 255), anchor='mm',
           stroke_width=stroke, stroke_fill=(0, 0, 0, 255))
    return im


def render_race(card, H):
    W = H * CARD_ASPECT
    x0, x1, y0, y1 = RACE_BAND
    im = Image.new('RGBA', (round((x1 - x0) * W), round((y1 - y0) * H)), (0, 0, 0, 0))
    f = font(TITLE, RACE_SIZE * H)
    ImageDraw.Draw(im).text(((0.5 - x0) * W, (RACE_CY - y0) * H), card['race'], font=f,
                            fill=(255, 255, 255, 255), anchor='mm',
                            stroke_width=max(1, round(RACE_SIZE * H * 0.08)), stroke_fill=(0, 0, 0, 255))
    return im


def render_text(card, H):
    kind = card['type']
    b = BODY[kind]
    W = H * CARD_ASPECT
    x0, x1, y0, y1 = body_band(kind)
    bw, bh = round((x1 - x0) * W), round((y1 - y0) * H)
    im = Image.new('RGBA', (bw, bh), (0, 0, 0, 0))
    ws = words(card['text'])
    if not ws:
        return None
    box_w, box_h = b['w'] * W, b['h'] * H
    size = max(5, BODY_SIZE * H)
    min_size = max(4, size * 0.6)
    step = H / 400
    while True:
        lines, space = layout(ws, size, box_w)
        if lines and len(lines) * size * 1.2 <= box_h:
            break
        if size <= min_size:
            lines, space = layout(ws, size, box_w, True)
            break
        size -= step
    body_f, bold_f = font(BODY_FONT, size), font(BOLD_FONT, size)
    line_h = size * 1.2
    top = max(0, (box_h - len(lines) * line_h) / 2)
    ink = INK[kind] + (255,)
    d = ImageDraw.Draw(im)
    # the box's left and top edges inside the band image
    left = ((0.5 + b['x']) - b['w'] / 2 - x0) * W
    box_top = (b['top'] - y0) * H
    for li, (line, lw) in enumerate(lines):
        x = left + max(0, (box_w - lw) / 2)
        base = box_top + top + li * line_h + size * 0.95   # baseline within the line
        for wi, w in enumerate(line):
            if wi:
                x += space
            for t, bold in w:
                f = bold_f if bold else body_f
                d.text((x, base), t, font=f, fill=ink, anchor='ls')
                x += f.getlength(t)
    return im


def fit(im, size):
    """Reduce a supersampled band to its file size, premultiplied so the
    transparent edges do not darken (Lanczos on straight alpha fringes)."""
    import numpy as np
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, alpha = a[..., :3] * a[..., 3:4], a[..., 3:4]
    pre = np.concatenate([rgb, alpha], axis=2)
    chans = [Image.fromarray((pre[..., i] * 255).astype(np.uint8)).resize(size, Image.Resampling.LANCZOS) for i in range(4)]
    out = np.stack([np.asarray(c).astype(np.float32) / 255.0 for c in chans], axis=2)
    al = np.clip(out[..., 3:4], 0, 1)
    rgb = np.where(al > 1e-4, np.clip(out[..., :3] / np.maximum(al, 1e-4), 0, 1), 0)
    res = np.concatenate([rgb, al], axis=2)
    return Image.fromarray((res * 255 + .5).astype(np.uint8), 'RGBA')


def bake(card):
    # Supersampled card heights chosen so each band lands on its file at SSx.
    nx0, nx1, ny0, ny1 = NAME_BAND
    H_name = NAME_FILE[1] * SS / (ny1 - ny0)
    name = fit(render_name(card, H_name), NAME_FILE)
    name.save(OUT / f"{card['id']}-n.tga", compression=None)
    tx0, tx1, ty0, ty1 = body_band(card['type'])
    H_text = TEXT_FILE[1] * SS / (ty1 - ty0)
    text = render_text(card, H_text)
    has_text = text is not None
    if has_text:
        fit(text, TEXT_FILE).save(OUT / f"{card['id']}-t.tga", compression=None)
    if card.get('race'):
        H_race = RACE_FILE[1] * SS / (RACE_BAND[3] - RACE_BAND[2])
        fit(render_race(card, H_race), RACE_FILE).save(OUT / f"{card['id']}-r.tga", compression=None)
    return has_text


def lua_rect(r):
    return '{%.4f,%.4f,%.4f,%.4f}' % r


def main(ids):
    OUT.mkdir(exist_ok=True)
    cards = printed_cards()
    if ids:
        cards = [c for c in cards if c['id'] in ids]
    entries, total = [], 0
    for c in cards:
        has_text = bake(c)
        entries.append((c['id'], c['type'], has_text, c.get('race')))
    for f in OUT.glob('*.tga'):
        total += f.stat().st_size
    if not ids:
        lines = [
            '-- GENERATED FILE -- DO NOT EDIT BY HAND.',
            '-- Regenerate with: python tools/build_card_text.py (docs/24)',
            '--',
            '-- Every card\'s name and rules text, baked into textures so a leaning',
            '-- hand card turns them smoothly. `name` / `text` are the rects each band',
            '-- image covers on the card face: {left, right, top, bottom}, fractions of',
            '-- the face, y down from the top. The files are Art/CardText/<id>-n.tga',
            '-- and <id>-t.tga. A card listed with text=false has no rules text.',
            'local ADDON, ns = ...',
            'local N = ' + lua_rect(NAME_BAND),
            'local B = {',
        ] + ['  %s = %s,' % (k, lua_rect(body_band(k))) for k in sorted(BODY)] + [
            '}',
            'local R = ' + lua_rect(RACE_BAND),
            'local RB = ' + lua_rect(RACE_BANNER),
            '-- { frame type, has a rules band, race printed on the race banner or nil }',
            'ns.CardText = { name = N, text = B, race = R, raceBanner = RB, cards = {',
        ]
        for cid, kind, has_text, race in sorted(entries, key=lambda e: e[0]):
            lines.append('  ["%s"] = { "%s", %s%s },' % (cid, kind, 'true' if has_text else 'false',
                                                       (', "%s"' % race) if race else ''))
        lines += ['} }', '']
        (ROOT / 'ForeverHearthstone' / 'Client' / 'Assets' / 'CardText.lua').write_text('\n'.join(lines), encoding='utf-8')
        report = {'cards': len(entries), 'files': len(list(OUT.glob('*.tga'))), 'bytes': total,
                  'name_file': NAME_FILE, 'text_file': TEXT_FILE, 'supersample': SS,
                  'fonts': ['Vollkorn-Black (names)', 'LibreFranklin-SemiBold / ExtraBold (rules)']}
        (ART / 'card-text-report.json').write_text(json.dumps(report, indent=2))
    print(f'{len(entries)} cards, {total / 1e6:.1f} MB in {OUT}')


if __name__ == '__main__':
    main(set(sys.argv[1:]))
