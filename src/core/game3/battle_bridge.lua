-- Battle entry for Sevii: owned game3 battle + white-out / FRLG money (H3/H6/H7).
-- No host Battle / no save.party swap. H4 remaps are transitional (party_view keeps Gen3 ids).

local Party = require("src.core.game3.party")
local PartyView = require("src.core.game3.battle.party_view")
local Downgrade = require("src.core.game3.battle_downgrade")

local BattleBridge = {}

BattleBridge._remap = nil
BattleBridge._battleParty = nil
BattleBridge._interceptInstalled = false
BattleBridge._whiteoutHook = nil
BattleBridge._finish = nil

local function runtimeActive()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.isActive and Runtime.isActive()
end

local BADGE_LOSS_MULT = { 2, 4, 6, 9, 12, 16, 20, 25, 30 } -- index 0..8 badges
local BADGE_FLAGS = {
  0x820, 0x821, 0x822, 0x823, 0x824, 0x825, 0x826, 0x827, -- FLAG_BADGE01..08
}

local function count_badges(session, hostSave)
  local flags = nil
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.getStore and Space.getStore()
  if store and store.flags then
    flags = store.flags
  elseif session and session.flags then
    flags = session.flags
  end
  if flags then
    local n = 0
    for _, fid in ipairs(BADGE_FLAGS) do
      if flags[fid] or flags[tostring(fid)] then n = n + 1 end
    end
    return math.min(8, n)
  end
  local badges = 0
  if hostSave then
    local inv = hostSave.inventory or {}
    for id, qty in pairs(inv) do
      if type(id) == "string" and id:find("BADGE", 1, true) and (qty or 0) > 0 then
        badges = badges + 1
      end
    end
    if type(hostSave.badges) == "number" then
      badges = math.max(badges, hostSave.badges)
    elseif type(hostSave.badges) == "table" then
      local c = 0
      for _, v in pairs(hostSave.badges) do if v then c = c + 1 end end
      badges = math.max(badges, c)
    end
  end
  return math.max(0, math.min(8, badges))
end

function BattleBridge.calcMoneyLossFrlg(session, hostSave)
  local maxLv = 1
  local party = session and session.party
  if type(party) == "table" then
    for _, mon in ipairs(party) do
      local lv = tonumber(mon and mon.level) or 1
      if lv > maxLv then maxLv = lv end
    end
  end
  local badges = count_badges(session, hostSave)
  -- pret: toplevel * 4 * sWhiteOutMoneyLossMultipliers[nbadges]
  local mult = BADGE_LOSS_MULT[badges + 1] or 2
  return maxLv * 4 * mult
end

function BattleBridge.applyFrlgMoneyLoss(session, hostSave)
  local loss = BattleBridge.calcMoneyLossFrlg(session, hostSave)
  local money = tonumber(session and session.money) or tonumber(hostSave and hostSave.money) or 0
  money = math.max(0, money - loss)
  if session then session.money = money end
  if hostSave then hostSave.money = money end
  return loss, money
end

function BattleBridge.installWhiteoutIntercept(mod, game)
  if BattleBridge._interceptInstalled then return end
  BattleBridge._interceptInstalled = true

  local function onWhiteout()
    local Runtime = require("src.core.game3.runtime")
    if not Runtime.isActive() then return false end
    local session = Runtime.getSession()
    BattleBridge.applyFrlgMoneyLoss(session, game and game.save)
    local Field = require("src.core.game3.field")
    Field.respawnAtHeal()
    return true
  end
  BattleBridge._whiteoutHook = onWhiteout

  local ok, World = pcall(require, "src.world.gen2.World")
  if ok and World then
    if type(World.whiteOut) == "function" and not World._game3WhiteOut then
      local prev = World.whiteOut
      World.whiteOut = function(self, ...)
        if onWhiteout() then return end
        return prev(self, ...)
      end
      World._game3WhiteOut = true
    end
    if type(World.warpToPokemonCenter) == "function" and not World._game3WarpPC then
      local prev = World.warpToPokemonCenter
      World.warpToPokemonCenter = function(self, ...)
        if runtimeActive() and onWhiteout() then return end
        return prev(self, ...)
      end
      World._game3WarpPC = true
    end
  end
end

local function writeback(session, battleParty, remap, result, save, opts)
  opts = opts or {}
  if not session then return end
  Downgrade.writebackPlayerPp(session.party, session.move_overlay, remap, battleParty)
  for i, mon in ipairs(session.party or {}) do
    local src = battleParty and battleParty[i]
    if src then
      Party.applyBattleFields(mon, {
        hp = src.hp,
        maxHp = src.maxHp,
        status = src.status,
        sleep = src.sleep,
        level = src.level,
        exp = src.exp,
        pp = src.pp,
        maxPp = src.maxPp,
        moves = src.moves,
        species = src.species or src.speciesId,
        speciesId = src.speciesId or src.species,
        name = src.name,
        growthRate = src.growthRate,
        attack = src.attack or src.atk,
        defense = src.defense or src.def,
        speed = src.speed or src.spe,
        spAtk = src.spAtk or src.spa,
        spDef = src.spDef or src.spd,
        _allowMoveRewrite = true,
      })
    end
  end
  local lost = (result == "lose" or result == "whiteout" or result == "blackout")
  if not lost then return end

  -- pret CB2_EndTrainerBattle EARLY_RIVAL + RIVAL_BATTLE_HEAL_AFTER:
  -- heal and continue script — no white-out warp.
  local flags = tonumber(opts.rivalFlags) or 0
  local healAfter = opts.noWhiteout
    or (opts.earlyRival and (flags % 2 == 1)) -- bit0 = RIVAL_BATTLE_HEAL_AFTER
  if healAfter then
    Party.healAll(session.party)
    return
  end

  BattleBridge.applyFrlgMoneyLoss(session, save)
  local Field = require("src.core.game3.field")
  Field.respawnAtHeal()
