local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local F = {}

function F.boot(game, d)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not d.check(game.boot ~= nil, "boot reached") then return nil end
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not d.check(type(raw) == "string", "identity has the post-Hall-of-Fame save") then return nil end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)
  session = require("src.core.game3.runtime").getSession()
  if not d.check(session and session.version == "emerald" and S.flag("FLAG_SYS_GAME_CLEAR"),
      "post-game Emerald session (" .. tostring(session and session.name) .. ")") then return nil end
  require("src.core.game3.scripting.natives").ensureBound(session)
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end
  return session
end

function F.mon(session, name, moves, nature, evs)
  local D = require("src.core.game3.rse.frontier.trainers")
  local personality = nature or 0
  local m = D.createMon(S.species(name), 50, 31, personality, tonumber(session.trainerId) or 0,
    { otName = session.name, moves = {} })
  local ms = {}
  for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
  D.setMoves(m, ms)
  D.setEvs(m, evs or { 252, 252, 6, 0, 0, 0 })
  m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
  return m
end

function F.teleport(game, d, mapId, x, y, facing)
  local Map = require("src.core.game3.map")
  local Runtime = require("src.core.game3.runtime")
  S.settle(game)
  local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
  if not ok then d.note("Map.load " .. mapId .. ": " .. tostring(err)) end
  local s = Runtime.getSession()
  if s then s.x, s.y, s.facing = x, y, facing end
  U.wait(30)
  S.settle(game)
  return ok
end

local function messageText()
  local Message = require("src.ui.game3.message")
  local pages = Message._pages or {}
  local t = {}
  for _, pg in ipairs(pages) do
    if type(pg) == "table" then
      for _, part in ipairs(pg) do t[#t + 1] = type(part) == "table" and tostring(part.text or part.s or "") or tostring(part) end
    else
      t[#t + 1] = tostring(pg)
    end
  end
  t = table.concat(t, " ")
  if type(t) == "table" then
    local ok, s = pcall(require("src.core.game3.scripting.text_ir").toAscii, t, {})
    t = ok and s or ""
  end
  return tostring(t or "")
end
F.messageText = messageText

local function optionTexts(ch)
  local out = {}
  for i, o in ipairs(ch.options or {}) do
    out[i] = tostring(type(o) == "table" and (o.text or o.label or o[1]) or o):upper()
  end
  return out
end
F.optionTexts = optionTexts

function F.pick(ch, word)
  for i, t in ipairs(optionTexts(ch)) do
    if t:find(word, 1, true) then return i end
  end
  return nil
end

function F.yesNo(ch)
  local msg = messageText():upper()
  local yes, no = F.pick(ch, "YES"), F.pick(ch, "NO")
  if yes and no then
    if msg:find("RECORD", 1, true) then return no end
    return yes
  end
  return nil
end

function F.partyPicker(d, game, slots, shotName)
  local PartyMenu = require("src.ui.game3.party_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local state = { opened = 0, saved = 0 }
  function state.idle()
    if PartyMenu.isOpen() and PartyMenu.mode == "choose_multi" then
      state.opened = state.opened + 1
      if state.opened == 1 and shotName then
        U.wait(10)
        d.shot(game, shotName)
      end
      local want = type(slots) == "function" and slots(state.opened) or slots
      for _, slot in ipairs(want) do
        PartyMenu.enterChosenMon(slot)
        U.wait(4)
      end
      PartyMenu.confirmChosenMons()
      U.wait(10)
      return true
    end
    if SaveMenu.isOpen() then
      state.saved = state.saved + 1
      U.tap(game, "a")
      U.wait(8)
      return true
    end
    return false
  end
  return state
end

function F.vmLogsExcept(d, patterns)
  local kept, dropped = {}, 0
  for _, l in ipairs(d.vmLogs) do
    local skip = false
    for _, p in ipairs(patterns) do if l:find(p, 1, true) then skip = true end end
    if skip then dropped = dropped + 1 else kept[#kept + 1] = l end
  end
  d.vmLogs = kept
  return dropped
end

return F
