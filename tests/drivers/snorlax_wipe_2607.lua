-- pokered/scripts/Route12.asm:37
-- pokered/scripts/Route16.asm:37
-- pokered/engine/battle/battle_transitions.asm:28
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleTransition = require("src.render.BattleTransition")
  local scripts = require("data.scripts.init")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local fails = 0
  local probeCanvas = love.graphics.newCanvas(160, 144)
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function contains(ow, npc)
    for _, entity in ipairs(ow.entities) do
      if entity == npc then return true end
    end
    return false
  end
  local function npcNamed(ow, name)
    for _, npc in ipairs(ow.npcs) do
      if npc.def.name == name then return npc end
    end
  end
  local function watch(ow, npc)
    local counts = { hidden = 0, npcReplay = 0, playerReplay = 0, replay = false }
    local npcDraw, heroDraw, replay = npc.draw, ow.player.draw, ow.drawWipeSprites
    npc.draw = function(self, ...)
      if not contains(ow, self) then counts.hidden = counts.hidden + 1 end
      if counts.replay then counts.npcReplay = counts.npcReplay + 1 end
      return npcDraw(self, ...)
    end
    ow.player.draw = function(self, ...)
      if counts.replay then counts.playerReplay = counts.playerReplay + 1 end
      return heroDraw(self, ...)
    end
    ow.drawWipeSprites = function(self)
      counts.replay = true
      replay(self)
      counts.replay = false
    end
    return counts
  end
  local function probe(ow)
    love.graphics.push("all")
    love.graphics.setCanvas(probeCanvas)
    love.graphics.clear(0, 0, 0, 0)
    ow:drawWipeSprites()
    love.graphics.pop()
  end
  local function awaitTransition(label)
    for _ = 1, 900 do
      local top = game.stack:top()
      if getmetatable(top) == BattleTransition then return top end
      if top and top.isTextBox then U.tap(game, "a") else U.wait(1) end
    end
    check(label .. "_reached_transition", false)
  end
  local function awaitWipe(tr, fraction)
    for _ = 1, 300 do
      if game.stack:top() ~= tr then return false end
      if tr.phase == "wipe" and tr.t / tr.wipeLen >= fraction then
        return tr.t < tr.wipeLen
      end
      U.wait(1)
    end
    return false
  end
  local function capture(name)
    check(name .. "_capture", U.still(game, dir .. "/2607_" .. name .. ".png"))
  end
  local function routeSetup(route)
    local mapId = "ROUTE_" .. route
    local wake = scripts.get(mapId).snorlaxWake
    game.save.flags[wake.beatFlag] = nil
    game.save.objectToggles[mapId] = { [wake.objName] = true }
    U.teleport(game, mapId, 10, 10, "left")
    local npc = npcNamed(game.overworld, wake.objName)
    if not check("route" .. route .. "_sleeping_snorlax_exists", npc ~= nil) then return end
    U.teleport(game, mapId, npc.cellX + 1, npc.cellY, "left")
    U.wait(20)
    local ow = game.overworld
    npc = npcNamed(ow, wake.objName)
    local adjacent = npc and math.abs(npc.cellX - ow.player.cellX)
                     + math.abs(npc.cellY - ow.player.cellY) == 1
    if not check("route" .. route .. "_snorlax_adjacent", adjacent) then return end
    local counts = watch(ow, npc)
    ow.runner:run(wake.script, { npc = npc })
    return ow, npc, counts
  end

  game.save.flags = game.save.flags or {}
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.player.name = "RED"
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }

  for _, route in ipairs({ "12", "16" }) do
    local label = "route" .. route
    local ow, npc, counts = routeSetup(route)
    if ow then
      local tr = awaitTransition(label)
      if tr then
        check(label .. "_hidden_before_flash", not contains(ow, npc))
        check(label .. "_retains_detached_context", ow.battleOamKeep == npc)
        if check(label .. "_count_partial_wipe", awaitWipe(tr, 0.55)) then probe(ow) end
        for _ = 1, 300 do
          if game.stack:top() ~= tr then break end
          U.wait(1)
        end
        check(label .. "_transition_completes", game.stack:top() ~= tr)
        check(label .. "_no_hidden_replay_count", counts.hidden == 0 and counts.npcReplay == 0)
        check(label .. "_player_replays_count", counts.playerReplay > 0)
      end
    end
    ow, npc, counts = routeSetup(route)
    if ow then
      local tr = awaitTransition(label .. "_capture")
      if tr then
        for _ = 1, 100 do
          if tr.phase ~= "flash" or tr.t >= 12 then break end
          U.wait(1)
        end
        if check(label .. "_flash_reached", tr.phase == "flash") then
          capture(label .. "_flash_player_only")
        end
        if check(label .. "_partial_wipe_reached", awaitWipe(tr, 0.55)) then
          capture(label .. "_partial_wipe_player_only")
        end
        check(label .. "_no_hidden_replay_capture", counts.hidden == 0 and counts.npcReplay == 0)
        check(label .. "_player_replays_capture", counts.playerReplay > 0)
      end
    end
  end

  for _, kind in ipairs({ "trainer", "wild" }) do
    U.teleport(game, "PALLET_TOWN", 10, 8, "left")
    local npc = game.overworld.npcs[1]
    if check(kind .. "_control_npc_exists", npc ~= nil) then
      local name = npc.def.name
      U.teleport(game, "PALLET_TOWN", npc.cellX + 1, npc.cellY, "left")
      U.wait(20)
      local ow = game.overworld
      npc = npcNamed(ow, name)
      local counts = watch(ow, npc)
      local row = kind == "trainer" and { "start_battle", kind, "OPP_YOUNGSTER", 1 }
                  or { "start_battle", kind, "WEEDLE", 5 }
      ow.runner:run({ row }, { npc = npc })
      local tr = awaitTransition(kind .. "_control")
      if tr and check(kind .. "_control_partial_wipe", awaitWipe(tr, 0.55)) then
        check(kind .. "_control_member", contains(ow, npc) and ow.battleOamKeep == npc)
        capture(kind .. "_partial_wipe_visible_npc")
        check(kind .. "_visible_survivor_replays", counts.npcReplay > 0)
        check(kind .. "_player_survivor_replays", counts.playerReplay > 0)
      end
    end
  end
  U.log("RESULT", fails == 0 and "PASS" or "FAIL", "snorlax_wipe_2607", "failures=" .. fails)
  love.event.quit(fails == 0 and 0 or 1)
end
