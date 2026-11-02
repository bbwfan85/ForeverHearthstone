# Menus and match inspection

## September 23 Hearthstone screen pass (collection, My Decks, Play Bots)

The three out-of-match screens were restyled on Hearthstone's own layouts; behaviour, controls and saved data are unchanged.

- **My Collection** is a book: leather cover, parchment pages, a shadowed fold and the class name across each page. Class crests run along the top as tabs (All, the nine classes and Neutral; only All, your class and Neutral when building a deck). The flat red header bar is gone. Search, the 0–7+ mana crystals, Owned, the filter menu and Packs sit in one dark tray under the book. Gold arrows on the book's edges turn pages, "Page N of M" and Craft/Disenchant sit in the book's bottom band, and owned counts hang under each card on a small dark tab. An even column count is a two-page spread whose gutter no card crosses; an odd count is a single page.
- **Deck editor**: the hero's portrait banner carries the editable deck name. Rows are Hearthstone deck tiles: mana crystal, name, the card's art fading in from the right, and a count box only for two copies. Legendaries are named in orange. The card count, Done and Use Deck sit at the foot.
- **My Decks**: six hero deck boxes to a page (gold rim, name banner, count in red until legal, glow on the active deck) with a small X/Sure? delete corner. Book arrows page through, and New Deck and Collection buttons sit underneath.
- **Play Bots**: the Play-screen layout. A book on the left holds the nine opponent portraits, then your deck boxes. A stage on the right shows the chosen hero large in a gold frame over the amber Choose Deck/Play button. The cabinet dims behind it and restores on Back to Hearth.

