local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_mon_anim_sweep"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_mon_anim_sweep failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

local function waitFor(pred, limit)
  for _ = 1, limit or 600 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

local function topId()
  local t = require("src.ui.game3.stack").top()
  return t and t.id
end

local function tapWait(game, btn, n)
  U.tap(game, btn)
  U.wait(n or 20)
end

local function shot(game, name)
  U.still(game, DIR .. "/" .. name .. ".png")
end

local function run(M, s, tasksFirst)
  local n = 0
  while not M.done(s) and n < 2000 do
    M.step(s, tasksFirst)
    n = n + 1
  end
  return n
end

local function sweep(M, C)
  local EGG = C:require("species", "SPECIES_EGG")
  local stuck, longest, longestSp = {}, 0, 0
  for sp = 1, EGG do
    local s = M.newSprite(sp, { data = { [0] = 1, [2] = sp } })
    M.battleFront(s, sp, false, 1, { cry = function() end })
    local n = run(M, s)
    if n > longest then longest, longestSp = n, sp end
    if n >= 2000 or s.data[2] ~= sp or not s.animEnded then stuck[#stuck + 1] = "front" .. sp end
    for flip = 0, 1 do
      local q = M.newSprite(sp, { affineMode = "off", hFlip = flip == 0, data = { [0] = sp } })
      q.summary = true
      q.callback = function(x) x.data[1] = flip; M.summary(x, sp, sp == EGG) end
      if run(M, q, true) >= 2000 then stuck[#stuck + 1] = "summary" .. sp end
    end
    if sp <= 411 then
      for nature = 0, 24 do
        local b = M.newSprite(sp, { data = { [0] = 0, [2] = sp } })
        M.battleBack(b, sp, nature)
        if run(M, b) >= 2000 then stuck[#stuck + 1] = "back" .. sp .. "/" .. nature end
      end
    end
  end
  check(#stuck == 0, "all " .. EGG .. " species end their front, summary and 25-nature back anims ("
    .. table.concat(stuck, ",") .. ")")
  check(M.oob == 0, "no out-of-table sine reads (" .. M.oob .. ")")
  print(string.format("[driver] longest front anim %d frames (species %d)", longest, longestSp))
end

return function(game)
  if not check(waitFor(function() return game.phase == "boot" and game.boot end, 900), "boot reached") then
    return finish()
  end
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 }) end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local M = require("src.core.game3.mon_anim")
  local MonAnimBattle = require("src.core.game3.battle.mon_anim_battle")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil and session.version == "emerald", "emerald field session") then return finish() end
  if not check(M.enabled(), "Emerald cache carries front_anims/back_anims") then return finish() end
  try("sweep", function() sweep(M, C) end)

  local IDS = Flags.forVersion("emerald").IDS
  local store = Space.store or session
  for _, f in ipairs({ "FLAG_SYS_POKEMON_GET", "FLAG_SYS_POKEDEX_GET" }) do Flags.setFlag(store, nil, IDS[f], true) end
  local function sp(name) return C:require("species", "SPECIES_" .. name) end
  local function giveMon(name, level, nature)
    local ok, _, mon = Party.giveMon(session, sp(name), level)
    if ok and mon and nature then
      local p = tonumber(mon.personality) or 0
      mon.personality = p - (p % 25) + nature
      mon.nature = nature
    end
    return mon
  end
  session.party = {}
  local sal = giveMon("SALAMENCE", 50, 17)
  giveMon("MAGCARGO", 38)
  if sal then sal.hp = sal.maxHp or sal.hp end
  check(#session.party == 2, "party Salamence + Magcargo")

  try("battle", function()
    Map.load(nil, game, "EM_ROUTE117", { x = 32, y = 15, facing = "down" })
    U.wait(40)
    local BattleBridge = require("src.core.game3.battle_bridge")
    local Battle = require("src.core.game3.battle")
    local Anim = require("src.core.game3.battle.anim")
    local Ui = require("src.core.game3.battle.ui")
    local ok = BattleBridge.startWild(Runtime._mod, game, { species = sp("ODDISH"), level = 14 }, {})
    check(ok == true, "wild Oddish battle starts")
    local sim = M.newSprite(sp("ODDISH"), { data = { [0] = 1, [2] = sp("ODDISH") } })
    sim.callback = function(x) M.battleFront(x, sp("ODDISH"), false, 1, { cry = function() end }) end
    local enemyRows, playerSeen, frontShot, backShot = {}, false, false, false
    local lastTap = 0
    for f = 1, 4000 do
      local e = Anim.present("enemy")
      local p = Anim.present("player")
      local es = e and MonAnimBattle._active[e]
      if es and e.monFrame ~= nil then
        enemyRows[#enemyRows + 1] = { e.ox, e.oy, e.sx, e.sy, e.monFrame }
        if not frontShot and e.sy and e.sy < 0.95 then frontShot = true shot(game, "01_battle_front_squish") end
      end
      local ps = p and MonAnimBattle._active[p]
      if ps then
        playerSeen = true
        if not backShot and (p.ox or 0) ~= 0 then backShot = true shot(game, "02_battle_back_shake") end
      end
      if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then break end
      if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    local simSeq = {}
    repeat
      M.step(sim)
      simSeq[#simSeq + 1] = M.transform(sim)
    until M.done(sim) or #simSeq > 2000
    local match, j = #enemyRows > 0, 1
    for i, r in ipairs(enemyRows) do
      local found = false
      while j <= #simSeq do
        local t = simSeq[j]
        j = j + 1
        if r[1] == t.x2 and r[2] == t.y2 and math.abs(r[3] - t.sx) < 1e-9 and math.abs(r[4] - t.sy) < 1e-9
            and r[5] == t.frame then
          found = true
          break
        end
      end
      if not found then
        print(string.format("[driver] enemy row %d not in the port sequence: %s,%s,%.3f,%.3f,%s", i,
          tostring(r[1]), tostring(r[2]), r[3], r[4], tostring(r[5])))
        match = false
        break
      end
    end
    print(string.format("[driver] enemy rows %d, port frames %d", #enemyRows, #simSeq))
    check(match, "enemy Oddish present follows the Anim_VerticalSquishBounce + sAnim_Oddish_1 port for "
      .. #enemyRows .. " frames")
    check(frontShot, "front anim squish frame captured")
    check(playerSeen and backShot, "player Salamence back anim (nature 17 -> HorizontalShake_Slow) ran")
    check(Battle._phase == "command", "battle reached the command menu after the anims")
    shot(game, "03_battle_command")
    Battle.abort("run")
    waitFor(function() return not Battle.isActive() end, 600)
    U.wait(60)
  end)

  try("summary", function()
    Map.load(nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
    local s = Runtime.getSession()
    s.x, s.y = 14, 12
    Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
    Player.targetX, Player.targetY = 14, 12
    U.wait(60)
    tapWait(game, "start", 30)
    local StartMenu = require("src.ui.game3.start_menu")
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == "pokemon" then
        while StartMenu.cursor ~= i do tapWait(game, "down", 6) end
        tapWait(game, "a", 60)
        break
      end
    end
    check(topId() == "party", "POKEMON opens the party menu")
    tapWait(game, "a", 20)
    tapWait(game, "a", 2)
    local RseSummary = require("src.ui.game3.rse.summary_menu")
    local st = RseSummary._st
    local first
    local mid = waitFor(function()
      first = st.monSprite
      return first and first.animId ~= nil and (first.x2 ~= 0 or first.y2 ~= 0 or first.affineMode == "double")
    end, 240)
    check(topId() == "summary", "SUMMARY opens")
    check(mid, "summary Salamence anim is moving the sprite")
    shot(game, "04_summary_salamence_anim")
    check(waitFor(function() return M.done(first) end, 600), "summary Salamence anim ends")
    check(first.hFlip == true and first.affineMode == "off", "summary sprite ends flipped with affine off")
    tapWait(game, "down", 4)
    waitFor(function() return st.monSprite ~= first end, 120)
    local second = st.monSprite
    check(second ~= first and second ~= nil and second.species == sp("MAGCARGO"),
      "down re-creates the sprite for Magcargo (" .. tostring(second and second.species) .. ")")
    waitFor(function() return second.x2 ~= 0 or second.y2 ~= 0 or second.affineMode == "double" end, 120)
    shot(game, "05_summary_magcargo_anim")
    check(waitFor(function() return M.done(second) end, 600), "summary Magcargo anim ends")
    for _ = 1, 6 do
      if topId() == nil then break end
      tapWait(game, "b", 40)
    end
    check(topId() == nil, "menus closed back to the field (" .. tostring(topId()) .. ")")
  end)

  try("evolution", function()
    local EvolutionScene = require("src.ui.game3.evolution_scene")
    local ok, _, mon = Party.giveMon(session, sp("TORCHIC"), 16)
    check(ok and mon ~= nil, "Torchic for the evolution")
    local done
    EvolutionScene.start(mon, sp("COMBUSKEN"), { session = session, canStop = false, onDone = function(r) done = r end })
    local pre, post, preShot, postShot
    for _ = 1, 5000 do
      local ma = EvolutionScene._monAnim
      if ma and ma.evoSpecies == sp("TORCHIC") then
        pre = ma
        if not preShot and (ma.x2 ~= 0 or ma.y2 ~= 0 or ma.affineMode == "double") then
          preShot = true
          shot(game, "06_evo_torchic_anim")
        end
      end
      if ma and ma.evoSpecies == sp("COMBUSKEN") then
        post = ma
        if not postShot and (ma.x2 ~= 0 or ma.y2 ~= 0 or ma.affineMode == "double") then
          postShot = true
          shot(game, "07_evo_combusken_anim")
        end
      end
      if not EvolutionScene.isOpen() then break end
      local stt = EvolutionScene._state
      if stt == "congrats" or stt == "learn" or stt == "learn_moves" then U.tap(game, "a") else U.wait(1) end
    end
    check(pre ~= nil and M.done(pre), "pre-evolution Torchic front anim played to its end")
    check(post ~= nil, "Combusken front anim played at the evolution end")
    check(preShot and postShot, "evolution anim frames captured")
    check(not EvolutionScene.isOpen(), "evolution scene closed (" .. tostring(done) .. ")")
  end)

  try("egg", function()
    local EggHatch = require("src.ui.game3.egg_hatch")
    local Field = require("src.core.game3.field")
    local Daycare = require("src.core.game3.daycare")
    while #session.party > 2 do table.remove(session.party) end
    local ok = Party.giveEgg(session, sp("WURMPLE"))
    local egg = session.party[#session.party]
    check(ok and egg and egg.isEgg == true, "an EGG is in the party")
    egg.friendship, egg.eggCycles = 0, 0
    local dc = Daycare.stateOf(session)
    if dc then dc.stepCounter = 254 end
    Map.load(nil, game, "EM_ROUTE101", { x = 10, y = 12, facing = "down" })
    local s = Runtime.getSession()
    s.x, s.y = 10, 12
    Player.cellX, Player.cellY, Player.px, Player.py = 10, 12, 10 * 16, 12 * 16
    Player.targetX, Player.targetY = 10, 12
    Field.unlock()
    U.wait(40)
    local walked = 0
    for _ = 1, 60 do
      U.hold(game, walked % 2 == 0 and "up" or "down", 16)
      walked = walked + 1
      if EggHatch.isOpen() then break end
      U.tap(game, "a")
      U.wait(10)
      if EggHatch.isOpen() then break end
    end
    print(string.format("[driver] %d holds, day care counter %s, top %s", walked, tostring(dc and dc.stepCounter),
      tostring(topId())))
    check(EggHatch.isOpen(), "walking hatched the egg")
    local ma, eggShot
    for _ = 1, 3000 do
      ma = EggHatch._monAnim or ma
      if ma and not eggShot and (ma.x2 ~= 0 or ma.y2 ~= 0 or ma.affineMode == "double" or ma.frame == 1) then
        eggShot = true
        shot(game, "08_egg_hatch_wurmple_anim")
      end
      if EggHatch._state == "hatched_msg" then break end
      U.wait(1)
    end
    check(ma ~= nil and M.done(ma), "hatchling front anim ran before the hatched message")
    check(eggShot, "hatch anim frame captured")
    for _ = 1, 600 do
      if not EggHatch.isOpen() then break end
      U.tap(game, "b")
      U.wait(10)
    end
  end)

  finish()
end
