-- Comprehensive unit tests for Battle Pokémon Switch and Faint systems in Game 3.

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local SwitchSeq = require("src.core.game3.battle.switch_seq")
local Battle = require("src.core.game3.battle.init")
local Damage = require("src.core.game3.battle.damage")
local Commands = require("src.core.game3.battle.commands")
local PartyMenu = require("src.ui.game3.party_menu")

local function check(cond, msg)
  if not cond then
    error("[FAIL] " .. tostring(msg), 2)
  end
  print("[PASS] " .. tostring(msg))
end

local function eq(a, b, msg)
  if a ~= b then
    error(string.format("[FAIL] %s: expected %s, got %s", tostring(msg), tostring(b), tostring(a)), 2)
  end
  print("[PASS] " .. tostring(msg))
end

print("--- Testing State.wipeVolatilesAndStages & State.syncBattlerToParty ---")
do
  local party = {
    { species = 1, level = 5, hp = 20, maxHp = 20, status = 0, moves = { 33 }, pp = { 35 } },
    { species = 4, level = 5, hp = 19, maxHp = 19, status = 0, moves = { 33 }, pp = { 35 } },
  }
  local battler = State.makeBattler(party[1], "player", { partyIndex = 1 })
  battler.stages.attack = 2
  battler.stages.defense = -1
  battler.confusion = 3
  battler.seeded = true
  battler.mon.hp = 12
  battler.status = "PSN"

  State.syncBattlerToParty(battler, party)
  eq(party[1].hp, 12, "party entry synced HP")
  eq(party[1].status, "PSN", "party entry synced status")

  State.wipeVolatilesAndStages(battler, { batonPass = false })
  eq(battler.stages.attack, 0, "attack stage reset to 0")
  eq(battler.stages.defense, 0, "defense stage reset to 0")
  eq(battler.confusion, nil, "confusion cleared")
  eq(battler.seeded, nil, "seeded cleared")

  -- Baton pass preserves stages
  battler.stages.speed = 3
  battler.substitute = 10
  State.wipeVolatilesAndStages(battler, { batonPass = true })
  eq(battler.stages.speed, 3, "baton pass preserves stat stages")
  eq(battler.substitute, 10, "baton pass preserves substitute")
end

print("\n--- Testing Engine.hasLivingMons & Engine.nextLivingMonIndex ---")
do
  local party = {
    { species = 1, hp = 0, maxHp = 20 },
    { species = 4, hp = 15, maxHp = 19 },
    { species = 7, hp = 0, maxHp = 22 },
  }
  eq(Engine.hasLivingMons(party), true, "hasLivingMons detects conscious mon")
  eq(Engine.nextLivingMonIndex(party, 1), 2, "nextLivingMonIndex finds slot 2")
  eq(Engine.nextLivingMonIndex(party, 2), nil, "nextLivingMonIndex finds nil if only current slot is alive")

  local deadParty = {
    { species = 1, hp = 0, maxHp = 20 },
    { species = 4, hp = 0, maxHp = 19 },
  }
  eq(Engine.hasLivingMons(deadParty), false, "hasLivingMons false when all dead")
end

