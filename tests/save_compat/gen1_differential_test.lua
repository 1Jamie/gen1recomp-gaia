package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_differential skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local Compat = require("src.save_convert.Compat")
local Ref = require("tests.save_compat._gen1_reference")
local Random = require("tests.save_compat._gen1_random")
local R2 = require("tests.save_compat._r2")

local CASES = tonumber(os.getenv("GEN1_DIFF_CASES")) or 200
local DUMP = os.getenv("GEN1_DIFF_DUMP")
local VERSIONS = { "red", "blue", "yellow" }
local charmapTokens = dofile("src/save_convert/data/charmap.lua").byToken
local TYPE_INDEX = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BIRD = 6, BUG = 7,
  GHOST = 8, FIRE = 20, WATER = 21, GRASS = 22, ELECTRIC = 23, PSYCHIC_TYPE = 24, ICE = 25, DRAGON = 26 }
local BADGES = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE",
  "VOLCANOBADGE", "EARTHBADGE" }
local STATUS_BIT = { PSN = 8, BRN = 16, FRZ = 32, PAR = 64 }

local function hexName(text)
  local out = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ("%02X"):format(charmapTokens[ch]) end
  return table.concat(out)
end

local function hexBytes(bytes)
  local out = {}
  for i = 1, #bytes do out[i] = ("%02X"):format(bytes[i]) end
  return table.concat(out)
end

local function be(v, n)
  local t = {}
  for i = n, 1, -1 do t[i] = v % 256; v = math.floor(v / 256) end
  return hexBytes(t)
end

local function bcdBytes(v, n)
  local t = {}
  for i = n, 1, -1 do
    local d = v % 100
    v = math.floor(v / 100)
    t[i] = math.floor(d / 10) * 16 + d % 10
  end
  return hexBytes(t)
end

local function bitset(n)
  local t = {}
  for i = 1, n do t[i] = 0 end
  return t
end

local function setBit(t, index)
  local at = math.floor(index / 8) + 1
  if math.floor(t[at] / 2 ^ (index % 8)) % 2 == 0 then t[at] = t[at] + 2 ^ (index % 8) end
end

local function expectedMon(mon, party, ctx)
  local cw, data = ctx.cw, ctx.data
  local def = data.pokemon[mon.species]
  local m = {
    species = cw.pokemonIndex[mon.species], hp = mon.hp, boxLevel = mon.level,
    types = ("%02X%02X"):format(TYPE_INDEX[def.types[1]], TYPE_INDEX[def.types[2] or def.types[1]]),
    catchRate = mon.catchRate, otId = mon.otId, exp = mon.exp,
    statExp = be(mon.statExp.hp, 2) .. be(mon.statExp.attack, 2) .. be(mon.statExp.defense, 2)
      .. be(mon.statExp.speed, 2) .. be(mon.statExp.special, 2),
    dvs = ("%02X%02X"):format(mon.dvs.attack * 16 + mon.dvs.defense, mon.dvs.speed * 16 + mon.dvs.special),
  }
  m.status = 0
  if mon.status == "SLP" then m.status = mon.sleepTurns elseif mon.status then m.status = STATUS_BIT[mon.status] end
  local mv, pp = {}, {}
  for i = 1, 4 do
    local move = mon.moves[i]
    mv[i] = move and cw.movesIndex[move.id] or 0
    pp[i] = move and (move.pp + move.ppUps * 64) or 0
  end
  m.moves, m.pp = hexBytes(mv), hexBytes(pp)
  m.ot = hexName(mon.ot)
  m.nick = hexName(mon.nickname or def.name)
  m.listSpecies = m.species
  if party then
    m.level = mon.level
    m.stats = be(mon.stats.hp, 2) .. be(mon.stats.attack, 2) .. be(mon.stats.defense, 2) .. be(mon.stats.speed, 2)
      .. be(mon.stats.special, 2)
  end
  return m
end

