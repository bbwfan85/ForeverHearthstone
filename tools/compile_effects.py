"""
Forever Hearthstone -- spreadsheet -> Lua effect compiler.

WHY THIS EXISTS
  459 of 535 pool cards need a hand-authored effect script. Writing 459 nested
  Lua tables by hand is a data-entry job with a typo budget of zero. Instead you
  author terse rows in CSV and this compiles + VALIDATES them into
  ForeverHearthstone/Data/Effects/Generated.lua.

  Pinned build: 7234 (Basic + Classic + Naxxramas + GvG). Card stats NEVER appear
  in a script -- they live in generated printed data. A script is behaviour only.

  Run:  python tools/compile_effects.py
        python tools/compile_effects.py --coverage     (report only, no write)

  VALIDATION (nothing is written if any error fires):
    * unknown card id, op, selector, condition or keyword
    * unknown summon/transform token id   <- catches the wrong-token bug
    * the same card+hook authored in two files
    * script on a card whose printed data says it needs none  -> warning
  Errors name the source file and line.

AUTHORING FILES
  tools/effects.csv  plus every  tools/effects/*.csv
  The directory exists so several people (or agents) can author in parallel
  without colliding. All files share one header.

CSV COLUMNS
  card_id, hook, trigger, cond, ops, flags, notes

  hook     battlecry | combo | deathrattle | spell | aura | enrage
           | trigger | secret | heropower | ondraw
           | property
           NOTE a `cond` on a DEATHRATTLE row is rejected: the deathrattle is
           stored as bare ops and the condition would never be evaluated. Put it
           inside the ops as If(<cond>){...}.

           `property` declares a top-level SCRIPT FIELD the ENGINE reads, rather
           than ops it runs. This is what used to force a card into
           Handwritten.lua. Known properties:
               SpellMultiplier(n)        Prophet Velen
               DeathrattleMultiplier(n)  Baron Rivendare
               HealsDealDamage()         Auchenai Soulpriest
               AttacksPerTurn(n)         V-07-TR-0N (Mega-Windfury)
  trigger  event name, for hook=trigger|secret   (e.g. MINION_SUMMONED)
  cond     condition DSL; blank means unconditional. Also gates an `aura`.
  ops      semicolon-separated op DSL
  flags    secret rows:  cancels | exclusive | anyturn
           trigger rows: hand  -- fire while the card is IN HAND (Bolvar).
           A flags value on any other hook is an ERROR: it used to be silently
           discarded, which is how Bolvar first compiled cleanly and did nothing.
  notes    ignored by the compiler

  COMBO REPLACES the battlecry/spell rather than adding to it, so a Combo card
  that also does something unconditionally needs BOTH rows, and the combo row
  must repeat the base effect. See EX1_137 Headcrack.

SELECTOR DSL
  Shorthands:
    self  target  payload  attacker  defender
    adjacent           board neighbours of the SOURCE
    adjacent@target    board neighbours of the chosen TARGET
    adjacent@defender  board neighbours of an ATTACK's defender. Attack payloads
                       carry `defender`, never `target`, so adjacent@target
                       cannot serve Foe Reaper 4000.
    lastSummoned       the entity an EARLIER OP in this same list just summoned
    lastDrawn          ...or just drew. Nothing else can name "the thing I just
                       made" (Noble Sacrifice, Redemption, Holy Wrath).

  General form: scope.filter[.filter...]   -- filters COMPOSE
    scope    friendly | enemy | any
    filters  minion spell weapon hero char        (type; `char` adds heroes)
             hand deck secret graveyard play      (zone)
             beast demon dragon murloc pirate totem mech   (race)
    e.g.  friendly.hand.minion     minions in your hand
          enemy.minion             opponent's minions
          any.char                 every character, both heroes included
          friendly.beast           your Beasts
          friendly.weapon          your equipped weapon

  Extra filters in the chain:
    deathrattle   carries a deathrattle, PRINTED OR GRANTED   (Scarlet Purifier)
    battlecry     printed BATTLECRY; works in HAND            (Nerub'ar Weblord)
    issecret      the card IS a Secret -- NOT the same as the `secret` ZONE.
                  `friendly.deck.issecret` is a Secret in your deck;
                  `friendly.secret` is whatever is in your secret zone.
    id=CARDID     exactly this card    (Feugen asking whether Stalagg died)

  Trailing modifiers, any order:
    !self     exclude the source        !target  exclude the chosen target
    ~N        N at random (seeded)       #N      first N in board order
    +taunt    require keyword            -taunt  exclude keyword OR RACE
                                                 (`-mech` = a non-Mech minion)
    <N / >N   max / min attack           dmg / nodmg   damaged / undamaged

  NOTE "characters" includes heroes, "minions" does not. Conflating them is an
  easy and invisible error.

AMOUNTS
  A literal, or one of these dynamic forms:
    count(sel)      how many entities match          ("+1 for each ...")
    attackOf(sel)   that entity's attack             (Shadowflame)
    armorOf(sel)    that entity's armor              (Shield Slam)
    healthOf(sel)   that entity's CURRENT health
    damageOf(sel)   damage that entity has TAKEN     (Molten Giant)
    N-M             a seeded roll in [N,M]           (Crackle's $3-$6)
                    Rolled ONCE per op, not once per target: Lightning Storm
                    deals the same amount to every enemy minion.
    dealt           the amount the PREVIOUS op used  (Imp-losion's Imp per damage)
    payloadAmount   the amount carried by the EVENT being handled. A trigger
                    runs with a fresh ctx, so `dealt` cannot reach the damage it
                    is REACTING to -- use this instead (Mistress of Pain).
    costOf(sel)     that entity's current cost       (Holy Wrath)
    sub(a, b)       a minus b, clamped at zero       (Divine Favor, Jeeves)
    cardsPlayedEarlierThisTurn                       (Edwin VanCleef)
  A dynamic amount of 0 really means 0 -- Draw with a dynamic zero draws nothing.

OP DSL
  damage / healing
    Damage(sel, amount)          MissileSplit(sel, amount)
    DamageFrom(from, sel, amount)  -- dealt BY `from` (a minion), not the spell:
                                   -- no Spell Damage; its Poisonous applies (Betrayal)
    Heal(sel, amount)            SetHealth(sel, n)
    GainArmor(sel, amount)
  stats and keywords
    Buff(sel, atk, hp[, KW])     SetAttack(sel, n)
    DoubleAttack(sel)            DoubleHealth(sel)
      -- ADDS the current value once; it is an enchantment, not a multiplier
      -- that keeps applying (Blessed Champion, Divine Spirit)
    SwapHealth(sel)              -- source <-> target CURRENT health (Vol'jin);
                                 -- damage does not travel with the swap
    GiveKeyword(sel, KW)         RemoveKeyword(sel, KW)
    Swap(sel)                    InnerFire(sel)
    Silence(sel)                 Freeze(sel)
    -- TIMED variants; same args but they expire:
    BuffTurn(sel, atk, hp[, KW])        "this turn"
    BuffNextTurn(sel, atk, hp[, KW])    "until your next turn"
    KeywordTurn(sel, KW)                "this turn"
    KeywordNextTurn(sel, KW)            "until your next turn"
  board
    Summon(cardId[, n][, enemy])   SummonEntourage([enemy])
    Destroy(sel)                   ReturnToHand(sel)
    TakeControl(sel[, enemy][, ready])      Transform(sel, cardId)
      -- `enemy` hands the minion TO the opponent (Shadow Madness returns it);
      -- `ready` lets it attack this turn without Charge. If the receiving board
      -- is full the minion is DESTROYED, as in Hearthstone
    CopyToBoard(sel)               CopyPrinted(sel)
  moving cards BETWEEN ZONES (no mana is paid, no battlecry fires)
    MoveToHand(sel)                from ANY zone into its owner's hand
    MoveToBoard(sel[, enemy])      straight into play  (Voidcaller, Deathlord)
    MoveToSecret(sel)              into the secret zone (Mad Scientist)
    CopyToHand(sel[, n][, enemy])  copies the PRINTED card, never the buffed one
    MillDeck(n[, enemy])           discard the top n of a deck (Fel Reaver)
    ShuffleCardIn(cardId[, n][, enemy])   (Iron Juggernaut)
    SwapWithHand(sel)              source <-> a card in hand (Alarm-o-Bot)

  generating a card NOBODY DRAFTED, from the collectible pool
    AddRandomCard(pool[, n][, enemy][, Nless])   `3less` = Unstable Portal
    SummonRandom(pool[, n][, enemy])
    TransformRandom(sel, pool)
    EquipRandom([enemy])
    POOL FILTER: `+`-joined terms, a grammar of its OWN -- it picks a printed
    card from the whole collectible pool, NOT an entity already in the game:
        minion spell weapon          card type
        beast demon dragon murloc pirate totem mech    race (implies minion)
        legendary epic rare common   rarity
        cost=N                       exact printed cost
        cost=target                  the chosen target's cost (Recombobulator)
      e.g.  beast     minion+cost=2     minion+legendary     weapon
    Only COLLECTIBLE cards are ever generated -- never tokens.

  cards
    Draw(amount)                   DrawEnemy(n)
    AddCard(cardId[, n][, enemy])  AddCardEntourage([enemy])
    CopyEnemyHandCard()            Discard(n)
    ShuffleIn(sel)
  mana and weapons
    Mana(n[, temporary|empty][, enemy])
    LoseManaCrystal([n][, enemy])  -- Felguard. Mana() cannot go negative.
    Equip(cardId)                  DestroyWeapon([enemy])
    (Overload is PRINTED data, applied automatically -- NEVER script it)
  player-scoped timed modifiers
    scope = self|enemy . spell|secret|minion|any
    charges = a number, or "-" for unlimited.  duration = turn | nextturn
    CostDelta(scope, n, charges, duration)   e.g. CostDelta(self.spell, -3, 1, turn)
    CostSet(scope, n, charges, duration)     e.g. CostSet(enemy.spell, 0, -, nextturn)
    ClampHealth(side, min, duration)         e.g. ClampHealth(self, 1, turn)
  deferred / turn-scoped
    AtEndOfTurn{ops}    fires at the END of the CURRENT turn
    AtNextTurn{ops}     fires at the START of your next turn
    ResummonDied()      friendly minions that died this turn
  RETARGETING -- only meaningful inside a SECRET, because a secret resolves
  INLINE inside the raise that triggered it, so the payload it mutates is still
  the one the caller is about to read. An ordinary trigger is queued and runs
  after the damage. Use the PRE_ATTACK event, which is where the defender is
  re-read.
    RetargetAttack(sel)   Misdirection, Noble Sacrifice
    RetargetSpell(sel)    Spellbender

  other one-offs
    TriggerDeathrattles(sel)      fire them WITHOUT killing (Feign Death)
    GiveSpellDamage(sel, n)       a granted Spell Damage bonus (Ancient Mage)
    BecomeCopy(sel)               Transform into the SELECTED minion, keeping
                                  its current stats (Faceless Manipulator)
    StealSecret(sel)              move a secret between secret zones (Kezan)
    DestroyAllButOneRandom(sel)   Brawl -- `~N` picks N, this picks the REST
    DestroyInHand(sel)            ProcessDeaths never scans hands

  control flow and hooks
    If(cond){ops}{ops}   Repeat(amount){ops}   ForEach(sel){ops}
      -- Repeat takes any AMOUNT, including `dealt` (Imp-losion)
    RepeatUntil(cond){ops}  -- loop until the condition holds. Internally
                               bounded, because a board where nothing can die
                               would otherwise hang the client (Bouncing Blade)
    OneOf{ops}{ops}[{ops}...]  -- run exactly ONE branch, chosen at random from
                                  the shared stream (Tinkmaster, Enhance-o Mechano)
    Deathrattle(sel){ops}                 AddTrigger(sel, EVENT){ops}
      -- Deathrattle APPENDS: a minion may already have one, and granting a
      -- second must not destroy the first (Ancestral Spirit on a Loot Hoarder)
  auras (use the `aura` hook, and the cond column to gate them)
    A WEAPON can host an aura too (Cogmaster's Wrench), and an aura may target
    `self`, including a weapon buffing itself.
    Aura(sel, atk, hp[, KW+KW])   AuraCost(sel, delta[, floor])
      -- floor: "but not less than (N)"; never raises a cheaper card (Summoning Portal)

    A magnitude may be DYNAMIC -- any of the AMOUNTS forms above, optionally
    negated -- and it is re-read on every rebuild, so it tracks the game with no
    invalidation needed:
        AuraCost(self, -count(friendly.hand!self))    Mountain Giant
        AuraCost(self, -damageOf(friendly.hero))      Molten Giant
        Aura(self, count(any.murloc!self), 0)         Old Murk-Eye

    A card IN HAND may host an aura, but ONLY over `self` -- that is what lets
    the Giants discount themselves while still in hand. Any other hand aura is
    ignored, because a Sorcerer's Apprentice in hand must not discount anything.
  enrage (use the `enrage` hook)
    Aura(self, atk[, hp][, KEYWORD])

  IDIOMS worth knowing, found while authoring:
    * "+1 per X"          ForEach(X){ Buff(self, 1, 0) }   -- buffs accumulate
    * "restore to full"   Heal(sel, 99)   -- Game:Heal clamps to damage taken
    * "was a target given" If(Count(target, 1)){ ... }
    * "discard your hand" Discard(10)     -- HAND_LIMIT
    * If(){}{} NESTS. The then-block's non-greedy match backtracks correctly
      through inner braces and semicolons, so a branch may contain another If.
      That is what makes Lorewalker Cho ("the OTHER player", whichever side Cho
      is on) and Jeeves ("that player draws until they have 3") expressible with
      no new primitive at all -- put the side choice INSIDE the branches.

CHOOSE ONE
  You NEVER author a Choose One parent. Author its two MODES instead, by their
  own card ids -- EX1_166a and EX1_166b, not EX1_166 -- and the parent counts as
  covered once both exist. A script on the parent is an error, because the
  engine substitutes the chosen mode's script for the parent's and a parent
  script could never run.

  The mode's HOOK follows the PARENT's type, not the mode card's:
      parent MINION  ->  hook = battlecry     (Keeper of the Grove)
      parent SPELL   ->  hook = spell         (Wrath)
  Mode cards are all typed SPELL in printed data, which is a data artefact and
  not what they are; using `spell` on a minion's mode would author a body that
  never runs. The compiler checks this.

  Targeting needs no authoring at all -- each mode card carries its own
  playRequirements and Engine/Targeting reads them.

CONDITION DSL
  Combo            HasWeapon         HandNotEmpty      BoardFull
  ManaFull         -- the controller already has 10 mana crystals (Wild Growth)
  SelfDamaged      HasOverload
  Count(sel, min)  TargetHasRace(race)
  -- target-shape predicates. `target` as a SELECTOR bypasses every filter (it
  -- returns the chosen entity directly), so Count(target +frozen, 1) can never
  -- work. Use these instead:
  TargetIsDamaged  TargetAlive       TargetIsFrozen
  TargetHasKeyword(KW)
  TargetIsFriendly -- the target is the caster's own (Demonfire, Demonheart)
  PayloadAttackAtLeast(n)
  PayloadIsMinion  PayloadIsSpell    PayloadIsSelf     PayloadIsMine
  PayloadSummonedByMe                PayloadSourceIsSelf
  PayloadTargetIsHero                PayloadFatalToMyHero
  PayloadAttackerIsMinion            PayloadAttackerIsEnemy
  PayloadHasRace(race)               PayloadAttackAtMost(n)
  MyTurn           -- the controller's own turn. TURN_END and TURN_BEGIN fire
                      for BOTH players, so anything that should act only on its
                      owner's turn must say so (Fel Cannon).
  DamageKilled     -- did the PREVIOUS op's damage kill? (Mortal Coil)
  DamageSurvived   -- ...or not? (Slam). Decided by the target's resulting
                      HEALTH, so a Divine Shield that absorbs the hit counts as
                      a survival. Both are false when no damage op ran.
  MyHeroHealthAtMost(n)              (Mortal Strike)
  Chance(n)        -- an n%% roll from the SEEDED stream, never math.random
                      (Nat Pagle)
  PayloadCostAtMost(n)               (Gazlowe's "a 1-mana spell")
  PayloadHasDeathrattle              (Undertaker)
  PayloadIsSecret                    (Secretkeeper)
  PayloadHasOverload -- the played CARD carries printed Overload. NOT the same
                      as HasOverload, which reads the player's locked mana, i.e.
                      LAST turn's lock (Unbound Elemental)
  PayloadAttackerIsSelf -- attack payloads carry `attacker`, so PayloadIsSelf
                      and PayloadSourceIsSelf are both false on them
  PayloadTargetIsMyHero -- PayloadTargetIsHero does not test OWNERSHIP, and a
                      secret does fire on the opponent's turn (Eye for an Eye)
  PayloadCardIs(CARDID) -- identity of the card in the payload. Gallywix needs
                      it to refuse its own Coin, or the opponent playing that
                      Coin re-triggers it into an unbounded engine.
  Combinators:  not X      X and Y      X or Y

KEYWORDS accepted anywhere a KW is taken
  taunt charge divineshield windfury stealth poisonous frozen
  cantattack immune forgetful
  nospell   (= CANT_BE_TARGETED_BY_SPELLS)
  nopower   (= CANT_BE_TARGETED_BY_HERO_POWERS)
"""
import argparse, csv, os, re, sys, json, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chooseone

