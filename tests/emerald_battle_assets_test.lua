package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_battle_assets_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local raw = f:read("*a")
f:close()
if raw:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_battle_assets_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local ok, ffi = pcall(require, "ffi")
local Rom = require("src.import.gba.rom")
local Versions = require("src.import.gba.versions")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
Versions.select("emerald")
local rom = setmetatable({ _raw = raw, size = #raw, _cdata = ok and ffi.cast("const uint8_t*", raw) or nil }, Rom)

local files = {}
local cache = {
  write = function(_, rel, data) files[rel] = data; return true end,
  exists = function(_, rel) return files[rel] ~= nil end,
  read = function(_, rel) return files[rel] end,
}
local ROOT = "data/generated/gba"
local function load(rel)
  local src = files[ROOT .. "/" .. rel]
  if not src then return nil end
  return assert(loadstring(src))()
end

local function run(name)
  local M = require("src.import.gba." .. name)
  local okR, res = pcall(M.run, rom, cache, { cacheRoot = ROOT, strict = true, force = true })
  check(okR, name .. " runs strict on Emerald: " .. tostring(okR or res))
  for _, rel in ipairs(M.REQUIRED or {}) do
    check(files[ROOT .. "/" .. rel] ~= nil, name .. " wrote required " .. rel)
  end
  return res
end

run("battle_anim_extract")
local pack = load("pokemon/battle_anims/pack.lua")
check(pack ~= nil, "anim pack written")
if pack then
  local Names = require("src.import.gba.anim_names_emerald")
  local hexTasks, noCb, noTmpl, tasks = 0, 0, 0, {}
  local function scan(list)
    for _, op in ipairs(list or {}) do
      if op.op == "createvisualtask" or op.op == "createsoundtask" then
        if tostring(op.task):match("^0x") then hexTasks = hexTasks + 1 end
        tasks[op.task] = true
      elseif op.op == "createsprite" then
        if not op.callback then noCb = noCb + 1 end
        if not op.template then noTmpl = noTmpl + 1 end
      end
    end
  end
  for _, s in pairs(pack.moves) do scan(s) end
  for _, s in pairs(pack.labels) do scan(s) end
  for _, k in ipairs({ "general", "special", "status" }) do
    for _, s in pairs(pack[k]) do scan(s) end
  end
  eq(hexTasks, 0, "0 unresolved task names")
  eq(noCb, 0, "0 unresolved sprite callbacks")
  eq(noTmpl, 0, "0 unresolved sprite templates")
  local moves = 0
  for _ in pairs(pack.moves) do moves = moves + 1 end
  eq(moves, 355, "355 move scripts")
  eq(pack.generalNames[4], "POKEBLOCK_THROW", "general anim names are emerald's")
  check(tasks.LoadBaitGfx and tasks.FreeBaitGfx, "pokeblock gfx tasks carry the FR canonical names")
  check(tasks.IsBallBlockedByTrainer and tasks.ThrowBall_StandingTrainer, "emerald-only ball tasks are named")
  for _, name in ipairs(Names.gameOnly.tasks) do
    check(tasks[(name:gsub("^AnimTask_", ""))], "game-only task " .. name .. " is used by a script")
  end
  check(pack.tags.POKEBLOCK ~= nil, "POKEBLOCK sprite sheet baked")
  check(pack.statMask and #pack.statMask.pals == 8, "8 stat change palettes")
  local bgs = 0
  for k in pairs(pack.animBgs) do if type(k) == "number" then bgs = bgs + 1 end end
  eq(bgs, 27, "27 anim backgrounds")
  check(pack.animBgs.SURF_PLAYER and pack.animBgs.CURSE and pack.animBgs.FOG, "named anim backgrounds")
end

run("battle_ai_extract")
local ai = load("battle_ai/pack.lua")
check(ai and #ai.table == 32, "32 AI script entries")
if ai then
  local seen = {}
  for _, body in pairs(ai.scripts) do
    for _, ir in ipairs(body) do seen[ir.op] = true end
  end
  for _, op in ipairs({ "if_target_is_ally", "is_of_type", "check_ability", "if_flash_fired", "if_holds_item" }) do
    check(seen[op], "emerald AI op " .. op .. " decoded")
  end
end

run("battle_chrome_extract")
local chrome = load("pokemon/battle/manifest.lua")
check(chrome and chrome.layout == "rse", "rse chrome manifest")
if chrome then
  eq(#(files[ROOT .. "/pokemon/battle/textbox.rgba"] or ""), chrome.textboxW * chrome.textboxH * 4, "textbox size")
  eq(chrome.environments[0], "grass", "environment 0")
  eq(chrome.environments[9], "plain", "environment 9")
  for _, key in ipairs(chrome.scenes) do
    check(files[ROOT .. "/pokemon/battle/terrain_" .. key .. ".rgba"], "scene " .. key .. " baked")
  end
  eq(#chrome.scenes, 13, "13 scenes")
  eq(chrome.elementsTiles, 118, "118 healthbox element tiles")
  eq(#chrome.windows.normal, 24, "24 normal battle windows")
end

run("battle_transition_extract")
local tr = load("pokemon/battle_transition/manifest.lua")
check(tr and tr.layout == "rse", "rse transition manifest")
if tr then
  eq(tr.ids.AQUA, 17, "transition 17 is AQUA on Emerald")
  eq(tr.ids.SPIRAL, nil, "no SPIRAL transition on Emerald")
  eq(tr.ids.FRONTIER_CIRCLES_SYMMETRIC_SPIRAL_IN_SEQ, 41, "last transition id")
  eq(tr.assets.rayquaza.tiles, 938, "rayquaza tileset tiles")
  eq(tr.assets.rayquaza.w * tr.assets.rayquaza.h, #files[ROOT .. "/pokemon/battle_transition/rayquaza.idx"],
    "rayquaza index map")
  eq(tr.mugshotTrainerPics[5], 54, "champion mugshot pic")
  for _, key in ipairs(tr.mugshots) do
    check(files[ROOT .. "/pokemon/battle_transition/vsbar_" .. key .. "_female.rgba"], "vsbar " .. key)
  end
end

run("ball_open_extract")
check(load("pokemon/battle/ball_open/manifest.lua") ~= nil, "ball open manifest")

run("battle_rse_data_extract")
local data = load("pokemon/battle/rse_data.lua")
check(data ~= nil, "rse battle data")
if data then
  eq(#data.pickupItems, 18, "18 pickup items")
  eq(#data.rarePickupItems, 11, "11 rare pickup items")
  eq(data.pickupProbabilities[9], 98, "pickup probability tail")
  eq(data.stevenMons[1].speciesName, "SPECIES_METANG", "Steven mon 1")
  eq(data.stevenMons[1].level, 42, "Steven mon level")
  eq(data.stevenMons[3].speciesName, "SPECIES_AGGRON", "Steven mon 3")
  eq(#data.environmentToType, 10, "environment to type")
end

Versions.select("firered")
T.finish("emerald_battle_assets_test")
