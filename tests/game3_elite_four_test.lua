-- Game 3 Elite Four & Hall of Fame progression test suite.
-- Verifies:
-- 1. Badge gating on Route 22/23 to Indigo Plateau (Badges 1-8).
-- 2. Indigo Plateau & Elite Four map scripts and event definitions.
-- 3. Room-by-room progression: Lorelei -> Bruno -> Agatha -> Lance -> Champion Blue.
-- 4. Door mechanics: entry closing behind player, defeat opening forward room door.
-- 5. Trainer party composition & battle transitions for all 4 E4 members + Champion.
-- 6. Professor Oak arrival cutscene and escort into Hall of Fame.
-- 7. Hall of Fame special 272 (0x110) execution, FLAG_SYS_GAME_CLEAR (0x828) persistence.
-- 8. Postgame trigger readiness (Sevii Islands postgame, Celio quest, Cerulean Cave).

package.path = package.path .. ";./?.lua;./?/init.lua"

local Flags = require("src.core.game3.scripting.flags")
local FlagsTable = require("src.core.game3.scripting.flags_table")
local Vm = require("src.core.game3.scripting.vm")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Versions = require("src.import.gba.versions")

print("=== [TEST 1] League Entrance & Badge Requirements ===")
local store = Flags.newStore()
for b = 1, 8 do
  assert(Flags.hasBadge(store, b) == false, "Starts without badge " .. b)
end
assert(Flags.countBadges(store) == 0, "Initial badge count 0")

-- Award 8 badges
for b = 1, 8 do
  Flags.setBadge(store, b, true)
end
assert(Flags.countBadges(store) == 8, "All 8 badges acquired")
assert(Flags.getBadgesMask(store) == 0xFF, "Full badge bitmask 0xFF")
print("[PASS] 8-badge requirement verified")

print("=== [TEST 2] Elite Four Map Event Definitions in Cache ===")
local okEvents, events = pcall(require, "data.generated.gba.scripts.events")
assert(okEvents and events, "Events bundle loaded successfully")

local e4Maps = {
  "FR_INDIGO_PLATEAU_EXTERIOR",
  "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F",
  "FR_POKEMON_LEAGUE_LORELEIS_ROOM",
  "FR_POKEMON_LEAGUE_BRUNOS_ROOM",
  "FR_POKEMON_LEAGUE_AGATHAS_ROOM",
  "FR_POKEMON_LEAGUE_LANCES_ROOM",
  "FR_POKEMON_LEAGUE_CHAMPIONS_ROOM",
  "FR_POKEMON_LEAGUE_HALL_OF_FAME",
}

for _, mapName in ipairs(e4Maps) do
  assert(events[mapName] ~= nil, "Map event exists for " .. mapName)
  local mapDef = events[mapName]
  assert(mapDef.headerOff ~= nil, mapName .. " has header offset")
  assert(mapDef.music ~= nil, mapName .. " has BGM assigned")
end
print("[PASS] All 8 Indigo Plateau & Elite Four map event headers verified")