HERE  = os.path.dirname(os.path.abspath(__file__))
ROOT  = os.path.dirname(HERE)
# Authoring input: tools/effects.csv plus every tools/effects/*.csv.
# The directory exists so multiple people (or agents) can author in parallel
# without colliding on one file. All files share the same header and format.
CSV_IN  = os.path.join(HERE, "effects.csv")
CSV_DIR = os.path.join(HERE, "effects")
BUILD   = 7234        # keep in sync with tools/import_cards.py
PRINTED = os.path.join(HERE, "vendor", "cards.%d.enUS.json" % BUILD)
OUT     = os.path.join(ROOT, "ForeverHearthstone", "Data", "Effects", "Generated.lua")
#[[ Cards whose scripts the DSL cannot yet express live here, hand-written in
#   Lua and loaded AFTER Generated.lua. They are just as implemented as any
#   compiled card, so coverage has to count them -- it did not, and reported
#   three finished cards as missing. Read by id only; the bodies are Lua and
#   none of this tool's business. ]]
HANDWRITTEN = os.path.join(ROOT, "ForeverHearthstone", "Data", "Effects", "Handwritten.lua")

POOL_SETS    = ("CORE", "EXPERT1", "NAXX", "GVG", "PROMO", "REWARD")

#[[ Cards the ENGINE hands out with nothing in a script asking for them.
#   Engine/Game.lua holds the same id in COIN_ID and tests/test_pin.lua pins
#   its identity; this list is the coverage report's half of that pairing. ]]
ENGINE_DEALT = {"GAME_005"}
#[[ Mirrors ns.HERO_POWER_BY_CLASS in Engine/Enums.lua. Duplicated rather than
#   parsed out of the Lua, and a test asserts the two agree -- a silent drift
#   here would hide exactly the gap this list exists to surface. ]]
HERO_POWER_BY_CLASS = {
    "DRUID": "CS2_017", "HUNTER": "DS1h_292", "MAGE": "CS2_034",
    "PALADIN": "CS2_101", "PRIEST": "CS1h_001", "ROGUE": "CS2_083b",
    "SHAMAN": "CS2_049", "WARLOCK": "CS2_056", "WARRIOR": "CS2_102",
}
STATIC_KEYWORDS = {
    "TAUNT","CHARGE","DIVINE_SHIELD","WINDFURY","STEALTH","POISONOUS",
    "CANT_ATTACK","CANT_BE_TARGETED_BY_SPELLS",
    "CANT_BE_TARGETED_BY_HERO_POWERS","ImmuneToSpellpower",
    # GvG: FORGETFUL is a static attack-redirect property of the minion, read
    # by Game:Attack rather than scripted. Only Dunemaul Shaman has it.
    "FORGETFUL",
}
HOOKS = {"battlecry","combo","deathrattle","spell","aura","enrage",
         "trigger","secret","heropower","ondraw","property"}

errors, warnings = [], []
ROW_ORIGIN = {}
def err(row, msg):
    where = ROW_ORIGIN.get(row) or ("row %s" % row)
    errors.append("%s: %s" % (where, msg))
