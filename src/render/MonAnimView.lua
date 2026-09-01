-- ../pokecrystal/engine/gfx/pic_animation.asm:79-89 AnimateFrontpic

local MonAnim = require("src.render.MonAnim")
local Unown = require("src.core.gen2.Unown")

local MonAnimView = {}
MonAnimView.__index = MonAnimView

-- ../pokecrystal/engine/events/halloffame.asm:225-238
function MonAnimView.animData(def, mon)
  if not def then return nil end
  local data = def.anim
  if mon and mon.species == Unown.SPECIES and def.letters then
    local entry = def.letters[Unown.name(Unown.monLetter(mon))]
    if entry and entry.anim then data = entry.anim end
  end
  return data
end

function MonAnimView.start(def, mon, scene, imageFn, onCry)
  local data = MonAnimView.animData(def, mon)
  if not (data and data.tiles and imageFn) then return nil end
  local sheet = imageFn(data.sheet)
  if not sheet then return nil end
  local runner = MonAnim.new(data, scene, onCry)
  if not runner then return nil end
  return setmetatable({
    runner = runner,
    sheet = sheet,
    size = data.tiles * 8,
    quads = {},
  }, MonAnimView)
end

function MonAnimView:step()
  self.runner:update()
  return self.runner:finished()
end

function MonAnimView:finished() return self.runner:finished() end

function MonAnimView:currentFrame() return self.runner:currentFrame() end

-- ../pokecrystal/engine/gfx/pic_animation.asm:431-435
function MonAnimView:frame()
  local frame = self.runner:currentFrame()
  if frame <= 0 then return nil end
  local quad = self.quads[frame]
  if not quad then
    local w, h = self.sheet:getDimensions()
    if (frame + 1) * self.size > h then return nil end
    quad = love.graphics.newQuad(0, frame * self.size, self.size, self.size,
      w, h)
    self.quads[frame] = quad
  end
  return self.sheet, quad, self.size
end

return MonAnimView
