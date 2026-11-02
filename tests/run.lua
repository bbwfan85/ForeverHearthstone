--[[ tests/run.lua -- headless test entry point.

  Run from the PROJECT ROOT (paths in harness.lua are root-relative):

      lua tests/run.lua                 -- everything
      lua tests/run.lua aura            -- only suites whose name contains "aura"
      lua tests/run.lua juggler         -- the Knife Juggler acceptance tests

  Exit code is 0 on pass, 1 on any failure, so this drops straight into a
  pre-commit hook or CI step.

  Requires Lua 5.1 or LuaJIT. WoW ships Lua 5.1, so testing on 5.1 is testing on
  what actually runs the addon -- do not use a 5.2+ interpreter, or you will
  write `goto` and bit operators that the game client cannot parse.
]]

-- Make `require("tests.x")` work regardless of how the interpreter was invoked.
package.path = "./?.lua;./?/init.lua;" .. package.path

local H = require("tests.harness")

print("")
print("  Forever Hearthstone -- headless engine tests")
print(("  Lua: %s"):format(_VERSION))

local ok, err = pcall(H.LoadEngine)
if not ok then
  print("")
  print("  ENGINE FAILED TO LOAD:")
  print("  " .. tostring(err))
  print("")
  os.exit(2)
end

print(("  pinned patch: %s"):format(tostring(H.ns.PATCH_LABEL)))
local nCards = 0
for _ in pairs(H.ns.PrintedCards or {}) do nCards = nCards + 1 end
local nScripts = 0
for _ in pairs(H.ns.Scripts or {}) do nScripts = nScripts + 1 end
print(("  printed cards: %d    effect scripts: %d"):format(nCards, nScripts))

-- Suites register themselves on require, so the order here is the report order.
local SUITES = {
  "tests.test_pin",
  "tests.test_entity",
  "tests.test_aura",
  "tests.test_death",
  "tests.test_triggers",
  "tests.test_secrets",
  "tests.test_rules",
  "tests.test_opening",
  "tests.test_gvg",
  "tests.test_chooseone",
  "tests.test_primitives",
  "tests.test_zones",
  "tests.test_controller",
  "tests.test_net",
  "tests.test_transport",
  "tests.test_collection",
  "tests.test_rewards",
  "tests.test_collectionui",
  "tests.test_style",
  "tests.test_ai",
  "tests.test_packaging",
  "tests.test_cards_neutral",
  "tests.test_cards_classes_a",
  "tests.test_cards_classes_b",
  "tests.test_cards_finishers",
  "tests.test_partials",
  "tests.test_heropowers",
  "tests.test_tokens",
  "tests.test_table",
  "tests.test_weapons",
  "tests.test_dsl",
  "tests.test_dsl2",
  "tests.test_duration",
  "tests.test_playertimed",
  "tests.test_determinism",
  "tests.test_fx",
  "tests.test_director",
  "tests.test_assets",
  "tests.test_layout",
  "tests.test_ui",
  "tests.test_presentation",
  "tests.test_textfit",
  "tests.test_economy",
  "tests.test_vault",
  "tests.test_review",
  "tests.test_release013",
  "tests.test_rulings",
  "tests.test_readiness",
  "tests.test_tour",
}

for _, mod in ipairs(SUITES) do
  local okm, errm = pcall(require, mod)
  if not okm then
    print("")
    print(("  FAILED TO LOAD %s:"):format(mod))
    print("  " .. tostring(errm))
    print("")
    os.exit(2)
  end
end

os.exit(H.run(arg and arg[1] or nil))
