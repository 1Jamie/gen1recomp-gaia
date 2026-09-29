local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_lmg_minigames"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function now() return love.timer.getTime() end

local function finish()
  local Client = package.loaded["src.online.Client"]
  if Client then pcall(Client.disconnect) end
  print((failures == 0 and "PASS" or "FAIL") .. " em_lmg_minigames failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local okNew = pcall(function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local GameVersion = require("src.core.GameVersion")
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local Client = require("src.online.Client")
  local ArenaData = require("src.online.ArenaData")
  local Relay = require("tests.support.fake_relay")
  local Wire = require("src.link.Wire")
  local MG = require("src.core.game3.minigames.common")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local Countdown = require("src.ui.game3.minigames.common_countdown")
  local Art = require("src.ui.game3.minigames.common_art")
  local Pouch = require("src.ui.game3.minigames.berry_crush.pouch")

  local session = Runtime.getSession()
  result(okNew and session ~= nil, "new game reached the emerald field")
  result(GameVersion.get() == "emerald", "running emerald (" .. tostring(GameVersion.get()) .. ")")
  if not session then return finish() end
  session.trainerId = 0x1234

  local cache = Art.cache()
  for _, rel in ipairs({ "link/manifest.lua", "berry_crush/manifest.lua", "dodrio_berry_picking/manifest.lua",
      "pokemon_jump/manifest.lua", "mystery_gift/manifest.lua" }) do
    result(cache:read(Art.ROOT .. rel) ~= nil, "emerald cache has " .. rel)
  end
  result(Countdown.loadArt() ~= nil, "minigame countdown art loads")

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "BRENDAN")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })
  local profile, why = ArenaData.liveProfile3(Runtime._game or game, "g3_link")
  if not result(profile ~= nil, "live emerald profile (" .. tostring(why) .. ")") then return finish() end
  Client.connect({ name = "BRENDAN", profiles = { profile }, presence = { where = "game", status = "busy" } })

  local peers = {}
  local function peerSession(s)
    local rs = { paired = true, closed = false, left = false, seq = 0, target = s.room }
    function rs:send(msg)
      self.seq = self.seq + 1
      relay:handle(s, { type = "room_msg", seq = self.seq, msg = msg })
    end
    function rs:poll()
      local out = {}
      for _, m in ipairs(s.transport.inbox) do
        if m.type == "room_msg" and type(m.msg) == "table" then
          local inner = Wire.sanitize(m.msg)
          if inner then
            if m.relay then
              inner.relay = true
              if type(inner.seat) ~= "number" then inner.seat = -1 end
            else
              inner.seat = m.seat
            end
            out[#out + 1] = inner
          end
        end
      end
      s.transport.inbox = {}
      return out
    end
    function rs:players()
      local room = relay.rooms[s.room or ""]
      return room and room.players or {}
    end
    function rs:close()
      self.left = true
      self.closed = true
      relay:handle(s, { type = "room_leave" })
    end
    return rs
  end

  local function stepPeers()
    pcall(Client.update, MG.DT)
    for _, p in ipairs(peers) do
      if not p.m:finished() then
        local t = now()
        p.acc = p.acc + (t - p.last)
        p.last = t
        local n = 0
        while p.acc >= MG.DT and n < 8 do
          p.acc = p.acc - MG.DT
          n = n + 1
          p.input.n = p.input.n + 1
          p.m:step(p.input)
        end
      end
    end
  end

  local function waitFor(cond, seconds)
    local t0 = now()
    while not cond() do
      relay:pump()
      stepPeers()
      U.wait(1)
      if now() - t0 > (seconds or 5) then return false end
    end
    return true
  end
  local function pause(seconds)
    local t0 = now()
    waitFor(function() return now() - t0 >= seconds end, seconds + 1)
  end
  local function tap(key)
    U.tap(game, key)
    relay:pump()
    stepPeers()
  end

  waitFor(function() return Client.state() == "online" end, 5)
  result(Client.state() == "online", "client online on the fake relay")

  local function peerModule(G, bagSession)
    local M = setmetatable({}, { __index = G })
    M.hooks = setmetatable({
      session = function() return bagSession end,
      playSe = function() end, playSong = function() end, pauseMusic = function() end,
      resumeMusic = function() end, save = function() end, tick = function() end,
      newCountdown = function() return Countdown.new(120, 80, { playSe = function() end }) end,
      pickBerry = function(_, done)
        local list = Bag.listPocket(bagSession.bag, "BERRY_POUCH")
        done(list[1] and tonumber(list[1].id) or nil)
      end,
    }, { __index = G.hooks })
    M.new = function(ctx) return G.Sim.new(M, ctx) end
    return M
  end

  local function startPeer(game3Id, G, s, species)
    local room = relay.rooms[s.room or ""]
    local seat = relay:seatOf(room, s.id)
    local players = {}
    for _, p in ipairs(room.players) do
      players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0x2000 + p.seat, gender = p.seat % 2 }
    end
    local input = { n = 0 }
    function input:wasPressed(b) return b == "a" and self.n % 20 == 0 end
    function input:isDown() return false end
    local module = G
    if game3Id == "crush" then
      local bagSession = { bag = Bag.new(), berryPowder = 0 }
      Bag.add(bagSession.bag, 133 + seat, 2)
      module = peerModule(G, bagSession)
    end
    local m = MG.Match.new({ game = game3Id, session = peerSession(s), seat = seat, seats = #players,
      players = players, seed = room.seed, partySlot = 0 },
      { module = module, art = assert(G.loadArt()), leader = room.leader,
        partyMon = species and { species = species, personality = 0x5a5a0000 + seat, otId = 77 } or nil,
        me = { name = s.name, trainerId = 0x2000 + seat, gender = seat % 2 },
        countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end })
    peers[#peers + 1] = { s = s, m = m, input = input, acc = 0, last = now() }
  end

  local function play(spec)
    local G = require("src.core.game3.minigames." .. spec.module)
    print("[driver] " .. spec.id)
    Lobby.showPlayers({ { name = "MAY", trainerId = 0x2222 }, { name = "WALLY", trainerId = 0x3333 } },
      { mode = "leader", group = { min = spec.min, max = 5 }, activity = spec.activity })
    pause(0.3)
    U.still(game, DIR .. "/em_" .. spec.id .. "_lobby.png")
    Lobby.reset()

    peers = {}
    Client.openGroup(spec.wire, profile, { name = "BRENDAN", trainerId = 0x1234, gender = 0, version = "emerald" })
    if not result(waitFor(function() return Client.group() ~= nil end, 5), spec.id .. ": group opened") then return end
    local names = { "MAY", "WALLY" }
    local seats = {}
    for i, name in ipairs(names) do
      local s = relay:seat(string.format("b%07x", i + 16 * #spec.id), name)
      relay:handle(s, { type = "lobby_hello", protocol = 3, name = name, profiles = { profile } })
      relay:handle(s, { type = "group_join", leader = me.id, profile = profile,
        avatar = { name = name, trainerId = 0x2000 + i, gender = i % 2, version = i == 1 and "emerald" or "firered" } })
      seats[i] = s
    end
    local accepted = {}
    waitFor(function()
      local g = Client.group()
      for _, p in ipairs(g and g.pending or {}) do
        if not accepted[p.id] then accepted[p.id] = true; Client.acceptGroup(p.id, true) end
      end
      return g and #(g.members or {}) >= 3
    end, 5)
    Client.startGroup()
    if not result(waitFor(function()
      local room = Client.room()
      return room ~= nil and room.match ~= nil
    end, 5), spec.id .. ": group started a minigame room") then return end
    local room = Client.room()
    if not room then return end
    local players = {}
    for _, p in ipairs(room.players or {}) do
      players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0, gender = 0 }
    end
    MG.partySlot = spec.species and 0 or nil
    MG.launch({ game = spec.game, session = Client.roomSession(), seat = Client.seat(), seats = room.seats,
      players = players, seed = room.seed, returnToMap = false, partySlot = spec.species and 0 or nil })
    for _, s in ipairs(seats) do startPeer(spec.game, G, s, spec.species) end
    local mine = MG.match()
    if not result(mine ~= nil, spec.id .. ": MG built a match (art loaded)") then
      local run = MG._run
      print("[driver] art error " .. tostring(run and run.artError))
      MG.abort("driver")
      return
    end
    result(waitFor(function() return mine.phase ~= "ready" end, 10), spec.id .. ": every seat readied")
    if spec.drive then spec.drive(mine, tap, waitFor, pause) end
    local shot = {}
    waitFor(function()
      local cd = mine.countdown or (mine.sim and mine.sim.countdown)
      if not shot.cd and cd and cd.digitShown and cd:digitShown() == 3 then
        pause(0.15)
        shot.cd = U.still(game, DIR .. "/em_" .. spec.id .. "_countdown.png")
      end
      return mine.phase == "play" and (shot.cd or (mine.sim and mine.sim.started))
    end, 25)
    result(mine.phase == "play", spec.id .. ": reached play (phase " .. tostring(mine.phase) .. ")")
    pause(spec.playFor or 3)
    U.still(game, DIR .. "/em_" .. spec.id .. "_play.png")
    result(mine.sim ~= nil and not mine.simError, spec.id .. ": sim running with no error " .. tostring(mine.simError))
    MG.abort("driver")
    for _, p in ipairs(peers) do pcall(function() p.m.channel:leave() end) end
    peers = {}
    pause(0.5)
  end

  local jumpTables = Art.tables("pokemon_jump")
  local jumpSpecies = jumpTables and jumpTables.jump_mons[1].species
  result(jumpSpecies ~= nil, "emerald sPokeJumpMons read (first " .. tostring(jumpSpecies) .. ")")
  if jumpSpecies then Party.giveMon(session, jumpSpecies, 20) end
  play({ id = "pokemon_jump", module = "pokemon_jump", game = "jump", wire = "minigame_jump", activity = 9,
    min = 2, species = jumpSpecies, playFor = 4 })

  session.party = {}
  Party.giveMon(session, 85, 30)
  play({ id = "dodrio", module = "dodrio_berry_picking", game = "pick", wire = "minigame_pick", activity = 11,
    min = 3, species = 85, playFor = 4 })

  Bag.add(session.bag, 140, 3)
  play({ id = "berry_crush", module = "berry_crush", game = "crush", wire = "minigame_crush", activity = 10,
    min = 2, playFor = 3,
    drive = function(mine, tapK, wait, pauseK)
      local function stage() return mine.sim and mine.sim.stage end
      wait(function() return stage() == "ask" and mine.sim.printer and mine.sim.printer.prompt end, 15)
      tapK("a")
      local opened = wait(function()
        local Bm = require("src.ui.game3.screens").get("bag", session)
        return Pouch.isOpen() and Bm and Bm.open
      end, 10)
      result(opened, "berry_crush: emerald opened the BAG berries pocket (not the Berry Pouch)")
      pauseK(0.6)
      U.still(game, DIR .. "/em_berry_crush_bag.png")
      tapK("a")
      pauseK(0.3)
      tapK("a")
      result(wait(function() return not Pouch.isOpen() end, 6), "berry_crush: CONFIRM picked a berry")
      result(Bag.get(session.bag, 140) == 2, "berry_crush: one berry spent")
    end })

  game:returnToTitle()
  U.wait(60)
  local Boot = require("src.ui.game3.boot")
  local MysteryGiftUi = require("src.ui.game3.mystery_gift")
  for _ = 1, 60 do
    if game.boot and game.boot.phase == Boot.PHASE.MENU then break end
    U.tap(game, "start")
    U.wait(20)
  end
  if result(game.boot ~= nil and game.boot.phase == Boot.PHASE.MENU, "back at the emerald main menu") then
    local menu = game.boot.custom and game.boot.custom.menu
    if menu and menu._openMysteryGift then
      menu:_openMysteryGift()
    else
      Boot.openMysteryGift(game.boot)
    end
    U.wait(40)
    result((menu and menu.state == "mystery_gift") or game.boot.phase == Boot.PHASE.MYSTERY_GIFT,
      "the Mystery Gift screen opened")
    U.still(game, DIR .. "/em_mystery_gift_menu.png")
    MysteryGiftUi.reloadAssets()
    local okArt, errArt = pcall(function()
      for n = 0, 7 do
        assert(MysteryGiftUi.cardBackground(n), "card_bg" .. n)
        assert(MysteryGiftUi.newsBackground(n), "news_bg" .. n)
        assert(MysteryGiftUi.stampShadow(n), "stamp shadow " .. n)
      end
    end)
    result(okArt, "all 8 wonder card / news backgrounds and stamp shadows load " .. tostring(errArt or ""))
    if okArt then
      local canvas = love.graphics.newCanvas(240 * 4, 160 * 4)
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.clear(0, 0, 0, 1)
      for n = 0, 7 do
        local x, y = (n % 4) * 240, math.floor(n / 4) * 160
        love.graphics.draw(MysteryGiftUi.cardBackground(n), x, y)
        love.graphics.draw(MysteryGiftUi.newsBackground(n), x, y + 320)
        love.graphics.draw(MysteryGiftUi.stampShadow(n), x + 200, y + 136)
      end
      love.graphics.setCanvas()
      love.graphics.pop()
      local data = canvas:newImageData()
      local fh = io.open(DIR .. "/em_mystery_gift_backgrounds.png", "wb")
      if fh then
        fh:write(data:encode("png"):getString())
        fh:close()
      end
    end
  end
  finish()
end
