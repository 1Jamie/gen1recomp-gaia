local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local d = S.new("em_story_seg1", "/tmp/em_story_seg1")

local LAB = "EM_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB"

local OPENING_SET = {
  "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F_POKE_BALL", "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_RIVAL_MOM",
  "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_RIVAL_SIBLING", "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_TRUCK",
  "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_2F_POKE_BALL", "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_MOM",
  "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_TRUCK", "FLAG_HIDE_LITTLEROOT_TOWN_PLAYERS_HOUSE_VIGOROTH_1",
  "FLAG_HIDE_LITTLEROOT_TOWN_PLAYERS_HOUSE_VIGOROTH_2", "FLAG_HIDE_ROUTE_101_BIRCH_STARTERS_BAG",
  "FLAG_HIDE_ROUTE_101_BIRCH_ZIGZAGOON_BATTLE", "FLAG_HIDE_ROUTE_101_ZIGZAGOON", "FLAG_MET_RIVAL_MOM",
  "FLAG_RESCUED_BIRCH", "FLAG_RIVAL_LEFT_FOR_ROUTE103", "FLAG_SET_WALL_CLOCK", "FLAG_SYS_CLOCK_SET",
  "FLAG_SYS_POKEMON_GET", "FLAG_SYS_TV_HOME", "FLAG_VISITED_LITTLEROOT_TOWN",
}
local OPENING_CLEAR = {
  "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH", "FLAG_HIDE_LITTLEROOT_TOWN_FAT_MAN", "FLAG_HIDE_ROUTE_101_BOY",
}
local OPENING_VARS = {
  VAR_BIRCH_LAB_STATE = 3, VAR_LITTLEROOT_HOUSES_STATE_BRENDAN = 2, VAR_LITTLEROOT_INTRO_STATE = 7,
  VAR_LITTLEROOT_RIVAL_STATE = 3, VAR_LITTLEROOT_TOWN_STATE = 2, VAR_ROUTE101_STATE = 3, VAR_STARTER_MON = 1,
}

local function starter()
  return S.session().party[1]
end

local function battleShot(game, file)
  local taken = false
  return function(st, phase)
    local Ui = require("src.core.game3.battle.ui")
    if not taken and phase == "command" and Ui._mode == "menu" then
      taken = true
      U.wait(10)
      d.shot(game, file)
    end
  end
end

local function shotOnMessage(game, file, pred)
  local taken = false
  return function()
    if not taken and require("src.ui.game3.message").isOpen() and (not pred or pred()) then
      taken = true
      U.wait(12)
      d.shot(game, file)
    end
    return false
  end
end

local BEATS = {}