def warn(msg):      warnings.append(msg)

# ----------------------------------------------------------------- card data

def load_cards():
    cards = json.load(open(PRINTED, encoding="utf-8"))
    by_id = {c["id"]: c for c in cards}
    pool  = {c["id"]: c for c in cards
             if c.get("collectible") and c.get("set") in POOL_SETS
             and c.get("type") != "HERO"}
    return by_id, pool

def load_handwritten():
    """Card ids defined in Handwritten.lua, by `S["ID"] = {` assignment.

    Deliberately a narrow pattern: a line that does not match is counted as
    missing, which over-reports work to do. The opposite mistake -- counting a
    card as done when it is not -- is the one that actually costs something."""
    if not os.path.exists(HANDWRITTEN):
        return set()
    src = open(HANDWRITTEN, encoding="utf-8").read()
    return set(re.findall(r'^S\["([A-Za-z0-9_]+)"\]\s*=', src, flags=re.M))


def needs_script(c):
    """Does this printed card require a hand-authored effect script?"""
    mech = set(c.get("mechanics") or [])
    if mech - STATIC_KEYWORDS:
        return True
    if c["type"] in ("SPELL", "HERO_POWER"):
        return True
    txt = c.get("text")
    if not txt:
        return False
    # Flavour in plain type rather than italics: Shadow of Nothing's text is
    # "Mindgames whiffed! Your opponent had no minions!" -- a 0/1 that does nothing.
    if c["id"] in ("EX1_345t",):
        return False
    #[[ Text that merely RESTATES printed data needs no script.
    #
    #   CRITICAL: a reminder sentence is only strippable when the card ACTUALLY
    #   CARRIES the mechanic it describes. Stripping unconditionally produces a
    #   FALSE NEGATIVE, which is far worse than the false positive it fixes: the
    #   coverage report would call a card complete while it did nothing at all.
    #
    #   The live example is "50% chance to attack the wrong enemy". Only Dunemaul
    #   Shaman (GVG_066) has the FORGETFUL mechanic. Ogre Ninja, Ogre Warmaul and
    #   Ogre Brute carry the same sentence with NO tag, so for them the behaviour
    #   is genuinely unprinted and must be scripted. ]]
    mechset = set(c.get("mechanics") or [])
    stripped = re.sub(r"</?b>|</?i>|\[x\]", "", txt)

    def strip_if(mechanic, pattern):
        """Remove a reminder line only when the card really has that mechanic."""
        nonlocal stripped
        if mechanic is None or mechanic in mechset:
            stripped = re.sub(pattern, "", stripped, flags=re.I)

    strip_if("TAUNT",          r"\bTaunt\b")
    strip_if("CHARGE",         r"\bCharge\b")
    strip_if("DIVINE_SHIELD",  r"\bDivine Shield\b")
    strip_if("WINDFURY",       r"\bWindfury\b")
    strip_if("STEALTH",        r"\bStealth\b")
    strip_if("POISONOUS",      r"\bPoisonous\b")
    strip_if("POISONOUS",      r"Destroy any minion damaged by this minion\.?")
    strip_if("CANT_ATTACK",    r"Can't Attack")
    strip_if("CANT_BE_TARGETED_BY_SPELLS",
             r"Can't be targeted by [^.]*\.?")
    strip_if("FORGETFUL",      r"50% chance to attack the wrong enemy\.?")
    # these two are printed FIELDS rather than mechanics, so they are
    # unconditional -- spellDamage and overload are always honoured by the engine
    strip_if(None, r"Spell Damage \+\d+")
    strip_if(None, r"Overload:?\s*\(?\d+\)?")

    #[[ TEXT THAT IS ENTIRELY ITALIC IS FLAVOUR, not rules.
    #
    #   Worthless Imp's whole printed text is "<i>You are out of demons! At
    #   least there are always imps...</i>", which is a joke, not behaviour.
    #   Checked BEFORE the tags are stripped, and safe because NOT ONE card in
    #   the collectible pool has entirely-italic text -- so this can never hide
    #   a real effect, which is the failure mode that matters here. ]]
    if re.fullmatch(r"(?:\[x\])?\s*<i>.*</i>\s*", txt, flags=re.S):
        return False

    stripped = re.sub(r"\(\s*\)", "", stripped)
    stripped = re.sub(r"[.\s,]", "", stripped)
    return bool(stripped)

# ----------------------------------------------------------------- selectors

RACES = {"beast":"BEAST","demon":"DEMON","dragon":"DRAGON","murloc":"MURLOC",
         "pirate":"PIRATE","totem":"TOTEM","mech":"MECHANICAL"}
KEYWORDS = {"taunt":"TAUNT","charge":"CHARGE","divineshield":"DIVINE_SHIELD",
            "windfury":"WINDFURY","stealth":"STEALTH","poisonous":"POISONOUS",
            "frozen":"FROZEN","cantattack":"CANT_ATTACK","immune":"IMMUNE",
            "forgetful":"FORGETFUL",
            # untargetability. Short aliases because the real constant names are
            # unwieldy in a spreadsheet cell.
            "nospell":"CANT_BE_TARGETED_BY_SPELLS",
            "nopower":"CANT_BE_TARGETED_BY_HERO_POWERS",
            "cantbetargetedbyspells":"CANT_BE_TARGETED_BY_SPELLS",
            "cantbetargetedbyheropowers":"CANT_BE_TARGETED_BY_HERO_POWERS"}

#[[ parse_selector needs the card table only for `id=` validation. Threading it
#   through every call site would touch ~40 lines for one filter, so it is held
#   in a one-slot box that main() fills before any row is parsed. ]]
by_id_ref = [{}]


def parse_selector(s, row):
    s = (s or "").strip()
    if not s:
        return "{}"
    f = {}

    # trailing modifiers
    while True:
        m = re.search(r"(!self|!target|!defender|!attacker|~\d+|#\d+|\+\w+|-\w+|<\d+|>\d+|\bdmg\b|\bnodmg\b)$", s)
        if not m:
            break
        tok = m.group(1); s = s[:m.start()].strip()
        if tok == "!self":            f["exclude"] = '"SELF"'
        elif tok == "!defender":      f["excludeDefender"] = "true"
        elif tok == "!attacker":      f["excludeAttacker"] = "true"
        elif tok == "!target":        f["excludeTarget"] = "true"
        elif tok.startswith("~"):    f["random"] = tok[1:]
        elif tok.startswith("#"):    f["first"]  = tok[1:]
        elif tok.startswith("<"):    f["maxAtk"] = tok[1:]
        elif tok.startswith(">"):    f["minAtk"] = tok[1:]
        elif tok == "dmg":           f["damaged"] = "true"
        elif tok == "nodmg":         f["damaged"] = "false"
        elif tok.startswith("+"):
            kw = KEYWORDS.get(tok[1:].lower())
            if not kw: err(row, f"unknown keyword in selector: {tok}")
            else: f["keyword"] = f'"{kw}"'
        elif tok.startswith("-"):
            name = tok[1:].lower()
            # `-mech` is a negative RACE, `-taunt` a negative keyword. Races and
            # keywords share this one prefix because no name collides.
            if name in RACES:
                f["notRace"] = '"%s"' % RACES[name]
                f.setdefault("type", '"MINION"')
            elif name in KEYWORDS:
                f["notKeyword"] = '"%s"' % KEYWORDS[name]
            else:
                err(row, f"unknown keyword or race in selector: {tok}")

    low = s.lower()
    if low == "self":     return "{self=true}"
    if low == "target":
        f["target"] = "true"; return "{" + ",".join(f"{k}={v}" for k,v in f.items()) + "}"
    if low == "payload":  return "{payloadEntity=true}"
    if low in ("lastsummoned", "summoned"): return "{lastSummoned=true}"
    if low in ("lastdrawn", "drawn"):       return "{lastDrawn=true}"
    if low == "attacker": return "{payloadAttacker=true}"
    if low == "defender": return "{payloadDefender=true}"
    if low == "adjacent":
        f["adjacent"] = '"SELF"'; f["type"] = '"MINION"'
    elif low in ("adjacent@target", "adjacent.target"):
        f["adjacent"] = '"TARGET"'; f["type"] = '"MINION"'
    elif low in ("adjacent@defender", "adjacent.defender"):
        # attack payloads carry `defender`, never `target`
        f["adjacent"] = '"DEFENDER"'; f["type"] = '"MINION"'
    else:
        #[[ scope.filter[.filter...] -- filters COMPOSE, so friendly.hand.minion
        #   means side=FRIENDLY, zone=HAND, type=MINION. The old grammar allowed
        #   exactly one filter, which made every "minions in your hand" card
        #   inexpressible (Mana Wraith, Mechwarper, Sorcerer's Apprentice...).
        parts = low.split(".")
        if len(parts) < 2:
            err(row, f"bad selector {s!r} (expected scope.filter[.filter])")
            return "{}"
        scope, filters = parts[0], parts[1:]
        if scope == "friendly": f["side"] = '"FRIENDLY"'
        elif scope == "enemy":  f["side"] = '"ENEMY"'
        elif scope == "any":    f["side"] = '"ANY"'
        else: err(row, f"unknown selector scope {scope!r} in {s!r}")

        TYPES = {"minion":"MINION","spell":"SPELL","weapon":"WEAPON","hero":"HERO"}
        ZONES = {"hand":"HAND","deck":"DECK","secret":"SECRET","graveyard":"GRAVEYARD",
                 "play":"PLAY"}
        for filt in filters:
            if filt in TYPES:
                f["type"] = '"%s"' % TYPES[filt]
                if filt == "hero": f["hero"] = "true"
            elif filt == "char":
                f["hero"] = "true"
            elif filt in ZONES:
                f["zone"] = '"%s"' % ZONES[filt]
            elif filt in RACES:
                f["race"] = '"%s"' % RACES[filt]
                f.setdefault("type", '"MINION"')
            #[[ Deathrattle and Battlecry are not keywords -- they are script
            #   tags -- so they are filters in the chain rather than +/- flags.
            #   Scarlet Purifier wants `any.minion.deathrattle`. ]]
            elif filt == "deathrattle":
                f["hasDeathrattle"] = "true"
                f.setdefault("type", '"MINION"')
            elif filt == "battlecry":
                f["hasBattlecry"] = "true"
                f.setdefault("type", '"MINION"')
            #[[ `secret` is the secret ZONE; `issecret` is the card PROPERTY.
            #   Mad Scientist needs "a Secret in my DECK", which the zone filter
            #   cannot say -- it would move the card's location, not describe it. ]]
            elif filt == "issecret":
                f["isSecret"] = "true"
                f.setdefault("type", '"SPELL"')
            elif filt.startswith("notid="):
                m = re.search(r"notid=([A-Za-z0-9_]+)", s, re.I)
                cid = m.group(1) if m else filt[6:]
                if cid not in by_id_ref[0]:
                    err(row, f"unknown card id in selector: {cid!r}")
                f["notCardId"] = '"%s"' % cid
            elif filt.startswith("id="):
                cid = filt[3:]
                # the raw id is case-folded by `low`, so recover it from `s`
                m = re.search(r"id=([A-Za-z0-9_]+)", s)
                cid = m.group(1) if m else cid
                if cid not in by_id_ref[0]:
                    err(row, f"unknown card id in selector: {cid!r}")
                f["cardId"] = '"%s"' % cid
            else:
                err(row, f"unknown selector filter {filt!r} in {s!r}")

    return "{" + ",".join(f"{k}={v}" for k, v in f.items()) + "}"

