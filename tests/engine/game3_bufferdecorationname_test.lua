-- pokeemerald/src/scrcmd.c:1599 bufferdecorationname copies gDecorations[id].name.
-- Lanette's givedecoration DECOR_LOTAD_DOLL (99) was printing "99" because
-- bufferName never asked the decoration cache.
--   luajit tests/engine/game3_bufferdecorationname_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local DecorInv = require("src.core.game3.rse.decoration_inventory")
local Adapters = require("src.core.game3.scripting.adapters")
local Vm = require("src.core.game3.scripting.vm")
local Ops = require("src.core.game3.scripting.ops_a")
local Flags = require("src.core.game3.scripting.flags")

DecorInv.install({
  decorations = {
    [99] = { id = 99, name = "LOTAD DOLL", category = 6 },
  },
})

local stub = Adapters.stub({})
local host = Adapters.host(nil, nil, nil)

eq(stub.bufferName("bufferdecorationname", 99), "LOTAD DOLL", "stub names decoration 99")
eq(host.bufferName("bufferdecorationname", 99), "LOTAD DOLL", "host names decoration 99")
eq(stub.bufferName("bufferdecorationname", 1), nil, "unknown decoration stays unresolved")

local vm = Vm.new({
  store = Flags.newStore(),
  scripts = { t = { { op = "end" } } },
  adapters = stub,
})
vm:start("t")
Ops.dispatch(vm, { op = "setvar", [1] = 0x8000, [2] = 99 })
Ops.dispatch(vm, { op = "bufferdecorationname", dest = 1, src = 0x8000 })
eq(vm.ctx.stringVars[2], "LOTAD DOLL", "VAR_0x8000 decoration name fills STR_VAR_2")

local home = os.getenv("HOME")
local cache = home and (home .. "/Library/Application Support/LOVE/pokemon-love2d/emerald/data/generated/gba/decorations/decorations.lua")
local f = cache and io.open(cache, "rb")
if f then
  local src = f:read("*a")
  f:close()
  DecorInv.reset()
  local pack = assert(load(src, "@decorations.lua", "t", {}))()
  DecorInv.install(pack)
  eq(stub.bufferName("bufferdecorationname", 99), "LOTAD DOLL", "emerald cache decoration 99 is LOTAD DOLL")
end

T.finish("game3_bufferdecorationname_test")
