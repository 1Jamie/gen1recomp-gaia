-- wLastDexMode (engine/pokedex/pokedex.asm:60, :97) (#1474)
--   luajit tests/engine/gen2_dex_mode_persist_bug1474.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local PokedexMenu = require("src.ui.gen2.PokedexMenu")

local save = { position = { map = "ROUTE_30" } }
local game = { data = {}, save = save }

local first = PokedexMenu.new(game, {})
eq(first.modeIndex, 1, "a save with no remembered mode opens in NEW")

-- what the OPTION screen's .ChangeMode leaves behind
first.modeIndex = 3
first:close()
eq(save.lastDexMode, "A-Z", "closing the dex writes the live mode into the save")

local second = PokedexMenu.new(game, {})
eq(second.modeIndex, 3, "reopening the dex restores the remembered mode")

second.modeIndex = 2
second:close()
eq(PokedexMenu.new(game, {}).modeIndex, 2, "OLD survives the same way")

local fresh = PokedexMenu.new({ data = {}, save = {} }, {})
eq(fresh.modeIndex, 1, "a fresh save still starts on NEW")

local closed = false
local menu = PokedexMenu.new(game, { onClose = function() closed = true end })
menu:close()
check(closed, "close still runs the caller's onClose")

T.finish("gen2 pokedex mode persistence bug 1474")
