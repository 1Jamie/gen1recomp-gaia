local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_wild_encounters"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_wild_encounters failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Field = require("src.core.game3.field")
  local FieldMoves = require("src.core.game3.field_moves")
  local Encounters = require("src.core.game3.encounters")
  local Battle = require("src.core.game3.battle")
  local Bag = require("src.core.game3.bag")
  local MB = require("src.core.game3.mb")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local IDS = Flags.forVersion("emerald").IDS
  local function mv(n) return C.moves.byName["MOVE_" .. n] end
  local function sp(n) return C.species.byName["SPECIES_" .. n] end
  local function item(n) return C.items.byName["ITEM_" .. n] end

  session.party = {}
  Party.giveMon(session, sp("SWAMPERT"), 100, "SWAMPERT")
  session.party[1].moves = { mv("SURF"), mv("ROCK_SMASH"), mv("STRENGTH"), mv("EARTHQUAKE") }
  for i = 1, 8 do Flags.setFlag(Space.store, nil, IDS[string.format("FLAG_BADGE0%d_GET", i)], true) end
  Bag.add(session.bag, item("OLD_ROD"), 1)

  local function idle()
    return not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() and not Field.locked
      and not Warp.isBusy() and not (Choice.isOpen and Choice.isOpen())
      and not require("src.core.game3.field_move_show_mon").isActive() and not Battle.isActive()
  end

  local function pump(pred, frames)
    for _ = 1, frames or 600 do
      if pred() then return true end
      if Battle.isActive() then return pred() end
      if (Choice.isOpen and Choice.isOpen()) or Message._choice then
        U.tap(game, "a")
      elseif Message.isOpen and Message.isOpen() then
        U.tap(game, "a")
        U.wait(3)
      else
        U.wait(1)
      end
    end
    return pred()
  end

  local function place(mapId, x, y, facing, surfing)
    for _ = 1, 300 do if idle() then break end U.wait(1) end
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Player.surfing = surfing == true
    Field.unlock()
    U.wait(20)
  end

  local function size()
    local layout = Collision._mapDef and Collision._mapDef.midLayout
    return layout and layout.width or 0, layout and layout.height or 0
  end

  local function inTable(mapId, kind, species)
    local t = Encounters.tableFor(mapId)
    local area = t and t[kind]
    for _, s in ipairs(area and area.slots or {}) do
      if tonumber(s.species) == tonumber(species) then return true end
    end
    return false
  end

  local function enemySpecies()
    local st = Battle._st
    local mon = st and st.enemy and st.enemy.mon
    return mon and tonumber(mon.species)
  end

  local function winBattle()
    for _ = 1, 600 do if Battle._phase == "command" or not Battle.isActive() then break end U.wait(2) end
    L.run(game, { turnCap = 20 })
    for _ = 1, 900 do
      if not Battle.isActive() and idle() then return true end
      if Message.isOpen() then U.tap(game, "a") end
      U.wait(2)
    end
    return not Battle.isActive()
  end

  local function walkUntilBattle(a, b, steps)
    for i = 1, steps do
      U.hold(game, (i % 2 == 1) and a or b, 12)
      for _ = 1, 20 do
        if Battle.isActive() then return true end
        U.wait(1)
      end
    end
    return Battle.isActive()
  end

  -- pokeemerald/src/wild_encounter.c:552
  place("EM_ROUTE101", 10, 10, "down")
  local gx, gy
  local w, h = size()
  for y = 1, h - 2 do
    for x = 1, w - 2 do
      if not gx and Collision.behavior(x, y) == MB.id("TALL_GRASS") and Collision.behavior(x + 1, y) == MB.id("TALL_GRASS")
          and Collision.isWalkable(x, y) and Collision.isWalkable(x + 1, y) then
        gx, gy = x, y
      end
    end
  end
  check(gx ~= nil, "Route 101 has a pair of tall grass cells (" .. tostring(gx) .. "," .. tostring(gy) .. ")")
  if gx then
    place("EM_ROUTE101", gx, gy, "right")
    local got = walkUntilBattle("right", "left", 200)
    check(got, "walking in Route 101 grass starts a wild battle")
    if got then
      U.wait(90)
      U.shot(game, DIR .. "/01_grass_battle.png")
      local s = enemySpecies()
      check(s and inTable("EM_ROUTE101", "land", s), "the grass mon comes from the Route 101 land table (" .. tostring(s) .. ")")
      check(winBattle(), "the grass battle ends")
    end
  end

  -- pokeemerald/src/wild_encounter.c:599
  place("EM_ROUTE103", 10, 10, "down")
  local sx, sy
  w, h = size()
  for y = 1, h - 2 do
    for x = 1, w - 2 do
      if not sx and Collision.isWater(x, y) and Collision.isWater(x + 1, y) and Collision.isSurfable(Collision.behavior(x, y))
          and Collision.isSurfable(Collision.behavior(x + 1, y)) then
        sx, sy = x, y
      end
    end
  end
  check(sx ~= nil, "Route 103 has open water (" .. tostring(sx) .. "," .. tostring(sy) .. ")")
  if sx then
    place("EM_ROUTE103", sx, sy, "right", true)
    local got = walkUntilBattle("right", "left", 300)
    check(got, "surfing on Route 103 starts a wild battle")
    if got then
      U.wait(90)
      U.shot(game, DIR .. "/02_surf_battle.png")
      local s = enemySpecies()
      check(s and inTable("EM_ROUTE103", "water", s), "the surf mon comes from the Route 103 water table (" .. tostring(s) .. ")")
      check(winBattle(), "the surf battle ends")
    end
  end

  -- pokeemerald/src/wild_encounter.c:446
  local rocks = 0
  local rockSpecies
  for attempt = 1, 25 do
    place("EM_ROUTE111", 10, 10, "down")
    local cleared = false
    for _, eo in pairs(Objects._byId) do
      local gfx = eo.def and (eo.def.graphicsId or eo.def.gfx)
      local f = eo.def and tonumber(eo.def.flag or eo.def.flagId)
      if gfx == FieldMoves.GFX_IDS.ROCK_SMASH_ROCK and f and f ~= 0 and Flags.getFlag(Space.store, nil, f) then
        Flags.setFlag(Space.store, nil, f, false)
        cleared = true
      end
    end
    if cleared then place("EM_ROUTE111", 10, 10, "down") end
    local rock
    for _, eo in pairs(Objects._byId) do
      local gfx = eo.def and (eo.def.graphicsId or eo.def.gfx)
      if not rock and gfx == FieldMoves.GFX_IDS.ROCK_SMASH_ROCK and not eo.hidden then rock = eo end
    end
    if not rock then break end
    local rx, ry = rock.cellX, rock.cellY
    local stand
    for _, d in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      if not stand and Collision.isWalkable(rx + d[1], ry + d[2]) then stand = d end
    end
    if not stand then break end
    place("EM_ROUTE111", rx + stand[1], ry + stand[2], stand[3])
    U.tap(game, "a")
    pump(function() return Battle.isActive() or idle() end, 900)
    rocks = rocks + 1
    for _ = 1, 60 do if Battle.isActive() then break end U.wait(1) end
    if Battle.isActive() then
      U.wait(90)
      U.shot(game, DIR .. "/03_rock_smash_battle.png")
      rockSpecies = enemySpecies()
      winBattle()
      break
    end
  end
  check(rockSpecies ~= nil, "ROCK SMASH on a Route 111 rock started a wild battle (" .. rocks .. " rocks)")
  check(rockSpecies and inTable("EM_ROUTE111", "rocks", rockSpecies),
    "the rock mon comes from the Route 111 rock smash table (" .. tostring(rockSpecies) .. ")")

  -- pokeemerald/src/wild_encounter.c:113
  place("EM_ROUTE119", 17, 30, "up")
  local rules = Encounters.rules()
  local fx, fy
  w, h = size()
  for y = 2, h - 2 do
    for x = 2, w - 2 do
      if not fx and Collision.isWater(x, y) and Collision.isSurfable(Collision.behavior(x, y))
          and Collision.isWater(x, y + 1) and Collision.isSurfable(Collision.behavior(x, y + 1)) then
        for _ = 1, 8 do
          if rules.checkFeebas("EM_ROUTE119", { x = x, y = y }) then fx, fy = x, y break end
        end
      end
    end
  end
  check(fx ~= nil, "a Feebas tile exists on Route 119 for this save's trend seed (" .. tostring(fx) .. "," .. tostring(fy) .. ")")
  local fished, feebas, other = 0, false, {}
  if fx then
    session.registeredItem = item("OLD_ROD")
    for _ = 1, 40 do
      place("EM_ROUTE119", fx, fy + 1, "up", true)
      U.tap(game, "select")
      fished = fished + 1
      for _ = 1, 900 do
        if Battle.isActive() then break end
        if idle() and not Field.isFishing() then break end
        if Message.isOpen() then U.tap(game, "a") end
        U.wait(2)
      end
      if Battle.isActive() then
        U.wait(90)
        local s = enemySpecies()
        if s == sp("FEEBAS") then
          feebas = true
          U.shot(game, DIR .. "/04_feebas.png")
        else
          other[#other + 1] = s
        end
        winBattle()
        if feebas then break end
      end
    end
  end
  check(#other > 0 or feebas, "fishing with the OLD ROD hooks wild mons (" .. fished .. " casts)")
  local otherOk = true
  for _, s in ipairs(other) do if not inTable("EM_ROUTE119", "fishing", s) then otherOk = false end end
  check(otherOk, "non-Feebas bites come from the Route 119 fishing table")
  check(feebas, "fishing the Feebas tile hooks a FEEBAS (" .. fished .. " casts)")

  local st = Space.store
  local wilds = Flags.getVar(st, nil, C:require("vars", "VAR_DAILY_WILDS"))
  check((tonumber(wilds) or 0) >= 3, "IncrementDailyWildBattles counted the wild battles (" .. tostring(wilds) .. ")")
  finish()
end