Assets are built by `tools/build_hs_menus.py`, with provenance in `Art/hs-menus-report.json`. The class crests are imported from Manacost-Labs/HeartPulse (the parchment and gold border's source). The page shade, deck tile, count box, page arrow, Play button and glow are generated procedurally. The mana crystal, gold border, parchment and hero art were already bundled. `W.GoldFrame`, `W.TrayPanel`, `W.StyleDeckBox`/`W.ClearDeckBox` and `W.StylePlayButton` in `Client/UI/Widgets.lua` are the shared pieces. The stub gained `SetShown` on textures and font strings (real Mainline Region API), and the preview exporter now layers edit boxes at their own frame level.

Validation: 928 suites, 39,462 assertions, 0 failures (new suites cover the spine gutter, tray/tab separation, deck tiles and the practice stage). Offline previews in `tools/*.png` are regenerated; they approximate rendering (no additive blending or text truncation). **Fully restart WoW** to load the new textures.

## September 23 carved cabinet pass

The main menu now uses a centered, illustrated oak-and-brass cabinet on blue leather, with four large ivory inset controls. Practice opens an arched hero gallery inside the same cabinet; Back to Hearth restores the main controls without starting a match. Collection, deck, and pack controls share the new inset button material, and their outer backdrop uses the tavern scene.

The cabinet fades in over 0.3 seconds and has three subtle animated light accents. Its update handler is removed on hide. Four original quiet PCM cues cover hover, click, page movement, and cabinet opening on the SFX channel; hover retains its existing throttle and sound-pack overrides still win. These are original synthesized cues, not Hearthstone recordings or a music loop.

Generated artwork sources are retained in `tools/menu-assets/tavern-*.png`; provenance and hashes are in `Art/tavern-media-report.json`. Rebuild textures with `tools/import_tavern_media.py` (Pillow) and audio with `tools/build_menu_sounds.py`. Artwork is Hearthstone-inspired, not extracted classic menu artwork.

Validation: 890 suites, 33,014 assertions, zero failures under LuaJIT 2.1. The frame stub now dispatches direct OnShow/OnHide callbacks, allowing entrance and cleanup checks. Reviewed offline previews at 1000x680 and 800x600 plus practice, compact deck editing, and packs. These previews approximate rendering; live-client appearance and audio levels have not been verified. **Fully restart WoW to load the new textures and sounds**, then use `/fh`.

The retail addon directory is a junction to this workspace. Fully exit and restart WoW after the September 23 menu update so the new texture files are available. The installed junction already points at the edited files.

- `/fh` is movable and resizable, with a bottom-right resize grip. Play Bots opens an opponent picker; selecting a class waits for Play. A valid active collection deck is used for practice, with the Basic deck as fallback.
- My Decks lists saved decks, creates new ones, and opens a deck editor. Click a deck row to remove one copy. Scroll the deck rows independently; Use Deck is enabled only for a valid deck.
- Open Packs has its own set picker and card-back opening target. Five cards are laid out around the center; click any unrevealed card. Revealed positions survive resizing. Contents are still banked before the reveal begins.
- The menus reuse the bundled Hearthstone board surface, carved turn-button texture, portraits and card backs. Collection uses two textured page panels. These are adapted existing assets, not newly imported original Hearthstone menu scenes.
- Right-click your hero for six emotes. Local and remote emotes appear beside their portraits. Emotes retain the separate network channel and do not change the action stream.
- Right-click a hand or board card for live stats and active effects with sources. Scroll the inspector for more than three entries. Permanent buffs, temporary keywords and auras retain provenance; silence, expiration, transformation and consumed keywords remove the relevant entries.
- Empty-deck draws retain the existing increasing fatigue rule. Their events now display a fatigue message and sound, alongside the existing hero damage hit. Rendering or resizing does not replay the cue.

Validation: the strict WoW stub exercises the actual UI callbacks and engine. `tools/menu_preview.lua` plus `tools/menu_preview.py` produce an offline composition preview at 800×600; it is not a live WoW screenshot. Final appearance, clipping, fonts, and pointer behavior still need a live-client check.


## September 23 collection and menu revision

The supplied 1660x891 screenshot exposed a missing invariant: cards fit inside the window but did not fill it. The solver now balances two-dimensional coverage with readability, distributes remaining space across both axes, and preserves the first visible card's row when the column count changes. Tests cover the supplied size, 760x560 deck editing, ultrawide and tall windows, and 4K.

Collection now has search, toggleable mana filters, an explicit class/ownership picker, non-overlapping page arrows, empty-result feedback, and separate ownership counts. The deck sidebar supports name editing, artwork rows, independent scrolling, and legal-deck selection. Menu borders use fixed-size corners and sampled edges instead of stretching complete buttons. Collection has parchment pages; packs use a dedicated scene and pack image. Portrait selection and saved-deck tiles use the new menu framing.

Asset provenance and original hashes: `ForeverHearthstone/Art/menu-media-report.json`. Scene/chest/pack sources are Rymedy/hearthstone-web; parchment, leather, and compact border sources are Manacost-Labs/HeartPulse. These are adapted community-hosted assets, not a pixel-perfect recreation of the original collection screen. Unsupported baked-in shop and mode labels are excluded through texture coordinates.

`tools/import_menu_media.py` converts retained source files to TGA. `tools/collection_preview.lua` exports actual region positions; `tools/collection_preview.py` renders offline approximations for collection, deck building, compact layouts, packs, and practice. Font metrics and WoW rendering still require live-client verification. The older menu preview represents the previous implementation.

Validation: 887 suites, 32,642 assertions, no failures under LuaJIT (Lua 5.1 semantics).


## September 23 effects and interaction pass

Shared menu buttons now tint their textured trim on hover, darken on press, and play SFX-channel interface cues. Hover audio is throttled to one cue per 120 ms; disabled controls and layout refreshes stay silent. Custom text anchors on portrait/deck buttons are preserved. Collection cards use their existing silhouette textures for hover and selection rather than solid-color rectangles.

Pack opening now displays the existing pack artwork during the wind-up and burst. Cards fade and grow into their assigned layout rectangles without accumulating the choreography's old fan offsets. Reveals contract horizontally, keep the back visible until the midpoint, then expose the front. Rare, epic, and legendary tells use blue, purple, and amber. Bursts originate at the clicked card; shake and scene dimming are now connected. Shared particles use additive textured glints instead of square pixels. Face-down cards hide all front artwork and ornaments, including during resizing, so the transparent back corners cannot leak the face.

Resizing or changing views cancels stale pack timelines, particles, sounds, dimming, and shake while preserving granted rewards and revealed-card state. Independent crafting/disenchant copies survive grid refreshes and finish normally. Hiding the collection stops all effects. This pass reuses installed artwork and existing SFX resolution; it adds no audio recordings or new asset files.

Validation: 890 suites, 33,009 assertions, zero failures. Tests cover concealed flip timing, restored geometry, burst position, texture preservation, audio throttling, disabled controls, cancellation, and face-down front visibility. Inspected the offline `tools/pack-reveal.png` composition; this is not a live-client screenshot. Live WoW audio levels and animation feel still need in-game verification. Use `/reload` to load these Lua changes; the previous pass's new menu textures require a full restart if the client has not loaded them yet.
