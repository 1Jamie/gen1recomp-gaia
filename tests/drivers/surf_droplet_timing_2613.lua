-- pokered/engine/battle/animations.asm:1118
local U = require("tests.drivers.util")
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local Sound = require("src.core.Sound")

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/surf-droplets-2613"
  local failures = 0
  local function check(label, condition, detail)
    if condition then U.log("PASS", label) else
      failures = failures + 1
      U.log("FAIL", label, tostring(detail))
    end
    return condition
  end
  local function waitFor(predicate, limit, mash)
    for i = 1, limit do
      if predicate() then return true end
      if mash and i % 6 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    return predicate() and true or false
  end
  local function run()
    game.save.options = game.save.options or {}
    game.save.options.animations = true
    U.teleport(game, "PALLET_TOWN", 10, 8, "down")
    local ow = assert(game.overworld, "overworld unavailable")
    local function leave()
      for _ = 1, 10 do
        if game.stack:top() == ow then return end
        game.stack:pop()
      end
      error("battle stack did not unwind")
    end
    local function scenario(id, side, shots)
      local lead = Pokemon.new(game.data, "BLASTOISE", 60)
      lead.moves = { { id = side and id or "SPLASH", pp = 40 } }
      game.save.party = { lead }
      local b = BattleState.newWild(game, "BLASTOISE", 20)
      b.onFinish = function() end
      b.enemy.mon.moves = { { id = side and "SPLASH" or id, pp = 40 } }
      b.enemy.curMoves = b.enemy.mon.moves
      b.rng = function(a) return a or 0 end
      local sounds, firstSoundBusy, firstRemaining = {}, nil, nil
      local realSound = b.playAnimSound
      b.playAnimSound = function(self, soundMove)
        if self.animName == id and self.animAttackerIsPlayer == side then
          sounds[#sounds + 1] = { id = soundMove, tick = U.frame(), elapsed = self.animPlayer.elapsed }
          if soundMove == "HYDRO_PUMP" then
            firstSoundBusy, firstRemaining = Sound.moveSfxBusy(), Sound.moveSfxWaitFrames()
            U.log("SURF audio before HYDRO_PUMP", "busy=" .. tostring(firstSoundBusy),
              "remainingFrames=" .. tostring(firstRemaining))
          end
        end
        return realSound(self, soundMove)
      end
      ow:pushBattle(b)
      assert(waitFor(function() return b.phase == "menu" end, 2500, true), "battle menu did not open")
      U.tap(game, "a")
      assert(waitFor(function() return b.phase == "moveSelect" end, 180), "move menu did not open")
      U.tap(game, "a")
      assert(waitFor(function()
        return b.animPlaying and b.animName == id and b.animAttackerIsPlayer == side
      end, 3000, true), id .. " animation did not start")
      local ap = b.animPlayer
      local waterStart
      for _, ev in ipairs(ap.events) do
        if ev.effect == "SE_WATER_DROPLETS_EVERYWHERE" then waterStart = ev.frame break end
      end
      assert(waterStart, id .. " water effect missing from ROM cache")
      local visible, clear, cadence = 0, 0, true
      for _ = 1, 1500 do
        if not b.animPlaying or b.animName ~= id or b.animAttackerIsPlayer ~= side then break end
        local tick = ap.elapsed - waterStart
        local st = ap.steps[ap.stepIndex]
        local n = st and #st.sprites or 0
        if tick >= 10 and tick < 138 then
          if (tick - 10) % 2 == 0 then
            visible = visible + (n > 0 and 1 or 0)
            cadence = cadence and n > 0
          else
            clear = clear + (n == 0 and 1 or 0)
            cadence = cadence and n == 0
          end
        end
        if shots then
          local name = tick == 10 and "first_droplets" or tick == 11 and "first_clear"
            or tick == 136 and "last_droplets" or tick == 148 and "water_columns"
          if name then
            check("surf_" .. name .. "_screenshot",
              U.still(game, dir .. "/2613_" .. name .. ".png"))
          end
        end
        U.wait(1)
      end
      local label = id:lower() .. (side and "_player" or "_enemy")
      check(label .. "_64_visible_ticks", visible == 64, visible)
      check(label .. "_64_clear_ticks", clear == 64, clear)
      check(label .. "_visible_blank_cadence", cadence)
      check(label .. "_animation_started_cleanly", b.animStartWarned == nil)
      if id == "SURF" then
        local a, z
        for _, ev in ipairs(sounds) do
          if ev.id == "SURF" then a = ev end
          if ev.id == "HYDRO_PUMP" then z = ev end
        end
        check(label .. "_next_sound_frame_148", a and z and z.elapsed - a.elapsed == 148,
          a and z and z.elapsed - a.elapsed)
        if not shots then
          check(label .. "_next_sound_tick_148", a and z and z.tick - a.tick == 148,
            a and z and z.tick - a.tick)
        end
        check(label .. "_real_audio_observed", firstSoundBusy ~= nil and firstRemaining ~= nil)
      end
      leave()
    end
    scenario("SURF", true, false)
    scenario("SURF", false, false)
    scenario("MIST", true, false)
    scenario("TOXIC", true, false)
    scenario("SURF", true, true)
  end
  local ok, err = xpcall(run, debug.traceback)
  if not ok then failures = failures + 1 U.log("FAIL surf_driver_error", err) end
  U.log(failures == 0 and "PASS" or "FAIL", "surf_droplet_timing_2613")
  love.event.quit(failures == 0 and 0 or 1)
end
