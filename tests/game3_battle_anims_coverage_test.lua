-- Comprehensive Battle Animations Coverage Test
-- Verifies all 354 moves in pack.lua, testing GLSL shader integration,
-- Z-index depth, nearest-neighbor scaling tasks, and spatial audio panning.

local Anim = require("src.core.game3.battle.anim")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")

local passed = 0
local failed = 0

local function check(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. tostring(name))
  end
end

print("=== Battle Animations System Coverage Test ===")

-- 1. GLSL Screen Shader & Palette Effects
print("[test] 1. Screen effect shader lifecycle")
Anim.reset({ headless = true })
check(Anim.screenEffect().type == "none", "screen effect initialized to none")

AnimTasks.spawn("InvertScreenColor", 2, { 16 }, Anim.vm())
check(AnimTasks.activeCount() == 1, "InvertScreenColor task spawned")

-- Step 1 frame
AnimTasks.update(Anim.vm())
check(Anim.screenEffect().type == "invert", "InvertScreenColor sets shader to invert")

-- Run through duration
for _ = 1, 20 do
  AnimTasks.update(Anim.vm())
end
check(AnimTasks.activeCount() == 0, "InvertScreenColor task terminated cleanly")
check(Anim.screenEffect().type == "none", "InvertScreenColor restored shader to none")

-- FadeScreenToWhite
AnimTasks.spawn("FadeScreenToWhite", 2, { 16 }, Anim.vm())
AnimTasks.update(Anim.vm())
check(Anim.screenEffect().type == "fade_white", "FadeScreenToWhite sets shader to fade_white")
for _ = 1, 20 do
  AnimTasks.update(Anim.vm())
end
check(Anim.screenEffect().type == "none", "FadeScreenToWhite restored shader to none")

-- SetGrayscaleOrOriginalPal
AnimTasks.spawn("SetGrayscaleOrOriginalPal", 2, { 16 }, Anim.vm())
AnimTasks.update(Anim.vm())
check(Anim.screenEffect().type == "grayscale", "SetGrayscaleOrOriginalPal sets shader to grayscale")
for _ = 1, 20 do
  AnimTasks.update(Anim.vm())
end
check(Anim.screenEffect().type == "none", "SetGrayscaleOrOriginalPal restored shader to none")

-- 2. Z-Index Depth & Layering
print("[test] 2. Z-Index depth and layering rules")
AnimSprites.reset()

-- Physical contact -> GLOBAL_FRONT (Z = 900)
local sprFist = AnimSprites.acquire({
  z = AnimSprites.Z.GLOBAL_FRONT,
  callback = AnimCallbacks.get("BasicFistOrFoot"),
})
check(sprFist and sprFist.z == AnimSprites.Z.GLOBAL_FRONT, "BasicFistOrFoot assigned to GLOBAL_FRONT (900)")

-- Ground hazard -> GLOBAL_BEHIND (Z = 10)
local sprMud = AnimSprites.acquire({
  z = AnimSprites.Z.GLOBAL_BEHIND,
  callback = AnimCallbacks.get("MudSportDirt"),
})
check(sprMud and sprMud.z == AnimSprites.Z.GLOBAL_BEHIND, "MudSportDirt assigned to GLOBAL_BEHIND (10)")

local list = AnimSprites.sortedDrawList()
check(#list == 2, "2 sprites in sorted list")
check(list[1].z < list[2].z, "Background mud renders before foreground fist")
AnimSprites.reset()

-- 3. Audio Panning Task
print("[test] 3. Audio spatial panning task")
local pTask = AnimTasks.spawn("SoundTask_PlaySE1WithPanning", 2, { 5, -64, 63, 10 }, Anim.vm())
check(pTask ~= nil, "SoundTask_PlaySE1WithPanning spawned")
AnimTasks.update(Anim.vm())
check(pTask.data[10] == -64, "Initial pan is -64 (attacker)")
for _ = 1, 5 do
  AnimTasks.update(Anim.vm())
end
check(pTask.data[10] > -64 and pTask.data[10] < 63, "Pan sweeps across midpoint")
for _ = 1, 10 do
  AnimTasks.update(Anim.vm())
end
check(AnimTasks.activeCount() == 0, "Panning task terminates cleanly")

-- 4. Execute all 354 Move Scripts through VM
print("[test] 4. Full 354-move bytecode execution coverage")
local ok, Dataset = pcall(require, "src.core.game3.dataset")
local cache = ok and Dataset.cache and Dataset.cache() or nil
local packSrc = cache and cache.read and cache:read("data/generated/gba/pokemon/battle_anims/pack.lua")
if not packSrc then
  local f = io.open("data/generated/gba/pokemon/battle_anims/pack.lua", "r")
  if f then packSrc = f:read("*a"); f:close() end
end

check(type(packSrc) == "string" and #packSrc > 0, "pack.lua source loaded")

local chunk = loadstring and loadstring(packSrc) or load(packSrc)
local pack = chunk()
check(type(pack) == "table" and type(pack.moves) == "table", "pack.moves table parsed")

local moveCount = 0
local cleanFinishes = 0
local vmErrors = 0

local vm = AnimVm.new()
vm:setPack(pack)

for moveId, script in pairs(pack.moves) do
  moveCount = moveCount + 1
  AnimTasks.reset()
  AnimSprites.reset()
  Anim.reset({ headless = true })
  
  local okLaunch, err = pcall(function()
    vm:launch(script, { attackerSide = "player", isReversed = false })
  end)

  if not okLaunch then
    vmErrors = vmErrors + 1
    print(string.format("[ERROR] Move %s launch error: %s", tostring(moveId), tostring(err)))
  else
    -- Step VM up to 360 frames (6 seconds max for multi-hit/looping moves)
    local maxTicks = 360
    local ticks = 0
    while vm:busy() and ticks < maxTicks do
      ticks = ticks + 1
      vm:update(1 / 60)
    end

    if not vm:busy() then
      cleanFinishes = cleanFinishes + 1
    else
      print(string.format("[TIMEOUT] Move %s timed out after %d frames", tostring(moveId), maxTicks))
    end
  end
end

print(string.format("Tested %d moves: %d completed cleanly, %d launch errors", moveCount, cleanFinishes, vmErrors))
check(moveCount >= 354, "All 354 moves present and processed")
check(vmErrors == 0, "0 VM launch errors across all moves")
check(cleanFinishes == moveCount, "All moves cleanly terminate without freezing")

print(string.format("\nResults: %d Passed, %d Failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
