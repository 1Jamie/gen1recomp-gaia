local U = require("tests.drivers.util")
local Avatars = require("src.online.union.Avatars")
local FakeRelay = require("tests.support.fake_relay")
local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local Pokemon = require("src.pokemon.Pokemon")
local Presence = require("src.world.gen1.UnionRoomPresence")
local Protocol2 = require("src.online.Protocol2")
local PF = require("src.world.PikachuFollower")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")

local FP = { blue = "1111111111111111", crystal = "4444444444444444", firered = "5555555555555555",
             ruby = "7777777777777777", emerald = "6666666666666666" }

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function done()
    print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
    love.event.quit(fails == 0 and 0 or 1)
    coroutine.yield()
  end
  U.wait(10)
  local v = GameVersion.get()
  local dir = (os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-w5b-gen1") .. "/" .. v
  local home = os.getenv("HOME") .. "/Library/Application Support/LOVE/"
  Avatars.setReader(Avatars.directoryReader({
    red = home .. "g1r-red", blue = home .. "g1r-blue", yellow = home .. "g1r-yellow",
    crystal = home .. "g1r-crystal", firered = home .. "g1r-firered", ruby = home .. "g1r-ruby",
  }))

  local f = game.save.flags
  f.EVENT_GOT_STARTER = true
  f.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  f.EVENT_GOT_POKEDEX = true
  if GameVersion.isYellow() then
    game.save.pikachuInBall = false
    game.save.party = { Pokemon.new(game.data, "PIKACHU", 20), Pokemon.new(game.data, "PIDGEY", 5) }
  end
  game.save.lastOutdoor = { id = "VIRIDIAN_CITY", x = 10, y = 10 }

  local relay = FakeRelay.new({ clock = function() return love.timer.getTime() end })
  local mine = relay:seat("00000001", "ME")
  local Client = require("src.online.Client")
  Client.reset()
  Client.configure({ relayAddress = "fake:3", connect = function() return mine.transport end })
  Client.connect({ name = "ME", profiles = {} })

  local function step(n)
    for _ = 1, n or 1 do
      relay:pump()
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
  local function ow() return game.overworld end
  local function top() return game.stack:top() end
  local function atWorld() return top() == ow() end
  local function shot(name)
    U.still(game, ("%s/%s_%s.png"):format(dir, v, name))
  end
  ok(waitFor(function() return Client.state() == "online" end, 600), "the client links to the fake relay")

  FP.blue = require("src.online.union.Caps").fingerprint(game.data, 1)
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
  fake(2, "blue", "BLUE", 0, "player")
  fake(3, "crystal", "KRIS", 1, "player")
  fake(4, "firered", "LEAF", 0, "g3:3")
  fake(5, "ruby", "MAY", 1, "player")
  fake(6, "emerald", "WALLY", 0, "g3:5")
  step(4)

  local cx, cy = UnionRoomMap.cellFor(1)
  U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
  ok(waitFor(function()
    local s = Presence.active()
    return s and s.state == "joined" and #s:entities() == 5
  end, 1200), "the room connects and shows five members")
  local s = Presence.active()
  if not s then return done() end
  mash("a", atWorld, 60)
  step(20)

  local byName = {}
  for _, e in ipairs(s:entities()) do byName[e.p.name] = e end
  ok(byName.BLUE and not byName.BLUE.entry.standin and byName.BLUE.entry.gen == 1, "BLUE wears the Gen 1 sprite")
  ok(byName.KRIS and not byName.KRIS.entry.standin and byName.KRIS.entry.family == "gb2f", "KRIS wears Kris")
  ok(byName.LEAF and not byName.LEAF.entry.standin and byName.LEAF.entry.h == 32, "LEAF wears the FRLG class sprite")
  ok(byName.MAY and not byName.MAY.entry.standin and byName.MAY.entry.family == "rse:player", "MAY wears the R/S player")
  ok(byName.WALLY and byName.WALLY.entry.hostStandin and byName.WALLY.entry.hostVersion == v
    and #byName.WALLY.entry.need > 0, "WALLY wears a host-game trainer without an Emerald cache")
  ok(s.focus == byName.BLUE, "the faced member shows its name tag")
  for _, e in ipairs(s:entities()) do
    local x, y = UnionRoomMap.cellFor(e.p.slot)
    ok(e.cellX == x and e.cellY == y, ("%s stands on slot %d's cell"):format(e.p.name, e.p.slot))
  end

  local reads = Avatars.stats().reads
  step(120)
  ok(Avatars.stats().reads == reads, "no avatar cache reads while the room runs")

  local modes = { "gbc", "redpp", "ogred", "og" }
  for _, mode in ipairs(modes) do
    PaletteFX.setMode(mode)
    U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
    step(10)
    ok(Presence.active() == s and #ow().npcs >= 5, mode .. ": the members rebind after the map reloads")
    shot("01_room_" .. mode)
  end
  PaletteFX.setMode("gbc")
  U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
  step(10)

  local w0, h0, flags0 = love.window.getMode()
  love.window.setMode(160, 144, { resizable = true, minwidth = 160, minheight = 144 })
  step(8)
  shot("02_room_native_1x")
  love.window.setMode(390, 844, { resizable = true, minwidth = 160, minheight = 144 })
  step(8)
  shot("03_room_phone")
  PaletteFX.setMode("redpp")
  U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
  step(10)
  shot("03b_room_phone_redpp")
  PaletteFX.setMode("gbc")
  love.window.setMode(w0, h0, flags0)
  U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
  step(10)

  local lx, ly = byName.LEAF.cellX, byName.LEAF.cellY
  ow().player.cellX, ow().player.cellY = lx, ly - 1
  ow().player.px, ow().player.py = lx * 16, (ly - 1) * 16
  ow().player.facing = "down"
  step(6)
  shot("04_occlusion_tall_sprite_below_player")
  ok(s.focus == byName.LEAF, "facing LEAF from above tags LEAF")
  U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
  step(10)

  tap("a")
  ok(waitFor(function() return s.busy end, 120), "talking to BLUE opens the talk flow")
  ok(byName.BLUE.facing == "down", "BLUE turns to face the player")
  ok(mash("a", function()
    local t = top()
    return t and t.items and #t.items == 3
  end, 120), "the BATTLE / TRADE / CANCEL menu is up")
  step(4)
  shot("05_talk_menu")
  tap("a")
  local inv
  ok(waitFor(function()
    for _, i in pairs(relay.invites) do if i.to == seats.BLUE.id then inv = i end end
    return inv ~= nil
  end, 240), "a battle invite reaches BLUE")
  ok(waitFor(function() local t = top() return t and t.tick ~= nil end, 240), "the waiting line is up")
  shot("06_waiting")
  relay:handle(seats.BLUE.seat, { type = "invite_reply", id = inv.id, accept = true })
  ok(waitFor(function() return s.activity ~= nil end, 600), "BLUE accepting begins the activity")
  local PrepScreen = require("src.ui.union.prep.Gen1BattlePrep")
  ok(waitFor(function() return s.activity and s.activity.state == "ready" and getmetatable(top()) == PrepScreen end, 900),
    "the battle prep screen is up")
  local prep = s.activity and s.activity.prep
  ok(prep and prep.rules and prep.rules.ruleset == "native", "Gen 1 vs Gen 1 resolves the native ruleset")
  shot("07_battle_prep")
  tap("b")
  ok(waitFor(function() local t = top() return getmetatable(t) == PrepScreen and t.model.step == "closed" end, 120),
    "B cancels and the prep screen shows the cancelled line")
  shot("08_cancelled")
  ok(mash("a", function() return s.activity == nil and not s.busy and atWorld() end, 120),
    "the activity closes cleanly")
  ok(waitFor(function() return Client.room() == nil end, 600), "the prep room is left")

  relay:handle(seats.KRIS.seat, { type = "invite", to = "00000001", activity = "xg_trade",
                                  profile = seats.KRIS.profile, detail = {} })
  ok(waitFor(function() return s.busy end, 600), "KRIS's trade request opens a prompt")
  ok(byName.KRIS.facing ~= "down" or byName.KRIS.cellY < ow().player.cellY, "KRIS turns toward the player")
  ok(mash("a", function()
    local t = top()
    return t and getmetatable(t) == require("src.ui.ChoiceBox")
  end, 200), "the YES / NO box is up")
  shot("09_incoming_trade")
  tap("b")
  ok(waitFor(function() return not s.busy and atWorld() end, 240), "NO declines")

  ow().player.cellX, ow().player.cellY = byName.WALLY.cellX + 1, byName.WALLY.cellY
  ow().player.px, ow().player.py = ow().player.cellX * 16, ow().player.cellY * 16
  ow().player.facing = "left"
  step(4)
  tap("a")
  ok(waitFor(function() return s.busy end, 120), "talking to the stand-in opens the talk flow")
  step(60)
  shot("10_standin_line")
  mash("a", function() local t = top() return t and t.items ~= nil end, 200)
  tap("b")
  mash("a", function() return not s.busy and atWorld() end, 120)

  relay:handle(seats.MAY.seat, { type = "presence", status = "busy" })
  ow().player.cellX, ow().player.cellY = byName.MAY.cellX, byName.MAY.cellY + 1
  ow().player.px, ow().player.py = ow().player.cellX * 16, ow().player.cellY * 16
  ow().player.facing = "up"
  ok(waitFor(function() return s:entity(byName.MAY.p.slot).p.status == "busy" end, 240), "MAY's busy status arrives")
  tap("a")
  ok(waitFor(function() local t = top() return t and t.pages ~= nil end, 120), "talking to a busy member answers")
  step(40)
  shot("11_busy")
  mash("a", atWorld, 120)

  if GameVersion.isYellow() then
    U.teleport(game, UnionRoomMap.MAP_ID, UnionRoomMap.EXIT_X, UnionRoomMap.EXIT_Y, "up")
    step(20)
    for _ = 1, 4 do
      U.hold(game, "up", 18)
      step(20)
    end
    local pika = PF.current(ow())
    ok(pika ~= nil, "Pikachu follows inside the Union Room")
    local clash = false
    for _, e in ipairs(s:entities()) do
      if pika and pika.cellX == e.cellX and pika.cellY == e.cellY then clash = true end
    end
    ok(not clash, "Pikachu never shares a member's cell")
    shot("12_yellow_pikachu")
  end

  relay:drop(mine)
  ok(waitFor(function() return s.state == "reconnecting" end, 240), "a dropped link is noticed")
  ok(waitFor(function() return s.lostBox ~= nil end, 400), "the reconnecting line shows")
  step(60)
  shot("13_reconnecting")
  relay:reconnect(mine)
  ok(waitReal(function() return s.state == "joined" end, 10), "the link comes back")
  print(("client %s presence %s room %s"):format(Client.state(), s.state, s.room.state))
  ok(waitFor(function() return s.lostBox == nil and atWorld() end, 240), "the reconnecting line closes")
  ok(#s:entities() == 5, "every member is back after the resume")
  step(30)
  shot("14_resumed")

  U.teleport(game, "POKECENTER_2F", 6, 4, "down")
  step(4)
  ok(waitFor(function() return Presence.active() == nil end, 240), "leaving the map ends the presence")
  ok(waitFor(function()
    for _, inst in ipairs(relay.plazas.union) do if inst.slots["00000001"] then return false end end
    return true
  end, 240), "leaving the room leaves the plaza")
  done()
end
