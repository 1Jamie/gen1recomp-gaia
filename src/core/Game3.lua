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

local Game3 = {}
Game3.__index = Game3

function Game3.new()
  return setmetatable({
    input = Input,
    save = nil,
    session = nil,
    phase = "boot", -- boot UI | field
    boot = nil,
    returnToLauncher = nil,
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
  end
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
  Input:init()
  self.input = Input
  Dataset.hydrate(self)

  -- Never auto-skip boot into a legacy Sevii sidecar.
  local continueOk = self:_hasContinueSave()
  self.boot = Boot.new()
  Boot.setHasContinue(self.boot, continueOk)
  self.phase = "boot"
  self.session = nil

  self._step = FixedStep.new and FixedStep.new(60, function(dt)
    self:fixedUpdate(dt)
  end) or nil
end

function Game3:_aliasLA()
  if not self.session then return end
  if not Options.lEqualsA(self.session) then return end
  local input = self.input
  if not input then return end
  if input.wasPressed and input:wasPressed("l") then
    input:sourcePress("a", "l_equals_a")
  elseif input.isDown and input:isDown("l") then
    input:sourcePress("a", "l_equals_a_hold")
  end
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
      -- Refuse Sevii leftovers.
      if type(session.map) == "string" and session.map:sub(1, 6) == "SEVII_" then
        print("[game3] ignoring legacy Sevii save map " .. session.map)
        session = Schema.newGame({ gender = 0 })
      end
      self:_enterField(session, "continue")
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
  end
end

function Game3:fixedUpdate(dt)
  Audio.update(dt)
  if self.session then
    Audio.applyOptions(self.session)
  end

  if self.input and self.input.step then
    self.input:step()
  end

  local Rng = require("src.core.game3.rng")
  Rng.step()

  if self.phase == "boot" and self.boot then
    local action = Boot.update(self.boot, self.input, dt)
    self:_handleBootAction(action)
    return
  end

  if self.phase == "field" then
    self:_aliasLA()
    self:_handleRegisteredItem()
    if Runtime.isActive() then
      Runtime.update(dt)
    end
  end
end

function Game3:update(dt)
  if self._step and self._step.update then
    self._step:update(dt)
  else
    self:fixedUpdate(dt)
  end
end

function Game3:draw()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()

  if self.phase == "boot" and self.boot then
    local canvas = Display.ensureCanvas("main")
    if canvas then
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.origin()
      Boot.draw(self.boot)
      love.graphics.setCanvas()
      love.graphics.pop()
      local scale, ox, oy = Display.fit(w, h)
      love.graphics.setColor(0.02, 0.04, 0.08, 1)
      love.graphics.rectangle("fill", 0, 0, w, h)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(canvas, ox, oy, 0, scale, scale)
    else
      Boot.draw(self.boot)
    end
    return
  end

  if Runtime.isActive() then
    if Display.present(self, w, h) then
      return
    end
  end

  love.graphics.clear(0.05, 0.05, 0.12)
  love.graphics.setColor(0.4, 0.8, 0.4)
  local map = self.session and self.session.map or "?"
  love.graphics.printf("Fire Red field: " .. tostring(map), 0, h * 0.45, w, "center")
end

function Game3:keypressed(key)
  if self.input and self.input.keypressed then self.input:keypressed(key) end
end
function Game3:keyreleased(key)
  if self.input and self.input.keyreleased then self.input:keyreleased(key) end
end
function Game3:gamepadpressed(joystick, button)
  if self.input and self.input.gamepadpressed then self.input:gamepadpressed(joystick, button) end
end
function Game3:gamepadreleased(joystick, button)
  if self.input and self.input.gamepadreleased then self.input:gamepadreleased(joystick, button) end
end

function Game3:saveGame()
  if not self.session then return end
  if Runtime.getSession then
    local s = Runtime.getSession()
    if s then self.session = s end
  end
  self.save = Schema.toSaveTable(self.session)
  if SaveData.save then pcall(SaveData.save, self.save) end
end

function Game3:resize() end
function Game3:mousepressed() end
function Game3:mousereleased() end
function Game3:mousemoved() end
function Game3:wheelmoved() end
function Game3:textinput() end
function Game3:filedropped() end
function Game3:touchpressed() end
function Game3:touchmoved() end
function Game3:touchreleased() end
function Game3:gamepadaxis() end
function Game3:joystickpressed() end
function Game3:joystickreleased() end
function Game3:joystickaxis() end
function Game3:joystickhat() end
function Game3:joystickadded() end
function Game3:joystickremoved() end
function Game3:focus(f)
  if f then
    Audio.onFocusGained()
  end
end

function Game3:visible(v)
  if v then
    Audio.onFocusGained()
  end
end

function Game3:onResume()
  Audio.onFocusGained()
end
function Game3:quit()
  self:saveGame()
end

return Game3
