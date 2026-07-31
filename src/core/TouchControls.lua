-- On-screen touch controls: a visible d-pad, A, B, START and SELECT drawn
-- over the finished frame (art: Xelu's CC0 controller prompts, see
-- assets/touch/README.md).  Replaces the old touch gesture recognizer:
-- every control is a real button under the thumb, so there is no
-- tap-vs-swipe classification, no deferred-A double-tap window, and no
-- added latency.
--
-- Mobile only, and only while no controller is being used: the overlay
-- shows on Android/iOS, disappears the moment a gamepad button or stick
-- is used, and comes back on the next screen touch (Game routes both
-- events here).  POKEPORT_TOUCH=1 forces it on for desktop testing
-- (main.lua then drives it with the mouse); POKEPORT_TOUCH=0 forces it
-- off everywhere.
--
-- Player preferences (options.touchControls) can permanently disable the
-- overlay and/or override per-control positions as normalized window
-- fractions.  The launcher editor (src/ui/TouchControlsEditor.lua) writes
-- those; applyOptions reads them at boot and whenever options change.
--
-- Controls press GB buttons through Input:overlayPressed/Released -- their
-- own input source, not a keyboard alias -- so a held overlay direction
-- merges cleanly with a keyboard key or stick holding the same button,
-- and a player rebind can never detach the overlay.

local Input = require("src.core.Input")

local TouchControls = {}

-- idle vs pressed overlay opacity
local ALPHA = 0.65
local ALPHA_PRESSED = 0.95
-- translucent backing disc behind each control: the prompt art is dark
-- gray, so without it the controls melt into dark map areas
local BACK = 0.24
local BACK_PRESSED = 0.38

-- neutral zone at the d-pad center, as a fraction of the d-pad width;
-- inside it no direction is held (keeps a resting thumb from jittering)
local DPAD_DEAD = 0.16

-- hit slop: how far past the visible edge a press still counts, as a
-- multiplier on the control's half-width.  START/SELECT get more because
-- the glyphs are small.
local SLOP = { a = 1.3, b = 1.3, start = 1.4, select = 1.4 }

local BUTTONS = { "a", "b", "start", "select" }
local CONTROLS = { "dpad", "a", "b", "start", "select" }

local IMAGES = {
  dpad = "assets/touch/dpad.png",
  dpad_up = "assets/touch/dpad_up.png",
  dpad_down = "assets/touch/dpad_down.png",
  dpad_left = "assets/touch/dpad_left.png",
  dpad_right = "assets/touch/dpad_right.png",
  a = "assets/touch/a.png",
  b = "assets/touch/b.png",
  start = "assets/touch/start.png",
  select = "assets/touch/select.png",
}

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function wantsOverlay()
  local env = os.getenv("POKEPORT_TOUCH")
  if env == "1" then return true end
  if env == "0" then return false end
  local osName = love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

-- Normalize a persisted touchControls table into {enabled, positions}.
-- Unknown / garbage keys are dropped so a bad options.lua cannot brick
-- the overlay.
function TouchControls.normalizeConfig(tc)
  local out = { enabled = true, positions = nil }
  if type(tc) ~= "table" then return out end
  if tc.enabled == false then out.enabled = false end
  if type(tc.positions) == "table" then
    local pos = {}
    for _, name in ipairs(CONTROLS) do
      local p = tc.positions[name]
      if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
        pos[name] = { x = clamp01(p.x), y = clamp01(p.y) }
      end
    end
    if next(pos) then out.positions = pos end
  end
  return out
end

