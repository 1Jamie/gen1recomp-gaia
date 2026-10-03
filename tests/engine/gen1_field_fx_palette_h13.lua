package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness").suite("Gen1 field FX palette H13")
local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local Assets = require("src.render.Assets")
local Game = require("src.core.Game")
local OW = os.getenv("H13_OVERWORLD_SOURCE")
  and assert(loadfile(os.getenv("H13_OVERWORLD_SOURCE")))()
  or require("src.world.OverworldController")
local ImageWriter = require("src.import.ImageWriter")
local Renderer = require("src.render.Renderer")
local GbcPalette = require("src.render.GbcPalette")
local Tilt = require("src.render.Tilt")
local Pipelines = require("src.render.Pipelines")
local actualFixture
if os.getenv("H13_ACTUAL_FIXTURE") then
  local file = assert(io.open(os.getenv("H13_ACTUAL_FIXTURE"),"rb"))
  actualFixture = assert(require("src.link.Json").decode(file:read("*a")))
  file:close()
end

local bytes = {
  smoke = {0,24,26,102,4,66,11,129,86,137,26,46,76,18,56,56},
  fishingRod = {24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,
    192,192,240,240,60,60,15,15,3,3,0,0,0,0,0,0,
    2,2,7,5,7,5,141,139,237,235,222,214,184,184,96,96},
  redTree = {170,0,65,20,168,106,85,124,162,198,87,103,239,255,93,127,
    170,40,213,252,162,214,73,227,226,214,85,236,236,126,189,88,
    172,47,66,23,170,66,86,2,165,12,90,12,166,15,81,7,
    42,224,85,192,234,64,213,64,106,48,213,56,104,242,149,224},
  yellowTree = {170,0,65,20,168,106,85,124,130,254,87,127,239,255,93,127,
    170,40,213,252,162,254,85,255,250,254,85,252,236,126,189,88,
    172,47,66,23,170,66,86,2,165,12,90,12,166,15,81,7,
    42,224,85,192,234,64,213,64,106,48,213,56,104,242,149,224},
}

local ID = {}; ID.__index = ID
function ID:getDimensions() return self.w, self.h end
function ID:getWidth() return self.w end
function ID:getHeight() return self.h end
function ID:getPixel(x, y) return unpack(self.p[y * self.w + x + 1] or {0,0,0,0}) end
function ID:setPixel(x, y, ...) self.p[y * self.w + x + 1] = {...} end
function ID:mapPixel(fn)
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do self:setPixel(x, y, fn(x, y, self:getPixel(x, y))) end
  end
end
function ID:setFilter() end
local function imageData(w, h) return setmetatable({w = w, h = h, p = {}}, ID) end
local paths, draws, allocations, tint, shader = {}, {}, 0, {1,1,1,1}, nil
love.image.newImageData = function(a, b)
  if type(a) == "number" then return imageData(a, b) end
  local source = assert(paths[a], "missing fixture " .. tostring(a))
  local out = imageData(source.w, source.h)
  for y = 0, source.h - 1 do
    for x = 0, source.w - 1 do out:setPixel(x, y, source:getPixel(x, y)) end
  end
  return out
end
love.graphics.newImage = function(a)
  allocations = allocations + 1
  return type(a) == "string" and love.image.newImageData(a) or a
