package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")

local fixtures = {}
for _, c in ipairs(G2.cases()) do fixtures[c.id] = c end

local function u8(s, at) return s:byte(at + 1) end

-- constants/ram_constants.asm:235 STATUSFLAGS_FLASH_F
for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local L = Gen2Save.layoutFor(v)
  local c = fixtures["g2." .. v .. ".basic"]
  local save = assert(K.import(2, c.version, c.bytes))
  eq(save.flashUsed, nil, v .. ": a fixture with the bit clear imports unflashed")
  save.flashUsed = true
  local out = assert(K.export(2, v, save, false))
  eq(math.floor(u8(out, L.wStatusFlags) / 4) % 2, 1, v .. ": export sets STATUSFLAGS_FLASH_F")
  local back = assert(K.import(2, v, out))
  eq(back.flashUsed, true, v .. ": the bit imports as flashUsed")
  local before = u8(out, L.wStatusFlags)
  back.flashUsed = nil
  local cleared = assert(K.export(2, v, back, false))
  eq(u8(cleared, L.wStatusFlags), before - 4, v .. ": clearing it touches only bit 2")
  check(K.import(2, v, cleared).flashUsed == nil, v .. ": and the cleared bit reads back unflashed")
end

T.finish()
