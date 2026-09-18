-- Pokemon FireRed service owner (Gen 3 peer of Game / Game2).
-- Boot: copyright → title → main menu → Oak → gender → field (FR_* maps only).

local FixedStep = require("src.core.FixedStep")
local Input = require("src.core.Input")
local SaveData = require("src.core.SaveData")
local Schema = require("src.core.game3.save_schema_firered")
local Runtime = require("src.core.game3.runtime")
local Audio = require("src.core.game3.audio")
local Options = require("src.core.game3.options")
local Dataset = require("src.core.game3.dataset")
local Display = require("src.core.game3.display")
local Boot = require("src.ui.game3.boot")
local Help = require("src.ui.game3.help_system")

local QuestLog = require("src.ui.game3.quest_log")
local QuestRecorder = require("src.core.game3.quest_log_recorder")

local Game3 = {}
Game3.__index = Game3

Game3.SKIN_FAST_FORWARD = 4

function Game3.new()
  return setmetatable({
    input = Input,
    save = nil,
    session = nil,
    phase = "boot", -- boot UI | field
    boot = nil,
    returnToLauncher = nil,
    onExit = nil,
  }, Game3)
end

function Game3:_hasContinueSave()
  if not SaveData.load then return false end
  local ok, save = pcall(SaveData.load)
  if not ok or type(save) ~= "table" then return false end
  return save.engine == "game3" and type(save.map) == "string" and save.map:sub(1, 3) == "FR_"
end

function Game3:_enterField(session, reason)
  self.session = session
  Options.bind(session, self.options)
  -- Continue restores stream; new_game already seeded inside Schema.newGame.
  local Rng = require("src.core.game3.rng")
  if reason == "continue" then
    if not Rng.restoreFromSession(session) then
      -- Legacy saves without rng: soft-reset-ish reseed.
      session.trainerId = Rng.seedNewGame()
      Rng.captureToSession(session)
    else
      -- On GBA FRLG, continuing from title screen seeds/perturbs gRngValue with timer TM0
      Rng.perturb()
    end
  elseif session.rng then
    Rng.restoreFromSession(session)
    Rng.perturb()
  end
  self.save = Schema.toSaveTable(session)
  self.phase = "field"
  self.boot = nil
  -- Drop boot/title BG+OAM so Display.present composites the field underlay only.
  local okBg, Bg = pcall(require, "src.core.game3.bg")
  if okBg and Bg and Bg.reset then Bg.reset() end
  local okOam, Oam = pcall(require, "src.core.game3.oam")
  if okOam and Oam and Oam.reset then Oam.reset() end
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade then
    if Fade.clear then Fade.clear() end
    -- Come out of Oak's black screen onto the bedroom.
    if Fade.begin then Fade.begin(Fade.MODE.FROM_BLACK, 1) end
    Fade.lockInput = true -- pokefirered/src/field_fadetransition.c:441
  end
  session._questNewScene=true
  if reason == "continue" then session._questMap=session.map end
  Runtime.start(nil, self, session, { reason = reason or "new_game" })
  -- Runtime.start already Map.loads unless alreadyOnMap; keep explicit reload for
  -- session x/y/facing in case start opts change.
  local Map = require("src.core.game3.map")
  Map.load(nil, self, session.map, {
    x = session.x,
    y = session.y,
    facing = session.facing,
  })
  -- Map.load plays header / index mapSongs BGM.
end

