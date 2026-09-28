package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Sound = require("src.core.Sound")
local realPlay = Sound.play
local denied = 0
Sound.play = function(_, name)
  if name == "Denied" then denied = denied + 1 end
end
local textModule = package.loaded["src.render.TextBox"]
package.loaded["src.render.TextBox"] = {
  new = function(_, value, done)
    return { text = value, onDone = done }
  end,
}
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local scripts = require("data.scripts.story5")
local Suite = require("tests.harness").suite("locked gym gate sound")
local check, eq = Suite.check, Suite.eq
local function attempt(map, x, y, blocked)
  local presented, moves = nil, 0
  local game = {
    data = Data,
    save = { inventory = blocked and {} or { SECRET_KEY = true }, flags = {} },
    stack = { push = function(_, box) presented = box end },
  }
  local ow = {
    player = {},
    checkLedgeHop = function() return false end,
    scriptMove = function() moves = moves + 1 end,
  }
  local handled = scripts[map].onStep(game, ow, x, y)
  check(handled, map .. " lock handled")
  check(presented ~= nil, map .. " lock text shown")
  if presented and presented.onDone then presented.onDone() end
  eq(moves, 1, map .. " still pushes player back")
end
attempt("VIRIDIAN_CITY", 32, 8, true)
attempt("CINNABAR_ISLAND", 18, 4, true)
eq(denied, 0, "locked gym gates do not play Denied")
Sound.play = realPlay
package.loaded["src.render.TextBox"] = textModule
Suite.finish()