end
love.graphics.newShader = function() return {send = function(self, key, ...) self[key] = {...} end} end
love.graphics.setShader = function(s) shader = s end
love.graphics.getShader = function() return shader end
love.graphics.setColor = function(...) tint = {...} end
love.graphics.draw = function(image, ...)
  draws[#draws + 1] = {image = image, args = {...}, alpha = tint[4], shader = shader}
end

local function upvalue(fn, wanted)
  for i = 1, 100 do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then return value end
  end
end
local fx = {
  dust = assert(upvalue(OW.drawWorld, "fxDust")),
  tree = assert(upvalue(OW.drawWorld, "fxCutTree")),
  rod = assert(upvalue(OW.drawWorld, "fxRod")),
}
for i = 1, 100 do
  local name = debug.getupvalue(fx.dust, i)
  if name == "Game" then debug.setupvalue(fx.dust, i, Game); break end
end

local definitions = {
  smoke = {path = "assets/generated/fx/h13_smoke.png", w = 8, h = 8},
  cutTree = {path = "assets/generated/fx/h13_tree.png", w = 16, h = 16},
  fishingRod = {path = "assets/generated/fx/h13_rod.png", w = 8, h = 24},
}
local function fixtures(version, transparent)
  for key, def in pairs(definitions) do
    local raw = key == "cutTree" and bytes[version == "yellow" and "yellowTree" or "redTree"] or bytes[key]
    local cached = actualFixture and actualFixture[version].images[key]
    if cached then
      T.eq(table.concat(raw,","),table.concat(cached.raw,","),version .. " " .. key .. " pinned art matches approved ROM bytes")
      raw = cached.raw
    end
    local image = ImageWriter.decode2bpp(raw, def.w, def.h, transparent)
    if cached and not transparent then
      for y = 0,def.h-1 do for x = 0,def.w-1 do
        local c = cached.pixels[y*def.w+x+1]
        image:setPixel(x,y,c[1]/255,c[2]/255,c[3]/255,c[4]/255)
      end end
    end
    image.raw = raw
    paths[def.path] = image
  end
end
local function state()
  return setmetatable({
    map = {id = "PALLET_TOWN", def = {tileset = "OVERWORLD"}, renderer = {
      gbcAtlas = true, drawBorderFill = function() end, draw = function() end,
    }}, camera = {x = 3, y = 5}, ghosts = {}, entities = {}, neighbors = {},
    player = {px = 32, py = 48, cellY = 3, fishShakeDy = 1,
      sprite = {getScreenOrigin = function(_, x, y, cx, cy) return x - cx - 2, y - cy - 6 end}},
    screenPaletteName = function() return "ROUTE" end,
    poisonShadeMap = function() return nil end,
    drawShipAnim = function() end,
  }, {__index = OW})
end
Game.data = {field = {overworldFx = definitions}, palettes = {palettes = {ROUTE = PaletteFX.GRAYS}}, maps = {}}
Game.renderer = {worldViewSize = function() return 160,144 end,
  playfieldRect = function() return 0,0,160,144 end, fitScale = function() return 1 end,
  setWorldOverride = function() end, beginUprightPass = function() end, endUprightPass = function() end}
Game.stack = {top = function() end, states = {}}

local cases = {
  {name = "boulder", key = "smoke", group = 7, fn = fx.dust,
    setup = function(s) s:startDustAnim(2,3,nil,"right"); s.dustAnim.faded = false end, count = 4},
  {name = "cut dust", key = "smoke", group = 6, fn = fx.dust,
    setup = function(s) s:startDustAnim(2,3) end, count = 4},
  {name = "tree", key = "cutTree", group = 6, fn = fx.tree,
    setup = function(s) s:startCutTreeAnim(2,3); s.cutAnim.frames = 6 end, count = 2},
}
local oam = {down = {4,15,0}, up = {4,-8,0}, left = {-8,4,1}, right = {16,4,1,true}}
for _, dir in ipairs({"down", "up", "left", "right"}) do
  cases[#cases + 1] = {name = "rod " .. dir, key = "fishingRod", group = 0, fn = fx.rod,
    setup = function(s) s.fishing = {facing = dir} end, count = 1, dir = dir}
end
local function render(s, case)
  s.dustAnim, s.cutAnim, s.fishing = nil, nil, nil
  case.setup(s); draws = {}; shader = nil; case.fn(s, s.camera)
  return draws
end
local function sameRGB(a, b)
  return math.abs(a[1] - b[1]) < .00001 and math.abs(a[2] - b[2]) < .00001
    and math.abs(a[3] - b[3]) < .00001
end
local function palettePixels(rows, case, colors, label)
  local source = paths[definitions[case.key].path]
  local wrong, opaqueZero, invisibleNonzero, visible = 0, 0, 0, 0
  for _, row in ipairs(rows) do
    local q = type(row.args[1]) == "table" and row.args[1]
    for y = q and q.y or 0, (q and q.y or 0) + (q and q.h or source.h) - 1 do
      for x = q and q.x or 0, (q and q.x or 0) + (q and q.w or source.w) - 1 do
        local r = source:getPixel(x, y)
        local p = {row.image:getPixel(x, y)}
        if r > .83 then
          if p[4] ~= 0 then opaqueZero = opaqueZero + 1 end
        else
          local c = colors[r > .5 and 2 or r > .17 and 3 or 4]
          if not sameRGB(p, {c[1]/255,c[2]/255,c[3]/255}) then wrong = wrong + 1 end
          if p[4] ~= 1 then invisibleNonzero = invisibleNonzero + 1 end
          visible = visible + 1
        end
      end
    end
    T.eq(row.shader, nil, label .. " no extra effect shader")
  end
  T.eq(wrong, 0, label .. " exact assigned nonzero RGB")
  T.eq(opaqueZero, 0, label .. " source color zero keyed")
  T.eq(invisibleNonzero, 0, label .. " visible colors retain alpha")
  T.check(visible > 0, label .. " nonempty actual ROM-art pixels")
end
local function geometry(rows, case, label)
  T.eq(#rows, case.count, label .. " draw count")
  local a = rows[1].args
  if case.dir then
    local def = oam[case.dir]
    T.eq(a[1].x, 0, label .. " quad x")
    T.eq(a[1].y, def[3] * 8, label .. " correct used tile")
    T.eq(a[1].w, 8, label .. " quad width")
    T.eq(a[1].h, 8, label .. " quad height")
    T.eq(a[2], 32-3-2+def[1]+(def[4] and 8 or 0), label .. " anchored x")
    T.eq(a[3], 48-5-6+def[2]+1, label .. " anchored y and shake")
    T.eq(a[5], def[4] and -1 or nil, label .. " right XFLIP only")
  elseif case.key == "cutTree" then
    T.eq(a[1].y, 0, label .. " top quad")
    T.eq(rows[2].args[1].y, 8, label .. " bottom quad")
    T.eq(a[2], 31, label .. " top split x")
    T.eq(rows[2].args[2], 27, label .. " bottom split x")
    T.eq(a[3], 43, label .. " top y")
    T.eq(rows[2].args[3], 51, label .. " bottom y")
  else
    local x = case.group == 7 and 28 or 29
    T.eq(a[1], x, label .. " first x with boulder slide")
    T.eq(a[2], 43, label .. " first y")
    T.eq(rows[4].args[1], x+8, label .. " tiled second column")
    T.eq(rows[4].args[2], 51, label .. " tiled second row")
  end
  T.eq(rows[1].alpha, 1, label .. " lit beat tint")
end

for _, transparent in ipairs({false, true}) do
  Assets.invalidate()
  local s = state()
  local editionImages = {}
  for _, version in ipairs({"red", "blue", "yellow"}) do
    GameVersion.set(version); fixtures(version, transparent)
    PaletteFX.setMode("redpp"); PaletteFX.setShadeMap(nil); PaletteFX.setDarkWorld(false)
    for _, case in ipairs(cases) do
      local label = version .. (transparent and " current decoder " or " opaque cache ") .. case.name
      local rows = render(s, case)
      palettePixels(rows, case, PaletteFX.worldPack().spritePalettes[case.group], label)
      geometry(rows, case, label)
      local lit = rows[1].image
      local before = allocations
      T.eq(render(s, case)[1].image, lit, label .. " repeated draw cache")
      T.eq(allocations, before, label .. " repeated draw allocates no image")
      PaletteFX.setDarkWorld(true)
      local dark = render(s, case)[1].image
      T.check(dark ~= lit, label .. " dark cache differs")
      palettePixels(draws, case, PaletteFX.darkObp(PaletteFX.worldPack().spritePalettes[case.group],case.group), label .. " dark")
      PaletteFX.setDarkWorld(false)
      T.eq(render(s, case)[1].image, lit, label .. " Flash restores lit cached bake")
      for _, mode in ipairs({"og", "gbc", "ogred"}) do
        PaletteFX.setMode(mode)
        rows = render(s, case)
        local raw = s[case.key == "smoke" and "smokeImg" or case.key == "cutTree" and "cutTreeImg" or "rodImg"]
        T.eq(rows[1].image, raw, label .. " " .. mode .. " retains raw image")
        geometry(rows, case, label .. " " .. mode)
        draws = {}; shader = nil
        setmetatable({}, {__index = Renderer}):blitCanvas(raw,1,1,s:sgbWorldZones(),1,1,0,0,0,0,160,144,1,1)
        T.check(draws[1].shader ~= nil,label .. " " .. mode .. " retains final world palette shader")
      end
      PaletteFX.setMode("redpp")
      rows = render(s, case)
      palettePixels(rows, case, PaletteFX.worldPack().spritePalettes[case.group], label .. " return to Advanced")
      draws = {}; shader = nil
      setmetatable({}, {__index = Renderer}):blitCanvas(rows[1].image,1,1,s:sgbWorldZones(),1,1,0,0,0,0,160,144,1,1)
      T.eq(draws[1].shader,nil,label .. " Advanced final pass does not recolor the bake")
      editionImages[version .. case.name] = lit
      if version ~= "red" then
        T.check(lit ~= editionImages["red" .. case.name], label .. " edition cache does not alias Red")
      end
    end
    draws = {}; s.fishing = {facing = "right", hideRod = true}; fx.rod(s, s.camera)
    T.eq(#draws, 0, version .. " hidden rod draws nothing")
    for _, case in ipairs({cases[1], cases[2], cases[3]}) do
      render(s, case)
      if case.key == "cutTree" then s.cutAnim.frames = 5
      elseif s.dustAnim.boulder then s.dustAnim.faded = true
      else s.dustAnim.frames = 28 end
      draws = {}; case.fn(s, s.camera)
      T.eq(draws[1].alpha, .55, version .. " " .. case.name .. " flicker tint preserved")
    end
  end
end

Assets.invalidate(); PaletteFX.setMode("redpp")
local sharedState, priorTree = state(), nil
for _, version in ipairs({"red", "blue", "yellow", "red"}) do
  GameVersion.set(version); fixtures(version, false)
  local row = render(sharedState, cases[3])[1]
  palettePixels({row}, cases[3], PaletteFX.worldPack().spritePalettes[6], "edition switch without image invalidation " .. version)
  if priorTree then T.check(row.image ~= priorTree, "edition switch does not reuse a different edition bake") end
  priorTree = row.image
end

GameVersion.set("yellow"); Assets.invalidate(); fixtures("yellow", false)
PaletteFX.setMode("redpp"); PaletteFX.setDarkWorld(false)
local s = state()
s:startDustAnim(2,3,nil,"right"); s.dustAnim.faded = false
s:startCutTreeAnim(2,3); s.cutAnim.frames = 6; s.fishing = {facing = "right"}
local realTilt, realGround, realPipeline, realDraw = Tilt.active, Tilt.groundPoint, Pipelines.worldPipeline, Pipelines.drawWorld
local selected = "flat"
Tilt.active = function() return selected == "tilt" end
Tilt.groundPoint = function(x,y) return x,y end
Pipelines.worldPipeline = function() return selected == "pipeline" and "h13" or nil end
Pipelines.drawWorld = function(_, ctx)
  T.eq(ctx.spriteColors(), nil, "Advanced pipeline has no blanket color shader")
  ctx.drawFx(function(x,y) return x-s.camera.x,y-s.camera.y end, 1)
  return true
end
for _, path in ipairs({"flat", "tilt", "pipeline"}) do
  selected = path; draws = {}; shader = nil; s:drawWorld()
  T.eq(#draws, 7, path .. " actual world path draws dust/tree/rod exactly once")
  palettePixels({draws[1]}, cases[1], PaletteFX.worldPack().spritePalettes[7], path .. " dust")
  palettePixels({draws[5],draws[6]}, cases[3], PaletteFX.worldPack().spritePalettes[6], path .. " tree")
  palettePixels({draws[7]}, cases[7], PaletteFX.worldPack().spritePalettes[0], path .. " rod")
end
Tilt.active, Tilt.groundPoint, Pipelines.worldPipeline, Pipelines.drawWorld = realTilt, realGround, realPipeline, realDraw

local originalPack = PaletteFX.worldPack
local treeColors = originalPack().spritePalettes[6]
local permuted = {treeColors[1],treeColors[1],treeColors[1],treeColors[3]}
PaletteFX.worldPack = function() return {spritePalettes = {[6] = permuted}} end
Assets.invalidate()
palettePixels(render(state(), cases[3]), cases[3], permuted, "source key precedes palette permutation to color zero")
PaletteFX.worldPack = originalPack
Assets.invalidate(); fixtures("yellow", true)

local fadeState = state()
for _, dark in ipairs({false, true}) do
  PaletteFX.setDarkWorld(dark)
  for _, byte in ipairs({0xE4,0xF9,0xFE,0xFF}) do
    local uniforms = fadeState:warpFadeUniforms(byte)
    T.check(uniforms and uniforms.count > 0, "actual Advanced fade uniforms exist")
    for _, case in ipairs({cases[1],cases[3],cases[7]}) do
      local colors = PaletteFX.darkObp(originalPack().spritePalettes[case.group],case.group)
      local rows = render(fadeState, case)
      palettePixels(rows, case, colors, "pre-fade bake " .. case.name)
      for shade = 2,4 do
        local src = {colors[shade][1]/255,colors[shade][2]/255,colors[shade][3]/255}
        local destination
        for i = 1,uniforms.count do
          if sameRGB(src, uniforms.src[i]) then destination = uniforms.dst[i]; break end
        end
        T.check(destination, "existing world fade recognizes effect palette " .. case.group .. " shade " .. shade)
        local index = math.floor(byte / 4^(shade-1)) % 4 + 1
        local expected = colors[index]
        T.check(destination and sameRGB(destination, {expected[1]/255,expected[2]/255,expected[3]/255}),
          "actual fade output matches register byte for effect " .. case.group .. " shade " .. shade)
      end
    end
  end
end
PaletteFX.setDarkWorld(false); PaletteFX.setShadeMap(nil); PaletteFX.setMode("gbc")
T.finish()
