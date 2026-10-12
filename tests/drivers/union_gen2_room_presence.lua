local U = require("tests.drivers.util")
local Avatars = require("src.online.union.Avatars")
local FakeRelay = require("tests.support.fake_relay")
local GameVersion = require("src.core.GameVersion")
local Presence = require("src.world.gen2.UnionRoomPresence")
local Protocol2 = require("src.online.Protocol2")
local RoomMap = require("src.world.gen2.UnionRoomMap")
local Text = require("src.ui.gen2.union.Text")

local FP = { red = "1111111111111111", crystal = "4444444444444444", firered = "5555555555555555",
             ruby = "7777777777777777", emerald = "6666666666666666" }

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function done()
    print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
    love.event.quit(fails == 0 and 0 or 1)
    coroutine.yield()
  end
  U.wait(60)
  local world = game.world
  if not ok(world and world.map ~= nil, "world booted") then return done() end
  local v = GameVersion.current
  local dir = (os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-w5b") .. "/" .. v
  local home = os.getenv("HOME") .. "/Library/Application Support/LOVE/"
  Avatars.setReader(Avatars.directoryReader({
    red = home .. "g1r-red", crystal = home .. "g1r-crystal", [v] = home .. "g1r-" .. v,
    firered = home .. "g1r-firered", ruby = home .. "g1r-ruby",
  }))

  local relay = FakeRelay.new({ clock = function() return love.timer.getTime() end })
  local mine = relay:seat("00000001", "ME")
  local Client = require("src.online.Client")
  Client.reset()
  Client.configure({ relayAddress = "fake:3", connect = function() return mine.transport end })

  local function step(n)
    for _ = 1, n or 1 do
      relay:pump()
      Client.update(0)
      coroutine.yield()
    end
  end
  local function waitFor(cond, n)
    for _ = 1, n or 600 do
      if cond() then return true end
      step(1)
    end
    return cond()
  end
  local function waitReal(cond, seconds)
    local stop = love.timer.getTime() + seconds
    while love.timer.getTime() < stop do
      if cond() then return true end
      step(1)
    end
    return cond()
  end
  local function remode(w, h, flags)
    love.window.setMode(w, h, flags)
    world.mapImages = {}
    world.mapImage = world:imageFor(world.map.id)
    step(6)
  end
  local function tap(btn)
    table.insert(game.input.pressQueue, btn)
    step(1)
    game.input.state[btn] = false
    step(2)
  end
  local function mash(btn, cond, n)
    for _ = 1, n or 200 do
      if cond() then return true end
      tap(btn)
    end
    return cond()
  end
  local function shot(name)
    U.still(game, ("%s/%s_%s.png"):format(dir, v, name))
  end

  local seats = {}
  local function fake(n, version, name, gender, style)
    local id = ("%08x"):format(n)
    local seat = relay:seat(id, name)
    local gen = GameVersion.generation(version)
    local profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
                      fingerprint = FP[version], rulesetId = gen == 3 and "g3_single" or "union",
                      kind = "vanilla" }
    relay:handle(seat, Protocol2.lobbyHello({ name = name, profiles = { profile }, xgen = 1 }))
    relay:handle(seat, Protocol2.plazaJoin("union", profile,
      { name = name, trainerId = n, gender = gender, version = version, style = style }, 40,
      { xgen = 1, caps = { proto = 1, policy = 1, gens = { [tostring(gen)] = { { version = version, fp = FP[version] } } } } }))
    seats[name] = { seat = seat, id = id, profile = profile }
    return seat
  end
  fake(2, "red", "RED", 0, "player")
  fake(3, "crystal", "KRIS", 1, "player")
  fake(4, "firered", "LEAF", 0, "g3:3")
  fake(5, "ruby", "MAY", 1, "player")
  fake(6, "emerald", "WALLY", 0, "g3:5")

  local cx, cy = RoomMap.cellFor(1)
  world:warpToMapId(RoomMap.ID, cx, cy + 1, "up")
  ok(waitFor(function()
    local s = Presence.active()
    return s and s.state == "joined" and #s:entities() == 5
  end, 1200), "the room connects and shows five members")
  local s = Presence.active()
  if not s then return done() end
  mash("a", function() return game.stack:top() == nil and s.ui == nil end, 60)
  step(30)

  local byName = {}
  for _, e in ipairs(s:entities()) do byName[e.participant.name] = e end
  ok(byName.RED and not byName.RED.avatar.standin and byName.RED.avatar.gen == 1, "RED wears the Gen 1 sprite")
  ok(byName.KRIS and not byName.KRIS.avatar.standin and byName.KRIS.avatar.family == "gb2f", "KRIS wears Kris")
  ok(byName.LEAF and not byName.LEAF.avatar.standin and byName.LEAF.avatar.h == 32, "LEAF wears the FRLG class sprite")
  ok(byName.MAY and not byName.MAY.avatar.standin and byName.MAY.avatar.family == "rse:player", "MAY wears the R/S player")
  ok(byName.WALLY and byName.WALLY.avatar.hostStandin and byName.WALLY.avatar.hostVersion == v
    and #byName.WALLY.avatar.need > 0, "WALLY wears a host-game trainer without an Emerald cache")
  ok(s.tagged == byName.RED, "the faced member shows its name tag")
  shot("01_room_default")

  local G = love.graphics
  local w0, h0, flags0 = love.window.getMode()
  remode(160, 144, { resizable = true, minwidth = 160, minheight = 144 })
  shot("02_room_native_1x")
  remode(390, 844, { resizable = true, minwidth = 160, minheight = 144 })
  shot("03_room_phone")
  remode(w0, h0, flags0)

  tap("a")
  ok(waitFor(function() return s.ui == "talk" end, 120), "talking to RED opens the talk flow")
  ok(byName.RED.facing == "down", "RED turns to face the player")
  ok(mash("a", function()
    local top = game.stack:top()
    return top and top.items and #top.items == 3
  end, 120), "the BATTLE / TRADE / CANCEL menu is up")
  step(4)
  shot("04_talk_menu")
  tap("a")
  local inv
  ok(waitFor(function()
    for _, i in pairs(relay.invites) do if i.to == seats.RED.id then inv = i end end
    return inv ~= nil
  end, 240), "a battle invite reaches RED")
  ok(waitFor(function() local t = game.stack:top() return t and t.tick ~= nil end, 240), "the waiting line is up")
  shot("05_waiting")
  relay:handle(seats.RED.seat, { type = "invite_reply", id = inv.id, accept = true })
  ok(waitFor(function() return s.activity ~= nil end, 600), "RED accepting begins the activity")
  ok(waitFor(function() return s.activity and s.activity.waiter and s.activity.waiter:shown() end, 600),
    "the getting-ready line is up")
  local prep = s.activity and s.activity.prep
  waitFor(function() return prep and prep.rules ~= nil end, 120)
  print(("prep state %s blocked %s caps %s"):format(tostring(prep and prep.state), tostring(prep and prep.blocked),
    tostring(s.room.caps and next(s.room.caps.gens))))
  ok(prep and prep.rules and prep.rules.ruleset == "g3u", "Gen 2 vs Gen 1 resolves the g3u ruleset")
  local PrepScreen = require("src.ui.union.prep.Gen2BattlePrep")
  ok(waitFor(function() return getmetatable(game.stack:top()) == PrepScreen end, 600), "the battle prep screen is up")
  shot("06_battle_prep")
  tap("b")
  ok(waitFor(function()
    local t = game.stack:top()
    return getmetatable(t) == PrepScreen and t.model.step == "closed"
  end, 120), "B cancels and the prep screen shows the cancelled line")
  shot("07_cancelled")
  ok(mash("a", function() return s.activity == nil and s.ui == nil and game.stack:top() == nil end, 120),
    "the activity closes cleanly")
  ok(waitFor(function() return Client.room() == nil end, 600), "the prep room is left")

  relay:handle(seats.KRIS.seat, { type = "invite", to = "00000001", activity = "xg_trade",
                                  profile = seats.KRIS.profile, detail = {} })
  ok(waitFor(function() return s.ui == "prompt" end, 600), "KRIS's trade request opens a prompt")
  ok(mash("a", function()
    local top = game.stack:top()
    return top and getmetatable(top) == require("src.ui.ChoiceBox")
  end, 200), "the YES / NO box is up")
  shot("08_incoming_trade")
  tap("down")
  tap("a")
  ok(waitFor(function() return s.ui == nil and game.stack:top() == nil end, 240), "NO declines")

  world.player.cellX, world.player.cellY = byName.WALLY.cellX + 1, byName.WALLY.cellY
  world.player.px, world.player.py = world.player.cellX * 16, world.player.cellY * 16
  world.player.facing = "left"
  step(4)
  tap("a")
  ok(waitFor(function() return s.ui == "talk" end, 120), "talking to the stand-in opens the talk flow")
  step(40)
  shot("09_standin_line")
  mash("b", function() local t = game.stack:top() return t and t.items ~= nil end, 200)
  tap("b")
  mash("a", function() return s.ui == nil and game.stack:top() == nil end, 120)

  relay:handle(seats.MAY.seat, { type = "presence", status = "busy" })
  world.player.cellX, world.player.cellY = byName.MAY.cellX, byName.MAY.cellY + 1
  world.player.px, world.player.py = world.player.cellX * 16, world.player.cellY * 16
  world.player.facing = "up"
  ok(waitFor(function() return Presence.active():entity(byName.MAY.unionSlot).participant.status == "busy" end, 240),
    "MAY's busy status arrives")
  tap("a")
  ok(waitFor(function() local t = game.stack:top() return t and t.pages ~= nil end, 120), "talking to a busy member answers")
  step(40)
  shot("10_busy")
  mash("a", function() return s.ui == nil and game.stack:top() == nil end, 120)

  relay:drop(mine)
  ok(waitFor(function() return s.lost end, 240), "a dropped link is noticed")
  step(60)
  ok(waitFor(function() return s.ui == "notice" end, 240), "the reconnecting line shows")
  step(20)
  shot("11_reconnecting")
  relay:reconnect(mine)
  ok(waitReal(function() return not s.lost end, 10), "the link comes back")
  ok(waitFor(function() return s.ui == nil end, 240), "the reconnecting line closes")
  ok(#s:entities() == 5, "every member is back after the resume")
  step(30)
  shot("12_resumed")

  world:warpToMapId("POKECENTER_2F", 4, 4, "down")
  ok(waitFor(function() return Presence.active() == nil end, 240), "leaving the map ends the presence")
  ok(waitFor(function()
    for _, inst in ipairs(relay.plazas.union) do if inst.slots["00000001"] then return false end end
    return true
  end, 240), "leaving the room leaves the plaza")
  done()
end
