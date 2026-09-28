local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_menus"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_menus failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

local function topId()
  local t = require("src.ui.game3.stack").top()
  return t and t.id
end

local function tapWait(game, btn, n)
  U.tap(game, btn)
  U.wait(n or 20)
end

local function shot(game, name)
  U.wait(4)
  U.still(game, DIR .. "/" .. name .. ".png")
end

local function waitFor(pred, limit)
  for _ = 1, limit or 600 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

local function setupMon(C, Party, session, spec)
  local Pokemon = require("src.core.game3.pokemon")
  local ok, _, mon = Party.giveMon(session, C:require("species", "SPECIES_" .. spec.species), spec.level)
  if not (ok and mon) then return nil end
  mon.nickname = ""
  mon.otName, mon.ot, mon.otId, mon.otGender = "NICK", "NICK", 17925, 0
  mon.otSecretId = 0
  local RomText = require("src.core.game3.rom_text")
  local want = 0
  for i = 0, 24 do if RomText.at("gNatureNamePointers", i) == spec.nature then want = i end end
  for lo = 128, 0xFFFF do
    local hi = bit.bxor(17925, lo)
    local p = hi * 65536 + lo
    if p % 25 == want and lo % 256 >= 128 then mon.personality = p break end
  end
  mon.nature = mon.personality % 25
  mon.gender = Pokemon.gender(mon.species, mon.personality)
  mon.metLevel = spec.metLevel
  mon.metLocation = spec.metLocation
  mon.exp = spec.exp
  mon.moves, mon.pp, mon.maxPp = {}, {}, {}
  for i, name in ipairs(spec.moves) do
    local id = C:require("moves", "MOVE_" .. name)
    local def = Pokemon.battleMove(id)
    mon.moves[i] = id
    mon.pp[i] = def and def.pp or 0
    mon.maxPp[i] = def and def.pp or 0
  end
  mon.stats = spec.stats
  mon.hp, mon.maxHp = spec.stats.hp, spec.stats.hp
  return mon
end

