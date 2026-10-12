-- Pure pixel bake of a RED++ (GBC pack) tileset atlas.  No love.graphics and
-- no PaletteFX / save state, so the same code runs on the main thread (the
-- synchronous TileRenderer path) and in src/render/atlas_worker.lua.  The
-- caller resolves every palette decision up front and hands over plain data.

local AtlasBake = {}

-- shade 0-3 -> one of `colors`' 4 entries (same cutoffs PaletteFX's shader
-- uses), alpha passed through unchanged; nil/false colors leaves r,g,b as-is.
-- Shared by the whole-atlas bake and TileRenderer's animated-tile variants,
-- so water/flowers/spinners match the static tiles around them under RED++.
local function recolorSample(r, g, b, a, colors)
  if not (colors and a > 0) then return r, g, b, a end
  local col = r > 0.83 and colors[1] or r > 0.5 and colors[2]
              or r > 0.17 and colors[3] or colors[4]
  return col[1] / 255, col[2] / 255, col[3] / 255, a
end
AtlasBake.recolorSample = recolorSample

-- src / out: ImageData-like (getDimensions / getPixel / setPixel), same size.
-- tileColors: tile index (0-based) -> 4-colour palette, or false for "copy".
-- aliases: list of { tile, alias, colors }; bakes a copy of `tile` into the
-- spare slot `alias` (skipped when the slot lies outside the atlas).
function AtlasBake.bake(src, out, perRow, tileColors, aliases)
  local iw, ih = src:getDimensions()
  local total = (iw / 8) * (ih / 8)
  for t = 0, total - 1 do
    local colors = tileColors[t] or false
    local ox, oy = (t % perRow) * 8, math.floor(t / perRow) * 8
    for py = 0, 7 do
      for px = 0, 7 do
        local sx, sy = ox + px, oy + py
        local r, g, b, a = src:getPixel(sx, sy)
        r, g, b, a = recolorSample(r, g, b, a, colors)
        out:setPixel(sx, sy, r, g, b, a)
      end
    end
  end
  for _, al in ipairs(aliases or {}) do
    if al.alias < total then
      local colors = al.colors
      local sxo = (al.tile % perRow) * 8
      local syo = math.floor(al.tile / perRow) * 8
      local dxo = (al.alias % perRow) * 8
      local dyo = math.floor(al.alias / perRow) * 8
      for py = 0, 7 do
        for px = 0, 7 do
          local r, g, b, a = src:getPixel(sxo + px, syo + py)
          r, g, b, a = recolorSample(r, g, b, a, colors)
          out:setPixel(dxo + px, dyo + py, r, g, b, a)
        end
      end
    end
  end
  return out
end

return AtlasBake