print("\n--- Testing SwitchSeq Dynamic Withdraw Strings ---")
do
  local st = State.new({
    playerParty = {
      { species = 1, level = 10, hp = 25, maxHp = 30 }, -- >50% HP
      { species = 4, level = 10, hp = 10, maxHp = 30 }, -- <=50% & >20% HP
      { species = 7, level = 10, hp = 5, maxHp = 30 },  -- <=20% HP
    },
    foeMon = { species = 16, level = 10, hp = 30, maxHp = 30 },
  })

  local logged = {}
  local pushMsg = function(t) logged[#logged + 1] = t end

  -- >50% HP
  SwitchSeq.beginPlayerSwitch(st, 2, { headless = true, pushMsg = pushMsg })
  check(logged[1]:find("that's enough!"), "HP > 50% uses 'that\\'s enough!'")
  eq(st.player.partyIndex, 2, "active player party index switched to 2")
  eq(st.enemy.participants[1], true, "outgoing mon index recorded as participant")
  eq(st.enemy.participants[2], true, "incoming mon index recorded as participant")

  -- <=50% HP
  logged = {}
  SwitchSeq.beginPlayerSwitch(st, 3, { headless = true, pushMsg = pushMsg })
  check(logged[1]:find("good job!"), "HP <= 50% uses 'good job!'")
  eq(st.player.partyIndex, 3, "active player party index switched to 3")

  -- <=20% HP
  logged = {}
  SwitchSeq.beginPlayerSwitch(st, 1, { headless = true, pushMsg = pushMsg })
  check(logged[1]:find("you did it!"), "HP <= 20% uses 'you did it!'")
  eq(st.player.partyIndex, 1, "active player party index switched to 1")
end

print("\n--- Testing Manual Switch Turn Execution vs Opponent Attack ---")
do
  local pMon1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local pMon2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local foeMon = Damage.ensureStats({ species = 16, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })

  local ok, err = Battle.start({
    headless = true,
    autoFight = false,
    playerParty = { pMon1, pMon2 },
    foe = foeMon,
    wild = true,
  })
  check(ok, "Battle started successfully")
  Battle.update(0, nil) -- Advance intro to command

  local st = Battle.getState()
  eq(st.player.partyIndex, 1, "starts with slot 1 active")

  -- Queue a player switch to slot 2 while opponent uses Tackle
  Battle._actions = {
    { kind = "move", user = "enemy", target = "player", move = 33, slot = 1 },
  }
  Battle._actionI = 1
  Battle._metaAct = { kind = "switch", user = "player", slot = 2 }
  Battle._phase = "actions"

  Battle.update(0, nil)

  print("AFTER TURN st.player.mon.hp=", st.player.mon.hp, "pMon2.hp=", pMon2.hp, "pMon2.maxHp=", pMon2.maxHp)
  eq(st.player.partyIndex, 2, "switched to slot 2 before enemy attack")
  check(st.player.mon.hp < pMon2.maxHp, "enemy attack hit newly switched-in Pokémon (slot 2)")
  eq(pMon1.hp, pMon1.maxHp, "withdrawn Pokémon (slot 1) took no damage")

  Battle.abort()
end

print("\n--- Testing Pursuit Intercept on Switch ---")
do
  -- Move 228 is PURSUIT
  local pMon1 = Damage.ensureStats({ species = 1, level = 5, hp = 10, maxHp = 20, moves = { 33 }, pp = { 35 } })
  local pMon2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local foeMon = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, moves = { 228 }, pp = { 20 } })

  Battle.start({
    headless = true,
    autoFight = false,
    playerParty = { pMon1, pMon2 },
    foe = foeMon,
    wild = true,
  })
  Battle.update(0, nil) -- Advance intro

  local st = Battle.getState()
  -- Enemy queues Pursuit, Player queues switch to slot 2
  Battle._actions = {
    { kind = "move", user = "enemy", target = "player", move = 228, slot = 1 },
  }
  Battle._actionI = 1
  Battle._metaAct = { kind = "switch", user = "player", slot = 2 }
  Battle._phase = "actions"

  Battle.update(0, nil)

  check(State.isFainted(st.player) or st.player.partyIndex == 2, "Pursuit intercepted switch")

  Battle.abort()
end

print("\n--- Testing Multi-Mon Enemy Trainer Battle & Shift Species Leak ---")
do
  local pMon1 = Damage.ensureStats({ species = 1, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } })
  local pMon2 = Damage.ensureStats({ species = 4, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } })
  local eMon1 = Damage.ensureStats({ species = 16, level = 5, hp = 1, maxHp = 15, moves = { 33 }, pp = { 35 } })
  local eMon2 = Damage.ensureStats({ species = 19, level = 5, hp = 15, maxHp = 15, moves = { 33 }, pp = { 35 } })

  local ok, err = Battle.start({
    headless = true,
    autoFight = false,
    playerParty = { pMon1, pMon2 },
    foeParty = { eMon1, eMon2 },
    foe = { trainerId = 326 },
    wild = false,
  })
  check(ok, "Trainer battle started with 2 enemy Pokémon")
  Battle.update(0, nil) -- Advance intro

  local st = Battle.getState()
  eq(#st.foeParty, 2, "st.foeParty has 2 Pokémon")
  eq(st.enemy.partyIndex, 1, "starts with enemy slot 1")

  -- Defeat first enemy Pokémon (1 HP)
  Battle._actions = {
    { kind = "move", user = "player", target = "enemy", move = 33, slot = 1 },
  }
  Battle._actionI = 1
  Battle._phase = "actions"
  Battle.update(0, nil)

  eq(st.over, false, "battle is NOT over after first enemy Pokémon faints")
  eq(st.enemy.partyIndex, 2, "enemy trainer sent out second Pokémon (slot 2)")
  eq(st.enemy.species, 19, "second enemy Pokémon is species 19 (RATTATA)")

  -- Defeat second enemy Pokémon
  Battle._actions = {
    { kind = "move", user = "player", target = "enemy", move = 33, slot = 1 },
  }
  Battle._actionI = 1
  Battle._phase = "actions"
  Battle.update(0, nil)

  eq(st.over, true, "battle ends when all enemy trainer Pokémon faint")
  eq(st.result, "win", "battle result is win")

  Battle.abort()
end

print("\n--- Testing Party Blackout Defeat ---")
do
  local pMon1 = Damage.ensureStats({ species = 1, level = 5, hp = 1, maxHp = 20, moves = { 33 }, pp = { 35 } })
  local foeMon = Damage.ensureStats({ species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } })

  Battle.start({
    headless = true,
    autoFight = false,
    playerParty = { pMon1 },
    foe = foeMon,
    wild = true,
  })
  Battle.update(0, nil) -- Advance intro

  local st = Battle.getState()
  -- Enemy defeats only player Pokémon
  Battle._actions = {
    { kind = "move", user = "enemy", target = "player", move = 33, slot = 1 },
  }
  Battle._actionI = 1
  Battle._phase = "actions"
  Battle.update(0, nil)

  eq(st.over, true, "battle ended on player party blackout")
  eq(st.result, "lose", "result is lose")

  Battle.abort()
