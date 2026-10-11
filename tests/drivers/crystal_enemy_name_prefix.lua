-- ../pokecrystal/home/text.asm:322-345 (PlaceBattlersName)
-- ../pokecrystal/data/text/battle.asm:10-15, :162-167
--
--   tools/run_driver.sh crystal <identity> tests/drivers/crystal_enemy_name_prefix.lua <shotdir>
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Trainers = require("src.world.gen2.Trainers")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-enemy-prefix"
  os.execute("mkdir -p '" .. out .. "'")
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[enemy-prefix] " .. (cond and "PASS " or "FAIL ") .. msg)
    return cond
  end
  local function finish()
    print("[enemy-prefix] " .. (fails == 0 and "PASS all claims"
      or (fails .. " claims failed")) .. " -- shots in " .. out)
    love.event.quit(fails == 0 and 0 or 1)
  end
  local function flat(s) return (tostring(s or ""):gsub("[\n\v\f]", "|")) end

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
  ok(warped and world.map.id == "ROUTE_38", "standing on ROUTE 38")

  local function waitScreen()
    for _ = 1, 600 do
      U.wait(1)
      local top = game.stack:top()
      if top and top.battle then return top end
    end
    return nil
  end

  local function settle(screen)
    U.wait(3)
    for _ = 1, 400 do
      if screen.typer and screen.typedText == screen.message
          and screen.typer:done() then break end
      U.wait(1)
    end
  end

  -- Runs the battle until every wanted line has been seen (or the screen
  -- closes), snapping each one as it finishes typing.
  local function watch(screen, wants, prefix, budget)
    local seen = {}
    local turns = 0
    for _ = 1, budget or 3000 do
      if game.stack:top() ~= screen then break end
      local line = screen.message and tostring(screen.message) or ""
      for key, want in pairs(wants) do
        if not seen[key] and line:find(want.pattern) then
          seen[key] = line
          settle(screen)
          U.still(game, out .. "/" .. prefix .. "_" .. key .. ".png")
        end
      end
      local done = true
      for key in pairs(wants) do if not seen[key] then done = false end end
      if done then break end
      if screen.phase == "menu" then
        turns = turns + 1
        if turns > 12 then break end
        U.tap(game, "a")
        U.wait(3)
        if screen.phase == "moves" then U.tap(game, "a") end
      elseif (screen.messageTimer or 0) > 0 or screen.phase == "resolving" then
        U.tap(game, "a")
      else
        U.tap(game, "a")
      end
      U.wait(1)
    end
    return seen
  end

  -- ---- wild: a GROWL spammer against a wild TACKLE user ------------------
  local lead = Mon.new(data, "MILTANK", 30)
  assert(lead, "could not build a MILTANK")
  assert(data.moves.GROWL and data.moves.TACKLE, "GROWL / TACKLE missing")
  lead.moves = { { id = "GROWL", pp = 40, maxPp = 40 } }
  lead.item = nil
  save.party = { lead }

  local wild = Mon.new(data, "PIDGEY", 12)
  assert(wild, "could not build a wild PIDGEY")
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.item = nil
  ok(world:startBattle({ wild = wild }), "a wild battle starts")
  local screen = waitScreen()
  if not ok(screen ~= nil, "the wild battle screen is up") then return finish() end

  local seen = watch(screen, {
    ["01_wild_appeared"] = { pattern = "^Wild PIDGEY" },
    ["02_enemy_used"] = { pattern = "^Enemy PIDGEY\nused TACKLE!" },
    ["03_enemy_stat_fell"] = { pattern = "^Enemy PIDGEY's ATTACK" },
  }, "wild")
  ok(seen["01_wild_appeared"] ~= nil, "WildPokemonAppearedText is bare: "
    .. flat(seen["01_wild_appeared"]))
  ok(seen["02_enemy_used"] ~= nil, "the foe's used-move line opens on Enemy: "
    .. flat(seen["02_enemy_used"]))
  ok(seen["03_enemy_stat_fell"] ~= nil, "the foe's stat line opens on Enemy: "
    .. flat(seen["03_enemy_stat_fell"]))
  ok(seen["02_enemy_used"] == nil
    or not tostring(seen["02_enemy_used"]):find("Wild", 1, true),
    "and never says Wild")

  -- Finish the wild fight on the faint line.
  local faintSeen
  for _ = 1, 900 do
    if game.stack:top() ~= screen then break end
    local line = screen.message and tostring(screen.message) or ""
    if not faintSeen and line:find("fainted!", 1, true) then
      faintSeen = line
      settle(screen)
      U.still(game, out .. "/wild_04_enemy_fainted.png")
    end
    if screen.phase == "menu" then screen.battle.enemy.hp = 0 end
    U.tap(game, "a")
    U.wait(2)
  end
  ok(faintSeen ~= nil and faintSeen:find("^Enemy PIDGEY") ~= nil,
    "BattleText_EnemyMonFainted: " .. flat(faintSeen))
  ok(game.stack:top() ~= screen, "the wild battle ended")
  U.wait(20)

  -- ---- trainer: the same lines through a YOUNGSTER --------------------------
  local classes = data.trainers and data.trainers.classes or {}
  local youngster
  for id, class in pairs(classes) do
    if id == "YOUNGSTER" and type(class) == "table" then youngster = class end
  end
  local record = youngster and Trainers.lookup(data.trainers, youngster.index, 1)
  if not ok(record ~= nil, "YOUNGSTER #1 resolves from the trainer table") then
    return finish()
  end
  lead.hp = lead.maxHp or lead.hp
  save.party = { lead }
  ok(world:startScriptedBattle(record, nil, function() end), "a trainer battle starts")
  screen = waitScreen()
  if not ok(screen ~= nil, "the trainer battle screen is up") then return finish() end
  local foeName = screen.battle and screen.battle.enemy
    and screen.battle:monName(screen.battle.enemy) or "?"
  local foeDisplay = record.className .. " " .. record.name

  seen = watch(screen, {
    ["01_sent_out"] = { pattern = "^" .. foeDisplay:gsub("%p", "%%%0") .. "\nsent out" },
    ["02_enemy_used"] = { pattern = "^Enemy " .. foeName:gsub("%p", "%%%0") .. "\nused " },
  }, "trainer")
  ok(seen["01_sent_out"] ~= nil, "BattleText_EnemySentOut names the mon bare: "
    .. flat(seen["01_sent_out"]))
  ok(seen["02_enemy_used"] ~= nil, "the trainer's mon opens on Enemy: "
    .. flat(seen["02_enemy_used"]))

  for _ = 1, 1500 do
    if game.stack:top() ~= screen then break end
    if screen.phase == "menu" then
      for _, m in ipairs(screen.battle.enemyParty or {}) do m.hp = 0 end
      screen.battle.enemy.hp = 0
    end
    U.tap(game, "a")
    U.wait(2)
  end
  ok(game.stack:top() ~= screen, "the trainer battle ended")
  finish()
end
