-- Hot-path caches and the bugs fixed alongside them: Font's encode/width
-- memo, PaletteFX/GbcPalette last-sent uniform detection, SpriteRenderer's
-- obp bake lookup, Hooks' unwrap of the last link, Sandbox's per-name
-- verdict, Input's recycled step tables and stale-pad rebuild, and
-- TextBox's scroll slide running on the logic step instead of draw.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Logger"] = {
  info = function() end, warn = function() end, error = function() end,
  debug = function() end,
}

-- ------------------------------------------------------------- Font
do
  local Font = require("src.render.Font")
  local a = Font.encode("ABC")
  a[1], a[4] = -1, -2
  local b = Font.encode("ABC")
  eq(#b, 3, "encode hands out a copy: a caller's append does not stick")
  check(b[1] ~= -1, "encode hands out a copy: a caller's write does not stick")
  check(a ~= b, "each encode is a fresh table")
  eq(Font.glyphCount("ABC"), #Font.split("ABC"), "glyphCount matches split")
  local w = Font.width("ABC")
  eq(Font.width("ABC"), w, "cached width is stable")
  local rev = Font.revision
  Font.setFrame(Font.frameIndex())
  eq(Font.revision, rev, "re-selecting the same frame keeps the caches")
  Font.setFrame(Font.frameIndex() + 1)
  check(Font.revision > rev, "a frame change drops cached widths")
  Font.setFrame(1)
end

-- ------------------------------------------------------------- PaletteFX
local function recordingShader()
  local sh = { sends = {} }
  function sh.send(self, name, value)
    self.sends[#self.sends + 1] = { name = name, value = { value[1], value[2], value[3] } }
  end
  return sh
end

do
  local PaletteFX = require("src.render.PaletteFX")
  PaletteFX.pickerActive = function() return false end
  local pal = { { 255, 0, 0 }, { 0, 255, 0 }, { 0, 0, 255 }, { 0, 0, 0 } }
  local sh = recordingShader()

  PaletteFX.mode = "gbc"
  PaletteFX.sendColors(sh, pal)
  eq(#sh.sends, 4, "first send sets all four colors")
  PaletteFX.sendColors(sh, pal)
  eq(#sh.sends, 4, "identical colors to the same shader are not re-sent")
  local changed = { pal[1], pal[2], { 10, 20, 30 }, pal[4] }
  PaletteFX.sendColors(sh, changed)
  eq(#sh.sends, 5, "only the changed uniform is re-sent")
  eq(sh.sends[5].name, "c2", "and it is the one that changed")

  local other = recordingShader()
  PaletteFX.sendColors(other, changed)
  eq(#other.sends, 4, "the record is per shader")

  PaletteFX.forgetSent(sh)
  PaletteFX.sendColors(sh, changed)
  eq(#sh.sends, 9, "forgetSent makes the next send go out in full")

  PaletteFX.sendShades(sh, pal)
  PaletteFX.sendColors(sh, changed)
  eq(sh.sends[#sh.sends].name, "c2", "sendShades shares the record with sendColors")

  -- the index arithmetic must land on exactly what effectiveColors resolves
  local function lastFour(s)
    local out = {}
    for i = #s.sends, 1, -1 do
      local e = s.sends[i]
      local k = tonumber(e.name:sub(2)) + 1
      if not out[k] then out[k] = e.value end
    end
    return out
  end
  for _, mode in ipairs({ "gbc", "gbc_inv", "og", "og_inv", "classic" }) do
    for _, map in ipairs({ false, PaletteFX.DARK_BGP, PaletteFX.POISON_BGP }) do
      PaletteFX.mode = mode
      PaletteFX.setShadeMap(map or nil)
      local s = recordingShader()
      PaletteFX.sendColors(s, pal)
      local want = PaletteFX.effectiveColors(pal)
      local got = lastFour(s)
      local same = true
      for i = 1, 4 do
        for c = 1, 3 do
          if math.abs(got[i][c] - want[i][c] / 255) > 1e-12 then same = false end
        end
      end
      check(same, ("sendColors matches effectiveColors (%s, map %s)")
        :format(mode, tostring(map and true)))
    end
  end
  PaletteFX.mode = "gbc"
  PaletteFX.setShadeMap(nil)
end

-- ------------------------------------------------------------- GbcPalette
do
  local GbcPalette = require("src.render.GbcPalette")
  local sh = recordingShader()
  love.graphics.newShader = function() return sh end
  love.graphics.setShader = function() end
  local pal = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 } }
  check(GbcPalette.useRaw(pal), "useRaw binds")
  eq(#sh.sends, 4, "useRaw sends pal0..pal3 once")
  GbcPalette.useRaw(pal)
  eq(#sh.sends, 4, "an unchanged palette is not re-sent")
  GbcPalette.useRaw({ pal[1], { 1, 2, 3 }, pal[3], pal[4] })
  eq(#sh.sends, 5, "one changed entry is one send")
  eq(sh.sends[5].name, "pal1", "to the changed uniform")
end

-- ------------------------------------------------------------- SpriteRenderer
do
  local Assets = require("src.render.Assets")
  local loads = 0
  Assets.image = function() loads = loads + 1; return { tag = loads } end
  local SpriteRenderer = require("src.render.SpriteRenderer")
  SpriteRenderer.invalidate()
  local savedImage = love.image
  love.image = nil -- headless bake path
  local colors = { {}, {}, {}, {} }
  local one = SpriteRenderer.obpImage("sheet.png", colors, 1)
  eq(SpriteRenderer.obpImage("sheet.png", colors, 1), one, "a cache hit returns the bake")
  eq(SpriteRenderer.obpImage("sheet.png", colors, "1"), one,
    "number and string groups share a key, as the concatenated key did")
  check(SpriteRenderer.obpImage("sheet.png", colors, "dark") ~= nil, "a new group bakes")
  SpriteRenderer.invalidate()
  check(SpriteRenderer.obpImage("sheet.png", colors, 1) ~= one, "invalidate drops the lookup too")
  love.image = savedImage
end

-- ------------------------------------------------------------- Hooks
do
  local Hooks = require("src.mods.Hooks")
  local h = Hooks.new()
  local unwrap = h:wrap("x", function(next, v) return next(v + 1) end)
  eq(h:call("x", function(v) return v * 2 end, 1), 4, "a single link runs")
  unwrap()
  eq(h.chains.x, nil, "unwrapping the last link drops the chain (wantsHook false)")
  eq(h:call("x", function(v) return v * 2 end, 1), 2, "and the call is plain vanilla")
  local u1 = h:wrap("y", function(next, ...) return next(...) end)
  local u2 = h:wrap("y", function(next, ...) return next(...) end)
  u1()
  check(h.chains.y ~= nil, "a chain with links left stays")
  u2()
  eq(h.chains.y, nil, "and goes once empty")
  local stale = h:wrap("z", function(next, ...) return next(...) end)
  h:removeOwner(nil)
  h.chains.z = nil
  local fresh = h:wrap("z", function(next, ...) return next(...) end)
  stale()
  check(h.chains.z ~= nil, "a stale unwrap never drops a newer chain")
  fresh()
  local ok, err = pcall(function()
    return h:call("none", function() error("boom", 0) end)
  end)
  check(not ok and err == "boom", "vanilla errors propagate without a chain")
  h:wrap("w", function(next, ...) return next(...) end)
  ok, err = pcall(function()
    return h:call("w", function() error("deep", 0) end)
  end)
  check(not ok and err == "deep", "vanilla errors propagate through a chain unwrapped")
  local n, a, b, c = select("#", h:call("w", function() return 1, nil, 3 end)),
    h:call("w", function() return 1, nil, 3 end)
  eq(n, 3, "trailing results keep their count")
  check(a == 1 and b == nil and c == 3, "and their values")
end

-- ------------------------------------------------------------- Sandbox
do
  local Sandbox = require("src.mods.Sandbox")
  for _ = 1, 2 do
    check(Sandbox.moduleDenial("io") ~= nil, "io denied")
    check(Sandbox.moduleDenial("love.filesystem") ~= nil, "love.* denied")
    eq(Sandbox.moduleDenial("love"), nil, "bare love allowed")
    check(Sandbox.moduleDenial("socket.http") ~= nil, "network needs the permission")
    eq(Sandbox.moduleDenial("socket.http", { network = true }), nil, "and passes with it")
    eq(Sandbox.moduleDenial("src.core.Game"), nil, "engine modules allowed")
  end
end

-- ------------------------------------------------------------- Input
do
  local Input = require("src.core.Input")
  Input:init()
  Input:keypressed("up")
  Input:step()
  local pressed, queue = Input.pressed, Input.pressQueue
  check(Input:wasPressed("up"), "press edges")
  Input:keyreleased("up")
  Input:step()
  eq(Input.pressed, pressed, "step recycles its own pressed table")
  eq(Input.pressQueue, queue, "and its own queue")
  check(not Input:wasPressed("up"), "cleared in place")
  local mine = { a = true }
  Input.pressed = mine
  Input:step()
  check(Input.pressed ~= mine and mine.a == true,
    "a table a test installed is replaced, never emptied")

  -- a pad swapped for another between two polls, same count
  local function pad(name, connected)
    return { name = name, connected = connected,
      isGamepadDown = function() return false end,
      isConnected = function(self) return self.connected end,
      isGamepad = function() return true end,
      getName = function(self) return self.name end,
      getGUID = function() return "" end,
      getID = function() return 1 end,
      getButtonCount = function() return 12 end,
      getAxisCount = function() return 4 end }
  end
  local p1, p2 = pad("one", true), pad("two", true)
  local current = { p1 }
  love.joystick = {
    getJoystickCount = function() return #current end,
    getJoysticks = function() return current end,
  }
  local GamepadMap = require("src.core.GamepadMap")
  GamepadMap.ignoreRawForJoystick = function() return true end
  GamepadMap.isAccelerometer = function() return false end
  Input:pollPads()
  eq(Input._pollPads[1], p1, "first poll caches the pad")
  p1.connected = false
  current = { p2 }
  Input:pollPads()
  eq(Input._pollPads[1], p2, "a disconnected cached pad forces a rebuild")
  current = { p1 }
  p1.connected = true
  Input:joysticksChanged()
  Input:pollPads()
  eq(Input._pollPads[1], p1, "joysticksChanged drops the cache")
  love.joystick = nil
end

-- ------------------------------------------------------------- TextBox
do
  local TextBox = require("src.render.TextBox")
  local input = {
    wasPressed = function() return false end,
    isDown = function() return false end,
  }
  local game = { data = { text = {} }, input = input,
    save = { generation = 2, options = { textSpeed = 1 } } }
  local box = TextBox.new(game, "a\nb\nc")
  local steps = 0
  while not box.scrollPx and steps < 200 do
    box:update(1 / 60)
    steps = steps + 1
  end
  eq(box.scrollPx, 6, "the frame that scrolls ends 2px into the slide")
  local drew = pcall(box.draw, box)
  if drew then
    pcall(box.draw, box)
    eq(box.scrollPx, 6, "draw no longer advances the slide")
  end
  box:update(1 / 60)
  eq(box.scrollPx, 4, "each logic step moves it 2px")
  box:update(1 / 60)
  box:update(1 / 60)
  eq(box.scrollPx, nil, "and it ends after four steps")
end

-- ------------------------------------------------------------- ShaderFX
do
  love.filesystem.write = function() return true end
  love.graphics.getRendererInfo = function() return "OpenGL", "4.1 stub", "stub", "stub" end
  love.graphics.getSupported = function() return { glsl3 = true } end
  love.graphics.flushBatch = function() end
  love.graphics.validateShader = function() return true end
  love.timer = love.timer or {}
  love.timer.getDelta = love.timer.getDelta or function() return 1 / 60 end
  local sends = {}
  love.graphics.newShader = function(frag, vert)
    local sh = { frag = frag, vert = vert }
    function sh.send(self, name, value) sends[#sends + 1] = name end
    return sh
  end
  local quads = 0
  love.graphics.newQuad = function(x, y, w, h, sw, sh)
    quads = quads + 1
    local q = { x = x, y = y, w = w, h = h }
    function q.setViewport(self, nx, ny, nw, nh) self.x, self.y, self.w, self.h = nx, ny, nw, nh end
    return q
  end
  local ShaderFX = require("src.render.ShaderFX")
  local ok = ShaderFX.activate("main", { name = "lcd3x.slangp",
    fullPath = "tests/data/shaderfx/gl/lcd3x.slangp", converted = true })
  eq(ok, true, "lcd3x activates under the stub")
  local canvas = setmetatable({ w = 800, h = 720 }, { __index = {
    getWidth = function(self) return self.w end,
    getHeight = function(self) return self.h end,
    getPixelWidth = function(self) return self.w end,
    getPixelHeight = function(self) return self.h end,
  } })
  local rect = { x = 0, y = 0, w = 800, h = 720, scale = 5 }
  ShaderFX.render(canvas, rect, { w = 160, h = 144 }, 1, 1)
  local first = #sends
  check(first > 0, "the first frame sends the pass uniforms")
  ShaderFX.render(canvas, rect, { w = 160, h = 144 }, 1, 1)
  eq(#sends, first, "an identical frame re-sends nothing")
  eq(quads, 1, "the crop quad is re-aimed, not rebuilt")
  ShaderFX.render(canvas, { x = 0, y = 0, w = 640, h = 576, scale = 4 },
    { w = 160, h = 144 }, 1, 1)
  check(#sends > first, "a size change re-sends what changed")
  ShaderFX.deactivate("main")
end

T.finish("render_hotpath_caches")
