-- FRLG battler healthboxes via pret OAM semantics + interface element tiles.
-- CreateSprite centers; HP bar subsprites are offsets from that center
-- (AddSubspritesToOamBuffer undoes centerToCorner, then applies subsprite x/y).
--
-- Healthbox GFX bake placeholder "Lv" / "/" tiles; pret TextIntoHealthboxObject
-- overwrites them. We cream-fill those regions and print like UpdateNick /
-- UpdateLvl / UpdateHpTextInHealthbox.

local BattleChrome = require("src.ui.game3.battle_chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local State = require("src.core.game3.battle.state")

local Healthbox = {}

-- pret InitBattlerHealthboxCoords (singles) — sprite CENTER of left half
Healthbox.ENEMY_CENTER = { x = 44, y = 30 }
Healthbox.PLAYER_CENTER = { x = 158, y = 88 }

-- Cream fill matches healthbox pal index 2 (text bg).
local CREAM = { 248 / 255, 248 / 255, 216 / 255, 1 }

-- Healthbox OBJ pal text colors (gBattleInterface_Healthbox_Pal).
-- Nick: fg=1 shadow=3; gender uses DYNAMIC_COLOR_2/1 (pal 11 / 10).
local HB_TEXT = {
  fg = { 64 / 255, 64 / 255, 64 / 255, 1 },
  shadow = { 216 / 255, 208 / 255, 176 / 255, 1 },
}
local HB_MALE = {
  fg = { 65 / 255, 205 / 255, 255 / 255, 1 },
  shadow = { 0 / 255, 98 / 255, 148 / 255, 1 },
}
local HB_FEMALE = {
  fg = { 255 / 255, 156 / 255, 148 / 255, 1 },
  shadow = { 156 / 255, 65 / 255, 57 / 255, 1 },
}

-- Inner cream right edge of assembled sheets (exclusive text end X).
local PLAYER_TEXT_RIGHT = 96
local ENEMY_TEXT_RIGHT = 89

-- pret AddTextPrinterAndCreateWindowOnHealthbox(..., y=3) for nick / level.
local TEXT_Y = 3
-- HP printer y=5 within 16px tile row → ~20 on assembled player sheet.
local HP_NUM_Y = 20

-- Baked placeholder ink + drop-shadow on healthbox sheets.
-- Shadow is pal index 3 ≈ (222,214,181). Do NOT rectangle-fill (eats top border).
local PLAYER_PLACEHOLDER_INK = {
  -- "Lv" fg (66,66,66)
  { 64, 10 }, { 64, 11 }, { 68, 11 }, { 70, 11 },
  { 64, 12 }, { 68, 12 }, { 70, 12 },
  { 64, 13 }, { 68, 13 }, { 70, 13 },
  { 64, 14 }, { 65, 14 }, { 66, 14 }, { 67, 14 }, { 69, 14 },
  -- "Lv" shadow
  { 65, 11 }, { 71, 11 }, { 65, 12 }, { 71, 12 }, { 65, 13 }, { 71, 13 },
  { 68, 14 }, { 70, 14 }, { 71, 14 },
  { 64, 15 }, { 65, 15 }, { 66, 15 }, { 67, 15 }, { 68, 15 }, { 69, 15 }, { 70, 15 },
  -- "/" fg
  { 69, 25 }, { 68, 26 }, { 67, 27 }, { 66, 28 }, { 65, 29 }, { 64, 30 },
  -- "/" shadow
  { 69, 26 }, { 68, 27 }, { 67, 28 }, { 66, 29 }, { 65, 30 }, { 64, 31 },
}

local ENEMY_PLACEHOLDER_INK = {
  -- "Lv" fg
  { 56, 10 }, { 56, 11 }, { 60, 11 }, { 62, 11 },
  { 56, 12 }, { 60, 12 }, { 62, 12 },
  { 56, 13 }, { 60, 13 }, { 62, 13 },
  { 56, 14 }, { 57, 14 }, { 58, 14 }, { 59, 14 }, { 61, 14 },
  -- "Lv" shadow
  { 57, 11 }, { 63, 11 }, { 57, 12 }, { 63, 12 }, { 57, 13 }, { 63, 13 },
  { 60, 14 }, { 62, 14 }, { 63, 14 },
  { 56, 15 }, { 57, 15 }, { 58, 15 }, { 59, 15 }, { 60, 15 }, { 61, 15 }, { 62, 15 },
}

local function player_top_left(cx, cy)
  return cx - 32, cy - 16
end

local function enemy_top_left(cx, cy)
  return cx - 32, cy - 16
end

--- HP bar sprite center (SpriteCB_HealthBar).
local function hp_bar_center(side, hbCx, hbCy)
  if side == "player" then
    return hbCx + 16, hbCy
  end
  return hbCx + 8, hbCy
end

--- Subsprite 0 is at (−16, 0) from center → composite TL = (cx−16, cy).
local function hp_bar_top_left(barCx, barCy)
  return barCx - 16, barCy
end

local function hp_ratio(side, battler)
  local ok, Anim = pcall(require, "src.core.game3.battle.anim")
  if ok and Anim and Anim.displayHpRatio then
    return Anim.displayHpRatio(side, battler)
  end
  if not battler or not battler.mon then return 0 end
  local hp = tonumber(battler.mon.hp) or 0
  local maxHp = tonumber(battler.mon.maxHp) or 1
  if maxHp < 1 then maxHp = 1 end
  return math.max(0, math.min(1, hp / maxHp))
end

local function display_hp_nums(side, battler)
  local ok, Anim = pcall(require, "src.core.game3.battle.anim")
  if ok and Anim and Anim.displayHpRatio then
    local _, hp, maxHp = Anim.displayHpRatio(side, battler)
    return math.floor((hp or 0) + 0.5), math.floor((maxHp or 0) + 0.5)
  end
  local mon = battler and battler.mon
  return tonumber(mon and mon.hp) or 0, tonumber(mon and mon.maxHp) or 0
end

local function small_opts(colors)
  return { small = true, colors = colors or HB_TEXT }
end

local function erase_placeholder_ink(boxX, boxY, pts)
  love.graphics.setColor(CREAM)
  for i = 1, #pts do
    local p = pts[i]
    love.graphics.rectangle("fill", boxX + p[1], boxY + p[2], 1, 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Pret UpdateNickInHealthbox: hide gender when nick == species for Nidoran.
local function healthbox_gender(mon)
  if not mon then return nil end
  local g = mon.gender
  if g ~= "M" and g ~= "F" then
    local Pokemon = require("src.core.game3.pokemon")
    local species = tonumber(mon.species or mon.speciesId)
    if species and Pokemon.gender then
      g = Pokemon.gender(species, mon.personality)
    end
  end
  if g ~= "M" and g ~= "F" then return nil end
  local species = tonumber(mon.species or mon.speciesId) or 0
  -- SPECIES_NIDORAN_F=29, SPECIES_NIDORAN_M=32 (FRLG national)
  if species == 29 or species == 32 then
    local nick = tostring(mon.nickname or "")
    local sname = tostring(mon.name or "")
    if nick == "" or nick == sname then
      return nil
    end
  end
  return g
end

local function draw_name_gender(name, gender, x, y)
  FrlgFont.draw(name, x, y, small_opts(HB_TEXT))
  if not gender then return end
  local nw = FrlgFont.measure(name, { small = true })
  -- ♂/♀ join arrow↔circle mostly via shadow pixels; need HB shadow on cream
  -- (FrlgFont.COLOR.MALE shadow is nearly invisible here and splits the glyph).
  if gender == "M" then
    FrlgFont.drawGlyph(FrlgFont.CHAR_MALE, x + nw, y, small_opts(HB_MALE))
  elseif gender == "F" then
    FrlgFont.drawGlyph(FrlgFont.CHAR_FEMALE, x + nw, y, small_opts(HB_FEMALE))
  end
end

--- Pret UpdateLvlInHealthbox: {LV_2}+digits, right-aligned in the level slot.
local function draw_level(lv, boxX, y, textRight)
  local digits = tostring(lv or 1)
  local lvW = FrlgFont.advance(FrlgFont.CHAR_LV_2, { small = true })
  local digW = FrlgFont.measure(digits, { small = true })
  local x = boxX + textRight - (lvW + digW)
  FrlgFont.drawGlyph(FrlgFont.CHAR_LV_2, x, y, small_opts(HB_TEXT))
  FrlgFont.draw(digits, x + lvW, y, small_opts(HB_TEXT))
end

--- Pret singles HP text: current + CHAR_SLASH, max; visually "19/ 19" right-aligned.
local function draw_hp_nums(cur, maxHp, boxX, y, textRight)
  local text = string.format("%d/ %d", cur or 0, maxHp or 0)
  local w = FrlgFont.measure(text, { small = true })
  FrlgFont.draw(text, boxX + textRight - w, y, small_opts(HB_TEXT))
end

function Healthbox.draw(side, battler)
  if not battler then return end
  local Anim = require("src.core.game3.battle.anim")
  local stage = Anim.stage and Anim.stage()
  local hb = stage and stage.healthbox and stage.healthbox[side]
  if hb and hb.visible == false then return end
  local ox = (hb and hb.ox) or 0

  local isPlayer = side == "player"
  local c = isPlayer and Healthbox.PLAYER_CENTER or Healthbox.ENEMY_CENTER
  local tlX, tlY
  if isPlayer then
    tlX, tlY = player_top_left(c.x + ox, c.y)
    BattleChrome.drawPlayerBox(tlX, tlY)
    erase_placeholder_ink(tlX, tlY, PLAYER_PLACEHOLDER_INK)
  else
    tlX, tlY = enemy_top_left(c.x + ox, c.y)
    BattleChrome.drawEnemyBox(tlX, tlY)
    erase_placeholder_ink(tlX, tlY, ENEMY_PLACEHOLDER_INK)
  end

  local barCx, barCy = hp_bar_center(side, c.x + ox, c.y)
  local bx, by = hp_bar_top_left(barCx, barCy)
  BattleChrome.drawHpBar(bx, by, hp_ratio(side, battler))

  local name = State.displayName(battler)
  local lv = battler.mon and battler.mon.level or 1
  do
    local ok, AnimP = pcall(require, "src.core.game3.battle.anim")
    if ok and AnimP and AnimP.present then
      local p = AnimP.present(side)
      if p and p.displayLevel then lv = p.displayLevel end
    end
  end

  local ty = tlY + TEXT_Y
  local textRight = isPlayer and PLAYER_TEXT_RIGHT or ENEMY_TEXT_RIGHT
  local gender = healthbox_gender(battler.mon)

  local SummaryChrome = require("src.ui.game3.summary_chrome")
  local SummaryData = require("src.core.game3.summary_data")
  local stObj = battler.status or (battler.mon and (battler.mon.status or battler.mon.status1))
  local ailment = SummaryData.statusAilment({ status = stObj, hp = battler.mon and battler.mon.hp })

  if isPlayer then
    draw_name_gender(name, gender, tlX + 16, ty)
    draw_level(lv, tlX, ty, textRight)
    if ailment >= 1 and ailment <= 6 then
      SummaryChrome.drawStatusIcon(tlX + 16, tlY + 19, ailment)
    end
    local mon = battler.mon
    if mon then
      local cur, maxHp = display_hp_nums(side, battler)
      draw_hp_nums(cur, maxHp, tlX, tlY + HP_NUM_Y, textRight)
    end
    local expRatio = 0
    do
      local ok, AnimE = pcall(require, "src.core.game3.battle.anim")
      if ok and AnimE and AnimE.displayExpRatio then
        expRatio = AnimE.displayExpRatio(side, battler)
      else
        local Experience = require("src.core.game3.battle.experience")
        local prog = Experience.progress(battler.mon)
        expRatio = prog.progressPercent or 0
      end
    end
    BattleChrome.drawExpBar(tlX + 32, tlY + 32, expRatio)
  else
    draw_name_gender(name, gender, tlX + 8, ty)
    draw_level(lv, tlX, ty, textRight)
    if ailment >= 1 and ailment <= 6 then
      SummaryChrome.drawStatusIcon(tlX - 2, tlY + 17, ailment)
    end
  end
end

function Healthbox.syncOam(_st)
  return
end

return Healthbox