BEATS[#BEATS + 1] = { id = "start", run = function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "QUINCY", gender = 0, start = {
    map = LAB, x = 6, y = 5, facing = "up", healMap = "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", healX = 4, healY = 2,
  } })
  U.wait(30)
  for _, f in ipairs(OPENING_SET) do S.setFlag(f, true) end
  for _, f in ipairs(OPENING_CLEAR) do S.setFlag(f, false) end
  for k, v in pairs(OPENING_VARS) do S.setVar(k, v) end
  local s = S.session()
  s.party = {}
  local mon = S.giveMon("SPECIES_TORCHIC", 10, { "MOVE_SCRATCH", "MOVE_GROWL", "MOVE_FOCUS_ENERGY", "MOVE_EMBER" })
  d.check(mon ~= nil and s.party[1] == mon, "segment start: Torchic starter (VAR_STARTER_MON 1) in party")
  S.saveCheckpoint(game, "start")
  S.loadCheckpoint(game, "start")
  return d.check(S.mapNow() == LAB and S.var("VAR_BIRCH_LAB_STATE") == 3,
    "segment start: Birch's lab after the starter (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/Route103/scripts.inc:20
BEATS[#BEATS + 1] = { id = "route103", run = function(game)
  S.travel(game, { "EM_LITTLEROOT_TOWN", "EM_ROUTE101", "EM_OLDALE_TOWN", "EM_ROUTE103" })
  if not d.check(S.mapNow() == "EM_ROUTE103", "Littleroot -> Route 101 -> Oldale -> Route 103 on foot") then return false end
  local may = S.objectByScript("Route103_EventScript_Rival")
  if not d.check(may ~= nil, "May waits on Route 103") then return false end
  S.talkTo(game, may)
  S.settle(game, { limit = 20000, onBattleFrame = battleShot(game, "01_route103_may_battle"),
    until_ = function() return S.flag("FLAG_DEFEATED_RIVAL_ROUTE103") and not S.busy() end })
  d.check(S.battles[#S.battles] and S.battles[#S.battles].result == "win", "Route 103 May battle won through the battle UI")
  return d.check(S.flag("FLAG_DEFEATED_RIVAL_ROUTE103") and S.var("VAR_BIRCH_LAB_STATE") == 4,
    "May heads back to the lab (VAR_BIRCH_LAB_STATE=" .. S.var("VAR_BIRCH_LAB_STATE") .. ")")
end }

-- pokeemerald/data/maps/LittlerootTown_ProfessorBirchsLab/scripts.inc:143
BEATS[#BEATS + 1] = { id = "pokedex", run = function(game)
  local dexShot = shotOnMessage(game, "02_birch_pokedex", function() return S.mapNow() == LAB end)
  S.travel(game, { "EM_OLDALE_TOWN", "EM_ROUTE101", "EM_LITTLEROOT_TOWN", LAB }, { settle = { limit = 20000, watch = dexShot } })
  S.settle(game, { limit = 20000, watch = dexShot,
    until_ = function() return S.var("VAR_BIRCH_LAB_STATE") == 5 and not S.busy() end })
  d.check(S.flag("FLAG_SYS_POKEDEX_GET") and S.var("VAR_BIRCH_LAB_STATE") == 5,
    "Birch gives the POKEDEX (VAR_BIRCH_LAB_STATE=" .. S.var("VAR_BIRCH_LAB_STATE") .. ")")
  d.check(S.hasItem("ITEM_POKE_BALL"), "May hands over POKE BALLs")
  local shoesShot = shotOnMessage(game, "03_running_shoes", function() return S.mapNow() == "EM_LITTLEROOT_TOWN" end)
  S.travel(game, { "EM_LITTLEROOT_TOWN", "EM_ROUTE101" }, { settle = { limit = 6000, watch = shoesShot } })
  return d.check(S.flag("FLAG_RECEIVED_RUNNING_SHOES") and S.flag("FLAG_SYS_B_DASH"),
    "Mom stops the player and gives the RUNNING SHOES")
end }

local function fightTrainer(game, label, name, shot, talkOpts, trainer)
  local eo = S.objectByScript(label)
  if not d.check(eo ~= nil, name .. " is on the map") then return false end
  if trainer and S.trainerBeaten(trainer) then
    return d.check(true, name .. " already beaten on the way (" .. trainer .. ")")
  end
  local tid = trainer and S.C():require("trainers", trainer)
  local mine
  for _ = 1, 4 do
    local before = #S.battles
    S.talkTo(game, eo, talkOpts)
    S.settle(game, { limit = 20000, onBattleFrame = shot and battleShot(game, shot) or nil })
    for i = before + 1, #S.battles do
      if not tid or S.battles[i].trainer == tid then mine = S.battles[i] end
    end
    if mine or not tid or S.trainerBeaten(trainer) then break end
  end
  return d.check(mine ~= nil and mine.result == "win", name .. " battle won (" .. tostring(mine and mine.result) .. ")")
end

local function fightTrainers(game, list)
  for _, t in ipairs(list) do
    fightTrainer(game, t[1], t[2], t.shot, nil, t.trainer)
  end
end

-- pokeemerald/data/maps/OldaleTown/scripts.inc:36
BEATS[#BEATS + 1] = { id = "oldale", run = function(game)
  S.travel(game, { "EM_OLDALE_TOWN" })
  local clerk = S.objectByScript("OldaleTown_EventScript_MartEmployee")
  if not d.check(clerk ~= nil, "Oldale Mart employee waits by the Pokemon Center") then return false end
  S.talkTo(game, clerk)
  S.settle(game, { limit = 8000, watch = shotOnMessage(game, "04_oldale_potion", function()
    return S.flag("FLAG_TEMP_1") and S.mapNow() == "EM_OLDALE_TOWN" end),
    until_ = function() return S.flag("FLAG_RECEIVED_POTION_OLDALE") and not S.busy() end })
  return d.check(S.flag("FLAG_RECEIVED_POTION_OLDALE") and S.hasItem("ITEM_POTION"),
    "the Mart employee walks the player to the Mart and gives a POTION")
end }

-- pokeemerald/data/maps/Route102/scripts.inc:1
BEATS[#BEATS + 1] = { id = "route102", run = function(game)
  S.travel(game, { "EM_ROUTE102" })
  if not d.check(S.mapNow() == "EM_ROUTE102", "Oldale west exit open (FLAG_ADVENTURE_STARTED) -> Route 102") then return false end
  fightTrainers(game, {
    { "Route102_EventScript_Calvin", "Youngster Calvin", shot = "05_route102_calvin", trainer = "TRAINER_CALVIN_1" },
    { "Route102_EventScript_Rick", "Bug Catcher Rick", trainer = "TRAINER_RICK" },
    { "Route102_EventScript_Allen", "Youngster Allen", trainer = "TRAINER_ALLEN" },
    { "Route102_EventScript_Tiana", "Lass Tiana", trainer = "TRAINER_TIANA" },
  })
  return true
end }

-- pokeemerald/data/maps/PetalburgCity_Gym/scripts.inc:101
BEATS[#BEATS + 1] = { id = "petalburg", run = function(game)
  S.travel(game, { "EM_PETALBURG_CITY" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_PETALBURG_CITY", "Route 102 -> Petalburg City") then return false end
  S.settle(game, { limit = 6000 })
  S.travel(game, { "EM_PETALBURG_CITY_GYM" })
  local norman = S.objectByScript("PetalburgCity_Gym_EventScript_Norman")
  if not d.check(norman ~= nil, "Norman stands at the gym entrance") then return false end
  S.talkTo(game, norman)
  local sawNorman = shotOnMessage(game, "06_meet_norman")
  local sawWally = false
  S.settle(game, { limit = 40000, watch = function()
      sawNorman()
      if not sawWally and require("src.core.game3.battle").isActive() then sawWally = true end
      return false
    end,
    onBattleFrame = battleShot(game, "07_wally_catch_tutorial"),
    until_ = function() return S.var("VAR_PETALBURG_GYM_STATE") >= 2 and S.mapNow() == "EM_PETALBURG_CITY_GYM" and not S.busy() end })
  local wb = S.battles[#S.battles]
  d.check(wb and wb.result == "catch", "Wally's catch tutorial battle runs by itself (" .. tostring(wb and wb.result) .. ")")
  d.shot(game, "08_back_in_gym")
  return d.check(S.var("VAR_PETALBURG_GYM_STATE") == 2 and S.var("VAR_PETALBURG_CITY_STATE") >= 3,
    "back in the gym Norman sends the player to Rustboro (VAR_PETALBURG_GYM_STATE=" .. S.var("VAR_PETALBURG_GYM_STATE") .. ")")
end }

-- pokeemerald/data/maps/PetalburgWoods/scripts.inc:4
BEATS[#BEATS + 1] = { id = "woods", run = function(game)
  S.travel(game, { "EM_PETALBURG_CITY", "EM_ROUTE104", "EM_PETALBURG_WOODS" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_PETALBURG_WOODS", "Petalburg -> Route 104 (south) -> Petalburg Woods") then return false end
  S.goTo(game, { 26, 23 }, { settle = { limit = 20000 } })
  local grunt = false
  S.settle(game, { limit = 30000, onBattleFrame = battleShot(game, "09_woods_aqua_grunt"),
    onBattleStart = function() grunt = true end,
    until_ = function() return S.var("VAR_PETALBURG_WOODS_STATE") == 1 and not S.busy() end })
  d.check(d.ran("PetalburgWoods_EventScript_DevonResearcherLeft") or d.ran("PetalburgWoods_EventScript_DevonResearcherRight"),
    "the Devon researcher looks for Shroomish (coord event)")
  d.check(grunt and S.battles[#S.battles].result == "win", "Team Aqua grunt battle in Petalburg Woods won")
  d.check(S.hasItem("ITEM_GREAT_BALL"), "the researcher gives a GREAT BALL")
  return d.check(S.var("VAR_PETALBURG_WOODS_STATE") == 1, "VAR_PETALBURG_WOODS_STATE=1")
end }

-- pokeemerald/data/maps/RustboroCity_Gym/scripts.inc:4
BEATS[#BEATS + 1] = { id = "roxanne", run = function(game)
  local mon = starter()
  S.setLevel(mon, 20, "SPECIES_COMBUSKEN")
  S.setMoves(mon, { "MOVE_EMBER", "MOVE_DOUBLE_KICK", "MOVE_PECK", "MOVE_FOCUS_ENERGY" })
  S.travel(game, { "EM_ROUTE104", "EM_RUSTBORO_CITY" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_RUSTBORO_CITY", "Petalburg Woods -> Route 104 (north) -> Rustboro City") then return false end
  S.travel(game, { "EM_RUSTBORO_CITY_GYM" })
  if not d.check(S.mapNow() == "EM_RUSTBORO_CITY_GYM", "into the Rustboro Gym") then return false end
  fightTrainers(game, {
    { "RustboroCity_Gym_EventScript_Josh", "Youngster Josh", trainer = "TRAINER_JOSH" },
    { "RustboroCity_Gym_EventScript_Tommy", "Youngster Tommy", trainer = "TRAINER_TOMMY" },
    { "RustboroCity_Gym_EventScript_Marc", "Hiker Marc", trainer = "TRAINER_MARC" },
  })
  fightTrainer(game, "RustboroCity_Gym_EventScript_Roxanne", "Leader Roxanne", "10_roxanne", nil, "TRAINER_ROXANNE_1")
  S.settle(game, { limit = 20000, until_ = function() return S.flag("FLAG_RECEIVED_TM_ROCK_TOMB") and not S.busy() end })
  d.shot(game, "11_stone_badge")
  d.check(S.flag("FLAG_BADGE01_GET") and S.var("VAR_RUSTBORO_CITY_STATE") == 1, "STONE BADGE (FLAG_BADGE01_GET)")
  return d.check(S.hasItem("ITEM_TM39"), "Roxanne gives TM39 ROCK TOMB")
end }

-- pokeemerald/data/maps/RustboroCity/scripts.inc:270
BEATS[#BEATS + 1] = { id = "stolen_goods", run = function(game)
  S.travel(game, { "EM_RUSTBORO_CITY" })
  S.goTo(game, function(x, y) return x == 23 and y >= 20 and y <= 24 end, { settle = { limit = 20000 } })
  local shotTaken = shotOnMessage(game, "12_devon_goods_stolen", function() return S.flag("FLAG_DEVON_GOODS_STOLEN") == false end)
  S.settle(game, { limit = 20000, watch = shotTaken,
    until_ = function() return S.var("VAR_RUSTBORO_CITY_STATE") == 2 and not S.busy() end })
  return d.check(S.flag("FLAG_DEVON_GOODS_STOLEN") and S.var("VAR_RUSTBORO_CITY_STATE") == 2,
    "leaving the gym: an Aqua grunt steals the DEVON GOODS (VAR_RUSTBORO_CITY_STATE=" .. S.var("VAR_RUSTBORO_CITY_STATE") .. ")")
end }

-- pokeemerald/data/maps/RusturfTunnel/scripts.inc:287
BEATS[#BEATS + 1] = { id = "rusturf", run = function(game)
  S.travel(game, { "EM_ROUTE116" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE116", "Rustboro -> Route 116") then return false end
  S.goTo(game, { 47, 9 }, { settle = { limit = 20000 } })
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "13_briney_peeko"),
    until_ = function() return S.var("VAR_ROUTE116_STATE") == 2 and not S.busy() end })
  d.check(S.var("VAR_ROUTE116_STATE") == 2, "Mr. Briney asks for help: Peeko was taken into the tunnel")
  S.travel(game, { "EM_RUSTURF_TUNNEL" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_RUSTURF_TUNNEL", "Route 116 -> Rusturf Tunnel") then return false end
  S.settle(game, { limit = 4000 })
  local grunt = S.objectByScript("RusturfTunnel_EventScript_Grunt")
  if not d.check(grunt ~= nil, "the Aqua grunt holds Peeko in the tunnel") then return false end
  S.talkTo(game, grunt, { settle = { limit = 20000 } })
  S.settle(game, { limit = 30000, onBattleFrame = battleShot(game, "14_rusturf_grunt"),
    until_ = function() return S.flag("FLAG_RECOVERED_DEVON_GOODS") and not S.busy() end })
  d.check(S.battles[#S.battles] and S.battles[#S.battles].result == "win", "Rusturf Tunnel grunt battle won")
  return d.check(S.hasItem("ITEM_DEVON_GOODS") and S.var("VAR_RUSTBORO_CITY_STATE") == 4,
    "DEVON GOODS recovered (FLAG_RECOVERED_DEVON_GOODS, VAR_RUSTBORO_CITY_STATE=" .. S.var("VAR_RUSTBORO_CITY_STATE") .. ")")
end }

-- pokeemerald/data/maps/RustboroCity_DevonCorp_3F/scripts.inc:28
BEATS[#BEATS + 1] = { id = "devon", run = function(game)
  S.travel(game, { "EM_ROUTE116", "EM_RUSTBORO_CITY" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_RUSTBORO_CITY", "back to Rustboro with the goods") then return false end
  local cells = { ["30,9"] = true, ["31,10"] = true, ["30,11"] = true, ["30,12"] = true }
  S.goTo(game, function(x, y) return cells[x .. "," .. y] end, { settle = { limit = 20000 } })
  S.settle(game, { limit = 30000, watch = shotOnMessage(game, "15_mr_stone", function()
      return S.mapNow() == "EM_RUSTBORO_CITY_DEVON_CORP_3F" and S.hasItem("ITEM_LETTER") end),
    until_ = function() return S.var("VAR_RUSTBORO_CITY_STATE") == 6 and not S.busy() end })
  d.check(S.flag("FLAG_RETURNED_DEVON_GOODS"), "the Devon employee takes the goods back and escorts the player to 3F")
  d.check(S.hasItem("ITEM_LETTER"), "Mr. Stone gives the LETTER for Steven")
  return d.check(S.flag("FLAG_SYS_POKENAV_GET") and S.var("VAR_RUSTBORO_CITY_STATE") == 6,
    "Mr. Stone gives the POKENAV (VAR_RUSTBORO_CITY_STATE=" .. S.var("VAR_RUSTBORO_CITY_STATE") .. ")")
end }

local function pokenavTutorial(game)
  local Pokenav = require("src.ui.game3.rse.pokenav.init")
  local function nav() return Pokenav.active() end
  local function screen() local n = nav() return n and n.screen end
  local function idle()
    local n = nav()
    return n and n.phase == "menu" and not n:busy(n.screenTask) and not n:busy(n.loopTask)
  end
  local function waitIdle(limit)
    for _ = 1, limit or 900 do
      if idle() or not Pokenav.isOpen() then return true end
      U.wait(1)
    end
  end
  local function press(btn)
    U.tap(game, btn)
    U.wait(2)
    waitIdle()
    U.wait(2)
  end
  waitIdle()
  d.shot(game, "17_pokenav_tutorial")
  for _ = 1, 6 do
    local sc = screen()
    if not sc or sc.currMenuItem == 2 then break end
    press("down")
  end
  press("a")
  waitIdle()
  local mc = screen()
  press("a")
  U.tap(game, "a")
  U.wait(30)
  for _ = 1, 4000 do
    if mc and mc.printer and not mc.printer:isActive() and idle() then break end
    if mc and mc.printer and mc.printer.state ~= "char" then U.tap(game, "a") end
    U.wait(1)
  end
  d.shot(game, "18_pokenav_call_mr_stone")
  press("a")
  U.wait(10)
  for _ = 1, 6 do
    if not Pokenav.isOpen() then break end
    press("b")
  end
  return not Pokenav.isOpen()
end

-- pokeemerald/data/maps/RustboroCity/scripts.inc:31
BEATS[#BEATS + 1] = { id = "match_call", run = function(game)
  S.travel(game, { "EM_RUSTBORO_CITY_DEVON_CORP_2F", "EM_RUSTBORO_CITY_DEVON_CORP_1F", "EM_RUSTBORO_CITY" })
  local Pokenav = require("src.ui.game3.rse.pokenav.init")
  local closed
  S.settle(game, { limit = 20000, choice = function() return "NAV" end,
    watch = shotOnMessage(game, "16_match_call_scientist", function() return S.flag("FLAG_HAS_MATCH_CALL") end),
    onIdleUi = function()
      if Pokenav.isOpen() and closed == nil then closed = pokenavTutorial(game) return true end
      return false
    end,
    until_ = function() return S.var("VAR_RUSTBORO_CITY_STATE") == 7 and not S.busy() end })
  d.check(closed == true, "the PokeNav tutorial: MATCH CALL, call Mr. Stone, switch off")
  return d.check(S.flag("FLAG_HAS_MATCH_CALL") and S.var("VAR_RUSTBORO_CITY_STATE") == 7,
    "outside Devon the scientist adds MATCH CALL (VAR_RUSTBORO_CITY_STATE=" .. S.var("VAR_RUSTBORO_CITY_STATE") .. ")")
end }

-- pokeemerald/data/maps/RustboroCity/scripts.inc:720
BEATS[#BEATS + 1] = { id = "may_rustboro", run = function(game)
  S.goTo(game, function(x, y) return y == 53 and x >= 12 and x <= 19 end, { settle = { limit = 30000,
    onBattleFrame = battleShot(game, "19_rustboro_may_battle") } })
  S.settle(game, { limit = 30000, onBattleFrame = battleShot(game, "19_rustboro_may_battle"),
    until_ = function() return S.flag("FLAG_DEFEATED_RIVAL_RUSTBORO") and not S.busy() end })
  d.check(S.flag("FLAG_MET_RIVAL_RUSTBORO") and S.flag("FLAG_ENABLE_RIVAL_MATCH_CALL"), "May registers in the MATCH CALL")
  return d.check(S.flag("FLAG_DEFEATED_RIVAL_RUSTBORO") and S.battles[#S.battles].result == "win",
    "Rustboro May battle won (FLAG_DEFEATED_RIVAL_RUSTBORO)")
end }

-- pokeemerald/data/maps/Route104_MrBrineysHouse/scripts.inc:17
BEATS[#BEATS + 1] = { id = "briney_dewford", run = function(game)
  S.travel(game, { "EM_ROUTE104", "EM_PETALBURG_WOODS", { "EM_ROUTE104", arrive = { 10, 38 } }, "EM_ROUTE104_MR_BRINEYS_HOUSE" },
    { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE104_MR_BRINEYS_HOUSE", "Route 104 -> Mr. Briney's cottage") then return false end
  local briney = S.objectByScript("Route104_MrBrineysHouse_EventScript_Briney")
  if not d.check(briney ~= nil, "Mr. Briney is home with Peeko") then return false end
  S.talkTo(game, briney)
  local sailShot = false
  S.settle(game, { limit = 40000, watch = function()
      if not sailShot and S.mapNow() == "EM_ROUTE105" then sailShot = true d.shot(game, "20_sailing_route105") end
    end,
    until_ = function() return S.mapNow() == "EM_DEWFORD_TOWN" and S.var("VAR_BOARD_BRINEY_BOAT_STATE") == 0 and not S.busy() end })
  d.shot(game, "21_landed_dewford")
  return d.check(S.mapNow() == "EM_DEWFORD_TOWN" and not S.flag("FLAG_HIDE_MR_BRINEY_DEWFORD_TOWN"),
    "Mr. Briney sails the player across Route 105/106 to Dewford (" .. tostring(S.mapNow()) .. ")")
end }

local function flashLevel()
  local s = S.session()
  return tonumber(s and s.flashLevel) or 0
end

-- pokeemerald/data/maps/DewfordTown_Gym/scripts.inc:5
BEATS[#BEATS + 1] = { id = "brawly", run = function(game)
  local mon = starter()
  S.setLevel(mon, 26)
  S.travel(game, { "EM_DEWFORD_TOWN_GYM" })
  if not d.check(S.mapNow() == "EM_DEWFORD_TOWN_GYM", "into the Dewford Gym") then return false end
  S.settle(game, { limit = 600 })
  local dark = flashLevel()
  d.check(dark == 7, "dark gym: ON_TRANSITION sets flash level 7 with no trainers beaten (" .. dark .. ")")
  U.wait(20)
  d.shot(game, "22_dewford_gym_dark")
  local levels = { dark }
  local gym = {
    { "DewfordTown_Gym_EventScript_Laura", "Battle Girl Laura", trainer = "TRAINER_LAURA" },
    { "DewfordTown_Gym_EventScript_Takao", "Black Belt Takao", trainer = "TRAINER_TAKAO" },
    { "DewfordTown_Gym_EventScript_Brenden", "Sailor Brenden", trainer = "TRAINER_BRENDEN" },
    { "DewfordTown_Gym_EventScript_Cristian", "Black Belt Cristian", trainer = "TRAINER_CRISTIAN" },
    { "DewfordTown_Gym_EventScript_Lilith", "Battle Girl Lilith", trainer = "TRAINER_LILITH" },
    { "DewfordTown_Gym_EventScript_Jocelyn", "Battle Girl Jocelyn", trainer = "TRAINER_JOCELYN" },
  }
  local consistent = true
  for _, t in ipairs(gym) do
    fightTrainer(game, t[1], t[2], nil, nil, t.trainer)
    S.settle(game, { limit = 4000 })
    local beaten = 0
    for _, g in ipairs(gym) do if S.trainerBeaten(g.trainer) then beaten = beaten + 1 end end
    levels[#levels + 1] = flashLevel()
    if flashLevel() ~= 7 - beaten then consistent = false end
  end
  d.note("flash levels " .. table.concat(levels, ","))
  d.check(consistent and levels[#levels] == 1, "each gym trainer beaten widens the flash radius (animateflash, "
    .. table.concat(levels, ",") .. ")")
  d.shot(game, "23_dewford_gym_brighter")
  fightTrainer(game, "DewfordTown_Gym_EventScript_Brawly", "Leader Brawly", "24_brawly", nil, "TRAINER_BRAWLY_1")
  S.settle(game, { limit = 20000, until_ = function() return S.flag("FLAG_RECEIVED_TM_BULK_UP") and not S.busy() end })
  d.check(flashLevel() == 0, "lights fully on after Brawly (" .. flashLevel() .. ")")
  d.shot(game, "25_knuckle_badge")
  d.check(S.hasItem("ITEM_TM08"), "Brawly gives TM08 BULK UP")
  return d.check(S.flag("FLAG_BADGE02_GET"), "KNUCKLE BADGE (FLAG_BADGE02_GET)")
end }

-- pokeemerald/data/maps/GraniteCave_StevensRoom/scripts.inc:4
BEATS[#BEATS + 1] = { id = "granite_cave", run = function(game)
  S.travel(game, { "EM_DEWFORD_TOWN", "EM_ROUTE106", "EM_GRANITE_CAVE_1F",
    { "EM_GRANITE_CAVE_B1F", arrive = { 4, 21 } }, { "EM_GRANITE_CAVE_B2F", arrive = { 28, 21 } },
    { "EM_GRANITE_CAVE_B1F", arrive = { 29, 13 } }, { "EM_GRANITE_CAVE_1F", arrive = { 35, 3 } },
    "EM_GRANITE_CAVE_STEVENS_ROOM" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_GRANITE_CAVE_STEVENS_ROOM", "Dewford -> Route 106 -> Granite Cave 1F/B1F/B2F -> Steven's room ("
      .. tostring(S.mapNow()) .. ")") then return false end
  local steven = S.objectByScript("GraniteCave_StevensRoom_EventScript_Steven")
  if not d.check(steven ~= nil, "Steven waits at the back of Granite Cave") then return false end
  S.talkTo(game, steven)
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "26_steven_letter"),
    until_ = function() return S.flag("FLAG_REGISTERED_STEVEN_POKENAV") and not S.busy() end })
  d.check(S.flag("FLAG_DELIVERED_STEVEN_LETTER") and not S.hasItem("ITEM_LETTER"), "the LETTER is delivered to Steven")
  d.check(S.hasItem("ITEM_TM47"), "Steven gives TM47 STEEL WING")
  return d.check(S.flag("FLAG_REGISTERED_STEVEN_POKENAV"), "Steven registers in the MATCH CALL")
end }

-- pokeemerald/data/maps/DewfordTown/scripts.inc:141
BEATS[#BEATS + 1] = { id = "briney_slateport", run = function(game)
  S.travel(game, { { "EM_GRANITE_CAVE_1F", arrive = { 5, 10 } }, { "EM_GRANITE_CAVE_B1F", arrive = { 25, 13 } },
    { "EM_GRANITE_CAVE_B2F", arrive = { 29, 13 } }, { "EM_GRANITE_CAVE_B1F", arrive = { 28, 21 } },
    { "EM_GRANITE_CAVE_1F", arrive = { 17, 11 } }, "EM_ROUTE106", "EM_DEWFORD_TOWN" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_DEWFORD_TOWN", "back through Granite Cave to Dewford") then return false end
  local briney = S.objectByScript("DewfordTown_EventScript_Briney")
  if not d.check(briney ~= nil, "Mr. Briney waits at the Dewford dock") then return false end
  S.talkTo(game, briney)
  local sailShot, lastMap = false, nil
  S.settle(game, { limit = 40000, choice = function() return "SLATEPORT" end,
    watch = function()
      if not sailShot and S.mapNow() == "EM_ROUTE108" then sailShot = true d.shot(game, "27_sailing_route108") end
      if S.mapNow() ~= lastMap then
        lastMap = S.mapNow()
        local P = require("src.core.game3.player")
        d.note("sail map " .. tostring(lastMap) .. " at " .. P.cellX .. "," .. P.cellY .. " vm " .. S.vmWhere())
      end
    end,
    until_ = function() return S.mapNow() == "EM_ROUTE109" and not S.flag("FLAG_HIDE_ROUTE_109_MR_BRINEY") and not S.busy() end })
  d.shot(game, "28_landed_route109")
  return d.check(S.mapNow() == "EM_ROUTE109" and not S.flag("FLAG_HIDE_ROUTE_109_MR_BRINEY"),
    "Mr. Briney sails across Route 107/108 and lands on the Route 109 beach (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/SlateportCity_OceanicMuseum_2F/scripts.inc:4
BEATS[#BEATS + 1] = { id = "museum", run = function(game)
  S.setLevel(starter(), 28)
  S.travel(game, { "EM_SLATEPORT_CITY", "EM_SLATEPORT_CITY_STERNS_SHIPYARD_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_SLATEPORT_CITY_STERNS_SHIPYARD_1F", "Route 109 -> Slateport -> Stern's Shipyard") then return false end
  local dock = S.objectByScript("SlateportCity_SternsShipyard_1F_EventScript_Dock")
  S.talkTo(game, dock)
  S.settle(game, { limit = 8000, until_ = function() return S.flag("FLAG_DOCK_REJECTED_DEVON_GOODS") and not S.busy() end })
  d.check(S.flag("FLAG_DOCK_REJECTED_DEVON_GOODS") and S.flag("FLAG_HIDE_SLATEPORT_CITY_TEAM_AQUA"),
    "Dock sends the player to Capt. Stern at the museum; the Aqua line leaves the museum door")
  S.travel(game, { "EM_SLATEPORT_CITY", "EM_SLATEPORT_CITY_OCEANIC_MUSEUM_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_SLATEPORT_CITY_OCEANIC_MUSEUM_1F", "Slateport -> Oceanic Museum") then return false end
  local money = S.session().money
  S.goTo(game, function(x, y) return (x == 9 or x == 10) and y == 7 end, { settle = { limit = 8000 } })
  S.settle(game, { limit = 8000, until_ = function() return S.var("VAR_SLATEPORT_MUSEUM_1F_STATE") == 1 and not S.busy() end })
  d.check(S.var("VAR_SLATEPORT_MUSEUM_1F_STATE") == 1 and S.session().money == money - 50,
    "the entrance fee (50) is paid at the counter")
  S.travel(game, { "EM_SLATEPORT_CITY_OCEANIC_MUSEUM_2F" })
  local stern = S.objectByScript("SlateportCity_OceanicMuseum_2F_EventScript_CaptStern")
  if not d.check(stern ~= nil, "Capt. Stern is on the museum's 2F") then return false end
  local before = #S.battles
  S.talkTo(game, stern)
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "29_museum_aqua_grunt"),
    until_ = function() return S.flag("FLAG_DELIVERED_DEVON_GOODS") and not S.busy() end })
  local won = 0
  for i = before + 1, #S.battles do if S.battles[i].result == "win" then won = won + 1 end end
  d.check(won == 2, "both Team Aqua grunts on 2F beaten (" .. won .. ")")
  d.shot(game, "30_goods_delivered")
  d.check(not S.hasItem("ITEM_DEVON_GOODS"), "DEVON GOODS handed to Capt. Stern")
  return d.check(S.flag("FLAG_DELIVERED_DEVON_GOODS") and S.var("VAR_SLATEPORT_OUTSIDE_MUSEUM_STATE") == 1,
    "Archie leaves, Stern gets the goods (FLAG_DELIVERED_DEVON_GOODS)")
end }

-- pokeemerald/data/maps/Route110/scripts.inc:430
BEATS[#BEATS + 1] = { id = "route110", run = function(game)
  S.travel(game, { "EM_SLATEPORT_CITY_OCEANIC_MUSEUM_1F", "EM_SLATEPORT_CITY" }, { settle = { limit = 20000 } })
  d.check(S.healAtCenter(game, "EM_SLATEPORT_CITY", "SlateportCity"), "the Slateport Pokemon Center nurse heals the party")
  S.travel(game, { "EM_ROUTE110" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE110", "Slateport -> Route 110") then return false end
  if S.var("VAR_REGISTER_BIRCH_STATE") == 1 then
    S.goTo(game, function(x, y) return y == 85 and x >= 7 and x <= 10 end, { settle = { limit = 20000 } })
    S.settle(game, { limit = 20000, watch = shotOnMessage(game, "31_route110_birch"),
      until_ = function() return S.var("VAR_REGISTER_BIRCH_STATE") ~= 1 and not S.busy() end })
    d.check(S.flag("FLAG_ENABLE_PROF_BIRCH_MATCH_CALL"), "Birch registers in the MATCH CALL on Route 110")
  end
  S.setLevel(starter(), 40)
  S.setMoves(starter(), { "MOVE_SLASH", "MOVE_DOUBLE_KICK", "MOVE_EMBER", "MOVE_PECK" })
  S.goTo(game, function(x, y) return y == 58 and x >= 33 and x <= 35 end, { settle = { limit = 30000 } })
  if S.needsHeal() then
    S.travel(game, { "EM_SLATEPORT_CITY" }, { settle = { limit = 20000 } })
    d.check(S.healAtCenter(game, "EM_SLATEPORT_CITY", "SlateportCity"), "back to Slateport to heal after the Route 110 trainers")
    S.travel(game, { "EM_ROUTE110" }, { settle = { limit = 20000 } })
  end
  S.goTo(game, function(x, y) return y == 56 and x >= 33 and x <= 35 end, { settle = { limit = 30000,
    onBattleFrame = battleShot(game, "32_route110_may_battle") } })
  S.settle(game, { limit = 30000, onBattleFrame = battleShot(game, "32_route110_may_battle"),
    until_ = function() return S.var("VAR_ROUTE110_STATE") ~= 0 and not S.busy() end })
  return d.check(S.var("VAR_ROUTE110_STATE") ~= 0 and S.battles[#S.battles].result == "win",
    "Route 110 May battle won (VAR_ROUTE110_STATE=" .. S.var("VAR_ROUTE110_STATE") .. ")")
end }

-- pokeemerald/data/maps/MauvilleCity/scripts.inc:84
BEATS[#BEATS + 1] = { id = "wally_mauville", run = function(game)
  S.travel(game, { "EM_MAUVILLE_CITY" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_MAUVILLE_CITY", "Route 110 -> Mauville City") then return false end
  d.check(S.healAtCenter(game, "EM_MAUVILLE_CITY", "MauvilleCity"), "the Mauville Pokemon Center nurse heals the party")
  local wally = S.objectByScript("MauvilleCity_EventScript_Wally")
  if not d.check(wally ~= nil, "Wally and his uncle stand by the gym") then return false end
  S.talkTo(game, wally)
  S.settle(game, { limit = 40000, onBattleFrame = battleShot(game, "33_mauville_wally_battle"),
    until_ = function() return S.flag("FLAG_DEFEATED_WALLY_MAUVILLE") and not S.busy() end })
  d.shot(game, "34_after_wally")
  return d.check(S.flag("FLAG_DEFEATED_WALLY_MAUVILLE") and S.battles[#S.battles].result == "win",
    "Wally battle won in Mauville (FLAG_DEFEATED_WALLY_MAUVILLE)")
end }

local SWITCHES = { { 0, 15 }, { 4, 12 }, { 3, 9 }, { 8, 9 } }

-- pokeemerald/data/maps/MauvilleCity_Gym/scripts.inc:1
BEATS[#BEATS + 1] = { id = "wattson", run = function(game)
  S.setLevel(starter(), 40)
  d.check(S.healAtCenter(game, "EM_MAUVILLE_CITY", "MauvilleCity"), "healed again before the gym")
  S.travel(game, { "EM_MAUVILLE_CITY_GYM" })
  if not d.check(S.mapNow() == "EM_MAUVILLE_CITY_GYM", "into the Mauville Gym") then return false end
  S.settle(game, { limit = 600 })
  d.shot(game, "35_mauville_gym")
  local wattson = S.objectByScript("MauvilleCity_Gym_EventScript_Wattson")
  if not d.check(wattson ~= nil, "Wattson at the back of the gym") then return false end
  local P = require("src.core.game3.player")
  local pressed = {}
  local function avoidExcept(i)
    local a = {}
    for j, sw in ipairs(SWITCHES) do
      if j ~= i and not (P.cellX == sw[1] and P.cellY == sw[2]) then a[sw[1] .. "," .. sw[2]] = true end
    end
    return a
  end
  local function nearWattson(x, y) return math.abs(x - wattson.cellX) + math.abs(y - wattson.cellY) == 1 end
  local function pressBestSwitch()
    local best, bestLen
    for i, sw in ipairs(SWITCHES) do
      if not (P.cellX == sw[1] and P.cellY == sw[2]) then
        local p = S.path(game, sw, { avoid = avoidExcept(i) })
        if p and (pressed[i] or 0) < 3 and (not best or #p < bestLen) then best, bestLen = i, #p end
      end
    end
    if not best then return false end
    pressed[best] = (pressed[best] or 0) + 1
    S.goTo(game, SWITCHES[best], { settle = { limit = 20000 }, avoid = avoidExcept(best) })
    S.settle(game, { limit = 4000 })
    d.note(string.format("pressed switch %d at %d,%d (VAR_MAUVILLE_GYM_STATE=%d)", best, SWITCHES[best][1], SWITCHES[best][2],
      S.var("VAR_MAUVILLE_GYM_STATE")))
    return true
  end
  local opened, healed = false, 0
  for _ = 1, 16 do
    if S.trainerBeaten("TRAINER_WATTSON_1") then break end
    if healed < 3 and S.needsHeal() then
      healed = healed + 1
      d.check(S.healAtCenter(game, "EM_MAUVILLE_CITY", "MauvilleCity"), "back to the Pokemon Center after the gym trainers")
      S.travel(game, { "EM_MAUVILLE_CITY_GYM" })
      S.settle(game, { limit = 600 })
      wattson = S.objectByScript("MauvilleCity_Gym_EventScript_Wattson") or wattson
      pressed = {}
    end
    if S.path(game, nearWattson, { avoid = avoidExcept(nil) }) then
      if next(pressed) and not opened then
        opened = true
        d.shot(game, "36_switches_pressed")
      end
      S.goTo(game, nearWattson, { avoid = avoidExcept(nil), settle = { limit = 20000 } })
      if not (healed < 3 and S.needsHeal()) then
        S.talkTo(game, wattson, { avoid = avoidExcept(nil), settle = { limit = 20000 } })
        S.settle(game, { limit = 20000, onBattleFrame = battleShot(game, "37_wattson") })
      end
    elseif not pressBestSwitch() then
      break
    end
  end
  d.check(next(pressed) ~= nil and opened, "switch puzzle: pressing switches toggles the beams open to Wattson")
  local wb
  local wid = S.C():require("trainers", "TRAINER_WATTSON_1")
  for _, b in ipairs(S.battles) do if b.trainer == wid then wb = b end end
  d.check(wb and wb.result == "win", "Leader Wattson battle won (" .. tostring(wb and wb.result) .. ")")
  S.settle(game, { limit = 20000, until_ = function() return S.flag("FLAG_RECEIVED_TM_SHOCK_WAVE") and not S.busy() end })
  d.shot(game, "38_dynamo_badge")
  d.check(S.hasItem("ITEM_TM34"), "Wattson gives TM34 SHOCK WAVE")
  return d.check(S.flag("FLAG_BADGE03_GET") and S.flag("FLAG_DEFEATED_MAUVILLE_GYM"), "DYNAMO BADGE (FLAG_BADGE03_GET)")
end }

return function(game)
  io.stdout:setvbuf("line")
  local from = os.getenv("EM_STORY_FROM")
  local to = os.getenv("EM_STORY_TO")
  local startAt = 1
  if from then
    for i, b in ipairs(BEATS) do
      if b.id == from then startAt = i end
    end
    if startAt > 1 then
      for _ = 1, 900 do
        if game.phase == "boot" and game.boot then break end
        U.wait(1)
      end
      if not d.check(S.loadCheckpoint(game, BEATS[startAt - 1].id), "resume from checkpoint " .. BEATS[startAt - 1].id) then
        return d.finish()
      end
    end
  end
  for i = startAt, #BEATS do
    local b = BEATS[i]
    d.note("BEAT " .. b.id .. " on " .. tostring(S.mapNow()))
    local ok, res = xpcall(function() return b.run(game) end, debug.traceback)
    if not ok then
      d.check(false, "beat " .. b.id .. " raised: " .. tostring(res))
      break
    end
    if res == false then
      d.note("beat " .. b.id .. " stopped at " .. tostring(S.mapNow()) .. " vm " .. S.vmWhere())
      break
    end
    S.saveCheckpoint(game, b.id)
    if to and b.id == to then break end
  end
  d.finish()
end
