local U = require("tests.drivers.util")
local Center = require("src.world.gen2.UnionCenter2F")
local FakeRelay = require("tests.support.fake_relay")
local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local Presence = require("src.world.gen2.UnionRoomPresence")
local Protocol2 = require("src.online.Protocol2")
local RoomMap = require("src.world.gen2.UnionRoomMap")
local TextBox = require("src.render.TextBox")

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
  U.wait(60)
  local world = game.world
  if not ok(world and world.map ~= nil, "world booted") then return finish() end
  local v = GameVersion.current
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/union-board-2902-gen2"
  local save = game.save

  if not require("src.online.union.Caps").gameplayMods(game) then
    local marker = "union_gen2_board_2902_restart"
    if love.filesystem.getInfo(marker) then
      ok(false, "the forced gameplay mod is live after the restart")
      return finish()
    end
    love.filesystem.write(marker, "1")
    local loader = game.mods
    ok(loader and loader:setEnabled("example_mew_starter", true), "example_mew_starter enabled")
    ok(loader and loader:setGen2Forced("example_mew_starter", true), "example_mew_starter forced onto this Gen 2 game")
    if fails > 0 then return finish() end
    print("restarting so the mod loads")
    love.event.quit("restart")
    coroutine.yield()
    return
  end

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
  local function tap(btn)
    table.insert(game.input.pressQueue, btn)
    step(1)
    game.input.state[btn] = false
    step(2)
  end
  local function top() return game.stack:top() end
  local function boxText()
    for i = #game.stack.states, 1, -1 do
      local t = game.stack.states[i]
      if getmetatable(t) == TextBox then
        local out = {}
        for _, page in ipairs(t.pages or {}) do
          for _, line in ipairs(page) do out[#out + 1] = type(line) == "table" and table.concat(line) or tostring(line) end
        end
        return table.concat(out, " ")
      end
    end
    return ""
  end
  local function until_(cond, btn, n)
    for _ = 1, n or 200 do
      if cond() then return true end
      tap(btn or "a")
    end
    return cond()
  end
  local function shows(s) return function() return boxText():find(s, 1, true) ~= nil end end
  local function shot(name)
    for _ = 1, 300 do
      local box
      for i = #game.stack.states, 1, -1 do
        if getmetatable(game.stack.states[i]) == TextBox then box = game.stack.states[i] break end
      end
      if not box or box.done or box.waiting then break end
      step(1)
    end
    step(30)
    U.still(game, ("%s/2902_%s_%s.png"):format(dir, v, name))
  end
  local function calm() return top() == nil and not world:busy() end

  local gate = game.data.gen2Scripts[Center.RECEPTIONIST_KEY][3].event
  world.events:set(gate, true)
  local def2f = world.maps[Center.MAP_ID]
  local row = {}
  for bx = 0, 7 do row[#row + 1] = string.format("%02x", def2f.blocks[def2f.width + bx + 1]) end
  print("2F row 1 blocks " .. table.concat(row, " "))
  local Caps = require("src.online.union.Caps")
  local liveMods = Caps.gameplayMods
  local egg = Mon.new(game.data, "TOGEPI", 5)
  egg.isEgg = true
  save.party = { Mon.new(game.data, "CYNDAQUIL", 12), egg }
  local rcpt
  for _, o in ipairs(world.maps[Center.MAP_ID].objects) do
    if o.scriptKey == Center.RECEPTIONIST_KEY then rcpt = o end
  end
  if not ok(rcpt ~= nil, "union receptionist is on the 2F") then return finish() end
  local colo
  for _, w in ipairs(def2f.warps) do if w.destMap == "COLOSSEUM" then colo = w end end
  local unionDoor
  for _, w in ipairs(def2f.warps) do if w.destMap == RoomMap.ID then unionDoor = w end end
  ok(unionDoor and colo and unionDoor.y == colo.y and rcpt.x == unionDoor.x and rcpt.y == colo.y + 2,
     ("union door (%s,%s) and desk (%d,%d) sit in the added column, level with the COLOSSEUM desk"):format(
       tostring(unionDoor and unionDoor.x), tostring(unionDoor and unionDoor.y), rcpt.x, rcpt.y))
  world:warpToMapId(Center.MAP_ID, rcpt.x - 4, rcpt.y + 2, "up")
  step(30)
  shot("00_2f_layout")
  ok(liveMods(game), "this identity has link-play mods on")
  world:warpToMapId(Center.MAP_ID, rcpt.x, rcpt.y + 1, "up")
  step(30)
  tap("a")
  ok(until_(shows("link play"), "a", 120), "link-play mods are refused at the desk: " .. boxText())
  shot("00b_mods_refused")
  until_(calm, "a", 120)
  ok(world.map.id == Center.MAP_ID, "a modded save stays on the 2F")
  Caps.gameplayMods = function() return false end
  world:warpToMapId(Center.MAP_ID, rcpt.x, rcpt.y + 1, "up")
  step(30)
  tap("a")
  ok(until_(shows("at least two"), "a", 120), "a POKEMON and an EGG get the need-two line: " .. boxText())
  shot("01_need_two_with_egg")
  until_(calm, "a", 120)
  ok(world.map.id == Center.MAP_ID, "the player stays on the 2F")

  save.party = { Mon.new(game.data, "CYNDAQUIL", 12), Mon.new(game.data, "MAREEP", 8) }
  local leaf = relay:seat("00000004", "LEAF")
  local profile = { engine = 3, version = "firered", engineVersion = "0.0.0-dev", apiVersion = 2,
                    fingerprint = "5555555555555555", rulesetId = "g3_single", kind = "vanilla" }
  relay:handle(leaf, Protocol2.lobbyHello({ name = "LEAF", profiles = { profile }, xgen = 1 }))
  relay:handle(leaf, Protocol2.plazaJoin("union", profile,
    { name = "LEAF", trainerId = 4, gender = 1, version = "firered", style = "g3:3" }, 40,
    { xgen = 1, caps = { proto = 1, policy = 1, gens = { ["3"] = { { version = "firered", fp = "5555555555555555" } } } } }))
  -- pokefirered/include/constants/pokemon.h:6
  relay:handle(leaf, Protocol2.presence({ board = { species = 152, level = 5, wantType = 13 } }))

  local ax, ay = RoomMap.ATTENDANT.x, RoomMap.ATTENDANT.y
  world:warpToMapId(RoomMap.ID, ax, ay + 1, "up")
  ok(waitFor(function()
    local s = Presence.active()
    return s and s.state == "joined" and #s:entities() == 1
  end, 1200), "the room connects with LEAF in it")
  local s = Presence.active()
  if not s then return finish() end
  until_(function() return calm() and s.ui == nil end, "b", 60)
  local nurse = world:npcAt(ax, ay)
  ok(nurse and nurse.def and nurse.def.sprite == "SPRITE_NURSE", "the nurse stands at FRLG's attendant cell")
  shot("02_room_nurse")

  tap("a")
  ok(until_(function() local t = top() return t and t.header and #t.items == 3 end, "a", 120),
     "the nurse offers REGISTER / INFO / EXIT")
  shot("03_register_menu")
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.gen2.PartyMenu") end, "a", 60), "the party menu opens")
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.gen2.union.List") end, "a", 60), "the type list opens")
  shot("04_type_list")
  tap("a")
  ok(until_(shows("completed"), "a", 60), "registration completes")
  local posted = s.boardEntry and s.boardEntry.board
  ok(posted and posted.species == 155 and posted.wantType == 0, "CYNDAQUIL is posted wanting NORMAL")
  until_(function() return calm() and s.ui == nil end, "a", 60)

  world:warpToMapId(RoomMap.ID, RoomMap.BOARD.x, RoomMap.BOARD.y + 1, "up")
  step(20)
  until_(function() return calm() and s.ui == nil end, "b", 30)
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.gen2.union.List") end, "a", 60), "the trading board opens")
  local list = top()
  ok(list and list.items and #list.items == 2 and tostring(list.items[1].label):find("CHIKORITA", 1, true) ~= nil,
     "LEAF's CHIKORITA is on the board")
  shot("05_board_list")
  tap("a")
  ok(until_(function() return getmetatable(top()) == require("src.ui.ChoiceBox") end, "a", 60)
     and shows("make a trade")(), "MAREEP fits LEAF's ELECTRIC request, so the trade is asked")
  shot("06_ask_trade")
  tap("a")
  local inv
  ok(waitFor(function()
    for _, i in pairs(relay.invites) do if i.to == "00000004" then inv = i end end
    return inv ~= nil
  end, 240), "an invite reaches LEAF")
  ok(inv and inv.activity == "xg_trade", "as a cross-gen trade")
  tap("b")
  until_(function() return calm() and s.ui == nil end, "a", 120)
  Caps.gameplayMods = liveMods
  finish()
end
