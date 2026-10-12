package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

-- Minimal LOVE stand-ins: ImageData with paste, Images, Quads with viewports.
local Data = {}
Data.__index = Data
local function newData(w, h, fmt)
  return setmetatable({ w = w, h = h, fmt = fmt or "rgba8", px = {} }, Data)
end
function Data:getDimensions() return self.w, self.h end
function Data:getFormat() return self.fmt end
function Data:paste(src, dx, dy, sx, sy, sw, sh)
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      self.px[(dy + y) * self.w + dx + x] = src.px[(sy + y) * src.w + sx + x]
    end
  end
end

local Image = {}
Image.__index = Image
function Image:getDimensions() return self.data.w, self.data.h end
function Image:setFilter() end

local Quad = {}
Quad.__index = Quad
function Quad:getViewport() return self.x, self.y, self.w, self.h end

local draws = {}
_G.love = {
  image = { newImageData = function(w, h, fmt) return newData(w, h, fmt) end },
  graphics = {
    newImage = function(data) return setmetatable({ data = data }, Image) end,
    newQuad = function(x, y, w, h) return setmetatable({ x = x, y = y, w = w, h = h }, Quad) end,
    draw = function(img, q) draws[#draws + 1] = { img = img, q = q } end,
    setColor = function() end,
    rectangle = function() end,
  },
}

local Faces = require("src.ui.game3.rs.font_faces")

local function sheet(w, h, tag)
  local d = newData(w, h)
  for i = 0, w * h - 1 do d.px[i] = tag .. i end
  return d
end

local W, H = 32, 32
local fg, sh, fixed = sheet(W, H, "f"), sheet(W, H, "s"), sheet(W, H, "x")
local q0 = love.graphics.newQuad(0, 0, 8, 16)
local q1 = love.graphics.newQuad(16, 0, 6, 16)
local b1 = love.graphics.newQuad(16, 0, 3, 16)

local atlas = Faces.pack(fg, sh, fixed, { [0] = q0, [1] = q1 }, { [1] = b1 })
check(atlas ~= nil, "pack builds an atlas from fg, shadow and embedded-colour sheets")
local off = H + 16
local img = atlas.image.data
eq(img.h, 3 * off - 16, "three layers stacked with a gap between them")
eq(img.px[0], "f0", "fg layer copied verbatim at the top")
eq(img.px[off * W + 5], "s5", "shadow layer copied verbatim below the fg")
eq(img.px[2 * off * W + 7], "x7", "embedded-colour layer copied verbatim at the bottom")

local function vp(q) return { q:getViewport() } end
local e = atlas.of[q1]
check(e ~= nil and atlas.of[b1] ~= nil and atlas.of[q0] ~= nil, "every normal and boundary quad is mapped")
local f, s, x = vp(e.fg), vp(e.sh), vp(e.fixed)
check(f[1] == 16 and f[2] == 0 and f[3] == 6 and f[4] == 16, "fg quad keeps the source viewport")
check(s[1] == 16 and s[2] == off and s[3] == 6, "shadow quad is offset by one layer")
check(x[1] == 16 and x[2] == 2 * off and x[3] == 6, "embedded-colour quad is offset by two layers")
eq(vp(atlas.of[b1].fg)[3], 3, "boundary quads keep their 3-px width")

local two = Faces.pack(fg, sh, nil, { [0] = q0 }, {})
check(two and two.image.data.h == 2 * off - 16 and two.of[q0].fixed == nil,
  "a font without embedded colours packs two layers")
check(Faces.pack(fg, sheet(16, 16, "s"), nil, { [0] = q0 }, {}) == nil,
  "mismatched sheets fall back to separate textures")
local other = sheet(W, H, "s")
other.fmt = "r8"
check(Faces.pack(fg, other, nil, { [0] = q0 }, {}) == nil,
  "mismatched formats fall back to separate textures")

-- Every layer of every glyph in a string draws from the one atlas texture.
local FrlgFont = require("src.ui.game3.frlg_font")
local saved = {
  spec = FrlgFont._spec, ver = FrlgFont._syncVersion, faces = FrlgFont._faces,
}
local Runtime = package.loaded["src.core.game3.runtime"]
local GV = require("src.core.GameVersion")
local v = (Runtime and type(Runtime.session) == "table" and Runtime.session.version) or GV.current or ""
FrlgFont._syncVersion, FrlgFont._spec = v, { nativeLayout = "rs" }
local face = {
  name = "normal", nativeIndexed = true,
  fg = love.graphics.newImage(fg), sh = love.graphics.newImage(sh), fixed = love.graphics.newImage(fixed),
  quads = {}, boundaryQuads = {}, widths = {}, height = 16, pitch = 16, letterSpacing = 0,
}
for id = 0, 255 do
  face.quads[id] = love.graphics.newQuad(0, 0, 8, 16)
  face.widths[id] = 6
end
face.atlas = Faces.pack(fg, sh, fixed, face.quads, face.boundaryQuads)
FrlgFont._faces = { normal = face }

local colors = { fg = { 1, 1, 1, 1 }, shadow = { 0, 0, 0, 1 } }
FrlgFont.draw("AB", 0, 0, { colors = colors })
check(#draws == 6, "two glyphs draw shadow, fg and embedded colours: " .. #draws)
local allAtlas = true
for _, d in ipairs(draws) do
  if d.img ~= face.atlas.image then allAtlas = false end
end
check(allAtlas, "every glyph layer draws from the packed atlas (one texture, batchable)")

draws = {}
face.atlas = nil
FrlgFont.draw("A", 0, 0, { colors = colors })
check(#draws == 3 and draws[1].img == face.sh and draws[2].img == face.fg and draws[3].img == face.fixed,
  "without an atlas the separate sheets still draw")

FrlgFont._spec, FrlgFont._syncVersion, FrlgFont._faces = saved.spec, saved.ver, saved.faces
T.finish("game3_rs_font_atlas_test")