local function expectedList(mons, party, ctx)
  local out = { count = #mons }
  for i, mon in ipairs(mons) do out[i] = expectedMon(mon, party, ctx) end
  return out
end

local function townIndex(ctx, save)
  local heal = save.lastHeal
  return ctx.cw.mapsIndex[(heal.outdoor and heal.outdoor.id) or heal.map]
end

local function expected(save, version, ctx)
  local cw, data = ctx.cw, ctx.data
  local flags = save.flags
  local d = {}
  d.playerName = hexName(save.player.name)
  d.rivalName = hexName(save.player.rival)
  d.playerId = save.player.id
  d.money = save.money
  d.coins = save.coins
  local badges = 0
  for i, id in ipairs(BADGES) do if save.inventory[id] then badges = badges + 2 ^ (i - 1) end end
  d.badges = badges
  local opts = save.options
  d.options = (opts.textSpeed) + (opts.battleStyle == "set" and 0x40 or 0) + (opts.animations == false and 0x80 or 0)
  local owned, seen = bitset(19), bitset(19)
  for id, dex in pairs(cw.pokemonDex) do
    if save.pokedex.owned[id] then setBit(owned, dex - 1) end
    if save.pokedex.seen[id] then setBit(seen, dex - 1) end
  end
  d.dexOwned, d.dexSeen = hexBytes(owned), hexBytes(seen)
  local function rowsOf(map)
    local out = {}
    for id, qty in pairs(map) do
      if not id:match("BADGE$") and qty > 0 then
        local left, idx = qty, cw.itemsIndex[id]
        while left > 0 do
          local q = math.min(left, 99)
          out[#out + 1] = ("%02X:%02X"):format(idx, q)
          left = left - q
        end
      end
    end
    table.sort(out)
    return out
  end
  d.bagRows = rowsOf(save.inventory)
  d.pcRows = rowsOf(save.pcItems)
  d.curMap = cw.mapsIndex[save.player.map]
  d.x, d.y = save.player.x, save.player.y
  d.lastMap = cw.mapsIndex[save.lastOutdoor.id]
  d.boxByte = 0x80 + save.currentBox - 1
  d.numHoF = save.hallOfFame and #save.hallOfFame or 0
  local toggles = bitset(32)
  for bitIdx, e in pairs(data.toggleObjects.byBit) do if not e[3] then setBit(toggles, bitIdx) end end
  d.toggles = hexBytes(toggles)
  local hidden = bitset(14)
  for i, row in ipairs(data.hiddenItems) do
    if save.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] then setBit(hidden, i - 1) end
  end
  d.hiddenItems = hexBytes(hidden)
  local coinBits = bitset(2)
  for i, row in ipairs(require("src.save_convert.data.hidden_coins")) do
    if save.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] then setBit(coinBits, i - 1) end
  end
  d.hiddenCoins = hexBytes(coinBits)
  d.walk = save.player.surfing and 2 or (save.onBike and 1 or 0)
  local visited = bitset(2)
  for idx = 0, 10 do
    if save.visited[cw.mapsByIndex[idx]] then setBit(visited, idx) end
  end
  d.townVisited = visited[1] * 256 + visited[2]
  local chosen
  for _, name in ipairs({ "BULBASAUR", "CHARMANDER", "SQUIRTLE", "PIKACHU" }) do
    if flags["EVENT_CHOSE_" .. name] then chosen = name end
  end
  local rivalOf = { CHARMANDER = "SQUIRTLE", SQUIRTLE = "BULBASAUR", BULBASAUR = "CHARMANDER" }
  d.playerStarter = chosen and cw.pokemonIndex[chosen] or 0
  if version == "yellow" then
    d.rivalStarter = (save.rivalStarter and save.rivalStarter >= 1 and save.rivalStarter <= 3) and save.rivalStarter or 0
  else
    d.rivalStarter = chosen and cw.pokemonIndex[rivalOf[chosen]] or 0
  end
  d.blackout = townIndex(ctx, save)
  local f1 = (flags.EVENT_GOT_OLD_ROD and 8 or 0) + (flags.EVENT_GOT_GOOD_ROD and 16 or 0)
    + (flags.EVENT_GOT_SUPER_ROD and 32 or 0) + (flags.EVENT_GAVE_GUARDS_DRINK and 64 or 0)
  local f4 = (flags.EVENT_GOT_LAPRAS and 1 or 0) + (save.usedPokecenter and 4 or 0) + (flags.EVENT_GOT_STARTER and 8 or 0)
  local f6 = save.forcedBike and 32 or 0
  local e4 = flags.EVENT_STARTED_ELITE_4 and 2 or 0
  d.statusFlags = hexBytes({ f1, 0, badges, 0, 0, 0, f4, 0, 0, 0, f6, 0, e4 })
  d.tradeFlags = "0000"
  local events = bitset(320)
  for name in pairs(flags) do
    if flags[name] and data.eventFlags.byName[name] and name ~= "EVENT_RECEIVED_BIKE_VOUCHER" and name ~= "EVENT_GOT_HM_FLASH" then
      setBit(events, data.eventFlags.byName[name])
    end
  end
  if flags.EVENT_RECEIVED_BIKE_VOUCHER then setBit(events, data.eventFlags.byName.EVENT_GOT_BIKE_VOUCHER) end
  if flags.EVENT_GOT_HM_FLASH then setBit(events, data.eventFlags.byName.EVENT_GOT_HM05) end
  if save.safari then setBit(events, data.eventFlags.byName.EVENT_IN_SAFARI_ZONE) end
  d.events = events
  local total = math.floor(save.playTime * 60 + 0.5)
  local hours = math.floor(total / 216000)
  local rem = total - hours * 216000
  local minutes = math.floor(rem / 3600)
  rem = rem - minutes * 3600
  local seconds = math.floor(rem / 60)
  d.playTime = hexBytes({ hours, 0, minutes, seconds, rem - seconds * 60 })
  d.party = expectedList(save.party, true, ctx)
  d.boxes = {}
  for b = 1, 12 do d.boxes[b] = expectedList(save.boxes[b], false, ctx) end
  d.hof = {}
  for t, team in ipairs(save.hallOfFame or {}) do
    local rows = {}
    for _, mon in ipairs(team) do
      rows[#rows + 1] = ("%02X/%d/%s"):format(cw.pokemonIndex[mon.species], mon.level,
        hexName(mon.nickname or data.pokemon[mon.species].name))
    end
    d.hof[t] = table.concat(rows, ",")
  end
  d.safariBalls = save.safari and save.safari.balls or 0
  d.safariSteps = save.safari and save.safari.steps or 0
  d.safariGate = save.safari and 5 or 0
  local fossil = { KABUTO = { "DOME_FOSSIL", "KABUTO" }, OMANYTE = { "HELIX_FOSSIL", "OMANYTE" },
    AERODACTYL = { "OLD_AMBER", "AERODACTYL" } }
  if save.labFossilMon then
    local f = fossil[save.labFossilMon]
    d.fossil = ("%02X%02X"):format(cw.itemsIndex[f[1]], cw.pokemonIndex[f[2]])
  else
    d.fossil = "0000"
  end
  d.trash = save.trashPuzzle and ("%02X%02X"):format(save.trashPuzzle.first, save.trashPuzzle.second) or "0000"
  local dark = false
  for _, id in ipairs(data.field.darkMaps.maps) do if id == save.player.map then dark = true end end
  d.palOffset = dark and (save.flashLit and 0 or 6) or 0
  d.dayCareInUse = save.daycare and 1 or 0
  if version == "yellow" then
    d.yellowPikachu = ("%02X%02X"):format(save.pikachuHappiness, save.pikachuMood)
    d.emotion = save.pikachuEmotionModifier or 0
    local score = save.surfingHighScore or 0
    d.surfHi = ("%02X%02X"):format(tonumber(bcdBytes(score % 100, 1), 16), tonumber(bcdBytes(math.floor(score / 100), 1), 16))
  end
  return d
