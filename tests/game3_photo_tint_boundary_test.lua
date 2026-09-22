-- BUG2 regression: Game Corner photo tint (VAR_0x8004 -> special 0x167 ->
-- store 0x4042) must survive the message/waitmessage/delay yield boundary, and
-- the tint MULTICHOICE (listId 2 = MULTICHOICE_TRAINER_CARD_ICON_TINT) must
-- offer all four cart options even when the extract cache is missing.
--
-- Root cause locked by this test (NOT a Ctx.wipeSpecial mid-run wipe):
--   * the extracted photo chain is ONE vm run (goto = same-run jump,
--     ops_a.lua jump()); wipeSpecial only runs at Vm:start — before the
--     multichoice setvar — and at haltCleanup — after the special.
--   * when scripts/multichoice.lua is absent from the resolved cache root
--     (stale pre-extractor extracts predate commit aed3bbce, Sep 19),
--     Multichoice.resolve fell back to countHint — and adapters.multichoice
--     passed row[4] as that hint.  For a plain `multichoice` row, row[4] is
--     ignoreBPress (=1), so resolve synthesized a ONE-option menu
--     ("OPTION 0") -> VAR_RESULT always 0 -> setvar VAR_0x8004, 0
--     (MON_ICON_TINT_NORMAL) -> special 0x167 writes tint 0 = untinted.
--
-- Rows below are transcribed from the extracted bundle
-- (data/generated/gba/scripts/scripts.lua: g3:081b2867 tail, g3:081b28db-e6-
-- f1-fc, g3:081b2907) which mirrors pokefirered data/scripts/trainer_card.inc
-- + data/maps/CeruleanCity_GameCorner/scripts.inc (money preamble trimmed).

