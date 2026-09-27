package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_slots_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_slots_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local rom = { id = "emerald", size = #data }
function rom.get(_, o) return data:byte(o + 1) end
function rom.u16(_, o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom.u32(_, o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom.readString(_, o, n) return data:sub(o + 1, o + n) end

local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
}

local M = require("src.import.gba.rse.slot_machine_extract")
local ROOT = "data/generated/gba"
local ok, man = M.run(rom, cache, { cacheRoot = ROOT })
eq(ok, true, "slot machine extractor ran")
check(M.ready(cache, ROOT), "slot machine cache ready")
for _, rel in ipairs(M.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end

local Slots = require("src.core.game3.rse.slot_machine")
local tables = Slots.loadTables(cache)
local Tb = tables.tables
eq(Tb.reelSymbols[0][0], 0, "left reel starts with a red 7")
eq(Tb.reelSymbols[2][20], Slots.SYMBOL.CHERRY, "right reel ends with a cherry")
eq(Tb.payouts[Slots.MATCH.RED_7], 300, "red 7 pays 300")
eq(Tb.payouts[Slots.MATCH.MIXED_7], 90, "mixed 7 pays 90")
eq(Tb.specialDrawOdds[5][2], 16, "luckiest machine bet-3 special odds")
eq(Tb.reelTimeProbLucky[0][16], 5, "lucky reel time table corner")
eq(#Tb.digitalScenes[0], 3, "insert-bet scene has 3 sprites")
eq(Tb.digitalCoords[34][0], 0, "A-button start coords")
eq(#tables.palettes.sprites, 8, "8 sprite palettes")
eq(tables.palettes.litMatchLine[0], 17 + 28 * 32 + 31 * 1024, "middle row lit colour")

local U32 = 4294967296
local Rng = require("src.core.game3.rng")
local function lcg(seed)
  local Rng = require("src.core.game3.rng")
  local state = seed
  return function()
    state = (Rng.mulU32(state, 1103515245) + 24691) % U32
    return math.floor(state / 65536)
  end, function() return state end
end

local vectors = dofile("tests/data/emerald_gc/slots_vectors.lua")
check(#vectors >= 300, "300 pret C oracle vectors")
local fails = 0
local function same(a, b) return a == b end
for vi, v in ipairs(vectors) do
  local rnd, stateOf = lcg(v.seed)
  local flashed = 0
  local sm = Slots.new(Tb, { random = rnd, flashMatchLine = function(l) flashed = bit.bor(flashed, bit.lshift(1, l)) end })
  sm.machineId, sm.bet, sm.luckyGame = v.id, v.bet, v.lucky == 1
  sm.pikaPowerBolts, sm.netCoinLoss, sm.reelTimeSpinsUsed, sm.reelTimeSpinsLeft = v.bolts, v.loss, v.used, v.left
  sm.machineBias = v.pre
  sm.reelSpeed = v.speed
  for i = 0, 2 do
    sm.reelPixelOffsets[i] = v.pix[i + 1]
    sm.reelPositions[i] = 21 - v.pix[i + 1] / 24
  end
  sm:drawMachineBias()
  if v.force ~= 0 then sm.machineBias = bit.bor(sm.machineBias, v.force) end
  local bias = sm.machineBias
  sm:resetBiasFailure()
  local turns, rows = {}, {}
  for r = 0, 2 do
    for _ = 1, v.spin[r + 1] do
      for q = r, 2 do sm:advanceSlotReel(q, sm.reelSpeed) end
    end
    sm:decideStop(r)
    turns[r + 1], rows[r + 1] = sm.reelExtraTurns[r], sm.winnerRows[r]
    while true do
      local pp = math.fmod(sm.reelPixelOffsets[r], 24)
      if pp ~= 0 then
        pp = sm:advanceSlotReelToNextSymbol(r, sm.reelSpeed)
      elseif sm.reelExtraTurns[r] ~= 0 then
        sm.reelExtraTurns[r] = sm.reelExtraTurns[r] - 1
        sm:advanceSlotReel(r, sm.reelSpeed)
        pp = math.fmod(sm.reelPixelOffsets[r], 24)
      end
      if pp == 0 and sm.reelExtraTurns[r] == 0 then break end
      for q = r + 1, 2 do sm:advanceSlotReel(q, sm.reelSpeed) end
    end
  end
  sm:checkMatch()
  rnd()
  sm:getReelTimeDraw()
  local speed = sm:reelTimeSpeed()
  local ex = sm:shouldReelTimeMachineExplode(v.chk) and 1 or 0
  local good = same(bias, v.bias) and same(sm.didNotFailBias and 1 or 0, v.dnf) and same(sm.biasSymbol, v.sym)
    and same(turns[1], v.turns[1]) and same(turns[2], v.turns[2]) and same(turns[3], v.turns[3])
    and same(rows[1], v.rows[1]) and same(rows[2], v.rows[2]) and same(rows[3], v.rows[3])
    and same(sm.reelPositions[0], v.pos[1]) and same(sm.reelPositions[1], v.pos[2]) and same(sm.reelPositions[2], v.pos[3])
    and same(sm.matches, v.matches) and same(sm.payout, v.payout) and same(flashed, v.flashed)
    and same(sm.reelTimeDraw, v.draw) and same(speed, v.rtspeed) and same(ex, v.explode) and same(stateOf(), v.rng)
  if not good then
    fails = fails + 1
    if fails <= 5 then
      print(string.format("vector %d: bias %d/%d turns %s/%s rows %s/%s pos %d,%d,%d/%s matches %d/%d payout %d/%d draw %d/%d speed %d/%d rng %d/%d",
        vi, bias, v.bias, table.concat(turns, ","), table.concat(v.turns, ","), table.concat(rows, ","), table.concat(v.rows, ","),
        sm.reelPositions[0], sm.reelPositions[1], sm.reelPositions[2], table.concat(v.pos, ","), sm.matches, v.matches,
        sm.payout, v.payout, sm.reelTimeDraw, v.draw, speed, v.rtspeed, stateOf(), v.rng))
    end
  end
end
eq(fails, 0, "Lua slot logic matches the pret C oracle on every vector")

local covered = { bias7 = 0, won = 0, manip = 0 }
for _, v in ipairs(vectors) do
  if bit.band(v.bias, 192) ~= 0 then covered.bias7 = covered.bias7 + 1 end
  if v.matches ~= 0 then covered.won = covered.won + 1 end
  if v.turns[3] > 0 then covered.manip = covered.manip + 1 end
end
check(covered.bias7 > 30 and covered.won > 30 and covered.manip > 30,
  string.format("vectors cover 7-biases (%d), wins (%d), manipulated stops (%d)", covered.bias7, covered.won, covered.manip))

require("src.core.GameVersion").set("emerald")
local Kit = require("src.ui.game3.rse.gc_kit")
local UI = require("src.ui.game3.rse.slot_machine")
local KEYS = { R = "r", A = "a", B = "b", select = "select", start = "start", up = "up", down = "down", left = "left", right = "right" }

local function replay(path)
  local tr = dofile(path)
  local rng = 0
  local function rnd()
    rng = (Rng.mulU32(rng, 1103515245) + 24691) % U32
    return math.floor(rng / 65536)
  end
  local ui = UI.new({ manifest = tables, cache = cache, headless = true, machineId = tr.machineId, coins = tr.coins,
    vblankRandom = true, random = rnd, sound = Kit.sound({ muted = true, version = "emerald" }) })
  ui:frame({ new = {}, held = {} })
  local c = ui.core
  c.luckyGame = tr.lucky == 1
  for i = 0, 2 do
    c.reelPositions[i] = math.fmod(Tb.initialReelPositions[i][tr.lucky], 21)
    c.reelPixelOffsets[i] = math.fmod(504 - c.reelPositions[i] * 24, 504)
  end
  for _ = 1, 200 do
    if c.state == 5 then break end
    ui:frame({ new = {}, held = {} })
  end
  rng = tr.syncRng
  local ev, lagAt = {}, {}
  for _, e in ipairs(tr.events) do
    ev[e.rel] = e
    if e.lag then lagAt[e.rel + 1] = true end
  end
  local checks = {}
  for _, row in ipairs(tr.checks) do checks[row[1]] = row end
  local compared, bad, first = 0, 0, nil
  for rel = tr.sync + 1, tr.last do
    local e = ev[rel]
    local new = {}
    for _, k in ipairs(e and e.keys or {}) do new[KEYS[k]] = true end
    if e and e.poke then
      if e.poke.bias then c.machineBias = bit.bor(c.machineBias, e.poke.bias) end
      if e.poke.bolts then
        c.pikaPowerBolts = e.poke.bolts
        ui.m.tasks:get(ui.sm.pikaPowerBoltTaskId).data[1] = e.poke.bolts
      end
    end
    if lagAt[rel] then
      ui.m.vblankCb(ui.m)
      rnd()
    else
      ui:frame({ new = new, held = new })
    end
    local row = checks[rel]
    if row then
      compared = compared + 1
      local pos = c.reelPositions[0] .. "," .. c.reelPositions[1] .. "," .. c.reelPositions[2]
      local pix = c.reelPixelOffsets[0] .. "," .. c.reelPixelOffsets[1] .. "," .. c.reelPixelOffsets[2]
      local mine = { rng, c.state, c.coins, c.payout, c.machineBias, c.pikaPowerBolts, c.reelTimeSpinsLeft, pos, pix }
      for i, v in ipairs(mine) do
        if row[i + 1] ~= v then
          bad = bad + 1
          first = first or string.format("rel %d %s: lua %s emu %s", rel, tr.fields[i], tostring(v), tostring(row[i + 1]))
          break
        end
      end
    end
  end
  return compared, bad, first
end

for _, name in ipairs({ "slots_trace_bias", "slots_trace_reeltime" }) do
  local n, bad, first = replay("tests/data/emerald_gc/" .. name .. ".lua")
  check(n > 200, name .. ": replays over 200 checkpoints of the pygba ROM trace (" .. n .. ")")
  eq(bad, 0, name .. ": RNG, state, coins, payout, bias, bolts, Reel Time spins and reel positions match the ROM frame by frame" .. (first and (" (" .. first .. ")") or ""))
end

local sm = Slots.new(Tb, { random = lcg(0) })
sm:init(0, 100)
eq(sm.coins, 100, "init keeps coins")
check(sm.reelPositions[0] == 0 or sm.reelPositions[0] == 6, "initial reel position from sInitialReelPositions")

T.finish()
