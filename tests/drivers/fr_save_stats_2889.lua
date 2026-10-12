local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("fr_save_stats_2889", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_save_stats_2889")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local StartMenu = require("src.ui.game3.start_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local session = Runtime.getSession()
  session.name = "RED"
  if not S.check(F.goTo(game, "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", 7, 6, "up"), "viridian pokemon center loaded") then
    return S.finish()
  end

  local calls = {}
  local draw = FrlgFont.draw
  FrlgFont.draw = function(text, x, y, opts)
    calls[#calls + 1] = { text = text, x = x, y = y, opts = opts or {} }
    return draw(text, x, y, opts)
  end

  local function openSave()
    U.tap(game, "start")
    U.wait(20)
    if not S.check(StartMenu.isOpen(), "start menu open") then return false end
    local idx
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == "save" then idx = i end
    end
    if not S.check(idx ~= nil, "save entry listed") then return false end
    for _ = 1, 16 do
      if StartMenu.cursor == idx then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(30)
    return S.check(SaveMenu.isOpen(), "save window open")
  end

  local function find(pred)
    for i = #calls, 1, -1 do
      if pred(calls[i]) then return calls[i] end
    end
  end

  local function checkWindow(tag, dex, shot)
    calls = {}
    S.still(game, shot)
    local header = find(function(c) return tostring(c.text):find("VIRIDIAN", 1, true) end)
    S.check(header and header.opts.colors and header.opts.colors.fg == FrlgFont.STDPAL[8]
      and header.opts.colors.shadow == FrlgFont.STDPAL[9], tag .. " location header blue")
    S.check(header and not header.opts.small and header.y == 8, tag .. " location header normal font at y 0")
    local name = find(function(c) return c.text == "RED" end)
    S.check(name and not name.opts.small and name.x == 68 and name.y == 22, tag .. " player name normal font at (60,14)")
    local smalls, rows = 0, dex and 8 or 6
    for _, c in ipairs(calls) do
      if c.opts.small and c.y >= 22 and c.y <= 64 then smalls = smalls + 1 end
    end
    S.check(smalls == rows - 1, tag .. " labels and values small font (" .. smalls .. ")")
    local time = find(function(c) return tostring(c.text):match("^%d+:%d%d$") end)
    S.check(time and time.opts.small and time.x == 68 and time.y == 8 + (dex and 56 or 42),
      tag .. " time small font at x 60")
  end

  if not openSave() then return S.finish() end
  checkWindow("no dex:", false, "2889_01_save_window_no_dex.png")
  U.tap(game, "b")
  U.wait(20)
  if StartMenu.isOpen() then U.tap(game, "b") end
  U.wait(20)

  F.setFlag("FLAG_SYS_POKEDEX_GET", true)
  if not openSave() then return S.finish() end
  checkWindow("dex:", true, "2889_02_save_window_dex.png")
  U.tap(game, "b")
  U.wait(10)
  FrlgFont.draw = draw
  return S.finish()
end
