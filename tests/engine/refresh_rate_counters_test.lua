-- Presentation counters that draw code samples must advance at the fixed
-- 60Hz logic rate, not once per rendered frame:
--   * Player:pose's surf bob (a 144Hz display bobbed 2.4x too fast, and the
--     battle-transition wipe, which draws the player twice a frame, doubled
--     it) -- now counted in Game:step logic steps (Game.logicStep);
--   * the battle text box's ScrollTextUpOneLine offset (scrollPx), which
--     BattleState:drawTextArea / WideBattle counted down per draw -- now
--     BattleState:tickTextScroll, run once per update step.
-- Also pins the per-frame caching in the battle OAM colorizer: one
-- sgbBattlePals() per frame, shared color triples, and AnimPlayer's
-- uniform sends always matching the colors of the cell being painted.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

-- ---------------------------------------------------------------- surf bob
do
  local prevGame = package.loaded["src.core.Game"]
  local fakeGame = { logicStep = 10 }
  package.loaded["src.core.Game"] = fakeGame
  local Player = require("src.world.Player")
  local p = setmetatable({ surfing = true, px = 0, py = 0, facing = "down",
                           progress = 0, animClock = 0 }, Player)
  -- the wipe's double draw (and any 120/144Hz frame without a new step)
  p:pose(); p:pose(); p:pose()
  T.eq(p.bobTimer, 1, "three draws inside one logic step advance the bob once")
  fakeGame.logicStep = 11
  p:pose(); p:pose()
  T.eq(p.bobTimer, 2, "the next step advances it exactly once more")
  fakeGame.logicStep = 14
  p:pose()
  T.eq(p.bobTimer, 5, "steps run between draws (fast-forward) all count")
  -- the 32-step cycle: low for bob 0..15, one pixel down for 16..31
  local lows, highs = 0, 0
  for _ = 1, 32 do
    fakeGame.logicStep = fakeGame.logicStep + 1
    local _, _, y = p:pose()
    local y2 = select(3, p:pose()) -- a second draw in the same step
    T.eq(y2, y, "a repeat draw in the same step shows the same bob")
    if y == 0 then lows = lows + 1 else highs = highs + 1 end
  end
  T.eq(lows, 16, "16 steps of the cycle sit on the baseline")
  T.eq(highs, 16, "16 steps of the cycle sit a pixel down")
  -- no running Game (headless callers): the old per-call tick
  fakeGame.logicStep = nil
  local before = p.bobTimer
  p:pose(); p:pose()
  T.eq(p.bobTimer, (before + 2) % 32, "without a step clock each pose ticks")
  package.loaded["src.core.Game"] = prevGame
end

-- --------------------------------------------------------- battle scroll
local BattleState = require("src.battle.BattleState")
do
  local b = setmetatable({ phase = "messages", current = {}, scrollPx = 8 },
                         { __index = BattleState })
  local seen = {}
  for i = 1, 5 do
    b:tickTextScroll()
    seen[i] = tostring(b.scrollPx)
  end
  T.eq(table.concat(seen, ","), "6,4,2,nil,nil",
       "2px per logic step, cleared at 0 (the draws saw 6,4,2,0 before)")
  b.scrollPx = 8
  b.phase = "menu"
  b:tickTextScroll()
  T.eq(b.scrollPx, 8, "no count-down while the message box is not shown")
  b.phase, b.current, b.animPlaying, b.msgHold = "messages", nil, nil, true
  b:tickTextScroll()
  T.eq(b.scrollPx, 6, "msgHold keeps the box (and its scroll) live")
end

