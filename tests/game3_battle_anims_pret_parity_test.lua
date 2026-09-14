-- tests/game3_battle_anims_pret_parity_test.lua
-- Rigorous 1:1 pret (pokefirered) parity test suite for battle animation tasks, callbacks and move scripts

package.path = package.path .. ";./?.lua"

local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local AnimVm = require("src.core.game3.battle.anim_vm")
local Anim = require("src.core.game3.battle.anim")

local passed = 0
local failed = 0

local function test(name, fn)
  AnimTasks.reset()
  AnimSprites.reset()
  Anim.reset({ headless = true })
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " -> " .. tostring(err))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "assert_eq failed", tostring(b), tostring(a)), 2)
  end
end

local function assert_true(val, msg)
  if not val then
    error(msg or "assert_true failed", 2)
  end
end

local function make_vm(attackerSide)
  attackerSide = attackerSide or "player"
  local targetSide = (attackerSide == "player") and "enemy" or "player"
  local vm = AnimVm.new()
  vm._attackerSide = attackerSide
  vm._targetSide = targetSide
  return vm
end

print("=== Pret (pokefirered) 1:1 Parity Audit Tests ===")

-- ---------------------------------------------------------------------------
-- 1. Registry Completeness against pokefirered/data/battle_anim_scripts.s
-- ---------------------------------------------------------------------------

test("Visual Tasks Registry - all 213 pret visual tasks are registered", function()
  local f = io.open("pokefirered/data/battle_anim_scripts.s", "r")
  assert_true(f ~= nil, "pokefirered/data/battle_anim_scripts.s must exist")
  local text = f:read("*a")
  f:close()

  local missing = 0
  for task in text:gmatch("createvisualtask%s+([%w_]+)") do
    local key = task:gsub("^AnimTask_", "")
    local fn = AnimTasks.REGISTRY[task] or AnimTasks.REGISTRY[key] or AnimTasks.REGISTRY["AnimTask_" .. key]
    if not fn then
      print("    Missing pret task in REGISTRY: " .. task)
      missing = missing + 1
    end
  end
  assert_eq(missing, 0, "All visual tasks from battle_anim_scripts.s must be registered")
end)

-- ---------------------------------------------------------------------------
-- 2. Dig & Subterranean Mechanics
-- ---------------------------------------------------------------------------

test("DigDownMovement - 3-step subterranean bounce and invisible toggle", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.oy = 0
  p.invisible = false

  local t = AnimTasks.spawn("DigDownMovement", 2, { 0 }, vm)
  assert_true(t ~= nil and t.active, "DigDownMovement should spawn")

  for _ = 1, 24 do AnimTasks.update(vm) end
  assert_true(p.oy > 0, "should have descended downward into ground")

  AnimTasks.update(vm)
  assert_true(not t.active, "DigDownMovement should complete in 24 frames")
  assert_true(p.invisible, "Mon should be invisible while underground")
end)

test("DigUpMovement - emergence from underground with coordinate recovery", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.oy = 32
  p.invisible = true

  local t = AnimTasks.spawn("DigUpMovement", 2, { 1 }, vm)
  assert_true(t ~= nil and t.active, "DigUpMovement should spawn")

  AnimTasks.update(vm)
  assert_true(not p.invisible, "Mon becomes visible immediately upon rising")

  for _ = 2, 20 do AnimTasks.update(vm) end
  AnimTasks.update(vm)
  assert_true(not t.active, "DigUpMovement should complete in 20 frames")
  assert_eq(p.oy, 0, "Mon oy must restore to 0 upon completion")
end)

-- ---------------------------------------------------------------------------
-- 3. Skull Bash & Extreme Speed Mechanics
-- ---------------------------------------------------------------------------

test("SkullBashPosition - side-aware backstep and forward rush", function()
  local vmPlayer = make_vm("player")
  local pPlayer = Anim.present("player")
  pPlayer.ox = 0

  -- Player backstep
  local t1 = AnimTasks.spawn("SkullBashPosition", 2, { 0 }, vmPlayer)
  for _ = 1, 17 do AnimTasks.update(vmPlayer) end
  assert_true(pPlayer.ox < 0, "Player should step back (negative ox)")

  -- Enemy backstep
  local vmEnemy = make_vm("enemy")
  local pEnemy = Anim.present("enemy")
  pEnemy.ox = 0
  local t2 = AnimTasks.spawn("SkullBashPosition", 2, { 0 }, vmEnemy)
  for _ = 1, 17 do AnimTasks.update(vmEnemy) end
  assert_true(pEnemy.ox > 0, "Enemy should step back (positive ox)")
end)

test("ExtremeSpeedImpact & Reappear - rapid target shudder and 14-frame flicker", function()
  local vm = make_vm("player")
  local pTgt = Anim.present("enemy")
  pTgt.ox = 0

  local tImpact = AnimTasks.spawn("ExtremeSpeedImpact", 2, {}, vm)
  AnimTasks.update(vm)
  assert_true(pTgt.ox ~= 0, "Target should shudder during ExtremeSpeed impact")

  for _ = 2, 19 do AnimTasks.update(vm) end
  assert_true(not tImpact.active, "ExtremeSpeedImpact should finish after 18 frames")
  assert_eq(pTgt.ox, 0, "Target ox should restore to 0")

  local pAtk = Anim.present("player")
  local tReappear = AnimTasks.spawn("ExtremeSpeedMonReappear", 2, {}, vm)
  for _ = 1, 14 do AnimTasks.update(vm) end
  AnimTasks.update(vm)
  assert_true(not tReappear.active, "ExtremeSpeedMonReappear should finish in 14 frames")
  assert_eq(pAtk.invisible, false, "Attacker must be visible after reappearing")
end)

