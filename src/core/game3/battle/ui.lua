-- FRLG battle UI (pret battle_bg windows + battle_interface). Chrome from ROM extract.

local Message = nil
pcall(function()
  Message = require("src.ui.game3.message")
end)
local Choice = nil
pcall(function()
  Choice = require("src.ui.game3.choice")
end)

local Commands = require("src.core.game3.battle.commands")
local State = require("src.core.game3.battle.state")
local Moves = require("src.core.game3.battle.moves")
local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local BattleChrome = require("src.ui.game3.battle_chrome")
local BattleBg = require("src.core.game3.battle.bg")
local Healthbox = require("src.core.game3.battle.healthbox")
local Pokemon = require("src.core.game3.pokemon")
local Window = require("src.ui.game3.window")
local Types = require("src.core.game3.battle.types")

local Ui = {}

Ui._queue = {}
Ui._showing = false
Ui._headless = false
Ui._log = {}
Ui._mode = "none" -- "none"|"menu"|"moves"|"bag"
Ui._menuIndex = 1
Ui._moveIndex = 1
Ui._st = nil
Ui._pendingCommand = nil
Ui._session = nil

-- pret sBattlerCoords (singles) — CreateSprite CENTER before pic y_offset
local ENEMY_MON = { x = 176, y = 40 }
local PLAYER_MON = { x = 72, y = 80 }

local PicCoords = nil
pcall(function()
  PicCoords = require("src.core.game3.battle.pic_coords")
end)

--- pret GetBattlerSpriteFinal_Y (a3=TRUE / BATTLER_COORD_Y_PIC_OFFSET).
local function battler_sprite_center(side, species, base)
  local cx, cy = base.x, base.y
  if not PicCoords or not species then return cx, cy end
  local sp = tonumber(species) or 0
  if side == "player" then
    local yo = (PicCoords.back and PicCoords.back[sp]) or 0
    cy = cy + yo + 8 -- player +8 when a3
  else
    local yo = (PicCoords.front and PicCoords.front[sp]) or 0
    local elev = (PicCoords.elev and PicCoords.elev[sp]) or 0
    cy = cy + yo - elev
  end
  return cx, cy
end

function Ui.reset(opts)
  opts = opts or {}
  Ui._queue = {}
  Ui._showing = false
  Ui._headless = opts.headless and true or false
  Ui._log = {}
  Ui._mode = "none"
  Ui._menuIndex = 1
  Ui._moveIndex = 1
  Ui._st = nil
  Ui._pendingCommand = nil
  if not Ui._headless then
    pcall(BattleChrome.install, nil)
  end
end

function Ui.bindState(st, session)
  Ui._st = st
  if session ~= nil then Ui._session = session end
end

function Ui.bindSession(session)
  Ui._session = session
end

