-- The Battle Tower trainer's three lines, driven in a real game: the greeting
-- maps/BattleTowerBattleRoom.asm:31 prints before the battle, the quote
-- WinTrainerBattle's .battle_tower arm prints after a win
-- (engine/battle/core.asm:2401-2407) and the one LostBattle's prints after a
-- loss (:2943-2952).
--
--   tools/run_driver.sh crystal <identity> tests/drivers/crystal_tower_quote_2862.lua <shotdir>
local U = require("tests.drivers.util")

local BattleTower = require("src.core.gen2.BattleTower")
local BattleTowerText = require("src.script.gen2.BattleTowerText")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-tower-quote"
  local fails, shots = 0, 0

  local function say(line) print("[driver] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end
  local function still(name)
    shots = shots + 1
    U.still(game, ("%s/2862_%02d_%s.png"):format(out, shots, name))
  end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end
  local function plain(text)
    return type(text) == "string" and (text:gsub("\012?{DONE}$", "")) or text
  end
  local function firstLine(text)
    return plain(text):match("^[^\n\012]*")
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")

  local roster = BattleTower.roster(game.data)
  ok(roster ~= nil and roster.text ~= nil,
    "trainers.lua carries the Battle Tower text block")
  if roster and roster.text then
    say(("text: genderByName=%s male %d/%d female %d/%d"):format(
      tostring(roster.text.genderByName), #roster.text.male.intro,
      roster.text.male.count, #roster.text.female.intro,
      roster.text.female.count))
  end

  local function setParty(level, strongMove)
    local party = {}
    for _, row in ipairs({ { "TYPHLOSION", "FLAMETHROWER" },
        { "FERALIGATR", "SURF", "BERRY" },
        { "MEGANIUM", "BODY_SLAM", "GOLD_BERRY" } }) do
      local moveId = strongMove and row[2] or "TACKLE"
      local def = game.data.moves[moveId]
      local mon = Mon.new(game.data, row[1], level, {
        moves = { { id = moveId, pp = def.pp, maxPp = def.pp } },
      })
      mon.item = row[3]
      party[#party + 1] = mon
    end
    game.save.party = party
  end
  setParty(60, true)

  local tower = BattleTower.state(game.save)
  tower.levelGroup = 1
  tower.streak = 0
  tower.trainers = {}
  tower.challenge = BattleTower.NO_CHALLENGE

  while game.stack:top() do game.stack:pop() end
  assert(world:setMap("BATTLE_TOWER_BATTLE_ROOM", 3, 7, "up"),
    "no BATTLE_TOWER_BATTLE_ROOM in the cache")
  U.wait(30)

  local function hardestMove(mon)
    local best, bestPower = 1, -1
    for index, move in ipairs((mon and mon.moves) or {}) do
      local def = game.data.moves and game.data.moves[move.id]
      local power = (def and def.power) or 0
      if (move.pp or 0) > 0 and power > bestPower then
        best, bestPower = index, power
      end
    end
    return best
  end
  local function refill(mon)
    for _, move in ipairs((mon and mon.moves) or {}) do
      move.pp = move.maxPp or move.pp
    end
  end

  -- One round of the room loop: the walk-in, the greeting, the battle, the
  -- quote.  `expectOutcome` is what the party fielded should produce.
  local function round(label, expectOutcome)
    local opponent, set = nil, nil
    local sawIntro, introPage = false, nil
    for _ = 1, 1200 do
      local vm = world.vm
      if vm and vm.btOpponent and not opponent then
        opponent = vm.btOpponent
        set = BattleTowerText.set(roster.text, roster.trainers[opponent.index + 1])
      end
      local body = world.lastText
      if set and type(body) == "string" and not sawIntro then
        for _, line in ipairs(set.intro) do
          if plain(body) == plain(line) then
            sawIntro, introPage = true, body
            U.wait(70)
            still(label .. "_intro_quote")
            break
          end
        end
      end
      if world.battleActive then break end
      if world.textbox or world.choicebox then tap("a", 4) else U.wait(2) end
    end
    ok(opponent ~= nil, label .. ": an opponent was drawn")
    ok(world.battleActive, label .. ": the battle screen came up")
    if not (opponent and world.battleActive) then return end

    local vm = world.vm
    local index = vm.btTextIndex
    local expected = {
      intro = BattleTowerText.pick(roster, opponent.index, BattleTowerText.INTRO, index),
      won = BattleTowerText.pick(roster, opponent.index, BattleTowerText.LOSS, index),
      lost = BattleTowerText.pick(roster, opponent.index, BattleTowerText.WIN, index),
    }
    say(("%s: opponent %s %s (row %d) text index %s"):format(label,
      tostring(opponent.classId), tostring(opponent.name), opponent.index,
      tostring(index)))
    say(label .. ": intro  " .. firstLine(expected.intro))
    say(label .. ": won    " .. firstLine(expected.won))
    say(label .. ": lost   " .. firstLine(expected.lost))
    ok(sawIntro and plain(introPage) == plain(expected.intro),
      label .. ": battletowertext INTRO printed the greeting the index names")

    U.wait(60)
    local screen = game.stack:top()
    local battle = screen and screen.battle
    ok(battle ~= nil and battle.inBattleTowerBattle == true,
      label .. ": the battle is a Tower battle")
    local want = expectOutcome == "win" and expected.won or expected.lost
    local sawQuote = false
    for _ = 1, 1500 do
      if not world.battleActive then break end
      local message = screen.message
      if want and type(message) == "string" and not sawQuote
          and plain(message):find(firstLine(want), 1, true) then
        sawQuote = true
        U.wait(80)
        still(label .. "_" .. expectOutcome .. "_quote")
      end
      if battle and battle.over then
        tap("a", 3)
      else
        local phase = screen.phase
        if phase == "menu" then
          if expectOutcome == "win" then refill(battle.player) end
          screen.menuIndex = 1
          tap("a", 4)
        elseif phase == "moves" then
          screen.menuIndex = hardestMove(battle.player)
          tap("a", 4)
        elseif phase == "submenu" then
          tap("down", 3)
          tap("a", 4)
        else
          tap("a", 3)
        end
      end
    end
    say(("%s: outcome=%s"):format(label, tostring(battle and battle.outcome)))
    ok(battle and battle.outcome == expectOutcome,
      label .. ": the battle ended in a " .. expectOutcome)
    ok(sawQuote, label .. ": the trainer's " .. expectOutcome
      .. " quote was printed on the battle screen")
    for _ = 1, 200 do
      if not world.battleActive then break end
      tap("a", 3)
    end
    ok(not world.battleActive, label .. ": the battle screen came down")
  end

  round("r1", "win")

  -- The receptionist's heal and the "next up" prompt run on their own; a
  -- hopeless party goes in for round two.
  setParty(2, false)
  round("r2", "lose")

  say(fails == 0 and "PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
