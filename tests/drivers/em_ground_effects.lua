local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_ground_effects")

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")
  local FieldEffects = require("src.core.game3.field_effects")
  local Objects = require("src.core.game3.objects")
  local MB = require("src.core.game3.mb")

  local function walkable(x, y) return Collision.inBounds(x, y) and Collision.isWalkable(x, y) end

  F.check(F.goTo(game, "EM_PETALBURG_CITY", 10, 10, "down"), "Petalburg City loads")
  local FxRse = FieldEffects.rse()
  F.check(FxRse ~= nil, "Emerald field effects run the RSE ground effects")
  local px, py = F.findCell(function(x, y)
    return walkable(x, y) and not Collision.isWater(x, y) and FxRse.B.reflective(Collision.behavior(x, y + 1))
  end, 0, 0, 40, 40)
  F.check(px ~= nil, "found a bank cell above Petalburg pond water (" .. tostring(px) .. "," .. tostring(py) .. ")")
  if px then
    F.goTo(game, "EM_PETALBURG_CITY", px, py, "down")
    U.wait(4)
    F.check(FxRse.reflectionType(px, py, px, py, 16, 32) == 2, "pond below the player gives a water reflection")
    F.shot(game, "01_petalburg_pond_reflection.png", true)
    F.check((FxRse.lastReflections or 0) >= 1, "reflection drawn (" .. tostring(FxRse.lastReflections) .. ")")
    local objects = FieldEffects.manifest()
    F.check(objects.paletteTags[FxRse.lastReflectionTag or -1] == "gObjectEventPal_BrendanReflection",
      "Brendan reflects with gObjectEventPal_BrendanReflection (" .. tostring(FxRse.lastReflectionTag) .. ")")
  end

  F.check(F.goTo(game, "EM_ROUTE109", 10, 20, "down"), "Route 109 loads")
  local function sandy(x, y)
    local b = Collision.behavior(x, y)
    return b == MB.id("SAND") or b == MB.id("FOOTPRINTS")
  end
  local sx, sy = F.findCell(function(x, y)
    return walkable(x, y) and walkable(x + 1, y) and walkable(x + 2, y) and sandy(x + 1, y)
  end, 0, 0, 80, 100)
  F.check(sx ~= nil, "found a sand run on the Route 109 beach (" .. tostring(sx) .. "," .. tostring(sy) .. ")")
  if sx then
    F.goTo(game, "EM_ROUTE109", sx, sy, "right")
    F.walk(game, "right")
    F.walk(game, "right")
    F.walk(game, "right")
    local tracks = 0
    for _, a in ipairs(FieldEffects._anims) do if a.kind == "tracks" then tracks = tracks + 1 end end
    F.check(tracks >= 1, "leaving sand leaves footprints (" .. tracks .. ")")
    F.shot(game, "02_route109_footprints.png", true)
  end

  F.check(F.goTo(game, "EM_ROUTE111", 20, 60, "down"), "Route 111 loads")
  local dx, dy = F.findCell(function(x, y)
    return walkable(x, y) and walkable(x + 1, y) and walkable(x + 2, y)
      and FxRse.B.deepSand(Collision.behavior(x + 1, y)) and FxRse.B.deepSand(Collision.behavior(x + 2, y))
  end, 0, 0, 60, 120)
  F.check(dx ~= nil, "found deep sand on Route 111 (" .. tostring(dx) .. "," .. tostring(dy) .. ")")
  if dx then
    F.goTo(game, "EM_ROUTE111", dx, dy, "right")
    F.walk(game, "right")
    F.walk(game, "right")
    U.wait(2)
    F.check(FxRse.count("sand_pile") >= 1, "walking through deep sand piles sand on the feet")
    F.shot(game, "03_route111_deep_sand_pile.png", true)
    F.walk(game, "right")
    local deep = 0
    for _, a in ipairs(FieldEffects._anims) do if a.kind == "tracks" and a.sheet == "deep_sand_footprints" then deep = deep + 1 end end
    F.check(deep >= 1, "deep sand leaves deep footprints (" .. deep .. ")")
  end

  F.check(F.goTo(game, "EM_ROUTE119", 10, 10, "down"), "Route 119 loads")
  local lx, ly = F.findCell(function(x, y)
    return walkable(x, y) and not Collision.isGrass(x, y) and Collision.behavior(x + 1, y) == MB.id("LONG_GRASS")
  end, 0, 0, 60, 140)
  F.check(lx ~= nil, "found long grass on Route 119 (" .. tostring(lx) .. "," .. tostring(ly) .. ")")
  if lx then
    F.goTo(game, "EM_ROUTE119", lx, ly, "right")
    U.hold(game, "right", 6)
    U.wait(4)
    F.check(FieldEffects._fx and FieldEffects._fx.sheet == "long_grass", "stepping into long grass rustles the long grass sprite")
    F.shot(game, "04_route119_long_grass.png", true)
    for _ = 1, 30 do U.wait(1) end
    F.settle(game)
  end

  F.check(F.goTo(game, "EM_ROUTE102", 10, 10, "down"), "Route 102 loads")
  local jx, jy = F.findCell(function(x, y)
    return walkable(x, y) and Collision.behavior(x, y + 1) == MB.id("JUMP_SOUTH") and walkable(x, y + 2)
      and not Collision.isGrass(x, y + 2)
  end, 0, 0, 60, 40)
  F.check(jx ~= nil, "found a south ledge on Route 102 (" .. tostring(jx) .. "," .. tostring(jy) .. ")")
  if jx then
    F.goTo(game, "EM_ROUTE102", jx, jy, "down")
    U.hold(game, "down", 10)
    F.check(Player.jumping == true, "the player hops the ledge")
    F.shot(game, "05_ledge_jump_shadow.png", true)
    local dust = false
    for _ = 1, 60 do
      for _, a in ipairs(FieldEffects._anims) do if a.kind == "dust" then dust = true end end
      if dust then break end
      U.wait(1)
    end
    F.check(dust, "landing on plain ground kicks up dust")
  end

  local npc
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.visible and not eo.hidden and not eo.invisible and not npc then npc = eo end
  end
  F.check(npc ~= nil, "an NPC is on Route 102")
  if npc then
    local lid = npc.localId
    F.goTo(game, "EM_ROUTE102", npc.cellX, npc.cellY + 2, "up")
    npc = Objects.find(lid)
    for _ = 1, 60 do
      if not npc.moving then break end
      U.wait(1)
    end
    npc.frozen = true
    local started = Objects.scriptJump(npc, npc.facing, 0)
    print(string.format("[driver] INFO npc lid=%s jump started=%s moving=%s arc=%s rse=%s", tostring(lid), tostring(started),
      tostring(npc.moving), tostring(npc.jumpArc ~= nil), tostring(Objects.isRse())))
    U.wait(6)
    F.check((npc.raiseY or 0) < 0 and npc.jumpArc ~= nil, "NPC jump in place arcs upward (" .. tostring(npc.raiseY) .. ")")
    F.shot(game, "06_npc_jump_in_place.png", true)
    U.wait(20)
    F.check(npc.jumpArc == nil and (npc.raiseY or 0) == 0, "NPC lands back on its cell")
    npc.frozen, npc.scriptBusy = false, false
  end

  F.finish()
end
