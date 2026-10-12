local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_choose_box"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS choose_box")
    love.event.quit(0)
  else
    print("FAIL choose_box failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local BoxStorageUI = require("src.ui.game3.box_storage_ui")
  local PcChrome = require("src.ui.game3.pc_chrome")
  local version = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(version)
  local rs = version == "ruby" or version == "sapphire"

  local session = Runtime.getSession()
  if not result(session ~= nil, version .. ": new game reached the game3 field") then return finish() end

  local function newMon(name, level)
    session.party = {}
    local _, _, mon = Party.giveMon(session, C:require("species", name), level)
    session.party = {}
    return mon
  end
  local storage = Storage.ensure(session)
  storage.currentBox = 5
  for s = 1, 15 do storage.boxes[2].mons[s] = newMon("SPECIES_PIDGEY", 10) end
  for s = 1, 30 do storage.boxes[3].mons[s] = newMon("SPECIES_RATTATA", 10) end
  session.party = { newMon("SPECIES_PIKACHU", 20), newMon("SPECIES_SPEAROW", 12), newMon("SPECIES_ODDISH", 9) }

  local draws, recording = {}, false
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img, a, b, c, ...)
    if recording and type(a) == "userdata" and a.typeOf and a:typeOf("Quad") then
      local _, _, qw, qh = a:getViewport()
      draws[#draws + 1] = { img = img, x = b, y = c, w = qw, h = qh }
    end
    return realDraw(img, a, b, c, ...)
  end

  BoxStorageUI.show({ session = session, subMode = "deposit" })
  U.wait(90)
  U.tap(game, "a")
  U.wait(20)
  result(BoxStorageUI.mode == "action_menu", version .. ": A on party mon opens the action menu (mode " .. tostring(BoxStorageUI.mode) .. ")")
  U.tap(game, "a")
  U.wait(20)
  result(BoxStorageUI.mode == "pick_box", version .. ": STORE opens Deposit in which BOX? (mode " .. tostring(BoxStorageUI.mode) .. ")")
  result(BoxStorageUI._pickBox == 1, version .. ": the chooser opens on BOX 1 (got " .. tostring(BoxStorageUI._pickBox) .. ")")
  result(#session.party == 3, version .. ": nothing is stored before a box is chosen")

  draws, recording = {}, true
  for _ = 1, 600 do
    if #draws >= 8 then break end
    U.wait(1)
  end
  recording = false
  local got = {}
  local sidesImg = PcChrome._chooseBoxSidesImg
  if rs then
    local Kit = require("src.ui.game3.rse.scene_kit")
    sidesImg = Kit.image(Kit.manifest("pokemon/storage").sprites.box_popup_sides.png)
  end
  for _, d in ipairs(draws) do
    if d.img == sidesImg and d.w == 8 then
      local key = d.x .. "," .. d.y .. "," .. d.h
      if not got[key] then got[key] = true; got[#got + 1] = key end
    end
  end
  local ok = #got == 4
  for _, k in ipairs({ "120,64,32", "120,96,16", "192,64,32", "192,96,16" }) do ok = ok and got[k] == true end
  result(ok, version .. ": chooser side pieces at pret corners (got " .. table.concat(got, " ") .. ")")
  U.still(game, DIR .. "/cw_01_" .. version .. "_deposit_which_box_box1.png")

  U.tap(game, "right")
  U.wait(20)
  result(BoxStorageUI._pickBox == 2, version .. ": right moves the chooser to BOX 2")
  U.still(game, DIR .. "/cw_02_" .. version .. "_chooser_box2_15.png")
  U.tap(game, "a")
  U.wait(60)
  local n2 = 0
  for i = 1, 30 do if storage.boxes[2].mons[i] then n2 = n2 + 1 end end
  result(n2 == 16 and #session.party == 2, version .. ": A stores the mon into BOX 2 (box " .. n2 .. ", party " .. #session.party .. ")")

  BoxStorageUI.partyCursor = 1
  U.tap(game, "a")
  U.wait(20)
  U.tap(game, "a")
  U.wait(20)
  result(BoxStorageUI.mode == "pick_box" and BoxStorageUI._pickBox == 2,
    version .. ": the next deposit opens on the last box used (BOX " .. tostring(BoxStorageUI._pickBox) .. ")")
  U.tap(game, "right")
  U.wait(20)
  U.tap(game, "a")
  U.wait(20)
  result(BoxStorageUI.mode == "deposit_box_full", version .. ": BOX 3 at 30/30 says the box is full")
  U.still(game, DIR .. "/cw_03_" .. version .. "_box_full.png")
  U.tap(game, "a")
  U.wait(20)
  result(BoxStorageUI.mode == "pick_box", version .. ": the full message returns to the chooser")
  U.tap(game, "b")
  U.wait(20)
  result(BoxStorageUI.mode == "party_drawer" and #session.party == 2, version .. ": B cancels without storing")

  U.tap(game, "a")
  U.wait(20)
  U.tap(game, "a")
  U.wait(20)
  local wantBox = rs and 3 or 2
  result(BoxStorageUI.mode == "pick_box" and BoxStorageUI._pickBox == wantBox,
    version .. ": after a full box and cancel the chooser opens on BOX " .. wantBox
    .. " (BOX " .. tostring(BoxStorageUI._pickBox) .. ")")
  U.still(game, DIR .. "/cw_04_" .. version .. "_chooser_after_full_cancel.png")
  U.tap(game, "b")
  U.wait(20)

  BoxStorageUI.close()
  U.wait(20)
  BoxStorageUI.show({ session = session, subMode = "deposit" })
  U.wait(90)
  BoxStorageUI.partyCursor = 1
  U.tap(game, "a")
  U.wait(20)
  U.tap(game, "a")
  U.wait(20)
  result(BoxStorageUI.mode == "pick_box" and BoxStorageUI._pickBox == 1,
    version .. ": reopening the PC starts the chooser on BOX 1 (BOX " .. tostring(BoxStorageUI._pickBox) .. ")")
  U.tap(game, "b")
  U.wait(20)

  BoxStorageUI.close()
  U.wait(20)
  love.graphics.draw = realDraw
  finish()
end
