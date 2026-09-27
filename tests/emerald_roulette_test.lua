package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_roulette_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_roulette_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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

require("src.core.GameVersion").set("emerald")
local M = require("src.import.gba.rse.roulette_extract")
local ROOT = "data/generated/gba"
local ok = M.run(rom, cache, { cacheRoot = ROOT })
eq(ok, true, "roulette extractor ran")
check(M.ready(cache, ROOT), "roulette cache ready")
for _, rel in ipairs(M.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end

local R = require("src.core.game3.rse.roulette")
local man = R.loadTables(cache)
local Tb = man.tables
eq(Tb.rouletteTables[0].baseTravelDist, 360, "left table travels 360")
eq(Tb.rouletteTables[1].var1C, -1.0, "right table var1C is -1.0f")
eq(Tb.minBets[3], 6, "service day right table min bet 6")
eq(Tb.grid[R.ROW_GREEN].tilemapOffset, 15, "green row tilemap offset")
eq(Tb.slots[11].gridSquare, 19, "slot 11 is purple Makuhita")
eq(#man.sprites.wheelIcons[11].anims, 1, "wheel icon anims read from the ROM")

eq(R.getMultiplier(Tb, R.newState(Tb, 0), 6), 12, "single square pays 12x")
eq(R.getMultiplier(Tb, R.newState(Tb, 0), 1), 4, "column pays 4x")
eq(R.getMultiplier(Tb, R.newState(Tb, 0), 5), 3, "row pays 3x")
eq(R.isHitInBetSelection(11, 1), 1, "green Wynaut hits the Wynaut column")
eq(R.isHitInBetSelection(12, 10), 1, "green Azurill hits the green row")
eq(R.isHitInBetSelection(12, 1), 0, "green Azurill misses the Wynaut column")
eq(R.minBetId(0x81), 3, "special rate right table")

local ffi = require("ffi")
local fu = ffi.new("union { float f; uint32_t u; }")
local function fbits(x) fu.f = x; return tonumber(fu.u) end

local U32 = 4294967296
local Rng = require("src.core.game3.rng")
local rngState = 0
local function rnd()
  rngState = (Rng.mulU32(rngState, 1103515245) + 24691) % U32
  return math.floor(rngState / 65536)
end

local sound = {
  se = function() end, stopSe = function() end, sePlaying = function() return false end, fanfare = function() end,
  cry = function() end, setSePan = function() end, id = function() return 0 end,
}
local UI = require("src.ui.game3.rse.roulette")
local ui = UI.new({ manifest = man, cache = cache, headless = true, var8004 = 0, coins = 100, random = rnd, sound = sound })
for _ = 1, 12 do ui:frame({ new = {}, held = {} }) end
check(ui.st ~= nil and ui.st.playTaskId ~= nil, "roulette screen sets up headless")

local vectors = dofile("tests/data/emerald_gc/roulette_vectors.lua")
check(#vectors >= 300, "300 pret C oracle vectors")
local fails = 0
local stuckSeen, taillowSeen = 0, 0
for vi, v in ipairs(vectors) do
  local st = ui.st
  st.tableId = v.table
  st.partySpeciesFlags = v.party
  st.hitFlags = v.hit
  for i = 0, 5 do st.betSelection[i], st.hitSquares[i] = 0, 0 end
  st.betSelection[0] = v.bet
  st.curBallNum = 0
  st.wheelAngle = v.wheel
  st.wheelSpeed = Tb.rouletteTables[v.table].wheelSpeed
  st.wheelDelay = Tb.rouletteTables[v.table].wheelDelay
  st.wheelDelayTimer = 0
  st.ballStuck, st.ballUnstuck, st.useTaillow, st.ballRolling = false, false, false, false
  st.ballState, st.hitSlot, st.stuckHitSlot = 0, 0, 0
  ui.hours = v.hours
  ui.m.coordOffsetY = 0
  local d = ui:task(st.playTaskId).data
  d[6], d[8] = v.ball, v.total
  local ball = ui:spr(v.ball)
  for i = 0, 7 do ball.data[i] = 0 end
  ball.x2, ball.y2 = 0, 0
  ball.callback = nil
  rngState = v.seed
  rnd()
  ui:taskInitBallRoll(st.playTaskId)
  ui:taskSpinWheel()
  local head = st.ballTravelDistFast == v.fast and st.ballTravelDistSlow == v.slow and fbits(st.ballAngle) == v.angle0
  rnd()
  st.ball = ui:spr(st.curBallSpriteId)
  ball = st.ball
  ball.callback = ui:sprCb("rollBallStart")
  ui:taskSpinWheel()
  ball.callback(ball)
  local frames = 1
  while frames < 6000 do
    if st.ballState == 0xFF then break end
    if ball.callback == ui:sprCb("unstickTaillowPickUp") then break end
    rnd()
    ui:taskSpinWheel()
    ball.callback(ball)
    frames = frames + 1
  end
  local good = head and frames == v.frames and st.ballState == v.state and st.hitSlot == v.hitSlot
    and st.stuckHitSlot == v.stuckSlot and (st.ballStuck and 1 or 0) == v.stuck and (st.useTaillow and 1 or 0) == v.taillow
    and ball.data[0] == v.d0 and ball.data[3] == v.d3 and ball.data[4] == v.d4 and ball.data[6] == v.d6 and ball.data[7] == v.d7
    and ball.x2 == v.x2 and ball.y2 == v.y2 and fbits(st.ballAngle) == v.ang and fbits(st.ballDistToCenter) == v.dist
    and fbits(st.ballAngleSpeed) == v.spd and st.wheelAngle == v.wheelOut and rngState == v.rng
  if v.stuck == 1 then stuckSeen = stuckSeen + 1 end
  if v.taillow == 1 then taillowSeen = taillowSeen + 1 end
  if not good then
    fails = fails + 1
    if fails <= 5 then
      print(string.format("vector %d: head %s frames %d/%d slot %d/%d stuck %s/%d d7 %d/%d ang %d/%d dist %d/%d rng %d/%d",
        vi, tostring(head), frames, v.frames, st.hitSlot, v.hitSlot, tostring(st.ballStuck), v.stuck, ball.data[7], v.d7,
        fbits(st.ballAngle), v.ang, fbits(st.ballDistToCenter), v.dist, rngState, v.rng))
    end
  end
  for i = 55, 57 do
    local id = st.spriteIds[i]
    if id and id < 64 then require("src.ui.game3.rse.gc_kit").destroySprite(ui.m, ui:sprite(id)) end
    st.spriteIds[i] = nil
  end
end
eq(fails, 0, "ball physics (f32) matches the pret C oracle on every vector")
check(stuckSeen >= 10 and taillowSeen >= 5, "vectors cover stuck balls (" .. stuckSeen .. ") and Taillow rescues (" .. taillowSeen .. ")")

local Kit = require("src.ui.game3.rse.gc_kit")
local tr = dofile("tests/data/emerald_gc/roulette_trace.lua")
local seNow = 0
local tsound = Kit.sound({ muted = true, version = "emerald" })
tsound.sePlaying = function() return seNow == 1 end
local ui2 = UI.new({ manifest = man, cache = cache, headless = true, var8004 = 0, coins = tr.coins, vblankRandom = true,
  random = rnd, sound = tsound, hours = tr.hours, partyFlags = tr.party })
for _ = 1, 400 do
  if ui2.st and ui2.st.nextTask == "taskContinuePlaying" then break end
  ui2:frame({ new = {}, held = {} })
end
check(ui2.st and ui2.st.nextTask == "taskContinuePlaying", "trace replay reaches the table")
rngState = tr.syncRng
ui2.st.wheelAngle, ui2.st.wheelDelayTimer, ui2.st.gridX = tr.wheel, tr.wdt, tr.gridX
ui2.m.coordOffsetX, ui2.m.coordOffsetY = tr.cox, tr.coy
local ev, lagAt = {}, {}
for _, e in ipairs(tr.events) do
  ev[e.rel] = e
  if e.lag then lagAt[e.rel + 1] = true end
end
local checksAt = {}
for _, row in ipairs(tr.checks) do checksAt[row[1]] = row end
local KEYS = { A = "a", B = "b", up = "up", down = "down", left = "left", right = "right" }
local compared, bad, first = 0, 0, nil
for rel = tr.sync + 1, tr.last do
  local e = ev[rel]
  if e and e.se ~= nil then seNow = e.se end
  local new = {}
  for _, k in ipairs(e and e.keys or {}) do new[KEYS[k]] = true end
  if lagAt[rel] then
    ui2.m.vblankCb(ui2.m)
    rnd()
  else
    ui2:frame({ new = new, held = new })
  end
  local row = checksAt[rel]
  if row and not ui2.done then
    compared = compared + 1
    local st = ui2.st
    local d = ui2:task(st.playTaskId).data
    local mine = { rngState, st.hitFlags, st.wheelAngle, st.gridX, st.ballState, st.hitSlot,
      st.ballAngle and fbits(st.ballAngle) or 0, st.ballDistToCenter and fbits(st.ballDistToCenter) or 0,
      st.ballAngleSpeed and fbits(st.ballAngleSpeed) or 0, d[13], d[6], d[4], ui2.m.coordOffsetX, ui2.m.coordOffsetY }
    for i, v in ipairs(mine) do
      if row[i + 1] ~= v then
        bad = bad + 1
        first = first or string.format("rel %d %s: lua %s emu %s", rel, tr.fields[i], tostring(v), tostring(row[i + 1]))
        break
      end
    end
  end
end
check(compared > 500, "replays over 500 checkpoints of the pygba ROM roulette trace (" .. compared .. ")")
eq(bad, 0, "RNG, hits, wheel, grid, ball physics (f32), credit, ball count and selection match the ROM frame by frame"
  .. (first and (" (" .. first .. ")") or ""))

T.finish()
