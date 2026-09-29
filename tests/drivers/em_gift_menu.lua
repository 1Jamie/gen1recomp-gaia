local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_gift_menu"

return function(game)
  local failures = 0
  local function check(c, label)
    print((c and "PASS " or "FAIL ") .. label)
    if not c then failures = failures + 1 end
    return c
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " em_gift_menu failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local SaveData = require("src.core.SaveData")
  local Flags = require("src.core.game3.scripting.flags")
  local C = require("src.core.game3.constants").of("emerald")
  local save = SaveData.load()
  if not check(type(save) == "table" and save.engine == "game3", "the identity has an Emerald save") then return finish() end
  local store = Flags.newStore()
  Flags.loadInto(store, { flags = save.flags, vars = save.vars })
  Flags.setFlag(store, nil, C:require("flags", "FLAG_SYS_MYSTERY_GIFT_ENABLE"), true)
  local snap = Flags.serialize(store)
  save.flags, save.vars = snap.flags, snap.vars
  check(SaveData.save(save) ~= false, "FLAG_SYS_MYSTERY_GIFT_ENABLE written to the save")

  local Boot = require("src.ui.game3.boot")
  local function menu() return game.boot and game.boot.custom and game.boot.custom.menu end
  for _ = 1, 80 do
    if game.boot.phase == Boot.PHASE.MENU and menu() and menu().state == "input" then break end
    U.tap(game, "start")
    U.wait(20)
  end
  local m = menu()
  if not check(m ~= nil and m.state == "input", "the Emerald main menu is up") then return finish() end
  check(m.items[3] == "MYSTERY_GIFT", "the MYSTERY GIFT row shows once the questionnaire flag is set")
  U.shot(game, DIR .. "/01_main_menu.png")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "down")
  U.wait(4)
  check(m.cursor == 3, "cursor on MYSTERY GIFT")
  U.tap(game, "a")
  for _ = 1, 200 do
    if m.state == "mystery_gift" then break end
    U.wait(1)
  end
  if not check(m.state == "mystery_gift" and m.gift ~= nil, "MYSTERY GIFT opens the gift screen") then return finish() end
  U.wait(30)
  U.shot(game, DIR .. "/02_gift_menu.png")
  local MysteryGift = require("src.core.game3.mystery_gift")
  check(MysteryGift.familyOf(m.gift.session) == "rse", "the gift screen runs on the rse family")
  local st = m.gift
  local S = require("src.ui.game3.mystery_gift").STATE
  local pub = os.getenv("G3GIFT_TEST_PUBKEY")
  local function advance(pred, seconds)
    local deadline = love.timer.getTime() + (seconds or 10)
    while love.timer.getTime() < deadline do
      if pred() then return true end
      local msg = st.msg
      if msg and msg.revealed >= msg.total and not msg.auto and not msg.hold then U.tap(game, "a") else U.wait(1) end
    end
    return pred()
  end
  if pub and #pub == 64 then
    MysteryGift.GIFT_PUBKEY = pub
    U.tap(game, "a")
    check(advance(function() return st.state == S.SEARCHING end), "WONDER CARDS starts the fetch")
    check(advance(function() return st.state ~= S.SEARCHING end, 15) and st.state == S.OFFER_LIST,
      "the rse feed verified and listed, err=" .. tostring(st.lastError))
    local labels = {}
    for i, e in ipairs(st.offers or {}) do labels[i] = tostring(e.label) end
    print("[driver] rse card rows: " .. table.concat(labels, " | "))
    check(#labels == 3 and labels[1] == "AURORA TICKET" and labels[2] == "EON TICKET" and labels[3] == "OLD SEA MAP",
      "only the rse rows are offered (the FRLG MYSTIC TICKET is filtered out)")
    U.wait(10)
    U.shot(game, DIR .. "/03_rse_card_list.png")
    U.tap(game, "a")
    U.wait(10)
    U.shot(game, DIR .. "/04_rse_card_preview.png")
    U.tap(game, "a")
    check(advance(function() return st.state == S.MAIN_MENU and not st.msg end, 15), "the AURORA TICKET card is received and saved")
    local card = MysteryGift.getSavedCard(st.session)
    check(card and card.gift.setFlags[1] == C:require("flags", "FLAG_ENABLE_SHIP_BIRTH_ISLAND"),
      "the saved card carries Emerald's FLAG_ENABLE_SHIP_BIRTH_ISLAND")
    check(MysteryGift.ramScriptId(st.session) == "aurora", "and runs the ROM AURORA TICKET ramscript")
    local reloaded = SaveData.load()
    local rec = type(reloaded) == "table" and type(reloaded.modData) == "table" and reloaded.modData.mysteryGift
    check(rec and rec.card and rec.card.idNumber == card.idNumber, "the Wonder Card is written to the save")
  end
  for _ = 1, 40 do
    if menu() ~= m then break end
    U.tap(game, "b")
    U.wait(10)
  end
  check(menu() ~= m and game.boot.phase == Boot.PHASE.TITLE, "leaving the gift screen returns to the title screen")
  return finish()
end
