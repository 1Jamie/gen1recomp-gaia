-- Wireless / RFU-side specials: Pokemon Jump + Dodrio Berry Picking records,
-- the Berry Powder vendor exchange (CeruleanCity_House5), Berry Crush rankings,
-- and the Seven Island e-Reader trainer house.  The port has no Wireless
-- Adapter hardware, so RF-internal work degrades to safe answers that let the
-- calling scripts finish — no dispatch entry is left nil.
--
-- pret anchors: data/specials.inc, src/berry_powder.c, src/pokemon_jump.c,
-- src/dodrio_berry_picking.c, src/berry_crush.c, src/battle_tower.c,
-- src/field_specials.c.

local Strings = require("src.core.Strings")
local Std = require("src.core.game3.scripting.stdscripts")

local Wireless = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_OBJ_GFX_ID_0 = 0x4010 -- pokefirered/include/constants/vars.h:28
local OBJ_EVENT_GFX_YOUNGSTER = 18 -- pokefirered/include/constants/event_objects.h:24
local PARTY_SIZE = 6 -- pokefirered/include/constants/pokemon.h
local MAX_BERRY_POWDER = 99999 -- pokefirered/src/berry_powder.c:12

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

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(ctx), ctx, id, tonumber(value) or 0)
end

local function setResult(ctx, value)
  varSet(ctx, VAR_RESULT, value)
end

