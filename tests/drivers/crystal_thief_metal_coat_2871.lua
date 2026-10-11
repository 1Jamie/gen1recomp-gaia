-- ../pokecrystal/engine/battle/core.asm:6009-6039 (.WildItem)
-- ../pokecrystal/engine/battle/move_effects/thief.asm
--
--   tools/run_driver.sh crystal <identity> tests/drivers/crystal_thief_metal_coat_2871.lua <shotdir>
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Screens = require("src.ui.Screens")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-thief-2871"
  os.execute("mkdir -p '" .. out .. "'")
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[thief-2871] " .. (cond and "PASS " or "FAIL ") .. msg)
    return cond
  end
  local function finish()
    print("[thief-2871] " .. (fails == 0 and "PASS all claims"
      or (fails .. " claims failed")) .. " -- shots in " .. out)
    love.event.quit(fails == 0 and 0 or 1)
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")
  local save, data = game.save, game.data

  local warped = false
  for _, spot in ipairs({ { 20, 9 }, { 21, 9 }, { 10, 9 }, { 30, 9 }, { 20, 5 } }) do
    if world:warpToMapId("ROUTE_38", spot[1], spot[2], "down") then
      warped = true
      break
    end
  end
  for _ = 1, 120 do
    if not world:busy() then break end
    U.wait(1)
  end
  U.wait(10)
  ok(warped and world.map.id == "ROUTE_38", "standing on ROUTE 38 ("
    .. tostring(world.map.id) .. ")")

  local lead = Mon.new(data, "SNEASEL", 40)
  assert(lead, "could not build a SNEASEL")
  assert(data.moves.THIEF, "no THIEF in the move table")
  lead.moves = { { id = "THIEF", pp = 10, maxPp = 10 } }
  lead.item = nil
  save.party = { lead }

  local draws = { 192, 19 }
  local i = 0
  local function roll() i = i + 1 return draws[math.min(i, #draws)] end
  local wild = Mon.new(data, "MAGNEMITE", 16, { wild = true, random = roll })
  assert(wild, "could not build a wild MAGNEMITE")
  ok(wild.item == "METAL_COAT", "the forced .WildItem roll gave METAL COAT ("
    .. tostring(wild.item) .. ")")
  ok(world:startBattle({ wild = wild }), "a wild battle starts")

  local screen
  for _ = 1, 600 do
    U.wait(1)
    local top = game.stack:top()
    if top and top.battle then screen = top break end
  end
  if not ok(screen ~= nil, "the battle screen is up") then return finish() end
  for _ = 1, 900 do
    if screen.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(2)
  end
  ok(screen.phase == "menu", "reached the battle menu")
  U.wait(10)
  U.still(game, out .. "/01_battle_menu.png")

  U.tap(game, "a")
  for _ = 1, 60 do
    if screen.phase == "moves" then break end
    U.wait(1)
  end
  ok(screen.phase == "moves", "FIGHT opened the move list")
  U.wait(5)
  U.still(game, out .. "/02_move_list.png")
  U.tap(game, "a")

  local sawStole = false
  for _ = 1, 1200 do
    if game.stack:top() ~= screen then break end
    local line = screen.message and tostring(screen.message) or ""
    if not sawStole and line:find("stole", 1, true) then
      sawStole = true
      U.wait(3)
      for _ = 1, 400 do
        if screen.typer and screen.typedText == screen.message
            and screen.typer:done() then break end
        U.wait(1)
      end
      U.still(game, out .. "/03_stole_text.png")
      ok(line:find("METAL COAT", 1, true) ~= nil,
        "StoleText names METAL COAT: " .. line:gsub("[\n\v\f]", " "))
      break
    end
    if (screen.messageTimer or 0) > 0 then U.tap(game, "a") end
    if screen.phase == "menu" then break end
    U.wait(1)
  end
  ok(sawStole, "the stole line was printed")
  ok(lead.item == "METAL_COAT", "the lead holds METAL COAT mid-battle")
  ok(screen.battle.enemy.item == nil, "the MAGNEMITE no longer holds it")

  for _ = 1, 900 do
    if game.stack:top() ~= screen then break end
    screen.battle.enemy.hp = 0
    U.tap(game, "a")
    U.wait(2)
  end
  for _ = 1, 300 do
    if game.stack:top() ~= screen then break end
    U.tap(game, "a")
    U.wait(2)
  end
  ok(game.stack:top() ~= screen, "the battle ended")
  U.wait(20)
  ok(save.party[1] == lead and save.party[1].item == "METAL_COAT",
    "the party mon still holds METAL COAT after the battle")

  Screens.push(game, "Gen2SummaryMenu", {
    party = save.party, index = 1,
    onClose = function() game.stack:pop() end,
  })
  U.wait(30)
  U.still(game, out .. "/04_summary_item.png")
  U.tap(game, "b")
  U.wait(10)
  finish()
end
