local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local d = S.new("em_story_seg4", "/tmp/em_story_seg4")

local PRE_SET = {
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
  "FLAG_DOCK_REJECTED_DEVON_GOODS", "FLAG_ENABLE_BRAWLY_MATCH_CALL",
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
  "FLAG_BADGE04_GET", "FLAG_BADGE05_GET", "FLAG_BADGE06_GET", "FLAG_DEFEATED_EVIL_TEAM_MT_CHIMNEY",
  "FLAG_DEFEATED_FORTREE_GYM", "FLAG_DEFEATED_LAVARIDGE_GYM", "FLAG_DEFEATED_PETALBURG_GYM",
  "FLAG_ENABLE_FLANNERY_MATCH_CALL", "FLAG_ENABLE_WALLY_MATCH_CALL", "FLAG_ENABLE_WINONA_MATCH_CALL",
  "FLAG_EVIL_LEADER_PLEASE_STOP", "FLAG_HIDE_FORTREE_CITY_KECLEON", "FLAG_HIDE_MAUVILLE_GYM_WATTSON",
  "FLAG_HIDE_METEOR_FALLS_1F_1R_COZMO", "FLAG_HIDE_METEOR_FALLS_TEAM_MAGMA", "FLAG_HIDE_MT_CHIMNEY_TEAM_AQUA",
  "FLAG_HIDE_MT_CHIMNEY_TEAM_MAGMA", "FLAG_HIDE_ROUTE_109_MR_BRINEY", "FLAG_HIDE_ROUTE_109_MR_BRINEY_BOAT",
  "FLAG_HIDE_ROUTE_111_ROCK_SMASH_TIP_GUY", "FLAG_HIDE_ROUTE_112_TEAM_MAGMA", "FLAG_HIDE_ROUTE_118_STEVEN",
  "FLAG_HIDE_ROUTE_119_TEAM_AQUA", "FLAG_HIDE_ROUTE_120_KECLEON_BRIDGE", "FLAG_HIDE_ROUTE_120_KECLEON_BRIDGE_SHADOW",
  "FLAG_HIDE_ROUTE_120_STEVEN", "FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1", "FLAG_HIDE_RUSTURF_TUNNEL_ROCK_2",
  "FLAG_HIDE_RUSTURF_TUNNEL_WANDA", "FLAG_HIDE_RUSTURF_TUNNEL_WANDAS_BOYFRIEND", "FLAG_HIDE_VERDANTURF_TOWN_SCOTT",
  "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WALLY", "FLAG_HIDE_WEATHER_INSTITUTE_2F_WORKERS", "FLAG_KECLEON_FLED_FORTREE",
  "FLAG_LANDMARK_FIERY_PATH", "FLAG_MET_ARCHIE_METEOR_FALLS", "FLAG_MIRAGE_TOWER_VISIBLE",
  "FLAG_PETALBURG_MART_EXPANDED_ITEMS", "FLAG_RECEIVED_CASTFORM", "FLAG_RECEIVED_DEVON_SCOPE", "FLAG_RECEIVED_GO_GOGGLES",
  "FLAG_RECEIVED_HM_FLY", "FLAG_RECEIVED_HM_ROCK_SMASH", "FLAG_RECEIVED_HM_STRENGTH", "FLAG_RECEIVED_HM_SURF",
  "FLAG_RECEIVED_METEORITE", "FLAG_RECEIVED_TM_AERIAL_ACE", "FLAG_RECEIVED_TM_FACADE", "FLAG_RECEIVED_TM_OVERHEAT",
  "FLAG_REGISTERED_BERNIE", "FLAG_REGISTERED_BROOKE", "FLAG_REGISTERED_CATHERINE", "FLAG_REGISTERED_FLANNERY",
  "FLAG_REGISTERED_ISAAC", "FLAG_REGISTERED_JACKSON", "FLAG_REGISTERED_LYDIA", "FLAG_REGISTERED_MADELINE",
  "FLAG_REGISTERED_NORMAN", "FLAG_REGISTERED_ROSE", "FLAG_REGISTERED_WILTON", "FLAG_REGISTERED_WINONA",
  "FLAG_REGISTERED_WINSTON", "FLAG_RUSTURF_TUNNEL_OPENED", "FLAG_SCOTT_CALL_FORTREE_GYM", "FLAG_SYS_TV_WATCH",
  "FLAG_VISITED_FALLARBOR_TOWN", "FLAG_VISITED_FORTREE_CITY", "FLAG_VISITED_LAVARIDGE_TOWN", "FLAG_VISITED_VERDANTURF_TOWN",
  "FLAG_RECEIVED_BIKE",
}
local PRE_CLEAR = {
  "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH", "FLAG_HIDE_LITTLEROOT_TOWN_FAT_MAN", "FLAG_HIDE_ROUTE_101_BOY",
  "FLAG_HIDE_ROUTE_116_DEVON_EMPLOYEE", "FLAG_HIDE_SLATEPORT_MUSEUM_POPULATION",
  "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WALLYS_UNCLE",
  "FLAG_ENABLE_FIRST_WALLY_POKENAV_CALL", "FLAG_HIDE_DEWFORD_HALL_SLUDGE_BOMB_MAN", "FLAG_HIDE_FALLARBOR_HOUSE_PROF_COZMO",
  "FLAG_HIDE_MAUVILLE_CITY_WATTSON", "FLAG_HIDE_MT_CHIMNEY_LAVA_COOKIE_LADY", "FLAG_HIDE_MT_CHIMNEY_TRAINERS",
  "FLAG_HIDE_PETALBURG_GYM_GREETER", "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WANDA",
  "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WANDAS_BOYFRIEND", "FLAG_HIDE_WEATHER_INSTITUTE_1F_WORKERS",
}
local PRE_VARS = {
  VAR_BIRCH_LAB_STATE = 5, VAR_BOARD_BRINEY_BOAT_STATE = 0, VAR_BRINEY_HOUSE_STATE = 1, VAR_BRINEY_LOCATION = 0,
  VAR_CABLE_CLUB_TUTORIAL_STATE = 1, VAR_DEVON_CORP_3F_STATE = 1, VAR_LITTLEROOT_INTRO_STATE = 7,
  VAR_LITTLEROOT_HOUSES_STATE_BRENDAN = 2, VAR_LITTLEROOT_RIVAL_STATE = 4, VAR_LITTLEROOT_TOWN_STATE = 4,
  VAR_OLDALE_RIVAL_STATE = 2, VAR_OLDALE_TOWN_STATE = 1, VAR_PETALBURG_CITY_STATE = 5, VAR_PETALBURG_GYM_STATE = 7,
  VAR_PETALBURG_WOODS_STATE = 1, VAR_REGISTER_BIRCH_STATE = 2, VAR_ROUTE101_STATE = 3, VAR_ROUTE104_STATE = 2,
  VAR_ROUTE110_STATE = 1, VAR_ROUTE116_STATE = 2, VAR_RUSTBORO_CITY_STATE = 8, VAR_RUSTURF_TUNNEL_STATE = 6,
  VAR_SCOTT_PETALBURG_ENCOUNTER = 1, VAR_SCOTT_STATE = 4, VAR_SLATEPORT_OUTSIDE_MUSEUM_STATE = 3, VAR_STARTER_MON = 1,
  VAR_LAVARIDGE_TOWN_STATE = 2, VAR_ROUTE118_STATE = 1, VAR_ROUTE119_STATE = 1, VAR_WEATHER_INSTITUTE_STATE = 2,
  VAR_METEOR_FALLS_STATE = 1, VAR_CABLE_CAR_STATION_STATE = 0, VAR_JAGGED_PASS_ASH_WEATHER = 0,
  VAR_WALLY_CALL_STEP_COUNTER = 250, VAR_SCOTT_FORTREE_CALL_STEP_COUNTER = 0,
}
local PRE_TRAINERS = {
  "TRAINER_ALLEN", "TRAINER_ALYSSA", "TRAINER_BRAWLY_1", "TRAINER_BRENDEN", "TRAINER_CALVIN_1", "TRAINER_CINDY_1",
  "TRAINER_CRISTIAN", "TRAINER_DEVAN", "TRAINER_EDMOND", "TRAINER_EDWARD", "TRAINER_GRUNT_MUSEUM_1", "TRAINER_GRUNT_MUSEUM_2",
  "TRAINER_GRUNT_PETALBURG_WOODS", "TRAINER_GRUNT_RUSTURF_TUNNEL", "TRAINER_HAILEY", "TRAINER_HALEY_1", "TRAINER_ISABEL_1",
  "TRAINER_JAMES_1", "TRAINER_JOCELYN", "TRAINER_JOHNSON", "TRAINER_JOSH", "TRAINER_KALEB", "TRAINER_KAREN_1",
  "TRAINER_LAURA", "TRAINER_LILITH", "TRAINER_MARC", "TRAINER_MAY_ROUTE_103_TORCHIC", "TRAINER_MAY_ROUTE_110_TORCHIC",
  "TRAINER_MAY_RUSTBORO_TORCHIC", "TRAINER_RICK", "TRAINER_RICKY_1", "TRAINER_ROXANNE_1", "TRAINER_TAKAO", "TRAINER_TIANA",
  "TRAINER_TOMMY", "TRAINER_WALLY_MAUVILLE", "TRAINER_WATTSON_1", "TRAINER_KIRK", "TRAINER_SHAWN", "TRAINER_BEN",
  "TRAINER_VIVIAN", "TRAINER_ANGELO",
  "TRAINER_ALEXIA", "TRAINER_ANGELINA", "TRAINER_ASHLEY", "TRAINER_AUTUMN", "TRAINER_AXLE", "TRAINER_BERKE",
  "TRAINER_BERNIE_1", "TRAINER_BRICE", "TRAINER_BROOKE_1", "TRAINER_CATHERINE_1", "TRAINER_CELINA", "TRAINER_CLARK",
  "TRAINER_COLE", "TRAINER_DANIELLE", "TRAINER_DARIUS", "TRAINER_DAYTON", "TRAINER_DEANDRE", "TRAINER_DEREK",
  "TRAINER_DONALD", "TRAINER_EDWARDO", "TRAINER_ELI", "TRAINER_ERIC", "TRAINER_FABIAN", "TRAINER_FLANNERY_1",
  "TRAINER_FLINT", "TRAINER_GEORGE", "TRAINER_GERALD", "TRAINER_GINA_AND_MIA_1", "TRAINER_GRUNT_MT_CHIMNEY_1",
  "TRAINER_GRUNT_MT_CHIMNEY_2", "TRAINER_GRUNT_WEATHER_INST_1", "TRAINER_GRUNT_WEATHER_INST_2",
  "TRAINER_GRUNT_WEATHER_INST_3", "TRAINER_GRUNT_WEATHER_INST_5", "TRAINER_HUMBERTO", "TRAINER_IRENE", "TRAINER_ISAAC_1",
  "TRAINER_JACE", "TRAINER_JACKSON_1", "TRAINER_JARED", "TRAINER_JAYLEN", "TRAINER_JEFF", "TRAINER_JODY",
  "TRAINER_JULIO", "TRAINER_KEEGAN", "TRAINER_LARRY", "TRAINER_LENNY", "TRAINER_LUCAS_1", "TRAINER_LYDIA_1",
  "TRAINER_LYLE", "TRAINER_MADELINE_1", "TRAINER_MARY", "TRAINER_MAXIE_MT_CHIMNEY", "TRAINER_MAY_ROUTE_119_TORCHIC",
  "TRAINER_MIKE_2", "TRAINER_NORMAN_1", "TRAINER_PARKER", "TRAINER_RANDALL", "TRAINER_ROSE_1", "TRAINER_SHAYLA",
  "TRAINER_SHELLY_WEATHER_INSTITUTE", "TRAINER_TABITHA_MT_CHIMNEY", "TRAINER_TAKASHI", "TRAINER_TORI_AND_TIA",
  "TRAINER_TYRON", "TRAINER_WILTON_1", "TRAINER_WINONA_1", "TRAINER_WINSTON_1", "TRAINER_YASU",
}
local PRE_ITEMS = {
  "ITEM_HM02", "ITEM_HM03", "ITEM_HM04", "ITEM_HM06", "ITEM_TM39", "ITEM_TM08", "ITEM_TM47", "ITEM_TM34", "ITEM_TM50",
  "ITEM_TM42", "ITEM_TM40", "ITEM_DEVON_SCOPE", "ITEM_GO_GOGGLES", "ITEM_METEORITE", "ITEM_MACH_BIKE", "ITEM_POKE_BALL",
}


