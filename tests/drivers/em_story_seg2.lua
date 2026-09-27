local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local d = S.new("em_story_seg2", "/tmp/em_story_seg2")

local SEG1_SET = {
  "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F_POKE_BALL", "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_RIVAL_MOM",
  "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_RIVAL_SIBLING", "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_TRUCK",
  "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_2F_POKE_BALL", "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_MOM",
  "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_TRUCK", "FLAG_HIDE_LITTLEROOT_TOWN_PLAYERS_HOUSE_VIGOROTH_1",
  "FLAG_HIDE_LITTLEROOT_TOWN_PLAYERS_HOUSE_VIGOROTH_2", "FLAG_HIDE_ROUTE_101_BIRCH_STARTERS_BAG",
  "FLAG_HIDE_ROUTE_101_BIRCH_ZIGZAGOON_BATTLE", "FLAG_HIDE_ROUTE_101_ZIGZAGOON", "FLAG_MET_RIVAL_MOM",
  "FLAG_RESCUED_BIRCH", "FLAG_RIVAL_LEFT_FOR_ROUTE103", "FLAG_SET_WALL_CLOCK", "FLAG_SYS_CLOCK_SET",
  "FLAG_SYS_POKEMON_GET", "FLAG_SYS_TV_HOME", "FLAG_VISITED_LITTLEROOT_TOWN",
  "FLAG_ADDED_MATCH_CALL_TO_POKENAV", "FLAG_ADVENTURE_STARTED", "FLAG_BADGE01_GET", "FLAG_BADGE02_GET",
  "FLAG_DEFEATED_DEWFORD_GYM", "FLAG_DEFEATED_RIVAL_ROUTE103", "FLAG_DEFEATED_RIVAL_RUSTBORO", "FLAG_DEFEATED_RUSTBORO_GYM",
  "FLAG_DEFEATED_WALLY_MAUVILLE", "FLAG_DELIVERED_DEVON_GOODS", "FLAG_DELIVERED_STEVEN_LETTER",
  "FLAG_DOCK_REJECTED_DEVON_GOODS", "FLAG_ENABLE_BRAWLY_MATCH_CALL", "FLAG_ENABLE_FIRST_WALLY_POKENAV_CALL",
  "FLAG_ENABLE_MR_STONE_POKENAV", "FLAG_ENABLE_NORMAN_MATCH_CALL", "FLAG_ENABLE_PROF_BIRCH_MATCH_CALL",
  "FLAG_ENABLE_RIVAL_MATCH_CALL", "FLAG_ENABLE_ROXANNE_MATCH_CALL", "FLAG_ENABLE_SCOTT_MATCH_CALL", "FLAG_HAS_MATCH_CALL",
  "FLAG_HIDE_GRANITE_CAVE_STEVEN", "FLAG_HIDE_MAUVILLE_CITY_WALLY", "FLAG_HIDE_MAUVILLE_CITY_WALLYS_UNCLE",
  "FLAG_HIDE_PETALBURG_CITY_WALLYS_MOM", "FLAG_HIDE_PETALBURG_WOODS_AQUA_GRUNT", "FLAG_HIDE_PETALBURG_WOODS_DEVON_EMPLOYEE",
  "FLAG_HIDE_ROUTE_103_RIVAL", "FLAG_HIDE_ROUTE_104_MR_BRINEY_BOAT", "FLAG_HIDE_ROUTE_110_RIVAL", "FLAG_HIDE_ROUTE_110_TEAM_AQUA",
  "FLAG_HIDE_ROUTE_116_WANDAS_BOYFRIEND", "FLAG_HIDE_RUSTBORO_CITY_DEVON_CORP_3F_EMPLOYEE",
  "FLAG_HIDE_RUSTBORO_CITY_POKEMON_SCHOOL_SCOTT", "FLAG_HIDE_SLATEPORT_CITY_OCEANIC_MUSEUM_2F_CAPTAIN_STERN",
  "FLAG_HIDE_SLATEPORT_CITY_OCEANIC_MUSEUM_AQUA_GRUNTS", "FLAG_HIDE_SLATEPORT_CITY_TEAM_AQUA",
  "FLAG_INTERACTED_WITH_DEVON_EMPLOYEE_GOODS_STOLEN", "FLAG_LANDMARK_MR_BRINEY_HOUSE", "FLAG_MET_RIVAL_RUSTBORO",
  "FLAG_MR_BRINEY_SAILING_INTRO", "FLAG_POKERUS_EXPLAINED", "FLAG_RECEIVED_POKEDEX_FROM_BIRCH", "FLAG_RECEIVED_POKENAV",
  "FLAG_RECEIVED_POTION_OLDALE", "FLAG_RECEIVED_RUNNING_SHOES", "FLAG_RECEIVED_TM_BULK_UP", "FLAG_RECEIVED_TM_ROCK_TOMB",
  "FLAG_RECOVERED_DEVON_GOODS", "FLAG_REGISTERED_BRAWLY", "FLAG_REGISTERED_HALEY", "FLAG_REGISTERED_ISABEL",
  "FLAG_REGISTERED_RICKY", "FLAG_REGISTERED_STEVEN_POKENAV", "FLAG_RETURNED_DEVON_GOODS", "FLAG_SYS_B_DASH",
  "FLAG_SYS_POKEDEX_GET", "FLAG_SYS_POKENAV_GET", "FLAG_SYS_TV_START", "FLAG_VISITED_DEWFORD_TOWN",
  "FLAG_VISITED_MAUVILLE_CITY", "FLAG_VISITED_OLDALE_TOWN", "FLAG_VISITED_PETALBURG_CITY", "FLAG_VISITED_RUSTBORO_CITY",
  "FLAG_VISITED_SLATEPORT_CITY",
  "FLAG_DEFEATED_MAUVILLE_GYM", "FLAG_BADGE03_GET", "FLAG_RECEIVED_TM_SHOCK_WAVE", "FLAG_ENABLE_WATTSON_MATCH_CALL",
}
local SEG1_CLEAR = {
  "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH", "FLAG_HIDE_LITTLEROOT_TOWN_FAT_MAN", "FLAG_HIDE_ROUTE_101_BOY",
  "FLAG_HIDE_ROUTE_109_MR_BRINEY", "FLAG_HIDE_ROUTE_109_MR_BRINEY_BOAT", "FLAG_HIDE_ROUTE_116_DEVON_EMPLOYEE",
  "FLAG_HIDE_RUSTURF_TUNNEL_WANDA", "FLAG_HIDE_RUSTURF_TUNNEL_WANDAS_BOYFRIEND", "FLAG_HIDE_SLATEPORT_MUSEUM_POPULATION",
  "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WALLY", "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WALLYS_UNCLE",
  "FLAG_HIDE_VERDANTURF_TOWN_SCOTT",
}
local SEG1_VARS = {
  VAR_BIRCH_LAB_STATE = 5, VAR_BOARD_BRINEY_BOAT_STATE = 0, VAR_BRINEY_HOUSE_STATE = 1, VAR_BRINEY_LOCATION = 3,
  VAR_CABLE_CLUB_TUTORIAL_STATE = 1, VAR_DEVON_CORP_3F_STATE = 1, VAR_LITTLEROOT_INTRO_STATE = 7,
  VAR_LITTLEROOT_HOUSES_STATE_BRENDAN = 2, VAR_LITTLEROOT_RIVAL_STATE = 4, VAR_LITTLEROOT_TOWN_STATE = 4,
  VAR_OLDALE_RIVAL_STATE = 2, VAR_OLDALE_TOWN_STATE = 1, VAR_PETALBURG_CITY_STATE = 3, VAR_PETALBURG_GYM_STATE = 5,
  VAR_PETALBURG_WOODS_STATE = 1, VAR_REGISTER_BIRCH_STATE = 2, VAR_ROUTE101_STATE = 3, VAR_ROUTE104_STATE = 2,
  VAR_ROUTE110_STATE = 1, VAR_ROUTE116_STATE = 2, VAR_RUSTBORO_CITY_STATE = 8, VAR_RUSTURF_TUNNEL_STATE = 3,
  VAR_SCOTT_PETALBURG_ENCOUNTER = 1, VAR_SCOTT_STATE = 3, VAR_SLATEPORT_OUTSIDE_MUSEUM_STATE = 3, VAR_STARTER_MON = 1,
}
local SEG1_TRAINERS = {
  "TRAINER_ALLEN", "TRAINER_ALYSSA", "TRAINER_BRAWLY_1", "TRAINER_BRENDEN", "TRAINER_CALVIN_1", "TRAINER_CINDY_1",
  "TRAINER_CRISTIAN", "TRAINER_DEVAN", "TRAINER_EDMOND", "TRAINER_EDWARD", "TRAINER_GRUNT_MUSEUM_1", "TRAINER_GRUNT_MUSEUM_2",
  "TRAINER_GRUNT_PETALBURG_WOODS", "TRAINER_GRUNT_RUSTURF_TUNNEL", "TRAINER_HAILEY", "TRAINER_HALEY_1", "TRAINER_ISABEL_1",
  "TRAINER_JAMES_1", "TRAINER_JOCELYN", "TRAINER_JOHNSON", "TRAINER_JOSH", "TRAINER_KALEB", "TRAINER_KAREN_1",
  "TRAINER_LAURA", "TRAINER_LILITH", "TRAINER_MARC", "TRAINER_MAY_ROUTE_103_TORCHIC", "TRAINER_MAY_ROUTE_110_TORCHIC",
  "TRAINER_MAY_RUSTBORO_TORCHIC", "TRAINER_RICK", "TRAINER_RICKY_1", "TRAINER_ROXANNE_1", "TRAINER_TAKAO", "TRAINER_TIANA",
  "TRAINER_TOMMY", "TRAINER_WALLY_MAUVILLE", "TRAINER_WATTSON_1", "TRAINER_KIRK", "TRAINER_SHAWN", "TRAINER_BEN",
  "TRAINER_VIVIAN", "TRAINER_ANGELO",
}