local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then pcall(adapters.setStringVar, index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

-- pokefirered/src/battle_tower.c:1354 ValidateEReaderTrainer / :1368 an
-- all-zero record is no trainer at all.  Reads the session directly so this
-- module never depends on the capability-gated natives_tower module.
local function visitingEReaderTrainer(session)
  local trainer = session and session.ereaderTrainer
  if type(trainer) ~= "table" then return nil end
  if type(trainer.party) ~= "table" or type(trainer.party[1]) ~= "table" then
    return nil
  end
  return trainer
end

-- pokefirered/src/battle_tower.c:830 BufferBattleTowerTrainerMessage — the
-- greeting is an easy-chat phrase; same conversion seam as
-- natives_tower.lua:165 convertSpeech.
local function convertSpeech(words)
  if type(words) ~= "table" then return "" end
  local okE, EasyChatData = pcall(require, "src.core.game3.easy_chat_data")
  if not (okE and EasyChatData and EasyChatData.formatPhrase) then return "" end
  local ok, text = pcall(EasyChatData.formatPhrase, words, 3, 2)
  if ok and type(text) == "string" then return text end
  return ""
end

Wireless.HANDLERS = {
  -- pokefirered/src/party_menu.c:5818 ChooseMonForWirelessMinigame
  -- data/scripts/cable_club.inc:1181/1196: the picker writes the party slot
  -- into VAR_0x8004 and the script aborts when it is >= PARTY_SIZE.  The port
  -- has no RFU minigame behind the picker, so answer "cancel" deterministically
  -- — the script takes its AbortMinigame path instead of dead-ending.
  [Std.SPECIAL.ChooseMonForWirelessMinigame] = function(ctx)
    varSet(ctx, VAR_0x8004, PARTY_SIZE)
    return false
  end,

  -- pokefirered/src/pokemon_jump.c:2687 IsPokemonJumpSpeciesInParty
  -- data/scripts/cable_club.inc:1177: VAR_RESULT FALSE prints
  -- CableClub_EventScript_NoEligiblePkmn and exits.  The sPokeJumpMons
  -- eligibility table (pokemon_jump.c:766) backs a minigame the port cannot
  -- host, so the graceful answer is FALSE — no dead air, no nil dispatch.
  [Std.SPECIAL.IsPokemonJumpSpeciesInParty] = function(ctx)
    setResult(ctx, 0)
    return false, 0
  end,

  -- pokefirered/src/pokemon_jump.c:4487 ShowPokemonJumpRecords
  -- data/scripts/cable_club.inc:1278 + TwoIsland_JoyfulGameCorner scripts:
  -- `special / waitstate / releaseall`.  No RFU link records exist in the
  -- port, so the screen is skipped and the waitstate completes instantly.
  [Std.SPECIAL.ShowPokemonJumpRecords] = function()
    return false
  end,

  -- pokefirered/src/dodrio_berry_picking.c:2929 ShowDodrioBerryPickingRecords
  -- data/scripts/cable_club.inc:1286 + Two Island Game Corner records corner.
  [Std.SPECIAL.ShowDodrioBerryPickingRecords] = function()
    return false
  end,

  -- pokefirered/src/berry_crush.c:3189 ShowBerryCrushRankings
  -- data/maps/CeruleanCity_House5/scripts.inc:169 EventScript_BerryCrushRankings:
  -- `lockall / special / waitstate / releaseall`.
  [Std.SPECIAL.ShowBerryCrushRankings] = function()
    return false
  end,

  -- pokefirered/src/berry_powder.c:113 DisplayBerryPowderVendorMenu — draws
  -- the powder-amount window over the House5 dialogue.  The port shows the
  -- amount on the POWDER JAR bag line instead (item_use.lua:727), so this
  -- only records that the vendor window pair is open.
  [Std.SPECIAL.DisplayBerryPowderVendorMenu] = function(ctx)
    if ctx then ctx.berryPowderVendorOpen = true end
    local session = sessionOf(ctx)
    if session then session.berryPowderVendorOpen = true end
    return false
  end,

  -- pokefirered/src/berry_powder.c:128 RemoveBerryPowderVendorMenu
  [Std.SPECIAL.RemoveBerryPowderVendorMenu] = function(ctx)
    if ctx then ctx.berryPowderVendorOpen = false end
    local session = sessionOf(ctx)
    if session then session.berryPowderVendorOpen = false end
    return false
  end,

  -- pokefirered/src/berry_powder.c:108 PrintPlayerBerryPowderAmount — repaints
  -- the vendor window opened by DisplayBerryPowderVendorMenu.  No such window
  -- in the port (see Display above), so nothing to repaint: bound no-op.
  [Std.SPECIAL.PrintPlayerBerryPowderAmount] = function()
    return false
  end,

  -- pokefirered/src/berry_powder.c:40 Script_HasEnoughBerryPowder
  -- VAR_0x8004 holds the cost; answer mirrors the pret bool return.
  [Std.SPECIAL.Script_HasEnoughBerryPowder] = function(ctx)
    local session = sessionOf(ctx)
    local powder = math.floor(tonumber(session and session.berryPowder) or 0)
    local cost = varGet(ctx, VAR_0x8004)
    local enough = (powder >= cost) and 1 or 0
    setResult(ctx, enough)
    return false, enough
  end,

  -- pokefirered/src/berry_powder.c:77 Script_TakeBerryPowder — subtracts
  -- VAR_0x8004 when affordable, else answers FALSE and leaves the balance.
  -- session.berryPowder is the port's powder field (item_use.lua:728).
  [Std.SPECIAL.Script_TakeBerryPowder] = function(ctx)
    local session = sessionOf(ctx)
    local powder = math.floor(tonumber(session and session.berryPowder) or 0)
    local cost = varGet(ctx, VAR_0x8004)
    local took = 0
    if session and powder >= cost then
      powder = math.min(powder - cost, MAX_BERRY_POWDER)
      session.berryPowder = powder
      took = 1
    end
    setResult(ctx, took)
    return false, took
  end,

  -- pokefirered/src/field_specials.c:331 BufferEReaderTrainerName —
  -- CopyEReaderTrainerName5(gStringVar1) (battle_tower.c:1343).  Called by
  -- data/maps/SevenIsland_House_Room1/scripts.inc:88; the dialogue prints
  -- {STR_VAR_1} (text.inc:19).  Physical card data never reaches the port, so
  -- fall back to a generic name when no stored record exists.
  [Std.SPECIAL.BufferEReaderTrainerName] = function(ctx, adapters)
    local trainer = visitingEReaderTrainer(sessionOf(ctx))
    local name = trainer and trainer.name
    if type(name) ~= "string" or name == "" then name = Strings("TRAINER") end
    setStringVar(ctx, adapters, 1, name)
    return false
  end,

  -- pokefirered/src/battle_tower.c:1401 BufferEReaderTrainerGreeting —
  -- buffers the card's easy-chat greeting into gStringVar4;
  -- data/maps/SevenIsland_House_Room2/scripts.inc:18 prints it via
  -- `msgbox gStringVar4`.  No card => stored greeting if the record carries
  -- one, else a short stock line so the box is never blank.
  [Std.SPECIAL.BufferEReaderTrainerGreeting] = function(ctx, adapters)
    local trainer = visitingEReaderTrainer(sessionOf(ctx))
    local greeting = trainer and trainer.greeting
    local text
    if type(greeting) == "string" and greeting ~= "" then
      text = greeting
    elseif type(greeting) == "table" then
      text = convertSpeech(greeting)
    end
    if not text or text == "" then text = Strings("OK, LET'S BATTLE!") end
    setStringVar(ctx, adapters, 4, text)
    return false
  end,

  -- pokefirered/src/battle_tower.c:397 SetEReaderTrainerGfxId —
  -- VarSet(VAR_OBJ_GFX_ID_0, OBJ_EVENT_GFX_YOUNGSTER) so the visiting trainer
  -- object has a gfx id; data/maps/SevenIsland_House_Room2/scripts.inc:7 runs
  -- it on transition.
  [Std.SPECIAL.SetEReaderTrainerGfxId] = function(ctx)
    varSet(ctx, VAR_OBJ_GFX_ID_0, OBJ_EVENT_GFX_YOUNGSTER)
    return false
  end,
}

return Wireless