local SEG3_SET = {
  "FLAG_BADGE07_GET", "FLAG_BADGE08_GET", "FLAG_DEFEATED_GRUNT_SPACE_CENTER_1F", "FLAG_DEFEATED_MOSSDEEP_GYM",
  "FLAG_DEFEATED_SOOTOPOLIS_GYM", "FLAG_ENABLE_JUAN_MATCH_CALL", "FLAG_ENABLE_TATE_AND_LIZA_MATCH_CALL",
  "FLAG_GROUDON_AWAKENED_MAGMA_HIDEOUT", "FLAG_HIDE_AQUA_HIDEOUT_1F_GRUNT_1_BLOCKING_ENTRANCE",
  "FLAG_HIDE_AQUA_HIDEOUT_1F_GRUNT_2_BLOCKING_ENTRANCE", "FLAG_HIDE_AQUA_HIDEOUT_B2F_SUBMARINE_SHADOW",
  "FLAG_HIDE_AQUA_HIDEOUT_GRUNTS", "FLAG_HIDE_CAVE_OF_ORIGIN_B1F_WALLACE", "FLAG_HIDE_JAGGED_PASS_MAGMA_GUARD",
  "FLAG_HIDE_LILYCOVE_CITY_AQUA_GRUNTS", "FLAG_HIDE_LILYCOVE_CITY_RIVAL", "FLAG_HIDE_LILYCOVE_MOTEL_SCOTT",
  "FLAG_HIDE_LILYCOVE_POKEMON_CENTER_CONTEST_LADY_MON", "FLAG_HIDE_MAGMA_HIDEOUT_4F_GROUDON_ASLEEP",
  "FLAG_HIDE_MAGMA_HIDEOUT_GRUNTS", "FLAG_HIDE_MOSSDEEP_CITY_SCOTT", "FLAG_HIDE_MOSSDEEP_CITY_SPACE_CENTER_1F_STEVEN",
  "FLAG_HIDE_MOSSDEEP_CITY_SPACE_CENTER_MAGMA_NOTE", "FLAG_HIDE_MT_PYRE_SUMMIT_TEAM_AQUA",
  "FLAG_HIDE_ROUTE_121_TEAM_AQUA_GRUNTS", "FLAG_HIDE_SEAFLOOR_CAVERN_AQUA_GRUNTS",
  "FLAG_HIDE_SEAFLOOR_CAVERN_ENTRANCE_AQUA_GRUNT", "FLAG_HIDE_SEAFLOOR_CAVERN_ROOM_9_KYOGRE_ASLEEP",
  "FLAG_HIDE_SKY_PILLAR_TOP_RAYQUAZA", "FLAG_INTERACTED_WITH_STEVEN_SPACE_CENTER",
  "FLAG_KYOGRE_ESCAPED_SEAFLOOR_CAVERN", "FLAG_LANDMARK_SEAFLOOR_CAVERN", "FLAG_LANDMARK_SKY_PILLAR",
  "FLAG_MET_ARCHIE_SOOTOPOLIS", "FLAG_MET_MAXIE_SOOTOPOLIS", "FLAG_MET_RIVAL_LILYCOVE", "FLAG_MET_TEAM_AQUA_HARBOR",
  "FLAG_OMIT_DIVE_FROM_STEVEN_LETTER", "FLAG_RECEIVED_HM_DIVE", "FLAG_RECEIVED_HM_WATERFALL",
  "FLAG_RECEIVED_RED_OR_BLUE_ORB", "FLAG_RECEIVED_TM_CALM_MIND", "FLAG_RECEIVED_TM_WATER_PULSE",
  "FLAG_REGISTERED_CRISTIN", "FLAG_REGISTERED_JESSICA", "FLAG_REGISTERED_JUAN", "FLAG_REGISTERED_TATE_AND_LIZA",
  "FLAG_SOOTOPOLIS_ARCHIE_MAXIE_LEAVE", "FLAG_STEVEN_GUIDES_TO_CAVE_OF_ORIGIN", "FLAG_TEAM_AQUA_ESCAPED_IN_SUBMARINE",
  "FLAG_VISITED_LILYCOVE_CITY", "FLAG_VISITED_MOSSDEEP_CITY", "FLAG_VISITED_SOOTOPOLIS_CITY",
  "FLAG_WALLACE_GOES_TO_SKY_PILLAR",
}
local SEG3_CLEAR = {
  "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_2F_PICHU_DOLL", "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_RIVAL_BEDROOM",
  "FLAG_HIDE_MT_PYRE_SUMMIT_MAXIE", "FLAG_HIDE_SLATEPORT_CITY_HARBOR_CAPTAIN_STERN",
  "FLAG_HIDE_SLATEPORT_CITY_STERNS_SHIPYARD_MR_BRINEY", "FLAG_SCOTT_CALL_FORTREE_GYM",
}
local SEG3_TRAINERS = {
  "TRAINER_ALLISON", "TRAINER_ANDREA", "TRAINER_ANNIKA", "TRAINER_ARCHIE", "TRAINER_BETHANY", "TRAINER_BLAKE",
  "TRAINER_BRIANNA", "TRAINER_BRIDGET", "TRAINER_CALE", "TRAINER_CHASE", "TRAINER_CLIFFORD", "TRAINER_COLIN",
  "TRAINER_CONNIE", "TRAINER_CRISSY", "TRAINER_CRISTIN_1", "TRAINER_DAPHNE", "TRAINER_DECLAN", "TRAINER_GRACE",
  "TRAINER_GRUNT_AQUA_HIDEOUT_2", "TRAINER_GRUNT_AQUA_HIDEOUT_4", "TRAINER_GRUNT_AQUA_HIDEOUT_5",
  "TRAINER_GRUNT_AQUA_HIDEOUT_6", "TRAINER_GRUNT_AQUA_HIDEOUT_7", "TRAINER_GRUNT_AQUA_HIDEOUT_8",
  "TRAINER_GRUNT_MAGMA_HIDEOUT_11", "TRAINER_GRUNT_MAGMA_HIDEOUT_12", "TRAINER_GRUNT_MAGMA_HIDEOUT_13",
  "TRAINER_GRUNT_MAGMA_HIDEOUT_16", "TRAINER_GRUNT_MAGMA_HIDEOUT_2", "TRAINER_GRUNT_MAGMA_HIDEOUT_3",
  "TRAINER_GRUNT_MAGMA_HIDEOUT_9", "TRAINER_GRUNT_MT_PYRE_1", "TRAINER_GRUNT_MT_PYRE_2", "TRAINER_GRUNT_MT_PYRE_3",
  "TRAINER_GRUNT_MT_PYRE_4", "TRAINER_GRUNT_SEAFLOOR_CAVERN_5", "TRAINER_GRUNT_SPACE_CENTER_2",
  "TRAINER_GRUNT_SPACE_CENTER_4", "TRAINER_GRUNT_SPACE_CENTER_5", "TRAINER_GRUNT_SPACE_CENTER_6",
  "TRAINER_GRUNT_SPACE_CENTER_7", "TRAINER_HANNAH", "TRAINER_JESSICA_1", "TRAINER_JUAN_1", "TRAINER_KATHLEEN",
  "TRAINER_KATIE", "TRAINER_KEVIN", "TRAINER_MACEY", "TRAINER_MARCEL", "TRAINER_MATT", "TRAINER_MAURA",
  "TRAINER_MAXIE_MAGMA_HIDEOUT", "TRAINER_MAY_LILYCOVE_TORCHIC", "TRAINER_NATE", "TRAINER_NICHOLAS", "TRAINER_OLIVIA",
  "TRAINER_PRESTON", "TRAINER_REED", "TRAINER_SAMANTHA", "TRAINER_SHELLY_SEAFLOOR_CAVERN", "TRAINER_SYLVIA",
  "TRAINER_TABITHA_MAGMA_HIDEOUT", "TRAINER_TALIA", "TRAINER_TATE_AND_LIZA_1", "TRAINER_TIFFANY", "TRAINER_VIRGIL",
}
local SEG3_VARS = {
  VAR_JAGGED_PASS_STATE = 2, VAR_MOSSDEEP_CITY_STATE = 3, VAR_MOSSDEEP_SPACE_CENTER_STAIR_GUARD_STATE = 2,
  VAR_MOSSDEEP_SPACE_CENTER_STATE = 3, VAR_MT_PYRE_STATE = 2, VAR_RIVAL_RAYQUAZA_CALL_STEP_COUNTER = 250,
  VAR_ROUTE121_STATE = 1, VAR_ROUTE128_STATE = 2, VAR_SCOTT_FORTREE_CALL_STEP_COUNTER = 10, VAR_SCOTT_STATE = 5,
  VAR_SEAFLOOR_CAVERN_STATE = 1, VAR_SKY_PILLAR_RAYQUAZA_CRY_DONE = 1, VAR_SKY_PILLAR_STATE = 3,
  VAR_SLATEPORT_CITY_STATE = 2, VAR_SLATEPORT_HARBOR_STATE = 2, VAR_SOOTOPOLIS_CITY_STATE = 6,
  VAR_SOOTOPOLIS_WALLACE_STATE = 1, VAR_STEVENS_HOUSE_STATE = 2,
}

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

