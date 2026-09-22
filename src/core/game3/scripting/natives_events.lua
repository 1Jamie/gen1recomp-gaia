local Std = require("src.core.game3.scripting.stdscripts")

local Events = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321
local VAR_FACING = 0x800C -- src/core/game3/scripting/ctx.lua Ctx.VAR_FACING

-- pokefirered/src/field_tasks.c:51
local ICEFALL_CAVE_ICE_COORDS = {
  { 8, 3 }, { 10, 5 }, { 15, 5 },
  { 8, 9 }, { 9, 9 }, { 16, 9 },
  { 8, 10 }, { 9, 10 }, { 8, 14 },
}

-- pokefirered/include/constants/metatile_labels.h:188
local METATILE_SEAFOAM_CRACKED_ICE = 0x35A

-- pokefirered/include/constants/songs.h:290
local MUS_CYCLING = 282

-- pokefirered/include/save_location.h:9
local CHAMPION_SAVEWARP = 0x80

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf(ctx)
  local rt = package.loaded["src.core.game3.runtime"]
  return (rt and rt.getSession and rt.getSession())
    or (ctx and ctx.session)
    or nil
end

local function scriptStore(ctx)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf(ctx)
  return (Space and Space.store)
    or (session and (session.store or session))
    or (ctx and (ctx.store or ctx.session or (ctx.vars and ctx)))
    or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(ctx), ctx, id)) or 0
end

-- pokefirered/src/scrcmd.c:99
local function setResult(ctx, value)
  flagsMod().setVar(scriptStore(ctx), ctx, VAR_RESULT, tonumber(value) or 0)
end

local function currentMapId(ctx)
  local session = sessionOf(ctx)
  if session and session.map then return session.map end
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.current
end

local function partyOf(ctx)
  local session = sessionOf(ctx)
  return (session and session.party) or (ctx and ctx.party) or {}, session
end

local function noop()
  return false
end

Events.ICEFALL_CAVE_ICE_COORDS = ICEFALL_CAVE_ICE_COORDS
Events.METATILE_SEAFOAM_CRACKED_ICE = METATILE_SEAFOAM_CRACKED_ICE

