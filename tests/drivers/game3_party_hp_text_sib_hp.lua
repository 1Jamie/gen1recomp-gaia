local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_party_hp_text_sib_hp"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. "sib-hp " .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "sib-hp failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local CASES = {
  { level = 16, hp = 46, maxHp = 46 },
  { level = 100, hp = 7, maxHp = 341 },
  { level = 5, hp = 0, maxHp = 19 },
  { level = 100, hp = 999, maxHp = 999 },
  { level = 40, hp = 23, maxHp = 120 },
  { level = 3, hp = 10, maxHp = 12 },
}

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "HP", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local PartyMenu = require("src.ui.game3.party_menu")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field_session_ready") then return finish() end
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end

  local version = session.version
  session.party = {}
  for _, c in ipairs(CASES) do
    Party.giveMon(session, 2, c.level)
    local mon = session.party[#session.party]
    mon.hp, mon.maxHp, mon.status = c.hp, c.maxHp, nil
  end
  check(#session.party == #CASES, "party_filled")

  PartyMenu.show(session.party, session.move_overlay, {})
  U.wait(40)
  check(PartyMenu.open == true, "party_menu_open")
  U.still(game, DIR .. "/sib-hp_01_party_hp_values_" .. tostring(version) .. ".png")
  finish()
end
