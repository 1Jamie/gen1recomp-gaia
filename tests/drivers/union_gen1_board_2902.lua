local U = require("tests.drivers.util")
local FakeRelay = require("tests.support.fake_relay")
local GameVersion = require("src.core.GameVersion")
local Pokemon = require("src.pokemon.Pokemon")
local Presence = require("src.world.gen1.UnionRoomPresence")
local Protocol2 = require("src.online.Protocol2")
local TextBox = require("src.render.TextBox")
local UnionCenters = require("src.world.gen1.UnionCenters")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
    love.event.quit(fails == 0 and 0 or 1)
    coroutine.yield()
  end
  U.wait(10)
  local v = GameVersion.get()
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-board-2902"
  local f = game.save.flags
  f.EVENT_GOT_STARTER = true
  f.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  f.EVENT_GOT_POKEDEX = true
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
  local function tap(btn)
    table.insert(game.input.pressQueue, btn)
    step(1)
    game.input.state[btn] = false
    step(2)
  end
  local function ow() return game.overworld end
  local function top() return game.stack:top() end
  local function atWorld() return top() == ow() end
  local function shot(name)
    for _ = 1, 240 do
      local t = top()
      if not (t and t.pages and not t.done) then break end
      step(1)
    end
    step(30)
    U.still(game, ("%s/2902_%s_%s.png"):format(dir, v, name))
  end
  local function boxText()
    local t = top()
    if getmetatable(t) ~= TextBox then return "" end
    local out = {}
    for _, page in ipairs(t.pages or {}) do
      for _, line in ipairs(page) do out[#out + 1] = type(line) == "table" and table.concat(line) or tostring(line) end
    end
    return table.concat(out, " ")
  end
  local function until_(cond, btn, n)
    for _ = 1, n or 200 do
      if cond() then return true end
      tap(btn or "a")
    end
    return cond()
  end
  local function shows(s) return function() return boxText():find(s, 1, true) ~= nil end end

  local Caps = require("src.online.union.Caps")
  local liveMods = Caps.gameplayMods
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 5), Pokemon.new(game.data, "RATTATA", 5) }
  ok(liveMods(game), "this identity has link-play mods on")
  U.teleport(game, UnionCenters.FLOOR_2F, 7, 3, "up")
  tap("a")
  ok(until_(shows("link play"), "a", 120), "link-play mods are refused at the desk: " .. boxText())
  shot("00_mods_refused")
  ok(until_(shows("come again"), "a", 60), "then please come again: " .. boxText())
  ok(until_(atWorld, "a", 120), "the refusal closes")
  ok(ow().map.id == UnionCenters.FLOOR_2F, "a modded save stays on the 2F")
  Caps.gameplayMods = function() return false end

  game.save.party = { Pokemon.new(game.data, "PIDGEY", 5) }
  U.teleport(game, UnionCenters.FLOOR_2F, 7, 3, "up")
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.ChoiceBox") end, "a", 120),
     "the union attendant asks to go in")
  tap("a")
  ok(until_(shows("at least two"), "a", 60), "one POKEMON gets the need-two line: " .. boxText())
  shot("01_need_two")
  ok(until_(atWorld, "a", 120), "the refusal closes")
  ok(ow().map.id == UnionCenters.FLOOR_2F, "the player stays on the 2F")

  game.save.party = { Pokemon.new(game.data, "PIDGEY", 5), Pokemon.new(game.data, "RATTATA", 5) }
  ok(waitFor(function() return Client.state() == "online" end, 600), "the client links to the fake relay")
  local leaf = relay:seat("00000004", "LEAF")
  local profile = { engine = 3, version = "firered", engineVersion = "0.0.0-dev", apiVersion = 2,
                    fingerprint = "5555555555555555", rulesetId = "g3_single", kind = "vanilla" }
  relay:handle(leaf, Protocol2.lobbyHello({ name = "LEAF", profiles = { profile }, xgen = 1 }))
  relay:handle(leaf, Protocol2.plazaJoin("union", profile,
    { name = "LEAF", trainerId = 4, gender = 1, version = "firered", style = "g3:3" }, 40,
    { xgen = 1, caps = { proto = 1, policy = 1, gens = { ["3"] = { { version = "firered", fp = "5555555555555555" } } } } }))
  -- pokefirered/include/constants/pokemon.h:6
  relay:handle(leaf, Protocol2.presence({ board = { species = 7, level = 5, wantType = 0 } }))
  step(4)

  local ax, ay = UnionRoomMap.ATTENDANT.x, UnionRoomMap.ATTENDANT.y
  U.teleport(game, UnionRoomMap.MAP_ID, ax, ay + 1, "up")
  ok(waitFor(function()
    local s = Presence.active()
    return s and s.state == "joined" and #s:entities() == 1
  end, 1200), "the room connects with LEAF in it")
  local s = Presence.active()
  if not s then return finish() end
  until_(atWorld, "b", 60)
  local nurse = ow():npcAtCell(ax, ay)
  ok(nurse and nurse.def.sprite == "SPRITE_NURSE", "the nurse stands at FRLG's attendant cell")
  shot("02_room_nurse")

  tap("a")
  ok(until_(function() local t = top() return t and t.items and #t.items == 3 end, "a", 120),
     "the nurse offers REGISTER / INFO / EXIT")
  shot("03_register_menu")
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.PartyMenu") end, "a", 60), "the party menu opens")
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.ListMenu") end, "a", 60), "the type list opens")
  shot("04_type_list")
  tap("a")
  ok(until_(shows("completed"), "a", 60), "registration completes")
  local posted = s.boardEntry and s.boardEntry.board
  ok(posted and posted.species == 16 and posted.wantType == 0, "PIDGEY is posted wanting NORMAL")
  until_(atWorld, "a", 60)

  U.teleport(game, UnionRoomMap.MAP_ID, UnionRoomMap.BOARD.x, UnionRoomMap.BOARD.y + 1, "up")
  step(10)
  until_(atWorld, "b", 30)
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.ListMenu") end, "a", 60), "the trading board opens")
  local list = top()
  ok(list and list.items and #list.items == 2 and tostring(list.items[1].label):find("SQUIRTLE", 1, true) ~= nil,
     "LEAF's SQUIRTLE is on the board")
  shot("05_board_list")
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.ChoiceBox") end, "a", 60),
     "PIDGEY fits LEAF's NORMAL request, so the trade is asked")
  shot("06_ask_trade")
  tap("a")
  local inv
  ok(waitFor(function()
    for _, i in pairs(relay.invites) do if i.to == "00000004" then inv = i end end
    return inv ~= nil
  end, 240), "an invite reaches LEAF")
  ok(inv and inv.activity == "xg_trade", "as a cross-gen trade")
  tap("b")
  until_(atWorld, "a", 120)
  Caps.gameplayMods = liveMods
  finish()
end
