local Ops = require("Ops")
local Gen = require("Gen")
local PAL = require("Theme").PAL
local M = {}
function M.draw(S, Kit, x, y, w, h)
  Kit.card(x, y, w, h)
  local pad, gap, row = 14 * Kit.scale, 10 * Kit.scale, Kit.controlH()
  local cx, inner = x + pad, w - 2 * pad
  local g = Gen.ofState(S)
  local fields = {
    {
      "name",
      "Trainer name",
      (S.save.player and S.save.player.name) or S.save.name or S.save.playerName or "",
    },
    { "id", "Trainer ID (0-65535)", (S.save.player and S.save.player.id) or S.save.trainerId or 0 },
    { "money", "Money (0-999999)", Gen.money(S.save) },
    { "coins", "Coins (0-9999)", Gen.coins(S.save) },
  }
  if g == 3 then
    table.insert(fields, 3, { "secretId", "Secret ID (0-65535)", S.save.secretId or 0 })
  end
  local contentH = pad * 2
    + #fields * (Kit.textHeight("small") + gap + row + gap)
    + (Gen.hasPlayerGender(S.save, S.version) and row + gap or 0)
  S.trainerScroll = Kit.scrollPixels(x, y, w, h, S.trainerScroll or 0, contentH)
  Kit.pushClip(x, y, w, h)
  local cy = y + pad - S.trainerScroll
  S.trainerDrafts = S.trainerDrafts or {}
  for _, f in ipairs(fields) do
    Kit.text("small", f[2], cx, cy, PAL.text)
    cy = cy + Kit.textHeight("small") + gap
    local key = "trainer-" .. f[1]
    local setW = math.max(row, 64 * Kit.scale)
    local function apply(v)
      if Ops.setTrainerProperty(S, f[1], v) then
        S.trainerDrafts[f[1]] = nil
      end
    end
    S.trainerDrafts[f[1]] = Kit.textfield(
      key,
      cx,
      cy,
      inner - setW - gap,
      row,
      S.trainerDrafts[f[1]] or tostring(f[3]),
      "value",
      { onSubmit = apply }
    )
    if Kit.button(cx + inner - setW, cy, setW, row, "Set", { kind = "accent", font = "small" }) then
      apply(S.trainerDrafts[f[1]])
      Kit.blur()
    end
    cy = cy + row + gap
  end
  if Gen.hasPlayerGender(S.save, S.version) then
    local half = (inner - gap) / 2
    for i, v in ipairs({ "male", "female" }) do
      if
        Kit.chip(
          cx + (i - 1) * (half + gap),
          cy,
          half,
          row,
          v:upper(),
          Gen.playerGender(S.save) == v
        )
      then
        Ops.setPlayerGender(S, v)
      end
    end
  end
  Kit.popClip()
end
return M
