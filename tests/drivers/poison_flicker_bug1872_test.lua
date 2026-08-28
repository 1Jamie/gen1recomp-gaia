-- pokered engine/gfx/screen_effects.asm:1-12 (#1872)
--   POKEPORT_DRIVER=tests/drivers/poison_flicker_bug1872_test.lua POKEPORT_IDENTITY=bug1872 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local PaletteFX = require("src.render.PaletteFX")
  local Zoom = require("src.render.Zoom")
  local Renderer = require("src.render.Renderer")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.party[1].status = "PSN"
  game.save.player.name = "bryan"

  local lo = Zoom.offsetRange(Renderer:fitScale())
  game.save.options.zoom = lo
  Zoom.applyOptions(game.save.options)

  U.teleport(game, "ROUTE_1", 5, 20, "down")
  U.wait(20)

  local rects = {}
  local realRect = love.graphics.rectangle
  love.graphics.rectangle = function(mode, x, y, w, h, ...)
    if mode == "fill" and x == 0 and y == 0 and w == 160 and h == 144 then
      rects[#rects + 1] = true
    end
    return realRect(mode, x, y, w, h, ...)
  end

  -- engine/events/poison.asm
  local ow, armed, peak = game.overworld, false, 0
  for _ = 1, 160 do
    local dir = (_ % 2 == 0) and "up" or "down"
    for _ = 1, 2 do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
      ow = game.overworld
      local n = ow and ow.poisonFlash or 0
      if n > peak then peak = n end
      if n > 0 then armed = true end
    end
    game.input.state[dir] = false
    if armed then break end
  end
  check("a poison tick armed the flicker while walking", armed)
  U.log("tinted frames", peak + 1)
  if armed then
    check("it arms four frames, like `ld c, 4 / call DelayFrames`", peak + 1 == 4)
  end

  local sawMap = false
  for _ = 1, 6 do
    U.wait(1)
    if PaletteFX.shadeMap() == PaletteFX.POISON_BGP then sawMap = true end
  end
  check("the flicker goes through the rBGP shade map, not a canvas overlay",
        sawMap)
  check("nothing filled the 160x144 UI canvas during the flash", #rects == 0)
  love.graphics.rectangle = realRect

  U.shot(game, "poison_flicker_bug1872.png")
  U.log("walk around with the poisoned CHARIZARD: every fourth step the WHOLE")
  U.log("window should darken for four frames, survey map and letterbox bars")
  U.log("included, not just the 160x144 box in the middle.")
  U.log("white background pixels drop one shade; sprites and dark tiles stay put.")

  while true do
    coroutine.yield()
  end
end