-- Pure default layout in LOVE units for a given window size.  Shared by
-- layout() and the editor's Reset path so defaults stay in one place.
function TouchControls.defaultLayout(ww, wh)
  local short = math.min(ww, wh)
  local dpadW = math.min(180, short * 0.34)
  local abW = dpadW * 0.46
  local ssW = dpadW * 0.30
  local margin = dpadW * 0.12
  return {
    dpad = { cx = margin + dpadW / 2, cy = wh - margin - dpadW / 2, w = dpadW },
    a = { cx = ww - margin - abW * 0.55, cy = wh - margin - abW * 1.75, w = abW },
    b = { cx = ww - margin - abW * 1.60, cy = wh - margin - abW * 0.55, w = abW },
    start = { cx = ww / 2 + ssW * 0.60, cy = wh - margin - ssW * 0.95, w = ssW },
    select = { cx = ww / 2 - ssW * 0.60, cy = wh - margin - ssW * 0.95, w = ssW },
  }
end

local function loadImages()
  local img = {}
  for name, path in pairs(IMAGES) do
    local ok, im = pcall(love.graphics.newImage, path)
    if not ok then return nil end
    im:setFilter("linear", "linear")
    img[name] = im
  end
  return img
end

function TouchControls:init()
  self.active = wantsOverlay()
  self.enabled = true
  self.positions = nil
  self.preview = false
  self.controllerHidden = false
  self.touches = {}
  -- per-GB-button owner count: two fingers on A must not double-press it,
  -- and lifting one of them must not release the other's hold
  self.held = {}
  self.dpadTouch = nil
  self.layoutW, self.layoutH = nil, nil
  self.img = nil
  -- Images load whenever the platform wants the overlay OR the launcher
  -- editor forces a preview (desktop testing of the editor).
  if self.active then
    self.img = loadImages()
  end
end

-- Ensure art is loaded for the launcher editor even when wantsOverlay()
-- is false (desktop without POKEPORT_TOUCH).
function TouchControls:ensureImages()
  if self.img then return true end
  self.img = loadImages()
  return self.img ~= nil
end

-- Apply options.touchControls.  Called from Game:applyOptions and from
-- the launcher editor after a save.
function TouchControls:applyOptions(opts)
  local cfg = TouchControls.normalizeConfig(opts and opts.touchControls)
  self.enabled = cfg.enabled
  self.positions = cfg.positions
  self.layoutW, self.layoutH = nil, nil
  if not self.enabled then
    self.controllerHidden = false
    self:reset()
  end
end

function TouchControls:config()
  return {
    enabled = self.enabled ~= false,
    positions = self.positions,
  }
end

-- Preview mode: force-draw the overlay for the layout editor, ignoring
-- platform / enabled / gamepad gates.  Gameplay input still respects
-- enabled via touchpressed.
function TouchControls:setPreview(on)
  self.preview = on and true or false
  if on then
    self:ensureImages()
    self.controllerHidden = false
  end
end

function TouchControls:visible()
  if self.preview then return self.img ~= nil end
  return self.active and self.enabled ~= false and self.img ~= nil
     and not self.controllerHidden
end

local function clampZone(zone, ww, wh)
  local half = zone.w * 0.5
  zone.cx = math.max(half, math.min(ww - half, zone.cx))
  zone.cy = math.max(half, math.min(wh - half, zone.cy))
end

-- Layout in LOVE units (density-independent on mobile), recomputed when
-- the window size changes (rotation, resize).  Default: d-pad bottom-left,
-- B/A bottom-right with A above B (the Game Boy diagonal), START/SELECT
-- flanking the bottom center.  Custom positions (normalized 0..1) override
-- centers while sizes stay derived from the short edge.
function TouchControls:layout()
  local ww, wh = love.graphics.getDimensions()
  if self.layoutW == ww and self.layoutH == wh and self.L then return self.L end
  self.layoutW, self.layoutH = ww, wh
  self.L = TouchControls.defaultLayout(ww, wh)
  if self.positions then
    for _, name in ipairs(CONTROLS) do
      local p = self.positions[name]
      local zone = self.L[name]
      if p and zone then
        zone.cx = p.x * ww
        zone.cy = p.y * wh
        clampZone(zone, ww, wh)
      end
    end
  end
  local ssW = self.L.start.w
  local fontSize = math.max(8, math.floor(ssW * 0.26))
  if not self.labelFont or self.fontSize ~= fontSize then
    self.fontSize = fontSize
    self.labelFont = love.graphics.newFont(fontSize)
  end
  return self.L