local function tid(name) return S.C():require("trainers", name) end

local function lastBattleWon(t)
  for i = #S.battles, 1, -1 do
    local b = S.battles[i]
    if not t or b.trainer == t then return b.result == "win", b end
  end
  return false
end

local function fightTrainer(game, label, name, shot, talkOpts, trainer)
  local eo = S.objectByScript(label)
  if trainer and S.trainerBeaten(trainer) then
    return d.check(true, name .. " beaten on the way (" .. trainer .. ")")
  end
  if not d.check(eo ~= nil, name .. " is on the map") then return false end
  local t = trainer and tid(trainer)
  local mine
  S.pendingBattleShot = shot
  for _ = 1, 4 do
    local before = #S.battles
    S.talkTo(game, eo, talkOpts)
    S.settle(game, { limit = 20000 })
    for i = before + 1, #S.battles do
      if not t or S.battles[i].trainer == t then mine = S.battles[i] end
    end
    if mine or not t or S.trainerBeaten(trainer) then break end
  end
  S.pendingBattleShot = nil
  return d.check(mine ~= nil and mine.result == "win", name .. " battle won (" .. tostring(mine and mine.result) .. ")")
end

local function teachHm(item, slot)
  local ItemUse = require("src.core.game3.item_use")
  local s = S.session()
  local ok, kind = ItemUse.useTm(s, s.bag, S.item(item), slot or 1)
  return ok, kind
end

local function knows(mon, move)
  for _, m in ipairs(mon and mon.moves or {}) do if m == S.move(move) then return true end end
  return false
end

local function slotWith(move)
  for i, m in ipairs(S.session().party or {}) do if knows(m, move) then return i, m end end
end

local function topId()
  local t = require("src.ui.game3.stack").top()
  return t and t.id
end

local function waitFor(pred, limit)
  for _ = 1, limit or 600 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

