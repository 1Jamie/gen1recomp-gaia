local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_link_records", "/tmp/em_link_records")
  local check = d.check

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return d.finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has a save") then return d.finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)
  session = require("src.core.game3.runtime").getSession()

  local Space = require("src.core.game3.scripting.space")
  local Win = require("src.ui.game3.rse.frontier_records")
  local function open(label)
    check(Space.startScript("EventScript_CableBoxResults") ~= false, label .. " script started")
    U.wait(30)
    check(Win.isOpen(), label .. " window open")
    d.shot(game, label)
    U.wait(60)
    check(Win.isOpen(), label .. " window still open after 60 frames")
    U.tap(game, "a")
    U.wait(30)
    check(not Win.isOpen(), label .. " window closed after A")
    S.settle(game)
  end
  session.linkBattleRecords = {}
  open("empty")
  session.linkBattleRecords = { { name = "MAY", wins = 3, losses = 1, draws = 0 } }
  session.gameStats = session.gameStats or {}
  session.gameStats[23], session.gameStats[24] = 3, 1
  open("one_record")
  return d.finish()
end