return function(game)
  if not check(waitFor(function() return game.phase == "boot" and game.boot end, 900), "boot reached") then
    return finish()
  end
  try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  end)
  U.wait(30)

  local Runtime = require("src.core.game3.runtime")
  local C = require("src.core.game3.constants").of("emerald")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Options = require("src.core.game3.options")
  local session = Runtime.getSession()
  if not check(session ~= nil and session.version == "emerald", "emerald field session") then return finish() end

  local IDS = Flags.forVersion("emerald").IDS
  local store = Space.store or session
  for _, f in ipairs({ "FLAG_SYS_POKEMON_GET", "FLAG_SYS_POKEDEX_GET", "FLAG_SYS_POKENAV_GET" }) do
    Flags.setFlag(store, nil, IDS[f], true)
  end
  for i = 1, 8 do Flags.setFlag(store, nil, IDS[string.format("FLAG_BADGE0%d_GET", i)], true) end
  Options.set(session, "frameType", 4)
  require("src.ui.game3.chrome").setFrameType(4)
  local function item(n, q) Bag.add(session.bag, C:require("items", "ITEM_" .. n), q or 1) end
  for _, row in ipairs({ { "STAR_PIECE", 1 }, { "STARDUST", 1 }, { "RARE_CANDY", 30 }, { "MAX_REPEL", 98 },
      { "FULL_RESTORE", 98 }, { "HEART_SCALE", 99 }, { "RED_SHARD", 99 }, { "FIRE_STONE", 99 },
      { "POKE_BALL", 47 }, { "ULTRA_BALL", 99 }, { "TIMER_BALL", 29 }, { "GREAT_BALL", 98 }, { "MASTER_BALL", 99 },
      { "TM01", 99 }, { "TM02", 99 }, { "TM03", 99 }, { "TM04", 99 }, { "TM05", 99 }, { "TM06", 99 }, { "TM07", 99 },
      { "TM08", 99 }, { "HM01", 1 },
      { "CHERI_BERRY", 4 }, { "PECHA_BERRY", 1 }, { "RAWST_BERRY", 1 }, { "LEPPA_BERRY", 2 }, { "ORAN_BERRY", 10 },
      { "PERSIM_BERRY", 6 }, { "SITRUS_BERRY", 1 }, { "FIGY_BERRY", 1 },
      { "OLD_ROD", 1 }, { "ITEMFINDER", 1 }, { "MACH_BIKE", 1 }, { "GO_GOGGLES", 1 }, { "DEVON_SCOPE", 1 },
      { "MAGMA_EMBLEM", 1 }, { "SS_TICKET", 1 }, { "BASEMENT_KEY", 1 } }) do
    item(row[1], row[2])
  end
  session.registeredItem = C:require("items", "ITEM_MACH_BIKE")
  session.party = {}
  local sec = nil
  local pack = require("src.ui.game3.rse.scene_kit").loadLua("data/generated/gba/region_map/map_sections.lua")
  for id, row in pairs(pack and pack.sections or {}) do if row.name == "METEOR FALLS" then sec = id end end
  setupMon(C, Party, session, { species = "SALAMENCE", level = 50, nature = "QUIET", metLevel = 35, metLocation = sec,
    exp = 158899, moves = { "HEADBUTT", "EMBER", "DRAGON_BREATH", "FLY" },
    stats = { hp = 166, atk = 155, def = 89, spa = 138, spd = 98, spe = 97 } })
  setupMon(C, Party, session, { species = "MAGCARGO", level = 38, nature = "QUIET", metLevel = 20, metLocation = sec,
    exp = 50000, moves = { "EMBER" }, stats = { hp = 95, atk = 60, def = 90, spa = 70, spd = 60, spe = 30 } })
  setupMon(C, Party, session, { species = "SMEARGLE", level = 100, nature = "QUIET", metLevel = 40, metLocation = sec,
    exp = 1000000, moves = { "SKETCH" }, stats = { hp = 287, atk = 100, def = 100, spa = 100, spd = 100, spe = 200 } })
  check(#session.party == 3, "three party members")

  try("Map.load", function()
    Map.load(nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  end)
  local s = Runtime.getSession()
  s.x, s.y = 14, 12
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  U.wait(60)

  tapWait(game, "start", 30)
  check(topId() == "start", "START opens the start menu (" .. tostring(topId()) .. ")")
  local StartMenu = require("src.ui.game3.start_menu")
  local ids = {}
  for _, e in ipairs(StartMenu.ENTRIES or {}) do ids[#ids + 1] = e.id end
  local list = table.concat(ids, ",")
  -- pokeemerald/src/start_menu.c:315
  check(list == "pokedex,pokemon,bag,pokenav,trainer,save,option,exit"
    or list == "pokedex,pokemon,bag,pokenav,trainer,save,option,mods,exit", "normal start menu rows (" .. list .. ")")
  check(StartMenu.ENTRIES[5] and StartMenu.ENTRIES[5].label == "NICK", "PLAYER row prints the player name")
  shot(game, "01_start_menu")

  local function openEntry(id)
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == id then
        while StartMenu.cursor ~= i do tapWait(game, "down", 6) end
        tapWait(game, "a", 60)
        return true
      end
    end
    return false
  end

  local ItemsData = require("src.core.game3.items_data")
  check(openEntry("bag"), "BAG row")
  check(topId() == "bag", "BAG opens the bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local names = { "02_bag_items", "02_bag_pocket2", "02_bag_pocket3", "02_bag_pocket4", "02_bag_pocket5" }
  for i = 1, 5 do
    if i > 1 then tapWait(game, "right", 40) end
    check(BagMenu.pocketIdx == i, "pocket " .. i .. " (" .. tostring(ItemsData.BAG_POCKET_ORDER[BagMenu.pocketIdx]) .. ")")
    shot(game, names[i])
  end
  tapWait(game, "right", 40)
  check(BagMenu.pocketIdx == 1, "right on KEY ITEMS wraps to ITEMS")
  for _ = 1, 3 do tapWait(game, "down", 8) end
  check(BagMenu.cursor == 4, "down x3 moves the cursor to row 4 (" .. tostring(BagMenu.cursor) .. ")")
  tapWait(game, "a", 30)
  check(BagMenu.mode == "action", "A opens the item context menu")
  shot(game, "02_bag_context")
  tapWait(game, "b", 30)
  tapWait(game, "b", 60)
  check(waitFor(function() return topId() == "start" end, 120), "B closes the bag back to the start menu")

  check(openEntry("pokemon"), "POKEMON row")
  check(topId() == "party", "POKEMON opens the party menu")
  shot(game, "03_party")
  tapWait(game, "a", 20)
  local PartyMenu = require("src.ui.game3.party_menu")
  local acts = table.concat(PartyMenu.ACTIONS or {}, ",")
  -- pokeemerald/src/party_menu.c:2604
  check(acts == "SUMMARY,FLY,SWITCH,ITEM,CANCEL", "Salamence actions list FLY (" .. acts .. ")")
  shot(game, "03_party_action")
  tapWait(game, "a", 60)
  check(topId() == "summary", "SUMMARY opens the summary")
  local RseSummary = require("src.ui.game3.rse.summary_menu")
  local pages = {}
  for i = 1, 4 do
    if i > 1 then tapWait(game, "right", 40) end
    pages[i] = RseSummary.page()
    shot(game, string.format("04_summary_p%d", i))
  end
  check(table.concat(pages, ",") == "0,1,2,3", "four summary pages INFO/SKILLS/BATTLE/CONTEST (" .. table.concat(pages, ",") .. ")")
  tapWait(game, "a", 40)
  check(RseSummary.detail(), "A on the contest page opens move detail")
  shot(game, "04_summary_contest_detail")
  tapWait(game, "b", 40)
  tapWait(game, "left", 40)
  check(RseSummary.page() == 2, "left returns to BATTLE MOVES")
  for _ = 1, 4 do
    if topId() == "start" then break end
    tapWait(game, "b", 60)
  end
  check(topId() == "start", "back to the start menu")

  check(openEntry("trainer"), "PLAYER row")
  check(topId() == "trainer", "PLAYER opens the trainer card")
  local TrainerCard = require("src.ui.game3.trainer_card")
  check(TrainerCard._rse == true and TrainerCard._card.badges[8] == true, "Emerald card with 8 badges")
  shot(game, "05_card_front")
  tapWait(game, "a", 60)
  check(TrainerCard.side == "back", "A flips the card")
  shot(game, "05_card_back")
  for _ = 1, 3 do
    if topId() == "start" then break end
    tapWait(game, "b", 60)
  end

  check(openEntry("option"), "OPTION row")
  local OptionMenu = require("src.ui.game3.rse.option_menu")
  check(topId() == "option" and OptionMenu.isOpen(), "OPTION opens the Emerald option menu")
  shot(game, "06_options")
  local function rowIndex(id)
    local p = OptionMenu._st.pages[#OptionMenu._st.pages]
    for i, r in ipairs(p.rows) do if r.id == id then return i end end
  end
  local top = OptionMenu._st.pages[1].rows
  check(top[1] and top[1].id == "group.speed" and rowIndex("textSpeed") == nil,
    "cart options are filed into the FRLG categories")
  local gi = rowIndex("group.graphics")
  check(gi ~= nil, "GRAPHICS category row")
  for _ = 1, (gi or 1) - 1 do tapWait(game, "down", 6) end
  shot(game, "06_options_down")
  tapWait(game, "a", 10)
  local fi = rowIndex("frameType")
  check(fi ~= nil and OptionMenu._st.pages[#OptionMenu._st.pages].rows[fi].cart ~= nil,
    "FRAME is a cart row inside GRAPHICS")
  shot(game, "06_options_graphics")
  for _ = 1, (fi or 1) - 1 do tapWait(game, "down", 6) end
  tapWait(game, "right", 10)
  check(Options.block(session.engineOptions or game.options).frameType == 5, "RIGHT on FRAME steps the frame type")
  tapWait(game, "left", 10)
  tapWait(game, "b", 60)
  tapWait(game, "b", 60)
  check(topId() == "start", "B leaves the option menu")

  check(openEntry("save"), "SAVE row")
  local SaveMenu = require("src.ui.game3.save_menu")
  check(topId() == "save" and SaveMenu._rse == true, "SAVE opens the Emerald save dialog")
  shot(game, "07_save")
  tapWait(game, "a", 10)
  check(waitFor(function() return SaveMenu._phase == "saved" or SaveMenu._phase == "overwrite" end, 120),
    "YES saves or asks to overwrite (" .. tostring(SaveMenu._phase) .. ")")
  if SaveMenu._phase == "overwrite" then tapWait(game, "a", 10) end
  check(waitFor(function() return SaveMenu._phase == "saved" end, 120), "saved message")
  shot(game, "07_save_done")
  check(waitFor(function() return not SaveMenu.isOpen() and topId() == nil end, 240),
    "the saved message closes the menus by itself")
  return finish()
end
