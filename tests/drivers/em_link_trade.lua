local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_link_trade"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_link_trade failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Natives = require("src.core.game3.scripting.natives")
  local Link = require("src.core.game3.link")
  local LB = require("src.core.game3.link.battle")
  local LT = require("src.core.game3.link.trade")
  local TradeScene = require("src.core.game3.trade_scene")
  local Game3Link = require("src.link.Game3Link")
  local Protocol = require("src.link.Protocol")
  local Wire = require("src.link.Wire")
  local Message = require("src.ui.game3.message")
  local C = require("src.core.game3.constants").of("emerald")

  local session = Runtime.getSession()
  if not result(session ~= nil and session.version == "emerald", "new game reached the Emerald field") then
    return finish()
  end

  local CENTER_2F = "EM_OLDALE_TOWN_POKEMON_CENTER_2F"
  local TRADE_CENTER = "EM_TRADE_CENTER"
  local function ctx() return Space.vm and Space.vm.ctx end
  local function adapters() return Space.vm and Space.vm.adapters end
  local function getVar(name) return tonumber(Flags.getVar(Space.store, ctx(), C:require("vars", name))) or 0 end
  local function setVar(name, v) Flags.setVar(Space.store, ctx(), C:require("vars", name), v) end
  local function special(name)
    local fn = Natives.handlerFor(name)
    if not fn then return nil end
    return fn(ctx(), adapters())
  end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    session.x, session.y, session.facing = x, y, facing
  end

  local peerHolder = { name = "RED", trainerId = 0x2222, party = {} }
  Party.giveMon(peerHolder, C:require("species", "SPECIES_PIKACHU"), 14)
  local peerMon = peerHolder.party[1]
  peerMon.otName, peerMon.ot = "RED", "RED"

  local peer, peerSeat, peerParty, peerGot, peerConfirmed = nil, false, false, nil, false
  local function pumpPeer()
    if not peer then return end
    peer:update(0)
    local lu = peer:take(LB.MSG.LINKUP)
    if lu then peer:send({ type = LB.MSG.LINKUP, linkType = lu.linkType, players = lu.players }) end
    if peer:take(LB.MSG.SEAT) then
      peerSeat = true
      peer:send({ type = LB.MSG.SEAT, seat = 1 })
    end
    if peer:take(LT.MSG.PARTY) then
      peerParty = true
      -- pokefirered/src/link.c:350
      peer:send({ type = LT.MSG.PARTY, name = "RED", trainerId = 0x2222, gender = 0,
        version = 4, progressFlags = 0x11, party = Protocol.packParty3({ peerMon }, { 1 }) })
    end
    local block = peer:take(LT.MSG.MON)
    if block then
      peerGot = block
      local theirs = { type = LT.MSG.MON, name = "RED", trainerId = 0x2222, mon = Protocol.packMon3(peerMon) }
      peer:send(theirs)
      peer:send({ type = LT.MSG.CONFIRM, digest = Protocol.tradeDigest(block.mon, Wire.sanitize(theirs).mon) })
    end
    local cmd = peer:take(LT.MSG.CMD)
    while cmd do
      if cmd.cmd == LT.LINKCMD.SET_MONS_TO_TRADE then
        peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
      elseif cmd.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
        peerConfirmed = true
        peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
      end
      cmd = peer:take(LT.MSG.CMD)
    end
  end
  local function waitP(frames)
    for _ = 1, frames do
      U.wait(1)
      pumpPeer()
    end
  end
  local function waitFor(pred, limit)
    local n = 0
    while n < (limit or 300) and not pred() do
      waitP(1)
      n = n + 1
    end
    return pred()
  end

  Flags.setFlag(Space.store, ctx(), C:require("flags", "FLAG_SYS_POKEDEX_GET"), true)
  Flags.setFlag(Space.store, ctx(), C:require("flags", "FLAG_IS_CHAMPION"), true)
  session.party = {}
  Party.giveMon(session, C:require("species", "SPECIES_TREECKO"), 16)
  Party.giveMon(session, C:require("species", "SPECIES_ZIGZAGOON"), 12)
  local sentSpecies = session.party[1].species

  local Choice = require("src.ui.game3.choice")
  local function busy()
    return (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen()) or Choice.active
  end
  local function unknownSpecials()
    local n = 0
    for key in pairs(Natives._logged or {}) do
      if tostring(key):find("^special:") then n = n + 1 print("[driver] unknown " .. tostring(key)) end
    end
    return n
  end
  Natives.resetLog()

  Map.load(nil, game, CENTER_2F, { x = 10, y = 3, facing = "up" })
  place(10, 3, "up")
  U.wait(60)
  result(Space.mapId == CENTER_2F, "the player is at the Oldale POKeMON CENTER 2F counter")
  U.shot(game, DIR .. "/em_link_trade_01_center_2f.png")

  -- pokeemerald/data/scripts/cable_club.inc:897 CableClub_EventScript_DirectCornerAttendant
  U.tap(game, "a")
  local n = 0
  while n < 600 and not (Link.connectPrompt ~= nil and Choice.active) do
    if Link.connectPrompt == nil and Message.isOpen and Message.isOpen() and not Choice.active then U.tap(game, "a") end
    U.wait(10)
    n = n + 10
  end
  result(Link.connectPrompt ~= nil and Choice.active,
    "offline, IsWirelessAdapterConnected (link.c:237) asks to connect")
  U.shot(game, DIR .. "/em_link_trade_01b_connect_prompt.png")
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "a")
  U.wait(30)
  n = 0
  while n < 600 and not Choice.active do
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(10)
    n = n + 10
  end
  result(Choice.active, "NO falls back to the Cable Club service menu (cable_club.inc:WelcomeToCableClub)")
  U.shot(game, DIR .. "/em_link_trade_01c_cable_club_menu.png")
  n = 0
  while n < 900 and busy() do
    U.tap(game, "b")
    U.wait(15)
    n = n + 15
  end
  result(not busy(), "B backs out of the Cable Club")
  result(unknownSpecials() == 0, "the Direct Corner script hit no unbound special")

  -- pokeemerald/data/scripts/cable_club.inc:384 CableClub_EventScript_EnterTradeCenter
  place(9, 2, "up")
  U.wait(20)
  place(9, 1, "up")
  U.wait(10)
  special("SetCableClubWarp")
  result(session.dynamicWarp ~= nil and session.dynamicWarp.map == CENTER_2F,
    "SetCableClubWarp (field_control_avatar.c:995) recorded the way back")

  local host
  host, peer = Game3Link.loopback({ game = game, linkType = Game3Link.LINKTYPE.TRADE_SETUP })
  host:update(0)
  peer:update(0)
  Link.attach(host)
  LT.loopbackCommit = true
  result(host:isReady(), "the other game is on the link")
  result(host.myHello.game3.version == "emerald" and host.myHello.game3.gameVersion == 0x4003,
    "the hello announces VERSION_EMERALD (link.c:330)")

  local yielded = special("TryTradeLinkup")
  result(yielded, "TryTradeLinkup (cable_club.c:610) parked the script")
  local linkup, guard = nil, 0
  while guard < 300 and linkup == nil do
    pumpPeer()
    local poll = ctx().nativePoll
    if poll and poll() then
      linkup = getVar("VAR_RESULT")
      ctx().nativePoll = nil
      ctx().mode = "bytecode"
    elseif LB.linkup ~= nil and LB.linkup ~= Link.LINKUP.ONGOING then
      linkup = LB.linkup
    end
    U.wait(1)
    guard = guard + 1
  end
  result(linkup == Link.LINKUP.SUCCESS, "both games chose TRADE, so the linkup succeeded (" .. tostring(linkup) .. ")")

  setVar("VAR_0x8004", Link.USING.TRADE_CENTER)
  setVar("VAR_CABLE_CLUB_STATE", Link.USING.TRADE_CENTER)
  result(Link.VAR_CABLE_CLUB_STATE == C:require("vars", "VAR_CABLE_CLUB_STATE"),
    "the link layer reads Emerald's VAR_CABLE_CLUB_STATE (0x4087)")
  Map.load(nil, game, TRADE_CENTER, { x = 5, y = 8, facing = "up" })
  place(5, 8, "up")
  waitP(90)
  result(Space.mapId == TRADE_CENTER, "the player is inside the Emerald TRADE CENTER")
  U.shot(game, DIR .. "/em_link_trade_02_trade_center.png")

  result(unknownSpecials() == 0, "the link path hit no unbound special")
  print("NOTE the trade seat opens src/ui/game3/link_trade_menu.lua, whose FireRed text keys are a crossfile request (W4-link)")
  LT.loopbackCommit = false
  Link.reset()
  finish()
end
