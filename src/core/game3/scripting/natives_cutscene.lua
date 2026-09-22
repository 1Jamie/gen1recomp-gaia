local Std = require("src.core.game3.scripting.stdscripts")

local Cutscene = {}

local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321

local SE_M_WING_ATTACK = 150 -- pokefirered/include/constants/songs.h:155
local SE_SS_ANNE_HORN = 249 -- pokefirered/include/constants/songs.h:255

local SPECIES_KABUTOPS = 141 -- pokefirered/src/script_menu.c:1165 (museum_extract.lua:9)
local SPECIES_AERODACTYL = 142 -- pokefirered/src/script_menu.c:1171

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

local function playSe(adapters, id)
  if adapters and adapters.playSe then
    adapters.playSe(id, false)
    return
  end
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function currentGame()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt._game or nil
end

local function cameraObject()
  local ok, CameraObject = pcall(require, "src.core.game3.camera_object")
  if ok and type(CameraObject) == "table" then return CameraObject end
  return nil
end

Cutscene.HANDLERS = {
  -- pokefirered/src/field_specials.c:318
  [Std.SPECIAL.SpawnCameraObject] = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.spawn then
      pcall(CameraObject.spawn, currentGame())
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:325
  [Std.SPECIAL.RemoveCameraObject] = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.remove then
      pcall(CameraObject.remove, currentGame())
    end
    return false
  end,
  -- review-v3 Q7: pret src/special_field_anim.c:223-265
  -- AnimateTeleporterHousing — 16-frame beats cycle the Sea Cottage
  -- teleporter light/door metatiles through 13 states (yellow/half-glow ↔
  -- red/full-glow), then rest on the green light + closed door.  Coord
  -- offsets: VAR_0x8004==0 → (x+6, y-5) right unit, else (x-1, y-5) left
  -- (metatile ids: pret include/constants/metatile_labels.h:177-186).
  -- Field.setMetatile routes through metatileOverrides + applyOverride, so
  -- the normal per-frame field draw picks the tiles up (same seam as the
  -- door override at field.lua:1110).  Headless suites cannot render the
  -- glow cycle — in-game visual check pending (AGENTS.md caveat).
  [Std.SPECIAL.AnimateTeleporterHousing] = function(ctx)
    local P = package.loaded["src.core.game3.player"]
      or require("src.core.game3.player")
    local okF, Field = pcall(require, "src.core.game3.field")
    local okT, Task = pcall(require, "src.core.game3.task")
    if not (okF and Field and Field.setMetatile and okT and Task and Task.spawn) then
      return false
    end
    local x = tonumber(P.cellX) or 0
    local y = (tonumber(P.cellY) or 0) - 5
    if varGet(ctx, VAR_0x8004) == 0 then x = x + 6 else x = x - 1 end
    local timer, state = 0, 0
    Task.spawn(function()
      if timer == 0 then
        if state % 2 == 0 then
          Field.setMetatile(x, y, 0x2B5, false)     -- Light_Yellow
          Field.setMetatile(x, y + 2, 0x2B7, false) -- Door_HalfGlowing
        else
          Field.setMetatile(x, y, 0x2B6, false)     -- Light_Red
          Field.setMetatile(x, y + 2, 0x2B8, false) -- Door_FullGlowing
        end
      end
      timer = timer + 1
      if timer ~= 16 then return false end
      timer = 0
      state = state + 1
      if state ~= 13 then return false end
      Field.setMetatile(x, y, 0x28A, false)     -- Light_Green (resting)
      Field.setMetatile(x, y + 2, 0x296, false) -- Door
      return true
    end)
    return false
  end,
  -- review-v3 Q7: pret src/special_field_anim.c:285-330
  -- AnimateTeleporterCable — every 4 frames walk a cable-ball pair left from
  -- (x+4, y-5), leaving the plain cable tiles behind, and stop after 4
  -- steps (state 4 draws the last plain tiles and destroys the task).
  [Std.SPECIAL.AnimateTeleporterCable] = function()
    local P = package.loaded["src.core.game3.player"]
      or require("src.core.game3.player")
    local okF, Field = pcall(require, "src.core.game3.field")
    local okT, Task = pcall(require, "src.core.game3.task")
    if not (okF and Field and Field.setMetatile and okT and Task and Task.spawn) then
      return false
    end
    local x = (tonumber(P.cellX) or 0) + 4
    local y = (tonumber(P.cellY) or 0) - 5
    local timer, state = 0, 0
    Task.spawn(function()
      if timer == 0 then
        if state ~= 0 then
          Field.setMetatile(x, y, 0x285, false)     -- Cable_Top
          Field.setMetatile(x, y + 1, 0x2B4, false) -- Cable_Bottom
          if state == 4 then return true end
          x = x - 1
        end
        Field.setMetatile(x, y, 0x2B9, false)     -- CableBall_Top
        Field.setMetatile(x, y + 1, 0x2BA, false) -- CableBall_Bottom
      end
      timer = timer + 1
      if timer == 4 then
        timer = 0
        state = state + 1
      end
      return false
    end)
    return false
  end,

  -- pokefirered/src/credits.c:711 DoCredits — the Indigo Plateau roll
  -- (data/maps/IndigoPlateau_Exterior/scripts.inc:80 `special / waitstate /
  -- releaseall`).  The port has no game3 credits sequence yet; bound so the
  -- waitstate completes and the script releases instead of skipping the
  -- dispatch as unknown.
  [Std.SPECIAL.DoCredits] = function()
    return false
  end,

  -- pokefirered/src/field_specials.c:90 ShowDiploma — pushes CB2_ShowDiploma
  -- (diploma.c:100); data/maps/CeladonCity_Condominiums_3F/scripts.inc:34
  -- parks on `waitstate`.  src/ui/Diploma.lua is the Gen 1 diploma page
  -- (engine/events/diploma.asm) with no FRLG wiring yet, so this completes
  -- the waitstate: the congratulations message still shows, the certificate
  -- screen is future work.
  [Std.SPECIAL.ShowDiploma] = function()
    return false
  end,

  -- pokefirered/src/ss_anne.c:82 DoSSAnneDepartureCutscene — horn + wake/smoke
  -- boat task; data/maps/SSAnne_Exterior/scripts.inc:21 runs it after
  -- `delay 50`, then removes the boat and warps.  The port has no wake/sprite
  -- sail task, so play the horn (SE_SS_ANNE_HORN) and let the script's own
  -- object removal + warp carry the beat.
  [Std.SPECIAL.DoSSAnneDepartureCutscene] = function(ctx, adapters)
    playSe(adapters, SE_SS_ANNE_HORN)
    return false
  end,

  -- pokefirered/src/field_specials.c:2133 DoPokemonLeagueLightingEffect —
  -- a timed BG_PLTT_ID(7) tint task (data/scripts/pokemon_league.inc:63);
  -- FLAG_TEMP_3 selects task-cancel instead of start.  The port never starts
  -- the tint, so the no-op covers both the start and the cancel arm.
  [Std.SPECIAL.DoPokemonLeagueLightingEffect] = function()
    return false
  end,

  -- pokefirered/src/field_specials.c:2535 LoopWingFlapSound — plays
  -- SE_M_WING_ATTACK now, then repeats every VAR_0x8005 frames until
  -- VAR_0x8004 loops (NavelRock_Summit/scripts.inc:39-41 + :54-55 set
  -- 3 loops / 35-frame delay while the camera pans).
  [Std.SPECIAL.LoopWingFlapSound] = function(ctx, adapters)
    local loops = varGet(ctx, VAR_0x8004)
    local delay = varGet(ctx, VAR_0x8005)
    playSe(adapters, SE_M_WING_ATTACK)
    if loops > 0 and delay > 0 then
      local okT, Task = pcall(require, "src.core.game3.task")
      if okT and Task and Task.spawn then
        local ticks, count = 0, 0
        Task.spawn(function()
          ticks = ticks + 1
          if ticks >= delay then
            ticks = 0
            count = count + 1
            playSe(adapters, SE_M_WING_ATTACK)
          end
          -- review-v3 Q11: pret destroys the task at data[0] == VAR_0x8004 - 1
          -- (field_specials.c:2553), so total plays = loops (1 entry + loops-1
          -- ticks), not loops+1.  The check runs every pump like pret's
          -- post-increment check (field_specials.c:2546-2554).
          return count >= loops - 1
        end)
      end
    end
    return false
  end,

  -- pokefirered/src/script_menu.c:1151 OpenMuseumFossilPic — draws the
  -- 64x64 fossil exhibit over the msgbox (data/maps/PewterCity_Museum_1F/
  -- scripts.inc:170-187: setvar species/x/y, special, msgbox, special).  The
  -- art is already extracted (museum_extract.lua -> gba/museum/*.rgba); the
  -- window widget that composites it is still to come, so this records the
  -- open state for that seam.  Species guard mirrors script_menu.c:1165-1176
  -- (only KABUTOPS/AERODACTYL draw; anything else returns FALSE) and, like
  -- pret, never touches dex flags — the old 0x18B mis-bind did.
  [Std.SPECIAL.OpenMuseumFossilPic] = function(ctx)
    local species = varGet(ctx, VAR_0x8004)
    if species ~= SPECIES_KABUTOPS and species ~= SPECIES_AERODACTYL then
      return false
    end
    if ctx then
      ctx.museumFossilPic = {
        species = species,
        x = varGet(ctx, VAR_0x8005),
        y = varGet(ctx, VAR_0x8006),
      }
    end
    return false
  end,

  -- pokefirered/src/script_menu.c:1184 CloseMuseumFossilPic — retires the
  -- task that owns the picture window.
  [Std.SPECIAL.CloseMuseumFossilPic] = function(ctx)
    if ctx then ctx.museumFossilPic = nil end
    return false
  end,
}

return Cutscene
