package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local cries, songs = {}, {}
package.loaded["src.core.game3.audio"] = {
  playCry = function(species, o) cries[#cries + 1] = { species = species, opts = o } return true end,
  playSong = function(id) songs[#songs + 1] = id end,
}
local behavior = 0x00
package.loaded["src.core.game3.collision"] = {
  behavior = function() return behavior end,
  isSurfable = function(b) return b == 0x10 end,
}
package.loaded["src.core.game3.player"] = { cellX = 3, cellY = 4, moving = false }
local MapStub = { MUSIC_DISABLE_OFF = 0, MUSIC_DISABLE_STOP = 1, MUSIC_DISABLE_KEEP = 2, disableMusicChange = 0 }
package.loaded["src.core.game3.map"] = MapStub
local mirage, mirageCalls = false, 0
package.loaded["src.core.game3.scripting.natives_field_rse"] = {
  isMirageIslandPresent = function() mirageCalls = mirageCalls + 1 return mirage end,
}

local GameVersion = require("src.core.GameVersion")
local Rng = require("src.core.game3.rng")
local Encounters = require("src.core.game3.encounters")
local AmbientCry = require("src.core.game3.ambient_cry")

local LAND_W = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
local WATER_W = { 60, 30, 5, 4, 1 }

local function slots(base, n)
  local out = {}
  for i = 1, n do out[i] = { species = base + i, minLevel = 5, maxLevel = 5 } end
  return out
end

Encounters._loaded = true
Encounters._tables = {
  T_LAND = { land = { rate = 20, slots = slots(100, 12) } },
  T_WATER = { water = { rate = 4, slots = slots(200, 5) } },
  T_BOTH = { land = { rate = 20, slots = slots(100, 12) }, water = { rate = 4, slots = slots(200, 5) } },
  T_FISH = { fishing = { rate = 30, slots = slots(300, 10) }, rockSmash = { rate = 20, slots = slots(400, 5) } },
  EM_ROUTE130 = { land = { rate = 20, slots = slots(100, 12) }, water = { rate = 4, slots = slots(200, 5) } },
}

local function idx(rand, w)
  local acc = 0
  for i = 1, #w do
    acc = acc + w[i]
    if rand < acc then return i end
  end
  return #w
end

local function session(version, party)
  return { version = version, map = "T_LAND", party = party or { { species = 1, personality = 0, abilityId = 0 } } }
end

local function draws_between(seed, fn)
  Rng.SeedRng(seed)
  fn()
  local after = Rng.getState().value
  Rng.SeedRng(seed)
  local n = 0
  while Rng.getState().value ~= after and n < 16 do Rng.Random() n = n + 1 end
  return n
end

for _, version in ipairs({ "firered", "emerald", "ruby" }) do
  GameVersion.set(version)
  local s = session(version)

  local landOk, waterOk, bothLand, bothWater, bothOk = true, true, 0, 0, true
  for seed = 1, 400 do
    Rng.SeedRng(seed)
    local want = 100 + idx(Rng.Random() % 100, LAND_W)
    Rng.SeedRng(seed)
    if AmbientCry.choose(s, "T_LAND") ~= want or AmbientCry.isWaterMon then landOk = false end

    Rng.SeedRng(seed)
    want = 200 + idx(Rng.Random() % 100, WATER_W)
    Rng.SeedRng(seed)
    if AmbientCry.choose(s, "T_WATER") ~= want or not AmbientCry.isWaterMon then waterOk = false end

    Rng.SeedRng(seed)
    local land = Rng.Random() % 100 < 80
    if land then want = 100 + idx(Rng.Random() % 100, LAND_W) else want = 200 + idx(Rng.Random() % 100, WATER_W) end
    Rng.SeedRng(seed)
    if AmbientCry.choose(s, "T_BOTH") ~= want or AmbientCry.isWaterMon == land then bothOk = false end
    if land then bothLand = bothLand + 1 else bothWater = bothWater + 1 end
  end
  check(landOk, version .. " land-only map picks land[ChooseWildMonIndex_Land()] in one draw")
  check(waterOk, version .. " water-only map picks water[ChooseWildMonIndex_WaterRock()] and flags water")
  check(bothOk, version .. " land+water map rolls Random() % 100 < 80 for land, then the slot")
  check(bothLand > bothWater * 2 and bothWater > 0, version .. " land+water split is roughly 80/20")
  eq(draws_between(5, function() AmbientCry.choose(s, "T_LAND") end), 1, version .. " land-only pick is one draw")
  eq(draws_between(5, function() AmbientCry.choose(s, "T_BOTH") end), 2, version .. " land+water pick is two draws")

  eq(draws_between(9, function() AmbientCry.choose(s, "T_FISH") end), 0, version .. " fishing/rock smash only map draws nothing")
  eq(AmbientCry.species, 0, version .. " fishing/rock smash tables are never used")
  AmbientCry.choose(s, "NO_SUCH_MAP")
  eq(AmbientCry.species, 0, version .. " map without a wild header has no ambient species")
  AmbientCry.resetTask()
  AmbientCry.update(s)
  eq(AmbientCry.state, AmbientCry.IDLE, version .. " no species -> idle")
  eq(draws_between(3, function() for _ = 1, 5000 do AmbientCry.update(s) end end), 0,
    version .. " idle never draws or plays")

  AmbientCry.choose(s, "T_LAND")
  local firstOk, repeatOk = true, true
  local firstMin, firstMax, repMin, repMax = math.huge, 0, math.huge, 0
  for seed = 1, 200 do
    AmbientCry.resetTask()
    AmbientCry.update(s)
    Rng.SeedRng(seed)
    local want = Rng.Random() % 2400 + 1200
    Rng.SeedRng(seed)
    AmbientCry.update(s)
    if AmbientCry.delay ~= want or AmbientCry.state ~= AmbientCry.WAIT then firstOk = false end
    firstMin, firstMax = math.min(firstMin, AmbientCry.delay), math.max(firstMax, AmbientCry.delay)
    AmbientCry.state = AmbientCry.RESET
    Rng.SeedRng(seed)
    want = Rng.Random() % 1200 + 1200
    Rng.SeedRng(seed)
    AmbientCry.update(s)
    if AmbientCry.delay ~= want then repeatOk = false end
    repMin, repMax = math.min(repMin, AmbientCry.delay), math.max(repMax, AmbientCry.delay)
  end
  check(firstOk and firstMin >= 1200 and firstMax <= 3599, version .. " first delay is Random() % 2400 + 1200")
  check(repeatOk and repMin >= 1200 and repMax <= 2399, version .. " repeat delay is Random() % 1200 + 1200")

  cries = {}
  AmbientCry.resetTask()
  AmbientCry.update(s)
  AmbientCry.update(s)
  local d = AmbientCry.delay
  for _ = 1, d - 1 do AmbientCry.update(s) end
  eq(#cries, 0, version .. " no cry before the countdown hits zero")
  Rng.SeedRng(77)
  local wantPan = Rng.Random() % 88 + 212
  if wantPan >= 128 then wantPan = wantPan - 256 end
  local wantVol = Rng.Random() % 30 + 50
  Rng.SeedRng(77)
  AmbientCry.update(s)
  eq(#cries, 1, version .. " cry plays on the frame the countdown reaches zero")
  local c = cries[1] or { opts = {} }
  eq(c.species, AmbientCry.species, version .. " ambient cry is the picked species")
  eq(c.opts.pan, wantPan, version .. " pan is (s8)(Random() % 88 + 212)")
  eq(c.opts.volume, wantVol, version .. " volume is Random() % 30 + 50")
  eq(c.opts.noDuck, true, version .. " ambient cry does not duck the BGM")
  eq(c.opts.mode, 0, version .. " ambient cry is CRY_MODE_NORMAL")
  eq(AmbientCry.state, AmbientCry.RESET, version .. " after a cry the timer goes to RESET")

  local panOk = true
  for seed = 1, 300 do
    Rng.SeedRng(seed)
    cries = {}
    AmbientCry.play(s)
    local o = cries[1] and cries[1].opts
    if not o or o.pan < -44 or o.pan > 43 or o.volume < 50 or o.volume > 79 then panOk = false end
  end
  check(panOk, version .. " pan stays in -44..43 and volume in 50..79")

  AmbientCry.species, AmbientCry.isWaterMon = 201, true
  behavior = 0x00
  cries = {}
  eq(draws_between(11, function() AmbientCry.play(s) end), 0, version .. " water mon on land skips without drawing pan/volume")
  eq(#cries, 0, version .. " water mon on land plays nothing")
  behavior = 0x10
  AmbientCry.play(s)
  eq(#cries, 1, version .. " water mon on surfable water plays")
  local P = package.loaded["src.core.game3.player"]
  P.moving, P.targetX, P.targetY = true, 9, 9
  local seen
  package.loaded["src.core.game3.collision"].behavior = function(x, y) seen = { x, y } return 0x10 end
  AmbientCry.play(s)
  eq(seen and seen[1], 9, version .. " surf check uses the player's destination tile")
  package.loaded["src.core.game3.collision"].behavior = function() return behavior end
  P.moving = false
  AmbientCry.isWaterMon = false

  cries, songs = {}, {}
  MapStub.disableMusicChange = MapStub.MUSIC_DISABLE_STOP
  local n = draws_between(13, function() AmbientCry.play(s) end)
  if version == "firered" then
    eq(#cries, 0, "firered MUSIC_DISABLE_STOP plays no cry")
    eq(songs[1], 0, "firered MUSIC_DISABLE_STOP stops the map music")
    eq(n, 2, "firered MUSIC_DISABLE_STOP still draws pan and volume")
    cries, songs = {}, {}
    MapStub.disableMusicChange = MapStub.MUSIC_DISABLE_KEEP
    eq(draws_between(13, function() AmbientCry.play(s) end), 2, "firered MUSIC_DISABLE_KEEP still draws pan and volume")
    eq(#cries + #songs, 0, "firered MUSIC_DISABLE_KEEP plays nothing and keeps the music")
  else
    eq(#cries, 1, version .. " has no music-disable branch in PlayAmbientCry")
  end
  MapStub.disableMusicChange = MapStub.MUSIC_DISABLE_OFF

  local fakeField = { locked = false, isLocked = function() return false end }
  AmbientCry.choose(s, "T_LAND")
  AmbientCry.resetTask()
  AmbientCry.tick(fakeField, nil, s)
  AmbientCry.tick(fakeField, nil, s)
  local before = AmbientCry.delay
  AmbientCry.tick(fakeField, nil, s)
  eq(AmbientCry.delay, before - 1, version .. " unlocked field counts down")
  fakeField.locked = true
  AmbientCry.tick(fakeField, nil, s)
  fakeField.locked = false
  fakeField.isLocked = function() return true end
  AmbientCry.tick(fakeField, nil, s)
  fakeField.isLocked = function() return false end
  AmbientCry.tick(fakeField, { vm = { isRunning = function() return true end } }, s)
  eq(AmbientCry.delay, before - 1, version .. " locked controls or a running script freeze the countdown")
  AmbientCry.resetTask()
  eq(AmbientCry.state, AmbientCry.INIT, version .. " field task reset returns to INIT")
end

local function repeat_delay(version, party, seed)
  GameVersion.set(version)
  local s = session(version, party)
  AmbientCry.species = 101
  AmbientCry.state = AmbientCry.RESET
  Rng.SeedRng(seed)
  AmbientCry.update(s)
  return AmbientCry.delay
end

local SWARM = 68
local leadSwarm = { { species = 267, abilityId = SWARM }, { species = 1, abilityId = 0 } }
local otherSwarm = { { species = 1, abilityId = 0 }, { species = 267, abilityId = SWARM } }
local eggLeadSwarm = { { species = 267, abilityId = SWARM, isEgg = true }, { species = 1, abilityId = 0 } }
local onlyEggSwarm = { { species = 267, abilityId = SWARM, isEgg = true } }
Rng.SeedRng(21)
local base = Rng.Random() % 1200 + 1200
eq(repeat_delay("emerald", leadSwarm, 21), math.floor(base / 2), "emerald lead Swarm halves the repeat delay")
eq(repeat_delay("emerald", otherSwarm, 21), base, "emerald non-lead Swarm does not halve (retail checks party[0])")
eq(repeat_delay("emerald", eggLeadSwarm, 21), math.floor(base / 2), "emerald Swarm egg lead halves when another mon is not an egg")
eq(repeat_delay("emerald", onlyEggSwarm, 21), base, "emerald Swarm egg alone does not halve")
eq(repeat_delay("ruby", leadSwarm, 21), base, "ruby has no Swarm halving")
eq(repeat_delay("firered", leadSwarm, 21), base, "firered has no Swarm halving")

GameVersion.set("emerald")
local em = session("emerald")
mirage, mirageCalls = false, 0
local waterOnly = true
for seed = 1, 100 do
  Rng.SeedRng(seed)
  local want = 200 + idx(Rng.Random() % 100, WATER_W)
  Rng.SeedRng(seed)
  if AmbientCry.choose(em, "EM_ROUTE130") ~= want or not AmbientCry.isWaterMon then waterOnly = false end
end
check(waterOnly, "emerald Route 130 without Mirage Island forces a water mon in one draw")
mirage = true
local sawLand = false
for seed = 1, 100 do
  AmbientCry.choose(em, "EM_ROUTE130")
  if not AmbientCry.isWaterMon then sawLand = true end
end
check(sawLand, "emerald Route 130 with Mirage Island uses the normal land/water pick")
mirageCalls = 0
GameVersion.set("firered")
AmbientCry.choose(session("firered"), "EM_ROUTE130")
eq(mirageCalls, 0, "firered never runs the Route 130 rule")

T.finish("game3 ambient cry")
