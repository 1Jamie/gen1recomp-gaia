package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local SpriteRenderer = require("src.render.SpriteRenderer")
local BattleState = require("src.battle.BattleState")

local prevVersion, prevMode, prevDark = GameVersion.get(), PaletteFX.mode, PaletteFX.darkWorld()

local bakes = {}
local realObp = SpriteRenderer.obpImage
SpriteRenderer.obpImage = function(path, colors, group)
  bakes[#bakes + 1] = { path = path, colors = colors, group = group }
  return realObp(path, colors, group)
end

local party = {
  { hp = 10 }, { hp = 10, status = "PSN" }, { hp = 0 },
}

local function ballBake(version)
  GameVersion.set(version)
  PaletteFX.setMode("ogred")
  PaletteFX.setDarkWorld(true)
  local before = #bakes
  PaletteFX.clearSpriteRedraws()
  PaletteFX.setPass("ui")
  local ok, err = pcall(BattleState.drawBallRow, BattleState, party, 88, 80, 8)
  PaletteFX.setPass(nil)
  PaletteFX.clearSpriteRedraws()
  check(ok, version .. " drawBallRow runs headless" .. (ok and "" or (": " .. tostring(err))))
  for i = before + 1, #bakes do
    if bakes[i].path == "assets/generated/battle/balls.png" then return bakes[i] end
  end
  return nil
end

do
  local b = ballBake("blue")
  check(b ~= nil, "blue: dark cave battle bakes the ball row through OBP")
  eq(b and b.group, "gbcobj_blue", "blue: ball row bake carries no dark shift")
  eq(b and b.colors, PaletteFX.GBC_OBJ_BLUE, "blue: ball row bakes the lit OBJ ramp")
  local colors, group = PaletteFX.ogObj()
  eq(group, "gbcobj_bluedark", "blue: overworld OBJ still takes the dark-cave shift")
  check(colors ~= PaletteFX.GBC_OBJ_BLUE, "blue: overworld OBJ colors are the shifted ramp")
end

do
  local b = ballBake("red")
  eq(b and b.group, "gbcobj_soft", "red: ball row bake carries no dark shift")
  eq(b and b.colors, PaletteFX.OG_RED_SOFT_OBJ, "red: ball row bakes the lit OBJ ramp")
  local _, group = PaletteFX.ogObj()
  eq(group, "gbcobj_softdark", "red: overworld OBJ still takes the dark-cave shift")
end

do
  PaletteFX.setDarkWorld(true)
  local colors, group = PaletteFX.dmgObjLit()
  eq(group, "obp0", "dmgObjLit ignores the dark-cave shift")
  eq(colors, PaletteFX.OBP0_SHADES, "dmgObjLit is the lit OBP0 ramp")
  local _, dgroup = PaletteFX.dmgObj()
  eq(dgroup, "obp0dark", "dmgObj keeps the dark-cave shift for overworld sprites")
end

SpriteRenderer.obpImage = realObp
PaletteFX.setDarkWorld(prevDark)
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish()