end

-- Move one control to a screen-space point and persist its normalized
-- position.  Used by the layout editor while dragging.
function TouchControls:setControlCenter(name, cx, cy)
  local ww, wh = love.graphics.getDimensions()
  local L = self:layout()
  local zone = L[name]
  if not zone then return end
  zone.cx, zone.cy = cx, cy
  clampZone(zone, ww, wh)
  self.positions = self.positions or {}
  self.positions[name] = { x = zone.cx / ww, y = zone.cy / wh }
end

function TouchControls:clearPositions()
  self.positions = nil
  self.layoutW, self.layoutH = nil, nil
end

local function inCircle(zone, x, y, slop)
  local r = zone.w * 0.5 * slop
  local dx, dy = x - zone.cx, y - zone.cy
  return dx * dx + dy * dy <= r * r
end

-- Which control (if any) contains (x, y).  Prefer face buttons over the
-- d-pad when they overlap, matching touchpressed's order.
function TouchControls:hitTest(x, y)
  local L = self:layout()
  for _, btn in ipairs(BUTTONS) do
    if inCircle(L[btn], x, y, SLOP[btn]) then return btn end
  end
  local dz = L.dpad
  local half = dz.w * 0.65
  if math.abs(x - dz.cx) <= half and math.abs(y - dz.cy) <= half then
    return "dpad"
  end
  return nil
end

local function dpadDir(zone, x, y)
  local dx, dy = x - zone.cx, y - zone.cy
  local dead = zone.w * DPAD_DEAD
  if math.abs(dx) < dead and math.abs(dy) < dead then return nil end
  if math.abs(dx) >= math.abs(dy) then
    return dx > 0 and "right" or "left"
  end
  return dy > 0 and "down" or "up"
end

local function pressBtn(self, btn)
  local n = (self.held[btn] or 0) + 1
  self.held[btn] = n
  if n == 1 then Input:overlayPressed(btn) end
end

local function releaseBtn(self, btn)
  local n = self.held[btn]
  if not n then return end
  if n > 1 then
    self.held[btn] = n - 1
  else
    self.held[btn] = nil
    Input:overlayReleased(btn)
  end
end

-- the d-pad touch's held direction changed (or ended): swap the GB hold
local function setDpad(self, touch, dir)
  if touch.dir == dir then return end
  if touch.dir then releaseBtn(self, touch.dir) end
  touch.dir = dir
  if dir then pressBtn(self, dir) end
end

function TouchControls:touchpressed(id, x, y)
  -- preview mode is layout-edit only: never press GB buttons
  if self.preview then return end
  if not (self.active and self.enabled ~= false and self.img) then return end
  -- a controller hid the overlay; the first touch only brings it back
  if self.controllerHidden then
    self.controllerHidden = false
    return
  end
  local L = self:layout()
  for _, btn in ipairs(BUTTONS) do
    if inCircle(L[btn], x, y, SLOP[btn]) then
      self.touches[id] = { control = btn }
      pressBtn(self, btn)
      return
    end
  end
  -- square hit zone a bit past the cross art; one owning finger at a time
  local dz = L.dpad
  local half = dz.w * 0.65
  if not self.dpadTouch
     and math.abs(x - dz.cx) <= half and math.abs(y - dz.cy) <= half then
    self.dpadTouch = id
    local touch = { control = "dpad", dir = nil }
    self.touches[id] = touch
    setDpad(self, touch, dpadDir(dz, x, y))
  end
end

function TouchControls:touchmoved(id, x, y)
  if self.preview then return end
  local touch = self.touches[id]
  -- only the d-pad tracks movement (slide between directions without
  -- lifting); buttons hold until release wherever the finger wanders
  if not touch or touch.control ~= "dpad" then return end
  setDpad(self, touch, dpadDir(self:layout().dpad, x, y))
