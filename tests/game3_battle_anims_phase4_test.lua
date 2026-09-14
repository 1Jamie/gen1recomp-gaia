-- tests/game3_battle_anims_phase4_test.lua
-- Unit and integration tests for Phase 4: Dynamic Backgrounds, Clones, Distortions, Spotlights, Substitute & Evaluators

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

print("=== Phase 4: Dynamic Backgrounds, Clones, Distortions & Specialized Systems Tests ===")

-- ---------------------------------------------------------------------------
-- 1. Dynamic Scrolling Backgrounds & High-Altitude Environments
-- ---------------------------------------------------------------------------

test("MoveSkyUppercutBg - vertical ascending clouds background lifetime and draw hook", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("MoveSkyUppercutBg", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")
  AnimTasks.update(vm)
  assert_eq(t.z, AnimSprites.Z.GLOBAL_BEHIND, "should layer on GLOBAL_BEHIND")
  assert_true(type(t.draw) == "function", "should provide a draw callback")

  for f = 2, 36 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("MoveSeismicTossBg - accelerating descent space background", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("MoveSeismicTossBg", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")
  AnimTasks.update(vm)
  assert_eq(t.z, AnimSprites.Z.GLOBAL_BEHIND, "should layer on GLOBAL_BEHIND")

  for f = 2, 40 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("PositionFissureBgOnBattler - ground abyss fissure", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("PositionFissureBgOnBattler", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")

  for f = 1, 40 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("SetPsychicBackground - warping psychic concentric rings background", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("SetPsychicBackground", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")

  for f = 1, 32 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("HeartsBackground - floating hearts background for Attract", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("HeartsBackground", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")

  for f = 1, 36 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("ScaryFace - looming demonic phantom mask", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("ScaryFace", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")
  AnimTasks.update(vm)
  assert_eq(t.z, AnimSprites.Z.MID_FIELD, "should layer on MID_FIELD")

  for f = 2, 32 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("CreateRaindrops - diagonal falling raindrop particles", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("CreateRaindrops", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")

  AnimTasks.update(vm) -- frame 1 generates particles
  assert_eq(t.z, AnimSprites.Z.GLOBAL_FRONT, "should layer on GLOBAL_FRONT")
  assert_true(t._particles ~= nil and #t._particles > 0, "should have generated particles")

  for f = 2, 36 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

-- ---------------------------------------------------------------------------
-- 2. Shadow Clones, Afterimages & Silhouette Transfers
-- ---------------------------------------------------------------------------

test("NightShadeClone & NightmareClone - rising dark silhouette with glowing eyes", function()
  local vm = make_vm("player")
  local t1 = AnimTasks.spawn("NightShadeClone", 2, {}, vm)
  assert_true(t1 ~= nil and t1.active, "NightShadeClone should spawn")

  for f = 1, 32 do
    AnimTasks.update(vm)
    assert_true(t1.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t1.active, "should destroy after duration")

  local t2 = AnimTasks.spawn("NightmareClone", 2, {}, vm)
  assert_true(t2 ~= nil and t2.active, "NightmareClone alias should spawn")
  for _ = 1, 33 do AnimTasks.update(vm) end
  assert_true(not t2.active, "should destroy after duration")
end)

test("DestinyBondWhiteShadow - floor white shadow", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("DestinyBondWhiteShadow", 2, {}, vm)
  assert_true(t ~= nil and t.active, "DestinyBondWhiteShadow should spawn")

  for f = 1, 30 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("MementoShadow - shadow transfer from attacker to target", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("InitMementoShadow", 2, {}, vm)
  assert_true(t ~= nil and t.active, "InitMementoShadow should spawn")

  for f = 1, 32 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("RolePlaySilhouette - target silhouette copy transfer", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("RolePlaySilhouette", 2, {}, vm)
  assert_true(t ~= nil and t.active, "RolePlaySilhouette should spawn")

  for f = 1, 28 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

-- ---------------------------------------------------------------------------
-- 3. Screen Distortions, Spotlights & Combat FX
-- ---------------------------------------------------------------------------

test("ScreenDistortionWobble (Extrasensory & Uproar) - custom screen tint wobble", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("ExtrasensoryDistortion", 2, {}, vm)
  assert_true(t ~= nil and t.active, "ExtrasensoryDistortion should spawn")

  AnimTasks.update(vm)
  local fx = Anim.screenEffect()
  assert_true(fx ~= nil, "should apply screen effect during distortion")
  assert_eq(fx.type, "custom_blend", "should use custom_blend effect")

  for _ = 2, 25 do AnimTasks.update(vm) end
  assert_true(not t.active, "should destroy after duration")
  assert_eq(Anim.screenEffect().type, "none", "should clear screen effect upon finish")
end)

test("Spotlight - cone lighting on target", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("CreateSpotlight", 2, {}, vm)
  assert_true(t ~= nil and t.active, "CreateSpotlight should spawn")
  AnimTasks.update(vm)
  assert_eq(t.z, AnimSprites.Z.GLOBAL_FRONT, "should layer on GLOBAL_FRONT")

  for f = 2, 32 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("MorningSunLightBeam & GlareEyeDots - descending sunbeams and crimson eyes", function()
  local vm = make_vm("player")
  local tSun = AnimTasks.spawn("MorningSunLightBeam", 2, {}, vm)
  assert_true(tSun ~= nil and tSun.active, "MorningSunLightBeam should spawn")
  for _ = 1, 33 do AnimTasks.update(vm) end
  assert_true(not tSun.active, "MorningSunLightBeam should destroy after duration")

  local tGlare = AnimTasks.spawn("GlareEyeDots", 2, {}, vm)
  assert_true(tGlare ~= nil and tGlare.active, "GlareEyeDots should spawn")
  for _ = 1, 29 do AnimTasks.update(vm) end
  assert_true(not tGlare.active, "GlareEyeDots should destroy after duration")
end)

test("Generic combat FX tasks - ElectricCharging, DrillPeck, GrudgeFlames, BarrageBall", function()
  local vm = make_vm("player")
  local list = {
    "ElectricChargingParticles", "DrillPeckHitSplats", "GrudgeFlames",
    "BarrageBall", "StatusClearedEffect", "RapinSpinMonElevation",
    "ImprisonOrbs", "SketchDrawMon", "SkillSwap", "Teleport",
    "ConversionAlphaBlend", "RotateAuroraRingColors"
  }
  for _, name in ipairs(list) do
    local t = AnimTasks.spawn(name, 2, {}, vm)
    assert_true(t ~= nil and t.active, "Task " .. name .. " should spawn")
    for _ = 1, 25 do AnimTasks.update(vm) end
    assert_true(not t.active, "Task " .. name .. " should finish cleanly in duration")
  end
end)

-- ---------------------------------------------------------------------------
-- 4. Battler Movement & Substitute Doll Swap
-- ---------------------------------------------------------------------------

test("DoubleTeam - horizontal jitter, alpha pulse and clean restoration", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.ox = 0
  p.alpha = 1.0

  local t = AnimTasks.spawn("DoubleTeam", 2, { 30 }, vm)
  assert_true(t ~= nil and t.active, "DoubleTeam should spawn")

  AnimTasks.update(vm)
  assert_true(p.ox ~= 0, "DoubleTeam should offset battler ox")

  for _ = 2, 31 do AnimTasks.update(vm) end
  assert_true(not t.active, "DoubleTeam should finish after 30 frames")
  assert_eq(p.ox, 0, "DoubleTeam must reset ox to 0")
  assert_eq(p.alpha, 1.0, "DoubleTeam must reset alpha to 1.0")
end)

test("MonToSubstitute - squash and stretch scaling and clean restoration", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.sx = 1.0
  p.sy = 1.0

  local t = AnimTasks.spawn("MonToSubstitute", 2, {}, vm)
  assert_true(t ~= nil and t.active, "MonToSubstitute should spawn")

  for _ = 1, 8 do AnimTasks.update(vm) end
  assert_true(p.sy < 1.0 and p.sx > 1.0, "should squash vertically and stretch horizontally")

  for _ = 9, 17 do AnimTasks.update(vm) end
  assert_true(not t.active, "MonToSubstitute should finish in 16 frames")
  assert_eq(p.sx, 1.0, "sx must restore to 1.0")
  assert_eq(p.sy, 1.0, "sy must restore to 1.0")
end)

test("AttackerPunchWithTrace - forward lunge and reset", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.ox = 0

  local t = AnimTasks.spawn("AttackerPunchWithTrace", 2, {}, vm)
  assert_true(t ~= nil and t.active, "AttackerPunchWithTrace should spawn")

  AnimTasks.update(vm)
  for _ = 2, 21 do AnimTasks.update(vm) end
  assert_true(not t.active, "should finish in 20 frames")
  assert_eq(p.ox, 0, "ox must reset to 0")
end)

-- ---------------------------------------------------------------------------
-- 5. Metadata Evaluators (Immediate Query Tasks)
-- ---------------------------------------------------------------------------

test("QueryStateTask evaluators - immediate resolution without blocking VM", function()
  local vm = make_vm("player")
  local evaluators = {
    "GetRolloutCounter", "GetFuryCutterHitCount", "IsFuryCutterHitRight",
    "GetReturnPowerLevel", "GetFrustrationPowerLevel", "GetSeismicTossDamageLevel",
    "IsPowerOver99", "GetBattleTerrain", "GetWeather", "IsContest",
    "IsTargetPlayerSide", "GetIsDoomDesireHitTurn", "IsHealingMove"
  }
  for _, ev in ipairs(evaluators) do
    local t = AnimTasks.spawn(ev, 2, {}, vm)
    assert_true(t ~= nil, "Evaluator " .. ev .. " should spawn")
    AnimTasks.update(vm)
    assert_true(not t.active, "Evaluator " .. ev .. " should immediately resolve")
  end
end)

-- ---------------------------------------------------------------------------
-- 6. Complex Script Execution & Integration
-- ---------------------------------------------------------------------------

local f = io.open("data/generated/gba/pokemon/battle_anims/pack.lua", "r")
local packSrc = f and f:read("*a")
if f then f:close() end
local chunk = loadstring and loadstring(packSrc) or load(packSrc)
local pack = chunk()

local function run_move_script(moveId, moveName)
  test(string.format("%s (Move #%d) - bytecode script execution", moveName, moveId), function()
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

run_move_script(164, "Substitute")
run_move_script(104, "Double Team")
run_move_script(327, "Sky Uppercut")
run_move_script(69, "Seismic Toss")
run_move_script(90, "Fissure")
run_move_script(213, "Attract")
run_move_script(262, "Memento")
run_move_script(272, "Role Play")
run_move_script(326, "Extrasensory")
run_move_script(266, "Follow Me")

print(string.format("\nPhase 4 Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
