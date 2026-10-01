package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local session, pending, puzzleChecks, effects, escapes, respawn
local player = { cellX = 10, cellY = 3, facing = "down" }
package.loaded["src.core.game3.player"] = player
package.loaded["src.mods.Runtime"] = {}
package.loaded["src.core.game3.rom_text"] = {}
package.loaded["src.ui.game3.message"] = {}
package.loaded["src.core.game3.audio"] = {}
package.loaded["src.core.game3.field_effects"] = {}
package.loaded["src.core.game3.objects"] = {}
package.loaded["src.core.game3.field_modules"] = { enabled = function() return false end }
package.loaded["src.core.game3.rse.init"] = {
  session = function() return session end,
  flag = function(_, s) return (s or session).opened == true end,
}
package.loaded["src.core.game3.field_move_show_mon"] = {
  start = function(mon, _, done)
    T.eq(mon, session.party[1], "DIG passes its party mon to the show-mon effect")
    pending = done
  end,
}
package.loaded["src.core.game3.warp"] = {
  startEscapeRope = function(game, map, x, y, done)
    escapes[#escapes + 1] = { game = game, map = map, x = x, y = y, done = done }
  end,
}

local BrailleField = require("src.core.game3.braille_field")
local realPredicate = BrailleField.shouldDoDig
BrailleField.shouldDoDig = function(s)
  puzzleChecks = puzzleChecks + 1
  return realPredicate(s)
end
BrailleField.doDig = function(s)
  effects = effects + 1
  T.eq(s, session, "braille effect receives the active session")
  s.opened = true
end
local Field = require("src.core.game3.field")
Field.respawnAtHeal = function(payload) respawn = payload end
local destination = { map = "EM_ROUTE134", x = 12, y = 9 }

local function run(case)
  pending, puzzleChecks, effects, escapes, respawn = nil, 0, 0, {}, nil
  session = { version = case.version or "emerald", map = case.map or "EM_SEALED_CHAMBER_OUTER_ROOM",
    opened = case.opened, x = case.x or 10, y = case.y or 3, party = { { species = 1 } },
    healMap = "EM_LITTLEROOT_TOWN" }
  player.cellX, player.cellY, player.facing = session.x, session.y, case.facing or "down"
  Field._session, Field._game, Field._locks = session, { session = session }, {}
  Field._fieldCallback, Field._flyLanding, Field._fallWarp = nil, nil, nil
  if case.namedLock then Field.lock("script") end
  Field.executeFieldMove({ action = "dig", mon = session.party[1], warp = destination })
  T.check(Field.locked, case.name .. " locks during show-mon")
  T.eq(puzzleChecks, 0, case.name .. " does not inspect puzzle before show-mon completes")
  T.eq(effects, 0, case.name .. " does not open wall before show-mon completes")
  T.eq(#escapes, 0, case.name .. " does not escape before show-mon completes")
  T.check(type(pending) == "function", case.name .. " registers a show-mon completion callback")
  pending()
  T.eq(puzzleChecks, session.version == "emerald" and 1 or 0,
    case.name .. " only Emerald checks the braille predicate")
  T.eq(effects, case.puzzle and 1 or 0, case.name .. " selects the correct braille effect count")
  T.eq(#escapes, case.puzzle and 0 or 1, case.name .. " selects the correct escape effect count")
  if case.puzzle then
    T.eq(session.opened, true, case.name .. " marks the chamber open")
    T.eq(Field._locks.default, nil, case.name .. " releases the DIG field lock")
    T.eq(Field.locked, case.namedLock == true, case.name .. " preserves independent named locks")
    T.eq(session.map, "EM_SEALED_CHAMBER_OUTER_ROOM", case.name .. " stays in the chamber")
  else
    local warp = escapes[1]
    T.eq(warp and warp.game, Field._game, case.name .. " passes the active game to escape")
    T.eq(warp and warp.map, destination.map, case.name .. " keeps the ordinary escape map")
    T.eq(warp and warp.x, destination.x, case.name .. " keeps the ordinary escape column")
    T.eq(warp and warp.y, destination.y, case.name .. " keeps the ordinary escape row")
    if warp then warp.done(warp.map, warp.x, warp.y) end
    T.same(respawn, { fieldMove = true, warp = destination }, case.name .. " forwards escape completion")
  end
end

run({ name = "left puzzle column facing down", x = 9, puzzle = true })
run({ name = "center puzzle column facing left", x = 10, facing = "left", puzzle = true })
run({ name = "right puzzle column with named script lock", x = 11, namedLock = true, puzzle = true })
run({ name = "wrong column", x = 8 })
run({ name = "wrong row", y = 4 })
run({ name = "wrong map", map = "EM_GRANITE_CAVE_1F" })
run({ name = "already open chamber", opened = true })
run({ name = "FireRed at a would-be puzzle spot", version = "firered" })

T.finish("game3_braille_dig_test")
