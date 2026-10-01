-- engine/overworld/spinners.asm:1-22, home/overworld.asm:41-44, home/overworld.asm:268-272
-- home/copy2.asm:62-91
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TileRenderer = require("src.render.TileRenderer")

  local results = {}
  local function check(label, ok)
    results[#results + 1] = (ok and "PASS " or "FAIL ") .. label
    return ok
  end

  U.teleport(game, "ROCKET_HIDEOUT_B2F", 13, 9, "left")
  U.wait(10)
  local ow = game.overworld
  check("overworld is up on ROCKET_HIDEOUT_B2F", ow ~= nil and ow.player ~= nil)

  U.hold(game, "left", 20)
  local spinning = false
  for _ = 1, 30 do
    if ow.player.spinning then spinning = true break end
    U.wait(1)
  end
  check("stepping on the arrow starts the spin", spinning)

  local facings, timers, blurs = {}, {}, {}
  for _ = 1, 1200 do
    if not ow.player.spinning then break end
    local _, _, _, facing = ow.player:pose()
    facings[#facings + 1] = facing
    timers[#timers + 1] = ow.player.spinTimer or 0
    TileRenderer.setSpinning(ow.spinnerSliding or false, ow.spinnerLeft)
    blurs[#blurs + 1] = TileRenderer.spinBlurActive()
    U.wait(1)
  end
  check(("the slide gave %d samples (want >= 400)"):format(#facings),
    #facings >= 400)

  local ticks = true
  for i = 2, #timers do
    if timers[i] - timers[i - 1] ~= 1 then ticks = false end
  end
  check("spinTimer advances exactly once per fixed step", ticks)

  local runs, run = {}, 1
  for i = 2, #facings do
    if facings[i] == facings[i - 1] then
      run = run + 1
    else
      runs[#runs + 1] = run
      run = 1
    end
  end
  local sixes, others = 0, 0
  for i = 2, #runs do
    if runs[i] == 6 then sixes = sixes + 1 else others = others + 1 end
  end
  check(("facing holds 6 steps (%d runs of 6, %d other)"):format(sixes, others),
    sixes >= 40 and others == 0)

  local span, spans = 1, {}
  for i = 2, #blurs do
    if blurs[i] == blurs[i - 1] then
      span = span + 1
    else
      spans[#spans + 1] = span
      span = 1
    end
  end
  local good, bad = 0, 0
  for i = 2, #spans do
    if spans[i] >= 47 and spans[i] <= 49 then good = good + 1
    else bad = bad + 1 end
  end
  check(("blur toggles once per 48-frame tile (%d good, %d off)"):format(good, bad),
    good >= 4 and bad == 0)

  local ok = true
  for _, line in ipairs(results) do
    U.log(line)
    if line:sub(1, 4) == "FAIL" then ok = false end
  end
  love.event.quit(ok and 0 or 1)
end
