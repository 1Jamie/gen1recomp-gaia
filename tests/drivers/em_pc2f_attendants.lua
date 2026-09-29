local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local CENTER_2F = "EM_OLDALE_TOWN_POKEMON_CENTER_2F"

return function(game)
  local d = S.new("em_pc2f_attendants", "/tmp/em_pc2f_attendants")
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

  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Family = require("src.core.game3.link.family")
  local Records = require("src.ui.game3.rse.frontier_records")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  local function settle()
    for _ = 1, 400 do
      if not (Message.isOpen() or Choice.active or Records.isOpen() or S.vmRunning()) then return true end
      if Choice.active then U.tap(game, "b") else U.tap(game, "a") end
      U.wait(4)
    end
    return false
  end
  local function talk(x, y, label)
    settle()
    local before = #d.started
    place(x, y, "up")
    U.wait(12)
    U.tap(game, "a")
    local opened = false
    for _ = 1, 120 do
      if Message.isOpen() or Choice.active or Records.isOpen() then opened = true break end
      U.wait(1)
    end
    d.note(label .. " ran " .. table.concat(d.started, ",", before + 1))
    return opened
  end

  -- pokeemerald/data/scripts/cable_club.inc:104
  Flags.setVar(Space.store, ctx(), Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
  Map.load(nil, game, CENTER_2F, { x = 12, y = 5, facing = "up" })
  U.wait(60)
  Flags.setFlag(Space.store, ctx(), Family.flag("emerald", "FLAG_SYS_POKEDEX_GET"), true)
  d.shot(game, "first_frame")

  local drawn = 0
  local origDraw = Records.drawWindow
  Records.drawWindow = function(...)
    drawn = drawn + 1
    return origDraw(...)
  end

  -- pokeemerald/src/field_control_avatar.c:405
  check(talk(12, 5, "cable box"), "the right-hand cable box opens the battle records")
  U.wait(20)
  d.shot(game, "cable_box_records")
  check(drawn > 0, "the battle records window is drawn on the field (" .. drawn .. ")")
  check(Records.isOpen(), "the records window waits for a button")
  U.tap(game, "a")
  U.wait(20)
  check(not Records.isOpen() and not S.vmRunning(), "A closes the records window and releases")

  -- pokeemerald/src/field_control_avatar.c:403
  check(talk(8, 5, "wireless box"), "the middle wireless box responds")
  check(settle(), "the wireless box releases")
  -- pokeemerald/src/field_control_avatar.c:373
  check(talk(3, 4, "pc"), "the left PC boots")
  for _ = 1, 30 do
    U.tap(game, "b")
    U.wait(3)
  end
  check(settle(), "the PC releases")

  for _, x in ipairs({ 10, 6, 2 }) do
    check(talk(x, 4, "attendant " .. x), "the attendant at x=" .. x .. " responds")
    check(settle(), "the attendant at x=" .. x .. " releases")
  end
  d.shot(game, "done")
  Records.drawWindow = origDraw
  return d.finish()
end
