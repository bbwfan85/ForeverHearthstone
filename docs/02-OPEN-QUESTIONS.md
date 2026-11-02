# Deviation vs. Recreation Collisions

You told me to flag collisions and ask rather than resolve them. These came out
of the pinned data, not from speculation — each one is a place where your
exhaustive deviation list and Hearthstone's actual rules cannot both hold.

Four need your decision (asked in chat). Three I resolved, with reasoning, and
flag here for your veto.

---

## ANSWERED 2026-09-19 -> see [03-COLLECTION-DECISIONS.md](03-COLLECTION-DECISIONS.md)

C1 -> WoW-native paths (all four kept).
C2 -> class cards drop golden from mobs. NOTE: this reopens the levels 40-60 gap.
C3 -> Classic-only crafting, Basic dupes still dust. Plus: the whole Basic set is
      GRANTED, not collected, which is Hearthstone's own starter-deck mechanism and
      needs no deviation at all.
C4 -> levelling awards all 25 class cards; packs are neutral-only.

Original framing retained below for the record.

## (was) NEEDS YOUR DECISION

### C1. Four cards have no acquisition path at all

The pinned pool contains 4 collectible cards outside Basic/Classic:

| card | set | Hearthstone acquisition |
|---|---|---|
| Old Murk-Eye (EX1_062) | REWARD | collect every Murloc card |
| Captain's Parrot (NEW1_016) | REWARD | Collector's Edition **purchase** |
| Elite Tauren Chieftain (PRO_001) | PROMO | promotional / BlizzCon |
| Gelbin Mekkatorque (PRO_001a) | PROMO | promotional |

Deviation 6 removes the store and deviation 2 replaces all acquisition with WoW
play. Three of these were bought or handed out at events. They are currently
imported with `unobtainable=true` so nothing breaks either way.

Note Old Murk-Eye's real condition — "collect every Murloc" — maps *perfectly*
onto your set-trigger system and would be a genuinely great chase card.

### C2. Golden class cards are impossible by construction

* Deviation 1: class cards come **purely** from levelling.
* Deviation 3: golden cards are **drop-only**, never craftable.
* Class cards never drop.

Therefore **226 of 379 cards can never exist in golden form**, and golden
collecting is a neutral-only activity (153 cards). That may be fine, but it is a
consequence of two deviations colliding rather than a decision you made.

Worth noting: this collides with a *third* thing you asked about — what fills
levels 40–60 once class progression is exhausted. Golden class cards as a 40–60
track would resolve both at once.

### C3. Scope of the dust economy

Hearthstone's own data is unambiguous here: **the 142 Basic cards carry no dust
array.** They cannot be crafted or disenchanted. Only the 246 Classic cards have
dust values (verified — see 00-PATCH-PIN.md for the table).

Under your deviations, Basic = levelling reward, so crafting one is meaningless
and you can never hold a duplicate. Keeping Hearthstone's rule therefore fits
naturally — but it means the entire dust economy operates over 246 cards, not
379, which changes the completion maths substantially.

The awkward case is **golden Basic cards**. In Hearthstone they unlock at class
levels 50–60. Here they would have to drop, but deviation 3 says goldens are
drop-only while deviation 1 says class cards come from levelling.

### C4. Do Classic-set class cards come from levelling too?

You wrote "class cards awarded purely by levelling, full class set complete at
level 40". Each class has:

* 10 Basic class cards
* 15 Classic class cards (Rogue 16) — including the class legendaries
  (Tirion Fordring, Bloodmage Thalnos, Grommash, Edwin VanCleef…)

Read one way, "full class set" = all 25, and packs/mob drops are **neutral-only**.
Read the other way, only the 10 Basic ones are levelling rewards and the 15
Classic ones come from packs like everything else.

These produce completely different progression curves, pack contents and dust
economies, so I'm not picking. The first reading is what your wording suggests
and is the cleaner design; it also means a level-40 character has a guaranteed
complete class toolkit, which is a strong feel.

---

## RESOLVED — flagging for your veto

### R1. Neutrals account-wide, class cards per-character → **account-wide neutrals**

You asked me to recommend. **Neutral collection, dust and golden status
account-wide; class cards per-character.**

The data makes the case. Neutrals are 153 of 379 cards — 40% of the pool, and
the *majority* of any given deck, since a character can only ever access
25 class cards + 153 neutrals = 178 cards. Because a WoW character is one class
permanently, per-character neutrals would mean every new alt grinds the same 153
cards from scratch before it can build anything, and your deckbuilding variety
comes almost entirely from that pool. Account-wide neutrals make an alt
immediately playable, which is the whole point of the class-locking deviation.

Class cards stay per-character because they are levelling rewards for *that*
character's levelling.

Consequence: the dust pool must be account-wide too, or dust earned by
disenchanting an account-wide neutral would be trapped on one character.

### R2. Patch pin → **build 5834**

The entire difference between your two options is `Unleash the Hounds` at 2 vs
3 mana. Full evidence in 00-PATCH-PIN.md. Choosing a patch where it is already
3 is selecting a date, not rebalancing. Both builds are vendored; switching is
a two-line change.

### R3. Turn timer during world interruption

The rope must pause when a match pauses for a world event (deviation 5), which
is a deviation from Hearthstone's timer. Unavoidable and uninteresting — a
paused rope is obviously right. Recorded so it isn't mistaken for an oversight
later. Turn count and fatigue are unaffected by pausing.

---

## Not a collision, but flagging a real risk

**Unsolicited whisper advertising.** You asked that a challenged player who
lacks the addon be whispered a download pitch. Mechanically that's easy. The
problem is it's an automated unsolicited whisper to a stranger, which is what
gold-spam looks like from the receiving end, and it's the kind of thing that
attracts reports and Blizzard attention regardless of intent.

I'll build it, but gated: **once per target character ever** (persisted), off by
default or opt-in on first run, and phrased as a single short line. I'd raise
this again before it ships. It's your call, not a refusal — I just don't want it
to be the reason the addon gets a policy problem.
