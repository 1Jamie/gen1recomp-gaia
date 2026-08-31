-- ../pokecrystal/engine/battle/battle_transition.asm:584

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Transition = require("src.ui.gen2.BattleTransition")

local function make(opts)
  opts.environment = opts.environment or "TOWN"
  local state = Transition.new(nil, opts)
  state.drawCells = function(self, _w, _h, cells, byte, ly)
    self.drawn = { cells = cells, byte = byte, ly = ly }
  end
  return state
end

local function frame(state)
  state.drawn = nil
  state:drawWidescreen(160, 144)
  return state.drawn
end

local function pastBall(state)
  state:update()
  state:update()
end

do
  local cells = Transition.pokeballCells()
  T.eq(#cells, 112, ".PokeBallTransition sets 112 bits")
  local minX, minY, maxY = 20, 18, -1
  for _, cell in ipairs(cells) do
    minX = math.min(minX, cell[1])
    minY = math.min(minY, cell[2])
    maxY = math.max(maxY, cell[2])
  end
  T.eq(minX, Transition.POKEBALL_X, "the stamp starts at hlcoord 2, 1 (x)")
  T.eq(minY, Transition.POKEBALL_Y, "the stamp starts at hlcoord 2, 1 (y)")
  T.eq(maxY - minY + 1, 16, "and it is sixteen rows tall")
end

do
  T.eq(Transition.ballShade(nil), 4, "colour 3 shows shade 3 at the identity")
  T.eq(Transition.ballShade(Transition.flashByte({ 3, 2, 1, 0 })), 4,
    "...which is what the identity row packs to")
  T.eq(Transition.ballShade(Transition.flashByte({ 0, 0, 0, 0 })), 1,
    "the white-out row takes the ball with it")
  T.eq(Transition.ballShade(Transition.flashByte({ 1, 0, 0, 0 })), 2,
    "and a mid row moves it one step along the ramp")
end

do
  local state = make({ trainer = true })
  T.eq(state.phase, "pokeball", "a trainer battle stamps the ball first")
  T.check(frame(state) ~= nil, "and draws it before the flash")

  pastBall(state)
  T.eq(state.phase, "flash", "then the flash starts")
  local seen = 0
  for _ = 1, Transition.FLASH_FRAMES do
    if frame(state) then seen = seen + 1 end
    state:update()
  end
  T.eq(seen, Transition.FLASH_FRAMES,
    "the ball is still in the tilemap for every flash frame")
  T.eq(state.phase, "outro", "the flash hands off to the outro")

  local drawn, missed, guard = 0, 0, 0
  while state.phase == "outro" and guard < 400 do
    if frame(state) then drawn = drawn + 1 else missed = missed + 1 end
    state:update()
    guard = guard + 1
  end
  T.check(drawn > 0, "and the outro paints over a ball that is still there")
  T.eq(missed, 0, "no outro frame drops it early")
  T.eq(state.phase, "black", "the outro ends on the black hold")
  T.eq(frame(state), nil, "which is solid black, ball included")
end

do
  local state = make({ trainer = false })
  T.eq(state.phase, "flash", "a wild battle has no ball to stamp")
  local drew, guard = false, 0
  while not state.finished and guard < 400 do
    if frame(state) then drew = true end
    state:update()
    guard = guard + 1
  end
  T.eq(drew, false, "and never draws one")
end

do
  local state = make({ trainer = true, dark = true })
  T.eq(state.phase, "pokeball", "a DARKNESS trainer battle still stamps it")
  pastBall(state)
  T.eq(state.phase, "outro", "...and skips straight to the outro")
  T.check(frame(state) ~= nil, "...with the ball still on screen")
end

do
  local state = make({
    trainer = true, environment = "CAVE", playerLevel = 10, enemyLevel = 5,
  })
  T.eq(state.style, "sine", "a cave trainer battle wobbles")
  pastBall(state)
  local guard = 0
  while state.phase == "flash" and guard < 400 do
    state:update()
    guard = guard + 1
  end
  state:update()
  local drawn = frame(state)
  T.check(drawn ~= nil, "the ball rides the sine outro")
  T.check(drawn and drawn.ly ~= nil,
    "...and takes the frame's rSCX overrides with it")
end

T.finish("gen2 trainer ball lifetime bug 2021")
