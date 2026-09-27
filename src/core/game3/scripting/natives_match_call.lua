local NativesMatchCall = {}

local VAR_0x8004 = 0x8004
local VAR_RESULT = 0x800D
-- pokeemerald/include/constants/script_menu.h:8
local MULTI_B_PRESSED = 127

local function session()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function MatchCall()
  return require("src.core.game3.rse.match_call")
end

local function Rematch()
  return require("src.core.game3.rse.rematch")
end

local function Flags()
  return require("src.core.game3.scripting.flags")
end

local function specialVar(ctx, id)
  local v = tonumber(Flags().getVar(nil, ctx, id)) or 0
  if v == 0 and ctx and type(ctx.getVar) == "function" then v = tonumber(ctx:getVar(id)) or 0 end
  return v
end

local function setResult(ctx, v)
  Flags().setVar(nil, ctx, VAR_RESULT, v)
  if ctx and type(ctx.setVar) == "function" then ctx:setVar(VAR_RESULT, v) end
end

local function shared(name, fn)
  return function(ctx, adapters, ...)
    local sess = session()
    if not MatchCall().enabled(sess) then
      local core = require("src.core.game3.scripting.natives").CORE[name]
      if core then return core(ctx, adapters, ...) end
      return false
    end
    return fn(ctx, adapters, sess, ...)
  end
end

NativesMatchCall.BY_NAME = {
  -- pokeemerald/src/battle_setup.c:1839
  ShouldTryRematchBattle = shared("ShouldTryRematchBattle", function(ctx, _, sess)
    setResult(ctx, Rematch().shouldTryRematchBattle(sess, ctx.trainerBattleOpponentA or 0) and 1 or 0)
    return false
  end),
  -- pokeemerald/src/battle_setup.c:1847
  IsTrainerReadyForRematch = shared("IsTrainerReadyForRematch", function(ctx, _, sess)
    setResult(ctx, Rematch().isTrainerReadyForRematch(sess, ctx.trainerBattleOpponentA or 0) and 1 or 0)
    return false
  end),
  -- pokeemerald/src/field_specials.c:3618
  IsTrainerRegistered = function(ctx)
    local sess = session()
    local R = Rematch()
    local idx = R.firstBattleTableId(specialVar(ctx, VAR_0x8004))
    setResult(ctx, (idx >= 0 and R.flag(sess, R.registeredFlagId(sess, idx))) and 1 or 0)
    return false
  end,
  -- pokeemerald/src/pokenav_match_call_data.c:1156
  SetMatchCallRegisteredFlag = function(ctx)
    MatchCall().setRegisteredFlag(session(), specialVar(ctx, VAR_0x8004))
    return false
  end,
  -- pokeemerald/src/script_menu.c:673
  ScriptMenu_CreateStartMenuForPokenavTutorial = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    local sess = session()
    setResult(ctx, 0xFF)
    return Natives.yieldHost(ctx, adapters, function(done)
      local RomText = require("src.core.game3.rom_text")
      local labels = {}
      for i, key in ipairs({ "gText_MenuOptionPokedex", "gText_MenuOptionPokemon", "gText_MenuOptionBag",
          "gText_MenuOptionPokenav", false, "gText_MenuOptionSave", "gText_MenuOptionOption", "gText_MenuOptionExit" }) do
        labels[i] = key and RomText.plain(key) or tostring(sess and (sess.name or sess.playerName) or "")
      end
      local Choice = require("src.ui.game3.choice")
      -- pokeemerald/src/script_menu.c:689
      Choice.multi(labels, 0, function(sel)
        setResult(ctx, (sel == nil or sel < 0) and MULTI_B_PRESSED or sel)
        done()
      end, { left = 22, top = 1, maxRight = 29, ignoreBPress = false })
    end)
  end,
  -- pokeemerald/src/pokenav.c:333
  OpenPokenavForTutorial = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    local sess = session()
    return Natives.yieldHost(ctx, adapters, function(done)
      require("src.ui.game3.rse.pokenav.init").show({ session = sess, tutorial = true, onClose = done })
    end)
  end,
}

pcall(require, "src.core.game3.rse.match_call")

return NativesMatchCall
