# Forever Hearthstone 0.2.5

## Progression and rewards

- Added a Progression button between Challenges and Settings. Browse the scrollable level reward track, pack contents and drop odds there.
- All ten Basic class cards are available from the start. Level rewards unlock Classic class cards at odd levels 3–31 and Naxxramas/GvG class cards at levels 36–60. Existing cards are preserved and missed grants catch up at login.
- Reward cards show their artwork and support right-click inspection. Removed empty-level filler and corrected number alignment and card text formatting.
- All successful mob and boss drops now award packs, never single cards. Combined packs include Classic, GvG and Naxxramas neutral cards.
- Base pack chances remain normal 1.5%, elite 4%, rare 5%, repeat dungeon boss 12%. First encounter kills and raid bosses guarantee a pack; saved bad-luck protection remains.
- Pack and class-card reward notifications appear automatically at the top center. Packs are banked immediately; no click is required. Level-ups print actual rewards in chat.
- Added Preview Pack Drop under Progression → Pack & Drop Odds. It plays the notification without changing your collection.

## Menu fixes

- Removed pulsing decorative circles from the menus.
- Fixed the bot opponent and difficulty labels overlapping at smaller window sizes.

## Installation and validation

Replace the old ForeverHearthstone addon folder with the folder from the ZIP, then restart WoW. Protocol remains 10.

All 1,281 automated suites passed (98,042 assertions), plus 20 compiler tests (247 checks). The build checked 1,031 texture references. All 3,970 archive entries matched the staged files and the packaged-addon smoke test passed. Live two-player networking, reward persistence and the latest visual changes still need live-client verification.