function Game3:load(opts)
  opts = opts or {}
  self.onExit = opts.onExit or self.onExit
  Input:init()
  self.input = Input
  Dataset.hydrate(self)
  Help.reset()
  Help.install(Dataset.cache())
  QuestLog.install(Dataset.cache())

  local TouchControls = require("src.core.TouchControls")
  TouchControls:init()
  self.touchControls = TouchControls
  TouchControls:setHotkeyHandler(function(action, pressed)
    if not action then return end
    if action:sub(1, 4) == "key:" then
      local key = action:sub(5)
      if pressed then
        if self.keypressed then self:keypressed(key) end
      else
        if self.keyreleased then self:keyreleased(key) end
      end
      return
    end
    if action == "fast_forward_hold" then
      if pressed then
        if self._skinSpeedPrev == nil then
          self._skinSpeedPrev = self.speedOverride or false
        end
        self.speedOverride = Game3.SKIN_FAST_FORWARD
      else
        local prev = self._skinSpeedPrev
        self._skinSpeedPrev = nil
        self.speedOverride = (prev ~= false) and prev or nil
      end
    elseif action == "fast_forward_toggle" then
      if pressed then self:_cycleSpeed(1) end
    elseif action == "soft_reset" then
      if pressed then
        if self.input then self.input:reset() end
        TouchControls:reset()
        self:returnToTitle()
      end
    elseif action == "menu" then
      if pressed and self.phase == "field" and self.session then
        require("src.ui.game3.option_menu").show({ session = self.session, game = self })
      end
    end
  end)

  local okLoad, rawSave, recovered = false, nil, nil
  if SaveData.load then okLoad, rawSave, recovered = pcall(SaveData.load) end
  if not okLoad then rawSave, recovered = nil, nil end
  local saveStatus = "ok"
  if recovered then
    saveStatus = "error" -- pokefirered/src/main_menu.c:251
  elseif okLoad and rawSave == nil and SaveData.persistenceFs and SaveData.saveFilename then
    local okFs, exists = pcall(function()
      local fs = SaveData.persistenceFs(nil)
      return fs and fs.getInfo and fs.getInfo(SaveData.saveFilename()) ~= nil
    end)
    if okFs and exists then saveStatus = "invalid" end -- pokefirered/src/main_menu.c:246
  end
  local options = (SaveData.loadOptions and SaveData.loadOptions())
    or (rawSave and rawSave.options)
    or (SaveData.defaultOptions and SaveData.defaultOptions())
  self.options = options
  self:applyOptions(options)

  -- Never auto-skip boot into a legacy Sevii sidecar.
  local continueOk = self:_hasContinueSave()
  require("src.ui.game3.start_menu").resetCursor() -- pokefirered/src/main.c:134
  self.boot = Boot.new()
  Boot.setHasContinue(self.boot, continueOk)
  if continueOk then
    Boot.setContinueInfo(self.boot, Boot.continueInfoFromSave(rawSave))
  end
  Boot.setSaveStatus(self.boot, saveStatus)
  Boot.setTextSpeed(self.boot, Options.block(self.options).textSpeed)
  self.phase = "boot"
  self.session = nil

  FixedStep:init(function(dt)
    self:fixedUpdate(dt)
  end)
  pcall(function()
    require("src.core.PresentSync").applyFixedStepPeriod()
  end)
end

function Game3:writeOptions()
  if type(self.options) ~= "table" then return end
  if SaveData.saveOptions then pcall(SaveData.saveOptions, self.options) end
end
Game3.persistOptions = Game3.writeOptions