# ---------------------------------------------------------------- conditions

def parse_cond(s, row):
    s = (s or "").strip()
    if not s: return None
    low = s.lower()
    #[[ PRECEDENCE: `and`/`or` bind LOOSER than `not`, as everywhere else.
    #
    #   This used to test the `not ` prefix FIRST, which made `not A and B`
    #   parse as `not (A and B)` -- quietly the opposite of what it reads like.
    #   It was found by a card whose secret then fired on the wrong events, and
    #   one authored card had already been written to depend on the old reading
    #   while another was contorted to work around it.
    #
    #   So the split happens first and `not` binds only to the term beside it.
    #   There are no parentheses in this grammar: write `not A and not B`. ]]
    for joiner, name in ((" and ", "All"), (" or ", "Any")):
        if joiner in low:
            idx = low.index(joiner)
            a = parse_cond(s[:idx], row); b = parse_cond(s[idx+len(joiner):], row)
            return '{c="%s",of={%s,%s}}' % (name, a, b)
    if low.startswith("not "):
        inner = parse_cond(s[4:], row)
        return "{c=\"Not\",of=%s}" % inner
    m = re.match(r"Count\(\s*(.+?)\s*,\s*(\d+)\s*\)$", s, re.I)
    if m:
        return '{c="CountAtLeast",sel=%s,min=%s}' % (parse_selector(m.group(1), row), m.group(2))
    m = re.match(r"TargetHasKeyword\(\s*(\w+)\s*\)$", s, re.I)
    if m:
        k = KEYWORDS.get(m.group(1).lower())
        if not k: err(row, "unknown keyword %r" % m.group(1)); return None
        return '{c="TargetHasKeyword",keyword="%s"}' % k
    m = re.match(r"HeroPowerIs\(\s*([A-Za-z0-9_]+)\s*\)$", s, re.I)
    if m:
        cid = m.group(1)
        if cid not in by_id_ref[0]:
            err(row, f"unknown card id in HeroPowerIs: {cid!r}")
        return '{c="HeroPowerIs",cardId="%s"}' % cid
    m = re.match(r"DiedThisGame\(\s*([A-Za-z0-9_]+)\s*\)$", s, re.I)
    if m:
        cid = m.group(1)
        if cid not in by_id_ref[0]:
            err(row, f"unknown card id in DiedThisGame: {cid!r}")
        return '{c="DiedThisGame",cardId="%s"}' % cid
    m = re.match(r"PayloadCardIs\(\s*([A-Za-z0-9_]+)\s*\)$", s, re.I)
    if m:
        cid = m.group(1)
        if cid not in by_id_ref[0]:
            err(row, f"unknown card id in PayloadCardIs: {cid!r}")
        return '{c="PayloadCardIs",cardId="%s"}' % cid
    m = re.match(r"Chance\(\s*(\d+)\s*\)$", s, re.I)
    if m:
        return '{c="Chance",pct=%s}' % m.group(1)
    m = re.match(r"PayloadCostAtMost\(\s*(\d+)\s*\)$", s, re.I)
    if m:
        return '{c="PayloadCostAtMost",max=%s}' % m.group(1)
    m = re.match(r"MyHeroHealthAtMost\(\s*(\d+)\s*\)$", s, re.I)
    if m:
        return '{c="MyHeroHealthAtMost",n=%s}' % m.group(1)
    m = re.match(r"PayloadAttackAtLeast\(\s*(\d+)\s*\)$", s, re.I)
    if m:
        return '{c="PayloadAttackAtLeast",min=%s}' % m.group(1)
    m = re.match(r"TargetHasRace\(\s*(\w+)\s*\)$", s, re.I)
    if m:
        r_ = RACES.get(m.group(1).lower())
        if not r_: err(row, f"unknown race {m.group(1)!r}"); return None
        return '{c="TargetHasRace",race="%s"}' % r_
    m = re.match(r"PayloadHasRace\(\s*(\w+)\s*\)$", s, re.I)
    if m:
        r_ = RACES.get(m.group(1).lower())
        if not r_: err(row, f"unknown race {m.group(1)!r}"); return None
        return '{c="PayloadHasRace",race="%s"}' % r_
    m = re.match(r"PayloadAttackAtMost\(\s*(\d+)\s*\)$", s, re.I)
    if m:
        return '{c="PayloadAttackAtMost",max=%s}' % m.group(1)
    SIMPLE = {"combo":"Combo","hasweapon":"HasWeapon","handnotempty":"HandNotEmpty",
              "selfdamaged":"SelfDamaged",
              "targetisdamaged":"TargetIsDamaged",
              "targetalive":"TargetAlive",
              "targetisfrozen":"TargetIsFrozen","hasoverload":"HasOverload",
              "targetisfriendly":"TargetIsFriendly",
              "boardfull":"BoardFull","manafull":"ManaFull",
              "payloadisminion":"PayloadIsMinion",
              "payloadisspell":"PayloadIsSpell","payloadisself":"PayloadIsSelf",
              "payloadsummonedbyme":"PayloadSummonedByMe",
              "payloadismine":"PayloadIsMine",
              "payloadfataltomyhero":"PayloadFatalToMyHero",
              "payloadsourceisself":"PayloadSourceIsSelf",
              "selfdamaged":"SelfDamaged",
              "targetisdamaged":"TargetIsDamaged",
              "targetalive":"TargetAlive",
              "targetisfrozen":"TargetIsFrozen",
              "payloadtargetishero":"PayloadTargetIsHero",
              "payloadattackerisminion":"PayloadAttackerIsMinion",
              "payloadattackerisenemy":"PayloadAttackerIsEnemy",
              # outcome of the damage the PREVIOUS op dealt
              "damagekilled":"DamageKilled",
              "damagesurvived":"DamageSurvived",
              "myturn":"MyTurn",
              "payloadhasdeathrattle":"PayloadHasDeathrattle",
              "payloadissecret":"PayloadIsSecret",
              "payloadhasoverload":"PayloadHasOverload",
              "payloadattackerisself":"PayloadAttackerIsSelf",
              "payloadtargetismyhero":"PayloadTargetIsMyHero",
              "lastdrawnisminion":"LastDrawnIsMinion",
              "lastdrawnisbeast":"LastDrawnIsBeast",
              "nominionplayedthisturn":"NoMinionPlayedThisTurn",
              "payloadspellhasminiontarget":"PayloadSpellHasMinionTarget"}
    if low in SIMPLE:
        return '{c="%s"}' % SIMPLE[low]
    err(row, f"unknown condition {s!r}")
    return None

# ----------------------------------------------------------------------- ops

def parse_amount(a, row):
    """A literal, or a dynamic spec the engine already understands:
         count(sel)     -> number of matches
         attackOf(sel)  -> that entity's attack
         armorOf(sel)   -> that entity's armor
       This is what makes "+1 for each X" and "damage equal to your Armor"
       expressible (King of Beasts, Shield Slam, Savagery, Divine Favor...)."""
    a = (a or "").strip()
    #[[ A rolled RANGE: Crackle "$3-$6", Lightning Storm "$2-$3", Imp-losion
    #   "$2-$4". Matched before the plain-integer test so `3-6` is not read as
    #   an expression, and before the dynamic forms so `2-4` cannot be a
    #   selector. The roll uses the shared seeded stream. ]]
    m = re.match(r"^(\d+)\s*-\s*(\d+)$", a)
    if m:
        lo, hi = int(m.group(1)), int(m.group(2))
        if hi <= lo:
            err(row, "range amount %r must have max > min" % a)
            return "0"
        return "{min=%d,max=%d}" % (lo, hi)
    # Edwin VanCleef: cards played BEFORE this one, this turn
    if a.lower() in ("cardsplayedearlierthisturn", "comboearlier"):
        return "{cardsPlayedEarlierThisTurn=true}"
    # the amount the previous op actually used -- Imp-losion's Imp per damage
    if a.lower() in ("dealt", "lastamount"):
        return "{lastAmount=true}"
    #[[ The amount carried by the EVENT being handled. Documented under AMOUNTS
    #   and implemented in Ops.lua, but this function never emitted it -- the
    #   same "the docstring promises what the grammar cannot say" gap that
    #   `dealt` had, found the same way: by a card that needed it. ]]
    if a.lower() == "payloadamount":
        return "{payloadAmount=true}"
    #[[ sub(a, b) -- a minus b, clamped at zero. "Draw until you have as many
    #   cards as your opponent" and "draw until they have 3" are both a
    #   difference, and the DSL had no arithmetic at all. ]]
    m = re.match(r"sub\(\s*(.+)\s*\)$", a, re.I)
    if m:
        parts = split_args(m.group(1))
        if len(parts) != 2:
            err(row, "sub() takes exactly two amounts, got %d" % len(parts))
            return "0"
        return "{sub={%s,%s}}" % (parse_amount(parts[0], row),
                                  parse_amount(parts[1], row))
    m = re.match(r"(count|attackOf|armorOf|healthOf|damageOf|costOf)\(\s*(.+?)\s*\)$", a, re.I)
    if m:
        kind = {"count":"count","attackof":"attackOf","armorof":"armorOf",
                "healthof":"healthOf","damageof":"damageOf","costof":"costOf"}[m.group(1).lower()]
        return "{%s=%s}" % (kind, parse_selector(m.group(2), row))
    if re.match(r"^-?\d+$", a):
        return a
    #[[ STRICT. This used to `return a` for anything unrecognised, which passed raw
    #   text into the generated Lua. A typo like `attackof(x)` (wrong case caught,
    #   but `atackOf(x)` not) emitted `atk=atackOf(x)`: valid Lua SYNTAX, an
    #   undefined global at runtime, so Generated.lua errored on load and took the
    #   whole addon with it -- and a syntax check could never catch it. ]]
    err(row, "amount %r is not a number, a N-M range, `dealt`, or one of "
             "count()/attackOf()/armorOf()/healthOf()/damageOf()" % a)
    return "0"

