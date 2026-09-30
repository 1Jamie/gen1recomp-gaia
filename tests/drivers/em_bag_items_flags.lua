local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_bag_items_flags"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_bag_items_flags failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local FieldMoves = require("src.core.game3.field_moves")
  local Field = require("src.core.game3.field")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local PartyMenu = require("src.ui.game3.party_menu")
  local RomText = require("src.core.game3.rom_text")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return end
  session.bag = session.bag or Bag.new()
  session.party = {}
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 10)

  for _, name in ipairs({ "ITEM_POKE_FLUTE", "ITEM_TM_CASE", "ITEM_BERRY_POUCH" }) do
    local ok, kind, text = ItemUse.useField(session, session.bag, C:require("items", name))
    check(ok == false and text and text:find("advice", 1, true) ~= nil,
      name .. " is not usable, Dad's advice: " .. tostring(text))
  end

  local up = C:require("flags", "FLAG_SYS_ENC_UP_ITEM")
  local down = C:require("flags", "FLAG_SYS_ENC_DOWN_ITEM")
  check(FieldMoves.SYS_FLAGS.WHITE_FLUTE_ACTIVE == up and up == 2221, "white flute flag is FLAG_SYS_ENC_UP_ITEM")
  check(FieldMoves.SYS_FLAGS.BLACK_FLUTE_ACTIVE == down and down == 2222, "black flute flag is FLAG_SYS_ENC_DOWN_ITEM")
  local ok, kind, text = ItemUse.useBlackWhiteFlute(session, C:require("items", "ITEM_WHITE_FLUTE"))
  check(ok and kind == "black_white_flute", "white flute used")
  check(Flags.getFlag(Space.store, nil, up) == true and Flags.getFlag(Space.store, nil, down) ~= true, "ENC_UP set, ENC_DOWN clear")
  check(Flags.getFlag(Space.store, nil, 0x803) ~= true, "trainer flag 0x803 untouched by the flute")
  local t = 0x803
  Flags.setFlag(Space.store, nil, t, true)
  Field.clearTempFieldEventData(Field._game, session.map)
  check(Flags.getFlag(Space.store, nil, up) ~= true, "ENC_UP cleared on map change")
  check(Flags.getFlag(Space.store, nil, t) == true, "trainer flag survives map change")
  local list = FieldMoves.tempSysFlags()
  local names = {}
  for _, id in ipairs(list) do names[#names + 1] = Flags.nameFor(id) end
  print("[driver] temp flags: " .. table.concat(names, ","))
  check(#list == 5, "five Emerald temp flags")

  local Itemfinder = require("src.core.game3.itemfinder")
  check(Itemfinder.textKey("nothing", session) == "gText_ItemFinderNothing", "itemfinder key")

  PartyMenu._chooseOrder = { 1, 2 }
  PartyMenu._chooseMax = 2
  local shown
  local orig = PartyMenu.showMessage
  PartyMenu.showMessage = function(text) shown = text end
  PartyMenu.enterChosenMon(3)
  PartyMenu.showMessage = orig
  check(shown and shown:find("No more than 2", 1, true) ~= nil, "multi party entry text: " .. tostring(shown))

  check(select(1, pcall(RomText.box, "gText_NicknameHatchPrompt", { stringVars = { "TORCHIC" } })), "hatch prompt key exists")
  local EggHatch = require("src.ui.game3.egg_hatch")
  check(EggHatch ~= nil, "egg hatch module loads")

  local LB = require("src.core.game3.link.battle")
  local FieldRse = require("src.core.game3.scripting.natives_field_rse")
  local Rse = require("src.core.game3.rse.init")
  Rse.setVar("VAR_LILYCOVE_FAN_CLUB_STATE", 2)
  local before = FieldRse.numFans()
  check(pcall(FieldRse.updateTrainerFansAfterLinkBattle, true), "fan club update after a link win runs")
  check(FieldRse.numFans() >= before, "a link win does not lose fans")
  check(Flags.ensurePalletOakHidden(Space.store) == nil and Flags.getFlag(Space.store, nil, 0x2C) ~= true,
    "Pallet Oak hide flag not set on Emerald")
  local Compat = require("src.mods.Gen3Compat")
  Flags.setFlag(Space.store, nil, up, true)
  check(Compat.getFlag("FLAG_SYS_ENC_UP_ITEM") == true, "Gen3Compat resolves Emerald flag names")
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  try("body", function() body(game) end)
  return finish()
end