function Game3:applyOptions(opts)
  opts = opts or self.options or {}
  self.options = opts
  local function try(mod, fn, ...)
    local ok, m = pcall(require, mod)
    if not ok or type(m) ~= "table" then return nil end
    local f = m[fn]
    if type(f) ~= "function" then return nil end
    local okCall, res = pcall(f, ...)
    if not okCall then return nil end
    return res
  end
  Audio.applyEngineOptions(opts)
  local cartOpts = Options.block(opts)
  require("src.core.game3.void_fill").setMode(cartOpts.voidFill)
  pcall(function()
    require("src.ui.game3.chrome").setFrameType(cartOpts.frameType)
  end)
  try("src.render.Tilt", "applyOptions", opts)
  try("src.render.Letterbox", "applyOptions", opts)
  try("src.render.Zoom", "applyOptions", opts)
  try("src.core.VideoMode", "applyOptions", opts)
  try("src.core.Orientation", "applyOptions", opts)
  local FaithfulRes = require("src.core.FaithfulRes")
  if FaithfulRes.setNativeSize then
    FaithfulRes.setNativeSize(Display.W, Display.H)
  end
  try("src.core.FaithfulRes", "applyOptions", opts)
  try("src.core.ScreenPosition", "applyOptions", opts)
  try("src.core.VSync", "applyOptions", opts)
  try("src.core.FrameCap", "applyOptions", opts)
  try("src.core.LogicClock", "applyOptions", opts)
  try("src.core.PresentSync", "applyFixedStepPeriod")
  local caps = try("src.core.Performance", "applyOptions", opts)
  if type(caps) == "table" then
    if not caps.tilt then try("src.render.Tilt", "setLevel", 0) end
    local okZ, Zoom = pcall(require, "src.render.Zoom")
    if okZ and Zoom then
      Zoom.allowSurvey = caps.survey
      if not caps.survey and (Zoom.offset or 0) < 0 then Zoom.offset = 0 end
    end
    if caps.fpsMax then
      try("src.core.FrameCap", "clampToPerformance", caps.fpsMax)
    end
  end
  if self.touchControls then
    self.touchControls:applyOptions({
      touchControls = opts.touchControls,
      haptics = opts.haptics,
      hotbar = opts.hotbar,
    })
  end
  if self.input and opts.bindings then
    self.input:applyBindings(opts.bindings)
  end
end

-- pokefirered/src/main.c:325
function Game3:_aliasLA()
  local input = self.input
  if not input or not input.setButtonAlias then return end
  local on
  if self.session then
    on = Options.lEqualsA(self.session)
  elseif type(self.options) == "table" then
    on = tonumber(Options.block(self.options).buttonMode) == 2
  end
  input:setButtonAlias("l", on and "a" or nil)
end

function Game3:_handleRegisteredItem()
  local input = self.input
  if not input or not input.wasPressed or not input:wasPressed("select") then
    return
  end
  local session = self.session
  local item = session and session.registeredItem
  if not item then return end
  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.uiBusy and Runtime.uiBusy() then return end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return end
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  if not session.bag or not Bag.has(session.bag, item, 1) then
    session.registeredItem = nil
    return
  end
  ItemUse.useField(session, session.bag, item, nil)
end

function Game3:_handleBootAction(action)
  if not action then return end
  if action.action == "continue" then
    local ok, save = pcall(SaveData.load)
    if ok and save and save.engine == "game3" then
      local session = Schema.fromSaveTable(save)
      Options.bind(session, self.options)
      -- Refuse Sevii leftovers.
      if type(session.map) == "string" and session.map:sub(1, 6) == "SEVII_" then
        print("[game3] ignoring legacy Sevii save map " .. session.map)
        session = Schema.newGame({ gender = 0 })
      end
      self.questPlayback = QuestLog.begin(session)
      if self.questPlayback then
        self.session=session
        self.phase="quest_log"
        Audio.stopAll()
      else
        self:_enterField(session, "continue")
      end
    end
    return
  end
  if action.action == "new_game" then
    local session = Schema.newGame({
      name = action.name or "RED",
      rivalName = action.rivalName or "BLUE",
      gender = action.gender or 0,
      start = action.start,
    })
    self:_enterField(session, "new_game")
    return
  end
  if action.action == "exit" then
    Audio.stopAll()
    if self.returnToLauncher then
      self.returnToLauncher()
    elseif self.onExit then
      self.onExit()
    elseif love.event and love.event.quit then
      love.event.quit()
    end
    return
  end
end

