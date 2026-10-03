return function(game)
  local U = require("tests.drivers.util")
  local GameVersion = require("src.core.GameVersion")
  local PaletteFX = require("src.render.PaletteFX")
  local GbcPalette = require("src.render.GbcPalette")
  local Tilt = require("src.render.Tilt")
  local Pipelines = require("src.render.Pipelines")
  local OW = require("src.world.OverworldController")
  local Assets = require("src.render.Assets")
  local Transition = require("src.render.Transition")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/h13-field-fx"
  local version = GameVersion.get()
  local failures = 0
  local function check(ok, label)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    U.log(failures == 0 and "PASS H13 native field FX palette" or "FAIL H13 native field FX palette", version)
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end
  local ready = false
  for _ = 1,600 do
    if game.data and game.data.field and game.data.field.overworldFx and game.stack
       and game.renderer and game.save and game.input then ready = true; break end
    U.wait(1)
  end
  if not check(ready and GameVersion.generation() == 1, "Gen1 imported field FX ready") then return finish() end
  local function upvalue(fn, wanted)
    for i = 1,100 do
      local name, value = debug.getupvalue(fn,i)
      if not name then break end
      if name == wanted then return value end
    end
  end
  local fx = {dust = assert(upvalue(OW.drawWorld,"fxDust")),
    tree = assert(upvalue(OW.drawWorld,"fxCutTree")), rod = assert(upvalue(OW.drawWorld,"fxRod"))}
  PaletteFX.setCustomRamp(nil)
  GbcPalette.setMode("gbc")
  Tilt.applyOptions({tilt = 0})
  Pipelines.reset()
  PaletteFX.setMode("redpp")
  U.teleport(game,"PALLET_TOWN",10,8,"right")
  local function settled(mapId)
    for _ = 1,300 do
      local ow = game.overworld
      if ow and ow.map and ow.map.id == mapId and ow.map.renderer and ow.map.renderer.gbcAtlas
         and game.stack:top() == ow and not ow.player.moving then return true end
      U.wait(1)
    end
    return false
  end
  if not check(settled("PALLET_TOWN"), "settled Advanced map and field stack") then return finish() end
  local function pose(dir, cutDust, faded)
    local ow = game.overworld
    local p = ow.player
    p.facing = dir or "right"; p.fishing = true; p.fishShakeDy = 0
    ow.fishing = {facing = p.facing}
    ow:startCutTreeAnim(p.cellX-2,p.cellY)
    ow.cutAnim.frames = 4
    if cutDust then ow:startDustAnim(p.cellX+2,p.cellY)
    else ow:startDustAnim(p.cellX+2,p.cellY,nil,"right") end
    if ow.dustAnim.boulder then ow.dustAnim.faded = faded or false
    elseif faded then ow.dustAnim.frames = 28 end
    return ow
  end
  local function shot(name)
    local ow = game.overworld
    if not check(ow and ow.map and ow.player and not ow.player.moving and game.stack:top() == ow,
                 name .. " settled field target") then return end
    check(U.still(game,DIR .. "/h13-" .. version .. "-" .. name .. ".png"), name .. " captured")
  end
  local function pixelCheck(fn, key, group, label)
    local ow = game.overworld
    local G = love.graphics
    local first, draws = nil, 0
    local draw = G.draw
    local target = G.newCanvas(256,256)
    G.push("all"); G.origin(); G.setCanvas(target); G.clear(0,0,0,0); G.setShader()
    G.draw = function(image, ...)
      first = first or image; draws = draws+1; return draw(image,...)
    end
    local ok, err = pcall(fn,ow,ow.camera)
    G.draw = draw; G.pop()
    target:release()
    if not check(ok and first, label .. " actual FX draw " .. tostring(err)) then return end
    local w,h = first:getDimensions()
    local canvas = G.newCanvas(w,h)
    G.push("all"); G.origin(); G.setCanvas(canvas); G.clear(0,0,0,0); G.setShader()
    G.setColor(1,1,1,1); G.setBlendMode("alpha","alphamultiply"); G.draw(first,0,0); G.pop()
    local actual = canvas:newImageData()
    local source = Assets.imageData(game.data.field.overworldFx[key].path)
    local colors = PaletteFX.darkObp(PaletteFX.worldPack().spritePalettes[group],group)
    local wrong, opaqueZero, visible = 0,0,0
    for y = 0,h-1 do for x = 0,w-1 do
      local r = source:getPixel(x,y)
      local rr,gg,bb,aa = actual:getPixel(x,y)
      if r > .83 then
        if aa > .01 then opaqueZero = opaqueZero+1 end
      else
        local c = colors[r > .5 and 2 or r > .17 and 3 or 4]
        if math.abs(rr-c[1]/255) > .01 or math.abs(gg-c[2]/255) > .01
           or math.abs(bb-c[3]/255) > .01 or math.abs(aa-1) > .01 then wrong = wrong+1 end
        visible = visible+1
      end
    end end
    check(wrong == 0 and visible > 0,label .. " exact GPU palette RGB/alpha")
    check(opaqueZero == 0,label .. " source color zero transparent")
    check(draws == (key == "smoke" and 4 or key == "cutTree" and 2 or 1),label .. " actual draw count")
    local pixels = actual:getString()
    source:release(); actual:release(); canvas:release()
    return pixels
  end

  pose("right")
  pixelCheck(fx.tree,"cutTree",6,"Advanced tree")
  pixelCheck(fx.dust,"smoke",7,"Advanced boulder dust")
  pixelCheck(fx.rod,"fishingRod",0,"Advanced rod")
  shot("advanced-boulder-tree-rod-right")
  pose("right",true)
  pixelCheck(fx.dust,"smoke",6,"Advanced Cut dust")
  shot("advanced-cut-dust-tree-rod-right")
  pose("right",false,true)
  game.overworld.cutAnim.frames = 5
  shot("advanced-existing-flicker")
  for _,dir in ipairs({"down","up","left"}) do pose(dir); shot("advanced-rod-" .. dir) end
  pose("right"); game.overworld.fishing.hideRod = true
  shot("advanced-hidden-rod")

  local darkMap = "ROCK_TUNNEL_1F"
  local listed = false
  for _, id in ipairs(game.data.field.darkMaps and game.data.field.darkMaps.maps or {}) do
    if id == darkMap then listed = true end
  end
  if not check(listed, "actual imported dark map listed") then return finish() end
  game.save.flashLit = nil
  U.teleport(game,darkMap,15,5,"right")
  if not check(settled(darkMap), "settled actual dark map and renderer") then return finish() end
  if not check(game.overworld.dark == true and PaletteFX.darkWorld() == true,
               "actual cave darkness armed before GPU checks") then return finish() end
  pose("right")
  local darkTree = pixelCheck(fx.tree,"cutTree",6,"dark tree")
  local darkDust = pixelCheck(fx.dust,"smoke",7,"dark boulder dust")
  local darkRod = pixelCheck(fx.rod,"fishingRod",0,"dark rod")
  shot("advanced-dark")
  check(game.overworld:useFlashFieldMove(),"actual Flash field callback started")
  local flashed = false
  for _ = 1,300 do
    local ow = game.overworld
    if game.stack:top() == ow and ow.map.id == darkMap and ow.dark == false
       and PaletteFX.darkWorld() == false and game.save.flashLit == true then flashed = true; break end
    if game.stack:top() ~= ow then U.tap(game,"a") end
    U.wait(3)
  end
  if not check(flashed and settled(darkMap),"actual Flash completed on same cave") then return finish() end
  if not check(game.overworld.dark == false and PaletteFX.darkWorld() == false,
               "actual Flash restored lit cave before GPU checks") then return finish() end
  pose("right")
  local litTree = pixelCheck(fx.tree,"cutTree",6,"Flash-restored tree")
  local litDust = pixelCheck(fx.dust,"smoke",7,"Flash-restored boulder dust")
  local litRod = pixelCheck(fx.rod,"fishingRod",0,"Flash-restored rod")
  check(darkTree and litTree and darkTree ~= litTree,"tree GPU pixels change after actual Flash")
  check(darkDust and litDust and darkDust ~= litDust,"dust GPU pixels change after actual Flash")
  check(darkRod and litRod and darkRod ~= litRod,"rod GPU pixels change after actual Flash")
  pose("right"); shot("advanced-flash-restored")
  U.teleport(game,"PALLET_TOWN",10,8,"right")
  if not check(settled("PALLET_TOWN") and game.overworld.dark == false and PaletteFX.darkWorld() == false,
               "settled lit Pallet restored before tilt fade and modes") then return finish() end
  Tilt.applyOptions({tilt = 2})
  pose("right"); shot("advanced-tilt")
  Tilt.applyOptions({tilt = 0})

  pose("right")
  local fade = Transition.new(game,nil,nil,true)
  fade.t = 8
  check(fade:bgp() == 0xF9,"actual held fade step F9")
  game.stack:push(fade)
  check(game.overworld:warpFadeUniforms(fade:bgp()) ~= nil,"existing fade recognizes all effect palettes")
  local drawFade, paletteHandoffs = fade.draw, 0
  fade.draw = function(self, ...)
    if self.paletteStepped then paletteHandoffs = paletteHandoffs + 1 end
    return drawFade(self, ...)
  end
  check(U.still(game,DIR .. "/h13-" .. version .. "-advanced-held-fade-f9.png"),"intentional held fade-step capture")
  fade.draw = nil
  check(paletteHandoffs > 0,"actual Advanced world fade consumer ran")
  game.stack:pop()

  for _,mode in ipairs({"og","gbc","ogred","redpp"}) do
    PaletteFX.setMode(mode)
    local ow = pose("right")
    check(mode ~= "redpp" or ow.map.renderer.gbcAtlas,"mode target rebuilt")
    shot("mode-" .. mode)
  end
  finish()
end