package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function checkEq(got, expected, msg)
  if got == expected then
    passed = passed + 1
    print(string.format("[ok] %s (got %s)", msg, tostring(got)))
  else
    failed = failed + 1
    print(string.format("[FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(got)))
  end
end

local Multichoice = require("src.core.game3.scripting.multichoice")

print("=== 1. cart list counts survive a missing extract cache ===")
Multichoice.LISTS = {} -- headless: no scripts/multichoice.lua on any root
checkEq(#Multichoice.resolve(2), 4,
  "MULTICHOICE_TRAINER_CARD_ICON_TINT (list 2) has 4 tints without the cache")
checkEq(#Multichoice.resolve(2, 1), 4,
  "an ignoreBPress row[4]=1 never shrinks list 2 (the BUG2 mechanism)")
checkEq(#Multichoice.resolve(0), 2, "list 0 (YES/NO) counts 2 from the cart table")
checkEq(#Multichoice.resolve(4242, 3), 3,
  "an unknown list id keeps the caller's count hint (legacy synthetic)")
check(string.format("%s", Multichoice.resolve(2)[3]):find("OPTION") ~= nil,
  "cache-miss labels stay synthetic in order (position 3 = PINK slot)")

print("=== 2. adapters.multichoice never reads row[4] as an option count ===")
do
  local captured
  package.loaded["src.core.game3.scripting.multichoice"] = {
    resolve = function(listId, countHint)
      captured = countHint
      return { "A", "B", "C" }, { left = 20, top = 5 }
    end,
  }
  local Adapters = require("src.core.game3.scripting.adapters")
  local adapters = Adapters.host(nil, nil, nil)
  -- pret: multichoice 21, 0, MULTICHOICE_TRAINER_CARD_ICON_TINT, TRUE
  --       -> [1]=x [2]=y [3]=listId [4]=ignoreBPress (=1 here)
  adapters.multichoice({ op = "multichoice", [1] = 21, [2] = 0, [3] = 2, [4] = 1 },
    function() end)
  checkEq(captured, 3,
    "plain multichoice passes the default hint, not ignoreBPress (was 1)")
  package.loaded["src.core.game3.scripting.multichoice"] = nil
end

print("=== 3. boundary: picked tint survives message/waitmessage/delay -> special 0x167 ===")
do
  local Std = require("src.core.game3.scripting.stdscripts")
  local Flags = require("src.core.game3.scripting.flags")
  local Vm = require("src.core.game3.scripting.vm")
  local Adapters = require("src.core.game3.scripting.adapters")
  local Schema = require("src.core.game3.save_schema_firered")

  local session = Schema.newGame({ name = "RED" })
  session.party = { { speciesId = 4, species = 4 } } -- one Charmander
  local store = Flags.newStore()
  package.loaded["src.core.game3.scripting.space"] = { store = store }
  package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

  local scripts = {
    -- g3:081b2867 tail: choice -> copyvar VAR_0x8000, VAR_RESULT -> case chain
    picker = {
      { op = "multichoice", [1] = 21, [2] = 0, [3] = 2, [4] = 1 },
      { op = "copyvar", [1] = 0x8000, [2] = 0x800D },
      { op = "compare_var_to_value", [1] = 0x8000, [2] = 0, var = 0x8000, value = 0 },
      { op = "goto_if", cond = 1, [1] = 1, [2] = 0, target = "tint0" },
      { op = "compare_var_to_value", [1] = 0x8000, [2] = 1, var = 0x8000, value = 1 },
      { op = "goto_if", cond = 1, [1] = 1, [2] = 0, target = "tint1" },
      { op = "compare_var_to_value", [1] = 0x8000, [2] = 2, var = 0x8000, value = 2 },
      { op = "goto_if", cond = 1, [1] = 1, [2] = 0, target = "tint2" },
      { op = "compare_var_to_value", [1] = 0x8000, [2] = 3, var = 0x8000, value = 3 },
      { op = "goto_if", cond = 1, [1] = 1, [2] = 0, target = "tint3" },
      { op = "end" },
    },
    -- g3:081b28db / :28e6 / :28f1 / :28fc — setvar VAR_0x8004, tint; goto photo
    tint0 = {
      { op = "setvar", [1] = 0x8004, [2] = 0, var = 0x8004, value = 0 },
      { op = "goto", target = "photo" },
      { op = "end" },
    },
    tint1 = {
      { op = "setvar", [1] = 0x8004, [2] = 1, var = 0x8004, value = 1 },
      { op = "goto", target = "photo" },
      { op = "end" },
    },
    tint2 = {
      { op = "setvar", [1] = 0x8004, [2] = 2, var = 0x8004, value = 2 },
      { op = "goto", target = "photo" },
      { op = "end" },
    },
    tint3 = {
      { op = "setvar", [1] = 0x8004, [2] = 3, var = 0x8004, value = 3 },
      { op = "goto", target = "photo" },
      { op = "end" },
    },
    -- g3:081b2907 EventScript_PrintPhoto: message/waitmessage -> delay 60
    -- -> special UpdateTrainerCardPhotoIcons (0x167) -> releaseall -> end
    photo = {
      { op = "lockall" },
      { op = "message", ptr = "txt_smile" },
      { op = "waitmessage" },
      { op = "playse", [1] = 320 },
      { op = "dofieldeffect", [1] = 69 },
      { op = "delay", [1] = 60 },
      { op = "special", id = Std.SPECIAL.UpdateTrainerCardPhotoIcons,
        [1] = Std.SPECIAL.UpdateTrainerCardPhotoIcons },
      { op = "releaseall" },
      { op = "end" },
    },
  }

  local adapters = Adapters.stub({ lookupText = function() return nil end })
  -- User picks PINK (index 2 of NORMAL/BLACK/PINK/SEPIA).
  adapters.multichoice = function(row, cb) cb(2) end
  adapters.playSe = function() end

  local vm = Vm.new({ store = store, scripts = scripts, text = {}, adapters = adapters })
  local ok = vm:start("picker")
  check(ok, "the photo script starts")
  for _ = 1, 300 do
    if not vm:isRunning() then break end
    vm:tick() end
  check(not vm:isRunning(), "the photo script runs to completion (releaseall + end)")

  -- The special's store write IS the boundary proof: a wipe between the
  -- setvar and the special would leave VAR_0x8004 = 0 -> store tint 0.
  checkEq(Flags.getVar(store, nil, 0x4042), 2,
    "store 0x4042 tint = PINK (2) after the yield boundary")
  checkEq(Flags.getVar(store, nil, 0x4043), 4,
    "store 0x4043 icon 1 = species 4 (the special ran with the party snapshot)")
end

print(string.format("Total: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
