local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local CENTER_2F = "EM_OLDALE_TOWN_POKEMON_CENTER_2F"

local function now() return love.timer.getTime() end

return function(game)
  local d = S.new("em_link_union_plaza", "/tmp/em_link_union_plaza")
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
  local Screen = require("src.ui.game3.union_room")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")

  session = Runtime.getSession()
  check(Plaza.MAP_ID == "EM_UNION_ROOM_PLAZA", "plaza id is EM_UNION_ROOM_PLAZA")
  while #(session.party or {}) < 2 do Party.giveMon(session, 280, 10) end

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

  local live = Link.liveProfile()
  if not check(live ~= nil, "the live g3 profile computes") then return d.finish() end
  Link.connect()
  check(waitFor(function() return Client.state() == "online" end, 5, 120), "the Client is online on the relay")

  -- pokeemerald/data/scripts/cable_club.inc:104
  Flags.setVar(Space.store, ctx(), Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  Map.load(nil, game, CENTER_2F, { x = 6, y = 4, facing = "up" })
  wait(60)
  Flags.setFlag(Space.store, ctx(), Family.flag("emerald", "FLAG_SYS_POKEDEX_GET"), true)
  place(6, 4, "up")
  wait(12)
  U.tap(game, "a")
  local origShow = Message.show
  Message.show = function(text, ...)
    d.note("MSG " .. tostring(text):gsub("\n", " "):sub(1, 70))
    return origShow(text, ...)
  end
  local entered = drive(function() return Space.mapId == Plaza.MAP_ID and Union.state == "main" end, 30)
  d.note("map=" .. tostring(Space.mapId) .. " union=" .. tostring(Union.state))
  if not check(entered, "the attendant walks the player into the Emerald plaza") then
    local c = ctx()
    d.note("vm running=" .. tostring(Space.vm and Space.vm:isRunning()) .. " pc=" .. tostring(c and c.pc and c.pc.listKey)
      .. ":" .. tostring(c and c.pc and c.pc.index) .. " wait=" .. tostring(c and (c.stateWait or c.nativePoll or c.waitKind))
      .. " player=" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY))
    d.note("started " .. table.concat(d.started, ","))
    d.shot(game, "enter_failed")
    return d.finish()
  end
  check(Player.cellX == 12 and Player.cellY == 24, "the player lands on the plaza door "
    .. tostring(Player.cellX) .. "," .. tostring(Player.cellY))
  local def = game.data and game.data.maps and game.data.maps[Plaza.MAP_ID]
  check(def and def.width == 25 and def.height == 25 and #def.warps == 2, "plaza is 25x25 with both cart exits")
  check(waitFor(function() return Client.plaza() ~= nil end, 5, 60), "the player is in the union plaza")
  me.presence.where = "union"

  local peers = {}
  for i, v in ipairs({ "firered", "leafgreen", "emerald" }) do
    local id = string.format("b%07d", i)
    local s = relay:seat(id, "P" .. i)
    relay:handle(s, { type = "lobby_hello", protocol = 3, name = "P" .. i, profiles = { live },
      presence = { where = "launcher", status = "idle", version = v } })
    s.avatar = { name = "P" .. i, trainerId = 0x1000 + i, gender = i % 2, version = v }
    relay:handle(s, { type = "plaza_join", kind = "union", cap = 40, profile = live, avatar = s.avatar })
    peers[#peers + 1] = s
  end
  check(waitFor(function() return Union.playerCount() == 3 end, 8, 120), "three FR/LG/EM plaza members appear")
  wait(40)
  d.shot(game, "plaza_mixed")

  place(3, 3, "up")
  wait(30)
  d.shot(game, "attendant_front")
  U.tap(game, "a")
  local shown = waitFor(function() return Message.isOpen() end, 5, 200)
  check(shown, "talking to the attendant shows her text")
  wait(20)
  d.shot(game, "attendant_text")
  local released = drive(function()
    if Screen.isOpen() then U.tap(game, "b") end
    return Union.state == "main" and not Message.isOpen() and not Screen.isOpen()
      and not (Space.vm and Space.vm:isRunning())
  end, 20)
  check(released, "the attendant flow ends and releases control state=" .. tostring(Union.state))
  place(3, 5, "down")
  wait(4)
  U.hold(game, "down", 20)
  wait(20)
  check(Player.cellY ~= 5 or Player.moving, "the player can walk again after the attendant")

  place(12, 23, "down")
  wait(10)
  for _ = 1, 20 do
    if Map.current == CENTER_2F then break end
    U.hold(game, "down", 8)
    relay:pump()
  end
  local back = waitFor(function() return Map.current == CENTER_2F end, 8, 300)
  d.note("after exit map=" .. tostring(Map.current) .. " space=" .. tostring(Space.mapId) .. " at "
    .. tostring(Player.cellX) .. "," .. tostring(Player.cellY))
  check(back, "the exit pad warps back to the PC 2F")
  d.shot(game, "exit_2f")
  check(Union.state == "off", "leaving the Union Room stops it")
  pcall(Link.reset)
  pcall(Client.disconnect)
  return d.finish()
end