-- ---------------------------------------------------------------------------
-- 4. Specialized Combat FX Tasks
-- ---------------------------------------------------------------------------

test("WaterSpoutLaunch & Rain - water geyser and falling cascade", function()
  local vm = make_vm("player")
  local tLaunch = AnimTasks.spawn("WaterSpoutLaunch", 2, {}, vm)
  assert_true(tLaunch ~= nil and tLaunch.active, "WaterSpoutLaunch should spawn")
  for _ = 1, 33 do AnimTasks.update(vm) end
  assert_true(not tLaunch.active, "WaterSpoutLaunch should finish after 32 frames")

  local tRain = AnimTasks.spawn("WaterSpoutRain", 2, {}, vm)
  assert_true(tRain ~= nil and tRain.active, "WaterSpoutRain should spawn")
  AnimTasks.update(vm)
  assert_true(tRain._particles ~= nil and #tRain._particles > 0, "WaterSpoutRain should generate particles")
  for _ = 2, 37 do AnimTasks.update(vm) end
  assert_true(not tRain.active, "WaterSpoutRain should finish after 36 frames")
end)

test("DoomDesireLightBeam & AirCutterProjectile - celestial beam and razor crescent", function()
  local vm = make_vm("player")
  local tBeam = AnimTasks.spawn("DoomDesireLightBeam", 2, {}, vm)
  assert_true(tBeam ~= nil and tBeam.active, "DoomDesireLightBeam should spawn")
  for _ = 1, 37 do AnimTasks.update(vm) end
  assert_true(not tBeam.active, "DoomDesireLightBeam should finish after 36 frames")

  local tCutter = AnimTasks.spawn("AirCutterProjectile", 2, {}, vm)
  assert_true(tCutter ~= nil and tCutter.active, "AirCutterProjectile should spawn")
  for _ = 1, 21 do AnimTasks.update(vm) end
  assert_true(not tCutter.active, "AirCutterProjectile should finish after 20 frames")
end)

test("StatsChange, FakeOut, GrowAndGrayscale, ShrinkTargetCopy", function()
  local vm = make_vm("player")
  local pAtk = Anim.present("player")
  local pTgt = Anim.present("enemy")

  -- FakeOut
  local tFake = AnimTasks.spawn("FakeOut", 2, {}, vm)
  for _ = 1, 17 do AnimTasks.update(vm) end
  assert_true(not tFake.active, "FakeOut should finish in 16 frames")

  -- StatsChange
  local tStats = AnimTasks.spawn("StatsChange", 2, { 0 }, vm)
  for _ = 1, 33 do AnimTasks.update(vm) end
  assert_true(not tStats.active, "StatsChange should finish in 32 frames")

  -- GrowAndGrayscale
  local tGrow = AnimTasks.spawn("GrowAndGrayscale", 2, {}, vm)
  for _ = 1, 25 do AnimTasks.update(vm) end
  assert_true(not tGrow.active, "GrowAndGrayscale should finish in 24 frames")
  assert_eq(pAtk.sx, 1.0, "sx must restore to 1.0")
  assert_eq(pAtk.grayscale, 0, "grayscale must restore to 0")

  -- ShrinkTargetCopy
  local tShrink = AnimTasks.spawn("ShrinkTargetCopy", 2, {}, vm)
  for _ = 1, 21 do AnimTasks.update(vm) end
  assert_true(not tShrink.active, "ShrinkTargetCopy should finish in 20 frames")
  assert_eq(pTgt.sx, 1.0, "sx must restore to 1.0")
  assert_eq(pTgt.alpha, 1.0, "alpha must restore to 1.0")
end)

-- ---------------------------------------------------------------------------
-- 5. Move Execution Parity for Complex Multi-turn & Special Moves
-- ---------------------------------------------------------------------------

local f = io.open("data/generated/gba/pokemon/battle_anims/pack.lua", "r")
local packSrc = f and f:read("*a")
if f then f:close() end
local chunk = loadstring and loadstring(packSrc) or load(packSrc)
local pack = chunk()

local function run_move(moveId, moveName)
  test(string.format("%s (Move #%d) - full bytecode execution parity", moveName, moveId), function()
    local script = pack.moves[moveId]
    assert_true(script ~= nil, "move script must exist for ID " .. tostring(moveId))
    local vm = AnimVm.new()
    vm:setPack(pack)
    vm:launch(script, { attackerSide = "player", isReversed = false })
    assert_true(vm:busy(), "VM should start busy")

    local maxTicks = 360
    local ticks = 0
    while vm:busy() and ticks < maxTicks do
      ticks = ticks + 1
      vm:update(1 / 60)
    end
    assert_true(not vm:busy(), string.format("move %d timed out after %d ticks", moveId, maxTicks))
  end)
end

run_move(91, "Dig")
run_move(130, "Skull Bash")
run_move(245, "Extreme Speed")
run_move(252, "Fake Out")
run_move(323, "Water Spout")
run_move(353, "Doom Desire")
run_move(314, "Air Cutter")
run_move(257, "Heat Wave")
run_move(37, "Thrash")
run_move(76, "SolarBeam")
run_move(174, "Curse")

print(string.format("\nPret Parity Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