-- ------------------------------------------- battle OAM colorizer caching
do
  local zoneA = { { 255, 255, 255 }, { 200, 0, 0 }, { 100, 0, 0 }, { 0, 0, 0 } }
  local zoneB = { { 255, 255, 255 }, { 0, 200, 0 }, { 0, 100, 0 }, { 0, 0, 0 } }
  local palsCalls = 0
  local b = setmetatable({}, { __index = BattleState })
  b.sgbBattlePals = function()
    palsCalls = palsCalls + 1
    return { [0] = zoneA, [1] = zoneB, [2] = zoneA, [3] = zoneB }
  end
  local PaletteFX = require("src.render.PaletteFX")
  local realObp = PaletteFX.usesSpriteObp
  PaletteFX.usesSpriteObp = function() return false end
  local memo = {}
  local c1 = b:animSpriteColors({ obp = "e4", x = 20, y = 20 }, 0, 0, memo)
  local c2 = b:animSpriteColors({ obp = "e4", x = 20, y = 28 }, 0, 8, memo)
  local c3 = b:animSpriteColors({ obp = "e4", x = 20, y = 20 }, 8, 8, memo)
  T.eq(palsCalls, 1, "one sgbBattlePals per frame memo")
  T.check(c1 == c2, "same zone + obp shares one triple table")
  T.check(c3 ~= c1, "the enemy-HUD zone resolves its own triple")
  T.eq(math.floor(c1[1][1] * 255 + 0.5), 200, "e4 color 1 is the zone's shade 1")
  T.eq(math.floor(c3[1][2] * 255 + 0.5), 200, "enemy HUD wears zone 1's shade 1")
  local fresh = b:animSpriteColors({ obp = "e4", x = 20, y = 20 }, 0, 0)
  T.eq(palsCalls, 2, "without a memo it resolves the palettes itself")
  T.same(fresh, c1, "memoized and unmemoized colors agree")
  PaletteFX.usesSpriteObp = realObp

  -- AnimPlayer.drawSprites: every blit must see the uniforms of the cell
  -- it paints, whatever sends were skipped as redundant
  local AnimPlayer = require("src.battle.AnimPlayer")
  local g = love.graphics
  local saved = {}
  for _, k in ipairs({ "draw", "setShader", "getScissor", "intersectScissor",
                       "setScissor" }) do saved[k] = g[k] end
  local shader = { u = {} }
  function shader:send(name, v) self.u[name] = v end
  local realShaderFn = PaletteFX.shader
  PaletteFX.shader = function() return shader end
  local scissor
  local blits = {}
  g.draw = function()
    blits[#blits + 1] = { c1 = shader.u.c1, c2 = shader.u.c2,
                          c3 = shader.u.c3, clip = scissor }
  end
  g.setShader = function() end
  g.getScissor = function()
    if scissor then return scissor[1], scissor[2], scissor[3], scissor[4] end
  end
  g.intersectScissor = function(x, y, w, h) scissor = { x, y, w, h } end
  g.setScissor = function(x, y, w, h) scissor = x and { x, y, w, h } or nil end
  local tri = {}
  local function colorAt(px, py)
    -- a vertical zone boundary at x = 16
    local key = px < 16 and "L" or "R"
    tri[key] = tri[key] or { { px < 16 and 1 or 0, 0, 0 }, { 0, 0, 0 },
                             { 0, 0, 0 } }
    return tri[key]
  end
  local ap = setmetatable({ sheetImage = function() return {} end,
                            tileQuad = function() return {} end },
                          { __index = AnimPlayer })
  local sprites = {
    { x = 8 + 4, y = 16, tile = 1 },    -- rx 4: fully in L
    { x = 8 + 12, y = 16, tile = 1 },   -- rx 12: straddles L|R
    { x = 8 + 20, y = 16 + 3, tile = 1 }, -- rx 20, ry 3: R only (2 rows)
    { x = 8 + 5, y = 16, tile = 1 },    -- back to L
  }
  ap:drawSprites(sprites, function(_, px, py) return colorAt(px, py) end)
  -- expected paint order: L, L+R(slice), R, R(slice, same colors -> no
  -- repaint), L
  local want = { "L", "L", "R", "R", "L" }
  T.eq(#blits, #want, "one blit per tile plus one per differing cell")
  for i, w in ipairs(want) do
    local bl = blits[i]
    if bl then
      T.eq(bl.c1 and bl.c1[1], w == "L" and 1 or 0,
           ("blit %d paints with its cell's colors"):format(i))
    end
  end
  T.check(blits[3] and blits[3].clip ~= nil,
          "the straddling tile's second cell is scissored")
  for k, v in pairs(saved) do g[k] = v end
  PaletteFX.shader = realShaderFn
end

T.finish("refresh-rate-independent counters")
