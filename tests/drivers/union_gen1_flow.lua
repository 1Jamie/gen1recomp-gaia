local U = require("tests.drivers.util")
local TextBox = require("src.render.TextBox")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local UnionCenters = require("src.world.gen1.UnionCenters")
local UnionRoomMap = require("src.world.gen1.UnionRoomMap")
local Origin = require("src.online.union.Origin")
local GameVersion = require("src.core.GameVersion")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
  end
  local v = GameVersion.get()
  local function shot(name)
    for _ = 1, 240 do
      local top = game.stack:top()
      if not (top and top.pages and not top.done) then break end
      U.wait(1)
    end
    U.wait(20)
    U.still(game, ("%s/%s_%s.png"):format(SHOT_DIR, v, name))
  end
  local function ow() return game.overworld end
  local function idle()
    local o = ow()
    return o and game.stack:top() == o and not o.transitioning
      and not o.runner:isRunning() and #o.scriptMoves == 0
      and not (o.pendingScripts and o.pendingScripts[1])
      and not o.healAnim and not o.emote
  end
  local function waitFor(cond, frames)
    for _ = 1, frames do
      if cond() then return true end
      U.wait(1)
    end
    return cond()
  end
  local function at()
    local p = ow().player
    return ow().map.id, p.cellX, p.cellY
  end
  local function boxText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local out = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do out[#out + 1] = type(line) == "table" and table.concat(line) or tostring(line) end
    end
    return table.concat(out, " ")
  end
  local function mash(btn, cond, frames)
    for _ = 1, frames do
      if cond() then return true end
      U.tap(game, btn)
      U.wait(3)
    end
    return cond()
  end
  local function settle()
    for _ = 1, 300 do
      if idle() then return true end
      local top = game.stack:top()
      U.tap(game, (top and top.choice) and "b" or "a")
      U.wait(3)
      if not idle() then U.tap(game, "b") U.wait(3) end
    end
    U.wait(30)
    return idle()
  end
  local function home(town)
    game.save.lastOutdoor = { id = town, x = 10, y = 10 }
  end

  U.wait(10)
  game.save.flags.EVENT_GOT_POKEDEX = true
  require("src.online.union.Caps").gameplayMods = function() return false end
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 5), Pokemon.new(game.data, "RATTATA", 5) }

  home("VIRIDIAN_CITY")
  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  U.tap(game, "a")
  ok(waitFor(function() return not idle() end, 120), "PC at 13,3 opens")
  shot("flow_01_pc_open")
  mash("b", idle, 400)

  local m1 = ow().map
  ok(not m1:isWalkableCell(10, 1) and not m1:isWalkableCell(10, 2), "pillar and cap seal the nurse side")
  ok(m1:isWalkableCell(11, 1) and m1:isWalkableCell(11, 2) and m1:isWalkableCell(12, 1), "stairs alcove is walkable")
  ok(not m1:isWalkableCell(13, 3), "PC cell stays solid")
  U.teleport(game, "VIRIDIAN_POKECENTER", 11, 1, "left")
  U.hold(game, "left", 30)
  waitFor(idle, 60)
  local _, cx, cy = at()
  ok(cx == 11 and cy == 1, ("walking left from 11,1 is blocked (%d,%d)"):format(cx, cy))

  home("VIRIDIAN_CITY")
  U.teleport(game, "VIRIDIAN_POKECENTER", 3, 3, "up")
  game.save.party[1].hp = 1
  U.tap(game, "a")
  ok(waitFor(function() return not idle() end, 120), "nurse responds on the patched 1F")
  mash("a", idle, 600)
  ok(game.save.party[1].hp == game.save.party[1].stats.hp, "nurse healed the party")
  U.wait(30)

  local function talkAll(mapId, town)
    home(town)
    U.teleport(game, mapId, 4, 4, "down")
    local list = {}
    for _, n in ipairs(ow().npcs) do list[#list + 1] = n.def end
    table.sort(list, function(p, q)
      local pn, qn = p.sprite == "SPRITE_NURSE", q.sprite == "SPRITE_NURSE"
      if pn ~= qn then return qn end
      return p.index < q.index
    end)
    for _, d in ipairs(list) do
      if d.sprite == "SPRITE_CHANSEY" then
        print(("SKIP %s: %s is silent on the vanilla layout too"):format(mapId, d.name))
        goto continue
      end
      U.teleport(game, mapId, 4, 4, "down")
      local npc = ow():npcByIndex(d.index)
      local spot
      if npc then
        npc.frozen = true
        local map = ow().map
        for pass = 1, 2 do
          for _, dir in ipairs({ { 0, 1, "up" }, { 1, 0, "left" }, { -1, 0, "right" }, { 0, -1, "down" } }) do
            for dist = 1, 2 do
              local x, y = npc.cellX + dir[1] * dist, npc.cellY + dir[2] * dist
              if dist == 2 and not map:isCounterCell(npc.cellX + dir[1], npc.cellY + dir[2]) then break end
              if map:inBounds(x, y) and map:isWalkableCell(x, y)
                 and (pass == 2 or not ow():npcAtCell(x, y)) then
                spot = { x, y, dir[3] }
                break
              end
            end
            if spot then break end
          end
          if spot then break end
        end
      end
      if spot then
        U.teleport(game, mapId, spot[1], spot[2], spot[3])
        npc = ow():npcByIndex(d.index)
        if npc then npc.frozen = true end
        U.tap(game, "a")
        local talked = waitFor(function() return not idle() end, 120)
        ok(talked, ("%s: %s answers from %d,%d"):format(mapId, d.name, spot[1], spot[2]))
        settle()
      else
        ok(false, ("%s: %s has no reachable talk cell"):format(mapId, d.name))
      end
      ::continue::
    end
  end
  talkAll("VIRIDIAN_POKECENTER", "VIRIDIAN_CITY")
  talkAll("MT_MOON_POKECENTER", "ROUTE_4")
  talkAll("INDIGO_PLATEAU_LOBBY", "INDIGO_PLATEAU")
  for _, id in ipairs({ "VIRIDIAN_POKECENTER", "MT_MOON_POKECENTER", "INDIGO_PLATEAU_LOBBY" }) do
    local has = false
    for _, o in ipairs(game.data.maps[id].objects) do
      if o.sprite == "SPRITE_LINK_RECEPTIONIST" then has = true end
    end
    ok(not has, id .. ": cable club receptionist moved off 1F")
  end

  home("ROUTE_4")
  U.teleport(game, "MT_MOON_POKECENTER", 13, 2, "up")
  U.hold(game, "up", 20)
  ok(waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F and idle() end, 900), "Mt Moon stairs reach 2F")
  ok((Origin.get(game.save) or {}).map == "MT_MOON_POKECENTER", "origin is Mt Moon")
  shot("flow_02_2f_arrival")

  game.save.flags.EVENT_GOT_POKEDEX = nil
  U.teleport(game, UnionCenters.FLOOR_2F, 11, 3, "up")
  U.tap(game, "a")
  ok(waitFor(function() return (boxText() or ""):find("preparations", 1, true) end, 300),
     "cable club without POKeDEX: " .. tostring(boxText()))
  settle()
  game.save.flags.EVENT_GOT_POKEDEX = true
  U.teleport(game, UnionCenters.FLOOR_2F, 11, 3, "up")
  U.tap(game, "a")
  ok(waitFor(function() return (boxText() or ""):find("Cable Club", 1, true) end, 300),
     "cable club receptionist greets on 2F: " .. tostring(boxText()))
  shot("flow_03_cable_club")
  local LinkState = require("src.link.LinkState")
  local linked = mash("a", function()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == LinkState then return true end
    end
    return false
  end, 300)
  ok(linked, "cable club still opens LinkState")
  shot("flow_04_linkstate")
  while game.stack:top() and game.stack:top() ~= ow() do game.stack:pop() end
  game.linkSession = nil
  ok(waitFor(idle, 60), "back on the 2F after the link menu")

  game.save.flags.EVENT_GOT_POKEDEX = nil
  U.teleport(game, UnionCenters.FLOOR_2F, 7, 3, "up")
  U.tap(game, "a")
  ok(waitFor(function() return (boxText() or ""):find("preparations", 1, true) end, 300),
     "union receptionist without POKeDEX: " .. tostring(boxText()))
  settle()
  game.save.flags.EVENT_GOT_POKEDEX = true

  U.teleport(game, UnionCenters.FLOOR_2F, 7, 3, "up")
  U.tap(game, "a")
  ok(waitFor(function() return (boxText() or ""):find("UNION", 1, true) end, 300),
     "union receptionist greets: " .. tostring(boxText()))
  local ChoiceBox = require("src.ui.ChoiceBox")
  ok(mash("a", function() return getmetatable(game.stack:top()) == ChoiceBox end, 200), "YES/NO opens")
  shot("flow_05_union_welcome")
  U.tap(game, "b")
  ok(waitFor(function() return (boxText() or ""):find("come again", 1, true) end, 300),
     "declining says please come again: " .. tostring(boxText()))
  settle()
  U.teleport(game, UnionCenters.FLOOR_2F, 7, 3, "up")
  U.tap(game, "a")
  ok(waitFor(function() return (boxText() or ""):find("UNION", 1, true) end, 300), "greeting again")
  ok(mash("a", function() return (boxText() or ""):find("SAVE", 1, true) end, 300), "asks to save: " .. tostring(boxText()))
  ok(mash("a", function() return ow().map.id == UnionCenters.UNION_ROOM end, 900), "walked into the union room")
  ok(waitFor(idle, 600), "union room idle after the warp")
  local m, x, y = at()
  local ex, ey = UnionRoomMap.entry()
  ok(m == UnionCenters.UNION_ROOM and x == ex and y == ey, ("entered at the exit carpet (%d,%d)"):format(x, y))
  ok((Origin.get(game.save) or {}).map == "MT_MOON_POKECENTER", "origin kept inside the room")
  shot("flow_06_union_room")
  local slotsOk = true
  for slot = 1, UnionRoomMap.CAP do
    local sx, sy = UnionRoomMap.cellFor(slot)
    if not (sx and ow().map:isWalkableCell(sx, sy)) then slotsOk = false end
  end
  ok(slotsOk, "all 40 participant cells are walkable in the room")

  local function nurseFront(raw, label)
    local rp = raw and raw.player or {}
    ok(rp.map == "MT_MOON_POKECENTER" and rp.x == 3 and rp.y == 3 and rp.facing == "up",
       ("%s: written save stands in front of the Mt Moon nurse (%s %s,%s %s)"):format(label,
         tostring(rp.map), tostring(rp.x), tostring(rp.y), tostring(rp.facing)))
    ok(raw and Origin.get(raw) == nil, label .. ": written save carries no origin")
    ok(raw and raw.lastOutdoor and raw.lastOutdoor.id == "ROUTE_4", label .. ": written lastOutdoor is the center's town")
  end
  U.hold(game, "up", 20)
  waitFor(idle, 120)
  local _, rx, ry = at()
  ok(game:writeSave(), "save written inside the room")
  m, x, y = at()
  ok(m == UnionCenters.UNION_ROOM and x == rx and y == ry, "saving does not move the live player")
  ok((Origin.get(game.save) or {}).map == "MT_MOON_POKECENTER", "live origin kept after saving")
  nurseFront(SaveData.load(), "room save")

  U.teleport(game, UnionCenters.UNION_ROOM, ex, ey, "down")
  U.hold(game, "down", 30)
  ok(waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F end, 600), "exit carpet leads to 2F")
  ok(waitFor(function() return (boxText() or ""):find("come again", 1, true) end, 600),
     "receptionist sees the player off: " .. tostring(boxText()))
  shot("flow_07_seen_off")
  mash("a", idle, 400)
  m, x, y = at()
  ok(m == UnionCenters.FLOOR_2F and x == 6 and y == 4, ("walked out to %s %d,%d"):format(m, x, y))
  local closed = UnionCenters.forData(game.data).gateClosed
  ok(ow().map:blockAt(UnionCenters.GATE_2F.bx, UnionCenters.GATE_2F.by) == closed, "gate closed again")
  ok(not ow().map:isWalkableCell(6, 2), "gate cell is solid after closing")
  U.teleport(game, UnionCenters.FLOOR_2F, 6, 3, "up")
  U.hold(game, "up", 30)
  waitFor(idle, 60)
  _, x, y = at()
  ok(x == 6 and y == 3, ("walking up into the closed gate is blocked (%d,%d)"):format(x, y))

  ok(game:writeSave(), "save written on 2F")
  ok(ow().map.id == UnionCenters.FLOOR_2F, "live player still on 2F after saving")
  local raw2 = SaveData.load()
  nurseFront(raw2, "2F save")
  game:restoreSave(raw2, nil, { freshBoot = true, continued = true })
  U.wait(10)
  m, x, y = at()
  ok(m == "MT_MOON_POKECENTER" and x == 3 and y == 3, ("reloaded in front of the nurse (%s %d,%d)"):format(m, x, y))
  shot("flow_08_reload_nurse_front")

  home("ROUTE_4")
  U.teleport(game, "MT_MOON_POKECENTER", 13, 2, "up")
  U.hold(game, "up", 20)
  waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F and idle() end, 900)
  ow():captureSave(game.save)
  SaveData.save(game.save)
  local legacy = SaveData.load()
  ok(legacy.player.map == UnionCenters.FLOOR_2F, "raw 2F save on disk")
  game:restoreSave(legacy, nil, { freshBoot = true, continued = true })
  U.wait(10)
  m, x, y = at()
  ok(m == "MT_MOON_POKECENTER" and x == 3 and y == 3, ("load-time net moves a raw 2F save to the nurse (%s %d,%d)"):format(m, x, y))
  ok(Origin.get(game.save) == nil, "load-time net clears the origin")

  U.teleport(game, "MT_MOON_POKECENTER", 13, 2, "up")
  U.hold(game, "up", 20)
  waitFor(function() return ow().map.id == UnionCenters.FLOOR_2F and idle() end, 900)
  ow():captureSave(game.save)
  SaveData.save(game.save)
  ok((Origin.get(SaveData.load()) or {}).map == "MT_MOON_POKECENTER", "raw save left on 2F with origin Mt Moon")

  print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
