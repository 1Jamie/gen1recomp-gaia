-- Game3 owned battle engine entry.
-- Anim VM + hit sequencer pace presentation; effects/residuals owned.

local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local Engine = require("src.core.game3.battle.engine")
local Ui = require("src.core.game3.battle.ui")
local Damage = require("src.core.game3.battle.damage")
local Commands = require("src.core.game3.battle.commands")
local Moves = require("src.core.game3.battle.moves")
local Anim = require("src.core.game3.battle.anim")
local AnimSeq = require("src.core.game3.battle.anim_seq")
local ExpSeq = require("src.core.game3.battle.exp_seq")
local EvoSeq = require("src.core.game3.battle.evo_seq")
local IntroSeq = require("src.core.game3.battle.intro_seq")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Experience = require("src.core.game3.battle.experience")
local Evolution = require("src.core.game3.evolution")
local LearnMove = require("src.core.game3.battle.learn_move")
local Task = require("src.core.game3.task")
local Trainers = require("src.core.game3.scripting.trainers")
local SwitchSeq = require("src.core.game3.battle.switch_seq")

local Battle = {}

Battle._active = false
Battle._st = nil
Battle._adapter = nil
Battle._phase = nil
Battle._actions = nil
Battle._actionI = 1
Battle._onDone = nil
Battle._pendingEnd = nil
Battle._auto = false
Battle._metaAct = nil
Battle._headless = false
Battle._lowHpSong = false

-- pret GetHPBarLevel: red when scaled bar pixels are in (0, 20%] of 48.
local HP_BAR_PIXELS = 48

local function hp_bar_red(hp, maxHp)
  hp = tonumber(hp) or 0
  maxHp = tonumber(maxHp) or 0
  if maxHp <= 0 or hp <= 0 then return false end
  if hp >= maxHp then return false end
  local fraction = math.floor(hp * HP_BAR_PIXELS / maxHp)
  if fraction == 0 and hp > 0 then fraction = 1 end
  return fraction > 0 and fraction <= math.floor(HP_BAR_PIXELS * 20 / 100)
end

local function stop_low_hp_song()
  if not Battle._lowHpSong then return end
  Battle._lowHpSong = false
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    Audio.stopSe(SE.SE_LOW_HEALTH)
  end)
end

--- pret HandleLowHpMusicChange / HandleBattleLowHpMusicChange
local function update_low_hp_music()
  local st = Battle._st
  local mon = st and st.player and st.player.mon
  if not mon then
    stop_low_hp_song()
    return
  end
  local hp = tonumber(mon.hp) or 0
  local maxHp = tonumber(mon.maxHp) or 0
  local p = Anim.present("player")
  if p and p.displayHp ~= nil then
    hp = tonumber(p.displayHp) or hp
  end
  local red = hp_bar_red(hp, maxHp)
  if red and not Battle._lowHpSong then
    Battle._lowHpSong = true
    pcall(function()
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      Audio.playSe(SE.SE_LOW_HEALTH, { loop = true })
    end)
  elseif not red then
    stop_low_hp_song()
  end
end

local function push_msgs(list)
  for _, t in ipairs(list or {}) do
    Ui.push(t)
  end
end

local function foe_mon_from(foe)
  if type(foe) ~= "table" then
    return Damage.ensureStats({
      species = 16, level = 3,
      moves = { 33, 45 }, pp = { 35, 40 },
    }, 3)
  end
  local Pokemon = require("src.core.game3.pokemon")
  local Rng = require("src.core.game3.rng")
  local species = foe.species or foe.id or 16
  local personality = foe.personality
  if personality == nil then
    -- pret GenerateWildMon → CreateMonWithNature uses Random stream;
    -- Random32 matches Unown path; nature comes from personality % 25.
    personality = Rng.Random32()
  end
  local gender = foe.gender
  if gender ~= "M" and gender ~= "F" and gender ~= "U" then
    gender = Pokemon.gender and Pokemon.gender(species, personality) or "U"
  end
  local mon = {
    species = species,
    level = foe.level or 5,
    hp = foe.hp,
    maxHp = foe.maxHp,
    moves = foe.moves or { 33 },
    pp = foe.pp or { 35, 40, 0, 0 },
    status = foe.status,
    attack = foe.attack or foe.atk,
    defense = foe.defense or foe.def,
    spAtk = foe.spAtk or foe.spa,
    spDef = foe.spDef or foe.spd,
    speed = foe.speed or foe.spe,
    item = foe.item,
    gender = gender,
    ivs = foe.ivs,
    evs = foe.evs,
    personality = personality,
    nature = foe.nature or (Pokemon.natureId and Pokemon.natureId(personality)) or 0,
    ability = foe.ability or foe.abilityId,
    dvs = foe.dvs,
  }
  local needMoves = not mon.moves or #mon.moves == 0
  if needMoves then
    if Pokemon.movesAtLevel then
      local moves, pp, maxPp = Pokemon.movesAtLevel(mon.species, mon.level)
      if moves and #moves > 0 then
        mon.moves = moves
        mon.pp = pp
        mon.maxPp = maxPp
      end
    end
  end
  return Damage.ensureStats(mon, mon.level)