function Game3:fixedUpdate(dt)
  self:_aliasLA()
  if self.input and self.input.step then self.input:step() end
  if self.input and self.input.softResetStep and self.input:softResetStep() then
    self.input:reset()
    if self.touchControls then self.touchControls:reset() end
    self:returnToTitle()
    return
  end
  if self.phase == "quest_log" then
    local p=self.questPlayback
    local scene=p:current()
    Audio.applyOptions(self.session)
    if scene and scene.song then Audio.playSong(scene.song) end
    Audio.pumpBgm()
    p:update({a=self.input:wasPressed("a"),b=self.input:wasPressed("b")})
    if p.done then
      self.questPlayback=nil
      self.input:reset()
      self:_enterField(self.session,"continue")
    end
    return
  end
  if Help.update(self) then
    -- Keep streaming BGM fed without advancing fanfare/script callbacks.
    Audio.pumpBgm()
    return
  end
  if self.session then Audio.applyOptions(self.session) end

  local Rng = require("src.core.game3.rng")
  Rng.step()

  if self.phase == "boot" and self.boot then
    local action = Boot.update(self.boot, self.input, dt)
    self:_handleBootAction(action)
    return
  end

  if self.phase == "field" then
    self:_handleRegisteredItem()
    if Runtime.isActive() then
      Runtime.update(dt)
      QuestRecorder.update(self)
    end
  end
end

function Game3:speedCategory()
  local okB, Battle = pcall(require, "src.core.game3.battle")
  if okB and Battle and Battle.isActive and Battle.isActive() then
    return "battle"
  end
  local okS, Stack = pcall(require, "src.ui.game3.stack")
  if okS and Stack and Stack.busy and Stack.busy() then return "menu" end
  if Help.isOpen and Help.isOpen() then return "menu" end
  if self.phase ~= "field" then return "menu" end
  return "overworld"
end

function Game3:logicSpeed()
  local override = tonumber(self.speedOverride)
  if override then return math.max(1, override) end
  local b = self.phase == "boot" and self.boot
  if b and (b.phase == Boot.PHASE.INTRO or b.phase == Boot.PHASE.TITLE
      or b.phase == Boot.PHASE.TITLE_CRY or b.phase == Boot.PHASE.TITLE_RESTART) then
    return 1
  end
  local GameSpeed = require("src.core.GameSpeed")
  local opts = self.options
  if type(opts) ~= "table" then return 1 end
  local key = GameSpeed.optionKey(self:speedCategory())
  return math.max(1, GameSpeed.clamp(opts[key]))
end

function Game3:_cycleSpeed(dir)
  if type(self.options) ~= "table" then return end
  local GameSpeed = require("src.core.GameSpeed")
  local key = GameSpeed.optionKey(self:speedCategory())
  self.options[key] = GameSpeed.cycle(self.options[key], dir)
  self:writeOptions()
end

function Game3:zoomGateOK()
  if self.phase ~= "field" then return false end
  local okB, Battle = pcall(require, "src.core.game3.battle")
  if okB and Battle and Battle.isActive and Battle.isActive() then return false end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return false end
  local Shop = package.loaded["src.ui.game3.shop_menu"]
  if Shop and Shop.isShopCamera and Shop.isShopCamera() then return false end
  return true
end

function Game3:zoomStep(delta)
  if not self:zoomGateOK() then return end
  local Zoom = require("src.render.Zoom")
  local Renderer = require("src.render.Renderer")
  local offset = Zoom.step(delta, Renderer:fitScale())
  if type(self.options) == "table" then
    self.options.zoom = offset
    self:writeOptions()
  end
end

function Game3:update(dt)
  local speed = self:logicSpeed()
  FixedStep.maxAccum = FixedStep.catchupLimit(speed)
  FixedStep:update(dt, speed)
  self._audioAccum = (self._audioAccum or 0) + dt
  local STEP = 1 / 60
  local guard = 0
  while self._audioAccum >= STEP and guard < 8 do
    self._audioAccum = self._audioAccum - STEP
    guard = guard + 1
    pcall(Audio.update, STEP)
  end
  if self._audioAccum > 0.25 then self._audioAccum = 0 end
  pcall(function() require("src.render.Tilt").update(dt) end)
