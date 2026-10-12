local Board = require("src.online.union.Board")
local Dialog = require("src.ui.union.gen1.Dialog")
local Strings = require("src.core.Strings")
local Text = require("src.ui.union.gen1.Text")

local UI = {}

UI.DEX_MAX = 151
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

UI.GEN = 1

function UI.national(data, mon) return Board.national(data, mon) end
function UI.speciesName(data, national) return Board.speciesName(data, national) end
function UI.typeLabel(data, name) return Board.typeLabel(data, name, UI.GEN) end

local function inParty(game, mon)
  for _, m in ipairs(game.save and game.save.party or {}) do
    if m == mon then return true end
  end
  return false
end

function UI.clear(presence)
  if not presence.boardEntry then return end
  presence.boardEntry = nil
  if presence.state == "joined" then presence.room:setBoard(false) end
end

function UI.settle(game, presence)
  local e = presence.boardEntry
  if e and not inParty(game, e.mon) then UI.clear(presence) end
end

local function open(game, presence, done)
  if presence.state ~= "joined" then
    Dialog.say(game, Text.error(presence.offlineCode or "offline"), done)
    return nil
  end
  UI.settle(game, presence)
  presence:setBusy(true)
  return function()
    presence:setBusy(false)
    if done then done() end
  end
end

function UI.pickType(game, onPick)
  local ListMenu = require("src.ui.ListMenu")
  local items = {}
  for i, name in ipairs(Board.types(UI.GEN)) do
    items[i] = { label = UI.typeLabel(game.data, name), value = name }
  end
  items[#items + 1] = { label = Strings(UI.CANCEL), value = false }
  local list
  list = ListMenu.new(game, Strings(UI.TITLE), items, {
    onChoose = function(item)
      list:close()
      onPick(item and item.value or nil)
    end,
    onCancel = function() onPick(nil) end,
  })
  game.stack:push(list)
  return list
end

-- pokefirered/src/union_room.c:3320
function UI.register(game, presence, finish)
  local function cancel() Dialog.say(game, say("canceled"), finish) end
  Dialog.say(game, say("whichMon"), function()
    local PartyMenu = require("src.ui.PartyMenu")
    game.stack:push(PartyMenu.new(game, {
      pickOnly = true,
      onCancel = cancel,
      onSwitch = function(mon)
        Dialog.say(game, say("chooseType"), function()
          UI.pickType(game, function(typeName)
            local entry = typeName and Board.entry(UI.national(game.data, mon), mon.level, typeName)
            if not entry then return cancel() end
            presence.room:setBoard(entry)
            presence.boardEntry = { mon = mon, board = entry }
            Dialog.say(game, say("completed"), finish)
          end)
        end)
      end,
    }))
  end)
end

-- pokefirered/src/union_room.c:3264
function UI.attendant(game, presence, done)
  local finish = open(game, presence, done)
  if not finish then return end
  local e = presence.boardEntry
  if e then
    local name = UI.speciesName(game.data, e.board.species)
    Dialog.ask(game, say("cancelReg", tostring(e.board.level), name), function(yes)
      if not yes then return finish() end
      UI.clear(presence)
      Dialog.say(game, say("canceled2"), finish)
    end)
    return
  end
  local function menu(text)
    Dialog.menu(game, text, UI.LABELS, function(i)
      if i == 1 then return UI.register(game, presence, finish) end
      if i == 2 then return menu(say("info")) end
      finish()
    end)
  end
  menu(say("welcome"))
end

function UI.items(game, presence)
  local items = {}
  for _, o in ipairs(Board.offers(presence.room, UI.DEX_MAX)) do
    items[#items + 1] = { label = UI.speciesName(game.data, o.species),
                          right = Strings("Lv%d", o.level), value = o }
  end
  items[#items + 1] = { label = Strings(UI.CANCEL), value = false }
  return items
end

-- pokefirered/src/union_room.c:3373
function UI.check(game, presence, done)
  local finish = open(game, presence, done)
  if not finish then return end
  local player = game.save and game.save.player or {}
  local function board()
    local ListMenu = require("src.ui.ListMenu")
    local list
    list = ListMenu.new(game, Strings(UI.TITLE), UI.items(game, presence), {
      onChoose = function(item)
        list:close()
        local o = item and item.value
        if not o then return finish() end
        UI.pick(game, presence, o, board, finish)
      end,
      onCancel = finish,
    })
    game.stack:push(list)
  end
  Dialog.say(game, say("checked", player.name), board)
end

function UI.partyTypes(game)
  return Board.partyTypes(game.data, game.save and game.save.party, UI.GEN)
end

-- pokefirered/src/union_room.c:3404
function UI.pick(game, presence, o, reopen, finish)
  local p = presence.room:member(o.p.id) or o.p
  if not Board.hasType(UI.partyTypes(game), o.typeName) then
    Dialog.say(game, say("noType", UI.typeLabel(game.data, o.typeName), p.name), reopen)
    return
  end
  Dialog.ask(game, say("askTrade", p.name), function(yes)
    if not yes then return finish() end
    if require("src.online.union.Participant").busy(p) then
      Dialog.say(game, Text.say("busy", p.name), finish)
      return
    end
    require("src.ui.union.gen1.Talk").invite(game, presence, p, "xg_trade", function()
      UI.settle(game, presence)
      finish()
    end)
  end)
end

return UI
