local Ops = require("Ops")
local P = require("PokeblockOps")
local Touch = require("TouchEditor")
local Theme = require("Theme")
local PAL = Theme.PAL
local M = {}

local function selected(S)
  local n = tonumber(S.pokeblockSlot) or 1
  if n < 1 or n > P.COUNT or n ~= math.floor(n) then n = 1 end
  S.pokeblockSlot = n
  return n
end

function M.draw(S, Kit, x, y, w, h)
  local s, gap, row = Kit.scale, 8 * Kit.scale, Kit.controlH()
  S.pokeblockScroll = Kit.scrollPixels(x, y, w, h, S.pokeblockScroll or 0, S._pokeblockHeight or 0)
  Kit.pushClip(x, y, w, h)
  local start = y - S.pokeblockScroll
  local cy = start
  local slot = selected(S)
  local free = P.firstFree(S.save)
  local addW = Kit.buttonWidth("Add block", { font = "small", kind = "good", icon = "plus" }, row)
  Kit.text("small", "Pokéblock Case  " .. P.count(S.save) .. " / " .. P.COUNT, x,
    cy + (row - Kit.textHeight("small")) / 2, PAL.text)
  if Kit.button(x + w - addW, cy, addW, row, "Add block",
    { font = "small", kind = "good", icon = "plus", enabled = free ~= nil }) then
    P.add(S)
  end
  cy = cy + row + gap
  local wide = w >= 760 * s
  local gw = wide and math.floor(w * 0.55) or w
  local cols = math.max(1, math.min(5, math.floor((gw + gap) / (110 * s + gap))))
  local cw = (gw - (cols - 1) * gap) / cols
  for i = 1, P.COUNT do
    local b = P.block(S.save, i)
    local label = i .. "  " .. (b.color == 0 and "Empty" or P.colorName(b.color))
    if Kit.button(x + (i - 1) % cols * (cw + gap), cy + math.floor((i - 1) / cols) * (row + gap), cw, row,
      label, { face = "tab", font = "small", align = "left", active = i == slot, id = "pokeblock-slot-" .. i }) then
      S.pokeblockSlot = i
      Ops.disarm(S)
    end
  end
  local gridBottom = cy + math.ceil(P.COUNT / cols) * (row + gap) + gap
  if wide then
    x, w = x + gw + 2 * gap, w - gw - 2 * gap
  else
    cy = gridBottom
  end
  local block = P.block(S.save, slot)
  if block.color == 0 then
    local boxH = 2 * row
    Kit.emptyBox(x, cy, w, boxH, "Slot " .. slot .. " is empty")
    cy = cy + boxH + gap
    if Kit.button(x, cy, w, row, "Add here", { font = "small", kind = "good", icon = "plus" }) then
      P.add(S, slot)
    end
    cy = cy + row + gap
  else
    Kit.text("small", "Slot " .. slot .. ": " .. P.colorName(block.color) .. " Pokéblock", x, cy, PAL.text)
    cy = cy + Kit.textHeight("small") + gap
    cy = cy + Touch.choice(S, Kit, "pokeblock-color", "Color", block.color, P.colorOptions(), x, cy, w,
      function(v) return P.set(S, slot, "color", v) end,
      "The block's color, as the case and Blender name it.") + gap
    for _, field in ipairs({ "spicy", "dry", "sweet", "bitter", "sour", "feel" }) do
      local help = field == "feel"
        and "Feel adds to sheen when fed; the game counts at most 99. Choose 0 to 255."
        or "Raises the matching contest condition when fed. Choose 0 to 255."
      cy = cy + Touch.value(S, Kit, "pokeblock-" .. field, P.FIELD_NAMES[field], block[field],
        { lo = 0, hi = P.MAX_BYTE, help = help }, x, cy, w,
        function(v) return P.set(S, slot, field, v) end) + gap
    end
    local armId = "pokeblock-delete-" .. slot
    if Kit.button(x, cy, w, row, Ops.armLabel(S, armId, "Delete block"),
      { font = "small", kind = "danger", icon = "trash" }) then
      if Ops.arm(S, armId, "Delete this Pokéblock? Tap again to confirm") then P.clear(S, slot) end
    end
    cy = cy + row + gap
  end
  S._pokeblockHeight = math.max(cy, gridBottom) - start
  Kit.popClip()
end

return M
