local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_message_speed_2570"
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "message_speed_2570")
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "message speed boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "message speed field reached") then return finish() end
  local Options = require("src.core.game3.options")
  local Message = require("src.ui.game3.message")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Space = require("src.core.game3.scripting.space")
  local Map = require("src.core.game3.map")
  local Flags = require("src.core.game3.scripting.flags")
  local Fade = require("src.ui.game3.fade")
  local rse = session.version == "emerald"
  local defs = Flags.forVersion(session.version)
  local mapId = rse and "EM_OLDALE_TOWN_POKEMON_CENTER_1F" or "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
  local function waitFor(pred, limit)
    for _ = 1, limit do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local realShow = Message.show
  local observed
  Message.show = function(text, opts)
    local result = realShow(text, opts)
    observed = { first = Message._pages[1], count = #Message._pages, typing = Message.isTyping() }
    return result
  end
  local cases = rse and {
    { id = 2, name = "oldale_gentleman" },
    { id = 3, name = "oldale_boy" },
    { id = 4, name = "oldale_girl_unavailable", dex = false },
    { id = 4, name = "oldale_girl_available", dex = true },
  } or {
    { id = 2, name = "viridian_gentleman" },
    { id = 3, name = "viridian_boy" },
  }
  for _, case in ipairs(cases) do
    for speed = 0, 2 do
      Options.set(session, "textSpeed", speed)
      if rse and case.dex ~= nil then
        Flags.setFlag(Space.store, nil, assert(defs.IDS.FLAG_SYS_POKEDEX_GET), case.dex)
      end
      Map.load(nil, game, mapId, { x = 7, y = 7, facing = "up" })
      if not check(waitFor(function()
          return not Field.locked and not Fade.active and not (Space.vm and Space.vm:isRunning())
        end, 600), case.name .. " map settles") then Message.show = realShow return finish() end
      local eo = Objects.find(case.id)
      if not check(eo ~= nil, case.name .. " NPC exists") then Message.show = realShow return finish() end
      eo.frozen = true
      Player.reset(eo.cellX, eo.cellY + 1, "up")
      Player.syncToHost(game)
      observed = nil
      U.tap(game, "a")
      if not check(waitFor(function() return observed ~= nil and Message.isOpen() end, 120),
          case.name .. " opens from one A") then Message.show = realShow return finish() end
      check(observed.count >= 2, case.name .. " cached ROM text contains multiple paragraphs")
      check(observed.typing, case.name .. " option " .. speed .. " starts by typing")
      check(Message._page == 1 and Message.currentPage() == observed.first,
        case.name .. " option " .. speed .. " preserves first paragraph after opening A")
      if not check(waitFor(Message.isWaiting, 1600), case.name .. " first paragraph prints") then
        Message.show = realShow return finish()
      end
      if speed == 0 then U.still(game, DIR .. "/" .. case.name .. "_first.png") end
      for page = 2, observed.count do
        U.tap(game, "a")
        check(Message._page == page, case.name .. " fresh A advances to paragraph " .. page)
        if not check(waitFor(Message.isWaiting, 1600), case.name .. " paragraph " .. page .. " prints") then
          Message.show = realShow return finish()
        end
      end
      if speed == 0 then U.still(game, DIR .. "/" .. case.name .. "_last.png") end
      for _ = 1, 120 do
        if not Message.isOpen() and not (Space.vm and Space.vm:isRunning()) and not Field.locked then break end
        U.tap(game, "a")
        U.wait(2)
      end
      check(not Message.isOpen() and not (Space.vm and Space.vm:isRunning()) and not Field.locked,
        case.name .. " script terminates and unlocks after final paragraph")
    end
  end
  Message.show = realShow
  Message.show("Instant", { speed = 0 })
  check(Message.isWaiting(), "explicit speed zero remains instant in live field printer")
  Message.close()
  finish()
end
