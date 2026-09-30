#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_low_hp_hook_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local ModRuntime = require("src.mods.Runtime")
local Battle = require("src.core.game3.battle")

local plays, stops = 0, 0
Audio.playSe = function(id)
  if id == SE.SE_LOW_HEALTH then plays = plays + 1 end
end
Audio.stopSe = function(id)
  if id == SE.SE_LOW_HEALTH then stops = stops + 1 end
end

local function reset()
  plays, stops = 0, 0
  Battle._lowHpSong = false
  Battle._st = { player = { mon = { hp = 1, maxHp = 100 } } }
end

local function step(n)
  for _ = 1, n do Battle._updateLowHpMusic() end
end

reset()
step(3)
check(plays == 1, "no hook: siren starts once")

reset()
ModRuntime.hooks = {
  chains = { ["battle.low_health_alarm"] = {} },
  call = function(_, _, vanilla, ctx)
    ctx.on = false
    return vanilla(ctx)
  end,
}
step(3)
check(plays == 0, "hook forcing on=false suppresses siren")

reset()
local sawBattle = false
ModRuntime.hooks = {
  chains = { ["battle.low_health_alarm"] = {} },
  call = function(_, _, vanilla, ctx)
    sawBattle = ctx.battle == Battle._st and ctx.on == true
    return vanilla(ctx)
  end,
}
step(2)
check(plays == 1 and sawBattle, "pass-through hook sees on=true and battle, siren plays once")

if failed > 0 then
  print(failed .. " failed")
  os.exit(1)
end
print("all passed")
os.exit(0)