local function lead() return S.session().party[1] end

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
    local M = require("src.ui.game3.message")
    if not taken and M.isOpen() and (not pred or pred()) then
      taken = true
      U.wait(2)
      if M.isOpen() and M.isTyping() then M.skipReveal() end
      U.wait(3)
      d.shot(game, file)
    end
    return false
  end
end

local function setTrainerFlag(name)
  local F = require("src.core.game3.scripting.flags")
  local EM = F.forVersion("emerald")
  F.setFlag(require("src.core.game3.scripting.space").store, nil, (EM.IDS.TRAINER_FLAGS_START or 0x500)
    + S.C():require("trainers", name), true)
end

local function fightTrainer(game, label, name, shot, talkOpts, trainer)
  local eo = S.objectByScript(label)
  if not d.check(eo ~= nil, name .. " is on the map") then return false end
  if trainer and S.trainerBeaten(trainer) then
    return d.check(true, name .. " already beaten on the way (" .. trainer .. ")")
  end
  local tid = trainer and S.C():require("trainers", trainer)
  local mine
  S.pendingBattleShot = shot
  for _ = 1, 4 do
    local before = #S.battles
    S.talkTo(game, eo, talkOpts)
    S.settle(game, { limit = 20000, onBattleFrame = shot and battleShot(game, shot) or nil })
    for i = before + 1, #S.battles do
      if not tid or S.battles[i].trainer == tid then mine = S.battles[i] end
    end
    if mine or not tid or S.trainerBeaten(trainer) then break end
  end
  S.pendingBattleShot = nil
  return d.check(mine ~= nil and mine.result == "win", name .. " battle won (" .. tostring(mine and mine.result) .. ")")
end

local function lastBattleWon(tid)
  for i = #S.battles, 1, -1 do
    local b = S.battles[i]
    if not tid or b.trainer == tid then return b.result == "win", b end
  end
  return false
end

local function teachHm(item, slot)
  local ItemUse = require("src.core.game3.item_use")
  local s = S.session()
  local ok, kind, msg = ItemUse.useTm(s, s.bag, S.item(item), slot or 1)
  return ok, kind
end

local function knows(mon, move)
  for _, m in ipairs(mon.moves or {}) do if m == S.move(move) then return true end end
  return false
end

