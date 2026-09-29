local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("G3X_SEAT") or "0") or 0
local SYNC = os.getenv("G3X_SYNC_DIR") or ((os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/g3x")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3x"
local TAG = "g3x_seat" .. SEAT

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. TAG .. " " .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function now() return love.timer.getTime() end

local function writeFile(path, text)
  local fh = io.open(path, "w")
  if fh then
    fh:write(text)
    fh:close()
  end
end

local function readFile(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local s = fh:read("*a")
  fh:close()
  return s
end

return function(game)
  print("PASS " .. TAG .. " driver_started")
  os.execute("mkdir -p '" .. SYNC .. "'")
  local Link, Client
  local function finish()
    writeFile(SYNC .. "/done" .. SEAT, failures == 0 and "ok" or "fail")
    if Link then pcall(Link.reset) end
    if Client then pcall(Client.disconnect) end
    print((failures == 0 and "PASS " or "FAIL ") .. TAG .. " xfamily_plaza failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local version = require("src.core.GameVersion").get()
  if version == "emerald" then
    local SaveData = require("src.core.SaveData")
    local Schema = require("src.core.game3.save_schema_firered")
    local raw = love.filesystem.read("saves/emerald/slot1.lua")
    if not result(type(raw) == "string", "emerald identity has a save") then return finish() end
    local session = Schema.fromSaveTable(SaveData.decode(raw))
    require("src.core.game3.options").bind(session, game.options)
    game:adoptSave(session, true)
    game:_enterField(session, "continue")
  else
    game:_handleBootAction({ action = "new_game", name = "RED" })
  end
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Party = require("src.core.game3.party")
  local Union = require("src.core.game3.link.union_room")
  local Chat = require("src.core.game3.link.chat")
  local Family = require("src.core.game3.link.family")
  local Plaza = require("src.core.game3.link.union_plaza_map")
  Link = require("src.core.game3.link")
  Client = require("src.online.Client")

  local session = Runtime.getSession()
  if not result(session ~= nil, "reached the field on " .. tostring(version)) then return finish() end
  session.name = SEAT == 0 and "RED" or "MAY"
  session.trainerId = 0x1100 + SEAT
  while #(session.party or {}) < 2 do Party.giveMon(session, version == "emerald" and 280 or 25, 10) end

  local function waitUntil(pred, seconds)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.wait(1)
    end
    return true
  end
  local function drive(cond, seconds)
    local deadline = now() + (seconds or 10)
    while not cond() and now() < deadline do
      if Choice.active or SaveMenu.isOpen() or Message.isOpen() then U.tap(game, "a") end
      U.wait(6)
    end
    return cond()
  end

  local okC, errC = Link.connect()
  result(okC ~= false, "Link.connect " .. tostring(os.getenv("POKEPORT_RELAY_ADDR")) .. " " .. tostring(errC))
  if not result(waitUntil(function() return Client.state() == "online" end, 15), "online on the relay") then
    return finish()
  end

  local center, cx, cy
  if version == "emerald" then
    -- pokeemerald/data/scripts/cable_club.inc:104
    Flags.setVar(Space.store, Space.vm and Space.vm.ctx, Family.var(version, "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
    center, cx, cy = "EM_OLDALE_TOWN_POKEMON_CENTER_2F", 6, 4
  else
    center, cx, cy = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", 6, 4
  end
  Map.load(nil, game, center, { x = cx, y = cy, facing = "up" })
  U.wait(60)
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, Family.flag(version, "FLAG_SYS_POKEDEX_GET"), true)
  Player.cellX, Player.cellY, Player.facing = cx, cy, "up"
  Player.px, Player.py, Player.targetX, Player.targetY = cx * 16, cy * 16, cx, cy
  game.session.x, game.session.y, game.session.facing = cx, cy, "up"
  U.wait(12)
  U.tap(game, "a")
  local entered = drive(function() return Space.mapId == Plaza.MAP_ID and Union.state == "main" end, 40)
  if not result(entered, "entered " .. tostring(Plaza.MAP_ID)) then
    U.still(game, DIR .. "/" .. TAG .. "_enter_failed.png")
    return finish()
  end
  result(waitUntil(function() return Client.plaza() ~= nil end, 10), "joined the relay union plaza")
  writeFile(SYNC .. "/in" .. SEAT, "1")

  local other
  local found = waitUntil(function()
    Union.relayTick(0)
    for slot = 1, Union.capacity() do
      local p = Union.players[slot]
      if p and not p.gone then other = slot return true end
    end
    return false
  end, 40)
  if not result(found, "the other game's player appears in the same plaza") then return finish() end
  local plaza = Client.plaza() or {}
  local otherVersion
  for _, m in ipairs(plaza.members or {}) do
    if tonumber(m.slot) == other and type(m.avatar) == "table" then otherVersion = m.avatar.version end
  end
  local want = SEAT == 0 and "emerald" or "firered"
  result(otherVersion == want, "the other member carries version " .. tostring(otherVersion))
  local v = Union.vobj(other)
  local x, y = Plaza.cellFor(other)
  result(waitUntil(function() v = Union.vobj(other) return v and v.visible and v.anim == nil end, 10)
    and v.x == x and v.y == y, "the other player stands on slot " .. other .. "'s cell")
  result(v and v.gfx == Union.graphicsIdFor(Union.players[other].gender, Union.players[other].trainerId),
    "drawn with this cart's union room class gfx")
  U.wait(30)
  Player.cellX, Player.cellY = x, y + 2
  Player.px, Player.py, Player.targetX, Player.targetY = x * 16, (y + 2) * 16, x, y + 2
  Player.facing = "up"
  U.wait(30)
  U.still(game, DIR .. "/" .. TAG .. "_plaza.png")

  if SEAT == 1 then
    waitUntil(function() return readFile(SYNC .. "/in0") ~= nil end, 30)
    U.wait(60)
    Union.partnerId = other
    Union._partner = Union.players[other]
    local chatIndex
    for i, item in ipairs(Union.INVITE_ITEMS) do
      if item.key == "CHAT" then chatIndex = i end
    end
    Union.chooseActivity(chatIndex)
    result(Union.state == "send_activity_request", "MAY invites RED to chat across games")
  else
    local rang = waitUntil(function()
      return Union.state == "player_contacted_you" or Union.state == "handle_activity_request"
    end, 40)
    result(rang, "RED's Union Room rings with MAY's chat invite")
    waitUntil(function()
      if Message.isOpen() and Message.isWaiting() and (Message._page or 1) < #(Message._pages or {}) then
        U.tap(game, "a")
      end
      return Choice.active
    end, 10)
    U.tap(game, "a")
  end
  local chatting = waitUntil(function()
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    return Chat.isActive()
  end, 40)
  if not result(chatting, "both games are in one chat room") then return finish() end
  U.wait(60)
  if SEAT == 1 then
    Chat.say("HI FROM EM")
  end
  local heard = waitUntil(function()
    for _, line in ipairs(Chat.lines or {}) do
      if type(line) == "table" and tostring(line.text):find("HI FROM EM", 1, true) then return true end
    end
    return SEAT == 1
  end, 20)
  result(heard, "the Emerald line reaches the FireRed chat")
  U.wait(30)
  U.still(game, DIR .. "/" .. TAG .. "_chat.png")
  waitUntil(function() return readFile(SYNC .. "/done" .. (1 - SEAT)) ~= nil or SEAT == 0 end, 5)
  return finish()
end
