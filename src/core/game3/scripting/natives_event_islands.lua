local Rse = require("src.core.game3.rse.init")
local EventIslands = require("src.core.game3.rse.event_islands")

local NativesEventIslands = {}

local function natives() return require("src.core.game3.scripting.natives") end

NativesEventIslands.BY_NAME = {
  -- pokeemerald/src/field_specials.c:3264
  DoDeoxysRockInteraction = function(ctx)
    local s = Rse.session()
    if not s then return false end
    local result, anim = EventIslands.rockInteraction(s)
    Rse.setSpecialVar(ctx, EventIslands.VAR_RESULT, result)
    NativesEventIslands.lastResult = result
    if anim then
      -- pokeemerald/src/field_specials.c:3368
      natives().awaitState(ctx, function()
        local FieldEffects = package.loaded["src.core.game3.field_effects"]
        for _, a in ipairs(FieldEffects and FieldEffects._anims or {}) do
          if a == anim then return false end
        end
        return true
      end)
    end
    return false
  end,
  -- pokeemerald/src/pokemon.c:2773
  CreateEnemyEventMon = function(ctx)
    local Enc = require("src.core.game3.encounters")
    local item = Rse.specialVar(ctx, 0x8006)
    Enc.setWildBattle(Rse.specialVar(ctx, 0x8004), Rse.specialVar(ctx, 0x8005), item ~= 0 and item or nil)
    -- pokeemerald/src/pokemon.c:2635
    if Enc._pendingWild then Enc._pendingWild.fatefulEncounter = true end
    return false
  end,
  -- pokeemerald/src/field_specials.c:3389
  SetDeoxysRockPalette = function()
    EventIslands.setRockPalette(Rse.session())
    return false
  end,
}

return NativesEventIslands
