local Faces = {}

local function read(path)
  local Cache = require("src.import.CacheFs")
  return Cache.readActive(path)
end

-- Stack the fg, shadow and embedded-colour sheets in one texture so a
-- string's glyphs share it and LOVE's autobatcher keeps the run in one draw
-- call, as frlg_font's pack_atlas does for the FRLG sheets.  `of` maps each
-- source quad to its { fg, sh, fixed } quads in the atlas; pixels are copied
-- verbatim.  nil (draw from the separate sheets) when the data is missing.
local ATLAS_GAP = 16
function Faces.pack(fgData, shData, fixedData, quads, boundaryQuads)
  if not (fgData and shData and love and love.image and love.graphics) then return nil end
  local ok, atlas = pcall(function()
    local w, h = fgData:getDimensions()
    local sw, shh = shData:getDimensions()
    if sw ~= w or shh ~= h then return nil end
    local fmt = fgData:getFormat()
    if shData:getFormat() ~= fmt or (fixedData and fixedData:getFormat() ~= fmt) then return nil end
    local off = h + ATLAS_GAP
    local data = love.image.newImageData(w, (fixedData and 3 or 2) * off - ATLAS_GAP, fmt)
    data:paste(fgData, 0, 0, 0, 0, w, h)
    data:paste(shData, 0, off, 0, 0, w, h)
    if fixedData then data:paste(fixedData, 0, 2 * off, 0, 0, w, h) end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    local aw, ah = img:getDimensions()
    local of = {}
    local function add(q)
      local qx, qy, qw, qh = q:getViewport()
      of[q] = {
        fg = love.graphics.newQuad(qx, qy, qw, qh, aw, ah),
        sh = love.graphics.newQuad(qx, qy + off, qw, qh, aw, ah),
        fixed = fixedData and love.graphics.newQuad(qx, qy + 2 * off, qw, qh, aw, ah) or nil,
      }
    end
    for _, q in pairs(quads) do add(q) end
    for _, q in pairs(boundaryQuads) do add(q) end
    return { image = img, of = of }
  end)
  return ok and atlas or nil
end

-- pokeruby/src/text.c:2676
function Faces.load(spec, name, language, loadImage, loadTable, palette, textMode)
  local id = assert(spec.faces[name], "unknown RS font face").id
  local stem = "rs_" .. language .. "_" .. id
  local manifest = assert(loadTable(spec.manifest), "RS native font manifest missing")
  local info = assert(manifest.fonts[stem], "RS native font manifest lacks " .. stem)
  assert(manifest.layout == "rs" and info.id == id and info.language == language, "RS native font identity")
  local dir = spec.dir
  local widths = assert(loadTable(dir .. stem .. "_widths.lua"), "RS native font widths missing")
  local monospace = textMode == 1
  if info.bpp == 1 and not monospace then
    stem = assert(info.variableStem, "RS variable-width font missing; re-import selected ROM")
  end
  local fg, _, fgData = loadImage({ { path = dir .. stem .. "_fg.rgba", w = info.width, h = info.height } })
  local sh, _, shData = loadImage({ { path = dir .. stem .. "_shadow.rgba", w = info.width, h = info.height } })
  local indices = read(dir .. stem .. ".idx")
  assert(fg and sh and widths and indices and #indices == info.width * info.height, "RS font assets missing for " .. stem)
  local fixed, present = {}, false
  for p = 1, #indices do
    local value = indices:byte(p)
    if value > 0 and value < 14 then
      local c = assert(palette[value], "RS embedded font color missing")
      fixed[p] = string.char(math.floor(c[1] * 255 + .5), math.floor(c[2] * 255 + .5), math.floor(c[3] * 255 + .5), 255)
      present = true
    else
      fixed[p] = "\0\0\0\0"
    end
  end
  local fixedImage, fixedData
  if present then
    fixedData = love.image.newImageData(info.width, info.height, "rgba8", table.concat(fixed))
    fixedImage = love.graphics.newImage(fixedData)
    fixedImage:setFilter("nearest", "nearest")
  end
  local quads, boundaryQuads = {}, {}
  for glyph = 0, info.glyphs - 1 do
    local width = assert(widths[glyph], "native RS glyph width missing")
    local drawWidth = monospace and 8 or (info.bpp == 1 and width == 3 and 4 or width)
    quads[glyph] = love.graphics.newQuad(glyph % 16 * 16, math.floor(glyph / 16) * 16, math.min(drawWidth, 8), 16, info.width, info.height)
    if not monospace and info.bpp == 1 and width == 3 then
      boundaryQuads[glyph] = love.graphics.newQuad(glyph % 16 * 16, math.floor(glyph / 16) * 16, 3, 16, info.width, info.height)
    end
    if monospace then widths[glyph] = 8 end
  end
  return {
    name = name, language = language, nativeIndexed = true,
    fg = fg, sh = sh, fixed = fixedImage, quads = quads, boundaryQuads = boundaryQuads, widths = widths,
    height = 16, pitch = 16, letterSpacing = 0, glyphs = info.glyphs,
    fgData = fgData, shData = shData,
    atlas = Faces.pack(fgData, shData, fixedData, quads, boundaryQuads),
  }
end

return Faces