Events.HANDLERS = {
  -- pokefirered/src/field_camera.c:93
  [Std.SPECIAL.DrawWholeMapView] = function()
    local FieldView = package.loaded["src.core.game3.field_view"]
    if FieldView then FieldView._nativeDirty = true end
    return false
  end,
  -- pokefirered/src/pokemon.c:6215
  [Std.SPECIAL.CreateEnemyEventMon] = function(ctx)
    local okE, Enc = pcall(require, "src.core.game3.encounters")
    if not (okE and Enc and Enc.setWildBattle) then return false end
    local item = varGet(ctx, VAR_0x8006)
    Enc.setWildBattle(varGet(ctx, VAR_0x8004), varGet(ctx, VAR_0x8005),
      item ~= 0 and item or nil)
    -- pokefirered/src/pokemon.c:2026
    local pending = Enc._pendingWild
    if pending then pending.fatefulEncounter = true end
    return false
  end,
  -- pokefirered/src/safari_zone.c:27
  [Std.SPECIAL.EnterSafariMode] = function()
    pcall(function() require("src.core.game3.safari").enter() end)
    return false
  end,
  -- pokefirered/src/safari_zone.c:35
  [Std.SPECIAL.ExitSafariMode] = function()
    pcall(function() require("src.core.game3.safari").exit() end)
    return false
  end,
  -- pokefirered/src/field_tasks.c:152
  [Std.SPECIAL.SetIcefallCaveCrackedIceMetatiles] = function(ctx)
    local okF, Field = pcall(require, "src.core.game3.field")
    if not (okF and Field and Field.setMetatile) then return false end
    local Flags = flagsMod()
    local store = scriptStore(ctx)
    for i = 1, #ICEFALL_CAVE_ICE_COORDS do
      if Flags.getFlag(store, ctx, i) then
        local c = ICEFALL_CAVE_ICE_COORDS[i]
        -- MapGridSetMetatileIdAt only swaps the metatile id; cracked ice stays
        -- walkable (the collision follows the new metatile), so do not force
        -- the impassable override.
        Field.setMetatile(c[1], c[2], METATILE_SEAFOAM_CRACKED_ICE, false)
      end
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:97
  [Std.SPECIAL.ForcePlayerOntoBike] = function()
    -- SetPlayerAvatarTransitionFlags(PLAYER_AVATAR_FLAG_MACH_BIKE) only runs
    -- for an on-foot avatar; a surfing player is not forced onto the bike.
    local okP, Player = pcall(require, "src.core.game3.player")
    if okP and Player and not Player.surfing then
      Player.biking = true
      Player.surfHopping = false
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:1513
  [Std.SPECIAL.ForcePlayerToStartSurfing] = function()
    -- SetPlayerAvatarTransitionFlags(PLAYER_AVATAR_FLAG_SURFING): a forced
    -- transition, so no surf hop and the bike override is cleared.
    local okP, Player = pcall(require, "src.core.game3.player")
    if okP and Player then
      Player.surfing = true
      Player.biking = false
      Player.surfHopping = false
    end
    return false
  end,
  -- pokefirered/src/wild_encounter.c:446
  [Std.SPECIAL.RockSmashWildEncounter] = function(ctx, adapters)
    local okE, Enc = pcall(require, "src.core.game3.encounters")
    local foe
    if okE and Enc and type(Enc.rollRocks) == "function" then
      foe = Enc.rollRocks(currentMapId(ctx))
    end
    if not (foe and adapters and adapters.startWildBattle) then
      setResult(ctx, 0)
      return false
    end
    foe.wildScripted = true
    setResult(ctx, 1)
    local Natives = require("src.core.game3.scripting.natives")
    return Natives.yieldHost(ctx, adapters, function(done)
      adapters.startWildBattle(foe, function(result)
        local code = Natives.outcome_to_code(result)
        if ctx then ctx.lastBattleOutcome = code end
        done()
      end, { wildScripted = true })
    end)
  end,
  -- pokefirered/src/save_location.c:105
  [Std.SPECIAL.SetPostgameFlags] = function(ctx)
    local session = sessionOf(ctx)
    if not session then return false end
    local Bit = require("bit")
    session.gcnLinkFlags = Bit.bor(tonumber(session.gcnLinkFlags) or 0, 0x800E)
    session.specialSaveWarpFlags =
      Bit.bor(tonumber(session.specialSaveWarpFlags) or 0, CHAMPION_SAVEWARP)
    return false
  end,
  -- pokefirered/src/field_specials.c:120 ShowFieldMessageStringVar4
  [Std.SPECIAL.ShowFieldMessageStringVar4] = function(ctx, adapters)
    local text = (ctx and ctx.stringVars and ctx.stringVars[4]) or ""
    -- pret ShowFieldMessage(gStringVar4): the field box stays up until the
    -- script closes it, the same seam the msgbox opcode uses (ops_a.lua:170).
    if ctx then ctx.messageOpen = true end
    local openStay = adapters and (adapters.openMessageStay or adapters.openMessageAsync)
    if openStay then
      openStay(text, nil)
    elseif adapters and adapters.openMessage then
      adapters.openMessage(text)
    end
    return false
  end,
  -- pokefirered/src/script.c:260 SetWalkingIntoSignVars
  [Std.SPECIAL.SetWalkingIntoSignVars] = function(ctx)
    if ctx then
      ctx.walkAwayFromSignInhibitTimer = 6
      ctx.msgBoxIsCancelable = true
      ctx.canWalkAway = true
    end
    local session = sessionOf(ctx)
    if session then
      session.walkAwayFromSignInhibitTimer = 6
      session.msgBoxIsCancelable = true
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:1733 StickerManGetBragFlags
  [Std.SPECIAL.StickerManGetBragFlags] = function(ctx)
    local session = sessionOf(ctx)
    local Flags = flagsMod()
    local store = scriptStore(ctx)
    local stats = session and (session.gameStats or session.stats) or {}

    -- Numeric game stats are authoritative (field_specials.c:1737
    -- GetGameStat); session fields / flags apply only when the index is absent.
    -- HOF enters: GAME_STAT_ENTERED_HOF = 10 (include/constants/game_stat.h:14)
    local hof = stats[10] or stats.enteredHof
      or (session and (session.hofClears or session.hallOfFameCount))
      or (Flags.getFlag(store, ctx, "FLAG_SYS_GAME_CLEAR") and 1 or 0)
    hof = tonumber(hof) or 0

    -- Hatched eggs: GAME_STAT_HATCHED_EGGS = 13 (game_stat.h:17)
    local eggs = stats[13] or stats.hatchedEggs
      or (session and session.eggsHatched) or 0
    eggs = tonumber(eggs) or 0
    local eggsClamped = math.min(0xFFFF, eggs)

    -- Link battle wins: GAME_STAT_LINK_BATTLE_WINS = 23 (game_stat.h:27;
    -- 24 is LINK_BATTLE_LOSSES, which is why wins used to read 0)
    local linkWins = stats[23] or stats.linkBattleWins
      or (session and (session.linkWins or session.linkBattleWins)) or 0
    linkWins = tonumber(linkWins) or 0

    Flags.setVar(store, ctx, VAR_0x8004, hof)
    Flags.setVar(store, ctx, VAR_0x8005, eggsClamped)
    Flags.setVar(store, ctx, VAR_0x8006, linkWins)

    local result = 0
    if hof ~= 0 then result = result + 1 end
    if eggsClamped ~= 0 then result = result + 2 end
    if linkWins ~= 0 then result = result + 4 end

    Flags.setVar(store, ctx, 0x8008, result)
    setResult(ctx, result)
    return false, result
  end,
  -- pokefirered/src/field_specials.c:1710 UpdateTrainerCardPhotoIcons
  [Std.SPECIAL.UpdateTrainerCardPhotoIcons] = function(ctx)
    local party, session = partyOf(ctx)
    local Flags = flagsMod()
    local store = scriptStore(ctx)
    local partyCount = (party and #party) or 0

    local VAR_TRAINER_CARD_MON_ICON_1 = 0x4043
    local VAR_TRAINER_CARD_MON_ICON_TINT_IDX = 0x4042

    for i = 1, 6 do
      local iconSpecies = 0
      if party and i <= partyCount and party[i] then
        local mon = party[i]
        if mon.isEgg then
          iconSpecies = 412 -- SPECIES_EGG
        else
          iconSpecies = tonumber(mon.speciesId or mon.species) or 0
        end
      end
      Flags.setVar(store, ctx, VAR_TRAINER_CARD_MON_ICON_1 + i - 1, iconSpecies)
    end

    local tint = varGet(ctx, VAR_0x8004)
    Flags.setVar(store, ctx, VAR_TRAINER_CARD_MON_ICON_TINT_IDX, tint)
    return false
  end,
  -- pokefirered/src/field_player_avatar.c:1603 SeafoamIslandsB4F_CurrentDumpsPlayerOnLand
  [Std.SPECIAL.SeafoamIslandsB4F_CurrentDumpsPlayerOnLand] = function(ctx, adapters)
    local function finishDismount()
      local session = sessionOf(ctx)
      if session then
        session.surfing = false
        if session.player then
          session.player.surfing = false
          session.player.state = "walk"
          session.player.facing = "up"
        end
        session.facing = "up"
      end
      local rt = package.loaded["src.core.game3.runtime"]
      if rt and rt.player then
        rt.player.surfing = false
        rt.player.state = "walk"
        rt.player.facing = "up"
      end
      local okP, Player = pcall(require, "src.core.game3.player")
      if okP and Player then
        Player.surfing = false
        Player.state = "walk"
        Player.facing = "up"
      end
      local Field = package.loaded["src.core.game3.field"]
      if Field and Field.stopSurfing then
        pcall(Field.stopSurfing)
      end
    end

    if adapters and adapters.applyMovement then
      local Natives = require("src.core.game3.scripting.natives")
      return Natives.yieldHost(ctx, adapters, function(done)
        -- 0xA7 = MOVEMENT_ACTION_JUMP_SPECIAL_WITH_EFFECT_UP (jump 1 cell up onto stairs)
        adapters.applyMovement(255, { 0xA7, 0xFE }, function()
          finishDismount()
          done()
        end)
      end)
    else
      local okP, Player = pcall(require, "src.core.game3.player")
      if okP and Player and Player.cellY then
        Player.cellY = Player.cellY - 1
        Player.targetY = Player.cellY
        Player.py = Player.cellY * 16
      end
      finishDismount()
      return false
    end
  end,
  -- pokefirered/src/start_menu.c:620 Field_AskSaveTheGame
  [Std.SPECIAL.Field_AskSaveTheGame] = function(ctx, adapters)
    local okL, Link = pcall(require, "src.core.game3.link.init")
    if okL and Link and Link.askSaveTheGame then
      return Link.askSaveTheGame(ctx, adapters)
    end
    setResult(ctx, 0)
    return false
  end,
  -- pokefirered/src/load_save.c:208 LoadPlayerBag
  [Std.SPECIAL.LoadPlayerBag] = function()
    local okL, Link = pcall(require, "src.core.game3.link.init")
    if okL and Link and Link.loadPlayerBag then
      Link.loadPlayerBag()
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:461
  -- review-v3 Q8: pret src/field_specials.c:461-493 ShakeScreen — camera
  -- pan task: VAR_0x8004=y, VAR_0x8005=x, VAR_0x8006=iterations,
  -- 0x8007=duration; the pan flips sign every `duration` frames for
  -- `iterations` beats, then recentres (FieldView.cameraPanX/Y — the same
  -- seam natives_elevator writes).  SE_M_STRENGTH = 207
  -- (pret include/constants/songs.h:212), played at task creation.
  [Std.SPECIAL.ShakeScreen] = function(ctx)
    local x = varGet(ctx, VAR_0x8005)
    local y = varGet(ctx, VAR_0x8004)
    local iters = varGet(ctx, VAR_0x8006)
    local dur = varGet(ctx, 0x8007) -- pret gSpecialVar_0x8007 (no name const)
    if (x == 0 and y == 0) or iters < 1 or dur < 1 then return false end
    local FieldView = package.loaded["src.core.game3.field_view"]
    local okT, Task = pcall(require, "src.core.game3.task")
    if not (okT and Task and Task.spawn) then return false end
    pcall(function() require("src.core.game3.audio").playSe(207) end)
    local frame, left, cx, cy = 0, iters, x, y
    Task.spawn(function()
      frame = frame + 1
      if frame % dur == 0 then
        left = left - 1
        cx, cy = -cx, -cy
        if FieldView then
          FieldView.cameraPanX = cx
          FieldView.cameraPanY = cy
        end
        if left == 0 then
          if FieldView then
            FieldView.cameraPanX = 0
            FieldView.cameraPanY = 0
          end
          return true
        end
      end
      return false
    end)
    return false
  end,
  -- review-v3 Q8: DEFERRED — InitRoamer (pret src/roamer.c:120) boots the
  -- full roamer system (ClearRoamerData + CreateInitialRoamerMon box-mon,
  -- location-set tables, roam movement); the port has no roamer runtime
  -- beyond battle_bridge's `roamer` flag, so a stateless stub would only
  -- create dead state.  Needs the roamer feature system first.
  [Std.SPECIAL.InitRoamer] = noop,
  -- review-v3 Q8: pret src/field_specials.c:679-690 + :697-717 — when the
  -- request var is empty, sample an OWNED dex species (100 random rolls,
  -- else walk down with the pret wrap), pick the reward (30% luxury ball),
  -- reset the step counter, and publish the species name in gStringVar1.
  [Std.SPECIAL.SampleResortGorgeousMonAndReward] = function(ctx)
    local session = sessionOf(ctx)
    if not session then return false end
    local VAR_REQ = 0x4036    -- pret include/constants/vars.h:104
    local VAR_REWARD = 0x403B -- pret vars.h:109
    local VAR_STEP = 0x4035   -- pret vars.h:103 (GOREGEOUS typo is pret's)
    local requested = varGet(ctx, VAR_REQ)
    local store = scriptStore(ctx)
    local F = flagsMod()
    if requested == 0 or requested == 0xFFFF then
      local Rng = require("src.core.game3.rng")
      local ownedT = (session.dex and (session.dex.owned or session.dex.caught)) or {}
      local NUM = 411 -- pret NUM_SPECIES-1 (species.h:423 SPECIES_EGG=412)
      local sp, found = 1, false
      for _ = 1, 100 do
        sp = (Rng.Random() % NUM) + 1
        if ownedT[sp] then found = true break end
      end
      if not found then
        -- pret: walk down from the last roll, wrapping 1 → NUM.
        for _ = 1, 500 do -- pret is unbounded; cap guards an empty dex
          if ownedT[sp] then found = true break end
          if sp == 1 then sp = NUM else sp = sp - 1 end
        end
      end
      F.setVar(store, ctx, VAR_REQ, sp)
      -- 107/106/108/109/110/68 = BIG_PEARL/PEARL/STARDUST/STAR_PIECE/
      -- NUGGET/RARE_CANDY (pret items.h:72,110-114); 11 = LUXURY_BALL (:15).
      local rewards = { 107, 106, 108, 109, 110, 68 }
      local reward = 11
      if (Rng.Random() % 100) < 30 then
        reward = rewards[(Rng.Random() % #rewards) + 1]
      end
      F.setVar(store, ctx, VAR_REWARD, reward)
      F.setVar(store, ctx, VAR_STEP, 0)
    end
    -- pret: StringCopy(gStringVar1, gSpeciesNames[requested]) every call.
    local nameOf = package.loaded["src.core.game3.pokemon"]
      or require("src.core.game3.pokemon")
    if type(session.stringVars) ~= "table" then session.stringVars = {} end
    session.stringVars[1] = (nameOf.name and nameOf.name(requested)) or ""
    return false
  end,
  -- pokefirered/src/script.c:245 DisableMsgBoxWalkaway — the script turns off
  -- walk-away cancel for the box it is about to show (questionnaires, move
  -- tutors): the mirror image of SetWalkingIntoSignVars above.
  [Std.SPECIAL.DisableMsgBoxWalkaway] = function(ctx)
    if ctx then
      ctx.msgBoxIsCancelable = false
      ctx.canWalkAway = false
    end
    local session = sessionOf(ctx)
    if session then
      session.msgBoxIsCancelable = false
      session.canWalkAway = false
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:2319
  [Std.SPECIAL.DoDeoxysTriangleInteraction] = function(ctx)
    local session = sessionOf()
    if not session then return false end
    local Deoxys = require("src.core.game3.deoxys")
    -- The script does `waitstate` then `switch VAR_RESULT`; the rock animation
    -- runs on in the background exactly as pret's Task_WaitDeoxysFieldEffect does.
    setResult(ctx, Deoxys.interact(session))
    return false
  end,
  -- pokefirered/src/field_specials.c:2451
  [Std.SPECIAL.SetDeoxysTrianglePalette] = function(ctx)
    local session = sessionOf()
    local Deoxys = require("src.core.game3.deoxys")
    local num = session and Deoxys.getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM)
    if num == nil then num = varGet(ctx, Deoxys.VAR_DEOXYS_INTERACTION_NUM) end
    Deoxys.applyRockPalette(num or 0)
    return false
  end,
  -- pokefirered/src/field_specials.c:2512
  -- review-v3 Q8: pret src/field_specials.c:2512-2531 — HOF-clear counts
  -- gate the eight Lorelei-house doll flags (25/50/75/100/125/150/175/200),
  -- GAME_STAT_ENTERED_HOF = 10 (game_stat.h:14).
  [Std.SPECIAL.UpdateLoreleiDollCollection] = function(ctx)
    local session = sessionOf(ctx)
    local stats = session and (session.gameStats or session.stats) or {}
    local n = tonumber(stats[10]) or 0
    local F = flagsMod()
    local store = scriptStore(ctx)
    local dolls = {
      { 25, "FLAG_HIDE_LORELEI_HOUSE_MEOWTH_DOLL" },
      { 50, "FLAG_HIDE_LORELEI_HOUSE_CHANSEY_DOLL" },
      { 75, "FLAG_HIDE_LORELEIS_HOUSE_NIDORAN_F_DOLL" },
      { 100, "FLAG_HIDE_LORELEI_HOUSE_JIGGLYPUFF_DOLL" },
      { 125, "FLAG_HIDE_LORELEIS_HOUSE_NIDORAN_M_DOLL" },
      { 150, "FLAG_HIDE_LORELEIS_HOUSE_FEAROW_DOLL" },
      { 175, "FLAG_HIDE_LORELEIS_HOUSE_PIDGEOT_DOLL" },
      { 200, "FLAG_HIDE_LORELEIS_HOUSE_LAPRAS_DOLL" },
    }
    for _, d in ipairs(dolls) do
      if n >= d[1] then F.setFlag(store, ctx, d[2], false) end
    end
    return false
  end,
}

Events.HANDLERS[Std.SPECIAL.SetPostgameFlagsUnusedSlot] =
  Events.HANDLERS[Std.SPECIAL.SetPostgameFlags]

-- pokefirered/include/constants/global.h DIR_* as engine dir codes
-- (src/core/game3/field.lua DIR_BY_FACING): down=1 up=2 left=3 right=4.
local DIR_BY_NAME = { down = 1, up = 2, left = 3, right = 4 }
local WALKAWAY_ORDER = { "down", "up", "left", "right" }

-- pokefirered/src/field_control_avatar.c:301 FieldInput_HandleCancelSignpost.
-- Called every field frame from field.lua with the live script VM and the
-- frame's input, before player input is processed (overworld.c:1402).
-- Decrements the sign walk-away inhibit timer armed by SetWalkingIntoSignVars;
-- once it expires, pushes the D-pad away from the facing direction to cancel
-- the open sign message — the engine mirror of EventScript_CancelMessageBox
-- (data/event_scripts.s:1166): DoPicboxCancel (close the box), release, end.
function Events.pollWalkaway(vm, input)
  if not vm or not vm.ctx then return end
  local ctx = vm.ctx
  local session = sessionOf(ctx)

  local function clearWalkaway()
    ctx.walkAwayFromSignInhibitTimer = nil
    ctx.msgBoxIsCancelable = nil
    ctx.canWalkAway = nil
    if session then
      session.walkAwayFromSignInhibitTimer = nil
      session.msgBoxIsCancelable = nil
      session.canWalkAway = nil
    end
  end

  -- Walk-away rights die with the script (script.c:349 clears cancelable
  -- state on every new script): drop leftovers so the next message box
  -- cannot inherit them.
  if not (vm.isRunning and vm:isRunning()) then
    if ctx.walkAwayFromSignInhibitTimer ~= nil
      or ctx.msgBoxIsCancelable ~= nil
      or ctx.canWalkAway ~= nil then
      clearWalkaway()
    end
    return
  end

  local timer = tonumber(ctx.walkAwayFromSignInhibitTimer)
  if not timer then return end -- never armed for this script
  if timer > 0 then
    ctx.walkAwayFromSignInhibitTimer = timer - 1
    if session then
      session.walkAwayFromSignInhibitTimer = math.max(0, timer - 1)
    end
    return
  end

  -- Inhibit expired: walk-away must still be allowed on both halves (a
  -- script may have flipped them off with DisableMsgBoxWalkaway).
  local cancelable = ctx.msgBoxIsCancelable
  local canWalk = ctx.canWalkAway
  if session then
    if cancelable == nil then cancelable = session.msgBoxIsCancelable end
    if canWalk == nil then canWalk = session.canWalkAway end
  end
  if cancelable ~= true or canWalk ~= true then return end
  if ctx.messageOpen ~= true then return end

  -- input->dpadDirection != 0 && GetPlayerFacingDirection() != dpadDirection
  local dir
  if input then
    for _, d in ipairs(WALKAWAY_ORDER) do
      if input.wasPressed and input:wasPressed(d) then
        dir = d
        break
      end
    end
    if not dir then
      for _, d in ipairs(WALKAWAY_ORDER) do
        if input.isDown and input:isDown(d) then
          dir = d
          break
        end
      end
    end
  end
  if not dir then return end
  -- VAR_FACING is stamped by Vm:start from the player facing at script start;
  -- the player cannot turn while the script runs, so it is still current.
  local facing = ctx.specialVars and tonumber(ctx.specialVars[VAR_FACING])
  if not facing then
    local P = package.loaded["src.core.game3.player"]
    facing = P and DIR_BY_NAME[P.facing] or nil
  end
  if not facing or facing == DIR_BY_NAME[dir] then return end

  -- data/event_scripts.s:1166 EventScript_CancelMessageBox: DoPicboxCancel,
  -- release, end.
  if vm.adapters and vm.adapters.closeMessage then
    vm.adapters.closeMessage()
  end
  ctx.messageOpen = false
  if ctx.frozen then
    local okF, Field = pcall(require, "src.core.game3.field")
    if okF and Field and Field.unlock then Field.unlock() end
  end
  clearWalkaway()
  vm:halt(true)
end

return Events