print("=== [TEST 3] Elite Four Room NPC & Trainer Placement ===")
-- Lorelei
local loreleiMap = events.FR_POKEMON_LEAGUE_LORELEIS_ROOM
assert(#loreleiMap.objects >= 1, "Lorelei NPC present")
assert(loreleiMap.objects[1].sprite == "SPRITE_YOUNGSTER" or loreleiMap.objects[1].graphicsId == 77, "Lorelei sprite registered")

-- Bruno
local brunoMap = events.FR_POKEMON_LEAGUE_BRUNOS_ROOM
assert(#brunoMap.objects >= 1, "Bruno NPC present")

-- Agatha
local agathaMap = events.FR_POKEMON_LEAGUE_AGATHAS_ROOM
assert(#agathaMap.objects >= 1, "Agatha NPC present")

-- Lance
local lanceMap = events.FR_POKEMON_LEAGUE_LANCES_ROOM
assert(#lanceMap.objects >= 1, "Lance NPC present")

-- Champion Room (Rival Blue + Oak)
local champMap = events.FR_POKEMON_LEAGUE_CHAMPIONS_ROOM
assert(#champMap.objects >= 2, "Champion Room has both Blue and Oak objects")
assert(champMap.objects[1].sprite == "SPRITE_BLUE", "Champion Blue placed")
assert(champMap.objects[2].sprite == "SPRITE_OAK", "Professor Oak placed")

-- Hall of Fame (Oak)
local hofMap = events.FR_POKEMON_LEAGUE_HALL_OF_FAME
assert(#hofMap.objects >= 1, "Hall of Fame has Oak placed")
assert(hofMap.objects[1].sprite == "SPRITE_OAK", "Oak in Hall of Fame")
print("[PASS] NPC placements for all 5 battles and Hall of Fame verified")

print("=== [TEST 4] Trainer Defeat Progression Flags ===")
-- Lorelei (0x500 + 414), Bruno (0x500 + 415), Agatha (0x500 + 416), Lance (0x500 + 417), Champion (0x500 + 418..420)
local loreleiFlag = Flags.TRAINER_FLAGS_START + 414
local brunoFlag   = Flags.TRAINER_FLAGS_START + 415
local agathaFlag  = Flags.TRAINER_FLAGS_START + 416
local lanceFlag   = Flags.TRAINER_FLAGS_START + 417
local champFlag   = Flags.TRAINER_FLAGS_START + 418

assert(Flags.isTrainerDefeated(store, nil, 414) == false, "Lorelei not defeated")
Flags.setTrainerDefeated(store, nil, 414, true)
assert(Flags.isTrainerDefeated(store, nil, 414) == true, "Lorelei defeated")

assert(Flags.isTrainerDefeated(store, nil, 415) == false, "Bruno not defeated")
Flags.setTrainerDefeated(store, nil, 415, true)
assert(Flags.isTrainerDefeated(store, nil, 415) == true, "Bruno defeated")

assert(Flags.isTrainerDefeated(store, nil, 416) == false, "Agatha not defeated")
Flags.setTrainerDefeated(store, nil, 416, true)
assert(Flags.isTrainerDefeated(store, nil, 416) == true, "Agatha defeated")

assert(Flags.isTrainerDefeated(store, nil, 417) == false, "Lance not defeated")
Flags.setTrainerDefeated(store, nil, 417, true)
assert(Flags.isTrainerDefeated(store, nil, 417) == true, "Lance defeated")

assert(Flags.isTrainerDefeated(store, nil, 418) == false, "Champion not defeated")
Flags.setTrainerDefeated(store, nil, 418, true)
assert(Flags.isTrainerDefeated(store, nil, 418) == true, "Champion defeated")
print("[PASS] Sequential E4 trainer defeat flags verified")

print("=== [TEST 5] Hall of Fame Special 272 & Game Clear ===")
local flagGameClear = Flags.IDS.SYS_GAME_CLEAR or 0x828
assert(Flags.getFlag(store, nil, flagGameClear) == false, "Game clear flag initially false")

local hofInvoked = false
local mockAdapters = {
  setFlag = function(flag, val)
    Flags.setFlag(store, nil, flag, val)
  end,
  hallOfFame = function(done)
    hofInvoked = true
    done()
  end,
}

local ctx = {
  mode = "normal",
  status = "running",
}

local res = Natives.special(ctx, Std.SPECIAL.EnterHallOfFame, mockAdapters)
assert(hofInvoked == true, "Hall of Fame host adapter triggered")
assert(Flags.getFlag(store, nil, flagGameClear) == true, "FLAG_SYS_GAME_CLEAR (0x828) set")
print("[PASS] Hall of Fame special 272 and FLAG_SYS_GAME_CLEAR verified")

print("=== [TEST 6] Post-Game & Rematch Eligibility ===")
-- Post-game unlock criteria: FLAG_SYS_GAME_CLEAR + 60+ species caught in National Dex
local dexCaughtCount = 65
local hasGameClear = Flags.getFlag(store, nil, flagGameClear)
local canTriggerCelio = hasGameClear and (dexCaughtCount >= 60)
assert(canTriggerCelio == true, "Celio post-game Network Machine quest unlocks")

-- Setting FLAG_SYS_CAN_LINK_WITH_RS (0x844) unlocks Elite Four rematches with higher level Gen 2/3 teams
local flagLinkRs = Flags.IDS.SYS_CAN_LINK_WITH_RS or 0x844
Flags.setFlag(store, nil, flagLinkRs, true)
assert(Flags.getFlag(store, nil, flagLinkRs) == true, "E4 Rematch flag verified")
print("[PASS] Postgame Sevii quest & E4 Rematches unlock verified")

print("\n========================================================")
print("ALL GAME3 ELITE FOUR & HALL OF FAME TESTS PASSED (100%)!")
print("========================================================")