end

function Game3:draw()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()

  if self.phase == "quest_log" or (self.phase == "boot" and self.boot) then
    local kind = (self.phase == "quest_log") and "quest" or "boot"
    local function drawBootFrame()
      if self.phase == "quest_log" then QuestLog.draw(self.questPlayback,self.session)
      elseif Help.isOpen() then Help.draw() else Boot.draw(self.boot) end
    end
    if not Display.presentUi(self, w, h, kind, drawBootFrame) then
      local canvas = Display.ensureCanvas("main")
      if canvas then
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.origin()
        drawBootFrame()
        love.graphics.setCanvas()
        love.graphics.pop()
        local scale, ox, oy, _, _, scaleY = Display.fit(w, h)
        love.graphics.setColor(0.02, 0.04, 0.08, 1)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, ox, oy, 0, scale, scaleY)
      else
        drawBootFrame()
      end
    end
    if self.touchControls then
      self.touchControls:draw()
    end
    return
  end

  if Runtime.isActive() then
    if Display.present(self, w, h) then
      if self.touchControls then
        self.touchControls:draw()
      end
      return
    end
  end

  love.graphics.clear(0.05, 0.05, 0.12)
  love.graphics.setColor(0.4, 0.8, 0.4)
  local map = self.session and self.session.map or "?"
  love.graphics.printf("Fire Red field: " .. tostring(map), 0, h * 0.45, w, "center")
  if self.touchControls then
    self.touchControls:draw()
  end
end

function Game3:_hotkey(key)
  if key == "f1" then
    if self.phase == "field" then self:saveGame() end
    return true
  elseif key == "f2" then
    if self.phase == "field" then
      pcall(function() require("src.ui.game3.stack").clear() end)
      pcall(function()
        local R = require("src.core.game3.runtime")
        if R.stop then R.stop(nil, self) end
      end)
      pcall(function() require("src.core.game3.ghosts").clear() end)
      self:_handleBootAction({ action = "continue" })
    end
    return true
  elseif key == "1" then
    self:_cycleSpeed(1)
    return true
  elseif key == "3" then
    if self:zoomGateOK() then
      local Tilt = require("src.render.Tilt")
      Tilt.cycle()
      if type(self.options) == "table" then
        self.options.tilt = Tilt.level
        self:writeOptions()
      end
    end
    return true
  elseif key == "4" then
    if self:zoomGateOK() then
      local Zoom = require("src.render.Zoom")
      local Renderer = require("src.render.Renderer")
      local offset = Zoom.cycle(Renderer:fitScale())
      if type(self.options) == "table" then
        self.options.zoom = offset
        self:writeOptions()
      end
    end
    return true
  elseif key == "-" or key == "kp-" then
    self:zoomStep(-1)
    return true
  elseif key == "=" or key == "kp+" then
    self:zoomStep(1)
    return true
  end
  return false
end

function Game3:keypressed(key)
  if self:_hotkey(key) then return end
  if self.input and self.input.keypressed then self.input:keypressed(key) end
end
function Game3:keyreleased(key)
  if self.input and self.input.keyreleased then self.input:keyreleased(key) end
end

function Game3:_padPressedBody(joystick, button)
  if self.touchControls then self.touchControls:noteGamepad() end
  local Input2 = self.input
  if not Input2 then return end
  local selectHeld = Input2.isDown and Input2:isDown("select")
  if not selectHeld and joystick and joystick.isGamepadDown then
    local ok, down = pcall(function() return joystick:isGamepadDown("back") end)
    selectHeld = ok and down == true
  end
  local isTrigger = button == "lefttrigger" or button == "righttrigger"
  if not selectHeld and isTrigger and Input2.padAction then
    local action = Input2:padAction(button)
    if action == "speedUp" then
      self:_cycleSpeed(1)
      return
    elseif action == "speedDown" then
      self:_cycleSpeed(-1)
      return
    end
  end
  if selectHeld then
    local GamepadMap = require("src.core.GamepadMap")
    local digit = GamepadMap.displayChordDigit(button)
    if digit and self:_hotkey(digit) then return end
  end
  if Input2.gamepadpressed then Input2:gamepadpressed(joystick, button) end
