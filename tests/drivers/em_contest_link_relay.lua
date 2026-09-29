local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("CT_SEAT") or "0") or 0
local SYNC = os.getenv("CT_SYNC_DIR") or ((os.getenv("TMPDIR") or "/tmp") .. "/em_contest_link")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_contest_link"
local TAG = "ct_seat" .. SEAT
local NAMES = { [0] = "BRENDAN", [1] = "MAY" }
local SPECIES = { [0] = "SPECIES_ZIGZAGOON", [1] = "SPECIES_WINGULL" }
-- pokeemerald/include/constants/union_room.h:73
local WIRE = "contest_cool"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. TAG .. " " .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function now() return love.timer.getTime() end

local function writeFile(path, text)
  local fh = io.open(path, "w")
  if not fh then return false end
  fh:write(text)
  fh:close()
  return true
end

local function readFile(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local text = fh:read("*a")
  fh:close()
  return text
end

return function(game)
  print("PASS " .. TAG .. " driver_started")
  local Client

  local function finish()
    local Link = package.loaded["src.core.game3.link"]
    if Link then pcall(Link.reset) end
    if Client then pcall(Client.disconnect) end
    if failures == 0 then
      print("PASS " .. TAG .. " contest_link_relay")
      love.event.quit(0)
    else
      print("FAIL " .. TAG .. " contest_link_relay failures=" .. failures)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = NAMES[SEAT] })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local ArenaData = require("src.online.ArenaData")
  local Wire = require("src.link.Wire")
  local Link = require("src.core.game3.link")
  local CL = require("src.core.game3.link.contest_link")
  local Util = require("src.core.game3.rse.contest_util")
  local Stage = require("src.ui.game3.rse.contest")
  local Results = require("src.ui.game3.rse.contest_results")
  Client = require("src.online.Client")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  if not result(Wire.SCHEMAS.game3_contest_block ~= nil, "Wire has the game3_contest_block schema") then
    return finish()
  end
  local C = require("src.core.game3.constants").active(session)
  local g3 = Runtime._game or game
  session.name = NAMES[SEAT]
  session.trainerId = 0x2000 + SEAT
  session.party = {}
  Party.giveMon(session, C:require("species", SPECIES[SEAT]), 20 + SEAT)
  local avatar = { name = NAMES[SEAT], trainerId = session.trainerId, gender = SEAT, version = "emerald" }

  local function waitUntil(pred, seconds)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.wait(1)
    end
    return true
  end

  local profile, why = ArenaData.liveProfile3(g3, "g3_link")
  if not result(profile ~= nil, "live Gen 3 profile (" .. tostring(why) .. ")") then return finish() end
  local okC, errC = Client.connect({ name = NAMES[SEAT], profiles = { profile },
    presence = { where = "game", status = "busy" } })
  result(okC, "Client.connect " .. tostring(os.getenv("POKEPORT_RELAY_ADDR")) .. " " .. tostring(errC))
  if not result(waitUntil(function() return Client.state() == "online" end, 10), "online on the relay") then
    return finish()
  end

  local leaderFile = SYNC .. "/leader.txt"
  if SEAT == 0 then
    Client.openGroup(WIRE, profile, avatar)
    if not result(waitUntil(function() return Client.group() ~= nil end, 10), "group_open answered") then
      return finish()
    end
    writeFile(leaderFile, Client.you().id)
    local sentStart, accepted = false, {}
    local started = waitUntil(function()
      local g = Client.group()
      for _, p in ipairs(g and g.pending or {}) do
        if not accepted[p.id] then
          accepted[p.id] = true
          Client.acceptGroup(p.id, true)
        end
      end
      if g and #(g.members or {}) >= 2 and not sentStart then
        sentStart = true
        Client.startGroup()
      end
      local room = Client.room()
      return room ~= nil and room.stage == "battling" and room.match ~= nil
    end, 60)
    if not result(started, "partner accepted and the contest group started") then return finish() end
  else
    local leaderId
    waitUntil(function()
      leaderId = readFile(leaderFile)
      return leaderId ~= nil and leaderId ~= ""
    end, 30)
    if not result(leaderId ~= nil, "found the leader id") then return finish() end
    Client.joinGroup(leaderId, profile, avatar)
    local started = waitUntil(function()
      local room = Client.room()
      return room ~= nil and room.stage == "battling" and room.match ~= nil
    end, 60)
    if not result(started, "joined and the contest group started") then return finish() end
  end
  result(Client.seat() == SEAT, "relay seat " .. tostring(Client.seat()))

  local opened = Link.openRelay({ linkType = CL.LINKTYPE.EMODE })
  if not result(opened ~= nil, "Game3Link opened on the relay room") then return finish() end
  if not result(waitUntil(function() return Link.link and Link.link:isReady() end, 20), "link handshake ready") then
    return finish()
  end
  CL.wireless = true

  local s = CL.newSession(Link.link, { flags = CL.FLAG.IS_LINK + CL.FLAG.IS_WIRELESS })
  local contestant = Util.contestantFromMon(session.party[1], session)
  contestant.nickname = contestant.nickname or require("src.core.game3.pokemon").name(contestant.species)
  local job = CL.beginTransfer({ session = s, category = 0, partyMon = session.party[1], contestant = contestant,
    gameCleared = false })
  local code
  waitUntil(function()
    code = job:step()
    return code ~= nil
  end, 30)
  if not result(code == CL.RESULT.OK, "contestlinktransfer result " .. tostring(code)) then return finish() end
  local c = job.contest
  CL.active = s
  Util.state = { contest = c, partyIndex = 0, category = c.category, rank = c.rank, link = s }
  result(c.playerIndex == SEAT, "my contestant index is my link seat")
  result(c.mons[1 - SEAT].trainerName == NAMES[1 - SEAT], "partner's entrant arrived: " .. tostring(c.mons[1 - SEAT].trainerName))

  local stageDone = false
  Stage.open({ contest = c, session = session, onDone = function() stageDone = true end })
  local shot = false
  local deadline = now() + 240
  while not stageDone and now() < deadline do
    if not shot and c.contest.appealNumber == 2 then
      shot = true
      U.shot(game, DIR .. "/" .. TAG .. "_stage.png")
    end
    U.tap(game, "a")
  end
  if not result(stageDone, "contest stage finished all appeals") then return finish() end
  result(c.contest.appealNumber == 5, "five appeals ran")
  result(not c.linkDesync, "no per-round hash divergence")

  if SEAT == 1 then
    local hold = now() + 4
    while now() < hold do U.wait(1) end
  end
  local resultsDone = false
  local screen = Results.open({ contest = c, session = session, onDone = function() resultsDone = true end })
  local standby, standbyGone = nil, false
  deadline = now() + 240
  while not resultsDone and now() < deadline do
    local sc = Results.active() or screen
    if sc and sc.d and sc.d.linkTextBoxSpriteId then
      local sp = sc:sprite(sc.d.linkTextBoxSpriteId)
      local bt = sc.boxTexts and sc.boxTexts[sc.d.linkTextBoxSpriteId]
      if not standby and sp and not sp.invisible and bt then
        standby = { text = bt.text, x = sp.x, y = sp.y }
        U.shot(game, DIR .. "/" .. TAG .. "_results_standby.png")
      elseif standby and sp and sp.invisible then
        standbyGone = true
      end
    end
    U.tap(game, "a")
  end
  if SEAT == 0 then
    result(standby ~= nil and standby.text == "Communication standby…",
      "results show gText_CommunicationStandby while waiting (" .. tostring(standby and standby.text) .. ")")
    result(standby ~= nil and standby.y == 80, "the standby box sits at y=80 like ShowLinkResultsTextBox")
    result(standbyGone, "the standby box hides once the partner answers")
  end
  if screen and screen.done then resultsDone = true end
  result(resultsDone, "results screen finished")
  result(c.link == nil, "contest link closed after results")

  local mine = string.format("%d,%d,%d,%d|%d,%d,%d,%d|%s", c.totals[0], c.totals[1], c.totals[2], c.totals[3],
    c.standings[0], c.standings[1], c.standings[2], c.standings[3], CL.hash(c))
  print("[driver] " .. TAG .. " final " .. mine)
  writeFile(SYNC .. "/final" .. SEAT .. ".txt", mine)
  local theirs
  waitUntil(function()
    theirs = readFile(SYNC .. "/final" .. (1 - SEAT) .. ".txt")
    return theirs ~= nil and theirs ~= ""
  end, 60)
  result(theirs == mine, "both peers computed the same contest (" .. tostring(theirs) .. ")")
  return finish()
end
