package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

require("src.core.GameVersion").set("emerald")
require("src.core.game3.profile").reset()

local RomText = require("src.core.game3.rom_text")
RomText.at = function(name, i) return tostring(name) .. ":" .. tostring(i) end
RomText.plain = function(key) return tostring(key) end
RomText.count = function() return 3 end

local Runtime = require("src.core.game3.runtime")
local Boot = require("src.ui.game3.boot")
local BootModules = require("src.ui.game3.boot_modules")
local MainMenu = require("src.ui.game3.rse.main_menu_rse")
local OptionMenu = require("src.ui.game3.rse.option_menu")
local Stack = require("src.ui.game3.stack")
local Options = require("src.core.game3.options")
local Game3 = require("src.core.Game3")

local function fakeInput(button)
  return { wasPressed = function(_, b) return b == button end }
end

local function selectRow(id)
  local st = OptionMenu._st
  while #st.pages > 1 do OptionMenu.back() end
  for _, row in ipairs(st.pages[1].rows) do
    if row.id == "group.speed" then row.activate(st.ctx) end
  end
  local p = st.pages[#st.pages]
  for i, row in ipairs(p.rows) do
    if row.id == id then p.index = i return true end
  end
  return false
end

local function newGame(options)
  local wrote = 0
  local g = setmetatable({
    phase = "boot",
    options = options,
    writeOptions = function() wrote = wrote + 1 end,
  }, { __index = Game3 })
  return g, function() return wrote end
end

do
  local stale = newGame({ speedOverworld = 7, speedBattle = 7, speedMenu = 7 })
  Runtime._game = stale
  local g, wrote = newGame({ speedOverworld = 1, speedBattle = 1, speedMenu = 1,
    emerald = { textSpeed = 1 } })
  local state = Boot.new(g)
  check(state.custom ~= nil, "emerald boots through the custom boot modules")
  eq(state.custom.game, g, "boot state carries the game")
  local menu = MainMenu.new(state, { game = g, state = state, boot = Boot })
  eq(menu.game, g, "title main menu knows its game")

  menu:_openOptions()
  check(OptionMenu._st.ctx ~= nil, "title OPTION opened")
  eq(OptionMenu._st.ctx.options, g.options, "title OPTION edits the running game's options")
  check(OptionMenu._st.ctx.game == g, "title OPTION writes through the running game")

  check(selectRow("speedOverworld"), "OVERWORLD SPEED row reachable")
  OptionMenu.handleInput(fakeInput("right"))
  eq(g.options.speedOverworld, 2, "OVERWORLD SPEED lands on the game's options")
  eq(stale.options.speedOverworld, 7, "a stale Runtime game is untouched")
  check(wrote() > 0, "the change is persisted")
  g.phase = "field"
  eq(g:logicSpeed(), 2, "logicSpeed follows the menu change")

  check(selectRow("textSpeed"), "TEXT SPEED row reachable")
  OptionMenu.handleInput(fakeInput("right"))
  eq(Options.block(g.options).textSpeed, 2, "TEXT SPEED lands on the game's cart block")
  OptionMenu.close()
  menu.state = "options"
  menu:frame({ new = {}, held = {} })
  eq(state.textSpeed, 2, "closing OPTION refreshes the boot text speed for NEW GAME")
  Runtime._game = nil
  Stack.clear()
end

do
  local g = newGame({ speedOverworld = 1, speedBattle = 1, speedMenu = 1 })
  local state = BootModules.newState(Boot, { custom = true, params = {} }, g)
  eq(state.custom.game, g, "newState stores the game")
end

T.finish()