end

function Game3:_padReleasedBody(joystick, button)
  if self.input and self.input.gamepadreleased then
    self.input:gamepadreleased(joystick, button)
  end
end

function Game3:gamepadpressed(joystick, button)
  self:_padPressedBody(joystick, button)
end
function Game3:gamepadreleased(joystick, button)
  self:_padReleasedBody(joystick, button)
end

function Game3:saveGame()
  if not self.session or self.phase == "quest_log" then return end
  if Runtime.getSession then
    local s = Runtime.getSession()
    if s then self.session = s end
  end
  QuestRecorder.save(self)
  self.save = Schema.toSaveTable(self.session)
  if SaveData.save then pcall(SaveData.save, self.save) end
end

function Game3:resize() end

function Game3:mousepressed(x, y, button, istouch)
  if istouch then return end
  if os.getenv("POKEPORT_TOUCH") == "1" and self.touchControls then
    self.touchControls:touchpressed("mouse", x, y)
  end
end

function Game3:mousemoved(x, y, dx, dy, istouch)
  if istouch then return end
  if os.getenv("POKEPORT_TOUCH") == "1" and self.touchControls then
    self.touchControls:touchmoved("mouse", x, y)
  end
end

function Game3:mousereleased(x, y, button, istouch)
  if istouch then return end
  if os.getenv("POKEPORT_TOUCH") == "1" and self.touchControls then
    self.touchControls:touchreleased("mouse", x, y)
  end
end

function Game3:wheelmoved(_, dy)
  if type(dy) ~= "number" then return end
  if dy > 0 then
    self:zoomStep(1)
  elseif dy < 0 then
    self:zoomStep(-1)
  end
end
function Game3:textinput() end
function Game3:filedropped() end

function Game3:touchpressed(id, x, y, dx, dy, pressure)
  if self.touchControls and self.touchControls:touchpressed(id, x, y) then return end
end

function Game3:touchmoved(id, x, y, dx, dy, pressure)
  if self.touchControls then self.touchControls:touchmoved(id, x, y) end
end

function Game3:touchreleased(id, x, y, dx, dy, pressure)
  if self.touchControls then self.touchControls:touchreleased(id, x, y) end
end

function Game3:gamepadaxis(joystick, axis, value)
  if math.abs(value) > 0.5 and self.touchControls then
    self.touchControls:noteGamepad()
  end
  if self.input and self.input.triggerAxis then
    local trigger, phase = self.input:triggerAxis(axis, value)
    if trigger then
      if phase == "pressed" then
        self:_padPressedBody(joystick, trigger)
      elseif phase == "released" then
        self:_padReleasedBody(joystick, trigger)
      end
      return
    end
  end
  if self.input and self.input.gamepadaxis then self.input:gamepadaxis(joystick, axis, value) end
end

function Game3:joystickpressed(joystick, button)
  if self.touchControls then self.touchControls:noteGamepad() end
  local Input2 = self.input
  if Input2 and Input2.joyAction
      and not (Input2.isDown and Input2:isDown("select")) then
    local action = Input2:joyAction(button)
    if action == "speedUp" then
      self:_cycleSpeed(1)
      return
    elseif action == "speedDown" then
      self:_cycleSpeed(-1)
      return
    end
  end
  if Input2 and Input2.joystickpressed then Input2:joystickpressed(joystick, button) end
end

function Game3:joystickreleased(joystick, button)
  if self.input and self.input.joystickreleased then self.input:joystickreleased(joystick, button) end
