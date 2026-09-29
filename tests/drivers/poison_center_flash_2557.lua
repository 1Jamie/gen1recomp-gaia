-- engine/events/poison.asm:93 / engine/gfx/screen_effects.asm:2 (#2557)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local shotDir = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-29-26-01-userreported/shots"
  local fails = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then fails = fails + 1 end
    return ok
  end

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.party[1].status = "PSN"
  game.save.player.name = "bryan"
  game.save.usedPokecenter = true

  local function scenario(label, shots)
    U.log("=== " .. label)
    U.teleport(game, "VIRIDIAN_POKECENTER", 3, 7, "up")
    game.save.poisonSteps = 0
    local ow = game.overworld
    local p = ow.player
    local hpBefore = game.save.party[1].hp
    local flashFrames, shotTaken = 0, false
    for _ = 1, 400 do
      table.insert(game.input.pressQueue, "up")
      game.input.state.up = true
      if p.moving and p.targetY == 3 and not game.input.state.a then
        table.insert(game.input.pressQueue, "a")
        game.input.state.a = true
      end
      coroutine.yield()
      if (ow.poisonFlash or 0) > 0 and game.stack:top() == ow then
        flashFrames = flashFrames + 1
        if shots and not shotTaken then
          shotTaken = true
          game.input.state.up = false
          U.still(game, shotDir .. "/2557_01_flash_before_nurse_talk.png")
        end
      end
      if game.stack:top() ~= ow then break end
    end
    game.input.state.up = false
    game.input.state.a = false
    check(label .. ": 4th step landed at (3,3)", p.cellY == 3 and not p.moving)
    check(label .. ": the 4th step cost 1 HP", game.save.party[1].hp == hpBefore - 1)
    check(label .. ": flash plays 4 frames before the nurse talk", flashFrames == 4)
    check(label .. ": nurse dialogue opened after the flash", game.stack:top() ~= ow)
    check(label .. ": nothing frozen under the text box", (ow.poisonFlash or 0) == 0)

    local deferred, balls = 0, false
    for tick = 1, 1200 do
      if game.stack:top() ~= ow and tick % 4 == 0 then
        table.insert(game.input.pressQueue, "a")
      end
      coroutine.yield()
      game.input.state.a = false
      if game.stack:top() == ow and (ow.poisonFlash or 0) > 0 then
        deferred = deferred + 1
      end
      if ow.healAnim and ow.healAnim.lit >= 1 then
        balls = true
        break
      end
    end
    check(label .. ": machine started", balls)
    check(label .. ": no poison flash after the nurse text", deferred == 0)
    if shots and balls then
      U.still(game, shotDir .. "/2557_02_no_flash_at_balls.png")
    end
    for _ = 1, 400 do
      if game.stack:top() == ow and not ow.healAnim and not ow.emote then break end
      if game.stack:top() ~= ow then table.insert(game.input.pressQueue, "a") end
      coroutine.yield()
      game.input.state.a = false
    end
    game.save.party[1].status = "PSN"
  end

  scenario("count_pass", false)
  scenario("shot_pass", true)
  love.event.quit(fails == 0 and 0 or 1)
end