end

function TouchControls:touchreleased(id, x, y)
  if self.preview then return end
  local touch = self.touches[id]
  if not touch then return end
  self.touches[id] = nil
  if touch.control == "dpad" then
    setDpad(self, touch, nil)
    self.dpadTouch = nil
  else
    releaseBtn(self, touch.control)
  end
end

-- LÖVE has no touchcancelled: a touch interrupted by the OS (app
-- backgrounded, a system gesture stealing the finger) never fires
-- touchreleased and would strand its button held forever.  Called from
-- Game alongside Input:reset() on focus/visibility loss.
function TouchControls:reset()
  for btn in pairs(self.held or {}) do
    Input:overlayReleased(btn)
  end
  self.held = {}
  self.touches = {}
  self.dpadTouch = nil
end

-- a gamepad is being used: hide the overlay (dropping anything it held)
-- until the next screen touch asks for it back.  No-op when the player
-- permanently disabled the overlay -- there is nothing to hide, and a
-- later accidental touch must not resurrect it.
function TouchControls:noteGamepad()
  if not self.active or self.enabled == false or self.controllerHidden then
    return
  end
  self.controllerHidden = true
  self:reset()
end

-- last controller unplugged: show the overlay again immediately instead
-- of requiring a blind first tap
function TouchControls:joystickremoved()
  self:reset()
  if love.joystick and love.joystick.getJoystickCount
     and love.joystick.getJoystickCount() == 0 then
    self.controllerHidden = false
  end
end

local function drawIcon(img, zone, pressed, alphaMul)
  alphaMul = alphaMul or 1
  love.graphics.setColor(1, 1, 1, (pressed and BACK_PRESSED or BACK) * alphaMul)
  love.graphics.circle("fill", zone.cx, zone.cy, zone.w * 0.58)
  local scale = zone.w / img:getWidth()
  love.graphics.setColor(1, 1, 1, (pressed and ALPHA_PRESSED or ALPHA) * alphaMul)
  love.graphics.draw(img, zone.cx - zone.w / 2,
                     zone.cy - img:getHeight() * scale / 2, 0, scale, scale)
end

-- Screen-space, called by Game:draw after Renderer:endFrame so the
-- overlay rides on top of everything (world, UI, CRT/GBC FX included).
-- Also used by the launcher layout editor under preview mode.
function TouchControls:draw()
  if not self:visible() then return end
  local L = self:layout()
  -- when the player disabled the overlay but the editor is previewing,
  -- draw dimmed so the layout is still editable
  local alphaMul = (self.preview and self.enabled == false) and 0.45 or 1
  love.graphics.push("all")
  love.graphics.origin()

  local dpadTouch = self.dpadTouch and self.touches[self.dpadTouch]
  local dir = dpadTouch and dpadTouch.dir
  drawIcon(dir and self.img["dpad_" .. dir] or self.img.dpad, L.dpad,
           dir ~= nil, alphaMul)
  for _, btn in ipairs(BUTTONS) do
    drawIcon(self.img[btn], L[btn], self.held[btn] ~= nil, alphaMul)
  end

  -- the +/- glyphs alone don't say which is which; shadowed so the text
  -- reads on both the black letterbox and battle's white one.  Each label
  -- tracks its own control's cy/w so dragging START cannot move SELECT.
  love.graphics.setFont(self.labelFont)
  local function label(text, zone)
    local ly = zone.cy + zone.w * 0.66
    local w = self.labelFont:getWidth(text)
    love.graphics.setColor(0, 0, 0, 0.6 * alphaMul)
    love.graphics.print(text, zone.cx - w / 2 + 1, ly + 1)
    love.graphics.setColor(1, 1, 1, (ALPHA + 0.2) * alphaMul)
    love.graphics.print(text, zone.cx - w / 2, ly)
  end
  label("START", L.start)
  label("SELECT", L.select)

  love.graphics.pop()
end

TouchControls.CONTROLS = CONTROLS

return TouchControls