function Ui.push(text)
  if not text or text == "" then return end
  Ui._log[#Ui._log + 1] = text
  Ui._queue[#Ui._queue + 1] = text
end

function Ui.busy()
  if Ui._headless then return false end
  if Choice and Choice.active then return true end
  if Message and Message.isOpen and Message.isOpen() then return true end
  if Ui._showing then return true end
  if #Ui._queue > 0 then return true end
  return false
end

--- True while battle text is queued or on screen (intro / turn messages).
function Ui.dialogPending()
  if Ui._headless then return false end
  if Message and Message.isOpen and Message.isOpen() then return true end
  if Ui._showing then return true end
  return #Ui._queue > 0
end

--- YES/NO during award/learn (Choice.yesNo). cb(true|false)
function Ui.askYesNo(cb)
  if Ui._headless then
    if cb then cb(false) end
    return
  end
  if not Choice then
    if cb then cb(false) end
    return
  end
  Choice.yesNo(cb, { left = 22, top = 8 })
end

--- Multi-choice forget list. cb(0-based index) or cb(-1)/cb(127) on cancel.
function Ui.askForget(labels, cb)
  if Ui._headless then
    if cb then cb(-1) end
    return
  end
  if not Choice then
    if cb then cb(-1) end
    return
  end
  Choice.multi(labels, 0, cb, { left = 14, top = 2 })
end

function Ui.choiceActive()
  return Choice and Choice.active
end

function Ui.waitingForCommand()
  return Ui._mode == "menu" or Ui._mode == "moves" or Ui._mode == "bag"
end

local function open_battle_bag()
  local BagMenu = require("src.ui.game3.bag_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Ui._session
    or (Runtime and Runtime.getSession and Runtime.getSession())
  local bag = session and session.bag
  if not bag then
    Ui.push("The BAG is empty.")
    Ui._mode = "menu"
    return
  end
  Ui._mode = "bag"
  BagMenu.show(bag, {
    session = session,
    battle = true,
    onBattleUse = function(itemId, partySlot)
      if itemId == nil then
        Ui._mode = "menu"
        return
      end
      Ui._pendingCommand = {
        kind = "bag",
        user = "player",
        itemId = itemId,
        partySlot = partySlot,
      }
      Ui._mode = "none"
    end,
    onClose = function()
      -- close already notifies onBattleUse(nil) when cancelled
    end,
  })
end

function Ui.isShowing()
  return Ui._showing or Ui.busy() or (Message and Message.isOpen and Message.isOpen())
end

local function open_battle_party()
  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Ui._session
    or (Runtime and Runtime.getSession and Runtime.getSession())
  local State = require("src.core.game3.battle.state")
  if Ui._st and Ui._st.player and Ui._st.playerParty then
    State.syncBattlerToParty(Ui._st.player, Ui._st.playerParty)
  end
  local party = (Ui._st and Ui._st.playerParty) or (session and session.party)
  local overlay = (session and session.move_overlay)
  local activeSlot = (Ui._st and Ui._st.player and Ui._st.player.partyIndex) or 1
  Ui._mode = "party"
  PartyMenu.show(party, overlay, {
    mode = "battle_switch",
    session = session,
    activeSlot = activeSlot,
    battle = true,
    onSelect = function(slot)
      if slot == nil or slot == activeSlot then
        Ui._mode = "menu"
        return
      end
      Ui._pendingCommand = {
        kind = "switch",
        user = "player",
        slot = slot,
      }
      Ui._mode = "none"
    end,
    onClose = function()
      Ui._mode = "menu"
    end,
  })
end

function Ui.openMenu()
  Ui._mode = "menu"
  Ui._menuIndex = 1
  Ui._pendingCommand = nil
  if Message and Message.open then
    Message.open = false
  end
  Ui._showing = false
end

function Ui.takeCommand()
  local c = Ui._pendingCommand
  Ui._pendingCommand = nil
  return c
end

local function show_next()
  if Ui._showing then return end
  if #Ui._queue == 0 then return end
  local text = table.remove(Ui._queue, 1)
  if Ui._headless then return end
  if Message and Message.show then
    Ui._showing = true
    Message.show(text, {
      frame = "battle",
      battle = true,
      done = function()
        Ui._showing = false
      end,
    })
  end
end

function Ui.pump()
  if Ui._headless then
    while #Ui._queue > 0 do table.remove(Ui._queue, 1) end
    Ui._showing = false
    return true
  end
  if Message and Message.isOpen and Message.isOpen() then
    return false
  end
  Ui._showing = false
  if #Ui._queue > 0 then
    show_next()
    return false
  end
  return true
end

local function play_select()
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    Audio.playSe(SE.SE_SELECT)
  end)
end

local function grid_nav(index, input, maxN)
  local c = (index or 1) - 1
  if input:wasPressed("left") or input:wasPressed("right") then
    c = (c % 2 == 0) and (c + 1) or (c - 1)
  elseif input:wasPressed("up") or input:wasPressed("down") then
    c = (c < 2) and (c + 2) or (c - 2)
  else
    return index, false
  end
  if c < 0 then c = 0 end
  if c >= maxN then c = maxN - 1 end
  return c + 1, true
end

function Ui.handleInput(input)
  if not input then return false end

  -- Learn-move / evo YES-NO and forget list
  if Choice and Choice.active then
    if input:wasPressed("up") then
      Choice.move(-1)
      return true
    elseif input:wasPressed("down") then
      Choice.move(1)
      return true
    elseif input:wasPressed("a") then
      Choice.confirm()
      return true
    elseif input:wasPressed("b") then
      Choice.cancel()
      return true
    end
    return true
  end

  if not Ui.waitingForCommand() then return false end
  if Ui._mode == "menu" then
    local idx, moved = grid_nav(Ui._menuIndex, input, 4)
    if moved then
      Ui._menuIndex = idx
      play_select()
      return true
    end
    if input:wasPressed("a") then
      play_select()
      local kind = Commands.MENU[Ui._menuIndex]
      if kind == "FIGHT" then
        Ui._mode = "moves"
        Ui._moveIndex = 1
      elseif kind == "BAG" then
        open_battle_bag()
      elseif kind == "POKEMON" or kind == "POKéMON" then
        open_battle_party()
      else
        Ui._pendingCommand = Commands.playerAction(Ui._st, Ui._menuIndex, nil)
        Ui._mode = "none"
      end
      return true
    elseif input:wasPressed("b") then
      return true
    end
  elseif Ui._mode == "bag" or Ui._mode == "party" then
    -- Input owned by BagMenu / PartyMenu via Battle.update
    return true
  elseif Ui._mode == "moves" then
    local idx, moved = grid_nav(Ui._moveIndex, input, 4)
    if moved then
      Ui._moveIndex = idx
      play_select()
      return true
    end
    if input:wasPressed("a") then
      play_select()
      Ui._pendingCommand = Commands.playerAction(Ui._st, 1, Ui._moveIndex)
      Ui._mode = "none"
      return true
    elseif input:wasPressed("b") then
      play_select()
      Ui._mode = "menu"
      return true
    end
  end
  return false
end

local function draw_menu_text(text, x, y)
  FrlgFont.draw(tostring(text or ""), x, y, {
    small = true,
    colors = FrlgFont.COLOR.PARTY,
  })
end

local function draw_prompt_text(text, x, y)
  FrlgFont.draw(tostring(text or ""), x, y, {
    colors = FrlgFont.COLOR.WHITE,
  })
end

--- Draw mon pic at GetBattlerSpriteFinal_Y center (64×64 → TL = center−32).
-- Applies Anim present offsets / alpha / visibility / z (Dig/Fly hide).
local function draw_mon_sprite(battler, base, back)
  if not battler then return end
  local side = back and "player" or "enemy"
  local Anim = require("src.core.game3.battle.anim")
  local pres = Anim.present(side)
  if pres and pres.visible == false then return end

  local sp = battler.species
  if not sp and battler.mon and Pokemon.speciesOf then
    sp = Pokemon.speciesOf(battler.mon)
  elseif not sp and battler.mon then
    sp = battler.mon.species or battler.mon.speciesId
  end
  local cx, cy = battler_sprite_center(side, sp, base)
  if pres then
    cx = cx + (pres.ox or 0)
    cy = cy + (pres.oy or 0)
  end
  local scale = (pres and pres.scale) or 1
  local darken = (pres and pres.darken) or 0
  local entry
  if back and Pokemon.backPic then
    entry = Pokemon.backPic(sp)
  end
  if not entry then
    entry = Pokemon.frontPic and Pokemon.frontPic(sp)
  end
  if entry and entry.image then
    local a = (pres and pres.alpha) or 1
    local flash = pres and (pres.flash or 0) or 0
    local shade = 1 - darken * (1 - 8 / 255)
    if flash > 0 then
      love.graphics.setColor(1, 1, 1, a * (0.4 + 0.6 * ((flash % 2 == 0) and 1 or 0.3)))
    else
      love.graphics.setColor(shade, shade, shade, a)
    end
    local hFlip = (pres and pres.hFlip) and true or false
    local sx = (hFlip and -1 or 1) * scale
    love.graphics.draw(entry.image, cx, cy, 0, sx, scale, 32, 32)
  else
    -- Placeholder silhouette so lunge/shake is visible before full pic extract.
    local a = (pres and pres.alpha) or 1
    local flash = pres and (pres.flash or 0) or 0
    if flash > 0 and flash % 2 == 0 then
      love.graphics.setColor(1, 1, 1, a)
    elseif back then
      love.graphics.setColor(0.35, 0.55, 0.95, a)
    else
      love.graphics.setColor(0.95, 0.45, 0.35, a)
    end
    local hw = 24 * scale
    love.graphics.rectangle("fill", cx - hw, cy - hw, hw * 2, hw * 2)
    love.graphics.setColor(1, 1, 1, a * 0.9)
    love.graphics.rectangle("line", cx - hw, cy - hw, hw * 2, hw * 2)
  end
end

local function draw_action_menu(st)
  -- B_WIN_ACTION_PROMPT @ (1,15) after scroll → px (8,120); printer (2,2) → (10,122)
  -- B_WIN_ACTION_MENU @ (17,15) → (136,120); printer (0,2) → (136,122)
  -- ActionSelectionCreateCursorAt: tile (16+7*col, 35+row) → after scroll (128,120);
  -- cursor is a 1×2 BG pip whose ink lines up with printer y=2 text → draw at text Y.
  local name = st and st.player and State.displayName(st.player) or "POKéMON"
  draw_prompt_text(string.format("What will\n%s do?", name), 10, 122)
  local labels = { "FIGHT", "BAG", "POKéMON", "RUN" }
  local positions = {
    { 136, 122 }, { 184, 122 },
    { 136, 138 }, { 184, 138 },
  }
  local c = Ui._menuIndex - 1
  local cursorPos = {
    { 128, 122 }, { 176, 122 },
    { 128, 138 }, { 176, 138 },
  }
  local cp = cursorPos[c + 1] or cursorPos[1]
  Window.cursorPx(cp[1], cp[2], { colors = FrlgFont.COLOR.NORMAL })
  for i, pos in ipairs(positions) do
    draw_menu_text(labels[i], pos[1], pos[2])
  end
end

local function draw_move_menu(st)
  local mon = st and st.player and st.player.mon
  local positions = {
    { 16, 122 }, { 88, 122 },
    { 16, 138 }, { 88, 138 },
  }
  local cursorPos = {
    { 8, 122 }, { 80, 122 },
    { 8, 138 }, { 80, 138 },
  }
  local c = Ui._moveIndex - 1
  local cp = cursorPos[c + 1] or cursorPos[1]
  Window.cursorPx(cp[1], cp[2], { colors = FrlgFont.COLOR.NORMAL })
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    local label = "—"
    if mv and mv ~= 0 and mv ~= "" then
      label = Moves.displayName(mv)
    end
    draw_menu_text(label, positions[i][1], positions[i][2])
  end
  local slot = Ui._moveIndex
  local mv = mon and mon.moves and mon.moves[slot]
  if mv and mv ~= 0 and mv ~= "" then
    local def = Moves.get(mv)
    local pp = mon.pp and mon.pp[slot] or 0
    local maxPp = mon.maxPp and mon.maxPp[slot] or (def and def.pp) or pp
    draw_menu_text(string.format("PP %d/%d", pp, maxPp), 168, 122)
    draw_menu_text(Types.get(def and def.type) or "NORMAL", 168, 138)
  end
end


local function draw_trainer_sprites(stage)
  if not stage or not stage.trainer then return end
  local TrainerPic = require("src.core.game3.trainer_pic")
  local te = stage.trainer.enemy
  if te and te.visible then
    local picId = te.picId
    if picId ~= nil then
      local entry = TrainerPic.front(picId)
      if entry and entry.image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(entry.image, 176 + (te.ox or 0) - 32, 40 + (te.oy or 0) - 32)
      end
    end
  end
  local tp = stage.trainer.player
  if tp and tp.visible then
    local entry = TrainerPic.back(tp.gender or 0)
    if entry and entry.image then
      local frame = math.max(0, math.min(4, tonumber(tp.frame) or 0))
      local q = stage._backQuad
      if not q and love and love.graphics then
        -- quads cached on stage weakly; recreate each frame is fine for one sprite
      end
      local key = "back_" .. tostring(frame)
      Ui._trainerQuads = Ui._trainerQuads or {}
      if not Ui._trainerQuads[key] then
        Ui._trainerQuads[key] = love.graphics.newQuad(0, frame * 64, 64, 64, 64, 320)
      end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        entry.image, Ui._trainerQuads[key],
        80 + (tp.ox or 0) - 32, 80 + (tp.oy or 0) - 32)
    end
  end
end

local function draw_intro_ball(stage)
  if not stage or not stage.ball or not stage.ball.visible then return end
  local bx = (stage.ball.x or 0) + (stage.ball.ox or 0)
  local by = (stage.ball.y or 0) + (stage.ball.oy or 0)
  local rot = tonumber(stage.ball.rot) or 0
  local frame = math.max(0, math.min(2, tonumber(stage.ball.frame) or 0))
  local darken = tonumber(stage.ball.darken) or 0
  local flash = tonumber(stage.ball.flash) or 0
  local shade = math.max(0, math.min(1, 1 - darken * (1 - 8 / 255)))

  if flash > 0 and flash % 2 == 0 then
    love.graphics.setColor(1, 1, 1, 1)
  else
    love.graphics.setColor(shade, shade, shade, 1)
  end

  Ui._ballPoke = Ui._ballPoke or nil
  local img = Ui._ballPoke
  if img == nil then
    local candidates = {
      "data/generated/gba/intro/ball_poke.png",
      "data/generated/gba/intro/ballPoke.png",
    }
    for _, rel in ipairs(candidates) do
      if love and love.filesystem and love.filesystem.getInfo(rel) then
        local ok, loaded = pcall(love.graphics.newImage, rel)
        if ok and loaded then
          if loaded.setFilter then loaded:setFilter("nearest", "nearest") end
          img = loaded
          break
        end
      end
    end
    Ui._ballPoke = img or false
  end

  if img then
    Ui._ballQuads = Ui._ballQuads or {}
    local key = "ball_" .. frame
    if not Ui._ballQuads[key] then
      local iw, ih = img:getDimensions()
      Ui._ballQuads[key] = love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih)
    end
    love.graphics.draw(img, Ui._ballQuads[key], bx, by, rot, 1, 1, 8, 8)
  else
    -- Procedural 16x16 Poké Ball fallback
    love.graphics.push()
    love.graphics.translate(bx, by)
    love.graphics.rotate(rot)
    love.graphics.setColor(0.9, 0.2, 0.2, 1)
    love.graphics.arc("fill", 0, 0, 7, math.pi, 0)
    love.graphics.setColor(0.95, 0.95, 0.95, 1)
    love.graphics.arc("fill", 0, 0, 7, 0, math.pi)
    love.graphics.setColor(0.15, 0.15, 0.15, 1)
    love.graphics.circle("line", 0, 0, 7)
    love.graphics.rectangle("fill", -7, -1, 14, 2)
    love.graphics.circle("fill", 0, 0, 2.5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 0, 0, 1.2)
    love.graphics.pop()
  end

  -- Draw capture success stars / sparkles around the Poké Ball
  if stage.ball.stars and #stage.ball.stars > 0 then
    for _, star in ipairs(stage.ball.stars) do
      if star.visible ~= false then
        local sx = math.floor(bx + (star.ox or 0) + 0.5)
        local sy = math.floor(by + (star.oy or 0) + 0.5)
        local a = star.alpha or 1.0
        local rot = star.rot or 0
        local r = 4.5
        local rIn = 1.3

        -- 4-pointed sparkle star with contrast outline and bright white core
        love.graphics.push()
        love.graphics.translate(sx, sy)
        if rot ~= 0 then love.graphics.rotate(rot) end

        -- Dark border for clear contrast against any background
        love.graphics.setColor(0.15, 0.1, 0.0, a * 0.7)
        love.graphics.polygon("fill",
          0, -(r + 1),
          (rIn + 0.5), -(rIn + 0.5),
          (r + 1), 0,
          (rIn + 0.5), (rIn + 0.5),
          0, (r + 1),
          -(rIn + 0.5), (rIn + 0.5),
          -(r + 1), 0,
          -(rIn + 0.5), -(rIn + 0.5)
        )

        -- Vibrant golden star body
        love.graphics.setColor(1.0, 0.88, 0.15, a)
        love.graphics.polygon("fill",
          0, -r,
          rIn, -rIn,
          r, 0,
          rIn, rIn,
          0, r,
          -rIn, rIn,
          -r, 0,
          -rIn, -rIn
        )

        -- Bright white center sparkle / shine
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.rectangle("fill", -1, -1, 2, 2)
        love.graphics.pop()
      end
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_party_bars(stage)
  if not stage or not stage.partyBar then return end
  local m = BattleChrome.manifest and BattleChrome.manifest() or {}
  local enemy = stage.partyBar.enemy
  if enemy and enemy.visible then
    local pos = m.partyBarOpponent or { x = 104, y = 40 }
    BattleChrome.drawPartyBar(pos.x, pos.y, enemy.balls, enemy.ox)
  end
  local player = stage.partyBar.player
  if player and player.visible then
    local pos = m.partyBarPlayer or { x = 136, y = 96 }
    BattleChrome.drawPartyBar(pos.x, pos.y, player.balls, player.ox)
  end
