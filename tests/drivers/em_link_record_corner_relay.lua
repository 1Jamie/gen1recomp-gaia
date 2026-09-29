local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("G3X_SEAT") or "0") or 0
local SYNC = os.getenv("G3X_SYNC_DIR") or ((os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/g3rc")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3rc"
local TAG = "g3rc_seat" .. SEAT
local CENTER_2F = "EM_OLDALE_TOWN_POKEMON_CENTER_2F"
-- pokeemerald/data/maps/RecordCorner/map.json coord_events
local SPOTS = { [0] = { 6, 4 }, [1] = { 13, 4 } }

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. TAG .. " " .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function now() return love.timer.getTime() end

return function(game)
  print("PASS " .. TAG .. " driver_started")
  os.execute("mkdir -p '" .. SYNC .. "'")
  local Link, Client
  local function finish()
    local fh = io.open(SYNC .. "/done" .. SEAT, "w")
    if fh then fh:write("1") fh:close() end
    if Link then pcall(Link.reset) end
    if Client then pcall(Client.disconnect) end
    print((failures == 0 and "PASS " or "FAIL ") .. TAG .. " record_corner failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not result(type(raw) == "string", "identity has a save") then return finish() end
  local loaded = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(loaded, game.options)
  game:adoptSave(loaded, true)
  game:_enterField(loaded, "continue")
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Party = require("src.core.game3.party")
  local Family = require("src.core.game3.link.family")
  local RecordMix = require("src.core.game3.link.record_mix")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  Link = require("src.core.game3.link")
  Client = require("src.online.Client")

  local session = Runtime.getSession()
  session.name = SEAT == 0 and "MAY" or "BRENDAN"
  session.trainerId = 0x2200 + SEAT
  while #(session.party or {}) < 2 do Party.giveMon(session, 280, 10) end

  local function waitUntil(pred, seconds)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.wait(1)
    end
    return true
  end
  local function place(x, y, facing)
    Player.cellX, Player.cellY, Player.facing = x, y, facing
    Player.px, Player.py, Player.targetX, Player.targetY = x * 16, y * 16, x, y
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end

  Link.connect()
  if not result(waitUntil(function() return Client.state() == "online" end, 15), "online on the relay") then
    return finish()
  end
  -- pokeemerald/data/scripts/cable_club.inc:104
  Flags.setVar(Space.store, Space.vm and Space.vm.ctx, Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  Map.load(nil, game, CENTER_2F, { x = 10, y = 4, facing = "up" })
  U.wait(60)
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, Family.flag("emerald", "FLAG_SYS_POKEDEX_GET"), true)
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, Family.flag("emerald", "FLAG_VISITED_MAUVILLE_CITY"), true)
  place(10, 4, "up")
  U.wait(12)
  U.tap(game, "a")

  local LINK_GROUP_RECORD_CORNER = 12
  local picked, roleChosen, askedYes = false, false, {}
  local lobbyActed = false
  local waitingFor = 0
  local deadline = now() + 90
  local reached = false
  while now() < deadline do
    if Space.mapId == Family.mapId("emerald", "recordCorner") then
      reached = true
      break
    end
    if Choice.active and Choice.kind == "multi" then
      local opts = Choice.options or {}
      local shown = {}
      for i, o in ipairs(opts) do shown[i] = type(o) == "table" and tostring(o.label or o.text or o[1]) or tostring(o) end
      print("[driver] " .. TAG .. " multi " .. table.concat(shown, "|"))
      local idx
      for i, o in ipairs(opts) do
        local label = type(o) == "table" and (o.label or o.text or o[1]) or o
        if not picked and tostring(label):upper():find("RECORD", 1, true) then idx = i end
      end
      if idx then
        picked = true
        Choice.autoPick(idx - 1)
      elseif picked and not roleChosen and #opts == 3 then
        roleChosen = true
        -- pokeemerald/data/scripts/cable_club.inc:1103
        Choice.autoPick(SEAT == 0 and 1 or 0)
      else
        U.tap(game, "a")
      end
    elseif Choice.active then
      Choice.autoPick(true)
    elseif SaveMenu.isOpen() then
      U.tap(game, "a")
    elseif Lobby.isOpen() and not lobbyActed then
      local rows = Lobby.players or Lobby._players or {}
      if SEAT == 0 then
        local g = Client.group()
        if type(g) == "table" and type(g.members) == "table" and #g.members >= 2 then
          lobbyActed = true
          Lobby.confirm()
        end
      elseif #rows > 0 then
        lobbyActed = true
        Lobby.cursor = 1
        Lobby.confirm()
      end
    elseif Message.isOpen() and Message.isWaiting() then
      waitingFor = waitingFor + 1
      if waitingFor > 10 then
        waitingFor = 0
        U.tap(game, "a")
      end
    else
      waitingFor = 0
    end
    U.wait(4)
  end
  local ctx = Space.vm and Space.vm.ctx
  print("[driver] " .. TAG .. " map=" .. tostring(Space.mapId) .. " 8004=" .. tostring(ctx and Flags.getVar(Space.store, ctx, 0x8004))
    .. " link=" .. tostring(Link.link and Link.link:isReady()))
  if not result(reached, "the Direct Corner group warps both into the Record Corner") then
    U.still(game, DIR .. "/" .. TAG .. "_failed.png")
    return finish()
  end
  result(Link.link ~= nil and Link.link:isReady(), "the relay link is up in the Record Corner")
  result(Link.link and Link.link.linkType == require("src.link.Game3Link").LINKTYPE.RECORD_MIX_BEFORE,
    "the link carries the record mix link type")
  waitUntil(function() return not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() end, 10)
  U.wait(30)
  local spot = SPOTS[SEAT]
  place(spot[1], spot[2] + 1, "up")
  U.wait(10)
  U.hold(game, "up", 20)
  local mixed = waitUntil(function()
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    return RecordMix.state == "done"
  end, 40)
  result(mixed, "records mixed over the relay")
  result(RecordMix.last and RecordMix.last.players == 2, "two record packets were mixed")
  U.wait(20)
  U.still(game, DIR .. "/" .. TAG .. "_mixed.png")
  waitUntil(function() local fh = io.open(SYNC .. "/done" .. (1 - SEAT)) if fh then fh:close() return true end end, 10)
  return finish()
end
