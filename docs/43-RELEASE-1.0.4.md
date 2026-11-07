# Forever Hearthstone 1.0.4

A large reliability and quality release, found by four rounds of independent
reviews (rules, bugs and player experience). Both players should update: some
duel fixes need both sides on 1.0.4, though 1.0.3 and 1.0.4 can still duel.

## Duels

- **Ending by agreement works for both players.** The "yes" can no longer be
  lost, and both players see "You both agreed to end the duel" with a Back to
  Menu button.
- **Disconnects and reloads end cleanly.** A duel one client had to stop
  (desync, error) now ends for both with no result, instead of leaving the
  other player alone and later handing them a win. Both players away at once
  is no result rather than a loss each. Rejoining after a /reload no longer
  gets stuck or aborts the other player.
- **Rematches after a claimed win or a leave are heard** (a lost message
  number used to block everything after it).
- **Safer against other players:** someone sharing your opponent's first name
  cannot take over your challenge or a rejoin; a stranger repeating challenges
  cannot block your own duel traffic; malformed messages are ignored instead of
  causing errors; a stranger's challenge cannot wipe a rematch you are settling
  or a practice game you are playing.
- **Duel from the main menu:** a new **Duel a Player** button challenges your
  target, or explains how. `/fh duel Name` works, including first-and-last
  names.
- Opening your collection from the duel deck picker keeps the duel; closing the
  picker calls it off and says so.
- Closing the deck picker, declining or an unanswered rematch no longer closes
  the main menu or locks out other challengers.
- In dungeons: zoning into an instance mid-duel counts as leaving the table;
  hidden positions or range answers no longer pause you or refuse a duel.
- Stalling opponents: a **Claim Victory** button on the board (it goes away if
  they play on).
- Right-click the enemy hero to squelch their emotes.

## In a match

- Cards whose bonus is ready **glow gold**, as in Hearthstone: Combo cards after
  you have played a card, Kill Command with a Beast, Mortal Strike at 12
  Health, Mind Control Tech, and the "if you have a Beast/Mech" battlecries.
- The mulligan says who goes first; Overload owed next turn is shown by the
  mana; an empty deck's tooltip shows the next fatigue damage.
- Refused moves are said by your hero on the board ("I don't have enough
  mana.") instead of in chat.
- The end screen shows your record and why the game ended.
- Card text is accurate in more places: the enlarged card from hand shows its
  current cost, Choose One spells show Spell Damage, Velen doubles healing in
  the text, Shadowform's hero power is not inflated, and new keyword notes for
  Spare Part, Counter and Mega-Windfury.

## Collection and decks

- Choose each deck's art (right-click a card in the deck, Use as Deck Art);
  automatic art now prefers your class's cards.
- **Copy** a deck from the deck editor.
- Cards with no copies left to add grey out while building.
- A full deck that is not legal says why, and pressing Use Deck explains it.
- Disenchanting warns which decks need that card; crafting an Epic or
  Legendary asks first.
- Type a rarity or a set ("legendary", "gvg", "naxx") in the search box to
  filter by it.
- Messages from the collection appear on the window, not only in chat.
- Old Murk-Eye can now be earned by every class.

## Progression and saving

- A level-40 character installing for the first time is told what it was
  given; new players get a three-line welcome.
- Open Packs on the main menu shows how many are waiting; `/fh open` opens the
  pack room.
- Deleting a character's save file no longer grants its milestone packs again.
- A save file once marked as tampered starts saving again when it opens
  cleanly, and data written by a newer version survives an older one.
- `/fh help` lists every command (`/fh help dev` for diagnostics); `/fh
  rewards` opens the Progression window.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.0.4.zip, then restart WoW completely. Saved collections
and decks carry over unchanged.

## Validation

All 1,340 automated suites pass. Review judges fuzzed 900 lockstep duels with
no divergence and checked every collectible spell's text against what it does
under Spell Damage and Velen. Network protocol unchanged (10). Changes that
would need a protocol bump (Hearthstone's mulligan hand order, a stronger
desync check) are deferred so 1.0.3 and 1.0.4 players can keep duelling.