end

function Ui.draw(w, h)
  if not (love and love.graphics) then return end
  w = w or Display.W
  h = h or Display.H

  if not BattleBg.draw() then
    love.graphics.setColor(0.92, 0.94, 0.96, 1)
    love.graphics.rectangle("fill", 0, 0, w, 112)
  end

  local Anim = require("src.core.game3.battle.anim")
  local st = Ui._st

  local stage = Anim.stage and Anim.stage()
  -- pret-ish z: trainers → mons → particles → ball → healthboxes → party bars
  draw_trainer_sprites(stage)
  if st then
    draw_mon_sprite(st.enemy, ENEMY_MON, false)
  end
  Anim.drawParticles()
  if st then
    draw_mon_sprite(st.player, PLAYER_MON, true)
  end
  draw_intro_ball(stage)
  if st then
    Healthbox.draw("enemy", st.enemy)
    Healthbox.draw("player", st.player)
  end
  draw_party_bars(stage)

  local panelMode = "none"
  if Ui._mode == "menu" then
    panelMode = "menu"
  elseif Ui._mode == "moves" then
    panelMode = "moves"
  end
  BattleChrome.drawPanel(panelMode)

  if Ui._mode == "menu" then
    draw_action_menu(st)
  elseif Ui._mode == "moves" then
    draw_move_menu(st)
  end

  local BagMenu = package.loaded["src.ui.game3.bag_menu"]
  if not BagMenu then
    local ok, M = pcall(require, "src.ui.game3.bag_menu")
    if ok then BagMenu = M end
  end
  if BagMenu and BagMenu.isOpen and BagMenu.isOpen() and BagMenu.draw then
    BagMenu.draw()
  end

  if Choice and Choice.active and Choice.draw then
    Choice.draw()
  end

  local PartyMenu = package.loaded["src.ui.game3.party_menu"]
  if not PartyMenu then
    local ok, M = pcall(require, "src.ui.game3.party_menu")
    if ok then PartyMenu = M end
  end
  if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() and PartyMenu.draw then
    PartyMenu.draw()
  end

  local Pokedex = package.loaded["src.ui.game3.pokedex"]
  if Pokedex and Pokedex.isOpen and Pokedex.isOpen() and Pokedex.draw then
    Pokedex.draw()
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function Ui.log()
  return Ui._log
end

return Ui
