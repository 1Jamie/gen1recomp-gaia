package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_regions skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local MapContext = require("src.save_convert.MapContext")
local G1 = require("tests.fixtures.save.gen1_build")
local Diff = require("tests.save_compat._diff")
local Regions = require("src.save_convert.regions.gen1")

local O = GenSave.OFFSETS
local KINDS = { derived = true, scratch = true, unused = true, progress = true, umbrella = true }

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

local leaf = {}
for _, r in ipairs(Regions.regions) do
  if r.tier == "T2" then
    check(KINDS[r.kind] ~= nil, ("T2 region %s declares a kind"):format(r.name))
  end
  if r.kind ~= "umbrella" then leaf[#leaf + 1] = r end
end

do
  local covered = {}
  for _, r in ipairs(leaf) do
    for o = r.offset, r.offset + r.size - 1 do covered[o] = (covered[o] or 0) + 1 end
  end
  local holes, overlaps = 0, 0
  for o = 0x25A3, 0x2D2B do
    if not covered[o] then holes = holes + 1 end
    if (covered[o] or 0) > 1 and not (o >= 0x2612 and o < 0x27E6) and not (o >= 0x289C and o < 0x2964) then overlaps = overlaps + 1 end
  end
  eq(holes, 0, "every byte of sMainData belongs to a named leaf region, not the umbrella")
  eq(overlaps, 0, "leaf regions nest only inside the map window and the game progress block")
end

local function spec(version)
  local party, boxes = {}, {}
  for i = 1, 6 do
    party[i] = G1.mon({ species = G1.VALID_SPECIES[i * 11], level = 20 + i, boxLevel = 20 + i, hp = 60 + i,
      nick = "P" .. i, exp = 9000 + i, stats = { 60 + i, 50, 40, 30, 20 }, moves = { 0x21, 0x2D, 0x0A, 0x55 },
      pp = { 35, 40, 30, 15 }, ppUps = { 0, 0, 0, 0 } })
  end
  for b = 1, 12 do boxes[b] = G1.boxOf(20, b * 17, "RED") end
  local bag, pc = {}, {}
  for i = 1, 20 do bag[i] = { 0x28 + i, 5 } end
  for i = 1, 50 do pc[i] = { i <= 47 and (i + 0x1C) or (0xC8 + i - 47), 3 } end
  return { version = version, party = party, boxes = boxes, currentBox = 3, hofTeams = 3, bag = bag, pc = pc,
    map = 1, x = 18, y = 20, lastMap = 1, dex = { 1, 4, 7, 25, 150 }, badges = 0x0F, playTime = { 5, 0, 12, 30, 40 },
    patch = function(b)
      b[G1.OFF.lastBlackoutMap] = 1
      b[O.trashFirst] = 6
      b[O.trashSecond] = 8
    end }
end

local function importCart(version)
  local bytes = G1.build(spec(version))
  local save = assert(K.import(1, version, bytes))
  local out = assert(K.export(1, version, deepCopy(save)))
  return save, out
end

local function names(entries)
  local out = {}
  for _, e in ipairs(entries) do out[e.name] = e end
  return out
end

local function mutations(version)
  local M = {}
  local function add(name, expect, fn, may)
    M[#M + 1] = { name = name, expect = expect, fn = fn, may = may or {} }
  end
  local data = K.gen1Data(version)
  local cw = GenSave.crosswalks(data)

  add("identityTag", { "identityTag" }, function(s) s.meta.playthroughId = ("ab"):rep(16) end)
  add("playerName", { "playerName" }, function(s) s.player.name = "ZED" end)
  add("rivalName", { "rivalName" }, function(s) s.player.rival = "RIVAL" end)
  add("playerId", { "playerId" }, function(s) s.player.id = 0x1234 end, { "party.", "curBox.", "box" })
  add("money", { "money" }, function(s) s.money = s.money + 1 end)
  add("coins", { "coins" }, function(s) s.coins = 321 end)
  add("dexOwned", { "dexOwned" }, function(s) s.pokedex.owned.BULBASAUR = nil end)
  add("dexSeen", { "dexSeen" }, function(s) s.pokedex.seen.MEW = true end)
  add("bag", { "bag" }, function(s)
    local id = next(s.bagOrder and { [s.bagOrder[1]] = true } or s.inventory)
    s.inventory[id] = s.inventory[id] + 1
  end)
  add("pcItems", { "pcItems" }, function(s)
    local id = s.pcOrder[1]
    s.pcItems[id] = s.pcItems[id] + 1
  end)
  add("badges", { "badges", "beatGymFlags" }, function(s) s.inventory.EARTHBADGE = 1 end)
  add("options", { "options" }, function(s) s.options = { textSpeed = 5, battleStyle = "set", animations = false } end)
  add("lastMap", { "lastMap" }, function(s) s.lastOutdoor = { id = "PEWTER_CITY" } end)
  add("lastBlackoutMap", { "lastBlackoutMap" }, function(s) s.lastHeal = { map = "CELADON_CITY", x = 41, y = 10 } end)
  add("walkBikeSurfState", { "walkBikeSurfState" }, function(s) s.onBike = true end)
  add("townVisited", { "townVisited" }, function(s) s.visited = { PALLET_TOWN = true, SAFFRON_CITY = true } end)
  add("toggleableObjectFlags", { "toggleableObjectFlags" }, function(s)
    s.objectToggles = s.objectToggles or {}
    local bit0 = data.toggleObjects.byBit[0]
    s.objectToggles[bit0[1]] = s.objectToggles[bit0[1]] or {}
    s.objectToggles[bit0[1]][bit0[2]] = not s.objectToggles[bit0[1]][bit0[2]]
  end)
  add("hiddenItemFlags", { "hiddenItemFlags" }, function(s)
    local row = data.hiddenItems[3]
    s.hiddenTaken = s.hiddenTaken or {}
    s.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] = true
  end)
  add("hiddenCoinFlags", { "hiddenCoinFlags" }, function(s)
    s.hiddenTaken = s.hiddenTaken or {}
    s.hiddenTaken.GAME_CORNER_3_14 = true
  end)
  add("safari", { "safariSteps", "safariBalls", "eventFlags", "safariGateScript" }, function(s)
    s.safari = { balls = 17, steps = 321 }
  end)
  add("fossil", { "fossil", "eventFlags" }, function(s)
    s.labFossilMon = "KABUTO"
    s.flags.EVENT_GAVE_FOSSIL_TO_LAB = true
  end)
  if version == "yellow" then
    add("rivalStarter", { "rivalStarter" }, function(s) s.rivalStarter = 3 end)
  else
    add("rivalStarter", { "rivalStarter", "playerStarter", "eventFlags" }, function(s)
      s.flags.EVENT_CHOSE_CHARMANDER = nil
      s.flags.EVENT_CHOSE_BULBASAUR = true
    end)
  end
  add("statusFlags1", { "statusFlags1" }, function(s) s.flags.EVENT_GOT_OLD_ROD = true end)
  add("statusFlags4", { "statusFlags4" }, function(s) s.usedPokecenter = true end)
  add("statusFlags6", { "statusFlags6" }, function(s) s.forcedBike = true end)
  add("elite4Flags", { "elite4Flags" }, function(s) s.flags.EVENT_STARTED_ELITE_4 = true end)
  add("inGameTradeFlags", { "inGameTradeFlags" }, function(s)
    local trades = require("src.save_convert.data" .. (version == "yellow" and ".trade_flags_yellow" or ".trade_flags"))
    s.flags[trades[0] or trades[1]] = true
  end)
  add("trashCanIndexes", { "trashCanIndexes" }, function(s) s.trashPuzzle = { first = 10, second = 2 } end)
  add("eventFlags", { "eventFlags" }, function(s) s.flags.EVENT_BEAT_BROCK = true end)
  add("playTime", { "playTimeHours", "playTimeMinSecFrames" }, function(s) s.playTime = s.playTime + 3700 end)
  add("playTimeMaxed", { "playTimeHours", "playTimeMaxed", "playTimeMinSecFrames" }, function(s)
    s.playTime = 256 * 3600 + 5
  end)
  add("hallOfFame", { "hallOfFame", "numHoFTeams" }, function(s)
    s.hallOfFame[#s.hallOfFame + 1] = { { species = "MEW", level = 70 } }
  end)
  add("dayCare", { "dayCare" }, function(s)
    s.daycare = { mon = { species = "EEVEE", level = 12, exp = 1500, hp = 30, otId = 7, ot = "RED",
      dvs = { attack = 1, defense = 2, speed = 3, special = 4 }, moves = { { id = "TACKLE", pp = 35, ppUps = 0 } } },
      steps = 5, depositLevel = 12 }
  end)
  add("currentBoxNum", { "currentBoxNum" }, function(s) s.currentBox = 5 end, { "curBox.", "box" })
  add("curMap", { "curMap", "xCoord", "yCoord", "mapMusic", "viewPointer", "blockCoords", "mapWindow",
      "wildData", "spriteData", "tileAnimations" },
    function(s) s.player.map, s.player.x, s.player.y = "PEWTER_CITY", 13, 17 end, { "DERIVED" })
  add("mapPalOffset", { "mapPalOffset", "curMap", "xCoord", "yCoord" },
    function(s) s.player.map, s.player.x, s.player.y = "ROCK_TUNNEL_1F", 15, 3 end, { "DERIVED" })
  add("position", { "xCoord", "yCoord", "viewPointer", "blockCoords", "mapWindow", "spriteData" },
    function(s) s.player.x, s.player.y = s.player.x + 1, s.player.y - 1 end, { "DERIVED" })

  for slot = 1, 6 do
    add("party.mon" .. slot, { "party.mon" .. slot }, function(s) s.party[slot].exp = s.party[slot].exp + 77 end)
    add("party.nick" .. slot, { "party.nick" .. slot }, function(s) s.party[slot].nickname = "NEWNICK" end)
    add("party.ot" .. slot, { "party.ot" .. slot }, function(s) s.party[slot].ot = "NEWOT" end)
    add("party.species" .. slot, { "party.species", "party.mon" .. slot, "party.nick" .. slot },
      function(s) s.party[slot].species = "RHYDON"; s.party[slot].nickname = nil end,
      { "party.nick" .. slot })
  end
  for slot = 1, 20 do
    local cur = 4
    for _, box in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12 }) do
      local p = ("box%02d."):format(box)
      add(p .. "mon" .. slot, { p .. "mon" .. slot }, function(s) s.boxes[box][slot].exp = s.boxes[box][slot].exp + 9 end)
      add(p .. "nick" .. slot, { p .. "nick" .. slot }, function(s) s.boxes[box][slot].nickname = "NN" end)
      add(p .. "ot" .. slot, { p .. "ot" .. slot }, function(s) s.boxes[box][slot].ot = "OO" end)
    end
    add("curBox.mon" .. slot, { "curBox.mon" .. slot }, function(s) s.boxes[cur][slot].exp = s.boxes[cur][slot].exp + 9 end, { "box04." })
    add("curBox.nick" .. slot, { "curBox.nick" .. slot }, function(s) s.boxes[cur][slot].nickname = "NN" end, { "box04." })
    add("curBox.ot" .. slot, { "curBox.ot" .. slot }, function(s) s.boxes[cur][slot].ot = "OO" end, { "box04." })
  end
  for _, box in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12 }) do
    local p = ("box%02d"):format(box)
    add(p .. ".count", { p .. ".count", p .. ".species" }, function(s) table.remove(s.boxes[box]) end)
    add(p .. ".species", { p .. ".species", p .. ".mon1", p .. ".nick1" }, function(s)
      s.boxes[box][1].species = "RHYDON"
      s.boxes[box][1].nickname = nil
    end, { p .. ".nick1" })
  end
  add("curBox.count", { "curBox.count", "curBox.species" }, function(s) table.remove(s.boxes[4]) end, { "box04." })
  add("curBox.species", { "curBox.species", "curBox.mon1", "curBox.nick1" }, function(s)
    s.boxes[4][1].species = "RHYDON"
    s.boxes[4][1].nickname = nil
  end, { "box04.", "curBox.nick1" })
  add("party.count", { "party.count", "party.species" }, function(s) table.remove(s.party) end)
  return M
