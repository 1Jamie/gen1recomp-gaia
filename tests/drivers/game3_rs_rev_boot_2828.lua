local U = require("tests.drivers.util")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. "rev2828 " .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "rev2828 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "REV" })
  U.wait(240)
  local session = require("src.core.game3.runtime").getSession()
  if not check(session ~= nil, "field_session_ready") then return finish() end
  local Space = require("src.core.game3.scripting.space")
  print("rev2828 version=" .. tostring(session.version) .. " map=" .. tostring(session.map))
  check(session.version == "ruby" or session.version == "sapphire", "version_is_rs")
  check(session.map == "SA_INSIDE_OF_TRUCK" or session.map == "RU_INSIDE_OF_TRUCK", "new_game_starts_in_truck")
  local Flags = require("src.core.game3.scripting.flags")
  local C = require("src.core.game3.constants").of(session.version)
  check(C:require("flags", "FLAG_SYS_POKEDEX_GET") ~= nil, "constants_loaded")
  check(Flags.getFlag(Space.store, nil, C:require("flags", "FLAG_SYS_POKEDEX_GET")) == false, "fresh_game_no_dex")
  local shots = os.getenv("POKEPORT_SHOT_DIR")
  if shots then U.still(game, shots .. "/2828_overworld_" .. tostring(session.version) .. ".png") end
  finish()
end
