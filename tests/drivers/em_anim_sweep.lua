local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_anim_sweep"

local SHOTS = {
  MORNING_SUN = 40, BLIZZARD = 60, TRANSFORM = 30, ROLE_PLAY = 40, SNATCH = 40, ODOR_SLEUTH = 30,
  GLARE = 30, METEOR_MASH = 30, BLOCK = 30, TORMENT = 40, ENCORE = 30, DOOM_DESIRE = 60,
  SURF = 40, PSYCHIC = 40, THUNDERBOLT = 20, FLAMETHROWER = 30, HYPER_BEAM = 40, EARTHQUAKE = 20,
}

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  local issues, issueSeen, current = {}, {}, "setup"
  local function issue(kind, name)
    local key = kind .. ":" .. tostring(name)
    if issueSeen[key] then return end
    issueSeen[key] = true
    issues[#issues + 1] = key .. " (" .. current .. ")"
  end
  local realPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local s = table.concat(parts, " ")
    if s:find("[battle.anim]", 1, true) and not s:find("cap", 1, true) then issue("log", s) end
    realPrint(...)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimCtx = require("src.core.game3.battle.anim_ctx")
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  local Ui = require("src.core.game3.battle.ui")
  local Map = require("src.core.game3.map")
  local GAME = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(GAME)
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then love.event.quit(1) return end

  local function sp(name) return C.species.byName["SPECIES_" .. name] end

  local realSpawn = AnimTasks.spawn
  AnimTasks.spawn = function(name, priority, args, vm)
    local n = tostring(name or "stub")
    local key = n:gsub("^g", "")
    if not (AnimTasks.REGISTRY[n] or AnimTasks.REGISTRY[key] or AnimTasks.REGISTRY["AnimTask_" .. key]) then
      issue("task", n)
    end
    return realSpawn(name, priority, args, vm)
  end
  local realGet = AnimCallbacks.get
  AnimCallbacks.get = function(name)
    if name and name ~= "" then
      local clean = tostring(name):gsub("^Anim", "")
      if not (rawget(AnimCallbacks, name) or AnimCallbacks[name] or AnimCallbacks[clean] or AnimCallbacks["Anim" .. clean]) then
        issue("callback", name)
      end
    end
    return realGet(name)
  end

  if GAME == "emerald" then
    local ok, err = pcall(function() Map.load(nil, game, "EM_ROUTE101", { x = 10, y = 12, facing = "down" }) end)
    result(ok, "load EM_ROUTE101 " .. tostring(err or ""))
  end
  U.wait(30)
  session.party = {}
  Party.giveMon(session, sp("SALAMENCE"), 50, "SALAMENCE")
  session.party[1].hp = session.party[1].maxHp or session.party[1].hp

  local started, serr = BattleBridge.startWild(Runtime._mod, game, { species = sp("ZIGZAGOON"), level = 50 }, { fade = false })
  result(started == true, "wild battle started " .. tostring(serr or ""))
  if not started then love.event.quit(1) return end
  local ready = false
  for _ = 1, 6000 do
    if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(ready, "battle reached the action menu")
  if not ready then love.event.quit(1) return end
  U.wait(20)

  local pack = Anim._pack or (Anim.scriptForMove(1) and Anim._pack)
  result(pack and pack.moves ~= nil, "Emerald anim pack loaded")
  local moveCount = 0
  for _ in pairs(pack.moves) do moveCount = moveCount + 1 end
  result(moveCount == 355, "pack has 355 move scripts (" .. moveCount .. ")")
  if GAME == "emerald" then
    result(#pack.generalNames == 22 and pack.generalNames[4] == "POKEBLOCK_THROW", "23 general anims, 4 = POKEBLOCK_THROW")
  end

  local st = Battle._st
  local pSpecies = st and st.player and st.player.mon and st.player.mon.species or sp("SALAMENCE")
  local eSpecies = st and st.enemy and st.enemy.mon and st.enemy.mon.species or sp("ZIGZAGOON")

  local function restore()
    for _, s in ipairs({ "player", "enemy" }) do
      local p = Anim.present(s)
      if p then
        p.visible = true
        p.ox, p.oy, p.sx, p.sy, p.rotation = 0, 0, 1, 1, 0
        p.blendCoeff = 0
        p.invisible = nil
        p.transformSpecies = nil
      end
      if p and p.substitute then Anim.setSubstitute(s, false) end
    end
  end

  local function audit_sprites()
    AnimSprites.init()
    for i = 1, AnimSprites.MAX do
      local s = AnimSprites._pool[i]
      if s.active and s.tag and s.tag ~= "" and not s.image and not s.invisible and s.visible ~= false
          and not (s._op and s._op.noGfx) then
        issue("sprite-no-image", s.tag)
      end
    end
  end

  local RESTORED = { visible = true, ox = true, oy = true, sx = true, sy = true, rotation = true, blendCoeff = true }
  local function snap()
    local out = {}
    for _, side in ipairs({ "player", "enemy" }) do
      local p = Anim.present(side) or {}
      for k, v in pairs(p) do
        local t = type(v)
        if (t == "number" or t == "boolean" or t == "string") and not RESTORED[k] then out[side .. "." .. k] = v end
      end
    end
    return out
  end
  local baseline
  local leaks = {}
  local function check_leak(label)
    local now = snap()
    for k, v in pairs(now) do
      if baseline[k] ~= v and not leaks[k] then
        leaks[k] = true
        print("[driver] leak " .. k .. " " .. tostring(baseline[k]) .. " -> " .. tostring(v) .. " after " .. label)
      end
    end
    for k, v in pairs(baseline) do
      if now[k] == nil and not leaks[k] then
        leaks[k] = true
        print("[driver] leak " .. k .. " " .. tostring(v) .. " -> nil after " .. label)
      end
    end
  end

  local timeouts, totalFrames, ran = 0, 0, 0
  local function run(label, launch, shotAt)
    current = label
    local okL, e = pcall(launch)
    if not okL then issue("launch", tostring(e)) return end
    local f = 0
    while f < 1500 do
      U.wait(1)
      f = f + 1
      if f % 8 == 0 then audit_sprites() end
      local want = shotAt and (type(shotAt) == "table" and shotAt[f] or shotAt == f)
      if want then
        local stem = label:lower():gsub("[^%w]+", "_")
        U.still(game, DIR .. "/" .. stem .. (type(shotAt) == "table" and string.format("_%03d", f) or "") .. ".png")
      end
      if not Anim.busy() and (not shotAt or f > (type(shotAt) == "table" and shotAt.last or shotAt)) then break end
    end
    if Anim.busy() then
      timeouts = timeouts + 1
      issue("timeout", label)
    end
    totalFrames = totalFrames + f
    ran = ran + 1
    restore()
    check_leak(label)
    U.wait(4)
  end

  local function opts(side, turn, moveId)
    local target = side == "player" and "enemy" or "player"
    return {
      attackerSide = side,
      targetSide = target,
      isReversed = side == "enemy",
      attackerSpecies = side == "player" and pSpecies or eSpecies,
      targetSpecies = side == "player" and eSpecies or pSpecies,
      moveTurn = turn or 0,
      turn = turn or 0,
      ctx = AnimCtx.build(side, target, { moveId = moveId }),
    }
  end

  baseline = snap()
  local only = os.getenv("EM_ANIM_MOVES")
  local shotList = nil
  if os.getenv("EM_ANIM_SHOTS") then
    shotList = { last = 0 }
    for n in os.getenv("EM_ANIM_SHOTS"):gmatch("%d+") do
      shotList[tonumber(n)] = true
      if tonumber(n) > shotList.last then shotList.last = tonumber(n) end
    end
  end
  local sides = os.getenv("EM_ANIM_SIDES") or "player,enemy"
  for id = 1, 354 do
    local name = (C:name("moves", id, "MOVE_") or ("MOVE_" .. id)):gsub("^MOVE_", "")
    if not only or only:find(name, 1, true) then
      for side in sides:gmatch("[^,]+") do
        local shot = shotList or (side == "player" and SHOTS[name] or nil)
        run(name .. "_" .. side, function() Anim.launchMove(id, opts(side, 0, id)) end, shot)
        for _, op in ipairs(pack.moves[id]) do
          if op.op == "choosetwoturnanim" or op.op == "jumpifmoveturn" then
            run(name .. "_turn1_" .. side, function() Anim.launchMove(id, opts(side, 1, id)) end, nil)
            break
          end
        end
      end
    end
  end
  if not only then
    for i = 0, #pack.generalNames do
      local n = pack.generalNames[i]
      do
        run("general_" .. n, function() Anim.launchGeneral(n, opts("player")) end, n == "STATS_CHANGE" and 20 or nil)
      end
    end
    for i = 0, #pack.statusNames do
      local n = pack.statusNames[i]
      run("status_" .. n, function() Anim.launchStatus(i, opts("enemy")) end, n == "STATUS_FRZ" and 20 or nil)
    end
    for _, n in ipairs({ "LVL_UP", "SUBSTITUTE_TO_MON", "MON_TO_SUBSTITUTE" }) do
      run("special_" .. n, function() Anim.launchSpecial(n, opts("player")) end, nil)
    end
  end

  print = realPrint
  print(string.format("[driver] ran %d anims, %d frames, %d timeouts", ran, totalFrames, timeouts))
  for _, s in ipairs(issues) do print("[driver] issue " .. s) end
  result(#issues == 0, "no unresolved task/callback, sprite without sheet, anim log or launch error (" .. #issues .. ")")
  result(timeouts == 0, "every anim finishes within 1500 frames")
  print(string.format("[driver] em_anim_sweep: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
