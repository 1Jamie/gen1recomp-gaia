#!/usr/bin/env luajit
-- Menu usage scenario: start menu -> save flow end to end, plus both cancel
-- paths.  Every menu opened here is closed before the next section, because
-- StartMenu/SaveMenu/Stack are process-wide singletons.
--
-- pret citations actually read for this suite:
--   pokefirered/src/start_menu.c:43-49   STARTMENU_POKEDEX..STARTMENU_EXIT order
--   pokefirered/src/start_menu.c:113-123 item label/callback table
--   pokefirered/src/start_menu.c:213-223 SetUpStartMenu_NormalField append order
--   pokefirered/src/start_menu.c:215     POKéDEX gated on FLAG_SYS_POKEDEX_GET
--   pokefirered/src/start_menu.c:217-218 POKéMON gated on FLAG_SYS_POKEMON_GET
--   pokefirered/src/start_menu.c:1003-1005 CloseStartMenu plays SE_SELECT
--   pokefirered/src/menu.c:276           cursor out of range clamps to 0
--   pokefirered/src/menu.c:376           A press plays SE_SELECT (the NO path's se)
--   pokefirered/src/menu.c:381           B press returns MENU_B_PRESSED (back-out)
--
-- Engine quirks designed around (NOT fixed here):
--   do_save reads Runtime._game.saveGame and must get a truthy confirm
--   (tests/engine/game3_save_menu_failure_test.lua), so this suite supplies
--   the same stub saveGame the real game carries (cf.
--   tests/game3_save_trainer_card_test.lua:91-92).
--   (The former "gap 1: POKéMON entry has no flag gate" is now implemented —
--   start_menu.lua gates it on 0x828 exactly as start_menu.c:217-218 does.)

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Stack = require("src.ui.game3.stack")
local StartMenu = require("src.ui.game3.start_menu")
local SaveMenu = require("src.ui.game3.save_menu")
local Flags = require("src.core.game3.scripting.flags")
local Runtime = require("src.core.game3.runtime")

-- do_save (save_menu.lua:94-133) reads Runtime._game, not SaveMenu._game.
-- _mod stays nil so the sidecar persist branch is skipped.
local saveCalls = 0
Runtime._game = { saveGame = function() saveCalls = saveCalls + 1 return true end }
Runtime._mod = nil

local session = {
  name = "RED",
  party = { { species = 25, level = 5, hp = 20, maxHp = 20 } },
}

local function ids()
  local out = {}
  for _, e in ipairs(StartMenu.ENTRIES) do out[#out + 1] = e.id end
  return table.concat(out, ",")
end

print("[test] 1. The start menu opens with the FRLG entry list")
StartMenu.show({ session = session })
check(StartMenu.isOpen() == true, "the start menu is open")
check(Stack.top() ~= nil and Stack.top().id == "start", "the start menu owns the top of the stack")
check(Stack.depth() == 1, "exactly one layer on the stack")
-- No flag store loaded -> the dex gate defaults open (start_menu.lua:26-35).
check(#StartMenu.ENTRIES == 7, "seven entries with no store loaded")
check(ids() == "pokedex,pokemon,bag,trainer,save,option,exit",
  "entry ids follow pret start_menu.c:43-49 / 113-123 order")
check(StartMenu.ENTRIES[4].label == "RED", "the PLAYER entry shows the session name")
check(StartMenu.cursor == 1, "cursor starts on POKéDEX")
StartMenu.close()
check(StartMenu.isOpen() == false and Stack.depth() == 0, "close() unwinds the layer")

print("[test] 2. Both entry gates follow their retail flags (0x829 / 0x828)")
local spaceMod = package.loaded["src.core.game3.scripting.space"]
local store = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = store }
check(Flags.getFlag(store, nil, 0x829) == false, "fresh store: the dex flag is clear")
check(Flags.getFlag(store, nil, 0x828) == false, "fresh store: the POKéMON flag is clear")
StartMenu.show({ session = session })
check(#StartMenu.ENTRIES == 5,
  "neither gated entry while both flags are clear (start_menu.c:214-218)")
check(StartMenu.ENTRIES[1].id == "bag", "BAG leads when both gates are shut")
StartMenu.close()
Flags.setFlag(store, nil, 0x829, true)
StartMenu.show({ session = session })
check(#StartMenu.ENTRIES == 6, "the POKéDEX entry returns once the flag is set (start_menu.c:215)")
check(StartMenu.ENTRIES[1].id == "pokedex", "and it leads the list (start_menu.c:216)")
StartMenu.close()
Flags.setFlag(store, nil, 0x828, true)
StartMenu.show({ session = session })
check(#StartMenu.ENTRIES == 7,
  "the POKéMON entry returns once FLAG_SYS_POKEMON_GET (0x828) is set (start_menu.c:217-218)")
check(StartMenu.ENTRIES[2].id == "pokemon", "it sits between POKéDEX and BAG (start_menu.c:218)")
StartMenu.close()
package.loaded["src.core.game3.scripting.space"] = spaceMod -- restore default

print("[test] 3. The cursor wraps the list (menu.c:276 clamp, modulo wrap)")
StartMenu.show({ session = session })
check(#StartMenu.ENTRIES == 7, "gate back to its default: dex shown, seven entries")
StartMenu.move(-1)
check(StartMenu.cursor == 7, "up from the top wraps to EXIT")
StartMenu.move(-1)
check(StartMenu.cursor == 6, "up again lands on OPTION")
StartMenu.move(1)
check(StartMenu.cursor == 7, "down wraps EXIT around to the top")
StartMenu.move(1)
check(StartMenu.cursor == 1, "and the list wraps back to POKéDEX")
for _ = 1, 4 do StartMenu.move(1) end
check(StartMenu.cursor == 5 and StartMenu.ENTRIES[5].id == "save",
  "four downs put the cursor on SAVE")

print("[test] 4. Confirming SAVE runs the YES/YES dialog and unwinds both menus")
local savesBefore = saveCalls
StartMenu.confirm() -- dispatch: id == "save" -> SaveMenu.show (start_menu.lua:151-153)
check(SaveMenu.isOpen() == true, "the save dialog opened over the start menu")
check(SaveMenu._phase == "confirm", "it asks 'Would you like to SAVE the game?' first")
check(SaveMenu.cursor == 1, "YES is preselected")
check(Stack.depth() == 2 and Stack.top().id == "save", "the save layer sits above the start layer")
check(Stack.has("start") == true and StartMenu.isOpen() == true,
  "the start menu stays open beneath (input goes to Stack.top().mod)")
-- Input routes to the top layer, so drive SaveMenu directly from here.
SaveMenu.confirm()
check(SaveMenu._phase == "overwrite", "YES advances to the overwrite confirm")
SaveMenu.confirm()
check(SaveMenu._phase == "saved", "the second YES writes and reports saved")
check(saveCalls == savesBefore + 1, "exactly one saveGame call happened")
SaveMenu.confirm() -- A on "[Player] saved the game."
check(SaveMenu.isOpen() == false, "the dialog closes")
check(StartMenu.isOpen() == false, "and takes the start menu with it (start_menu.c:583 path)")
check(Stack.depth() == 0, "the stack unwound to empty")
check(saveCalls == savesBefore + 1, "the dismissal itself saved nothing more")

print("[test] 5. NO closes the dialog without writing; cancel closes the menu")
local savesNow = saveCalls
StartMenu.resetCursor()
StartMenu.show({ session = session })
for _ = 1, 4 do StartMenu.move(1) end -- back down to SAVE
check(StartMenu.ENTRIES[StartMenu.cursor].id == "save", "cursor back on SAVE")
StartMenu.confirm()
check(SaveMenu.isOpen() == true and SaveMenu._phase == "confirm", "the save dialog reopened")
SaveMenu.move(1)
check(SaveMenu.cursor == 2, "cursor flips to NO")
SaveMenu.confirm() -- A press on NO (menu.c:376 plays SE_SELECT) -> SaveMenu.close()
check(SaveMenu.isOpen() == false, "NO closes the save dialog")
check(saveCalls == savesNow, "and nothing was written")
check(StartMenu.isOpen() == true and Stack.depth() == 1, "the start menu is still up beneath")
StartMenu.cancel() -- B on the list closes the menu (menu.c:381 back-out)
check(StartMenu.isOpen() == false, "cancel closes the start menu")
check(Stack.depth() == 0, "the stack is empty again")

print("[test] 6. The EXIT entry asks first; B backs out instead of quitting")
StartMenu.resetCursor()
StartMenu.show({ session = session })
for _ = 1, 6 do StartMenu.move(1) end
check(StartMenu.ENTRIES[StartMenu.cursor].id == "exit", "cursor on EXIT")
StartMenu.confirm()
check(StartMenu._confirmExit == true, "confirm opens the RETURN TO MAIN MENU? prompt")
check(StartMenu.isOpen() == true, "the menu has not closed yet")
StartMenu.move(1)
check(StartMenu._confirmCursor == 1, "inside the prompt, move flips the YES/NO choice")
StartMenu.cancel()
check(StartMenu._confirmExit == false and StartMenu.isOpen() == true,
  "B dismisses the prompt first (menu.c:381) instead of closing")
StartMenu.cancel()
check(StartMenu.isOpen() == false, "a second cancel closes the menu")
check(Stack.depth() == 0, "nothing left on the stack")
check(saveCalls == savesNow, "no stray save happened along the way")

finish()
