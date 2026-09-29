local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local SEAT = tonumber(os.getenv("TL_SEAT") or "0") or 0
local SYNC = os.getenv("TL_SYNC_DIR") or ((os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/em_tower_link")
local TAG = "tl_seat" .. SEAT
local NAMES = { [0] = "BRENDAN", [1] = "MAY" }
local LOBBY = "EM_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY"
local ROOM = "EM_BATTLE_FRONTIER_BATTLE_TOWER_MULTI_BATTLE_ROOM"

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
  os.execute("mkdir -p '" .. SYNC .. "'")
  local d = S.new("em_tower_link_multi_" .. SEAT, os.getenv("POKEPORT_SHOT_DIR") or ("/tmp/em_tower_link_" .. SEAT))
  local check, note = d.check, d.note
  local Link, Client
  local function finish()
    writeFile(SYNC .. "/done" .. SEAT, "1")
    local deadline = now() + 20
    while not readFile(SYNC .. "/done" .. (1 - SEAT)) and now() < deadline do U.wait(1) end
    if Link then pcall(Link.reset) end
    if Client then pcall(Client.disconnect) end
    return d.finish()
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, TAG .. " boot reached") then return finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", TAG .. " identity has the post-game save") then return finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Choice = require("src.ui.game3.choice")
  local Message = require("src.ui.game3.message")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local Natives = require("src.core.game3.scripting.natives")
  local LB = require("src.core.game3.link.battle")
  local Game3Link = require("src.link.Game3Link")
  Link = require("src.core.game3.link")
  Client = require("src.online.Client")

  session = Runtime.getSession()
  Natives.ensureBound(session)
  session.name = NAMES[SEAT]
  session.trainerId = 0x3300 + SEAT
  session.gender = SEAT
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end

  local function tough(name, moves)
    local m = D.createMon(S.species(name), 50, 31, 0, tonumber(session.trainerId) or 0,
      { otName = session.name, moves = {} })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  if SEAT == 0 then
    session.party = {
      tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }),
      tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_ROCK_SLIDE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    }
  else
    session.party = {
      tough("SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_ROCK_SLIDE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }),
      tough("SPECIES_GARDEVOIR", { "MOVE_PSYCHIC", "MOVE_THUNDERBOLT", "MOVE_CALM_MIND", "MOVE_SHADOW_BALL" }),
    }
  end

  local function waitUntil(pred, seconds)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.wait(1)
    end
    return true
  end

  Link.connect()
  if not check(waitUntil(function() return Client.state() == "online" end, 15), TAG .. " online on the relay") then
    return finish()
  end

  local ok = pcall(function() Map.load(nil, game, LOBBY, { x = 18, y = 7, facing = "up" }) end)
  U.wait(30)
  S.settle(game)
  if not check(ok and S.mapNow() == LOBBY, TAG .. " in the Battle Tower lobby") then return finish() end
  local attendant = S.objectByScript("BattleFrontier_BattleTowerLobby_EventScript_LinkMultisAttendant")
  if not check(attendant ~= nil, TAG .. " link multis attendant present") then return finish() end

  local seen = {}
  local origShow = Message.show
  Message.show = function(text, ...)
    local t = tostring(type(text) == "table" and table.concat(text, " ") or text):gsub("%s+", " ")
    seen[#seen + 1] = t
    note("MSG " .. t:sub(1, 90))
    return origShow(text, ...)
  end
  local function sawText(fragment)
    for _, t in ipairs(seen) do
      if t:find(fragment, 1, true) then return true end
    end
    return false
  end

  local hashes, desync, battleEnd = nil, nil, nil
  LB.keepRaw = true
  local origFinish = LB.finish
  LB.finish = function(result, ...)
    if LB._offField and not hashes then
      hashes = {}
      for turn, v in pairs(LB._myHashes or {}) do hashes[#hashes + 1] = { turn, v } end
      table.sort(hashes, function(a, b) return a[1] < b[1] end)
      desync = LB.endReason
      battleEnd = result
      local rows = {}
      for turn, r in pairs(LB._raw or {}) do
        rows[#rows + 1] = "turn " .. turn .. "\n" .. tostring(r.actives) .. "\n" .. tostring(r.volatile) .. "\n"
          .. tostring(r.bench) .. "\n" .. tostring(r.field)
      end
      table.sort(rows)
      writeFile(SYNC .. "/raw" .. SEAT .. ".txt", table.concat(rows, "\n"))
    end
    return origFinish(result, ...)
  end

  local partyChosen, saved, lobbyActed, leaderPicked, battles = false, 0, false, false, 0
  local retirePicked, continuePicked, declinedRecord = false, false, false
  local foePics, introPics
  local function choice(ch)
    local opts = ch.options or {}
    local labels = {}
    for i, o in ipairs(opts) do labels[i] = tostring(type(o) == "table" and (o.text or o.label or o[1]) or o):upper() end
    note("CHOICE " .. table.concat(labels, "|"))
    local function find(word)
      for i, l in ipairs(labels) do if l:find(word, 1, true) then return i end end
    end
    if find("BECOME LEADER") or find("JOIN GROUP") then
      leaderPicked = true
      return SEAT == 0 and (find("BECOME LEADER")) or find("JOIN GROUP")
    end
    if find("GO ON") then
      if SEAT == 0 then
        continuePicked = true
        return find("GO ON")
      end
      retirePicked = true
      return find("RETIRE")
    end
    if find("YES") and find("NO") and #labels == 2 and seen[#seen] and seen[#seen]:find("record your last", 1, true) then
      declinedRecord = true
      return find("NO")
    end
    if retirePicked and find("YES") and find("NO") and #labels == 2 then return find("YES") end
    if find("CHALLENGE") then return find("CHALLENGE") end
    if find("LV. 50") or find("LV.50") or find("LV50") then return 1 end
    return "yes"
  end
  local function idleUi()
    if PartyMenu.isOpen() and PartyMenu.mode == "choose_multi" and not partyChosen then
      partyChosen = true
      for _, slot in ipairs({ 1, 2 }) do
        PartyMenu.enterChosenMon(slot)
        U.wait(4)
      end
      PartyMenu.confirmChosenMons()
      U.wait(10)
      return true
    end
    if SaveMenu.isOpen() then
      saved = saved + 1
      U.tap(game, "a")
      U.wait(8)
      return true
    end
    return false
  end
  local ticks = 0
  local function watch()
    ticks = ticks + 1
    if ticks % 600 == 0 then
      local g = Client.group()
      note(string.format("tick %d map=%s lobby=%s msg=%s choice=%s members=%s room=%s", ticks, tostring(S.mapNow()),
        tostring(Lobby.isOpen()), tostring(Message.isOpen()), tostring(Choice.isOpen()),
        tostring(type(g) == "table" and type(g.members) == "table" and #g.members or "-"),
        tostring(Client.room() and Client.room().stage)))
    end
    if Lobby.isOpen() and not lobbyActed and not Choice.isOpen() then
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
    end
  end

  local shotBattle = false
  S.talkTo(game, attendant)
  S.settle(game, {
    limit = 200000,
    until_ = function()
      return battles >= 1 and (retirePicked or continuePicked) and S.mapNow() == LOBBY and not S.busy()
    end,
    choice = choice,
    watch = watch,
    onIdleUi = idleUi,
    onBattleStart = function(st)
      battles = battles + 1
      local rows = {}
      for _, side in ipairs({ "playerParty", "foeParty" }) do
        for i, m in ipairs(st[side] or {}) do
          local keys = {}
          for k, v in pairs(m) do
            if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = k .. "=" .. tostring(v) end
          end
          table.sort(keys)
          rows[#rows + 1] = side .. i .. " " .. table.concat(keys, " ")
          for _, sub in ipairs({ "stats", "ivs", "evs", "moves", "pp" }) do
            if type(m[sub]) == "table" then
              local parts = {}
              for k, v in pairs(m[sub]) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
              table.sort(parts)
              rows[#rows + 1] = "  " .. sub .. " " .. table.concat(parts, " ")
            end
          end
        end
      end
      writeFile(SYNC .. "/mons" .. SEAT .. ".txt", table.concat(rows, "\n"))
      if not foePics then
        local f = Util.frontier(Runtime.getSession())
        local ids = f.trainerIds or {}
        local n = tonumber(f.curChallengeBattleNum) or 0
        foePics = {
          a = st.trainerPicId, b = st.trainerB and st.trainerB.pic,
          wantA = D.frontSpriteId(Runtime.getSession(), tonumber(ids[n * 2 + 1]) or 0, D.FACILITY.TOWER),
          wantB = D.frontSpriteId(Runtime.getSession(), tonumber(ids[n * 2 + 2]) or 0, D.FACILITY.TOWER),
        }
        note(string.format("foe pics A=%s (want %s) B=%s (want %s)", tostring(foePics.a), tostring(foePics.wantA),
          tostring(foePics.b), tostring(foePics.wantB)))
      end
      note(string.format("battle %d vs %s multi=%s link=%s", battles, tostring(st.trainerName),
        tostring(LB.isMulti and LB.isMulti()), tostring(Link.link and Link.link.linkType)))
      if not shotBattle then
        shotBattle = true
        S.pendingBattleShot = TAG .. "_battle"
      end
    end,
    onBattleFrame = function()
      if introPics then return end
      local tr = require("src.core.game3.battle.anim").stage().trainer.enemy
      if tr and tr.visible and tr.pic2 ~= nil and (tonumber(tr.ox) or -1) == 0 then
        introPics = { a = tr.picId, b = tr.pic2 }
        d.shot(game, TAG .. "_intro")
      end
    end,
    onBattleEnd = function(result) note("battle " .. battles .. " -> " .. tostring(result)) end,
  })
  d.shot(game, TAG .. "_end")
  note("map=" .. tostring(S.mapNow()) .. " battles=" .. battles .. " saved=" .. saved)
  check(partyChosen, TAG .. " ChoosePartyForBattleFrontier picked two mons")
  check(leaderPicked, TAG .. " the lobby offered JOIN GROUP / BECOME LEADER")
  check(lobbyActed, TAG .. " paired through the wireless group screen")
  check(battles >= 1, TAG .. " fought a link multi battle (" .. battles .. ")")
  check(battleEnd == "win", TAG .. " the pair won the first multi battle (" .. tostring(battleEnd) .. ")")
  check(desync ~= "desync", TAG .. " no link desync (" .. tostring(desync) .. ")")
  check(foePics and foePics.a == foePics.wantA and foePics.b == foePics.wantB,
    TAG .. " opponents show their frontier trainer pics")
  check(introPics and foePics and introPics.a == foePics.wantA and introPics.b == foePics.wantB,
    TAG .. " the intro slides in both frontier trainer pics (" .. tostring(introPics and introPics.a) .. ","
      .. tostring(introPics and introPics.b) .. ")")
  check(foePics and foePics.a ~= LB.TRAINER_PIC_RED and foePics.a ~= LB.TRAINER_PIC_LEAF,
    TAG .. " opponent A is not drawn with a link trainer pic")
  check(sawText("want to battle"), TAG .. " intro names the two frontier trainers")
  check(sawText("were defeated"), TAG .. " win text is sText_TwoInGameTrainersDefeated")
  local list = {}
  for _, h in ipairs(hashes or {}) do list[#list + 1] = h[1] .. "=" .. h[2] end
  local mine = table.concat(list, ",")
  check(#list >= 1, TAG .. " turn hashes recorded (" .. #list .. ")")
  writeFile(SYNC .. "/hash" .. SEAT .. ".txt", mine)
  local theirs
  waitUntil(function()
    theirs = readFile(SYNC .. "/hash" .. (1 - SEAT) .. ".txt")
    return theirs ~= nil and theirs ~= ""
  end, 240)
  check(theirs == mine, TAG .. " both clients' battle hashes agree (" .. mine .. ")")
  if SEAT == 0 then
    check(continuePicked, TAG .. " leader chose GO ON")
    check(sawText("Your partner has retired"), TAG .. " leader sees gText_YourPartnerHasRetired")
  else
    check(retirePicked, TAG .. " member chose RETIRE")
    check(not sawText("Your partner has retired"), TAG .. " the retiring member does not see the partner text")
    check(declinedRecord, TAG .. " the retiring member declines the Frontier Pass record")
  end
  check(S.mapNow() == LOBBY, TAG .. " both warp back to the lobby (" .. tostring(S.mapNow()) .. ")")
  return finish()
end