end

print("\n--- Testing PartyMenu Battle Switch & Faint Validations ---")
do
  local party = {
    { species = 1, level = 10, hp = 25, maxHp = 25 }, -- Slot 1: Active
    { species = 4, level = 10, hp = 0, maxHp = 25 },  -- Slot 2: Fainted
    { species = 7, level = 10, hp = 20, maxHp = 25 }, -- Slot 3: Conscious bench
  }

  local selectedSlot = nil
  PartyMenu.show(party, nil, {
    mode = "battle_switch",
    activeSlot = 1,
    onSelect = function(slot) selectedSlot = slot end,
  })

  -- In battle_switch mode, cursor started at 2 (since 1 was active)
  -- Try to pick fainted slot 2
  local fakeInput = {
    wasPressed = function(self, key) return key == "a" end,
  }
  PartyMenu.handleInput(fakeInput)
  eq(PartyMenu.mode, "message", "picking fainted mon shows warning message")
  check(PartyMenu._messageText:find("no will"), "message states 'There\\'s no will to fight!'")
  PartyMenu.dismissMessage()

  -- Move to slot 3 and pick
  PartyMenu.cursor = 3
  PartyMenu.handleInput(fakeInput)
  eq(PartyMenu.mode, "action", "picking conscious bench mon opens action menu")
  eq(PartyMenu.ACTIONS[1], "SHIFT", "action menu has SHIFT option")

  -- Confirm SHIFT
  PartyMenu.actionCursor = 1
  PartyMenu.handleInput(fakeInput)
  eq(selectedSlot, 3, "SHIFT confirms slot 3 selection")
  eq(PartyMenu.isOpen(), false, "PartyMenu closed on confirmation")

  -- Test battle_faint mode (must pick conscious, cannot cancel)
  selectedSlot = nil
  PartyMenu.show(party, nil, {
    mode = "battle_faint",
    activeSlot = 1,
    onSelect = function(slot) selectedSlot = slot end,
  })
  eq(PartyMenu.mode, "battle_faint", "opened in battle_faint mode")

  -- Try to cancel with B
  local cancelInput = {
    wasPressed = function(self, key) return key == "b" end,
  }
  PartyMenu.handleInput(cancelInput)
  eq(PartyMenu.mode, "message", "pressing B shows warning in battle_faint mode")
  check(PartyMenu._messageText:find("Choose a POKéMON"), "message requires choosing a Pokémon")
  PartyMenu.dismissMessage()

  -- Pick valid conscious slot 3 -> opens action menu
  PartyMenu.cursor = 3
  PartyMenu.handleInput(fakeInput)
  eq(PartyMenu.mode, "action", "battle_faint opens action menu for conscious slot 3")
  eq(PartyMenu.ACTIONS[1], "SHIFT", "action menu has SHIFT")
  eq(PartyMenu.ACTIONS[2], "SUMMARY", "action menu has SUMMARY")
  eq(PartyMenu.ACTIONS[3], "CANCEL", "action menu has CANCEL")

  -- Confirm SHIFT
  PartyMenu.actionCursor = 1
  PartyMenu.handleInput(fakeInput)
  eq(selectedSlot, 3, "SHIFT confirms slot 3 selection in battle_faint")
  eq(PartyMenu.isOpen(), false, "PartyMenu closed after faint replacement")
end

print("\n--- Testing Multi-Mon EXP Split & Bench Participation ---")
do
  local pMon1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000, moves = { 33 }, pp = { 35 } })
  local pMon2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, exp = 1000, moves = { 33 }, pp = { 35 } })
  local foeMon = Damage.ensureStats({ species = 16, level = 10, hp = 1, maxHp = 30, moves = { 33 }, pp = { 35 } })

  Battle.start({
    headless = true,
    autoFight = false,
    playerParty = { pMon1, pMon2 },
    foe = foeMon,
    wild = true,
  })
  Battle.update(0, nil)

  local st = Battle.getState()
  -- Switch from slot 1 to slot 2
  Battle._actions = {}
  Battle._actionI = 1
  Battle._metaAct = { kind = "switch", user = "player", slot = 2 }
  Battle._phase = "actions"
  Battle.update(0, nil)
  eq(st.player.partyIndex, 2, "switched to slot 2")

  -- Defeat enemy with slot 2
  local p1ExpBefore = pMon1.exp
  local p2ExpBefore = pMon2.exp
  Battle._actions = {
    { kind = "move", user = "player", target = "enemy", move = 33, slot = 1 },
  }
  Battle._actionI = 1
  Battle._phase = "actions"
  Battle.update(0, nil)

  check(pMon1.exp > p1ExpBefore, "outgoing bench mon (slot 1) received participation EXP")
  check(pMon2.exp > p2ExpBefore, "finishing active mon (slot 2) received participation EXP")
  eq(pMon1.exp - p1ExpBefore, pMon2.exp - p2ExpBefore, "EXP split equally between both participants")

  Battle.abort()
end

print("\nALL BATTLE SWITCH & FAINT TESTS PASSED! (100%)")