local function smashRocks(game, cells, watch)
  local Objects = require("src.core.game3.objects")
  local n = 0
  for _, c in ipairs(cells) do
    local eo = Objects.at(c[1], c[2])
    if eo and S.path(game, function(x, y) return math.abs(x - c[1]) + math.abs(y - c[2]) == 1 end) then
      S.talkTo(game, eo)
      S.settle(game, { limit = 3000, watch = watch })
      if not Objects.at(c[1], c[2]) then n = n + 1 end
    end
  end
  return n
end

local function warpCells(game, mapId)
  local out = {}
  local def = game.data.maps[mapId]
  for _, w in ipairs(def and def.warps or {}) do out[#out + 1] = { tonumber(w.x), tonumber(w.y) } end
  return out
end

local function warpRoute(game, legs, opts)
  opts = opts or {}
  for i, leg in ipairs(legs) do
    local mapId, tx, ty = leg[1], leg[2], leg[3]
    for _ = 1, 6 do
      if S.mapNow() ~= mapId then break end
      local avoid = {}
      for _, c in ipairs(warpCells(game, mapId)) do
        if not (c[1] == tx and c[2] == ty) then avoid[c[1] .. "," .. c[2]] = true end
      end
      S.goTo(game, { tx, ty }, { avoid = avoid, goalBlocked = true, tries = 12, settle = opts.settle or { limit = 20000 } })
      S.settle(game, opts.settle or { limit = 20000 })
    end
    if S.mapNow() == mapId then
      d.note(string.format("warp route leg %d stuck on %s at %d,%d (target %d,%d)", i, mapId,
        require("src.core.game3.player").cellX, require("src.core.game3.player").cellY, tx, ty))
      return false
    end
  end
  return true
end

local BEATS = {}

BEATS[#BEATS + 1] = { id = "start", run = function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "QUINCY", gender = 0, start = {
    map = "EM_MAUVILLE_CITY", x = 8, y = 7, facing = "down", healMap = "EM_MAUVILLE_CITY", healX = 22, healY = 6,
  } })
  U.wait(30)
  for _, f in ipairs(SEG1_SET) do S.setFlag(f, true) end
  for _, f in ipairs(SEG1_CLEAR) do S.setFlag(f, false) end
  for k, v in pairs(SEG1_VARS) do S.setVar(k, v) end
  for _, t in ipairs(SEG1_TRAINERS) do setTrainerFlag(t) end
  local s = S.session()
  s.party = {}
  local bl = S.giveMon("SPECIES_TORCHIC", 10)
  S.setLevel(bl, 50, "SPECIES_BLAZIKEN")
  S.setMoves(bl, { "MOVE_SLASH", "MOVE_DOUBLE_KICK", "MOVE_EMBER" })
  local mr = S.giveMon("SPECIES_MARILL", 10)
  S.setLevel(mr, 45, "SPECIES_AZUMARILL")
  S.setMoves(mr, { "MOVE_BUBBLE_BEAM", "MOVE_ROLLOUT", "MOVE_DEFENSE_CURL" })
  for _, it in ipairs({ "ITEM_TM39", "ITEM_TM08", "ITEM_TM47", "ITEM_TM34", "ITEM_POTION", "ITEM_GREAT_BALL" }) do
    S.giveItem(it, 1)
  end
  S.giveItem("ITEM_POKE_BALL", 5)
  s.money = 20000
  d.check(#s.party == 2 and s.party[1].species == S.species("SPECIES_BLAZIKEN"),
    "segment start: Blaziken lv50 + Azumarill lv45 after the Dynamo Badge")
  S.saveCheckpoint(game, "start")
  S.loadCheckpoint(game, "start")
  return d.check(S.mapNow() == "EM_MAUVILLE_CITY" and S.flag("FLAG_BADGE03_GET") and S.var("VAR_PETALBURG_GYM_STATE") == 5,
    "segment start: Mauville City with 3 badges (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/MauvilleCity_House1/scripts.inc:4
BEATS[#BEATS + 1] = { id = "rock_smash", run = function(game)
  S.travel(game, { "EM_MAUVILLE_CITY_HOUSE1" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_MAUVILLE_CITY_HOUSE1", "Mauville -> the Rock Smash Dude's house") then return false end
  local dude = S.objectByScript("MauvilleCity_House1_EventScript_RockSmashDude")
  S.talkTo(game, dude)
  S.settle(game, { limit = 8000, watch = shotOnMessage(game, "01_rock_smash_dude"),
    until_ = function() return S.flag("FLAG_RECEIVED_HM_ROCK_SMASH") and not S.busy() end })
  d.check(S.hasItem("ITEM_HM06") and S.flag("FLAG_HIDE_ROUTE_111_ROCK_SMASH_TIP_GUY"), "the Rock Smash Dude gives HM06 ROCK SMASH")
  teachHm("ITEM_HM06", 1)
  return d.check(knows(lead(), "MOVE_ROCK_SMASH"), "Blaziken learns ROCK SMASH from HM06")
end }

-- pokeemerald/data/maps/Route112/scripts.inc:10
BEATS[#BEATS + 1] = { id = "route111", run = function(game)
  S.travel(game, { "EM_MAUVILLE_CITY", "EM_ROUTE111" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_ROUTE111", "Mauville -> Route 111") then return false end
  local smashed = smashRocks(game, { { 18, 101 }, { 19, 100 } })
  d.shot(game, "02_route111_rocks")
  d.check(smashed >= 1, "ROCK SMASH clears the Route 111 rocks (" .. smashed .. ")")
  S.travel(game, { "EM_ROUTE112" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_ROUTE112", "Route 111 -> Route 112 (the sandstorm is left alone)") then return false end
  local g = S.objectByScript("Route112_EventScript_MagmaGrunts")
  d.check(g ~= nil and not S.flag("FLAG_HIDE_ROUTE_112_TEAM_MAGMA"), "Team Magma blocks the cable car station")
  if g then
    S.talkTo(game, g)
    S.settle(game, { limit = 6000, watch = shotOnMessage(game, "03_route112_magma") })
  end
  S.travel(game, { "EM_FIERY_PATH", { "EM_ROUTE112", arrive = { 22, 10 } }, "EM_ROUTE111", "EM_ROUTE113", "EM_FALLARBOR_TOWN" },
    { settle = { limit = 8000 } })
  d.shot(game, "04_fallarbor")
  return d.check(S.mapNow() == "EM_FALLARBOR_TOWN", "Fiery Path -> Route 112 north -> Route 111 north -> Route 113 ash -> Fallarbor ("
    .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/MeteorFalls_1F_1R/scripts.inc:15
BEATS[#BEATS + 1] = { id = "meteor_falls", run = function(game)
  S.travel(game, { "EM_ROUTE114", "EM_METEOR_FALLS_1F_1R" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_METEOR_FALLS_1F_1R", "Fallarbor -> Route 114 -> Meteor Falls") then return false end
  S.goTo(game, { 14, 18 }, { settle = { limit = 20000 } })
  S.settle(game, { limit = 30000, watch = shotOnMessage(game, "05_meteor_falls_archie", function()
      return require("src.core.game3.objects").find(5) ~= nil end),
    until_ = function() return S.var("VAR_METEOR_FALLS_STATE") == 1 and not S.busy() end })
  d.check(S.flag("FLAG_MET_ARCHIE_METEOR_FALLS"), "Magma steals the meteorite, Archie arrives (FLAG_MET_ARCHIE_METEOR_FALLS)")
  return d.check(S.flag("FLAG_HIDE_ROUTE_112_TEAM_MAGMA") and S.var("VAR_METEOR_FALLS_STATE") == 1,
    "the Route 112 Magma line leaves (FLAG_HIDE_ROUTE_112_TEAM_MAGMA)")
end }

-- pokeemerald/data/maps/Route112_CableCarStation/scripts.inc:31
BEATS[#BEATS + 1] = { id = "cable_car", run = function(game)
  S.travel(game, { "EM_ROUTE114", "EM_FALLARBOR_TOWN", "EM_ROUTE113", "EM_ROUTE111", "EM_ROUTE112", "EM_FIERY_PATH",
    { "EM_ROUTE112", arrive = { 11, 36 } }, "EM_ROUTE112_CABLE_CAR_STATION" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_ROUTE112_CABLE_CAR_STATION", "back through Fiery Path to the Route 112 cable car station ("
      .. tostring(S.mapNow()) .. ")") then return false end
  local att = S.objectByScript("Route112_CableCarStation_EventScript_Attendant")
  if not d.check(att ~= nil, "the cable car attendant is at the gate") then return false end
  S.talkTo(game, att)
  local Core = require("src.core.game3.rse.cable_car")
  local rideShot = false
  S.settle(game, { limit = 40000, watch = function()
      local sc = Core.last and Core.last.screen
      if not rideShot and sc and (sc.frames or 0) >= 200 then rideShot = true d.shot(game, "06_cable_car_ride") end
    end,
    until_ = function() return S.mapNow() == "EM_MT_CHIMNEY_CABLE_CAR_STATION" and S.var("VAR_CABLE_CAR_STATION_STATE") == 0
      and not S.busy() end })
  d.check(rideShot, "the cable car scene rides up the mountain")
  return d.check(S.mapNow() == "EM_MT_CHIMNEY_CABLE_CAR_STATION" and S.var("VAR_CABLE_CAR_STATION_STATE") == 0,
    "arrive at the Mt. Chimney station and step off the car (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/MtChimney/scripts.inc:32
BEATS[#BEATS + 1] = { id = "mt_chimney", run = function(game)
  S.travel(game, { "EM_MT_CHIMNEY" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_MT_CHIMNEY", "out onto the summit of Mt. Chimney") then return false end
  local archie = S.objectByScript("MtChimney_EventScript_Archie")
  if archie then
    S.talkTo(game, archie)
    S.settle(game, { limit = 6000, watch = shotOnMessage(game, "07_mt_chimney_archie") })
  end
  d.check(S.flag("FLAG_EVIL_LEADER_PLEASE_STOP"), "Archie asks the player to stop Team Magma")
  fightTrainer(game, "MtChimney_EventScript_Grunt1", "Magma Grunt (Mt. Chimney 1)", nil, nil, "TRAINER_GRUNT_MT_CHIMNEY_1")
  fightTrainer(game, "MtChimney_EventScript_Tabitha", "Magma Admin Tabitha", "08_tabitha", nil, "TRAINER_TABITHA_MT_CHIMNEY")
  local maxie = S.objectByScript("MtChimney_EventScript_Maxie")
  if not d.check(maxie ~= nil, "Maxie stands at the meteorite machine") then return false end
  S.talkTo(game, maxie)
  S.settle(game, { limit = 40000, onBattleFrame = battleShot(game, "09_maxie"),
    until_ = function() return S.flag("FLAG_DEFEATED_EVIL_TEAM_MT_CHIMNEY") and not S.busy() end })
  d.check(lastBattleWon(S.C():require("trainers", "TRAINER_MAXIE_MT_CHIMNEY")), "Maxie battle won through the battle UI")
  d.check(S.flag("FLAG_DEFEATED_EVIL_TEAM_MT_CHIMNEY") and S.flag("FLAG_HIDE_MT_CHIMNEY_TEAM_MAGMA"),
    "Magma withdraws, Archie thanks the player (FLAG_DEFEATED_EVIL_TEAM_MT_CHIMNEY)")
  d.shot(game, "10_after_maxie")
  S.talkAt(game, 14, 6)
  S.settle(game, { limit = 8000, until_ = function() return S.flag("FLAG_RECEIVED_METEORITE") and not S.busy() end })
  return d.check(S.hasItem("ITEM_METEORITE") and S.flag("FLAG_RECEIVED_METEORITE"), "the METEORITE is removed from the machine")
end }

-- pokeemerald/data/maps/JaggedPass/scripts.inc:1
BEATS[#BEATS + 1] = { id = "jagged_pass", run = function(game)
  S.travel(game, { "EM_JAGGED_PASS" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_JAGGED_PASS", "Mt. Chimney -> Jagged Pass (top)") then return false end
  S.settle(game, { limit = 600 })
  d.shot(game, "11_jagged_pass")
  S.travel(game, { "EM_ROUTE112", "EM_LAVARIDGE_TOWN" }, { settle = { limit = 8000 } })
  return d.check(S.mapNow() == "EM_LAVARIDGE_TOWN", "down the Jagged Pass ledges on foot -> Route 112 -> Lavaridge ("
    .. tostring(S.mapNow()) .. ")")
end }

local LAVARIDGE_GYM_ROUTE = {
  { "EM_LAVARIDGE_TOWN_GYM_1F", 8, 9 }, { "EM_LAVARIDGE_TOWN_GYM_B1F", 1, 14 }, { "EM_LAVARIDGE_TOWN_GYM_1F", 0, 10 },
  { "EM_LAVARIDGE_TOWN_GYM_B1F", 0, 6 }, { "EM_LAVARIDGE_TOWN_GYM_1F", 2, 3 }, { "EM_LAVARIDGE_TOWN_GYM_B1F", 7, 2 },
  { "EM_LAVARIDGE_TOWN_GYM_1F", 10, 6 }, { "EM_LAVARIDGE_TOWN_GYM_B1F", 12, 12 },
}

-- pokeemerald/data/maps/LavaridgeTown_Gym_1F/scripts.inc:59
BEATS[#BEATS + 1] = { id = "flannery", run = function(game)
  if S.needsHeal() then S.healAtCenter(game, "EM_LAVARIDGE_TOWN", "LavaridgeTown") end
  S.travel(game, { "EM_LAVARIDGE_TOWN_GYM_1F" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_LAVARIDGE_TOWN_GYM_1F", "into the Lavaridge Gym") then return false end
  S.settle(game, { limit = 600 })
  d.shot(game, "12_lavaridge_gym")
  local maps = {}
  local watch = function() maps[S.mapNow()] = true end
  local ok = warpRoute(game, LAVARIDGE_GYM_ROUTE, { settle = { limit = 20000, watch = watch } })
  d.check(ok and S.mapNow() == "EM_LAVARIDGE_TOWN_GYM_1F", "floor holes drop to B1F and the steam vents launch back up to Flannery's ledge")
  local n = 0
  for i = 1, #S.battles do if S.battles[i].map and S.battles[i].map:find("LAVARIDGE_TOWN_GYM", 1, true) then n = n + 1 end end
  d.check(n >= 1, "buried gym trainers pop out of the sand and battle (" .. n .. ")")
  local fl = S.objectByScript("LavaridgeTown_Gym_1F_EventScript_Flannery")
  if not d.check(fl ~= nil, "Leader Flannery is on the map") then return false end
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Flannery (driver)") end
  S.talkTo(game, fl)
  S.settle(game, { limit = 40000, onBattleFrame = battleShot(game, "13_flannery"),
    until_ = function() return S.flag("FLAG_ENABLE_FLANNERY_MATCH_CALL") and not S.busy() end })
  d.check(lastBattleWon(S.C():require("trainers", "TRAINER_FLANNERY_1")), "Leader Flannery battle won")
  d.shot(game, "14_heat_badge")
  d.check(S.hasItem("ITEM_TM50"), "Flannery gives TM50 OVERHEAT")
  return d.check(S.flag("FLAG_BADGE04_GET") and S.var("VAR_PETALBURG_GYM_STATE") == 6,
    "HEAT BADGE (FLAG_BADGE04_GET), Norman's gym is ready (VAR_PETALBURG_GYM_STATE=" .. S.var("VAR_PETALBURG_GYM_STATE") .. ")")
end }

-- pokeemerald/data/maps/LavaridgeTown/scripts.inc:45
BEATS[#BEATS + 1] = { id = "go_goggles", run = function(game)
  S.travel(game, { "EM_LAVARIDGE_TOWN" }, { settle = { limit = 20000, watch = shotOnMessage(game, "15_may_go_goggles",
    function() return S.mapNow() == "EM_LAVARIDGE_TOWN" end) } })
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "15_may_go_goggles"),
    until_ = function() return S.flag("FLAG_RECEIVED_GO_GOGGLES") and not S.busy() end })
  return d.check(S.hasItem("ITEM_GO_GOGGLES") and S.var("VAR_LAVARIDGE_TOWN_STATE") == 2,
    "May waits outside the gym and gives the GO-GOGGLES (VAR_LAVARIDGE_TOWN_STATE=" .. S.var("VAR_LAVARIDGE_TOWN_STATE") .. ")")
end }

-- pokeemerald/data/maps/RusturfTunnel/scripts.inc:1
BEATS[#BEATS + 1] = { id = "to_petalburg", run = function(game)
  S.travel(game, { "EM_ROUTE112", "EM_ROUTE111" }, { settle = { limit = 8000 } })
  smashRocks(game, { { 19, 100 }, { 18, 101 } })
  S.travel(game, { "EM_MAUVILLE_CITY" }, { settle = { limit = 8000 } })
  if S.needsHeal() then d.check(S.healAtCenter(game, "EM_MAUVILLE_CITY", "MauvilleCity"), "the Mauville nurse heals the party") end
  S.travel(game, { "EM_ROUTE117", "EM_VERDANTURF_TOWN", "EM_RUSTURF_TUNNEL" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_RUSTURF_TUNNEL", "Lavaridge -> Route 112 -> Route 111 -> Mauville -> Route 117 -> Verdanturf -> Rusturf Tunnel ("
      .. tostring(S.mapNow()) .. ")") then return false end
  local reunion = shotOnMessage(game, "16_rusturf_reunion", function() return S.var("VAR_RUSTURF_TUNNEL_STATE") >= 4 end)
  local smashed = smashRocks(game, { { 24, 5 }, { 24, 4 } }, reunion)
  S.settle(game, { limit = 8000, watch = reunion })
  d.check(smashed >= 1, "ROCK SMASH breaks the tunnel blockage (" .. smashed .. ")")
  S.settle(game, { limit = 20000, watch = reunion,
    until_ = function() return S.var("VAR_RUSTURF_TUNNEL_STATE") >= 6 and not S.busy() end })
  d.check(S.var("VAR_RUSTURF_TUNNEL_STATE") >= 4, "Wanda and her boyfriend are reunited (VAR_RUSTURF_TUNNEL_STATE="
    .. S.var("VAR_RUSTURF_TUNNEL_STATE") .. ")")
  S.travel(game, { "EM_ROUTE116", "EM_RUSTBORO_CITY", "EM_ROUTE104", "EM_PETALBURG_WOODS", { "EM_ROUTE104", arrive = { 10, 38 } },
    "EM_PETALBURG_CITY" }, { settle = { limit = 8000 } })
  d.shot(game, "17_back_in_petalburg")
  return d.check(S.mapNow() == "EM_PETALBURG_CITY", "Rusturf Tunnel -> Rustboro -> Petalburg Woods -> Petalburg City ("
    .. tostring(S.mapNow()) .. ")")
end }

local PETALBURG_GYM_TRAINERS = {
  { "PetalburgCity_Gym_EventScript_Randall", "Cooltrainer Randall", "TRAINER_RANDALL" },
  { "PetalburgCity_Gym_EventScript_Mary", "Cooltrainer Mary", "TRAINER_MARY" },
  { "PetalburgCity_Gym_EventScript_George", "Cooltrainer George", "TRAINER_GEORGE" },
  { "PetalburgCity_Gym_EventScript_Alexia", "Cooltrainer Alexia", "TRAINER_ALEXIA" },
  { "PetalburgCity_Gym_EventScript_Parker", "Cooltrainer Parker", "TRAINER_PARKER" },
  { "PetalburgCity_Gym_EventScript_Berke", "Cooltrainer Berke", "TRAINER_BERKE" },
  { "PetalburgCity_Gym_EventScript_Jody", "Cooltrainer Jody", "TRAINER_JODY" },
}

local function adjacentPath(game, eo, opts)
  return eo and S.path(game, function(x, y) return math.abs(x - eo.cellX) + math.abs(y - eo.cellY) == 1 end, opts)
end

-- pokeemerald/data/maps/PetalburgCity_Gym/map.json:433
local PETALBURG_GYM_DOORS = {
  { 1, 105 }, { 7, 105 }, { 1, 92 }, { 7, 92 }, { 1, 79 }, { 7, 79 }, { 1, 66 }, { 1, 53 }, { 7, 53 }, { 7, 40 },
  { 1, 27 }, { 7, 14 },
}

-- pokeemerald/data/maps/PetalburgCity_Gym/scripts.inc:101
BEATS[#BEATS + 1] = { id = "norman", run = function(game)
  if S.needsHeal() then S.healAtCenter(game, "EM_PETALBURG_CITY", "PetalburgCity") end
  S.travel(game, { "EM_PETALBURG_CITY_GYM" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_PETALBURG_CITY_GYM", "into Norman's gym with four badges") then return false end
  S.settle(game, { limit = 600 })
  local P = require("src.core.game3.player")
  local rooms, fought = {}, 0
  local norman
  for _ = 1, 16 do
    rooms[#rooms + 1] = P.cellY
    local avoid = {}
    for _, c in ipairs(warpCells(game, S.mapNow())) do avoid[c[1] .. "," .. c[2]] = true end
    norman = S.objectByScript("PetalburgCity_Gym_EventScript_Norman")
    if norman and adjacentPath(game, norman, { avoid = avoid }) then break end
    for _, t in ipairs(PETALBURG_GYM_TRAINERS) do
      local eo = S.objectByScript(t[1])
      if eo and not S.trainerBeaten(t[3]) and adjacentPath(game, eo, { avoid = avoid }) then
        if fought == 0 then d.shot(game, "18_petalburg_gym_room") end
        fightTrainer(game, t[1], t[2], nil, { avoid = avoid }, t[3])
        fought = fought + 1
        S.settle(game, { limit = 6000 })
      end
    end
    local best
    for _, c in ipairs(PETALBURG_GYM_DOORS) do
      if c[2] < P.cellY and adjacentPath(game, { cellX = c[1], cellY = c[2] }, { avoid = avoid })
          and (not best or c[2] > best[2]) then
        best = c
      end
    end
    if not best then d.note("no forward door from " .. P.cellX .. "," .. P.cellY) break end
    local y0 = P.cellY
    S.talkAt(game, best[1], best[2], { avoid = avoid, settle = { limit = 20000 } })
    S.settle(game, { limit = 6000 })
    if P.cellY >= y0 then d.note("door at " .. best[1] .. "," .. best[2] .. " did not move the player up") end
  end
  d.check(fought >= 3, "the gym's room trainers beaten on the way up (" .. fought .. ")")
  if not d.check(norman ~= nil and adjacentPath(game, norman), "each beaten trainer slides the next doors open up to Norman (rooms "
      .. table.concat(rooms, ",") .. ")") then return false end
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Norman (driver)") end
  S.talkTo(game, norman)
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "19_norman"),
    watch = shotOnMessage(game, "20_wallys_dad", function() return S.flag("FLAG_BADGE05_GET") end),
    until_ = function() return S.flag("FLAG_RECEIVED_HM_SURF") and not S.busy() end })
  d.check(lastBattleWon(S.C():require("trainers", "TRAINER_NORMAN_1")), "Leader Norman battle won")
  d.check(S.flag("FLAG_BADGE05_GET") and S.hasItem("ITEM_TM42"), "BALANCE BADGE (FLAG_BADGE05_GET) and TM42 FACADE")
  d.shot(game, "21_hm_surf")
  return d.check(S.mapNow() == "EM_PETALBURG_CITY_WALLYS_HOUSE" and S.hasItem("ITEM_HM03") and S.var("VAR_PETALBURG_CITY_STATE") == 5,
    "Wally's father walks the player home and gives HM03 SURF (" .. tostring(S.mapNow()) .. ")")
end }

local function hasSpecies(name)
  for _, m in ipairs(S.session().party or {}) do
    if m.species == S.species(name) then return true end
  end
  return false
end

-- pokeemerald/data/maps/PetalburgCity_WallysHouse/scripts.inc:18
BEATS[#BEATS + 1] = { id = "surf", run = function(game)
  teachHm("ITEM_HM03", 2)
  d.check(knows(S.session().party[2], "MOVE_SURF"), "Azumarill learns SURF from HM03")
  S.travel(game, { "EM_PETALBURG_CITY", "EM_ROUTE104", "EM_PETALBURG_WOODS", { "EM_ROUTE104", arrive = { 10, 30 } },
    "EM_RUSTBORO_CITY", "EM_ROUTE116", "EM_RUSTURF_TUNNEL", "EM_VERDANTURF_TOWN", "EM_ROUTE117", "EM_MAUVILLE_CITY" },
    { settle = { limit = 8000 } })
  return d.check(S.mapNow() == "EM_MAUVILLE_CITY", "Petalburg -> Petalburg Woods -> Rustboro -> Rusturf Tunnel -> Verdanturf -> Mauville ("
    .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/Route118/scripts.inc:85
BEATS[#BEATS + 1] = { id = "route118", run = function(game)
  if S.needsHeal() then d.check(S.healAtCenter(game, "EM_MAUVILLE_CITY", "MauvilleCity"), "the Mauville nurse heals the party") end
  S.canSurf = true
  S.travel(game, { "EM_ROUTE118" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_ROUTE118", "Mauville -> Route 118") then return false end
  local surfed = false
  S.onSurf = function()
    if not surfed then surfed = true U.wait(10) d.shot(game, "22_route118_surf") end
  end
  S.goTo(game, function(x, y) return y == 11 and x >= 43 and x <= 45 end, { tries = 40, settle = { limit = 20000 } })
  S.onSurf = nil
  d.check(surfed, "SURF across the Route 118 channel")
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "23_route118_steven"),
    until_ = function() return S.var("VAR_ROUTE118_STATE") == 1 and not S.busy() end })
  return d.check(S.var("VAR_ROUTE118_STATE") == 1, "Steven jumps down the ledge and talks on Route 118 (VAR_ROUTE118_STATE="
    .. S.var("VAR_ROUTE118_STATE") .. ")")
end }

-- pokeemerald/data/maps/Route119_WeatherInstitute_2F/scripts.inc:39
BEATS[#BEATS + 1] = { id = "weather_institute", run = function(game)
  S.travel(game, { "EM_ROUTE119", "EM_ROUTE119_WEATHER_INSTITUTE_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE119_WEATHER_INSTITUTE_1F", "Route 118 -> Route 119 -> Weather Institute ("
      .. tostring(S.mapNow()) .. ")") then return false end
  d.check(not S.flag("FLAG_HIDE_ROUTE_119_TEAM_AQUA"), "Team Aqua occupies the Weather Institute")
  d.shot(game, "24_weather_institute")
  fightTrainer(game, "Route119_WeatherInstitute_1F_EventScript_Grunt1", "Aqua Grunt (Institute 1F)", nil, nil,
    "TRAINER_GRUNT_WEATHER_INST_1")
  S.travel(game, { "EM_ROUTE119_WEATHER_INSTITUTE_2F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE119_WEATHER_INSTITUTE_2F", "up to the Institute 2F") then return false end
  fightTrainer(game, "Route119_WeatherInstitute_2F_EventScript_Grunt2", "Aqua Grunt (Institute 2F)", nil, nil,
    "TRAINER_GRUNT_WEATHER_INST_2")
  fightTrainer(game, "Route119_WeatherInstitute_2F_EventScript_Grunt3", "Aqua Grunt (Institute 2F, 2)", nil, nil,
    "TRAINER_GRUNT_WEATHER_INST_3")
  local shelly = S.objectByScript("Route119_WeatherInstitute_2F_EventScript_Shelly")
  if not d.check(shelly ~= nil, "Aqua Admin Shelly holds the scientist") then return false end
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Shelly (driver)") end
  S.talkTo(game, shelly)
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "25_shelly"),
    choice = function() return hasSpecies("SPECIES_CASTFORM") and "no" or "yes" end,
    watch = shotOnMessage(game, "26_castform", function() return hasSpecies("SPECIES_CASTFORM") end),
    until_ = function() return S.flag("FLAG_RECEIVED_CASTFORM") and not S.busy() end })
  d.check(lastBattleWon(S.C():require("trainers", "TRAINER_SHELLY_WEATHER_INSTITUTE")), "Shelly battle won")
  d.check(S.flag("FLAG_HIDE_ROUTE_119_TEAM_AQUA") and S.var("VAR_WEATHER_INSTITUTE_STATE") >= 1,
    "Team Aqua leaves for Mt. Pyre (FLAG_HIDE_ROUTE_119_TEAM_AQUA)")
  return d.check(hasSpecies("SPECIES_CASTFORM") and S.flag("FLAG_RECEIVED_CASTFORM"), "the scientist gives CASTFORM")
end }

-- pokeemerald/data/maps/Route119/scripts.inc:39
BEATS[#BEATS + 1] = { id = "may_route119", run = function(game)
  S.travel(game, { "EM_ROUTE119_WEATHER_INSTITUTE_1F", "EM_ROUTE119" }, { settle = { limit = 20000 } })
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before May (driver)") end
  S.goTo(game, function(x, y) return y == 31 and (x == 25 or x == 26) end, { tries = 40, settle = { limit = 30000,
    onBattleFrame = battleShot(game, "27_route119_may") } })
  S.settle(game, { limit = 30000, onBattleFrame = battleShot(game, "27_route119_may"),
    until_ = function() return S.var("VAR_ROUTE119_STATE") == 1 and not S.busy() end })
  d.check(lastBattleWon(S.C():require("trainers", "TRAINER_MAY_ROUTE_119_TORCHIC")), "Route 119 May battle won")
  d.shot(game, "28_hm_fly")
  return d.check(S.hasItem("ITEM_HM02") and S.flag("FLAG_RECEIVED_HM_FLY") and S.var("VAR_ROUTE119_STATE") == 1,
    "May gives HM02 FLY, Scott passes by (VAR_ROUTE119_STATE=1)")
end }

-- pokeemerald/data/maps/Route120/scripts.inc:154
BEATS[#BEATS + 1] = { id = "devon_scope", run = function(game)
  S.travel(game, { "EM_FORTREE_CITY" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_FORTREE_CITY", "Route 119 -> Fortree City") then return false end
  local kec = S.objectByScript("FortreeCity_EventScript_Kecleon")
  if not d.check(kec ~= nil and not S.flag("FLAG_KECLEON_FLED_FORTREE"), "something unseeable blocks the Fortree Gym door") then
    return false
  end
  S.talkTo(game, kec)
  S.settle(game, { limit = 4000, watch = shotOnMessage(game, "29_fortree_unseeable") })
  S.travel(game, { "EM_ROUTE120" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE120", "Fortree -> Route 120") then return false end
  local steven = S.objectByScript("Route120_EventScript_Steven")
  if not d.check(steven ~= nil, "Steven stands on the Route 120 bridge") then return false end
  local before = #S.battles
  S.talkTo(game, steven)
  S.settle(game, { limit = 40000, onBattleFrame = battleShot(game, "30_bridge_kecleon"),
    until_ = function() return S.hasItem("ITEM_DEVON_SCOPE") and not S.busy() end })
  local kb = S.battles[before + 1]
  d.check(kb and kb.trainer == nil and kb.foe == S.species("SPECIES_KECLEON"),
    "Steven's DEVON SCOPE reveals a Kecleon: wild battle through the battle UI (" .. tostring(kb and kb.result) .. ")")
  return d.check(S.hasItem("ITEM_DEVON_SCOPE"), "Steven gives the DEVON SCOPE")
end }

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function gateSolve(game, goal)
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local P = require("src.core.game3.player")
  local RG = require("src.core.game3.rotating_gate")
  local p = RG._p
  local n = #p.gates
  local o0 = {}
  for i = 0, n - 1 do o0[i + 1] = RG.getOrientation(i) end
  local base = S.C():require("vars", "VAR_TEMP_0")
  local cur
  RG.setStore(function(id)
    local k = id - base
    return (cur[2 * k + 1] or 0) + (cur[2 * k + 2] or 0) * 256
  end, function(id, v)
    local k = id - base
    cur[2 * k + 1], cur[2 * k + 2] = v % 256, math.floor(v / 256) % 256
  end)
  local function blocked(x, y) return not (Collision.inBounds(x, y) and Collision.isWalkable(x, y)) end
  local function key(x, y, o) return x .. "," .. y .. ":" .. table.concat(o, "") end
  local start = { x = P.cellX, y = P.cellY, o = o0 }
  local seen = { [key(start.x, start.y, o0)] = true }
  local queue, head, found = { start }, 1, nil
  while head <= #queue and head < 200000 do
    local st = queue[head]
    head = head + 1
    if goal(st.x, st.y) then found = st break end
    for _, dir in ipairs({ "up", "left", "right", "down" }) do
      local dd = DELTA[dir]
      local tx, ty = st.x + dd[1], st.y + dd[2]
      if not blocked(tx, ty) and not Objects.blocks(tx, ty, nil, nil) then
        cur = {}
        for i = 1, n do cur[i] = st.o[i] end
        if not RG.checkCollision(dir, tx, ty, false, blocked, true) then
          local k = key(tx, ty, cur)
          if not seen[k] then
            seen[k] = true
            queue[#queue + 1] = { x = tx, y = ty, o = cur, prev = st, dir = dir }
          end
        end
      end
    end
  end
  RG.setStore(nil, nil)
  for i = 0, n - 1 do RG.setOrientation(i, o0[i + 1]) end
  if not found then return nil end
  local path = {}
  while found and found.prev do
    table.insert(path, 1, found.dir)
    found = found.prev
  end
  return path
end

-- pokeemerald/data/maps/FortreeCity_Gym/scripts.inc:1
BEATS[#BEATS + 1] = { id = "winona", run = function(game)
  S.travel(game, { "EM_FORTREE_CITY" }, { settle = { limit = 20000 } })
  local kec = S.objectByScript("FortreeCity_EventScript_Kecleon")
  if not d.check(kec ~= nil, "back in Fortree at the invisible obstacle") then return false end
  S.talkTo(game, kec)
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "31_fortree_devon_scope"),
    until_ = function() return S.flag("FLAG_KECLEON_FLED_FORTREE") and not S.busy() end })
  d.check(S.flag("FLAG_KECLEON_FLED_FORTREE"), "the DEVON SCOPE reveals the Kecleon and it flees (FLAG_KECLEON_FLED_FORTREE)")
  if S.needsHeal() then S.healAtCenter(game, "EM_FORTREE_CITY", "FortreeCity") end
  S.travel(game, { "EM_FORTREE_CITY_GYM" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_FORTREE_CITY_GYM", "into the Fortree Gym") then return false end
  S.settle(game, { limit = 600 })
  local RG = require("src.core.game3.rotating_gate")
  if not d.check(RG.active(), "the rotating gate puzzle is live") then return false end
  d.shot(game, "32_fortree_gates")
  local winona = S.objectByScript("FortreeCity_Gym_EventScript_Winona")
  local P = require("src.core.game3.player")
  local function nearWinona(x, y) return math.abs(x - winona.cellX) + math.abs(y - winona.cellY) == 1 end
  local rotations, walked = 0, 0
  for _ = 1, 12 do
    if nearWinona(P.cellX, P.cellY) then break end
    local path = gateSolve(game, nearWinona)
    if not path then d.note("no gate solution from " .. P.cellX .. "," .. P.cellY) break end
    for _, dir in ipairs(path) do
      local before = {}
      for g = 0, #RG._p.gates - 1 do before[g] = RG.getOrientation(g) end
      local x0, y0 = P.cellX, P.cellY
      S.step(game, dir)
      if S.busy() then S.settle(game, { limit = 20000 }) end
      for g = 0, #RG._p.gates - 1 do if RG.getOrientation(g) ~= before[g] then rotations = rotations + 1 end end
      if P.cellX == x0 and P.cellY == y0 then break end
      walked = walked + 1
      if S.mapNow() ~= "EM_FORTREE_CITY_GYM" then break end
    end
  end
  d.check(rotations > 0, "walking through the gates turns them (" .. rotations .. " rotations, " .. walked .. " steps)")
  if not d.check(nearWinona(P.cellX, P.cellY), "the gate maze leads to Winona") then return false end
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Winona (driver)") end
  S.talkTo(game, winona)
  S.settle(game, { limit = 40000, onBattleFrame = battleShot(game, "33_winona"),
    until_ = function() return S.flag("FLAG_RECEIVED_TM_AERIAL_ACE") and not S.busy() end })
  d.check(lastBattleWon(S.C():require("trainers", "TRAINER_WINONA_1")), "Leader Winona battle won")
  d.shot(game, "34_feather_badge")
  d.check(S.hasItem("ITEM_TM40"), "Winona gives TM40 AERIAL ACE")
  return d.check(S.flag("FLAG_BADGE06_GET") and S.flag("FLAG_DEFEATED_FORTREE_GYM"), "FEATHER BADGE (FLAG_BADGE06_GET)")
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
    local t0 = os.time()
    local ok, res = xpcall(function() return b.run(game) end, debug.traceback)
    d.note("BEAT " .. b.id .. " took " .. (os.time() - t0) .. "s")
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
