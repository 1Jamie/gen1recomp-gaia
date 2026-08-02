-- Fixed-step update loop at the Game Boy's ~60Hz.  Game logic advances in
-- whole steps regardless of the display refresh rate, which keeps movement,
-- text speed and battle timing deterministic.

local FixedStep = {}

FixedStep.STEP = 1 / 60
local MAX_ACCUM = 0.25 -- avoid spiral of death after a stall

function FixedStep:init(callback)
  self.accum = 0
  self.callback = callback
  self.suppressCatchup = false
end

-- The anti-spiral clamp doubles as a steps-per-frame ceiling (0.25s = 15
-- steps), which silently throttled the high fast-forward levels: at 100X
-- a 60fps frame wants ~100 steps. Game:update raises this to fit the
-- current speed target; a stall still cannot snowball past one frame's
-- intended budget.
FixedStep.maxAccum = MAX_ACCUM

function FixedStep:update(dt)
  -- A hitch's oversized dt lands on the frame AFTER discardCatchup was
  -- called (the hitch itself already ran inside the current step); absorb
  -- that one frame as a single step instead of the normal accumulator so
  -- the burst it would otherwise release doesn't play out as a slide.
  if self.suppressCatchup then
    self.suppressCatchup = false
    self.accum = 0
    self.callback(self.STEP)
    return
  end
  self.accum = math.min(self.accum + dt, self.maxAccum or MAX_ACCUM)
  while self.accum >= self.STEP do
    self.accum = self.accum - self.STEP
    self.callback(self.STEP)
  end
end

-- Drop any pending catch-up steps and arm the one-frame clamp above.  A
-- hitch inside one logic step (map seam setMap / song start) makes the
-- next real-time dt huge; without this the while-loop above would advance
-- many walk frames before the next draw, which looks like a slide with no
-- leg animation (issue #93).
function FixedStep:discardCatchup()
  self.accum = 0
  self.suppressCatchup = true
end

return FixedStep
