local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_braille_sealed_chamber")
local S = require("tests.drivers.em_story_util")

local OUTER = "EM_SEALED_CHAMBER_OUTER_ROOM"
local INNER = "EM_SEALED_CHAMBER_INNER_ROOM"

return function(game)
  local ok, err = xpcall(function()
  if not F.boot(game) then return F.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local FieldView = require("src.core.game3.field_view")
  local BrailleField = require("src.core.game3.braille_field")
  local Field = require("src.core.game3.field")
  local Player = require("src.core.game3.player")
  local PartyMenu = require("src.ui.game3.party_menu")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local C = require("src.core.game3.constants").of("emerald")
  local fl = F.flags()
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_WAILORD"), 40)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 40)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_RELICANTH"), 40)
  session.party[2].moves = { C:require("moves", "MOVE_DIG") }
  session.party[2].pp = { 10 }
  session.party[2].maxPp = { 10 }
  fl.set("FLAG_SYS_BRAILLE_DIG", false)
  F.check(BrailleField.checkRelicanthWailord(session), "Wailord first and Relicanth last satisfies CheckRelicanthWailord")

  F.check(F.goTo(game, OUTER, 10, 3, "up"), "Sealed Chamber outer room loads")
  F.check(BrailleField.shouldDoDig(session), "digging at (10,3) under the braille is the dig puzzle spot")
  F.shot(game, "2610_before_dig_closed_wall.png", true)
  PartyMenu.show(session.party, nil, { session = session, slot = 2 })
  PartyMenu.cursor = 2
  U.tap(game, "a")
  local digIndex
  for i, label in ipairs(PartyMenu.ACTIONS or {}) do
    if label == "DIG" then digIndex = i end
  end
  if not F.check(digIndex ~= nil, "2610 party action menu offers DIG") then return end
  for _ = 1, 16 do
    if PartyMenu.actionCursor == digIndex then break end
    U.tap(game, "down")
  end
  U.tap(game, "a")
  if not F.check(PartyMenu.mode == "yesno", "2610 DIG retains the exit confirmation") then return end
  U.tap(game, "a")
  local sawMon, finished = false, false
  for _ = 1, 1200 do
    sawMon = sawMon or ShowMon.isActive()
    if not ShowMon.isActive() and not Warp.isBusy() and not Field.locked and not PartyMenu.isOpen() then
      finished = true
      break
    end
    U.wait(1)
  end
  F.check(sawMon, "2610 party DIG plays the mon field animation")
  F.check(finished, "2610 party DIG finishes and unlocks controls")
  if not F.check(session.map == OUTER and Player.cellX == 10 and Player.cellY == 3,
      "2610 puzzle DIG stays at the rear wall instead of escaping") then return end
  F.check(fl.get("FLAG_SYS_BRAILLE_DIG"), "FLAG_SYS_BRAILLE_DIG set")
  F.check(not BrailleField.shouldDoDig(session), "the dig spot is spent once opened")
  local function checkWall(tag, overrides)
    local layout = game.data.maps[OUTER].midLayout
    for row, vertical in ipairs({ "Top", "Bottom" }) do
      for column, horizontal in ipairs({ "Left", "Mid", "Right" }) do
        local x, y = column + 8, row
        local label = "METATILE_Cave_SealedChamberEntrance_" .. vertical .. horizontal
        local expected = C:require("metatile_labels", label)
        F.check(layout:midAt(x, y) == expected, tag .. " " .. vertical .. horizontal .. " uses the ROM entrance tile")
        if overrides then
          local ov = Field.metatileOverrideAt(OUTER, x, y)
          F.check(ov and ov.metatile == expected, tag .. " " .. vertical .. horizontal .. " written by DIG")
        end
        if row == 2 then
          F.check((layout:collAt(x, y) == 7) == (column ~= 2),
            tag .. " " .. horizontal .. " entrance collision")
        end
      end
    end
  end
  checkWall("2610 opened", true)
  F.check(not Field.locked and not Warp.isBusy(), "2610 DIG leaves the field unlocked and warp idle")
  F.shot(game, "2610_after_party_dig_open_wall.png", true)
  F.check(F.goTo(game, OUTER, 10, 3, "up", { keepScripts = true }), "2610 reloads the opened outer room")
  F.check(fl.get("FLAG_SYS_BRAILLE_DIG"), "2610 braille DIG flag survives map reload")
  checkWall("2610 reloaded", false)
  F.shot(game, "2610_reloaded_open_wall.png", true)

  local entered = S.exitTo(game, INNER, { tries = 2, goToTries = 4, settle = { limit = 1200 } })
  if not F.check(entered and session.map == INNER, "2610 walks through the opened entrance into the inner room") then return end
  F.shot(game, "2610_inner_room_arrived.png", true)
  if not F.check(S.goTo(game, { 10, 5 }, { tries = 4 }), "walks up to the inner chamber braille") then return end
  S.face(game, "up")
  U.tap(game, "a")
  local braille = false
  for _ = 1, 200 do
    if Space.vm and Space.vm:isRunning() then braille = true end
    if braille then break end
    U.wait(1)
  end
  F.check(braille, "A on the back wall runs the braille script")
  U.wait(20)
  if Message.isTyping() then Message.skipReveal() end
  F.shot(game, "2610_braille_back_wall.png", true)
  local maxPan, done = 0, false
  for _ = 1, 1500 do
    maxPan = math.max(maxPan, math.abs(FieldView.cameraPanY or 0))
    if fl.get("FLAG_REGI_DOORS_OPENED") and not (Space.vm and Space.vm:isRunning()) then done = true break end
    if maxPan > 0 and not F.shakeShot then
      F.shakeShot = true
      F.shot(game, "2610_chamber_shaking.png", true)
    end
    if (_ % 20) == 0 then U.tap(game, "a") else U.wait(1) end
  end
  F.check(maxPan >= 2, "DoSealedChamberShakingEffect shakes the camera (" .. maxPan .. ")")
  F.check(done, "FLAG_REGI_DOORS_OPENED set after the door-opened message")
  F.check((FieldView.cameraPanY or 0) == 0, "camera panning restored after the shakes")
  end, debug.traceback)
  if not ok then F.check(false, "driver error: " .. tostring(err)) end
  F.finish()
end
