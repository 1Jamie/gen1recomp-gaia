local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("G3X_SEAT") or "0") or 0
local SYNC = os.getenv("G3X_SYNC_DIR") or ((os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/g3bb")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3bb"
local TAG = "g3bb_seat" .. SEAT
local CENTER_2F = "EM_OLDALE_TOWN_POKEMON_CENTER_2F"

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
    print((failures == 0 and "PASS " or "FAIL ") .. TAG .. " berry_blender failures=" .. failures)
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
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  Link = require("src.core.game3.link")
  Client = require("src.online.Client")

  local session = Runtime.getSession()
  session.name = SEAT == 0 and "MAY" or "BRENDAN"
  session.trainerId = 0x2200 + SEAT
  while #(session.party or {}) < 2 do Party.giveMon(session, 280, 10) end
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants").of("emerald")
  session.bag = session.bag or Bag.new()
  local berry = C:require("items", SEAT == 0 and "ITEM_CHERI_BERRY" or "ITEM_PECHA_BERRY")
  Bag.add(session.bag, berry, 5)
  local Pokeblock = require("src.core.game3.rse.pokeblock")
  result(Pokeblock.firstFreeSlot(session) ~= -1, "the POKEBLOCK CASE has a free slot")

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
  place(10, 5, "down")
  U.wait(12)
  local NativesBlender = require("src.core.game3.scripting.natives_blender")
  NativesBlender.last = nil
  -- pokeemerald/data/scripts/berry_blender.inc:558
  Space.startScript("BerryBlender_EventScript_TryDoLinkBlender")
  local picked, roleChosen, askedYes = false, false, {}
  local lobbyActed = false
  local waitingFor = 0
  local deadline = now() + 90
  local reached = false
  while now() < deadline do
    if NativesBlender.last and NativesBlender.last.linkSession then
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
        local _ = label
      end
      if idx then
        picked = true
        Choice.autoPick(idx - 1)
      elseif not roleChosen and #opts == 3 then
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
  print("[driver] " .. TAG .. " link=" .. tostring(Link.link and Link.link:isReady()))
  if not result(reached, "the blender link group reaches DoBerryBlending with a link session") then
    U.still(game, DIR .. "/" .. TAG .. "_failed.png")
    return finish()
  end
  local Game3Link = require("src.link.Game3Link")
  result(Link.link and Link.link.linkType == Game3Link.LINKTYPE.BERRY_BLENDER, "the link switched to the blender link type")
  result(#(Link.link and Link.link:players() or {}) == 2, "two blender players on the link")
  local screen = NativesBlender.last.screen
  local BagMenu = require("src.ui.game3.bag_menu")
  local B = require("src.core.game3.rse.berry_blender")
  local Kit = require("src.ui.game3.rse.gc_kit")
  local hits, inZone = 0, false
  if screen then
    local origJoy = screen.joyNew
    screen.joyNew = function(self, mask)
      if self.cb == "play" and mask == Kit.A and self.game then
        local best = self.game:previewInputScore(true) == B.CMD.BEST
        if best and not inZone then
          inZone = true
          hits = hits + 1
          return true
        end
        if not best then inZone = false end
        return false
      end
      return origJoy(self, mask)
    end
  end
  local lastCb
  local shotPlay, shotResults, sawPlay, berryChosen = false, false, false, false
  deadline = now() + 240
  local tick = 0
  while now() < deadline and not NativesBlender.last.done do
    tick = tick + 1
    local sc = NativesBlender.last.screen
    if sc and sc.cb ~= lastCb then
      lastCb = sc.cb
      print("[driver] " .. TAG .. " cb " .. tostring(sc.cb))
    end
    if BagMenu.isOpen and BagMenu.isOpen() then
      berryChosen = true
      if tick % 8 == 0 then U.tap(game, "a") end
    elseif sc and sc.yesNo then
      U.still(game, DIR .. "/" .. TAG .. "_again.png")
      U.tap(game, "b")
    elseif sc and sc.cb == "play" then
      sawPlay = true
      if not shotPlay and hits >= 3 then
        shotPlay = true
        U.still(game, DIR .. "/" .. TAG .. "_blending.png")
      end
    elseif sc and sc.cb == "end" and sc.game and sc.game.gameEndState == 6 and not shotResults then
      shotResults = true
      U.wait(30)
      U.still(game, DIR .. "/" .. TAG .. "_results.png")
    elseif tick % 10 == 0 then
      U.tap(game, "a")
    end
    U.wait(1)
  end
  result(berryChosen, "the berry was chosen from the BERRIES pocket")
  result(sawPlay, "the blend ran over the link")
  result(hits > 0, "the local player hit the arrow (" .. hits .. " hits)")
  if not result(NativesBlender.last.done, "the blend finished and returned to the field") then
    U.still(game, DIR .. "/" .. TAG .. "_stuck.png")
    return finish()
  end
  local res = NativesBlender.last.result or {}
  local pb = type(res.pokeblock) == "table" and res.pokeblock or {}
  local keys = {}
  for k, v in pairs(pb) do
    if type(v) ~= "table" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
  end
  table.sort(keys)
  local mine = table.concat(keys, ",") .. "|rpm=" .. tostring(res.maxRPM)
  print("[driver] " .. TAG .. " pokeblock " .. mine)
  result(#keys > 0 and (tonumber(pb.color) or 0) > 0, "a pokeblock came out (" .. tostring(pb.color) .. ")")
  local fh = io.open(SYNC .. "/block" .. SEAT .. ".txt", "w")
  if fh then fh:write(mine) fh:close() end
  local theirs
  waitUntil(function()
    local f2 = io.open(SYNC .. "/block" .. (1 - SEAT) .. ".txt")
    if not f2 then return false end
    theirs = f2:read("*a")
    f2:close()
    return theirs ~= nil and theirs ~= ""
  end, 60)
  result(theirs == mine, "both players got the same pokeblock and max RPM (" .. tostring(theirs) .. ")")
  local caseHas = false
  for _, b in pairs(session.pokeblocks or {}) do
    if type(b) == "table" and tonumber(b.color) == tonumber(pb.color) then caseHas = true end
  end
  result(caseHas, "the pokeblock landed in the POKEBLOCK CASE")
  waitUntil(function() local f3 = io.open(SYNC .. "/done" .. (1 - SEAT)) if f3 then f3:close() return true end end, 10)
  return finish()
end