def split_args(s):
    """Split on commas not nested inside (), {}."""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "({": depth += 1
        elif ch in ")}": depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip(): out.append(cur.strip())
    return out

def split_ops(s):
    """Split an op list on semicolons not nested inside brackets."""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "({": depth += 1
        elif ch in ")}": depth -= 1
        if ch == ";" and depth == 0:
            if cur.strip(): out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip(): out.append(cur.strip())
    return out

#[[ POOL FILTER GRAMMAR, for the cards that generate a card nobody drafted.
#
#   A `+`-joined list of terms, each one of:
#       minion spell weapon            card type
#       beast demon dragon murloc
#         pirate totem mech            race (implies minion)
#       legendary epic rare common     rarity
#       cost=N                         exact printed cost
#       cost=target                    the chosen target's cost (Recombobulator)
#   e.g.  minion+cost=2     beast     minion+legendary     weapon
#
#   It is NOT the selector grammar: a selector picks entities already in the
#   game, this picks a printed card from the whole collectible pool. Keeping
#   them separate stops "random Beast" being confused with "a Beast on the
#   board", which are different cards entirely. ]]
RARITIES = {"legendary": "LEGENDARY", "epic": "EPIC", "rare": "RARE",
            "common": "COMMON", "free": "FREE"}


def parse_pool(spec, row):
    spec = (spec or "").strip().lower()
    f, dynamic = {}, None
    if not spec:
        return "{}", None
    for term in [t.strip() for t in spec.split("+") if t.strip()]:
        if term in ("minion", "spell", "weapon"):
            f["type"] = '"%s"' % term.upper()
        elif term in RACES:
            f["race"] = '"%s"' % RACES[term]
            f.setdefault("type", '"MINION"')
        elif term in RARITIES:
            f["rarity"] = '"%s"' % RARITIES[term]
        elif term == "cost=target":
            dynamic = '"TARGET"'
        elif re.match(r"^cost=\d+$", term):
            f["cost"] = term.split("=")[1]
        else:
            err(row, f"unknown pool filter term {term!r} in {spec!r}")
    return "{" + ",".join(f"{k}={v}" for k, v in sorted(f.items())) + "}", dynamic


def parse_ops(s, row, by_id):
    ops = [parse_op(o, row, by_id) for o in split_ops(s or "")]
    return "{" + ",".join(o for o in ops if o) + "}"

#[[ EVERY CARD A SCRIPT CONJURES, collected as the rows are parsed.
#
#   The coverage report counts the COLLECTIBLE POOL, because that is what a
#   player drafts. A token is not collectible, so it was never counted -- and a
#   token with real rules text and no script does nothing, silently, exactly as
#   eight of the nine hero powers once did (see the hero-power note below).
#
#   These are audited separately at the end of the run. ]]
CONJURED = set()

def check_token(cid, row, by_id):
    cid = cid.strip().strip('"').strip("'")
    if cid not in by_id:
        err(row, f"unknown card id in Summon/Transform/AddCard: {cid!r}")
    CONJURED.add(cid)
    return cid

#[[ Count/side arguments for Summon() and AddCard().
#
#   STRICT ON PURPOSE. This used to test only `^\d+$` for a count and `enemy`
#   for a side, and DISCARD anything else with no error -- so the natural
#   Imp-losion spelling `Summon(GVG_045t, dealt)` compiled to a single Imp and
#   nothing said a word. That is precisely the silent-wrong-Lua failure the
#   strict parse_amount was written to end, so it ends here too: an argument
#   that is neither a side nor a valid amount is an ERROR. ]]
def _countAndSide(args, row, what):
    cnt, side = "", ""
    for extra in args:
        x = (extra or "").strip()
        if not x:
            continue
        if x.lower() in ("enemy", "opponent", "foe"):
            side = ',side="ENEMY"'
        elif re.match(r"^\d+$", x):
            cnt = ",count=%s" % x
        else:
            amt = parse_amount(x, row)     # errors itself if unrecognised
            if amt != "0" or x == "0":
                cnt = ",amount=%s" % amt
            else:
                err(row, f"{what}(): {x!r} is neither a count, an amount, nor `enemy`")
    return cnt, side


