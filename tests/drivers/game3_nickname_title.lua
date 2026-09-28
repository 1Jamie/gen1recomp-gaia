local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_nickname_title"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_nickname_title")
    love.event.quit(0)
  else
    print("FAIL game3_nickname_title failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  local ok, err = xpcall(function()
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
    U.wait(240)

    local Runtime = require("src.core.game3.runtime")
    local Party = require("src.core.game3.party")
    local Pokemon = require("src.core.game3.pokemon")
    local Space = require("src.core.game3.scripting.space")
    local Natives = require("src.core.game3.scripting.natives")
    local Naming = require("src.ui.game3.naming")
    local C = require("src.core.game3.constants").of(Runtime.getSession().version)

    local session = Runtime.getSession()
    if not result(session ~= nil and Space.vm ~= nil, "field session with a script VM") then return end
    local species = C:require("species", "SPECIES_MUDKIP")
    session.party = {}
    Party.giveMonToPlayer(session, species, 5)
    local sname = Pokemon.name(species)

    Space.vm.ctx.stringVars = Space.vm.ctx.stringVars or {}
    Space.vm.ctx.stringVars[1] = sname
    local ctx = { session = session, specialVars = { [0x8004] = 0 }, stringVars = { sname } }
    Natives.special(ctx, C:special("ChangePokemonNickname"), Space.vm.adapters)
    for _ = 1, 120 do
      if Naming.isOpen() then break end
      U.wait(1)
    end
    if not result(Naming.isOpen(), "ChangePokemonNickname opened the naming screen") then return end
    U.wait(60)
    local st = Naming._state
    U.shot(game, DIR .. "/nickname_title_" .. tostring(session.version) .. ".png")
    print("[driver] title=" .. tostring(st.title) .. " entry=" .. tostring(st.name))
    result(st.title == sname .. "'s nickname?", "title is the species name once plus 's nickname? (" .. tostring(st.title) .. ")")
    result(st.name == "", "entry field starts empty")
    Naming.close(nil)
    U.wait(30)
  end, debug.traceback)
  if not ok then result(false, "driver error: " .. tostring(err)) end
  finish()
end
