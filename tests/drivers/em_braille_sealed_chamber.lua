local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_braille_sealed_chamber")

return function(game)
  if not F.boot(game) then return F.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local FieldView = require("src.core.game3.field_view")
  local BrailleField = require("src.core.game3.braille_field")
  local Field = require("src.core.game3.field")
  local C = require("src.core.game3.constants").of("emerald")
  local fl = F.flags()
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_WAILORD"), 40)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 40)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_RELICANTH"), 40)
  F.check(BrailleField.checkRelicanthWailord(session), "Wailord first and Relicanth last satisfies CheckRelicanthWailord")

  F.check(F.goTo(game, "EM_SEALED_CHAMBER_OUTER_ROOM", 10, 3, "up"), "Sealed Chamber outer room loads")
  F.check(BrailleField.shouldDoDig(session), "digging at (10,3) under the braille is the dig puzzle spot")
  BrailleField.doDig(session)
  U.wait(4)
  local top = C:require("metatile_labels", "METATILE_Cave_SealedChamberEntrance_TopMid")
  local ov = Field.metatileOverrideAt("EM_SEALED_CHAMBER_OUTER_ROOM", 10, 1)
  F.check(ov and ov.metatile == top, "DoBrailleDigEffect opens the chamber entrance metatiles")
  F.check(fl.get("FLAG_SYS_BRAILLE_DIG"), "FLAG_SYS_BRAILLE_DIG set")
  F.check(not BrailleField.shouldDoDig(session), "the dig spot is spent once opened")
  F.shot(game, "01_outer_room_dug_open.png", true)

  F.check(F.goTo(game, "EM_SEALED_CHAMBER_INNER_ROOM", 10, 5, "up"), "Sealed Chamber inner room loads")
  U.tap(game, "a")
  local braille = false
  for _ = 1, 200 do
    if Space.vm and Space.vm:isRunning() then braille = true end
    if braille then break end
    U.wait(1)
  end
  F.check(braille, "A on the back wall runs the braille script")
  U.wait(20)
  F.shot(game, "02_braille_back_wall.png", true)
  local maxPan, done = 0, false
  for _ = 1, 1500 do
    maxPan = math.max(maxPan, math.abs(FieldView.cameraPanY or 0))
    if fl.get("FLAG_REGI_DOORS_OPENED") and not (Space.vm and Space.vm:isRunning()) then done = true break end
    if maxPan > 0 and not F.shakeShot then
      F.shakeShot = true
      F.shot(game, "03_chamber_shaking.png", true)
    end
    if (_ % 20) == 0 then U.tap(game, "a") else U.wait(1) end
  end
  F.check(maxPan >= 2, "DoSealedChamberShakingEffect shakes the camera (" .. maxPan .. ")")
  F.check(done, "FLAG_REGI_DOORS_OPENED set after the door-opened message")
  F.check((FieldView.cameraPanY or 0) == 0, "camera panning restored after the shakes")
  F.finish()
end
