-- engine/battle_anims/anim_commands.asm:603 BattleAnimCmd_BGP

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local AnimRunner = require("src.battle.gen2.AnimRunner")
local BgEffects = require("src.battle.gen2.BgEffects")
local GbcPalette = require("src.render.GbcPalette")

-- data/moves/animations.asm:4509 BattleAnim_ShadowBall
local SHADOW_BALL = {
  { "2gfx", "BATTLE_ANIM_GFX_EGG", "BATTLE_ANIM_GFX_SMOKE" },
  { "bgp", 0x1b },
  { "sound", 6 * 4 + 2, 0 },
  { "obj", "BATTLE_ANIM_OBJ_SHADOW_BALL", 64, 92, 0x2 },
  { "wait", 32 },
}

do
  local runner = AnimRunner.new({
    data = { scripts = { SHADOW_BALL = SHADOW_BALL } },
  })
  runner:start("SHADOW_BALL")
  T.eq(runner.bg.bgp, BgEffects.NORMAL_PAL, "identity ramp before the script")
  T.check(runner:step(), "the script is still running after frame one")
  T.eq(runner.bg.bgp, 0x1b,
    "anim_bgp $1b lands in wBGP: the inverted ramp the view must apply")
  runner.bg:reset()
  T.eq(runner.bg.bgp, BgEffects.NORMAL_PAL,
    "BattleAnim_RevertPals puts the identity back")
end

do
  T.eq(GbcPalette.BGP_IDENTITY, 0xe4, "dc 3, 2, 1, 0")
  local colors = { "c0", "c1", "c2", "c3" }
  local out = GbcPalette.remap(colors, 0x1b)
  T.eq(out[1], "c3", "$1b is dc 0, 1, 2, 3: colour 0 shows shade 3")
  T.eq(out[2], "c2", "colour 1 shows shade 2")
  T.eq(out[3], "c1", "colour 2 shows shade 1")
  T.eq(out[4], "c0", "colour 3 shows shade 0")
  T.check(GbcPalette.remap(colors, 0xe4) == colors,
    "the identity byte returns the palette untouched")
end

T.finish("gen2 shadow ball bgp bug 1269")
