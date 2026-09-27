local Std = require("src.core.game3.scripting.stdscripts")

local NativesPuzzlesRse = {}

NativesPuzzlesRse.SOURCES = {
  "src.core.game3.braille_field",
  "src.core.game3.mirage_tower",
  "src.core.game3.faraway_island",
  "src.core.game3.special_scene_rse",
}

NativesPuzzlesRse.BY_NAME = {
  -- pokeemerald/src/rotating_gate.c:933
  RotatingGate_InitPuzzle = function()
    require("src.core.game3.rotating_gate").initPuzzle()
    return false
  end,
  -- pokeemerald/src/rotating_gate.c:951
  RotatingGate_InitPuzzleAndGraphics = function()
    require("src.core.game3.rotating_gate").initPuzzleAndGraphics()
    return false
  end,
}

for _, name in ipairs(NativesPuzzlesRse.SOURCES) do
  for special, fn in pairs(require(name).BY_NAME or {}) do
    NativesPuzzlesRse.BY_NAME[special] = fn
  end
end

require("src.core.game3.rotating_tile_puzzle")

Std.legacyHandlers(NativesPuzzlesRse)

return NativesPuzzlesRse
