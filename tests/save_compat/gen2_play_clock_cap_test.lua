package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")

local DATA = {
  items = K.gen2Data.items, maps = K.gen2Data.maps,
  pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL", genderRatio = 0x1F } },
  moves = { TACKLE = { index = 33, pp = 35 }, GROWL = { index = 43, pp = 40 } },
}

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local S = require("src.save_convert.Gen2State").symsFor(v)
  local src = G2.build({ version = v, patch = function(b)
    b[S.wGameTimeCap] = 1
    b[S.wGameTimeHours], b[S.wGameTimeHours + 1] = 0x03, 0xE7
    b[S.wGameTimeMinutes], b[S.wGameTimeSeconds], b[S.wGameTimeFrames] = 59, 59, 0
  end })
  local save = assert(Gen2Save.decode(src, v, DATA))
  eq(save.playTime.capped, true, v .. ": the cart's GAME_TIME_CAPPED bit imports")
  eq(save.playTime.hours, 999, v .. ": at 999 hours")
  local out = assert(Gen2Save.encode(save, v, src, DATA))
  eq(out:byte(S.wGameTimeCap + 1), 1, v .. ": and exports")
  save.playTime = { hours = 999, minutes = 59, seconds = 59, frames = 0, capped = true }
  local bare = assert(Gen2Save.encode(save, v, G2.build({ version = v }), DATA))
  eq(bare:byte(S.wGameTimeCap + 1) % 2, 1, v .. ": an engine save that hit the cap sets the bit on a template that lacked it")
  local free = assert(Gen2Save.decode(G2.build({ version = v }), v, DATA))
  eq(free.playTime.capped, nil, v .. ": an uncapped cart carries no flag")
end

T.finish()
