local Board = require("src.online.union.Board")
local Dialog = require("src.ui.gen2.union.Dialog")
local Participant = require("src.online.union.Participant")
local Strings = require("src.core.Strings")
local Text = require("src.ui.gen2.union.Text")

local UI = {}

UI.GEN = 2
UI.DEX_MAX = 251
UI.TITLE = Strings.source("TRADING BOARD")
UI.LABELS = { Strings.source("REGISTER"), Strings.source("INFO"), Strings.source("EXIT") }
UI.CANCEL = Strings.source("CANCEL")

local S = Board.S
UI.S = S

local function say(key, ...)
  local n = select("#", ...)
  local args = { ... }
  for i = 1, n do args[i] = Text.clean(args[i]) end
  return Strings(S[key], unpack(args, 1, n))
end
UI.say = say

local function inParty(game, mon)
  for _, m in ipairs(game.save and game.save.party or {}) do
    if m == mon then return true end
  end
  return false
end

function UI.clear(session)
  if not session.boardEntry then return end
  session.boardEntry = nil
  if session.state == "joined" then session.room:setBoard(false) end
end

function UI.settle(session)
  local e = session.boardEntry
  if e and not inParty(session.game, e.mon) then UI.clear(session) end
end

local function open(session)
  if session.state ~= "joined" then
    session:uiOpen("board")
    Dialog.say(session.game, Text.error(session.err or "offline"), function() session:uiDone() end)
    return nil
  end
  UI.settle(session)
  session:uiOpen("board")
  return function() session:uiDone() end
end

local function popIf(game, state)
  if state and game.stack:top() == state then game.stack:pop() end
end

function UI.pickType(game, onPick)
  local List = require("src.ui.gen2.union.List")
  local items = {}
  for i, name in ipairs(Board.types(UI.GEN)) do
    items[i] = { label = Board.typeLabel(game.data, name, UI.GEN), value = name }
  end
  items[#items + 1] = { label = Strings(UI.CANCEL), value = false }
  local list = List.new(game, UI.TITLE, items, function(item) onPick(item and item.value or nil) end)
  game.stack:push(list)
  return list
end

-- pokefirered/src/union_room.c:3320
function UI.register(session, finish)
  local game = session.game
  local function cancel() Dialog.say(game, say("canceled"), finish) end
  Dialog.say(game, say("whichMon"), function()
    local PartyMenu = require("src.ui.gen2.PartyMenu")
    local menu
    menu = PartyMenu.new(game, {
      onCancel = function()
        popIf(game, menu)
        cancel()
      end,
      onChoose = function(_, mon)
        if Board.isEgg(mon) then
          Dialog.sfx(game, "Sfx_Wrong")
          return
        end
        popIf(game, menu)
        Dialog.say(game, say("chooseType"), function()
          UI.pickType(game, function(typeName)
            local entry = typeName and Board.entry(Board.national(game.data, mon), mon.level, typeName)
            if not entry then return cancel() end
            session.room:setBoard(entry)
            session.boardEntry = { mon = mon, board = entry }
            Dialog.say(game, say("completed"), finish)
          end)
        end)
      end,
    })
    game.stack:push(menu)
  end)
end

-- pokefirered/src/union_room.c:3264
function UI.attendant(session)
  local finish = open(session)
  if not finish then return end
  local game = session.game
  Dialog.sfx(game, "Sfx_ReadText2")
  local e = session.boardEntry
  if e then
    local name = Board.speciesName(game.data, e.board.species)
    Dialog.ask(game, say("cancelReg", tostring(e.board.level), name), function(yes)
      if not yes then return finish() end
      UI.clear(session)
      Dialog.say(game, say("canceled2"), finish)
    end)
    return
  end
  local function menu(text)
    Dialog.menu(game, text, UI.LABELS, function(i)
      if i == 1 then return UI.register(session, finish) end
      if i == 2 then return menu(say("info")) end
      finish()
    end)
  end
  menu(say("welcome"))
end

function UI.items(session)
  local items = {}
  for _, o in ipairs(Board.offers(session.room, UI.DEX_MAX)) do
    items[#items + 1] = { label = Board.speciesName(session.game.data, o.species),
                          right = Strings("Lv%d", o.level), value = o }
  end
  items[#items + 1] = { label = Strings(UI.CANCEL), value = false }
  return items
end

-- pokefirered/src/union_room.c:3373
function UI.check(session)
  local finish = open(session)
  if not finish then return end
  local game = session.game
  local player = game.save and game.save.player or {}
  local function board()
    local List = require("src.ui.gen2.union.List")
    game.stack:push(List.new(game, UI.TITLE, UI.items(session), function(item)
      local o = item and item.value
      if not o then return finish() end
      UI.pick(session, o, board, finish)
    end))
  end
  Dialog.sfx(game, "Sfx_ReadText2")
  Dialog.say(game, say("checked", player.name), board)
end

-- pokefirered/src/union_room.c:3404
function UI.pick(session, o, reopen, finish)
  local game = session.game
  local p = session.room:member(o.p.id) or o.p
  local types = Board.partyTypes(game.data, game.save and game.save.party, UI.GEN)
  if not Board.hasType(types, o.typeName) then
    Dialog.say(game, say("noType", Board.typeLabel(game.data, o.typeName, UI.GEN), p.name), reopen)
    return
  end
  Dialog.ask(game, say("askTrade", p.name), function(yes)
    if not yes then return finish() end
    if Participant.busy(p) then
      Dialog.say(game, Text.say("busy", p.name), finish)
      return
    end
    session:uiDone()
    session:uiOpen("talk")
    require("src.ui.gen2.union.Talk").invite(session, p, "xg_trade")
  end)
end

return UI
