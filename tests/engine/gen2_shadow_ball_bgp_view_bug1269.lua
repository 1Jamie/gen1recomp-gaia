-- engine/battle_anims/anim_commands.asm:1293 BattleAnim_SetBGPals
--
-- gen2_shadow_ball_bgp_bug1269.lua proves the runner lands bg.bgp and that
-- panelPalettes/remapTable would invert correctly; it never calls
-- BattleAnimView:present, which is where #1269 actually lived (the byte
-- was landed but nothing read it). This suite drives present() itself and
-- watches the shader binding around the backdrop draw.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

-- A remap shader that never touches the GPU: present() only needs
-- love.graphics.newShader to succeed so GbcPalette.remapShader() is
-- non-nil, which is the gate `present` checks before it will bake+remap.
local sentShader = { calls = {} }
function sentShader:send(name, ...) self.calls[#self.calls + 1] = name end
love.graphics.newShader = function() return sentShader end

-- The stub's stand-in Quad has no setViewport/getViewport, which blitRow
-- (the scanline blit present() drives 144 times a frame) needs; the real
-- love.graphics.Quad has both.
love.graphics.newQuad = function(x, y, w, h)
  local q = { x = x, y = y, w = w, h = h }
  function q:setViewport(x2, y2, w2, h2) self.x, self.y, self.w, self.h = x2, y2, w2, h2 end
  function q:getViewport() return self.x, self.y, self.w, self.h end
  return q
end

local T = require("tests.harness")
local GbcPalette = require("src.render.GbcPalette")
local BattleAnimView = require("src.ui.gen2.BattleAnimView")

local shaderDuringFill = "unset"
local realRectangle = love.graphics.rectangle
love.graphics.rectangle = function(...)
  if shaderDuringFill == "unset" then
    shaderDuringFill = love.graphics.getShader()
  end
  return realRectangle(...)
end

local view = BattleAnimView.new({}, nil)
-- data/moves/animations.asm:4509 BattleAnim_ShadowBall's anim_bgp $1b, with
-- no scroll and no rBGP window queued, is exactly the frame that used to
-- fall through the old `needsCanvas`-only early-out untouched.
local runner = {
  bg = {
    bgp = 0x1b,
    lcdc = nil,
    scx = 0,
    scy = 0,
    lyStart = 0,
    lyEnd = 0,
    lyBackup = {},
  },
}

T.check(love.graphics.getShader() == nil, "no shader bound before present")

view:present(runner, function() end, nil)

T.check(shaderDuringFill == sentShader,
  "the panel backdrop is drawn through the remap shader, not plainly")
T.check(love.graphics.getShader() == nil,
  "the shader is unbound again once present returns, so drawObjects is unaffected")

local sawRemapSend = false
for _, name in ipairs(sentShader.calls) do
  if name == "remapSrc" then sawRemapSend = true end
end
T.check(sawRemapSend, "GbcPalette.useRemap actually sent a remap table, not just bound the shader")

-- The identity byte must take the plain path: no bake, no shader, ever.
shaderDuringFill = "unset"
local identityRunner = {
  bg = { bgp = GbcPalette.BGP_IDENTITY, lcdc = nil, scx = 0, scy = 0,
    lyStart = 0, lyEnd = 0, lyBackup = {} },
}
local plainDrawCalled = false
view:present(identityRunner, function() plainDrawCalled = true end, nil)
T.check(plainDrawCalled, "identity rBGP takes the plain drawBg() path")
T.check(shaderDuringFill == "unset",
  "identity rBGP never touches the remap shader")

T.finish("gen2 shadow ball bgp view bug 1269")
