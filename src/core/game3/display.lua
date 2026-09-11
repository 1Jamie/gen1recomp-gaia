-- Game3 display owner (FRLG-native 240×160).
-- Owns the presented frame when Runtime is active: own canvas, own letterbox,
-- own UI. Field map is composited under the UI; Gen2 Chrome/StartMenu are not used.

local Display = {}

Display.W = 240
Display.H = 160
Display.TILE = 8
Display.COLS = 30
Display.ROWS = 20

Display._canvas = nil
Display._uiOnly = nil -- secondary canvas for UI layer when field is drawn by host
Display._logged = false

local function log(msg)
  print("[game3/display] " .. tostring(msg))
end

function Display.ensureCanvas(which)
  which = which or "main"
  local key = which == "ui" and "_uiOnly" or "_canvas"
  local existing = Display[key]
  if existing then
    local ok, cw, ch = pcall(function()
      return existing:getWidth(), existing:getHeight()
    end)
    if ok and cw == Display.W and ch == Display.H then
      return existing
    end
  end
  local ok, canvas = pcall(love.graphics.newCanvas, Display.W, Display.H)
  if not ok or not canvas then
    log("FAILED canvas create")
    return nil
  end
  canvas:setFilter("nearest", "nearest")
  Display[key] = canvas
  if not Display._logged then
    log("owned FRLG frame " .. Display.W .. "x" .. Display.H
      .. " (not Gen2 160x144)")
    Display._logged = true
  end
  return canvas
end

local SafeArea = require("src.core.SafeArea")

function Display.fit(winW, winH)
  local gw, gh = 0, 0
  if love and love.graphics and love.graphics.getDimensions then
    gw, gh = love.graphics.getDimensions()
  end
  winW = winW or (gw > 0 and gw or Display.W)
  winH = winH or (gh > 0 and gh or Display.H)

  local safeX, safeY, safeW, safeH = 0, 0, winW, winH
  if gw > 0 and gh > 0 and winW == gw and winH == gh then
    local sx, sy, sw, sh = SafeArea.windowRect()
    if sw and sw > 0 and sh and sh > 0 then
      safeX, safeY, safeW, safeH = sx, sy, sw, sh
    end
  end

  local isPortrait = safeH > safeW
  local scale, ox, oy, pw, ph

  if isPortrait then
    -- On mobile portrait, scale to fit the available safe width cleanly.
    scale = safeW / Display.W
    pw = Display.W * scale
    ph = Display.H * scale
    ox = safeX + math.floor((safeW - pw) * 0.5)
    -- In portrait, center the screen in the upper deck area (above the touch controls deck).
    local topDeckH = safeH * 0.48
    oy = safeY + math.max(4, math.floor((topDeckH - ph) * 0.5))
  else
    -- Landscape / desktop: fit cleanly within safe area
    scale = math.max(1, math.floor(math.min(safeW / Display.W, safeH / Display.H)))
    pw = Display.W * scale
    ph = Display.H * scale
    ox = safeX + math.floor((safeW - pw) * 0.5)
    oy = safeY + math.floor((safeH - ph) * 0.5)
  end

  return scale, ox, oy, pw, ph
end

local function beginOn(canvas)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1, 1)
end

local function endCanvas()
  love.graphics.setCanvas()
  love.graphics.pop()
end

--- GBA-style compositor: for priority 3→0, draw BGs then OBJs at that priority.
-- Lower priority number composites in front. Same priority: OBJ above BG.
-- opts:
--   animate (bool, default true) — run Oam.animateSprites
--   build (bool, default true) — rebuild OAM buffer
--   clear (r,g,b,a table) — clear before compose
--   scissor {x,y,w,h} — WIN-style clip
--   underlay function() — drawn behind all BG/OBJ (rare)
--   overlay function() — drawn after all BG/OBJ (fades, blend approximates)
function Display.composeHardware(opts)
  opts = opts or {}
  local Bg = require("src.core.game3.bg")
  local Oam = require("src.core.game3.oam")

  if opts.clear then
    local c = opts.clear
    love.graphics.clear(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
  end

  if opts.underlay then
    opts.underlay()
  end

  if opts.animate ~= false then
    Oam.animateSprites()
  end
  if opts.build ~= false then
    Oam.buildOamBuffer()
  end

  if opts.scissor then
    local s = opts.scissor
    love.graphics.setScissor(s.x, s.y, s.w, s.h)
  end

  -- Back → front: pri 3,2,1,0. Within each: BG then OBJ.
  for pri = 3, 0, -1 do
    Bg.flushPriority(pri)
    Oam.flushPriority(pri)
  end

  if opts.scissor then
    love.graphics.setScissor()
  end

  if opts.overlay then
    opts.overlay()
  end
end

--- Full present: build 240×160 frame (field + UI), letterbox to window.
function Display.present(game, winW, winH)
  local canvas = Display.ensureCanvas("main")
  if not canvas then return false end

  beginOn(canvas)
  local ok, err = xpcall(function()
    love.graphics.clear(0.06, 0.12, 0.20, 1)

    local Oam = require("src.core.game3.oam")
    local Bg = require("src.core.game3.bg")
    Oam.resetFrame()

    local Battle = require("src.core.game3.battle")
    if Battle.isActive() then
      Battle.draw(game, Display.W, Display.H)
    else
      local FieldView = require("src.core.game3.field_view")
      FieldView.draw(game, Display.W, Display.H)
    end

    local Gfx = require("src.core.game3.gfx")
    Gfx.drawUi()

    -- Animate after UI so party can attach bounce callbacks this frame.
    Oam.animateSprites()
    Oam.buildOamBuffer()
    if Bg.hasVisible() then
      for pri = 3, 0, -1 do
        Bg.flushPriority(pri)
        Oam.flushPriority(pri)
      end
    else
      Oam.flush()
    end
  end, debug.traceback)
  endCanvas()
  if not ok then
    error(err)
  end

  -- Void bars + blit our frame (game3 letterbox, not Gen2 Playfield).
  love.graphics.setColor(0.02, 0.04, 0.08, 1)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  local scale, ox, oy = Display.fit(winW, winH)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, ox, oy, 0, scale, scale)
  return true
end

return Display
