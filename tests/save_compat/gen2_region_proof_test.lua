package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveConvert = require("src.save_convert.SaveConvert")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2State = require("src.save_convert.Gen2State")
local Syms = require("src.save_convert.Gen2Syms")
local Layout = require("src.save_convert.Gen2Layout")
local Core = require("src.save_convert.gen2_state.core")

local HOME = os.getenv("HOME") or ""
local ROOTS = {
  gold = os.getenv("GOLD_CACHE") or HOME .. "/Library/Application Support/LOVE/gold-bsa0925-gameplay/gold",
  silver = os.getenv("SILVER_CACHE") or HOME .. "/Library/Application Support/LOVE/pokemon-love2d/silver",
  crystal = os.getenv("CRYSTAL_CACHE") or HOME .. "/Library/Application Support/LOVE/crystal-bsa0925-gameplay/crystal",
}
local DATA = {}
for version, dir in pairs(ROOTS) do DATA[version] = SaveConvert.gen2DataFromDir(dir) end

local function scanRows()
  local out = {}
  for _, row in ipairs(Core.coverage) do
    if row.mode == "static" then
      local labels = {}
      for k, v in pairs(row) do if k == "both" or k == "gs" or k == "crystal" then labels[#labels + 1] = tostring(v[1] or v.abs) end end
      for _, pattern in ipairs(row.scan or {}) do
        local pipe = io.popen("grep -rIn --include=*.lua -iE '\\.(" .. pattern .. ")[A-Za-z_]* *=[^=]' src 2>/dev/null | grep -v 'src/save_convert' | grep -v 'game3' | grep -v 'src/import' | head -5")
        local hits = pipe:read("*a")
        pipe:close()
        check(hits == "", ("static row %s: the engine never assigns *%s* -- %s"):format(labels[1] or "?", pattern, hits:gsub("\n", " | ")))
      end
      check(type(row.why) == "string" and row.why ~= "", "static row names its reason")
    end
  end
end
scanRows()

if not (DATA.gold and DATA.silver and DATA.crystal) then
  print("SKIP mutation proof: no extracted Gen 2 caches on this machine")
  T.finish()
  return
end

local EngineSave = require("src.core.gen2.Save")
local Mon = require("src.battle.gen2.Mon")

local function lists(version)
  local d = DATA[version]
  local sp, maps, mv = {}, {}, {}
  for id, def in pairs(d.pokemon) do
    if type(def) == "table" and def.index and def.index <= 251 and def.baseStats then sp[#sp + 1] = id end
  end
  for id, def in pairs(d.maps) do
    if type(def) == "table" and def.group and def.width and def.width >= 4 and def.height >= 4 and def.blocks
        and def.objectEventsAddr and def.objects and #def.objects > 0 then
      maps[#maps + 1] = id
    end
  end
  table.sort(sp); table.sort(maps)
  return sp, maps
end

local firstItem

local function base(version)
  local sp, maps = lists(version)
  local d = DATA[version]
  local save = EngineSave.newGame({ playerName = "ASH", rivalName = "GARY", trainerId = 12345, gender = "male" })
  save.version = version
  save.rtc = { day = 5, hour = 6, minute = 7 }
  local fixed = function() return { attack = 5, defense = 6, speed = 7, special = 8 } end
  save.party = { Mon.new(d, sp[1], 20, { dvs = fixed() }), Mon.new(d, sp[2], 30, { dvs = fixed() }) }
  for _, m in ipairs(save.party) do m.ot = "ASH"; m.otId = 12345 end
  local first = firstItem(d, "ITEM", 1)
  save.inventory = { [first] = 1 }
  save.bagOrder = { first }
  save.position = { map = maps[1], x = 3, y = 3, facing = "down" }
  save.options = { textSpeed = "MID", battleScene = true, battleStyle = "SHIFT", sound = "MONO", frame = 1, print = "NORMAL", menuAccount = true }
  save.playTime = { hours = 1, minutes = 2, seconds = 3, frames = 4 }
  return save, sp, maps
end

local function export(save, version)
  local out, err = Gen2Save.encode(save, version, nil, DATA[version])
  assert(out, err)
  return out
end

local function changed(a, b)
  local out = {}
  for i = 1, #a do if a:byte(i) ~= b:byte(i) then out[#out + 1] = i - 1 end end
  return out
end

firstItem = function(d, pocket, skip)
  local names = {}
  for id, def in pairs(d.items) do if type(def) == "table" and def.pocket == pocket then names[#names + 1] = id end end
  table.sort(names)
  return names[skip or 1]
end

local function firstTm(d)
  local names = {}
  for id, def in pairs(d.items) do if type(def) == "table" and def.tmNumber == 3 then names[#names + 1] = id end end
  table.sort(names)
  return names[1]
end

local MUT = {
  ["player.id"] = function(s) s.player.id = 777 end,
  ["player.name"] = function(s) s.player.name = "RED" end,
  ["mom.name"] = function(s) s.mom.name = "MAMA" end,
  ["rival.name"] = function(s) s.rival.name = "BLUE" end,
  playTime = function(s) s.playTime.hours = 5; s.playTime.seconds = 9 end,
  ["position.x"] = function(s) s.position.x = 5 end,
  ["position.y"] = function(s) s.position.y = 5 end,
  ["position.facing"] = function(s) s.position.facing = "left" end,
  ["position.map"] = function(s, v, sp, maps) s.position.map = maps[2]; s.position.x = 2; s.position.y = 2 end,
  variableSprites = function(s) s.variableSprites = { [3] = 9 } end,
  engineFlags = function(s) s.engineFlags = { [0] = true, [11] = true, [50] = true } end,
  ["player.money"] = function(s) s.player.money = 98765 end,
  ["mom.savedMoney"] = function(s) s.mom.savedMoney = 4000; s.mom.active = true; s.mom.savingMoney = true end,
  ["mom.active"] = function(s) s.mom.active = true end,
  ["mom.savingMoney"] = function(s) s.mom.savingMoney = true; s.mom.active = true end,
  ["player.coins"] = function(s) s.player.coins = 321 end,
  ["player.badges"] = function(s) s.player.badges = { ZEPHYR = true } end,
  ["player.kantoBadges"] = function(s) s.player.kantoBadges = { BOULDER = true } end,
  inventory = function(s, v) local d = DATA[v]; local id = firstItem(d, "ITEM", 2); s.inventory[id] = 5; s.bagOrder[#s.bagOrder + 1] = id
    local tm = firstTm(d); if tm then s.inventory[tm] = 2; s.bagOrder[#s.bagOrder + 1] = tm end end,
  bagOrder = function(s, v) local d = DATA[v]; local a, b = firstItem(d, "ITEM", 2), firstItem(d, "ITEM", 3)
    s.inventory = { [a] = 1, [b] = 1 }; s.bagOrder = { b, a } end,
  cartBag = function(s, v) local a = firstItem(DATA[v], "ITEM", 2); s.inventory = { [a] = 1 }; s.bagOrder = { a }
    s.cartBag = { ITEM = { { a, 1 }, { a, 0 } }, KEY_ITEM = {}, BALL = {} } end,
  pcItems = function(s, v) local a = firstItem(DATA[v], "ITEM", 2); s.pcItems = { [a] = 9 }; s.pcOrder = { a } end,
  pcOrder = function(s, v) local a, b = firstItem(DATA[v], "ITEM", 2), firstItem(DATA[v], "ITEM", 3)
    s.pcItems = { [a] = 1, [b] = 1 }; s.pcOrder = { b, a } end,
  playerState = function(s) s.playerState = "bike" end,
  mapScenes = function(s) for id in pairs(Layout.goldSilver.sceneVars) do s.mapScenes[id] = 3 break end
    local L = Layout.crystal; for id in pairs(L.sceneVars) do s.mapScenes[id] = 3 break end end,
  events = function(s) s.events = { [5] = 255 } end,
  mapObjectMasks = function(s, v)
    local def = DATA[v].maps[s.position.map]
    local masks = assert(require("src.save_convert.Gen2MapContext").objectMaskBytes(s.position.map, def, v, s))
    local overrides = {}
    for i in ipairs(def.objects) do overrides[i] = masks[(v == "crystal" and 1 or 2) + i] == 0 end
    s.mapObjectMasks = { map = s.position.map, masks = overrides }
  end,
  currentBox = function(s) s.currentBox = 4 end,
  boxNames = function(s) s.boxNames = { "ZZZ" } end,
  ["mom.whichItem"] = function(s) s.mom.whichItem = 3 end,
  ["mom.triggerBalance"] = function(s) s.mom.triggerBalance = 5000 end,
  party = function(s) s.party[1].level = 77 end,
  ["pokedex.caught"] = function(s, v, sp) s.pokedex.caught[sp[1]] = true end,
  ["pokedex.seen"] = function(s, v, sp) s.pokedex.seen[sp[1]] = true end,
  unownDex = function(s) s.unownDex = { 7 } end,
  firstUnownSeen = function(s) s.firstUnownSeen = 7 end,
  scriptMem = function(s, v) s.scriptMem = { [0xD9F2] = 4 } end,
}

local function offsets(spec, S, L)
  if spec.abs then return spec.abs, spec.abs + spec.len end
  local from = S[spec[1]]
  if not from then return nil end
  from = from + (spec.plus or 0)
  return from, spec.len and from + spec.len or S[spec[2]]
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local S = Gen2State.symsFor(version)
  local which = version == "crystal" and "crystal" or "gs"
  local L = Gen2Save.layoutFor(version)
  local save0, sp, maps = base(version)
  local want = {}
  for _, row in ipairs(Core.coverage) do
    local spec = row.both or row[which]
    if spec and row.mode == "modeled" then
      local from, to = offsets(spec, S, L)
      for _, key in ipairs(row.keys or {}) do
        want[key] = want[key] or {}
        want[key][#want[key] + 1] = { from, to }
      end
    end
  end
  local clean = export(save0, version)
  for key, ranges in pairs(want) do
    local mut = MUT[key]
    if not mut then
      check(false, ("%s: key %s has no mutation proof"):format(version, key))
    else
      local save = base(version)
      mut(save, version, sp, maps)
      local out = export(save, version)
      local diff = changed(clean, out)
      local inside, outside = 0, {}
      for _, off in ipairs(diff) do
        local hit = false
        for _, r in ipairs(ranges) do if off >= r[1] and off < r[2] then hit = true end end
        local derived = (off >= L.backupSave.checksum and off < L.backupSave.checksum + 2) or off == L.sChecksum or off == L.sChecksum + 1
        for _, seg in ipairs(L.backupSave.segments) do if off >= seg[2] and off < seg[2] + seg[3] then derived = true end end
        if off == S.wGreensName + 10 then derived = true end
        if off >= L.sBox and off < L.sBox + Gen2Save.BOX_BYTES then derived = true end
        for _, b in ipairs(L.boxes) do if off >= b and off < b + Gen2Save.BOX_BYTES then derived = true end end
        if off >= L.backupSave.options and off < L.backupSave.options + 8 then derived = true end
        if hit then inside = inside + 1 elseif not derived then outside[#outside + 1] = ("0x%04X"):format(off) end
      end
      check(inside > 0, ("%s: changing %s changes bytes inside its rows"):format(version, key))
      local mapKey = key:match("^position%.") or key == "party" or key == "pokedex.caught" or key == "pokedex.seen" or key == "playTime"
      if #outside > 0 then
        local tolerated = key == "position.map" or key == "playerState" or key == "currentBox" or key == "party" or key == "cartBag" or key == "inventory"
        check(tolerated or false, ("%s: changing %s also changed bytes outside its rows: %s"):format(version, key, table.concat(outside, " ", 1, math.min(#outside, 6))))
      end
    end
  end
end

T.finish()
