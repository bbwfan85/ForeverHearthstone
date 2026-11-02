# 16. Art check: End Turn, the result screen, packs, taunt glow, costs, the corner

Written 2026-09-24. `./run-tests.sh`: 992 suites, 0 failures. **Restart WoW**
once for the new textures (listed below); after that Lua changes need only `/reload`.

Every screen was rendered offline (`tools/collection_preview.lua` / `.py`) and
compared with Hearthstone's own screens: the real End Turn button in
`Art/board.tga`, the wiki's classic victory screenshot, and the real Open Packs
room and pack reveal.

| Report | Cause | Fix |
|---|---|---|
| End Turn not exactly Hearthstone's | `turn-button.tga` was a procedural flat-yellow fill in a cut-out of the painted socket, dark serif lettering, dimmed by a vertex tint on their turn | `tools/build_turn_button.py` lifts the **real** button from `board.tga` (a capture of the live table): silver bevel, mottled yellow glaze. Its "END TURN" lettering is inpainted (diffusion + soft mottle) so the addon prints END TURN / ENEMY TURN / GAME OVER in **black** capitals, as the game does. Their turn uses `turn-button-enemy.tga`, the same bevel with the glaze drained to grey. Never green |
| VICTORY banner not Hearthstone's | A red ribbon with gold VICTORY under an oval-masked portrait | `tools/build_result_art.py` keys Hearthstone's classic victory ornament out of the wiki screenshot (the table behind it is grey, so gold and blue key on saturation; stray glow is dropped by connectivity, pinholes closed). Now: the table **drained to grey** (`SetDesaturated`) and dimmed, your hero in the gilded arch under the **crown, laurels, trumpets and blue banners**, and the **wooden plaque** reading "Victory!" in white, black-edged. A defeat keeps the arch and plaque ("Defeat") without the laurels, portrait cracked and drained. Rematch / Main Menu sit under the banners |
| Opponent class names too dark | The opponent tiles are menu buttons; the button's hover/leave feedback repaints its label the plaque's dark brown, so after one hover the names went dark on their black strips | The tiles carry `textColor` (light), which the feedback honours |
| Pack opening background off; text not centred | The room was only the well, cropped, over a tavern backdrop; the hint, pack and blurb sat on fixed fractions unrelated to the art | `tools/build_pack_room.py` keeps Hearthstone's **whole** Open Packs room (purple tray, wooden frame, painted "Open Packs" plaque, the well) with its Shop button removed. The pack stands centred on the tray with its blurb under it; the hint is centred under the well. Opening a pack darkens the room and deals the cards as Hearthstone does: **three above (the middle highest), two below**, round the well's centre, each card's class ("All Classes", "Druid") under it as it turns, and **Done** in the middle once all five are up. No "Choose a card" text (Hearthstone has none) |
| Green "can attack" border wrong on taunt minions | The glow is a ring round the oval frame, drawn *behind* the taunt shield, which stands past the oval -- so the shield hid it | `tools/build_taunt_glow.py` traces the same soft ring round the shield + frame (`inplay_minion_taunt-glow.tga`, a canvas 1.25x the frame's). A minion wearing taunt switches to it (`cardFitGlow`), and back when silenced |
| Main Menu in a different place on each screen | Collection: a plaque at a fixed offset; practice: "Back to Hearth" at the bottom; board: none; the close was a letter X on some screens and a gilded round button on others | `Widgets.WindowControls`: every window's top-right corner is, right to left, the gilded round close, **Main Menu** (same size everywhere; hidden only on the main menu itself), any screen extras (My Decks), then the speaker. Practice keeps only **Back** (decks -> opponents) under the book. The My Decks delete X is the same round gilded cross |
| Collection mana costs off-centre, worst on two digits | Every cost was placed at the spell gem's centre (36/256); the minion gem is at 30.5, the weapon's at 34/85. Two digits used a fixed pitch, so "10" leaned right (the 1 is narrower) and ran wider than the gem | `Widgets.COST_GEM` per frame, measured from each `inhand_*` texture's gem. Digits are laid out by their **ink** widths with a slight outline overlap and the ink span centred (`GLYPH_INK`); two digits drop to 84%. Attack / health nudged onto the weapon's swords and shield |
| (found on the way) Mulligan heading dim | "Choose cards to replace" lived on the board frame, under the mulligan dimmer | Prompt lettering (mulligan heading, Choose One) is on a layer above the dimmers, in white |

## New files -- restart WoW once

`Art/turn-button-enemy.tga`, `Art/result-ornament.tga`, `Art/result-frame.tga`,
`Art/result-plaque.tga`, `Art/mask-result-arch.tga`, `Art/pack-room.tga`,
`Art/inplay_minion_taunt-glow.tga` (and `turn-button.tga` changed).
`hs-ribbon*.tga` and `menu-pack-room.tga` are no longer drawn.

## Checked in game (needs a client)

1. Practice: End Turn yellow with black lettering on your turn, grey "ENEMY TURN"
   on theirs; hover brightens it.
2. Give a minion taunt that can attack: the green glow follows the shield.
3. Win and lose a game: crown/laurels/banners on a win, arch only on a loss; the
   table goes grey behind; Rematch / Main Menu below.
4. Open Packs: the room fills the window; drag a pack to the well; cards land in
   the 3-over-2 deal with class names; Done closes.
5. Every screen: close top-right, Main Menu beside it (not on the main menu).
6. Collection filter 7+: 10 / 12 / 20 centred on their gems.
