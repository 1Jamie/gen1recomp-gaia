local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local CENTER_2F = "EM_OLDALE_TOWN_POKEMON_CENTER_2F"

local function now() return love.timer.getTime() end

return function(game)
  local d = S.new("em_link_plaza_save_continue", "/tmp/em_link_plaza_save_continue")
  local check = d.check
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return d.finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has a save") then return d.finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Party = require("src.core.game3.party")
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local Family = require("src.core.game3.link.family")
  local Plaza = require("src.core.game3.link.union_plaza_map")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")

  session = Runtime.getSession()
  while #(session.party or {}) < 2 do Party.giveMon(session, 280, 10) end
  session.healMap = "EM_OLDALE_TOWN_POKEMON_CENTER_1F"

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "MAY")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  local function wait(n)
    for _ = 1, n do
      relay:pump()
      U.wait(1)
    end
  end
  local function waitFor(cond, seconds, frames)
    local t0, n = now(), 0
    while not cond() do
      relay:pump()
      U.wait(1)
      n = n + 1
      if now() - t0 > (seconds or 5) and n > (frames or 60) then return false end
    end
    return true
  end
  local function drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or SaveMenu.isOpen() or Message.isOpen() then U.tap(game, "a") end
      wait(6)
    end
    return cond()
  end

  Link.connect()
  check(waitFor(function() return Client.state() == "online" end, 5, 120), "the Client is online on the relay")

  Flags.setVar(Space.store, ctx(), Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  Map.load(nil, game, CENTER_2F, { x = 6, y = 4, facing = "up" })
  wait(60)
  Flags.setFlag(Space.store, ctx(), Family.flag("emerald", "FLAG_SYS_POKEDEX_GET"), true)
  place(6, 4, "up")
  wait(12)
  U.tap(game, "a")
  local entered = drive(function() return Space.mapId == Plaza.MAP_ID and Union.state == "main" end, 30)
  if not check(entered, "the attendant walks the player into the Emerald plaza") then
    d.shot(game, "enter_failed")
    return d.finish()
  end
  wait(30)
  place(10, 12, "down")
  wait(10)
  d.shot(game, "01_plaza_before_save")

  local cableVar = Family.var("emerald", "VAR_CABLE_CLUB_STATE")
  check((tonumber(Flags.getVar(Space.store, ctx(), cableVar)) or 0) ~= 0, "VAR_CABLE_CLUB_STATE is set inside the plaza")
  local s = Runtime.getSession()
  d.note("dynamicWarp " .. tostring(s.dynamicWarp and s.dynamicWarp.map) .. " "
    .. tostring(s.dynamicWarp and s.dynamicWarp.x) .. "," .. tostring(s.dynamicWarp and s.dynamicWarp.y))
  check(game:saveGame() ~= false, "saving inside the plaza writes the slot")
  local saved = SaveData.decode(love.filesystem.read("saves/emerald/slot1.lua"))
  check(saved.map == Plaza.MAP_ID, "the slot records the plaza as the save map (" .. tostring(saved.map) .. ")")
  local w = saved.continueGameWarp or {}
  check(require("bit").band(tonumber(saved.specialSaveWarpFlags) or 0, 1) == 1 and w.map == CENTER_2F,
    "the slot carries CONTINUE_GAME_WARP to the PC 2F (" .. tostring(saved.specialSaveWarpFlags) .. " "
    .. tostring(w.map) .. " " .. tostring(w.x) .. "," .. tostring(w.y) .. ")")

  pcall(Link.reset)
  pcall(Client.disconnect)
  wait(10)

  local cont = Schema.fromSaveTable(saved)
  check(cont.map == CENTER_2F and require("bit").band(tonumber(cont.specialSaveWarpFlags) or 0, 1) == 0,
    "continue resolves to the PC 2F (" .. tostring(cont.map) .. " " .. tostring(cont.x) .. "," .. tostring(cont.y) .. ")")
  require("src.core.game3.options").bind(cont, game.options)
  game:adoptSave(cont, true)
  game:_enterField(cont, "continue")
  U.wait(30)
  d.shot(game, "02_continue_2f")
  S.settle(game, { limit = 3000, watch = function()
    if Message.isOpen() then U.tap(game, "a") end
  end })
  wait(30)
  d.shot(game, "03_continue_settled")
  check(Map.current == CENTER_2F, "continue lands in the PC 2F (" .. tostring(Map.current) .. ")")
  check(Player.cellX == 5, "the player stands in the Union Room doorway column (" .. tostring(Player.cellX)
    .. "," .. tostring(Player.cellY) .. ")")
  check((tonumber(Flags.getVar(Space.store, ctx(), cableVar)) or 0) == 0,
    "CableClub_EventScript_ExitUnionRoom clears VAR_CABLE_CLUB_STATE")
  check(not (Space.vm and Space.vm:isRunning()), "the exit script releases the player")
  check(Union.state == "off", "the Union Room is not running after continue")
  return d.finish()
end
