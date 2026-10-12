local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_box_popup_2878"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS box_popup_2878")
    love.event.quit(0)
  else
    print("FAIL box_popup_2878 failures=" .. failures)
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
  storage.currentBox = 2
  for s = 1, 15 do storage.boxes[2].mons[s] = newMon("SPECIES_ZIGZAGOON", 10) end
  session.party = { newMon("SPECIES_KIRLIA", 20), newMon("SPECIES_TAILLOW", 12) }

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
  result(BoxStorageUI._pickBox == 1, version .. ": the first deposit chooser opens on BOX 1, not the current BOX 2 (BOX "
    .. tostring(BoxStorageUI._pickBox) .. ")")
  U.tap(game, "right")
  U.wait(20)
  result(BoxStorageUI._pickBox == 2, version .. ": right moves the chooser to BOX 2")
  if rs then
    local Kit = require("src.ui.game3.rse.scene_kit")
    local man = Kit.manifest("pokemon/storage")
    local sideImg = man and Kit.image(man.sprites.box_popup_sides.png)
    draws = {}
    recording = true
    for _ = 1, 2000 do
      if #draws >= 8 then break end
      U.wait(1)
    end
    recording = false
    local got = {}
    for _, d in ipairs(draws) do
      if d.img == sideImg and d.w == 8 then
        local key = d.x .. "," .. d.y .. "," .. d.h
        if not got[key] then got[key] = true; got[#got + 1] = key end
      end
    end
    local want = { "120,64,32", "120,96,16", "192,64,32", "192,96,16" }
    local ok = #got == 4
    for _, k in ipairs(want) do ok = ok and got[k] == true end
    result(ok, version .. ": popup side pieces at pret corners 120/192,64 (8x32) and 120/192,96 (8x16) (got "
      .. table.concat(got, " ") .. ")")
  end
  U.still(game, DIR .. "/2878_01_" .. version .. "_deposit_which_box.png")
  U.tap(game, "a")
  U.wait(30)
  local n2 = 0
  for i = 1, 30 do if storage.boxes[2].mons[i] then n2 = n2 + 1 end end
  result(n2 == 16 and #session.party == 1,
    version .. ": A in the chooser deposits into BOX 2 (box " .. n2 .. ", party " .. #session.party .. ")")

  BoxStorageUI.close()
  U.wait(20)
  love.graphics.draw = realDraw
  finish()
end