end

local function actualView(raw)
  local out = {}
  for k, v in pairs(raw) do out[k] = v end
  local function rows(s)
    local t = {}
    for row in s:gmatch("[^,]+") do t[#t + 1] = row end
    table.sort(t)
    return t
  end
  out.bagRows, out.pcRows = rows(raw.bag), rows(raw.pc)
  local events = {}
  for i = 1, 320 do events[i] = tonumber(raw.events:sub(i * 2 - 1, i * 2), 16) end
  out.events = events
  return out
end

local function flat(v, path, out)
  if type(v) ~= "table" then
    out[path] = tostring(v)
    return
  end
  for k, x in pairs(v) do flat(x, path .. "." .. tostring(k), out) end
  if next(v) == nil then out[path] = "{}" end
end

local COMPARED = { "playerName", "rivalName", "playerId", "money", "coins", "badges", "options", "dexOwned", "dexSeen",
  "bagRows", "pcRows", "curMap", "x", "y", "lastMap", "boxByte", "numHoF", "toggles", "hiddenItems", "hiddenCoins",
  "walk", "townVisited", "playerStarter", "rivalStarter", "statusFlags", "tradeFlags", "events", "playTime", "party",
  "boxes", "hof", "safariBalls", "safariSteps", "safariGate", "fossil", "trash", "palOffset", "dayCareInUse" }
local YELLOW = { "yellowPikachu", "emotion", "surfHi" }

local checks, failures = 0, 0
local ctxFor = {}
local summary = { red = 0, blue = 0, yellow = 0 }
local identical = 0

for seed = 1, CASES do
  local version = VERSIONS[(seed - 1) % 3 + 1]
  local data = Random.data(version)
  ctxFor[version] = ctxFor[version] or { data = data, cw = GenSave.crosswalks(data) }
  local ctx = ctxFor[version]
  local save = Random.build(seed, version)
  local out, err = SaveConvert.exportSav(save, version)
  checks = checks + 1
  if not out then
    failures = failures + 1
    check(false, ("seed %d %s: export failed: %s"):format(seed, version, tostring(err)))
  else
    summary[version] = summary[version] + 1
    if DUMP then
      local f = assert(io.open(("%s/g1_diff_%03d_%s.sav"):format(DUMP, seed, version), "wb"))
      f:write(out)
      f:close()
    end
    local report = Compat.check(out, version)
    check(#report.errors == 0, ("seed %d %s: the compat validator accepts the export (%s)"):format(seed, version,
      report.errors[1] and report.errors[1].rule or ""))
    local want = expected(save, version, ctx)
    local function compareWith(bytes)
      local got = actualView(Ref.decode(bytes))
      local w, g = {}, {}
      for _, key in ipairs(COMPARED) do flat(want[key], key, w); flat(got[key], key, g) end
      if version == "yellow" then
        for _, key in ipairs(YELLOW) do flat(want[key], key, w); flat(got[key], key, g) end
      end
      local list = {}
      for path, v in pairs(w) do if g[path] ~= v then list[#list + 1] = ("%s want %s got %s"):format(path, v, tostring(g[path])) end end
      for path, v in pairs(g) do if w[path] == nil then list[#list + 1] = ("%s unexpected %s"):format(path, v) end end
      table.sort(list)
      return list
    end
    local bad = compareWith(out)
    local got = Ref.decode(out)
    if seed <= 3 then
      for _, at in ipairs({ 0x25F4, 0x2F2C + 8 + 14, 0x25CA, 0x29F3 + 5, 0x30C0 + 2 + 20 + 3, 0x2598, 0x2605,
          0x260D, 0x2CED, save.hallOfFame and 0x0599 or 0x25F5 }) do
        local broken = out:sub(1, at) .. string.char((out:byte(at + 1) + 1) % 256) .. out:sub(at + 2)
        checks = checks + 1
        if #compareWith(broken) == 0 then
          failures = failures + 1
          check(false, ("negative control: a flipped byte at 0x%X went unnoticed (seed %d)"):format(at, seed))
        end
      end
    end
    checks = checks + 1
    if #bad > 0 then
      failures = failures + 1
      check(false, ("seed %d %s: %d fields differ, first: %s"):format(seed, version, #bad, table.concat(bad, "; ", 1, math.min(3, #bad))))
    end
    local dayCare = got.dayCareMon
    if save.daycare then
      local dm = save.daycare.mon
      checks = checks + 1
      local ok = dayCare.species == ctx.cw.pokemonIndex[dm.species] and dayCare.boxLevel == dm.level
        and dayCare.exp == math.min(0xFFFFFF, dm.exp + save.daycare.steps) and dayCare.otId == dm.otId
      if not ok then
        failures = failures + 1
        check(false, ("seed %d %s: the day care mon decodes wrong"):format(seed, version))
      end
    end

    local imported = SaveConvert.importSav(out, version, version)
    if imported then
      local before, after = R2.project(1, save), R2.project(1, imported)
      local unexplained = {}
      for key, v in pairs(before) do
        local excused = key:match("%.traded$") or key:match("^player%.facing") or key:match("^lastHeal")
          or key:match("^daycare%.steps$") or key:match("^daycare%.mon%.exp$")
          or (key:match("^trashPuzzle") and save.trashPuzzle.first == 0 and save.trashPuzzle.second == 0)
        if not excused and after[key] ~= v then unexplained[#unexplained + 1] = ("%s %s -> %s"):format(key, v, tostring(after[key])) end
      end
      for key in pairs(after) do
        local bookkeeping = key:match("%.typeBytes") or key:match("%.cartStatus$") or key:match("%.cartMoveSlots")
          or key:match("%.cartEmptyPP") or key:match("%.boxLevel$") or key == "flags.EVENT_IN_SAFARI_ZONE"
          or key == "flags.EVENT_RECEIVED_BIKE_VOUCHER" or key == "flags.EVENT_GOT_HM_FLASH"
        if before[key] == nil and not key:match("^lastHeal") and not key:match("%.traded$") and not bookkeeping then
          unexplained[#unexplained + 1] = key .. " appeared"
        end
      end
      table.sort(unexplained)
      checks = checks + 1
      if #unexplained > 0 then
        failures = failures + 1
        check(false, ("seed %d %s: import(export(S)) differs from S in %d modeled keys, first: %s"):format(seed, version,
          #unexplained, unexplained[1]))
      end
      local town = townIndex(ctx, save)
      checks = checks + 1
      if ctx.cw.mapsIndex[imported.lastHeal.map] ~= town then
        failures = failures + 1
        check(false, ("seed %d %s: the heal point did not survive as the same blackout town"):format(seed, version))
      end
    end
    checks = checks + 1
    local again = imported and SaveConvert.exportSav(imported, version)
    if again ~= out then
      failures = failures + 1
      check(false, ("seed %d %s: export -> import -> export is not a fixed point"):format(seed, version))
    else
      identical = identical + 1
    end
    local fresh = imported and (function()
      imported.rawImport = nil
      return SaveConvert.exportSav(imported, version)
    end)()
    checks = checks + 1
    if not fresh then
      failures = failures + 1
      check(false, ("seed %d %s: the templateless re-export failed"):format(seed, version))
    else
      local a, b = Ref.decode(out), Ref.decode(fresh)
      local diffs = Ref.compare(a, b, { "^%.events", "^%.dayCareName", "^%.dayCareOt" })
      if #diffs > 0 then
        failures = failures + 1
        check(false, ("seed %d %s: templateless re-export differs from the first: %s"):format(seed, version, diffs[1]))
      end
    end
  end
end

check(true, ("%d checks over %d seeded models"):format(checks, CASES))
eq(failures, 0, ("%d seeded models (red %d, blue %d, yellow %d) export, decode in the reference decoder and reach a fixed point")
  :format(CASES, summary.red, summary.blue, summary.yellow))
eq(identical, CASES, "every export -> import -> export is byte-identical")

T.finish()