end

function Battle.isActive()
  return Battle._active == true
end

function Battle.getResult()
  return Battle._st and Battle._st.result
end

function Battle.getState()
  return Battle._st
end

local function finish(result)
  if not Battle._active then return end
  stop_low_hp_song()
  Battle._active = false
  Battle._phase = nil
  local st = Battle._st
  if st then
    st.over = true
    st.result = result or st.result or "win"
  end
  AnimSeq.reset()
  CatchSeq.reset()
  ExpSeq.reset()
  EvoSeq.reset()
  IntroSeq.reset()
  LearnMove.reset()
  SwitchSeq.reset()
  Anim.reset({ headless = true })
  local okM, Message = pcall(require, "src.ui.game3.message")
  if okM and Message then
    if Message.setFrame then Message.setFrame("dialogue") end
    if Message.open and Message.close then Message.close() end
  end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.unlock then Field.unlock() end
  -- Victory BGM starts in begin_win_award (while awards play). Map BGM is
  -- restored by battle_bridge on exit — do not clobber victory here.
  local cb = Battle._onDone
  Battle._onDone = nil
  if cb then cb(st and st.result or result or "win", st) end
end

function Battle.start(opts)
  opts = opts or {}
  if Battle._active then
    return nil, "battle already active"
  end
  local playerParty = opts.playerParty or {}
  if #playerParty == 0 then
    return nil, "empty party"
  end
  local foeMon = foe_mon_from(opts.foe)
  local foeParty = opts.foeParty
  if not foeParty and opts.foe and opts.foe.party then
    foeParty = {}
    for _, fm in ipairs(opts.foe.party) do
      foeParty[#foeParty + 1] = foe_mon_from(fm)
    end
  end
  Moves.loadRomPack(opts.cache)
  local st = State.new({
    wild = opts.wild,
    playerParty = playerParty,
    foeMon = foeMon,
    foeParty = foeParty,
    rng = opts.rng,
  })
  Battle._headless = opts.headless and true or false
  Battle._auto = (opts.autoFight == true) or (opts.headless and opts.autoFight ~= false)
  Ui.reset({ headless = opts.headless })
  do
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = opts.session
      or (Runtime and Runtime.getSession and Runtime.getSession())
    Ui.bindState(st, session)
    st.playerName = session and session.name or "PLAYER"
    if session and session.dex and foeMon and (foeMon.species or foeMon.speciesId) then
      local Dex = require("src.core.game3.dex")
      Dex.setSeen(session.dex, foeMon.species or foeMon.speciesId)
    end
  end
  Anim.reset({ headless = opts.headless })
  AnimSeq.reset()
  CatchSeq.reset()
  ExpSeq.reset()
  IntroSeq.reset()
  SwitchSeq.reset()
  -- Align party exp to ROM growth curves before battle display
  for _, mon in ipairs(playerParty) do
    Experience.syncExpToLevel(mon)
  end
  if foeMon then Experience.syncExpToLevel(foeMon) end
  if foeParty then
    for _, fm in ipairs(foeParty) do
      Experience.syncExpToLevel(fm)
    end
  end
  Anim.syncDisplayFromState(st)
  Battle._st = st
  Battle._adapter = Adapter.new(st, function(text) Ui.push(text) end)
  Battle._onDone = opts.onDone
  Battle._active = true
  Battle._lowHpSong = false
  Battle._phase = "intro"
  Battle._actions = nil
  Battle._actionI = 1
  Battle._pendingEnd = nil
  Battle._metaAct = nil

  local BattleBg = require("src.core.game3.battle.bg")
  local terrain = opts.terrain
  if terrain == nil and opts.mapKind then
    terrain = BattleBg.resolveFromMapKind(opts.mapKind)
  end
  if terrain == nil then
    terrain = BattleBg.TERRAIN.BUILDING
  end
  BattleBg.setTerrain(terrain)
  st.terrain = terrain

  -- Trainer presentation identity
  local trainerId = opts.trainerId
    or (opts.foe and opts.foe.trainerId)
    or (foeMon and foeMon.trainerId)
  local rivalName = opts.rivalName
  local playerGender = opts.playerGender or 0
  local trainerInfo = nil
  if trainerId and not st.wild then
    trainerInfo = Trainers.info(trainerId, { rivalName = rivalName })
  end
  st.trainerId = trainerId
  st.trainerClassName = trainerInfo and trainerInfo.className
  st.trainerName = trainerInfo and trainerInfo.name
  st.trainerPicId = (opts.trainerPicId)
    or (trainerInfo and trainerInfo.pic)
  st.trainerPartySize = trainerInfo and trainerInfo.partySize
  -- pret gTrainers[].aiFlags / items[4] — drive battle AI scripts + item use.
  st.aiFlags = opts.aiFlags
    or (trainerInfo and trainerInfo.aiFlags)
    or (st.wild and 0 or 1) -- wild: no scripts; fallback trainer: CHECK_BAD_MOVE
  st.trainerItems = opts.trainerItems
    or (trainerInfo and trainerInfo.items)
    or { 0, 0, 0, 0 }
  st.playerGender = playerGender

  -- Battle BGM
  do
    local Audio = require("src.core.game3.audio")
    local role = st.wild and "battleWild" or "battleTrainer"
    local song = Audio.role(role) or (st.wild and 298 or 297)
    Audio.playSong(song)
  end

  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.lock then Field.lock() end

  local introOpts = {
    pushMsg = function(text) Ui.push(text) end,
    headless = opts.headless,
    trainerId = trainerId,
    trainerPicId = st.trainerPicId,
    playerGender = playerGender,
    rivalName = rivalName,
  }
  if not IntroSeq.begin(st, introOpts) then
    -- Headless / skip: push FRLG strings for log parity.
    local ename = State.displayName(st.enemy)
    if st.wild then
      Ui.push("Wild " .. ename .. " appeared!")
    else
      local strings = Trainers.introStrings(trainerId, ename, { rivalName = rivalName })
      Ui.push(strings.wants)
      Ui.push(strings.sentOut)
    end
    Ui.push("Go! " .. State.displayName(st.player) .. "!")
  end

  if opts.headless and opts.autoFight ~= false then
    Battle._auto = true
    Battle.runToEnd()
  end
  return true
end

local function begin_turn_with(playerAct)
  local st = Battle._st
  local ad = Battle._adapter
  st.turn = st.turn + 1
  local enemyAct = Commands.enemyAction(st)
  local actions, meta = Engine.planTurnFromActions(st, ad, playerAct, enemyAct)
  Battle._actions = actions
  Battle._actionI = 1
  Battle._metaAct = meta
  Battle._phase = "actions"
end

local function choice_hooks()
  return {
    pushMsg = function(text) Ui.push(text) end,
    askYesNo = function(cb) Ui.askYesNo(cb) end,
    askForget = function(labels, cb) Ui.askForget(labels, cb) end,
    headless = Battle._headless,
  }
end

local function begin_evo_or_end()
  local st = Battle._st
  Battle._pendingEnd = Battle._pendingEnd or "win"
  if Battle._pendingEnd ~= "win" or not st then
    Battle._phase = "ending"
    return
  end
  local leveled = Battle._leveledUp or ExpSeq.leveledSet()
  local pending = Evolution.pending(st.playerParty, leveled)
  if Battle._headless then
    local Pokemon = require("src.core.game3.pokemon")
    for _, entry in ipairs(pending) do
      local fromName = Pokemon.displayMonName(entry.mon)
      local intoName = Pokemon.name(entry.toSpecies) or "?"
      Ui.push("What?\n" .. fromName .. " is evolving!")
      Evolution.apply(entry.mon, entry.toSpecies)
      Ui.push("Congratulations! Your " .. fromName
        .. "\nevolved into " .. intoName .. "!")
    end
    Battle._phase = "ending"
    return
  end
  local hooks = choice_hooks()
  local started = EvoSeq.begin(pending, hooks)
  if started then
    Battle._phase = "evolving"
  else
    Battle._phase = "ending"
  end
end

local function send_out_enemy_next(nextEnemyIdx)
  local st = Battle._st
  if not st then return end
  local pushFn = function(text) Ui.push(text) end
  local onDone = function()
    Battle._phase = "command"
    if Battle._auto then
      begin_turn_with(Commands.playerAction(st, 1, 1))
    else
      Ui.openMenu()
    end
  end
  if Battle._headless or Battle._auto then
    SwitchSeq.beginSendOut(st, "enemy", nextEnemyIdx, {
      headless = true,
      pushMsg = pushFn,
      onDone = onDone,
    })
  else
    SwitchSeq.beginSendOut(st, "enemy", nextEnemyIdx, {
      headless = false,
      pushMsg = pushFn,
      onDone = onDone,
    })
    Battle._phase = "switching"
  end
end

local function handle_player_faint()
  local st = Battle._st
  if not st then return end
  if st.player and st.playerParty then
    State.syncBattlerToParty(st.player, st.playerParty)
  end
  local hasLiving = Engine.hasLivingMons(st.playerParty)
  if not hasLiving then
    Battle._pendingEnd = "lose"
    Battle._phase = "ending"
    Ui.push("You have no more\nPOKéMON left!")
    Ui.push(string.format("%s blacked out!", (st.playerName or "PLAYER")))
    return
  end

  if Battle._headless or Battle._auto then
    local nextI = Engine.nextLivingMonIndex(st.playerParty, st.player and st.player.partyIndex) or 1
    SwitchSeq.beginSendOut(st, "player", nextI, {
      headless = true,
      pushMsg = function(t) Ui.push(t) end,
      onDone = function()
        Battle._phase = "command"
        if Battle._auto then
          begin_turn_with(Commands.playerAction(st, 1, 1))
        else
          Ui.openMenu()
        end
      end,
    })
    return
  end

  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  State.syncBattlerToParty(st.player, st.playerParty)
  Battle._phase = "switching"
  PartyMenu.show(st.playerParty or (session and session.party), session and session.move_overlay, {
    mode = "battle_faint",
    session = session,
    activeSlot = st.player.partyIndex,
    battle = true,
    onSelect = function(slot)
      SwitchSeq.beginSendOut(st, "player", slot, {
        headless = false,
        pushMsg = function(t) Ui.push(t) end,
        onDone = function()
          Battle._phase = "command"
          Ui.openMenu()
        end,
      })
      Battle._phase = "switching"
    end,
  })
end

local function handle_enemy_faint()
  local st = Battle._st
  if not st then return end
  stop_low_hp_song()
  if st.enemy and st.foeParty then
    State.syncBattlerToParty(st.enemy, st.foeParty)
  end
  local awards = {}
  if st and st.enemy then
    local partIndices = {}
    if st.enemy.participants then
      for pi, _ in pairs(st.enemy.participants) do
        partIndices[#partIndices + 1] = pi
      end
      table.sort(partIndices)
    end
    awards = Experience.awardFoe(st, st.enemy, {
      trainer = not st.wild,
      partyIndices = (#partIndices > 0) and partIndices or nil,
    })
  end
  Battle._leveledUp = {}
  local thenMsgs = {}
  local nextEnemyIdx = (not st.wild) and Engine.nextLivingMonIndex(st.foeParty, st.enemy and st.enemy.partyIndex)

  if not nextEnemyIdx then
    Battle._pendingEnd = "win"
    thenMsgs = { "You won the battle!" }
    do
      local Audio = require("src.core.game3.audio")
      local role = (st and st.wild) and "victoryWild" or "victoryTrainer"
      local song = Audio.role(role) or ((st and st.wild) and 311 or 310)
      Audio.playSong(song)
    end
  end

  local onAwardsFinished = function()
    if not nextEnemyIdx then
      if st and not st.wild and st.trainerId then
        local Prize = require("src.core.game3.battle.prize")
        local Runtime = package.loaded["src.core.game3.runtime"]
        local session = Runtime and Runtime.getSession and Runtime.getSession()
        if session then
          local Trainers = require("src.core.game3.scripting.trainers")
          local info = Trainers.info(st.trainerId)
          local lastLevel = info and tonumber(info.lastLevel)
          if not lastLevel or lastLevel < 1 then
            lastLevel = st.enemy and st.enemy.mon and tonumber(st.enemy.mon.level) or 1
          end
          local gained = Prize.awardTrainerWin(session, st.trainerId, {
            lastLevel = lastLevel,
            double = st.double or false,
            moneyMultiplier = st.moneyMultiplier or 1,
          })
          if gained > 0 then
            local pname = session.name or "PLAYER"
            Ui.push(Prize.moneyMessage(pname, gained))
          end
        end
      end
      begin_evo_or_end()
    else
      if Battle._headless or Battle._auto then
        send_out_enemy_next(nextEnemyIdx)
      else
        local nextMon = st.foeParty[nextEnemyIdx]
        local nextSp = nextMon and (nextMon.species or nextMon.speciesId)
        local Pokemon = require("src.core.game3.pokemon")
        local nextName = Pokemon.name(nextSp)
        local trName = (st.trainerClassName and st.trainerClassName ~= "")
          and (st.trainerClassName .. " " .. (st.trainerName or ""))
          or (st.trainerName or "TRAINER")
        Ui.push(string.format("%s is\nabout to send in\n%s.", trName, nextName))
        Ui.push(string.format("Will %s change\nPOKéMON?", (st.playerName or "PLAYER")))
        Ui.askYesNo(function(yes)
          if yes then
            local PartyMenu = require("src.ui.game3.party_menu")
            local Runtime = package.loaded["src.core.game3.runtime"]
            local session = Runtime and Runtime.getSession and Runtime.getSession()
            State.syncBattlerToParty(st.player, st.playerParty)
            PartyMenu.show(st.playerParty or (session and session.party), session and session.move_overlay, {
              mode = "battle_switch",
              session = session,
              activeSlot = st.player.partyIndex,
              battle = true,
              onSelect = function(pSlot)
                SwitchSeq.beginSendOut(st, "player", pSlot, {
                  headless = false,
                  pushMsg = function(t) Ui.push(t) end,
                  onDone = function()
                    send_out_enemy_next(nextEnemyIdx)
                  end,
                })
                Battle._phase = "switching"
              end,
              onClose = function()
                send_out_enemy_next(nextEnemyIdx)
              end,
            })
          else
            send_out_enemy_next(nextEnemyIdx)
          end
        end)
      end
    end
  end

  local hooks = choice_hooks()
  if Battle._headless then
    local Pokemon = require("src.core.game3.pokemon")
    for _, entry in ipairs(awards) do
      local r = entry.result or {}
      if (r.gained or 0) > 0 then
        local name = entry.battler and State.displayName(entry.battler)
          or Pokemon.displayMonName(entry.mon)
        Ui.push(name .. " gained\n" .. tostring(r.gained) .. " EXP. Points!")
        for _, lv in ipairs(r.levels or {}) do
          Ui.push(name .. " grew to\nLV. " .. tostring(lv) .. "!")
          Battle._leveledUp[entry.partyIndex or 1] = true
        end
        for _, lv in ipairs(r.levels or {}) do
          for _, mv in ipairs(Pokemon.movesLearnedAt(
            tonumber(entry.mon and entry.mon.species), lv)) do
            if Pokemon.teachMove(entry.mon, mv) then
              Ui.push(name .. " learned\n" .. Pokemon.moveName(mv) .. "!")
            end
          end
        end
      end
    end
    push_msgs(thenMsgs)
    onAwardsFinished()
    return
  end

  local started = ExpSeq.begin(awards, hooks.pushMsg, thenMsgs, hooks)
  if started then
    Battle._leveledUp = ExpSeq.leveledSet() or {}
    Battle._onExpDone = onAwardsFinished
    Battle._phase = "awarding"
  else
    push_msgs(thenMsgs)
    onAwardsFinished()
  end
end

local function begin_win_award()
  handle_enemy_faint()
end

local function after_actions()
  local st = Battle._st
  local ad = Battle._adapter
  local msgs = Engine.runResiduals(ad)
  for _, side in ipairs({ "player", "enemy" }) do
    local b = st[side]
    local p = Anim.present(side)
    if b and b.mon and p and p.displayHp ~= nil then
      local logical = tonumber(b.mon.hp) or 0
      if math.abs(logical - (p.displayHp or logical)) >= 1 then
        Anim.tweenHp(side, p.displayHp, logical, b.mon.maxHp)
      else
        p.displayHp = logical
      end
    end
  end
  push_msgs(msgs)
  if State.isFainted(st.enemy) then
    handle_enemy_faint()
    return
  elseif State.isFainted(st.player) then
    handle_player_faint()
    return
  end
  local endResult = Engine.checkEnd(st, ad)
  if endResult == "win" then
    handle_enemy_faint()
  elseif endResult == "lose" then
    handle_player_faint()
  else
    Battle._phase = "command"
    if not Battle._auto then
      Ui.openMenu()
    end
  end
end

local function step_action()
  local st = Battle._st
  local ad = Battle._adapter

  if Battle._metaAct then
    local meta = Battle._metaAct
    Battle._metaAct = nil
    if meta.kind == "run" then
      if Commands.tryFlee(st, ad) then
        st.over = true
        st.result = "run"
        Battle._pendingEnd = "run"
        Battle._phase = "ending"
        pcall(function()
          local Audio = require("src.core.game3.audio")
          local SE = require("src.core.game3.se_ids")
          Audio.playSe(SE.SE_FLEE)
        end)
        return
      end
    elseif meta.kind == "bag" then
      local Catching = require("src.core.game3.battle.catching")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      local bag = session and session.bag

      if Catching.isBall(meta.itemId) then
        if not st.wild then
          Ui.push("The TRAINER blocked\nthe BALL!")
          Battle._actions = {}
          Battle._phase = "command"
          Ui.openMenu()
          return
        end
        local Bag = require("src.core.game3.bag")
        if not bag or not Bag.has(bag, meta.itemId, 1) then
          Ui.push("You don't have that item.")
          Battle._actions = {}
          Battle._phase = "command"
          Ui.openMenu()
          return
        end
        Bag.remove(bag, meta.itemId, 1)
        local rng = ad and ad.rng and ad:rng() or st.rng
        local caught, shakes = Catching.tryCatch(meta.itemId, st.enemy, st, session, rng)
        local pushFn = function(text) Ui.push(text) end
        if Battle._headless or (Ui and Ui._headless) then
          CatchSeq.begin(st, meta.itemId, caught, shakes, {
            pushMsg = pushFn,
            headless = true,
            session = session,
          })
          if caught then
            Battle._actions = {}
            st.over = true
            st.result = "catch"
            Battle._pendingEnd = "catch"
            Battle._phase = "ending"
            return
          end
        else
          CatchSeq.begin(st, meta.itemId, caught, shakes, {
            pushMsg = pushFn,
            headless = false,
            session = session,
          })
          Battle._phase = "catching"
          return
        end
      else
        local BattleItems = require("src.core.game3.battle.items")
        local result, _msgs, endsTurn, endsBattle = BattleItems.use(
          st, ad, bag, session, meta.itemId, meta.partySlot)
        if endsBattle then
          Battle._actions = {}
          if result == "catch" then
            st.over = true
            st.result = "catch"
            Battle._pendingEnd = "catch"
          else
            st.over = true
            st.result = "run"
            Battle._pendingEnd = "run"
          end
          Battle._phase = "ending"
          return
        end
        if not endsTurn or result == "error" then
          Battle._actions = {}
          Battle._phase = "command"
          Ui.openMenu()
          return
        end
        if result == "heal" and st.player and st.player.partyIndex == meta.partySlot then
          local p = Anim.present("player")
          local logical = tonumber(st.player.mon and st.player.mon.hp) or 0
          if p and p.displayHp ~= nil and math.abs(logical - p.displayHp) >= 1 then
            Anim.tweenHp("player", p.displayHp, logical, st.player.mon.maxHp)
          end
        end
      end
    elseif meta.kind == "switch" then
      -- Pursuit interrupt check
      local enemyAct = nil
      local enemyActIdx = nil
      for idx, a in ipairs(Battle._actions or {}) do
        if a.user == "enemy" and a.kind == "move" then
          enemyAct = a
          enemyActIdx = idx
          break
        end
      end
      if enemyAct and Engine.isPursuit(enemyAct.move) and not State.isFainted(st.enemy) then
        table.remove(Battle._actions, enemyActIdx)
        local out = {}
        Engine.resolveMove(enemyAct.user, st.player, enemyAct.move, enemyAct.slot, ad, st, out, { pursuitSwitch = true })
        local animMeta = out._anim
        if Battle._headless or not animMeta then
          push_msgs(out)
          if State.isFainted(st.player) then
            Battle._actions = {}
            handle_player_faint()
            return
          end
        else
          AnimSeq.begin(animMeta, function(text) Ui.push(text) end)
          Battle._phase = "animating"
          return
        end
      end

      local newSlot = meta.slot or 1
      local pushFn = function(text) Ui.push(text) end
      local onDone = function()
        Battle._phase = "actions"
        if not Battle._actions or not Battle._actions[Battle._actionI] then
          after_actions()
        end
      end
      if Battle._headless then
        SwitchSeq.beginPlayerSwitch(st, newSlot, {
          headless = true,
          pushMsg = pushFn,
          onDone = onDone,
        })
        -- Fall through to enemy action list
      else
        SwitchSeq.beginPlayerSwitch(st, newSlot, {
          headless = false,
          pushMsg = pushFn,
          onDone = onDone,
        })
        Battle._phase = "switching"
        return
      end
    end
  end

  local act = Battle._actions and Battle._actions[Battle._actionI]
  if not act then
    after_actions()
    return
  end
  Battle._actionI = Battle._actionI + 1

  if act.meta then
    if not Battle._actions[Battle._actionI] then after_actions() end
    return
  end

  local uBattler = (type(act.user) == "string" and st and st[act.user]) or act.user
  local tBattler = (type(act.target) == "string" and st and st[act.target]) or act.target
  if uBattler and uBattler.side and st and st[uBattler.side] then uBattler = st[uBattler.side] end
  if tBattler and tBattler.side and st and st[tBattler.side] then tBattler = st[tBattler.side] end

  if State.isFainted(uBattler) or State.isFainted(tBattler) then
    if not Battle._actions[Battle._actionI] then after_actions() end
    return
  end

  local out = {}
  Engine.resolveMove(act.user, act.target, act.move, act.slot, ad, st, out)
  local animMeta = out._anim
  if Battle._headless or not animMeta then
    push_msgs(out)
  else
    AnimSeq.begin(animMeta, function(text) Ui.push(text) end)
    Battle._phase = "animating"
    return
  end

  if State.isFainted(st.enemy) then
    handle_enemy_faint()
    return
  elseif State.isFainted(st.player) then
    handle_player_faint()
    return
  end

  local ended = Engine.checkEnd(st, ad)
  if ended == "win" then
    handle_enemy_faint()
    return
  elseif ended == "lose" then
    handle_player_faint()
    return
  end
  if not Battle._actions[Battle._actionI] then
    after_actions()
  end
end

local function after_anim_sequence()
  local st = Battle._st
  local ad = Battle._adapter
  if State.isFainted(st.enemy) then
    handle_enemy_faint()
    return
  elseif State.isFainted(st.player) then
    handle_player_faint()
    return
  end
  local ended = Engine.checkEnd(st, ad)
  if ended == "win" then
    handle_enemy_faint()
    return
  elseif ended == "lose" then
    handle_player_faint()
    return
  end
  Battle._phase = "actions"
  if not Battle._actions[Battle._actionI] then
    after_actions()
  end
end

function Battle.update(dt, game)
  if not Battle._active then return end

  local input = game and game.input
  local Pokedex = package.loaded["src.ui.game3.pokedex"]
  if Pokedex and Pokedex.isOpen and Pokedex.isOpen() then
    if input then Pokedex.handleInput(input) end
    return
  end

  if not Battle._headless then
    Task.update(dt or 0)
    Anim.update(dt or 0)
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.tickCry then Audio.tickCry(dt or 1 / 60) end
    update_low_hp_music()
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() and PartyMenu.update then
      PartyMenu.update(dt or (1 / 60))
    end
  end

  if Battle._phase == "command" and not Battle._auto then
    local BagMenu = require("src.ui.game3.bag_menu")
    if BagMenu.isOpen and BagMenu.isOpen() then
      if input then BagMenu.handleInput(input) end
      return
    end
    local PartyMenu = require("src.ui.game3.party_menu")
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      if input then PartyMenu.handleInput(input) end
      return
    end
    if input then Ui.handleInput(input) end
    local cmd = Ui.takeCommand()
    if cmd then
      begin_turn_with(cmd)
    end
    return
  end

  -- Choice input during award / shift prompt / evolution learn-move prompts
  if (Battle._phase == "awarding" or Battle._phase == "evolving" or Battle._phase == "switching")
      and not Battle._auto and game and game.input then
    if Ui.choiceActive and Ui.choiceActive() then
      Ui.handleInput(game.input)
    end
  end

  -- Intro: pump dialogs even while slide tweens run
  if Battle._phase == "intro" then
    if not Ui.pump() then return end
    if IntroSeq.update() then
      Battle._phase = "command"
      if Battle._auto then
        begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
      else
        Ui.openMenu()
      end
    end
    return
  end

  -- Switch / send-out presentation
  if Battle._phase == "switching" then
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() then
      if input then PartyMenu.handleInput(input) end
      return
    end
    if Anim.busy() then return end
    if Ui.choiceActive and Ui.choiceActive() then
      return
    end
    if not Ui.pump() then return end
    SwitchSeq.update()
    return
  end

  -- Anim sequence owns presentation pacing
  if Battle._phase == "animating" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    local done = AnimSeq.update()
    if done then
      after_anim_sequence()
    end
    return
  end

  -- Poké Ball catch presentation
  if Battle._phase == "catching" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    local done = CatchSeq.update()
    if done then
      local res = CatchSeq.result()
      if res == "catch" then
        local catchRes = CatchSeq.catchResult and CatchSeq.catchResult()
        local enemy = Battle._st and Battle._st.enemy
        local sp = enemy and enemy.mon and (enemy.mon.species or enemy.mon.speciesId)
        if catchRes and catchRes.firstTimeCaught and sp and not Battle._headless then
          local okP, Pokedex = pcall(require, "src.ui.game3.pokedex")
          if okP and Pokedex and Pokedex.showRegistration then
            Battle._phase = "pokedex_reg"
            local Runtime = package.loaded["src.core.game3.runtime"]
            local session = Runtime and Runtime.getSession and Runtime.getSession()
            Pokedex.showRegistration(sp, {
              session = session,
              onDone = function()
                Battle._actions = {}
                Battle._pendingEnd = "catch"
                Battle._phase = "ending"
              end,
            })
            return
          end
        end
        Battle._actions = {}
        Battle._pendingEnd = "catch"
        Battle._phase = "ending"
      else
        Battle._phase = "actions"
        if not Battle._actions or not Battle._actions[Battle._actionI] then
          after_actions()
        end
      end
    end
    return
  end

  if Battle._phase == "pokedex_reg" then
    return
  end

  -- EXP award / level-up / learn-move
  if Battle._phase == "awarding" then
    if Anim.busy() then return end
    if Ui.choiceActive and Ui.choiceActive() then return end
    if not Ui.pump() then return end
    local done = ExpSeq.update()
    if done then
      Battle._leveledUp = ExpSeq.leveledSet() or Battle._leveledUp
      local cb = Battle._onExpDone
      Battle._onExpDone = nil
      if cb then
        cb()
      else
        begin_evo_or_end()
      end
    end
    return
  end

  -- Post-battle evolution (EVO_LEVEL)
  if Battle._phase == "evolving" then
    if Ui.choiceActive and Ui.choiceActive() then return end
    if not Ui.pump() then return end
    local done = EvoSeq.update()
    if done then
      Battle._phase = "ending"
    end
    return
  end

  if Anim.busy() then return end
  if not Ui.pump() then return end

  if Battle._phase == "actions" then
    step_action()
    if Battle._headless and Battle._phase == "ending" then
      finish(Battle._pendingEnd or "win")
    end
    return
  end

  if Battle._phase == "ending" then
    finish(Battle._pendingEnd or "win")
    return
  end

  if Battle._phase == "command" and Battle._auto then
    begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
  end
end

function Battle.runToEnd()
  if not Battle._active then return Battle.getResult() end
  Battle._auto = true
  Battle._headless = true
  local savedLog = Ui.log and Ui.log() or {}
  Ui.reset({ headless = true })
  Ui.bindState(Battle._st)
  if savedLog and #savedLog > 0 then
    for _, t in ipairs(savedLog) do
      Ui._log[#Ui._log + 1] = t
    end
  end
  Anim.reset({ headless = true })
  AnimSeq.reset()
  CatchSeq.reset()
  ExpSeq.reset()
  EvoSeq.reset()
  IntroSeq.reset()
  LearnMove.reset()
  local guard = 0
  while Battle._active and guard < 800 do
    guard = guard + 1
    Battle.update(0, nil)
  end
  return Battle.getResult()
end

function Battle.draw(_game, w, h)
  if not Battle._active then return end
  Ui.draw(w, h)
end

function Battle.abort(result)
  if Battle._active then finish(result or "run") end
end

return Battle
