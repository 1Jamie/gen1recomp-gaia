#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_map_sections").install()

local T = require("tests.harness")
local eq = T.eq
require("tests.game3_cache").stubSpeciesNames()

require("src.core.GameVersion").set("firered")
package.loaded["src.core.game3.audio"] = {
  playSe = function() end, playCry = function() end,
  playSong = function() end, stopAll = function() end,
}
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local Ui = require("src.core.game3.battle.ui")

eq(Ui.ppColorState(20, 20), 3, "full PP is normal")
eq(Ui.ppColorState(10, 20), 0, "half PP is yellow")
eq(Ui.ppColorState(5, 20), 1, "quarter PP is orange")
eq(Ui.ppColorState(0, 20), 2, "zero PP is red")
eq(Ui.ppColorState(2, 3), 0, "2/3 PP is yellow on the battle menu")
eq(Ui.ppColorState(1, 3), 1, "1/3 PP is orange")
eq(Ui.ppColorState(0, 3), 2, "zero small-move PP is red")
eq(Ui.ppColorState(1, 2), 1, "1/2 PP is orange for a 2-PP move")
eq(Ui.ppColorState(0, 2), 2, "zero 2-PP move is red")
eq(Ui.ppColorState(1, 1), 3, "full 1-PP move is normal")
eq(Ui.ppColorIndex(10, 20), 1, "battle yellow maps to the yellow ROM palette row")
eq(Ui.ppColorIndex(5, 20), 2, "battle orange maps to the orange ROM palette row")
eq(Ui.ppColorIndex(0, 20), 3, "battle red maps to the red ROM palette row")
eq(Ui.ppColorIndex(20, 20), 0, "battle normal maps to the normal ROM palette row")

T.finish("game3 battle PP color #2501")