def parse_op(s, row, by_id):
    s = s.strip()
    # control flow with brace blocks
    m = re.match(r"If\((.+?)\)\s*\{(.*?)\}\s*(?:\{(.*?)\})?$", s, re.S)
    if m:
        cond = parse_cond(m.group(1), row)
        t = parse_ops(m.group(2), row, by_id)
        e = parse_ops(m.group(3), row, by_id) if m.group(3) is not None else None
        out = '{op="Conditional",cond=%s,thenOps=%s' % (cond, t)
        if e: out += ",elseOps=%s" % e
        return out + "}"
    m = re.match(r"AtEndOfTurn\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="ScheduleEndOfTurn",ops=%s}' % parse_ops(m.group(1), row, by_id)
    m = re.match(r"AtNextTurn\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="ScheduleNextTurn",ops=%s}' % parse_ops(m.group(1), row, by_id)
    #[[ OneOf{a}{b}{c} -- run exactly ONE branch, chosen at random from the
    #   shared stream. Tinkmaster Overspark and Enhance-o Mechano. ]]
    m = re.match(r"OneOf\s*((?:\{.*?\}\s*){2,})$", s, re.S)
    if m:
        branches = re.findall(r"\{(.*?)\}", m.group(1), re.S)
        return '{op="OneOf",branches={%s}}' % ",".join(
            parse_ops(b, row, by_id) for b in branches)
    #[[ Repeat takes any AMOUNT, not just a literal. H.Repeat has always called
    #   the dynamic amount resolver; it was this regex that limited it to digits,
    #   which made `dealt` -- documented right there in parse_amount -- impossible
    #   to consume. Imp-losion is the card that needs it. ]]
    #[[ RepeatUntil(cond){ops} -- Bouncing Blade. Bounded internally, because a
    #   board where nothing can die would otherwise hang the client. ]]
    m = re.match(r"RepeatUntil\((.+?)\)\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="RepeatUntil",cond=%s,ops=%s}' % (
            parse_cond(m.group(1), row), parse_ops(m.group(2), row, by_id))
    m = re.match(r"Repeat\((.+?)\)\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="Repeat",amount=%s,ops=%s}' % (parse_amount(m.group(1), row),
                                                   parse_ops(m.group(2), row, by_id))
    m = re.match(r"ForEach\((.+?)\)\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="ForEach",sel=%s,ops=%s}' % (parse_selector(m.group(1), row),
                                                 parse_ops(m.group(2), row, by_id))
    m = re.match(r"AddTrigger\((.+?),\s*(\w+)\)\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="AddTrigger",sel=%s,on=ns.EVENT.%s,ops=%s}' % (
            parse_selector(m.group(1), row), m.group(2), parse_ops(m.group(3), row, by_id))
    #[[ CasterTrigger(sel, EVENT){ops}: a trigger granted to a minion whose ops
    #   run for the player who GRANTED it, whichever side the minion is on
    #   (Blessing of Wisdom on an enemy minion: its attacks draw for YOU). ]]
    m = re.match(r"CasterTrigger\((.+?),\s*(\w+)\)\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="AddTrigger",sel=%s,on=ns.EVENT.%s,forCaster=true,ops=%s}' % (
            parse_selector(m.group(1), row), m.group(2), parse_ops(m.group(3), row, by_id))
    m = re.match(r"Deathrattle\((.+?)\)\s*\{(.*)\}$", s, re.S)
    if m:
        return '{op="SetDeathrattle",sel=%s,ops=%s}' % (
            parse_selector(m.group(1), row), parse_ops(m.group(2), row, by_id))

    m = re.match(r"(\w+)\((.*)\)$", s, re.S)
    if not m:
        err(row, f"cannot parse op {s!r}")
        return None
    name, argstr = m.group(1), m.group(2)
    a = split_args(argstr)

    def S_(i):  return parse_selector(a[i], row)
    def N_(i):  return a[i].strip()
    def A_(i):  return parse_amount(a[i], row)
    def SIDE_(i):
        """Optional trailing 'enemy' argument -> side="ENEMY". The ops have always
           supported op.side; only the DSL could not emit it, which blocked every
           'for your opponent' card (Leeroy, King Mukla, Arcane Golem...)."""
        if len(a) > i and a[i].strip().lower() in ("enemy", "opponent", "foe"):
            return ',side="ENEMY"'
        return ""

    try:
        if name == "Damage":       return '{op="Damage",sel=%s,amount=%s}' % (S_(0), A_(1))
        #[[ DamageFrom(from, sel, amount): damage dealt BY a minion rather than
        #   by the spell -- no Spell Damage, and the dealer's Poisonous applies
        #   (Betrayal: the betrayed minion hits its neighbours). ]]
        if name == "DamageFrom":
            return '{op="Damage",from=%s,sel=%s,amount=%s}' % (S_(0), S_(1), A_(2))
        if name == "MissileSplit": return '{op="DamageRandomSplit",sel=%s,amount=%s,per=1}' % (S_(0), A_(1))
        if name == "Heal":         return '{op="Heal",sel=%s,amount=%s}' % (S_(0), A_(1))
        if name == "SetHealth":    return '{op="SetHealth",sel=%s,value=%s}' % (S_(0), N_(1))
        if name == "SetAttack":    return '{op="SetAttack",sel=%s,value=%s}' % (S_(0), A_(1))
        # ---- player-scoped timed modifiers -------------------------------
        if name in ("CostDelta", "CostSet"):
            scope, amt, charges, dur = a[0], N_(1), a[2].strip(), a[3].strip().lower()
            side, kind = (scope.split(".") + ["any"])[:2]
            side = "ENEMY" if side.strip().lower() == "enemy" else "SELF"
            kind = {"spell":"SPELL","secret":"SECRET","minion":"MINION","any":None}[kind.strip().lower()]
            d = {"turn":"ns.DURATION.END_OF_TURN",
                 "nextturn":"ns.DURATION.START_OF_YOUR_NEXT_TURN"}[dur]
            parts = ['op="AddCostMod"', 'side="%s"' % side, "duration=%s" % d]
            if kind: parts.append('appliesTo="%s"' % kind)
            parts.append(("setTo=%s" if name == "CostSet" else "amount=%s") % amt)
            if charges != "-": parts.append("charges=%s" % charges)
            return "{%s}" % ",".join(parts)
        if name == "ClampHealth":
            side = "ENEMY" if a[0].strip().lower() == "enemy" else "SELF"
            d = {"turn":"ns.DURATION.END_OF_TURN",
                 "nextturn":"ns.DURATION.START_OF_YOUR_NEXT_TURN"}[a[2].strip().lower()]
            return '{op="AddDamageClamp",side="%s",minHealth=%s,duration=%s}' % (side, N_(1), d)
        if name == "ResummonDied":
            return '{op="ResummonDiedThisTurn"}'
        if name == "Swap":         return '{op="SwapAttackHealth",sel=%s}' % S_(0)
        if name == "InnerFire":    return '{op="SetAttackToHealth",sel=%s}' % S_(0)
        if name == "GainArmor":    return '{op="GainArmor",sel=%s,amount=%s}' % (S_(0), A_(1))
        if name in ("Buff", "BuffTurn", "BuffNextTurn"):
            kw = ',keywords={"%s"}' % KEYWORDS[a[3].strip().lower()] if len(a) > 3 else ""
            dur = {"BuffTurn": ",duration=ns.DURATION.END_OF_TURN",
                   "BuffNextTurn": ",duration=ns.DURATION.START_OF_YOUR_NEXT_TURN"
                  }.get(name, "")
            return '{op="Buff",sel=%s,atk=%s,hp=%s%s%s}' % (S_(0), A_(1), A_(2), kw, dur)
        if name in ("GiveKeyword", "KeywordTurn", "KeywordNextTurn"):
            dur = {"KeywordTurn": ",duration=ns.DURATION.END_OF_TURN",
                   "KeywordNextTurn": ",duration=ns.DURATION.START_OF_YOUR_NEXT_TURN"
                  }.get(name, "")
            return '{op="GiveKeyword",sel=%s,keywords={"%s"}%s}' % (
                S_(0), KEYWORDS[a[1].strip().lower()], dur)
        if name == "Silence":      return '{op="Silence",sel=%s}' % S_(0)
        if name == "RemoveKeyword":
            return '{op="RemoveKeyword",sel=%s,keywords={"%s"}}' % (
                S_(0), KEYWORDS[a[1].strip().lower()])
        if name == "CopyEnemyHandCard": return '{op="CopyOpponentHandCard"}' 
        if name == "Freeze":       return '{op="Freeze",sel=%s}' % S_(0)
        if name == "Destroy":      return '{op="Destroy",sel=%s}' % S_(0)
        if name == "ReturnToHand":
            # an optional second argument raises the returned card's cost
            # (Freezing Trap: "It costs (2) more")
            if len(a) > 1 and a[1].strip():
                return '{op="ReturnToHand",sel=%s,cost=%d}' % (S_(0), int(a[1].strip()))
            return '{op="ReturnToHand",sel=%s}' % S_(0)
        if name == "TakeControl":
            # a trailing `enemy` hands the minion TO the opponent, which is how
            # Shadow Madness gives it back at end of turn
            toEnemy = ",toEnemy=true" if SIDE_(1) else ""
            #[[ `ready`: it may attack this turn although it just changed sides
            #   -- not Charge (a keyword, which a Silence would take away) but
            #   simply not summoning-sick (Shadow Madness). ]]
            ready = ",ready=true" if any(x.strip().lower() == "ready" for x in a[1:]) else ""
            return '{op="TakeControl",sel=%s%s%s}' % (S_(0), toEnemy, ready)
        if name == "ShuffleIn":    return '{op="ShuffleIntoDeck",sel=%s}' % S_(0)
        if name == "Transform":
            return '{op="Transform",sel=%s,cardId="%s"}' % (S_(0), check_token(a[1], row, by_id))
        if name == "CopyToBoard":  return '{op="CopyToBoard",sel=%s}' % S_(0)
        if name == "CopyPrinted":  return '{op="CopyToBoard",sel=%s,fromPrinted=true}' % S_(0)
        if name == "Summon":
            #[[ Placement flags. `flank`: right of the source, then left, then
            #   right... (Onyxia, Cenarius's Treants, Dr. Boom's Bots -- all
            #   documented on hearthstone.wiki.gg). `rightmost`: the far right
            #   even from a deathrattle, which otherwise takes the dead
            #   minion's slot (Soul of the Forest's Treants). ]]
            rest, place = [], ""
            for extra in a[1:]:
                x = (extra or "").strip().lower()
                if x == "flank":       place = ",alternate=true"
                elif x == "rightmost": place = ',position="RIGHTMOST"'
                else:                  rest.append(extra)
            cnt, side = _countAndSide(rest, row, "Summon")
            return '{op="Summon",cardId="%s"%s%s%s}' % (
                check_token(a[0], row, by_id), cnt, side, place)
        if name == "SummonEntourage":
            uniq, side = "", ""
            for extra in a:
                x = (extra or "").strip().lower()
                if x == "unique":                        uniq = ",uniqueEntourage=true"
                elif x in ("enemy", "opponent", "foe"):  side = ',side="ENEMY"'
                elif x: err(row, f"unknown flag {x!r} in SummonEntourage()")
            return '{op="Summon",fromEntourage=true%s%s}' % (uniq, side)
        # Spare Parts: pick one of the card's printed entourage ids into hand.
        if name == "AddCardEntourage":
            return '{op="AddCardToHand",fromEntourage=true%s}' % SIDE_(0)
        if name == "Draw":
            lit = a[0].strip()
            if re.match(r"^-?\d+$", lit):
                return '{op="Draw",count=%s}' % lit
            return '{op="Draw",amount=%s}' % parse_amount(lit, row)
        if name == "DrawEnemy":    return '{op="Draw",count=%s,side="ENEMY"}' % N_(0)
        if name == "Discard":      return '{op="Discard",count=%s}' % N_(0)
        if name == "AddCard":
            cnt, side = _countAndSide(a[1:], row, "AddCard")
            return '{op="AddCardToHand",cardId="%s"%s%s}' % (
                check_token(a[0], row, by_id), cnt, side)
        if name == "Overload":
            err(row, "Overload() is applied automatically from printed data -- "
                     "scripting it double-counts. Remove this op.")
            return None
        if name == "Mana":
            flags = ""
            for extra in a[1:]:
                x = extra.strip().lower()
                if x in ("temp", "temporary", "thisturn"): flags += ",temporary=true"
                elif x == "empty":                          flags += ",empty=true"
                elif x in ("enemy", "opponent", "foe"):     flags += ',side="ENEMY"'
                elif x:                                     err(row, f"unknown Mana flag {x!r}")
            if re.match(r"^-", N_(0)):
                err(row, "Mana() cannot take a negative count -- GainManaCrystal "
                         "loops upward and would silently do nothing. Losing a "
                         "crystal needs a dedicated op (Felguard).")
            return '{op="GainManaCrystal",count=%s%s}' % (N_(0), flags)
        #[[ ZONE MOVEMENT. These move a card BETWEEN zones without playing it:
        #   no mana is paid and no battlecry fires. See Ops.lua. ]]
        if name in ("MoveToHand", "MoveToBoard", "MoveToSecret", "CopyToHand"):
            cnt, side = "", ""
            for extra in a[1:]:
                x = extra.strip().lower()
                if re.match(r"^\d+$", x):                cnt = ",count=%s" % x
                elif x in ("enemy", "opponent", "foe"):  side = ',side="ENEMY"'
                elif x:                                  err(row, f"unknown flag {x!r} in {name}()")
            return '{op="%s",sel=%s%s%s}' % (name, S_(0), cnt, side)
        if name == "MillDeck":
            side = ""
            for extra in a[1:]:
                x = extra.strip().lower()
                if x in ("enemy", "opponent", "foe"): side = ',side="ENEMY"'
                elif x:                               err(row, f"unknown flag {x!r} in MillDeck()")
            return '{op="MillDeck",count=%s%s}' % (N_(0), side)
        if name == "ShuffleCardIn":
            cnt, side = "", ""
            for extra in a[1:]:
                x = extra.strip().lower()
                if re.match(r"^\d+$", x):                cnt = ",count=%s" % x
                elif x in ("enemy", "opponent", "foe"):  side = ',side="ENEMY"'
                elif x:                                  err(row, f"unknown flag {x!r} in ShuffleCardIn()")
            return '{op="ShuffleCardIn",cardId="%s"%s%s}' % (
                check_token(a[0], row, by_id), cnt, side)
        if name == "LoseManaCrystal":
            n = a[0].strip() if a and a[0].strip() else "1"
            side = ',side="ENEMY"' if len(a) > 1 and a[1].strip().lower() in (
                "enemy", "opponent", "foe") else ""
            return '{op="LoseManaCrystal",count=%s%s}' % (n, side)
        if name == "SetHeroPower":
            return '{op="SetHeroPower",cardId="%s"%s}' % (
                check_token(a[0], row, by_id), SIDE_(1))
        if name == "ReplaceHero":
            return '{op="ReplaceHero",cardId="%s",heroPowerId="%s"}' % (
                check_token(a[0], row, by_id), check_token(a[1], row, by_id))
        if name == "Resurrect":
            hp = ""
            if len(a) > 1 and a[1].strip():
                hp = ",health=%s" % N_(1)
            # `owner`: back on the side that controlled it (Reincarnate)
            own = ",toController=true" if len(a) > 2 and a[2].strip().lower() == "owner" else ""
            return '{op="Resurrect",sel=%s%s%s}' % (S_(0), hp, own)
        if name == "SettleDeaths":
            return '{op="SettleDeaths"}'
        if name == "CostChange":
            return '{op="ChangeCost",sel=%s,amount=%d}' % (S_(0), int(a[1].strip()))
        if name in ("RetargetAttack", "RetargetSpell", "TriggerDeathrattles",
                    "BecomeCopy", "StealSecret", "DestroyAllButOneRandom",
                    "DestroyInHand"):
            return '{op="%s",sel=%s}' % (name, S_(0))
        if name == "GiveSpellDamage":
            return '{op="GiveSpellDamage",sel=%s,amount=%s}' % (S_(0), N_(1))
        if name == "LookAtTop":
            return '{op="LookAtTop",count=%s}' % (N_(0) if a and a[0].strip() else "3")
        if name == "SwapWithHand":
            return '{op="SwapWithHand",sel=%s}' % S_(0)
        if name in ("AddRandomCard", "SummonRandom", "EquipRandom"):
            #[[ The pool spec is OPTIONAL and the flags are order-free, so an
            #   argument is classified by shape rather than by position --
            #   `EquipRandom(enemy)` has a flag where `AddRandomCard(beast)` has
            #   a pool. Anything that is not a recognised flag is the pool. ]]
            cnt, side, delta, poolspec = "", "", "", ""
            for extra in a:
                x = extra.strip().lower()
                if not x:                                continue
                elif re.match(r"^\d+$", x):              cnt = ",count=%s" % x
                elif x in ("enemy", "opponent", "foe"):  side = ',side="ENEMY"'
                elif re.match(r"^\d+less$", x):
                    delta = ",costDelta=-%s" % x.replace("less", "")
                elif poolspec:
                    err(row, f"{name}() takes at most one pool filter, got "
                             f"{poolspec!r} and {x!r}")
                else:                                    poolspec = x
            pool, dyn = parse_pool(poolspec, row)
            return '{op="%s",pool=%s%s%s%s%s}' % (
                name, pool, (",poolCost=%s" % dyn) if dyn else "", cnt, side, delta)
        if name == "TransformRandom":
            pool, dyn = parse_pool(a[1], row)
            return '{op="TransformRandom",sel=%s,pool=%s%s}' % (
                S_(0), pool, (",poolCost=%s" % dyn) if dyn else "")
        if name in ("DoubleAttack", "DoubleHealth", "SwapHealth"):
            return '{op="%s",sel=%s}' % (name, S_(0))
        if name == "Equip":
            return '{op="EquipWeapon",cardId="%s"}' % check_token(a[0], row, by_id)
        if name == "DestroyWeapon":return '{op="DestroyWeapon"%s}' % SIDE_(0)
    except (IndexError, KeyError) as ex:
        err(row, f"bad arguments to {name}(): {ex}")
        return None

    err(row, f"unknown op {name!r}")
    return None

# --------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--coverage", action="store_true", help="report only, do not write")
    args = ap.parse_args()

    by_id, pool = load_cards()
    by_id_ref[0] = by_id
    cards_raw = json.load(open(PRINTED, encoding="utf-8"))
    CHOOSE_ONE = chooseone.find(cards_raw)          # parent id -> [mode, mode]
    if len(CHOOSE_ONE) != chooseone.EXPECTED_IN_7234:
        err(0, "found %d Choose One cards, pin %d expects %d"
               % (len(CHOOSE_ONE), BUILD, chooseone.EXPECTED_IN_7234))
    MODE_PARENT = {m: par for par, ms in CHOOSE_ONE.items() for m in ms}

    sources = []
    if os.path.exists(CSV_IN):
        sources.append(CSV_IN)
    if os.path.isdir(CSV_DIR):
        sources += sorted(os.path.join(CSV_DIR, f)
                          for f in os.listdir(CSV_DIR) if f.lower().endswith(".csv"))
    if not sources:
        print("no authoring CSVs yet -- emitting coverage only")
    rows = []
    row_origin = {}          # rows index -> "file:line", so errors name the file
    for src in sources:
        with open(src, newline="", encoding="utf-8-sig") as fh:
            for ln, r in enumerate(csv.DictReader(fh), start=2):
                rows.append(r)
                row_origin[len(rows) + 1] = "%s:%d" % (os.path.basename(src), ln)
                ROW_ORIGIN[len(rows) + 1] = row_origin[len(rows) + 1]

    scripts = collections.defaultdict(dict)
    for i, r in enumerate(rows, start=2):
        cid  = (r.get("card_id") or "").strip()
        hook = (r.get("hook") or "").strip().lower()
        if not cid or cid.startswith("#"):
            continue
        if cid not in by_id:
            err(i, f"unknown card_id {cid!r}"); continue
        if hook not in HOOKS:
            err(i, f"unknown hook {hook!r}"); continue

        #[[ Choose One rows are authored on the MODE, and the mode's hook has to
        #   match the PARENT's card type -- see the CHOOSE ONE section above. ]]
        if cid in CHOOSE_ONE:
            err(i, f"{cid} is a Choose One card: author its modes "
                   f"({', '.join(CHOOSE_ONE[cid])}), not the parent"); continue
        if cid in MODE_PARENT:
            ptype = by_id[MODE_PARENT[cid]]["type"]
            want  = "battlecry" if ptype == "MINION" else "spell"
            if hook != want and hook != "combo":
                err(i, f"{cid} is a Choose One mode of a {ptype} "
                       f"({MODE_PARENT[cid]}), so its hook must be {want!r}, "
                       f"not {hook!r}"); continue

        cond = parse_cond(r.get("cond"), i)
        #[[ Game:AttachScript copies `s.deathrattle.ops` onto the entity and
        #   never looks at `.cond`, so a condition authored on a deathrattle row
        #   compiled fine and then fired UNCONDITIONALLY with nothing reporting
        #   it. Rejecting it is the honest fix: the author wants an inline
        #   If(...) op, which does work. ]]
        if hook == "deathrattle" and cond:
            err(i, "a `cond` on a deathrattle row is never evaluated -- the "
                   "deathrattle is stored as bare ops. Put the condition inside "
                   "the ops instead: If(<cond>){...}")
            continue
        ev   = (r.get("trigger") or "").strip().upper()
        # aura/enrage use their own Aura(...) grammar, not the op list -- do not
        # run them through parse_ops or they report a bogus "unknown op Aura".
        # aura/enrage/property use their own grammar, not the op list -- running
        # them through parse_ops reports a bogus "unknown op".
        opsl = (None if hook in ("aura", "enrage", "property")
                else parse_ops(r.get("ops"), i, by_id))

        #[[ A top-level SCRIPT PROPERTY rather than a behaviour: a flag the
        #   ENGINE reads, not an op list it runs. Prophet Velen's damage
        #   doubling is the original example, and it is the reason Velen sits in
        #   Handwritten.lua -- the DSL could not emit a top-level field at all. ]]
        if hook == "property":
            prop = (r.get("ops") or "").strip()
            m = re.match(r"(\w+)\(\s*(-?\d*)\s*\)$", prop)
            if not m:
                err(i, "property hook needs Name() or Name(n), got %r" % prop)
                continue
            pname, pval = m.group(1), m.group(2)
            PROPS = {
                "SpellMultiplier":       "number",   # Prophet Velen
                "DeathrattleMultiplier": "number",   # Baron Rivendare
                "HealsDealDamage":       "flag",     # Auchenai Soulpriest
                "WeaponAttackCost":      "flag",     # Gorehowl
                "ImmuneWhileAttacking":  "flag",     # Gladiator's Longbow
                "HeroPowerTargetsMinions": "flag",   # Steamwheedle Sniper
                "TurnSeconds":           "number",   # Nozdormu
                #[[ MEGA-WINDFURY, which is printed in the card TEXT and
                #   nowhere else: the vendored data gives V-07-TR-0N only
                #   CHARGE, so no importer could ever derive it. The engine
                #   computed `Windfury and 2 or 1`, so the four-attack
                #   finisher swung twice. ]]
                "AttacksPerTurn":        "number",   # V-07-TR-0N
                "HeroImmune":            "flag",     # Mal'Ganis
            }
            kind = PROPS.get(pname)
            if not kind:
                err(i, "unknown script property %r (known: %s)"
                       % (pname, ", ".join(sorted(PROPS))))
                continue
            if kind == "number":
                if not pval:
                    err(i, "%s() needs a number" % pname); continue
                key = pname[0].lower() + pname[1:]
                scripts[cid][key] = pval
            else:
                if pval:
                    err(i, "%s() takes no argument" % pname); continue
                key = pname[0].lower() + pname[1:]
                scripts[cid][key] = "true"
            continue

        if hook == "aura":
            #[[ A magnitude may be a NUMBER or a dynamic amount, optionally
            #   negated: Mountain Giant is `AuraCost(self, -count(friendly.hand!self))`
            #   and Old Murk-Eye is `Aura(self, count(any.murloc!self), 0)`.
            #   `count()` can never be negative, so the minus sign is carried as
            #   a `negate` flag rather than folded into the value. ]]
            AMT = r"(-?(?:\d+|\w+\([^()]*(?:\([^()]*\))?[^()]*\)))"
            m = re.match(r"Aura(?:Cost)?\((.+?),\s*" + AMT +
                         r"(?:,\s*" + AMT + r")?(?:,\s*([\w+]+))?\)$",
                         (r.get("ops") or "").strip())
            if not m:
                err(i, "aura hook needs Aura(sel, atk, hp) or AuraCost(sel, delta)")
                continue
            isCost = (r.get("ops") or "").strip().startswith("AuraCost")
            sel_ = parse_selector(m.group(1), i)

            def auramag(tok):
                """A literal stays a literal; anything else becomes a dynamic
                amount table with an explicit negate flag."""
                if tok is None:
                    return "0"
                tok = tok.strip()
                if re.match(r"^-?\d+$", tok):
                    return tok
                neg = tok.startswith("-")
                inner = parse_amount(tok.lstrip("-"), i)
                if not inner.startswith("{"):
                    err(i, "aura magnitude %r must be a number or a dynamic amount" % tok)
                    return "0"
                return inner[:-1] + (",negate=true}" if neg else "}")
            # Conditional auras: Aura.Recalc evaluates spec.cond on every rebuild,
            # so the aura simply stops contributing when the condition goes false.
            cnd = (",cond=%s" % cond) if cond else ""
            if isCost:
                #[[ AuraCost(sel, delta, floor): "costs (2) less, but not less
                #   than (1)" (Summoning Portal). The floor never RAISES a card
                #   that already costs less -- a Wisp stays 0. ]]
                flo = (",costFloor=%s" % m.group(3).strip()) if m.group(3) else ""
                if flo and not re.match(r"^\d+$", m.group(3).strip()):
                    err(i, "AuraCost floor must be a number"); continue
                scripts[cid]["aura"] = '{sel=%s,cost=%s%s%s}' % (sel_, auramag(m.group(2)), flo, cnd)
            else:
                kw = ""
                if m.group(4):
                    names = []
                    for part in m.group(4).split("+"):
                        k = KEYWORDS.get(part.strip().lower())
                        if not k: err(i, "unknown keyword %r in aura" % part)
                        else: names.append('"%s"' % k)
                    if names: kw = ",keywords={%s}" % ",".join(names)
                scripts[cid]["aura"] = '{sel=%s,atk=%s,hp=%s%s%s}' % (
                    sel_, auramag(m.group(2)), auramag(m.group(3)), kw, cnd)
        elif hook == "enrage":
            m = re.match(r"Aura\(\s*self\s*,\s*(-?\d+)(?:,\s*(-?\d+))?(?:,\s*(\w+))?\)$",
                         (r.get("ops") or "").strip())
            if not m:
                err(i, "enrage hook needs Aura(self, atk[, hp][, KEYWORD])"); continue
            ekw = ""
            if m.group(3):
                k = KEYWORDS.get(m.group(3).lower())
                if not k: err(i, "unknown keyword %r in enrage" % m.group(3))
                else: ekw = ',keywords={"%s"}' % k
            scripts[cid]["enrage"] = '{atk=%s,hp=%s%s}' % (
                m.group(1), m.group(2) or 0, ekw)
        elif hook == "trigger":
            if not ev: err(i, "trigger hook needs a trigger event"); continue
            #[[ `hand` makes the trigger fire while the card is IN HAND. Opt-in,
            #   because two ten-card hands walked on every raise is real work
            #   for the one card in the pool that needs it (Bolvar Fordragon). ]]
            tflags = ""
            for fl in re.split(r"[;, ]+", (r.get("flags") or "").strip().lower()):
                if fl in ("hand", "inhand"): tflags += "inHand=true,"
                elif fl: err(i, "unknown flag %r on a trigger row "
                                "(only `hand` is accepted here)" % fl)
            entry = '{on=ns.EVENT.%s,%s%sops=%s}' % (
                ev, tflags, ("cond=%s," % cond) if cond else "", opsl)
            scripts[cid].setdefault("_triggers", []).append(entry)
        elif hook == "secret":
            if not ev: err(i, "secret hook needs a trigger event"); continue
            # flags column: `cancels` (Counterspell, Freezing Trap) marks the
            # triggering action as cancelled; `exclusive` stops other secrets
            # firing on the same event.
            flags = ""
            for fl in re.split(r"[;, ]+", (r.get("flags") or "").strip().lower()):
                if fl == "cancels":   flags += "cancels=true,"
                elif fl == "exclusive": flags += "exclusive=true,"
                elif fl == "anyturn":   flags += "anyTurn=true,"
                elif fl:              err(i, f"unknown flag {fl!r}")
            scripts[cid]["secret"] = '{on=ns.EVENT.%s,%s%sops=%s}' % (
                ev, flags, ("cond=%s," % cond) if cond else "", opsl)
        else:
            #[[ Only `secret` and `trigger` rows read the flags column. A flag
            #   anywhere else used to be accepted and DISCARDED -- which is how
            #   Bolvar's `hand` flag came to compile cleanly and do nothing. ]]
            if (r.get("flags") or "").strip():
                err(i, "the flags column means nothing on a %r row" % hook)
                continue
            key = {"heropower": "heroPower", "ondraw": "onDraw"}.get(hook, hook)
            scripts[cid][key] = '{%sops=%s}' % (("cond=%s," % cond) if cond else "", opsl)

    # Two files claiming the same card+hook is a merge mistake, not an override.
    seen_hooks = {}
    for i, r in enumerate(rows, start=2):
        cid = (r.get("card_id") or "").strip()
        hk  = (r.get("hook") or "").strip().lower()
        if not cid or not hk: continue
        key = (cid, hk)
        if key in seen_hooks:
            errors.append("duplicate %s/%s authored twice (%s and %s)"
                          % (cid, hk, seen_hooks[key], row_origin.get(i, "?")))
        else:
            seen_hooks[key] = row_origin.get(i, "?")

    # ---- coverage
    need    = {cid for cid, c in pool.items() if needs_script(c)}
    have    = set(scripts.keys())
    hand    = load_handwritten()
    for cid in sorted(hand):
        if cid in scripts:
            warn("%s is authored in BOTH a CSV and Handwritten.lua; the "
                 "hand-written one wins at load time, so the CSV row is dead. "
                 "Delete one." % cid)
    have |= hand

    #[[ A Choose One parent is covered exactly when BOTH its modes are. Half a
    #   card is worse than none of it: the prompt would offer a mode that does
    #   nothing, so an odd one out is an error rather than a coverage gap. ]]
    for par, ms in CHOOSE_ONE.items():
        done = [m for m in ms if m in have]
        if len(done) == 1:
            errors.append("%s %r has only one of its two Choose One modes "
                          "authored (%s); author both or neither"
                          % (par, by_id[par]["name"], done[0]))
        elif len(done) == 2:
            have.add(par)
    missing = sorted(need - have)
    extra   = sorted(have - need - {cid for cid in have if by_id[cid].get("type") == "HERO_POWER"})
    for cid in extra:
        if cid in pool:
            warn(f"{cid} {by_id[cid]['name']!r} has a script but printed data says none needed")

    #[[ HERO POWERS, reported separately.
    #
    #   They are not collectible, so they were never in `pool` and the coverage
    #   report could not see them at all -- EIGHT OF THE NINE were unauthored
    #   and silently did nothing in every game, because UseHeroPower runs
    #   `if script and script.heroPower` and a missing script is not an error.
    #
    #   One power per class is in every single match, so this line matters more
    #   than its size suggests. ]]
    #[[ TOKENS, audited for exactly the hero-power reason above.
    #
    #   A token is not collectible, so it was never in `pool` and the coverage
    #   report was blind to it -- and THE COIN, which is in every match whose
    #   flip you lose, had NO SCRIPT AT ALL. Its printed text says "Gain 1 Mana
    #   Crystal this turn only"; playing it spent the card and did nothing,
    #   because a missing script is not an error anywhere in the engine --
    #   `if script and script.spell` simply skips.
    #
    #   The audited set is every card a script CONJURES (collected by
    #   check_token while the rows are parsed) plus the cards the ENGINE deals.
    #   `needs_script` is the same predicate the pool uses, so a Taunt token
    #   whose keyword is printed data is correctly not asked for one. ]]
    tok_need = sorted(cid for cid in (CONJURED | ENGINE_DEALT)
                      if cid in by_id and cid not in pool
                      and needs_script(by_id[cid]))
    tok_missing = [cid for cid in tok_need if cid not in have]

    hp_ids = sorted(set(HERO_POWER_BY_CLASS.values()))
    hp_have = [h for h in hp_ids if h in have]
    hp_missing = [h for h in hp_ids if h not in have]

    if sources:
        print("sources: " + ", ".join(os.path.basename(x) for x in sources))
    print("=" * 66)
    print("EFFECT SCRIPT COVERAGE  (pinned build %d)" % BUILD)
    print("=" * 66)
    print(f"  pool cards            : {len(pool)}")
    print(f"  need a script         : {len(need)}")
    print(f"  pure data, no script  : {len(pool) - len(need)}")
    print(f"  scripts authored      : {len(have & need)}"
          f"   ({len(hand & need)} hand-written in Handwritten.lua)")
    print(f"  still missing         : {len(missing)}")
    print(f"  hero powers           : {len(hp_have)}/{len(hp_ids)} authored"
          + (("   MISSING: " + ", ".join(hp_missing)) if hp_missing else ""))
    print(f"  tokens the game makes : "
          f"{len(tok_need) - len(tok_missing)}/{len(tok_need)} authored"
          + (("   MISSING: " + ", ".join(tok_missing)) if tok_missing else ""))
    if need:
        pct = 100.0 * len(have & need) / len(need)
        bar = "#" * int(pct / 2) + "." * (50 - int(pct / 2))
        print(f"  [{bar}] {pct:.1f}%")

    for cid in tok_missing:
        errors.append("%s %r is put into play by the game and its printed text "
                      "needs a script, but none is authored -- it would do "
                      "nothing at all, silently" % (cid, by_id[cid]["name"]))

    if errors:
        print(f"\n--- {len(errors)} ERROR(S) -- nothing written ---")
        for e in errors[:40]: print("  " + e)
        sys.exit(1)
    if warnings:
        print(f"\n--- {len(warnings)} warning(s) ---")
        for w in warnings[:20]: print("  " + w)

    if missing and args.coverage:
        print(f"\n--- next 30 unimplemented cards ---")
        for cid in missing[:30]:
            c = by_id[cid]
            print(f"  {cid:<12}{c['name']:<26}{(c.get('text') or '')[:52]}")

    if args.coverage:
        return

    # ---- emit
    lines = ["-- GENERATED by tools/compile_effects.py -- DO NOT EDIT BY HAND.",
             "-- Source: tools/effects.csv   Printed data: build %d" % BUILD, "",
             "local ADDON, ns = ...", "local S = ns.Scripts or {}",
             "ns.Scripts = S", ""]
    for cid in sorted(scripts):
        parts = []
        for k, v in sorted(scripts[cid].items()):
            if k == "_triggers":
                parts.append("triggers={%s}" % ",".join(v))
            else:
                parts.append("%s=%s" % (k, v))
        lines.append('S[%r] = {%s}' % (cid, ",".join(parts)))
    lines.append("")
    lines.append("return S")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print(f"\nwrote {os.path.relpath(OUT, ROOT)} ({len(scripts)} cards)")

if __name__ == "__main__":
    main()
