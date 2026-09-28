local Natives = {}

Natives.BY_NAME = {
  -- pokeemerald/src/field_specials.c:141
  Special_ShowDiploma = function(ctx, adapters)
    local Native = require("src.core.game3.scripting.natives")
    local Diploma = require("src.ui.game3.diploma")
    return Native.yieldHost(ctx, adapters, function(done)
      local shown = Diploma.show({ onDone = done })
      if not shown then done() end
    end)
  end,
}

return Natives