end

--- Start owned game3 battle (async). opts.done(result) when finished.
-- opts.earlyRival / opts.rivalFlags / opts.noWhiteout: Oaks Lab tutorial loss.
function BattleBridge.start(mod, game, foe, opts)
  opts = opts or {}
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not session then return nil, "no session" end

  BattleBridge.installWhiteoutIntercept(mod, game)

  local battleParty, remap = PartyView.fromSession(session.party, session.move_overlay)
  if #battleParty == 0 then return nil, "empty party" end

  BattleBridge._remap = remap
  BattleBridge._battleParty = battleParty

  local save = game and game.save
  local done = opts.done

  local function finish(result)
    writeback(session, battleParty, remap, result, save, opts)
    BattleBridge._remap = nil
    BattleBridge._battleParty = nil
    BattleBridge._finish = nil
    pcall(function()
      require("src.core.game3.audio").restoreMapSong()
    end)
    if done then done(result or "win") end
  end
  BattleBridge._finish = finish

  local Battle = require("src.core.game3.battle")
  local Map = package.loaded["src.core.game3.map"] or require("src.core.game3.map")
  local mapId = Map.current
  local mapDef = game and game.data and game.data.maps and mapId and game.data.maps[mapId]
  local mapKind = (mapDef and mapDef.kind) or opts.mapKind

  local gender = 0
  if session.gender == "female" or session.gender == "F" or session.gender == 1 then
    gender = 1
  elseif save and (save.gender == 1 or save.gender == "female" or save.gender == "F") then
    gender = 1
  end

  local startOpts = {
    wild = opts.wild,
    playerParty = battleParty,
    foe = foe,
    headless = opts.headless,
    rng = opts.rng,
    mapKind = mapKind,
    terrain = opts.terrain,
    trainerId = opts.trainerId or (foe and foe.trainerId),
    defeatText = opts.defeatText or (foe and foe.defeatText),
    victoryText = opts.victoryText or (foe and foe.victoryText),
    rivalName = opts.rivalName or session.rivalName or (save and save.rivalName),
    playerGender = opts.playerGender or gender,
    onDone = function(result)
      finish(result)
    end,
  }

  local function doStart()
    local ok, err = Battle.start(startOpts)
    if not ok then
      BattleBridge._finish = nil
      BattleBridge._remap = nil
      BattleBridge._battleParty = nil
      if done then done("win") end
      return nil, err
    end
    return true
  end

  if opts.headless or opts.fade == false then
    return doStart()
  end

  local okT, BattleTransition = pcall(require, "src.core.game3.battle_transition")
  if okT and BattleTransition and BattleTransition.start then
    local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
    if Field and Field.lock then Field.lock() end

    local leadMon = battleParty and battleParty[1]
    local playerLv = leadMon and (leadMon.level or leadMon.lvl) or 5
    local foeLv = (foe and foe.level) or (foe and foe.party and foe.party[1] and (foe.party[1].level or foe.party[1].lvl)) or 3

    local pickOpts = {
      wild = opts.wild,
      mapKind = mapKind,
      terrain = opts.terrain,
      playerLevel = playerLv,
      enemyLevel = foeLv,
      trainerId = startOpts.trainerId,
      playerGender = startOpts.playerGender,
      transitionId = opts.transitionId,
    }
    local tid = BattleTransition.pick(pickOpts)
    BattleTransition.start(tid, pickOpts, function()
      doStart()
    end)
    return true
  end

  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.begin then
    local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
    if Field and Field.lock then Field.lock() end
    Fade.begin(Fade.MODE.TO_BLACK, 1, function()
      doStart()
    end)
    return true
  end
  return doStart()
end

function BattleBridge.startWild(mod, game, encounter, opts)
  opts = opts or {}
  opts.wild = true
  return BattleBridge.start(mod, game, encounter, opts)
end

--- Tests / emergency: complete pending battle writeback.
function BattleBridge.finishPending(result)
  local Battle = package.loaded["src.core.game3.battle"]
    or require("src.core.game3.battle")
  if Battle.isActive and Battle.isActive() then
    Battle.abort(result or "win")
    return
  end
  if BattleBridge._finish then
    local f = BattleBridge._finish
    BattleBridge._finish = nil
    return f(result or "win")
  end
end

return BattleBridge