end

function Game3:joystickaxis(joystick, axis, value)
  if math.abs(value) > 0.5 and self.touchControls then
    self.touchControls:noteGamepad()
  end
  if self.input and self.input.joystickaxis then self.input:joystickaxis(joystick, axis, value) end
end

function Game3:joystickhat(joystick, hat, direction)
  if direction ~= "c" and self.touchControls then
    self.touchControls:noteGamepad()
  end
  if self.input and self.input.joystickhat then self.input:joystickhat(joystick, hat, direction) end
end

function Game3:joystickadded() end

function Game3:joystickremoved(joystick)
  if self.touchControls then self.touchControls:joystickremoved() end
end

function Game3:focus(f)
  if self.input then self.input:reset() end
  if self.touchControls then self.touchControls:reset() end
  if f then
    if self.input then self.input:reconcile() end
    Audio.onFocusGained()
  end
end

function Game3:visible(v)
  if v then
    self:onResume()
  else
    if self.input then self.input:reset() end
    if self.touchControls then self.touchControls:reset() end
  end
end

function Game3:onResume()
  if self.input then
    self.input:reset()
    self.input:reconcile()
  end
  if self.touchControls then self.touchControls:reset() end
  Audio.onFocusGained()
end

function Game3:returnToTitle()
  self.questPlayback=nil
  Help.reset()
  Audio.stopAll()
  local Stack = require("src.ui.game3.stack")
  Stack.clear()
  if Runtime.isActive() then
    Runtime.stop(nil, self)
  end
  self.phase = "boot"
  self.session = nil

  local okLoad, rawSave, recovered = false, nil, nil
  if SaveData.load then okLoad, rawSave, recovered = pcall(SaveData.load) end
  if not okLoad then rawSave, recovered = nil, nil end
  local saveStatus = "ok"
  if recovered then
    saveStatus = "error"
  elseif okLoad and rawSave == nil and SaveData.persistenceFs and SaveData.saveFilename then
    local okFs, exists = pcall(function()
      local fs = SaveData.persistenceFs(nil)
      return fs and fs.getInfo and fs.getInfo(SaveData.saveFilename()) ~= nil
    end)
    if okFs and exists then saveStatus = "invalid" end
  end
  local continueOk = self:_hasContinueSave()
  require("src.ui.game3.start_menu").resetCursor()
  self.boot = Boot.new()
  Boot.setHasContinue(self.boot, continueOk)
  if continueOk then
    Boot.setContinueInfo(self.boot, Boot.continueInfoFromSave(rawSave))
  end
  Boot.setSaveStatus(self.boot, saveStatus)
  Boot.setTextSpeed(self.boot, Options.block(self.options).textSpeed)
  self.boot.phase = Boot.PHASE.TITLE
  self.boot.timer = 0
  local TitleScreen = require("src.ui.game3.title_screen")
  TitleScreen.enter(self.boot)
end

function Game3:reset()
  self.questPlayback = nil
  Help.reset()
  Audio.endSession()
  require("src.ui.game3.stack").clear()
  if Runtime.isActive() then
    pcall(function() Runtime.stop(nil, self) end)
  end
  local Ghosts = package.loaded["src.core.game3.ghosts"]
  if Ghosts and Ghosts.clear then pcall(Ghosts.clear) end
  for _, name in ipairs({ "src.core.game3.oam", "src.core.game3.bg" }) do
    local mod = package.loaded[name]
    if mod and mod.reset then pcall(mod.reset) end
  end
  Display.release()
  if self.touchControls then
    pcall(function() self.touchControls:setHotkeyHandler(nil) end)
    self.touchControls = nil
  end
  self.boot = nil
  self.session = nil
  self.data = nil
  self.phase = "boot"
  self.returnToLauncher = nil
  self.onExit = nil
end

function Game3:quit()
  self:saveGame()
end

return Game3
