-- callnative / special allowlist; unknown → safe-skip + log once.
-- Handlers mirror pret specials → host adapters (heal / PC), not map coords.

local Std = require("src.core.game3.scripting.stdscripts")

local Natives = {}

Natives._logged = {}

local function yield_host(ctx, adapters, startFn)
  local finished = false
  ctx.mode = "native"
  ctx.status = "waiting"
  ctx.nativePoll = function() return finished end
  startFn(function()
    finished = true
  end)
  return not finished -- true = caller should yield
end

Natives.ALLOW = {
  ["special:" .. Std.SPECIAL.HealPlayerParty] = function(ctx, adapters)
    if not (adapters and adapters.nurseHeal) then return false end
    return yield_host(ctx, adapters, adapters.nurseHeal)
  end,
  ["special:" .. Std.SPECIAL.ShowPokemonStorageSystemPC] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, adapters.openPc)
  end,
  ["special:" .. Std.SPECIAL.PlayerPC] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, adapters.openPc)
  end,
  ["special:" .. Std.SPECIAL.AnimatePcTurnOn] = function() return false end,
  ["special:" .. Std.SPECIAL.AnimatePcTurnOff] = function() return false end,
  ["special:" .. Std.SPECIAL.CreatePCMenu] = function(ctx, adapters)
    -- Cart builds a menu; host PC UI is the whole menu — open it directly.
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, adapters.openPc)
  end,
  ["special:" .. Std.SPECIAL.ShowRegionMap] = function(ctx, adapters)
    if not (adapters and adapters.showTownMap) then return false end
    return yield_host(ctx, adapters, adapters.showTownMap)
  end,
  -- Shared intro/field primitives (fade / naming / cry)
  ["special:" .. Std.SPECIAL.FadeScreen] = function(ctx, adapters)
    if not (adapters and adapters.fadeScreen) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.fadeScreen(0, 1, done)
    end)
  end,
  ["special:" .. Std.SPECIAL.OpenNaming] = function(ctx, adapters)
    if not (adapters and adapters.openNaming) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.openNaming({ title = "NAME?" }, done)
    end)
  end,
  -- pret EventScript_ChangePokemonNickname: fadescreen TO_BLACK → this → waitstate.
  -- Opens naming under the held black, fades in, writes nickname on confirm.
  ["special:" .. Std.SPECIAL.ChangePokemonNickname] = function(ctx, adapters)
    if not (adapters and adapters.openNaming) then return false end
    return yield_host(ctx, adapters, function(done)
      local slot = 0
      if ctx and ctx.getVar then
        slot = tonumber(ctx:getVar(0x8004)) or 0
      end
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      local mon = session and session.party and session.party[slot + 1]
      local species = mon and tonumber(mon.species or mon.speciesId) or 1
      local Pokemon = require("src.core.game3.pokemon")
      pcall(function()
        if not Pokemon._names then Pokemon.install(nil) end
      end)
      local sname = (Pokemon.name and Pokemon.name(species)) or "POKéMON"
      adapters.openNaming({
        title = sname .. "'s nickname?",
        template = "NICKNAME",
        maxLen = 10, -- pret POKEMON_NAME_LENGTH
        species = species,
        personality = mon and mon.personality,
        gender = mon and mon.gender,
      }, function(name)
        if mon and type(name) == "string" and name ~= "" then
          mon.nickname = name
        end
        done()
      end)
    end)
  end,
  ["special:" .. Std.SPECIAL.BufferMonNickname] = function(ctx, adapters)
    -- pret BufferMonNickname → gStringVar1; host buffers for {STR_VAR_1}.
    local slot = 0
    if ctx and ctx.getVar then
      slot = tonumber(ctx:getVar(0x8004)) or 0
    end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local mon = session and session.party and session.party[slot + 1]
    local nick = ""
    if mon then
      if mon.nickname and mon.nickname ~= "" then
        nick = tostring(mon.nickname)
      else
        local Pokemon = require("src.core.game3.pokemon")
        pcall(function()
          if not Pokemon._names then Pokemon.install(nil) end
        end)
        nick = (Pokemon.name and Pokemon.name(mon.species or mon.speciesId)) or ""
      end
    end
    if adapters and adapters.setStringVar then
      adapters.setStringVar(1, nick)
    elseif ctx and ctx.stringVars then
      ctx.stringVars[1] = nick
    end
    return false
  end,
  ["special:" .. Std.SPECIAL.PlayCry] = function(ctx, adapters)
    local Audio = require("src.core.game3.audio")
    local species = 0
    if ctx and ctx.getVar then
      species = tonumber(ctx:getVar(0x8000)) or 0
    end
    Audio.playCry(species)
    return false
  end,
  ["special:" .. Std.SPECIAL.EnableNationalPokedex] = function(ctx, adapters)
    local Flags = require("src.core.game3.scripting.flags")
    local Space = package.loaded["src.core.game3.scripting.space"]
    local store = Space and Space.store
    if store and Flags and Flags.setFlag then
      Flags.setFlag(store, nil, 0x840, true) -- FLAG_SYS_NATIONAL_DEX
      if Flags.setVar then
        Flags.setVar(store, nil, 0x404E, 0x6258) -- VAR_NATIONAL_DEX
      end
    end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    if session then
      session.national_dex_unlocked = true
      if session.dex then
        session.dex.nationalUnlocked = true
      end
      if session.store and Flags and Flags.setFlag then
        Flags.setFlag(session.store, nil, 0x840, true)
        if Flags.setVar then
          Flags.setVar(session.store, nil, 0x404E, 0x6258)
        end
      end
    end
    if adapters and adapters.setFlag then
      adapters.setFlag(0x840, true)
    end
    return false
  end,
  ["special:" .. Std.SPECIAL.IsNationalPokedexEnabled] = function(ctx, adapters)
    local PokedexData = require("src.core.game3.pokedex_data")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local dex = session and session.dex
    local isUnlocked = PokedexData.isNationalUnlocked(session, dex)
    local resVal = isUnlocked and 1 or 0
    if ctx and ctx.setVar then
      ctx:setVar(0x800D, resVal) -- VAR_RESULT
    end
    if adapters and adapters.setVar then
      adapters.setVar(0x800D, resVal)
    end
    return false
  end,
  ["special:" .. Std.SPECIAL.SetUnlockedPokedexFlags] = function(ctx, adapters)
    local Flags = require("src.core.game3.scripting.flags")
    local Space = package.loaded["src.core.game3.scripting.space"]
    local store = Space and Space.store
    if store and Flags and Flags.setFlag then
      Flags.setFlag(store, nil, 0x829, true) -- FLAG_SYS_POKEDEX_GET
    end
    if adapters and adapters.setFlag then
      adapters.setFlag(0x829, true)
    end
    return false
  end,
  ["special:" .. Std.SPECIAL.EnterHallOfFame] = function(ctx, adapters)
    local Flags = require("src.core.game3.scripting.flags")
    local flagGameClear = (Flags.IDS and Flags.IDS.SYS_GAME_CLEAR) or 0x82C
    local Space = package.loaded["src.core.game3.scripting.space"]
    local store = Space and Space.store
    if store and Flags and Flags.setFlag then
      Flags.setFlag(store, nil, flagGameClear, true) -- FLAG_SYS_GAME_CLEAR
    end
    if adapters and adapters.setFlag then
      adapters.setFlag(flagGameClear, true)
    end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    if session then
      session.game_cleared = true
      if session.store and Flags and Flags.setFlag then
        Flags.setFlag(session.store, nil, flagGameClear, true)
      end
    end
    if adapters and adapters.hallOfFame then
      return yield_host(ctx, adapters, adapters.hallOfFame)
    end
    return false
  end,
}

function Natives.resetLog()
  Natives._logged = {}
end

local function log_once(kind, id, logger)
  local key = kind .. ":" .. tostring(id)
  if Natives._logged[key] then return end
  Natives._logged[key] = true
  local msg = string.format("[game3] skip unknown %s 0x%X", kind, tonumber(id) or 0)
  if logger then logger(msg) else print(msg) end
end

--- Returns whether the VM should yield (native wait).
function Natives.callnative(ctx, fnAddr, adapters)
  local id = tonumber(fnAddr) or 0
  local handler = Natives.ALLOW["native:" .. id]
  if handler then
    return handler(ctx, adapters) and true or false
  end
  log_once("callnative", id, adapters and adapters.log)
  return false
end

function Natives.special(ctx, specialId, adapters)
  local id = tonumber(specialId) or 0
  local handler = Natives.ALLOW["special:" .. id]
  if handler then
    return handler(ctx, adapters) and true or false
  end
  log_once("special", id, adapters and adapters.log)
  return false
end

return Natives