end

local function regionCovered(set, name)
  return set[name] ~= nil
end

local function runVersion(version)
  local tag = version .. ": "
  local save0, out0 = importCart(version)
  local regs = Regions.layouts[version] or Regions.layouts.default
  local proven = {}
  local derivedName = {}
  for _, r in ipairs(leaf) do if r.kind == "derived" then derivedName[r.name] = true end end

  for _, m in ipairs(mutations(version)) do
    local save = deepCopy(save0)
    local ok, err = pcall(m.fn, save)
    check(ok, tag .. m.name .. ": the mutation applies (" .. tostring(err) .. ")")
    if ok then
      local out, xerr = K.export(1, version, save)
      check(out ~= nil, tag .. m.name .. ": the export succeeds (" .. tostring(xerr) .. ")")
      if out then
        local diff = names(Diff.diff(out0, out, regs))
        for _, want in ipairs(m.expect) do
          if diff[want] then proven[want] = true end
          if not diff[want] and not (want == "mapWindow" or want == "wildData" or want == "spriteData"
              or want == "tileAnimations" or want == "mapMusic" or want == "eventFlags" or want == "beatGymFlags"
              or want == "party.nick1") then
            check(false, tag .. m.name .. ": " .. want .. " changed")
          end
        end
        local allowed = {}
        for _, w in ipairs(m.expect) do allowed[w] = true end
        for name in pairs(diff) do
          local ok2 = allowed[name]
          if name == "identityTag" then ok2 = true end
          for _, prefix in ipairs(m.may) do
            if name:sub(1, #prefix) == prefix or (prefix == "DERIVED" and derivedName[name]) then
              ok2 = true
              proven[name] = true
            end
          end
          if not ok2 then check(false, tag .. m.name .. ": unexpected region " .. name .. " changed") end
        end
      end
    end
  end

  local missing = {}
  do
    local altSpec = spec(version)
    altSpec.currentBox = 0
    local altBytes = G1.build(altSpec)
    local alt = assert(K.import(1, version, altBytes))
    local altOut0 = assert(K.export(1, version, deepCopy(alt)))
    local function altProve(label, fn, region, also)
      also = also or {}
      local save = deepCopy(alt)
      fn(save)
      local out = assert(K.export(1, version, save))
      local diff = names(Diff.diff(altOut0, out, regs))
      check(diff[region] ~= nil, tag .. label .. ": " .. region .. " changed")
      for n in pairs(diff) do
        local allowed = n == region or n == "identityTag"
        for _, a in ipairs(also) do if a == n then allowed = true; proven[n] = true end end
        check(allowed, tag .. label .. ": only " .. region .. " changed (saw " .. n .. ")")
      end
      proven[region] = true
    end
    for slot = 1, 20 do
      altProve("box04 mon", function(s) s.boxes[4][slot].exp = s.boxes[4][slot].exp + 3 end, "box04.mon" .. slot)
      altProve("box04 nick", function(s) s.boxes[4][slot].nickname = "ZZ" end, "box04.nick" .. slot)
      altProve("box04 ot", function(s) s.boxes[4][slot].ot = "QQ" end, "box04.ot" .. slot)
    end
    altProve("box04 count", function(s) table.remove(s.boxes[4]) end, "box04.count", { "box04.species" })
    altProve("box04 species", function(s) s.boxes[4][1].species = "RHYDON"; s.boxes[4][1].nickname = "RR" end, "box04.species",
      { "box04.mon1", "box04.nick1" })
    local keep = deepCopy(alt)
    keep.boxes[1][1].exp = keep.boxes[1][1].exp + 11
    local outKeep = assert(K.export(1, version, keep))
    eq(outKeep:sub(O.box1 + 1, O.box1 + 0x462), altBytes:sub(O.box1 + 1, O.box1 + 0x462),
      tag .. "the current box's bank copy is left as the cart holds it; the live copy is the authority")
  end

  local isContainer = {}
  for _, a in ipairs(leaf) do
    for _, b in ipairs(leaf) do
      if a ~= b and a.offset <= b.offset and b.offset + b.size <= a.offset + a.size and a.size > b.size then
        isContainer[a.name] = true
      end
    end
  end
  for _, r in ipairs(leaf) do
    if r.tier == "T1" and not r.derived and not isContainer[r.name] then
      local yellowOnly = r.name == "pikachuHappiness" or r.name == "pikachuMood" or r.name == "pikachuEmotionModifier"
        or r.name == "surfingMinigameHiScore"
      if (version == "yellow") == yellowOnly or (version ~= "yellow" and not yellowOnly) then
        if not proven[r.name] and not (r.name == "curMap" and proven.curMap) then missing[#missing + 1] = r.name end
      end
    end
  end
  return missing, proven
end

local missingRed = runVersion("red")
eq(table.concat(missingRed, ","), "", "every T1 region is proven writable from the model (red/blue)")

local function carryRun(version)
  local tag = version .. ": "
  local bytes = G1.build(spec(version))
  local save0 = assert(K.import(1, version, bytes))
  local save = deepCopy(save0)
  local applied = 0
  for _, m in ipairs(mutations(version)) do
    local trial = deepCopy(save)
    if pcall(m.fn, trial) then
      save = trial
      applied = applied + 1
    end
  end
  check(applied > 100, tag .. "the cumulative mutation set applies (" .. applied .. ")")
  local out = assert(K.export(1, version, save))
  local regs = Regions.layouts[version] or Regions.layouts.default
  local diff = Diff.diff(bytes, out, regs)
  local carried, changed = 0, {}
  for _, r in ipairs(leaf) do
    if r.tier == "T2" and (r.kind == "scratch" or r.kind == "unused" or r.kind == "progress") then
      carried = carried + 1
      changed[r.name] = false
    end
  end
  for _, e in ipairs(diff) do
    if changed[e.name] ~= nil then changed[e.name] = e end
  end
  for name, e in pairs(changed) do
    check(e == false, tag .. name .. " is carried from the cart byte for byte after every model change "
      .. (e and Diff.format({ e }) or ""))
  end
  check(carried >= 40, tag .. "the carry check covers every scratch/unused/progress region (" .. carried .. ")")
  local fresh = assert(K.export(1, version, deepCopy(save), false))
  eq(#fresh, 0x8000, tag .. "a templateless export of the same model is a full image")
  local derived = names(Diff.diff(bytes, out, regs))
  check(derived.curMap or derived.xCoord or derived.mapWindow, tag .. "the derived window followed the model's move")
end

carryRun("red")

local yellowMissing = runVersion("yellow")
local yellowOnly = {}
for _, n in ipairs(yellowMissing) do yellowOnly[#yellowOnly + 1] = n end
table.sort(yellowOnly)
eq(table.concat(yellowOnly, ","), "pikachuEmotionModifier,pikachuHappiness,pikachuMood,surfingMinigameHiScore",
  "yellow: only the Yellow-only regions are left for the Yellow mutation set")

do
  local save0, out0 = importCart("yellow")
  local regs = Regions.layouts.yellow
  local function check1(name, fn, region)
    local save = deepCopy(save0)
    fn(save)
    local out = assert(K.export(1, "yellow", save))
    local diff = names(Diff.diff(out0, out, regs))
    check(diff[region] ~= nil, "yellow: " .. name .. " reaches " .. region)
    for n in pairs(diff) do
      check(n == region or n == "identityTag", "yellow: " .. name .. " touches only " .. region .. " (saw " .. n .. ")")
    end
  end
  check1("friendship", function(s) s.pikachuHappiness = (s.pikachuHappiness or 90) + 7 end, "pikachuHappiness")
  check1("mood", function(s) s.pikachuMood = 0x40 end, "pikachuMood")
  check1("emotion modifier", function(s) s.pikachuEmotionModifier = 9 end, "pikachuEmotionModifier")
  check1("surfing high score", function(s) s.surfingHighScore = 1234 end, "surfingMinigameHiScore")
  local save = deepCopy(save0)
  save.surfingHighScore = 1234
  local out = assert(K.export(1, "yellow", save))
  eq(out:byte(O.surfHiScore + 1), 0x34, "the surfing score is little-endian BCD (low byte)")
  eq(out:byte(O.surfHiScore + 2), 0x12, "the surfing score is little-endian BCD (high byte)")
  eq(assert(K.import(1, "yellow", out)).surfingHighScore, 1234, "and reads back")
  carryRun("yellow")
end

T.finish()