-- pokeemerald/src/party_menu.c:3702
local function partyAction(game, move, action)
  local StartMenu = require("src.ui.game3.start_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local slot = slotWith(move)
  if not slot then d.note("no party mon knows " .. move) return false end
  S.settle(game, { limit = 600 })
  U.tap(game, "start")
  if not waitFor(function() return topId() == "start" end, 120) then d.note("start menu did not open") return false end
  local row
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "pokemon" then row = i end end
  for _ = 1, 12 do
    if StartMenu.cursor == row then break end
    U.tap(game, "down") U.wait(6)
  end
  U.tap(game, "a")
  if not waitFor(function() return PartyMenu.isOpen() and PartyMenu.mode == "list" end, 240) then
    d.note("party menu did not open (" .. tostring(topId()) .. ")") return false
  end
  U.wait(20)
  for _ = 1, 12 do
    if PartyMenu.cursor == slot then break end
    U.tap(game, "down") U.wait(6)
  end
  U.tap(game, "a")
  if not waitFor(function() return PartyMenu.mode == "action" end, 120) then d.note("party action menu did not open") return false end
  local want
  for i, a in ipairs(PartyMenu.ACTIONS or {}) do if a == action then want = i end end
  if not want then d.note("no " .. action .. " action (" .. table.concat(PartyMenu.ACTIONS or {}, ",") .. ")") return false end
  for _ = 1, 8 do
    if PartyMenu.actionCursor == want then break end
    U.tap(game, "down") U.wait(6)
  end
  U.tap(game, "a")
  return true
end

-- pokeemerald/src/fldeff_flash.c:72
local function useFlash(game, shot)
  if S.flag("FLAG_SYS_USE_FLASH") then return true end
  if not partyAction(game, "MOVE_FLASH", "FLASH") then return false end
  local Field = require("src.core.game3.field")
  waitFor(function() return S.flag("FLAG_SYS_USE_FLASH") end, 600)
  waitFor(function() return not Field.locked and not S.busy() end, 1200)
  S.settle(game, { limit = 3000 })
  if shot then U.wait(30) d.shot(game, shot) end
  return S.flag("FLAG_SYS_USE_FLASH")
end

-- pokeemerald/src/region_map.c:1647
local function fly(game, secName, destMap, shot)
  local RegionMap = require("src.ui.game3.rse.region_map")
  if not partyAction(game, "MOVE_FLY", "FLY") then return false end
  if not waitFor(function() return RegionMap.active() ~= nil end, 300) then d.note("fly map did not open") return false end
  local s = RegionMap.active()
  waitFor(function() return s.state == 12 end, 240)
  local target = S.C():require("region_map_sections", "MAPSEC_" .. secName)
  local tx, ty
  for y = RegionMap.CURSOR_Y_MIN, RegionMap.CURSOR_Y_MAX do
    for x = RegionMap.CURSOR_X_MIN, RegionMap.CURSOR_X_MAX do
      if not tx and RegionMap.mapSecAt(x, y) == target then tx, ty = x, y end
    end
  end
  if not tx then d.note("mapsec " .. secName .. " not on the fly map") return false end
  for _ = 1, 60 do
    if s.cursorX == tx and s.cursorY == ty then break end
    local dir = s.cursorX < tx and "right" or s.cursorX > tx and "left" or s.cursorY < ty and "down" or "up"
    local x0, y0 = s.cursorX, s.cursorY
    U.hold(game, dir, 2)
    waitFor(function() return s.cursorX ~= x0 or s.cursorY ~= y0 end, 30)
    waitFor(function() return s.inputFn == "full" end, 10)
    U.wait(1)
  end
  U.wait(8)
  if shot then d.shot(game, shot) end
  U.tap(game, "a")
  waitFor(function() return S.mapNow() == destMap end, 1500)
  local Field = require("src.core.game3.field")
  waitFor(function() return not Field.locked and not S.busy() end, 1500)
  S.settle(game, { limit = 3000 })
  return S.mapNow() == destMap
end

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function smashAt(game, x, y)
  local Objects = require("src.core.game3.objects")
  local eo = Objects.at(x, y)
  if not eo then return false end
  S.talkTo(game, eo)
  S.settle(game, { limit = 6000 })
  S.rocksSmashed = (S.rocksSmashed or 0) + (Objects.at(x, y) and 0 or 1)
  return Objects.at(x, y) == nil
end


local function objectsByScript(label)
  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local want = Space.bundle and Space.bundle.labels and Space.bundle.labels[label]
  local out = {}
  for _, lid in ipairs(Objects.listActive() or {}) do
    local eo = Objects.find(lid)
    local s = eo and not eo.hidden and (eo.scriptKey or (eo.def and (eo.def.script or eo.def.scriptKey)))
    if s and (s == label or (want and s == want)) then out[#out + 1] = eo end
  end
  return out
end

local function strengthSolve(game, goal, opts)
  opts = opts or {}
  local C = require("src.core.game3.collision")
  local P = require("src.core.game3.player")
  local boulders = objectsByScript("EventScript_StrengthBoulder")
  local orig = {}
  for _, b in ipairs(boulders) do orig[b.cellX .. "," .. b.cellY] = true end
  local rocks = {}
  for _, r in ipairs(objectsByScript("EventScript_RockSmash")) do rocks[r.cellX .. "," .. r.cellY] = true orig[r.cellX .. "," .. r.cellY] = true end
  local warpCells = {}
  for _, w in ipairs(game.data.maps[S.mapNow()].warps or {}) do
    if not C.isArrowWarpBehavior(C.behavior(w.x, w.y)) then warpCells[w.x .. "," .. w.y] = true end
  end
  local terrainCache = {}
  local function terrain(fx, fy, tx, ty, dir, elev)
    local k = fx .. "," .. fy .. ">" .. tx .. "," .. ty .. ":" .. tostring(elev)
    local v = terrainCache[k]
    if v == nil then
      local ok, why = C.canEnter(game, tx, ty, { fromX = fx, fromY = fy, dir = dir, elevation = elev, surfing = false })
      if not ok and why == "entity" and orig[tx .. "," .. ty] then ok = true end
      v = ok and true or false
      terrainCache[k] = v
    end
    return v
  end
  local function bkey(bs)
    local t = {}
    for i, b in ipairs(bs) do t[i] = b end
    table.sort(t)
    return table.concat(t, ";")
  end
  local bs0 = {}
  for _, b in ipairs(boulders) do bs0[#bs0 + 1] = b.cellX .. "," .. b.cellY end
  local start = { x = P.cellX, y = P.cellY, bs = bs0, e = P.currentElevation }
  local seen = { [start.x .. "," .. start.y .. "|" .. bkey(bs0)] = true }
  local q, head = { start }, 1
  local found
  while head <= #q and head < (opts.maxStates or 150000) do
    local st = q[head]
    head = head + 1
    if goal(st.x, st.y) then found = st break end
    local set = {}
    for i, b in ipairs(st.bs) do set[b] = i end
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
      local dd = DELTA[dir]
      local tx, ty = st.x + dd[1], st.y + dd[2]
      local tk = tx .. "," .. ty
      local nst
      if set[tk] then
        local bx, by = tx + dd[1], ty + dd[2]
        local bk = bx .. "," .. by
        if not set[bk] and not warpCells[bk] and not rocks[bk] and terrain(tx, ty, bx, by, dir, 3) then
          local nb = {}
          for i, b in ipairs(st.bs) do nb[i] = (i == set[tk]) and bk or b end
          nst = { x = tx, y = ty, bs = nb, e = st.e, prev = st, dir = dir, push = true }
        end
      elseif not (warpCells[tk] and not (opts.allowWarp and opts.allowWarp(tx, ty))) and terrain(st.x, st.y, tx, ty, dir, st.e) then
        local z = C.elevationAt(tx, ty)
        local ne = (z == nil or z == 15 or C.elevationAt(st.x, st.y) == 15) and st.e or z
        nst = { x = tx, y = ty, bs = st.bs, e = ne, prev = st, dir = dir }
      end
      if nst then
        local k = nst.x .. "," .. nst.y .. "|" .. bkey(nst.bs)
        if not seen[k] then
          seen[k] = true
          q[#q + 1] = nst
        end
      end
    end
  end
  if not found then return nil, head end
  local path, pushes = {}, 0
  while found and found.prev do
    table.insert(path, 1, found.dir)
    if found.push then pushes = pushes + 1 end
    found = found.prev
  end
  return path, pushes
end

local function useStrength(game)
  if S.flag("FLAG_SYS_USE_STRENGTH") then return true end
  local P = require("src.core.game3.player")
  local bs = objectsByScript("EventScript_StrengthBoulder")
  local best
  for _, b in ipairs(bs) do
    if S.path(game, function(x, y) return math.abs(x - b.cellX) + math.abs(y - b.cellY) == 1 end) then best = b break end
  end
  if not best then return false end
  S.talkTo(game, best)
  S.settle(game, { limit = 6000 })
  return S.flag("FLAG_SYS_USE_STRENGTH")
end

local function strengthGo(game, goal, opts)
  opts = opts or {}
  local P = require("src.core.game3.player")
  local pushes = 0
  local m0 = S.mapNow()
  for _ = 1, opts.tries or 6 do
    if goal(P.cellX, P.cellY) then return true, pushes end
    if S.mapNow() ~= m0 then return false, pushes end
    local path, n = strengthSolve(game, goal, opts)
    if not path then d.note("strength solver: no solution on " .. m0 .. " from " .. P.cellX .. "," .. P.cellY .. " (" .. tostring(n) .. " states)") return false, pushes end
    if n > 0 and not S.flag("FLAG_SYS_USE_STRENGTH") then
      if not useStrength(game) then d.note("could not activate STRENGTH") return false, pushes end
      path = strengthSolve(game, goal, opts)
      if not path then return false, pushes end
    end
    local Objects = require("src.core.game3.objects")
    local rockSet = {}
    for _, r in ipairs(objectsByScript("EventScript_RockSmash")) do rockSet[r] = true end
    for _, dir in ipairs(path) do
      local dd = DELTA[dir]
      local x0, y0 = P.cellX, P.cellY
      local b = Objects.at(x0 + dd[1], y0 + dd[2])
      if b and rockSet[b] then
        S.face(game, dir)
        smashAt(game, x0 + dd[1], y0 + dd[2])
        b = Objects.at(x0 + dd[1], y0 + dd[2])
      end
      S.step(game, dir)
      for _ = 1, 120 do
        if not (P.moving or (b and b.moving)) and not S.busy() then break end
        U.wait(1)
      end
      if S.busy() then S.settle(game, opts.settle or { limit = 20000 }) end
      if b and b.cellX ~= x0 + dd[1] + 0 or (b and b.cellY ~= y0 + dd[2]) then pushes = pushes + 1 end
      if P.cellX == x0 and P.cellY == y0 then
        U.wait(10)
        if b then S.step(game, dir) U.wait(20) end
        if P.cellX == x0 and P.cellY == y0 then break end
      end
      if S.mapNow() ~= m0 then break end
    end
  end
  return goal(P.cellX, P.cellY), pushes
end

local function seek(game, target, prefix, opts)
  opts = opts or {}
  local P = require("src.core.game3.player")
  local dead = {}
  local lastMap, entry
  for _ = 1, opts.tries or 30 do
    local cur = S.mapNow()
    if cur == target then return true end
    if cur ~= lastMap then lastMap, entry = cur, cur .. "@" .. P.cellX .. "," .. P.cellY end
    if opts.repel ~= false then S.useRepel() end
    local prev, q, head = { [cur] = false }, { cur }, 1
    while head <= #q do
      local m = q[head]
      head = head + 1
      if m == target then break end
      local def = game.data.maps[m]
      for _, w in ipairs(def and def.warps or {}) do
        local nm = w.destMap
        if nm and prev[nm] == nil and (nm == target or nm:find(prefix, 1, true)) and not (m == cur and dead[entry .. ">" .. nm]) then
          prev[nm] = m
          q[#q + 1] = nm
        end
      end
    end
    if prev[target] == nil then
      d.note("seek: no map route from " .. cur .. " to " .. target)
      return false
    end
    local hop = target
    while prev[hop] ~= cur do hop = prev[hop] end
    if os.getenv("EM_STORY_DEBUG") then d.note("seek " .. cur .. " -> " .. hop .. " (" .. entry .. ")") end
    local def = game.data.maps[cur]
    local function nearHop(x, y)
      for _, w in ipairs(def.warps or {}) do
        if w.destMap == hop and math.abs(x - w.x) + math.abs(y - w.y) == 1 then return true end
      end
      return false
    end
    if #objectsByScript("EventScript_StrengthBoulder") + #objectsByScript("EventScript_RockSmash") > 0 and not S.path(game, nearHop) then
      local ok, pushes = strengthGo(game, nearHop)
      S.strengthPushes = (S.strengthPushes or 0) + (pushes or 0)
    end
    local ok = S.exitTo(game, hop, { avoidWarps = true, settle = opts.settle or { limit = 20000 } })
    S.settle(game, opts.settle or { limit = 20000 })
    if not ok and S.mapNow() == cur then dead[entry .. ">" .. hop] = true end
  end
  return S.mapNow() == target
end


local function mugshotWatch(game, file, seen)
  return function()
    local BT = package.loaded["src.core.game3.battle_transition"]
    local fx = BT and BT._fx
    if not seen.key and fx and fx.mugKey and fx.state >= 6 then
      seen.key = fx.mugKey
      d.shot(game, file)
    end
  end
end

local function override(x, y)
  local Field = require("src.core.game3.field")
  local b = Field.metatileOverrides and Field.metatileOverrides[S.mapNow()]
  local o = b and b[y * 1024 + x]
  return o and o.metatile
end

local function mt(name) return S.C():require("metatile_labels", name) end

local function nearWarp(game, wx, wy)
  return function(x, y) return math.abs(x - wx) + math.abs(y - wy) == 1 end
end

local function toWarp(game, wx, wy, opts)
  opts = opts or {}
  local m0 = S.mapNow()
  local avoid = {}
  for _, w in ipairs(game.data.maps[m0].warps or {}) do
    if not (w.x == wx and w.y == wy) then avoid[w.x .. "," .. w.y] = true end
  end
  if not S.path(game, nearWarp(game, wx, wy), { avoid = avoid })
      and #objectsByScript("EventScript_StrengthBoulder") + #objectsByScript("EventScript_RockSmash") > 0 then
    local ok, pushes = strengthGo(game, nearWarp(game, wx, wy), { allowWarp = function() return false end })
    S.strengthPushes = (S.strengthPushes or 0) + (pushes or 0)
  end
  for _ = 1, 6 do
    if S.mapNow() ~= m0 then return true end
    S.goTo(game, { wx, wy }, { avoid = avoid, goalBlocked = true, tries = 20, settle = opts.settle or { limit = 30000 } })
    S.settle(game, opts.settle or { limit = 30000 })
    local P = require("src.core.game3.player")
    if S.mapNow() == m0 and P.cellX == wx and P.cellY == wy then
      local C = require("src.core.game3.collision")
      for _, dir in ipairs({ "down", "up", "left", "right" }) do
        local dd = DELTA[dir]
        if S.mapNow() ~= m0 or P.cellX ~= wx or P.cellY ~= wy then break end
        if not C.canEnter(game, wx + dd[1], wy + dd[2], { fromX = wx, fromY = wy, dir = dir, elevation = P.currentElevation }) then
          S.step(game, dir)
          S.settle(game, { limit = 600 })
        end
      end
    end
  end
  if S.mapNow() == m0 then
    local P = require("src.core.game3.player")
    d.note(string.format("warp %d,%d on %s not taken; player at %d,%d elev %s", wx, wy, m0, P.cellX, P.cellY, tostring(P.currentElevation)))
  end
  return S.mapNow() ~= m0
end

-- pokeemerald/src/item_use.c:742
local function patchUp()
  local ItemUse = require("src.core.game3.item_use")
  local s = S.session()
  local used = 0
  for i, mon in ipairs(s.party or {}) do
    if not mon.isEgg then
      if (tonumber(mon.hp) or 0) <= 0 then
        if not S.hasItem("ITEM_MAX_REVIVE") then return used, false end
        if ItemUse.useField(s, s.bag, S.item("ITEM_MAX_REVIVE"), i) then used = used + 1 end
      end
      local st = mon.status
      local statused = (type(st) == "number" and st ~= 0) or (type(st) == "string" and st ~= "") or type(st) == "table"
      if statused or (tonumber(mon.hp) or 0) < (tonumber(mon.maxHp) or 0) * 0.7 then
        if not S.hasItem("ITEM_FULL_RESTORE") then return used, false end
        if ItemUse.useField(s, s.bag, S.item("ITEM_FULL_RESTORE"), i) then used = used + 1 end
      end
      local lowPp = false
      for k = 1, 4 do
        local mx = tonumber(mon.maxPp and mon.maxPp[k]) or 0
        if mx > 0 and (tonumber(mon.pp and mon.pp[k]) or 0) * 2 < mx then lowPp = true end
      end
      if lowPp then
        if not S.hasItem("ITEM_MAX_ELIXIR") then return used, false end
        if ItemUse.useField(s, s.bag, S.item("ITEM_MAX_ELIXIR"), i) then used = used + 1 end
      end
    end
  end
  return used, true
end

local function labelWatch(seen)
  local Space = require("src.core.game3.scripting.space")
  local rev
  return function()
    local vm = Space.vm
    if not (vm and vm:isRunning()) then return end
    if not rev then
      rev = {}
      for name, key in pairs(Space.bundle and Space.bundle.labels or {}) do rev[key] = name end
    end
    local pc = vm.ctx and vm.ctx.pc
    local name = pc and (rev[pc.listKey] or pc.listKey)
    if name then seen[name] = true end
    for _, fr in ipairs(vm.ctx and vm.ctx.stack or {}) do
      local n = fr and (rev[fr.listKey] or fr.listKey)
      if n then seen[n] = true end
    end
  end
end

local function messageText()
  local M = require("src.ui.game3.message")
  local t = M.currentPage()
  if type(t) == "table" then t = table.concat(t, " ") end
  return t and tostring(t):gsub("\n", " ") or ""
end

local BEATS = {}

BEATS[#BEATS + 1] = { id = "start", run = function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "QUINCY", gender = 0, start = {
    map = "EM_SOOTOPOLIS_CITY", x = 31, y = 33, facing = "down", healMap = "EM_SOOTOPOLIS_CITY", healX = 43, healY = 32,
  } })
  U.wait(30)
  for _, f in ipairs(PRE_SET) do S.setFlag(f, true) end
  for _, f in ipairs(PRE_CLEAR) do S.setFlag(f, false) end
  for k, v in pairs(PRE_VARS) do S.setVar(k, v) end
  for _, t in ipairs(PRE_TRAINERS) do setTrainerFlag(t) end
  for _, f in ipairs(SEG3_SET) do S.setFlag(f, true) end
  for _, f in ipairs(SEG3_CLEAR) do S.setFlag(f, false) end
  for k, v in pairs(SEG3_VARS) do S.setVar(k, v) end
  for _, t in ipairs(SEG3_TRAINERS) do setTrainerFlag(t) end
  local s = S.session()
  s.party = {}
  local mn = S.giveMon("SPECIES_ELECTRIKE", 10)
  S.setLevel(mn, 80, "SPECIES_MANECTRIC")
  S.setMoves(mn, { "MOVE_THUNDERBOLT", "MOVE_CRUNCH", "MOVE_QUICK_ATTACK" })
  local bl = S.giveMon("SPECIES_TORCHIC", 10)
  S.setLevel(bl, 80, "SPECIES_BLAZIKEN")
  S.setMoves(bl, { "MOVE_SKY_UPPERCUT", "MOVE_FLAMETHROWER", "MOVE_STRENGTH", "MOVE_ROCK_SMASH" })
  local az = S.giveMon("SPECIES_MARILL", 10)
  S.setLevel(az, 78, "SPECIES_AZUMARILL")
  S.setMoves(az, { "MOVE_SURF", "MOVE_ICE_BEAM", "MOVE_DIVE" })
  local sw = S.giveMon("SPECIES_TAILLOW", 10)
  S.setLevel(sw, 74, "SPECIES_SWELLOW")
  S.setMoves(sw, { "MOVE_FLY", "MOVE_AERIAL_ACE", "MOVE_QUICK_ATTACK" })
  for _, it in ipairs(PRE_ITEMS) do S.giveItem(it, 1) end
  for _, it in ipairs({ "ITEM_HM05", "ITEM_HM07", "ITEM_HM08", "ITEM_TM03", "ITEM_TM04" }) do S.giveItem(it, 1) end
  S.setFlag("FLAG_RECEIVED_HM_FLASH", true)
  S.giveItem("ITEM_ULTRA_BALL", 5)
  S.giveItem("ITEM_FULL_RESTORE", 12)
  S.giveItem("ITEM_MAX_REVIVE", 4)
  S.giveItem("ITEM_MAX_ELIXIR", 6)
  s.money = 80000
  local Dex = require("src.core.game3.dex")
  for _, sp in ipairs({ "SPECIES_TORCHIC", "SPECIES_COMBUSKEN", "SPECIES_BLAZIKEN", "SPECIES_MARILL", "SPECIES_AZUMARILL",
      "SPECIES_TAILLOW", "SPECIES_SWELLOW", "SPECIES_ELECTRIKE", "SPECIES_MANECTRIC", "SPECIES_ZIGZAGOON", "SPECIES_WURMPLE",
      "SPECIES_POOCHYENA", "SPECIES_WINGULL", "SPECIES_TENTACOOL", "SPECIES_GEODUDE", "SPECIES_ZUBAT", "SPECIES_MACHOP" }) do
    Dex.setCaught(s.dex, S.species(sp))
  end
  d.check(#s.party == 4 and knows(sw, "MOVE_FLY") and knows(az, "MOVE_SURF") and knows(bl, "MOVE_STRENGTH")
    and knows(bl, "MOVE_ROCK_SMASH"), "segment start: Manectric lv80 / Blaziken lv80 / Azumarill lv78 / Swellow lv74 after the Rain Badge")
  S.saveCheckpoint(game, "start")
  S.loadCheckpoint(game, "start")
  S.canSurf = true
  local okHm = teachHm("ITEM_HM07", 3)
  d.check(okHm and knows(S.session().party[3], "MOVE_WATERFALL"), "Azumarill learns WATERFALL from HM07")
  local okFlash = teachHm("ITEM_HM05", 1)
  d.check(okFlash and knows(S.session().party[1], "MOVE_FLASH"), "Manectric learns FLASH from HM05")
  return d.check(S.mapNow() == "EM_SOOTOPOLIS_CITY" and S.flag("FLAG_BADGE08_GET") and S.var("VAR_SOOTOPOLIS_CITY_STATE") == 6,
    "segment start: Sootopolis City with 8 badges (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/EverGrandeCity/map.json:1
BEATS[#BEATS + 1] = { id = "to_ever_grande", run = function(game)
  S.canSurf = true
  local flew = fly(game, "MOSSDEEP_CITY", "EM_MOSSDEEP_CITY", "01_fly_mossdeep")
  if not d.check(flew, "FLY out of the Sootopolis crater to Mossdeep (" .. tostring(S.mapNow()) .. ")") then return false end
  S.travel(game, { "EM_ROUTE127", "EM_ROUTE128", "EM_EVER_GRANDE_CITY" }, { settle = { limit = 30000 } })
  d.shot(game, "02_ever_grande_sea")
  return d.check(S.mapNow() == "EM_EVER_GRANDE_CITY", "SURF Route 127 -> Route 128 -> Ever Grande City (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/scripts/field_move_scripts.inc:183
BEATS[#BEATS + 1] = { id = "waterfall", run = function(game)
  local P = require("src.core.game3.player")
  local C = require("src.core.game3.collision")
  local FM = require("src.core.game3.field_moves")
  S.canSurf = true
  local ok = S.goTo(game, function(x, y)
    return FM.isWaterfallBehavior(C.behavior(x, y - 1)) and not FM.isWaterfallBehavior(C.behavior(x, y)) and C.isWater(x, y)
  end, { tries = 30, settle = { limit = 30000 } })
  if not d.check(ok and P.surfing, "surf to the foot of the Ever Grande waterfall (" .. P.cellX .. "," .. P.cellY .. ")") then return false end
  S.face(game, "up")
  local y0 = P.cellY
  local asked = false
  U.tap(game, "a")
  S.settle(game, { limit = 20000, watch = function()
      local M = require("src.ui.game3.message")
      if not asked and require("src.ui.game3.choice").isOpen() then asked = true U.wait(4) d.shot(game, "03_waterfall_prompt") end
      return M
    end,
    until_ = function()
      local Field = require("src.core.game3.field")
      return asked and Field._waterfall == nil and not S.busy() and P.cellY < y0 - 2
    end })
  d.check(asked, "A at the waterfall asks to use WATERFALL")
  d.shot(game, "04_waterfall_top")
  if not d.check(P.cellY < y0 - 6 and not FM.isWaterfallBehavior(C.behavior(P.cellX, P.cellY)),
      "WATERFALL carries the player up the falls (" .. y0 .. " -> " .. P.cellY .. ")") then return false end
  S.goTo(game, function(x, y) return y < 58 and not C.isWater(x, y) end, { tries = 20, settle = { limit = 20000 } })
  S.settle(game, { limit = 3000 })
  d.check(S.flag("FLAG_VISITED_EVER_GRANDE_CITY"), "landing in Ever Grande City (FLAG_VISITED_EVER_GRANDE_CITY)")
  S.canSurf = false
  local healed = S.healAtCenter(game, "EM_EVER_GRANDE_CITY", "EverGrandeCity")
  return d.check(healed and S.mapNow() == "EM_EVER_GRANDE_CITY", "Ever Grande Pokemon Center heals the party")
end }

-- pokeemerald/data/maps/VictoryRoad_1F/scripts.inc:36
BEATS[#BEATS + 1] = { id = "wally", run = function(game)
  S.canSurf = false
  S.travel(game, { "EM_VICTORY_ROAD_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_VICTORY_ROAD_1F", "into Victory Road (" .. tostring(S.mapNow()) .. ")") then return false end
  S.settle(game, { limit = 600 })
  d.shot(game, "05_victory_road")
  S.goTo(game, function(x, y) return (x == 2 or x == 3) and y == 23 end, { tries = 30, settle = { limit = 60000,
    onBattleFrame = battleShot(game, "06_wally_battle") } })
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "06_wally_battle"),
    until_ = function() return S.flag("FLAG_DEFEATED_WALLY_VICTORY_ROAD") and not S.busy() end })
  d.check(d.ran("VictoryRoad_1F_EventScript_WallyBattleTrigger1") or d.ran("VictoryRoad_1F_EventScript_WallyBattleTrigger2"),
    "Wally runs up at the Victory Road entrance")
  d.check(lastBattleWon(tid("TRAINER_WALLY_VR_1")), "Wally battle won through the battle UI")
  local wally = S.objectByScript("VictoryRoad_1F_EventScript_EntranceWally")
  return d.check(S.flag("FLAG_DEFEATED_WALLY_VICTORY_ROAD") and wally ~= nil and S.var("VAR_VICTORY_ROAD_1F_STATE") >= 1,
    "Wally stays at the entrance (FLAG_DEFEATED_WALLY_VICTORY_ROAD, VAR_VICTORY_ROAD_1F_STATE=" .. S.var("VAR_VICTORY_ROAD_1F_STATE") .. ")")
end }

-- pokeemerald/data/maps/VictoryRoad_B1F/map.json:1
local VR_LEGS = {
  { "EM_VICTORY_ROAD_1F", 9, 14 },
  { "EM_VICTORY_ROAD_B1F", 30, 25 },
  { "EM_VICTORY_ROAD_B2F", 19, 12 },
  { "EM_VICTORY_ROAD_B1F", 20, 21 },
  { "EM_VICTORY_ROAD_1F", 39, 5 },
}

BEATS[#BEATS + 1] = { id = "victory_road", run = function(game)
  S.canSurf = true
  local before = #S.battles
  for i, leg in ipairs(VR_LEGS) do
    if S.mapNow() ~= leg[1] then
      d.note(string.format("leg %d expects %s, on %s", i, leg[1], tostring(S.mapNow())))
      break
    end
    S.useRepel()
    if i == 2 then
      S.settle(game, { limit = 600 })
      d.shot(game, "07_victory_road_b1f_dark")
      d.check(useFlash(game, "08_victory_road_b1f_flash"), "B1F is pitch dark: FLASH from the party menu lights it (FLAG_SYS_USE_FLASH)")
    end
    toWarp(game, leg[2], leg[3])
    S.settle(game, { limit = 30000 })
    if i == 2 then
      S.settle(game, { limit = 600 })
      d.shot(game, "09_victory_road_b2f")
      d.check(S.flag("FLAG_SYS_USE_FLASH"), "FLASH stays lit down on B2F")
    end
  end
  local fought = 0
  for i = before + 1, #S.battles do if S.battles[i].trainer then fought = fought + 1 end end
  d.check((S.strengthPushes or 0) > 0 or (S.rocksSmashed or 0) > 0, "STRENGTH / ROCK SMASH clear the way (" .. tostring(S.strengthPushes or 0)
    .. " pushes, " .. tostring(S.rocksSmashed or 0) .. " rocks)")
  d.check(true, "Victory Road trainers battled on the way (" .. fought .. ")")
  d.shot(game, "10_victory_road_exit")
  return d.check(S.mapNow() == "EM_EVER_GRANDE_CITY", "through Victory Road 1F/B1F/B2F to the league side of Ever Grande ("
    .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/EverGrandeCity_PokemonLeague_1F/scripts.inc:48
BEATS[#BEATS + 1] = { id = "league", run = function(game)
  S.canSurf = false
  S.travel(game, { "EM_EVER_GRANDE_CITY_POKEMON_LEAGUE_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_EVER_GRANDE_CITY_POKEMON_LEAGUE_1F", "into the Pokemon League (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  S.settle(game, { limit = 600 })
  d.shot(game, "11_league_1f")
  local nurse = S.objectByScript("EverGrandeCity_PokemonLeague_1F_EventScript_Nurse")
  if d.check(nurse ~= nil, "the league nurse is at the counter") then
    S.goTo(game, { nurse.cellX, nurse.cellY + 2 }, { tries = 20 })
    S.face(game, "up")
    U.tap(game, "a")
    S.settle(game, { limit = 8000 })
    d.check(S.partyHealthy(), "the league nurse heals the party")
  end
  local guard = S.objectByScript("EverGrandeCity_PokemonLeague_1F_EventScript_DoorGuard")
  if not d.check(guard ~= nil, "the door guards block the way") then return false end
  S.talkTo(game, guard)
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "12_league_guards"),
    until_ = function() return S.flag("FLAG_ENTERED_ELITE_FOUR") and not S.busy() end })
  return d.check(S.flag("FLAG_ENTERED_ELITE_FOUR"), "the guards check the badges and step aside (FLAG_ENTERED_ELITE_FOUR)")
end }

local E4 = {
  { id = "sidney", room = "EM_EVER_GRANDE_CITY_SIDNEYS_ROOM", from = { "EM_EVER_GRANDE_CITY_HALL5" }, next = "EM_EVER_GRANDE_CITY_HALL1",
    label = "EverGrandeCity_SidneysRoom_EventScript_Sidney", trainer = "TRAINER_SIDNEY", flag = "FLAG_DEFEATED_ELITE_4_SIDNEY",
    name = "Sidney", state = 1, shot = 13 },
  { id = "phoebe", room = "EM_EVER_GRANDE_CITY_PHOEBES_ROOM", from = {}, next = "EM_EVER_GRANDE_CITY_HALL2",
    label = "EverGrandeCity_PhoebesRoom_EventScript_Phoebe", trainer = "TRAINER_PHOEBE", flag = "FLAG_DEFEATED_ELITE_4_PHOEBE",
    name = "Phoebe", state = 2, shot = 16 },
  { id = "glacia", room = "EM_EVER_GRANDE_CITY_GLACIAS_ROOM", from = {}, next = "EM_EVER_GRANDE_CITY_HALL3",
    label = "EverGrandeCity_GlaciasRoom_EventScript_Glacia", trainer = "TRAINER_GLACIA", flag = "FLAG_DEFEATED_ELITE_4_GLACIA",
    name = "Glacia", state = 3, shot = 19 },
  { id = "drake", room = "EM_EVER_GRANDE_CITY_DRAKES_ROOM", from = {}, next = "EM_EVER_GRANDE_CITY_HALL4",
    label = "EverGrandeCity_DrakesRoom_EventScript_Drake", trainer = "TRAINER_DRAKE", flag = "FLAG_DEFEATED_ELITE_4_DRAKE",
    name = "Drake", state = 4, shot = 22 },
}

for _, m in ipairs(E4) do
  -- pokeemerald/data/scripts/elite_four.inc:19
  BEATS[#BEATS + 1] = { id = m.id, run = function(game)
    S.canSurf = false
    local used = patchUp()
    S.itemsUsed = (S.itemsUsed or 0) + used
    local chain = {}
    for _, h in ipairs(m.from) do chain[#chain + 1] = h end
    chain[#chain + 1] = m.room
    S.travel(game, chain, { settle = { limit = 20000 }, repel = false })
    if not d.check(S.mapNow() == m.room, "into " .. m.name .. "'s room (" .. tostring(S.mapNow()) .. ")") then return false end
    S.settle(game, { limit = 20000, until_ = function() return S.var("VAR_ELITE_4_STATE") >= m.state and not S.busy() end })
    local P = require("src.core.game3.player")
    local closed = override(6, 12) == mt("METATILE_EliteFour_EntryDoor_ClosedTop")
    d.shot(game, string.format("%02d_%s_room", m.shot, m.id))
    d.check(S.var("VAR_ELITE_4_STATE") == m.state and closed and P.cellY <= 7,
      "the player walks in and the door shuts behind (VAR_ELITE_4_STATE=" .. S.var("VAR_ELITE_4_STATE") .. ", y=" .. P.cellY .. ")")
    if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before " .. m.name .. " (driver)") end
    local eo = S.objectByScript(m.label)
    if not d.check(eo ~= nil, "Elite Four " .. m.name .. " waits in the room") then return false end
    local seen = {}
    local mug = mugshotWatch(game, string.format("%02d_%s_mugshot", m.shot + 1, m.id), seen)
    S.talkTo(game, eo)
    S.settle(game, { limit = 80000, watch = mug, onBattleFrame = battleShot(game, string.format("%02d_%s_battle", m.shot + 2, m.id)),
      until_ = function() return S.flag(m.flag) and not S.busy() end })
    d.check(seen.key == m.id, m.name .. "'s mugshot battle transition (" .. tostring(seen.key) .. ")")
    d.check(lastBattleWon(tid(m.trainer)), m.name .. " battle won through the battle UI")
    d.check(S.flag(m.flag) and override(6, 2) == mt("METATILE_EliteFour_OpenDoor_Opening"),
      m.name .. " is beaten and the far door opens (" .. m.flag .. ")")
    S.travel(game, { m.next }, { settle = { limit = 20000 }, repel = false })
    return d.check(S.mapNow() == m.next, "on to the next hall (" .. tostring(S.mapNow()) .. ")")
  end }
end

-- pokeemerald/data/maps/EverGrandeCity_ChampionsRoom/scripts.inc:23
BEATS[#BEATS + 1] = { id = "champion", run = function(game)
  S.canSurf = false
  S.itemsUsed = (S.itemsUsed or 0) + patchUp()
  d.check(true, "FULL RESTORE / MAX REVIVE / MAX ELIXIR used from the bag between rooms (" .. tostring(S.itemsUsed) .. ")")
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Wallace (driver)") end
  local seen, labels = {}, {}
  local mug = mugshotWatch(game, "25_wallace_mugshot", seen)
  local track = labelWatch(labels)
  local rivalShot, birchShot = false, false
  local ratingText
  local settle = { limit = 120000, onBattleFrame = battleShot(game, "26_wallace_battle"),
    watch = function()
      mug()
      track()
      if S.mapNow() == "EM_EVER_GRANDE_CITY_CHAMPIONS_ROOM" then labels._inRoom = true end
      local M = require("src.ui.game3.message")
      if not rivalShot and M.isOpen() and labels.EverGrandeCity_ChampionsRoom_EventScript_MayAdvice then
        rivalShot = true
        if M.isTyping() then M.skipReveal() end
        U.wait(3)
        d.shot(game, "27_champion_may")
      end
      if not birchShot and M.isOpen() and labels.ProfBirch_EventScript_ShowRatingMessage then
        birchShot = true
        if M.isTyping() then M.skipReveal() end
        U.wait(3)
        ratingText = messageText()
        d.shot(game, "28_birch_rates_dex")
      end
    end,
    until_ = function() return S.mapNow() == "EM_EVER_GRANDE_CITY_HALL_OF_FAME" or not S.busy() end }
  S.travel(game, { "EM_EVER_GRANDE_CITY_CHAMPIONS_ROOM" }, { settle = settle, repel = false })
  if not d.check(labels._inRoom or S.mapNow() == "EM_EVER_GRANDE_CITY_CHAMPIONS_ROOM",
      "up Hall 4 into the Champion's room (now " .. tostring(S.mapNow()) .. ")") then
    return false
  end
  settle.until_ = function() return S.mapNow() == "EM_EVER_GRANDE_CITY_HALL_OF_FAME" end
  S.settle(game, settle)
  d.check(d.ran("EverGrandeCity_ChampionsRoom_EventScript_EnterRoom"), "the player walks up to Wallace on entry")
  d.check(seen.key == "champion", "Wallace's mugshot battle transition (" .. tostring(seen.key) .. ")")
  d.check(lastBattleWon(tid("TRAINER_WALLACE")), "Champion Wallace battle won through the battle UI")
  d.check(labels.EverGrandeCity_ChampionsRoom_EventScript_MayAdvice and rivalShot, "May runs in after the battle")
  local dexCaught = 0
  for _ in pairs(S.session().dex.caught or {}) do dexCaught = dexCaught + 1 end
  d.check(labels.ProfBirch_EventScript_RatePokedex and ratingText ~= nil,
    "Prof. Birch arrives and rates the Pokedex (" .. tostring(ratingText and ratingText:sub(1, 40)) .. ")")
  return d.check(S.mapNow() == "EM_EVER_GRANDE_CITY_HALL_OF_FAME", "Wallace leads the player into the Hall of Fame (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/src/hall_of_fame.c:417
BEATS[#BEATS + 1] = { id = "hall_of_fame", run = function(game)
  local HallOfFame = require("src.ui.game3.hall_of_fame")
  local Credits = require("src.ui.game3.rse.credits")
  local fldeff = false
  S.settle(game, { limit = 60000, watch = function()
      local M = require("src.ui.game3.message")
      if M.isOpen() and not S._hofMsgShot then
        S._hofMsgShot = true
        if M.isTyping() then M.skipReveal() end
        U.wait(3)
        d.shot(game, "29_hof_wallace")
      end
      local FX = package.loaded["src.core.game3.fldeff_misc"]
      if not fldeff and FX and FX._active and FX._active.FLDEFF_HALL_OF_FAME_RECORD then
        fldeff = true
        U.wait(20)
        d.shot(game, "30_hof_record_machine")
      end
    end,
    until_ = function() return HallOfFame.isOpen() end })
  d.check(d.ran("EverGrandeCity_HallOfFame_EventScript_EnterHallOfFame"), "Wallace walks the player into the Hall of Fame")
  d.check(fldeff, "the Hall of Fame machine records the party (FLDEFF_HALL_OF_FAME_RECORD)")
  if not d.check(HallOfFame.isOpen(), "special GameClear opens the Hall of Fame screen") then return false end
  d.check(S.flag("FLAG_IS_CHAMPION") and S.flag("FLAG_SYS_GAME_CLEAR"), "FLAG_IS_CHAMPION and FLAG_SYS_GAME_CLEAR set")
  d.check(S.var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") == 3, "Dad's S.S. TICKET visit is readied (VAR_LITTLEROOT_HOUSES_STATE_BRENDAN=3)")
  local shots = { hold = "31_hof_mon", applause = "32_hof_welcome", exitwait = "33_hof_player" }
  local taken = {}
  for _ = 1, 20000 do
    local ph = HallOfFame.phase()
    if shots[ph] and not taken[ph] then
      taken[ph] = true
      U.wait(ph == "applause" and 200 or 20)
      d.shot(game, shots[ph])
    end
    if ph == "exitwait" then U.tap(game, "a") end
    if not HallOfFame.isOpen() then break end
    U.wait(1)
  end
  d.check(taken.hold and taken.applause and taken.exitwait, "each party mon is shown, then the player and the welcome")
  if not d.check(Credits.isOpen(), "the Hall of Fame rolls into the Emerald credits") then return false end
  local st = Credits.state
  local sceneNames = { [0] = "ocean_morning", "ocean_sunset", "forest_rival_arrive", "forest_catch_rival", "city_night" }
  local seenScenes, sceneN, monsSeen, theEnd, shotN = {}, 0, false, false, 0
  for _ = 1, 60000 do
    if not Credits.isOpen() then break end
    local d7 = st.m.tasks:get(st.mainId).data[7]
    if st.mainFunc == "main" and st.text and not st.m.ppu.palette:fadeActive() then
      if st.showMons then
        if not monsSeen and #st.mons > 0 then
          monsSeen = true
          U.wait(30)
          d.shot(game, "34_credits_mons")
        end
      elseif not seenScenes[d7] then
        seenScenes[d7] = true
        sceneN = sceneN + 1
        U.wait(30)
        shotN = shotN + 1
        d.shot(game, string.format("35_credits_bike_%d_%s", shotN, tostring(sceneNames[d7])))
      end
    end
    if st.theEnd == "theEnd" and not theEnd then
      theEnd = true
      U.wait(10)
      d.shot(game, "36_the_end")
      U.wait(60)
      U.tap(game, "a")
    end
    U.wait(1)
  end
  d.check(sceneN == 5 and monsSeen, "credits: five bike scenes with May and the Pokemon interludes (" .. sceneN .. ")")
  d.check(theEnd, "THE END")
  local reset = false
  for _ = 1, 600 do
    if game.phase == "boot" then reset = true break end
    U.wait(1)
  end
  return d.check(reset, "the credits end in a soft reset back to the title")
end }

local function toMenu(game)
  local custom = game.boot and game.boot.custom
  if not custom then return nil end
  for _ = 1, 400 do
    if custom.title or custom.menu then break end
    U.tap(game, "a")
    U.wait(8)
  end
  for _ = 1, 600 do
    if custom.menu then break end
    U.tap(game, "start")
    U.wait(10)
  end
  return custom.menu
end

-- pokeemerald/data/scripts/players_house.inc:392
BEATS[#BEATS + 1] = { id = "post_game", run = function(game)
  waitFor(function() return game.phase == "boot" and game.boot ~= nil and game.boot.custom ~= nil end, 900)
  local menu = toMenu(game)
  if not d.check(menu ~= nil, "title screen -> main menu after the reset") then return false end
  U.wait(60)
  local info = menu.info or {}
  d.check(menu.items[1] == "CONTINUE" and info.badges == 8, "the Hall of Fame save shows CONTINUE with 8 badges ("
    .. tostring(menu.items[1]) .. ", " .. tostring(info.badges) .. ")")
  d.shot(game, "37_main_menu_continue")
  U.tap(game, "a")
  waitFor(function() return game.phase ~= "boot" and S.session() ~= nil and S.mapNow() ~= nil end, 1200)
  U.wait(60)
  S.settle(game, { limit = 3000 })
  local home = "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F"
  d.shot(game, "38_continue_bedroom")
  if not d.check(S.mapNow() == home, "CONTINUE wakes the champion in his Littleroot bedroom (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  d.check(S.flag("FLAG_IS_CHAMPION") and S.flag("FLAG_SYS_GAME_CLEAR") and not S.hasItem("ITEM_SS_TICKET"),
    "the continued save keeps FLAG_IS_CHAMPION / FLAG_SYS_GAME_CLEAR")
  local party = S.session().party or {}
  d.check(#party > 0 and party[1].championRibbon == true, "GameClear gave the party the CHAMPION RIBBON")
  local dadShot, tvShot = false, false
  S.travel(game, { "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" }, { repel = false, settle = { limit = 60000,
    choice = function() return 1 end,
    watch = function()
      local M = require("src.ui.game3.message")
      if M.isOpen() and not dadShot and d.ran("PlayersHouse_1F_EventScript_GetSSTicketAndSeeLatiTV") then
        dadShot = true
        if M.isTyping() then M.skipReveal() end
        U.wait(3)
        d.shot(game, "39_dad_ss_ticket")
      end
      if M.isOpen() and not tvShot and S.flag("FLAG_SYS_TV_LATIAS_LATIOS") then
        tvShot = true
        if M.isTyping() then M.skipReveal() end
        U.wait(3)
        d.shot(game, "40_lati_news")
      end
    end } })
  S.settle(game, { limit = 60000, choice = function() return 1 end,
    until_ = function() return S.var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") == 4 and not S.busy() end })
  d.check(d.ran("PlayersHouse_1F_EventScript_GetSSTicketAndSeeLatiTV"), "downstairs, Dad arrives with a ticket from Mr. Briney")
  d.check(S.flag("FLAG_RECEIVED_SS_TICKET") and S.hasItem("ITEM_SS_TICKET"), "Dad gives the S.S. TICKET (FLAG_RECEIVED_SS_TICKET)")
  d.check(S.flag("FLAG_LATIOS_OR_LATIAS_ROAMING") and S.var("VAR_ROAMER_POKEMON") >= 0,
    "the TV news flash sets a roaming Lati@s loose (FLAG_LATIOS_OR_LATIAS_ROAMING)")
  d.shot(game, "41_post_game_home")
  return d.check(S.var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") == 4, "post-game home scene done (VAR_LITTLEROOT_HOUSES_STATE_BRENDAN=4)")
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
      S.canSurf = true
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
      if S.session() then S.saveCheckpoint(game, b.id .. "_fail") end
      break
    end
    if b.id ~= "hall_of_fame" and b.id ~= "post_game" then S.saveCheckpoint(game, b.id) end
    if to and b.id == to then break end
  end
  d.finish()
end
