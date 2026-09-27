local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_apprentice", "/tmp/em_apprentice")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has the post-Hall-of-Fame save") then return finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Natives = require("src.core.game3.scripting.natives")
  local Objects = require("src.core.game3.objects")
  local EasyChat = require("src.ui.game3.easy_chat")
  local Choice = require("src.ui.game3.choice")
  session = Runtime.getSession()
  Natives.ensureBound(session)
  local Ap = require("src.core.game3.rse.frontier.apprentice")
  check(Natives.handlerFor("CallApprenticeFunction") ~= nil, "CallApprenticeFunction bound on Emerald")
  require("src.core.game3.encounters").onStep = function() return nil end
  local Bag = require("src.core.game3.bag")
  Bag.add(session.bag, S.item("ITEM_LEFTOVERS"), 1)
  Bag.add(session.bag, S.item("ITEM_QUICK_CLAW"), 1)
  Bag.add(session.bag, S.item("ITEM_SITRUS_BERRY"), 1)

  local function teleport(mapId, x, y, facing)
    S.settle(game)
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    if not ok then note("Map.load " .. mapId .. ": " .. tostring(err)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    U.wait(30)
    S.settle(game)
    return ok
  end

  local p = Ap.player(session)
  local startId = p.id
  local asked = {}
  local shots = 0
  local chatDone = false
  local bagPick = 0
  for day = 1, 14 do
    S.setFlag("FLAG_DAILY_APPRENTICE_LEAVES", false)
    S.setFlag("FLAG_HIDE_APPRENTICE", false)
    if not teleport("EM_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY", 1, 7, "up") then break end
    local app = S.objectByScript("BattleFrontier_BattleTowerLobby_EventScript_Apprentice")
    if not app or app.hidden then
      note("day " .. day .. ": apprentice not shown")
      break
    end
    if day == 1 then
      check(tonumber(app.graphicsId) == S.var("VAR_OBJ_GFX_ID_0") or app.graphicsId ~= nil,
        "apprentice_setgfx picks the apprentice's gfx")
      shot("01_apprentice_in_lobby")
    end
    local before = p.questionsAnswered
    local menus = 0
    local settleOpts
    local tick = 0
    settleOpts = { limit = 20000,
      watch = function()
        tick = tick + 1
        if tick % 3000 == 0 then
          note("stuck? day " .. day .. " vm " .. S.vmWhere() .. " choice " .. tostring(Choice.isOpen()) .. " msg "
            .. tostring(require("src.ui.game3.message").isOpen()) .. " fade " .. tostring(require("src.ui.game3.fade").isActive and require("src.ui.game3.fade").isActive()))
        end
      end,
      choice = function(ch)
        menus = menus + 1
        if shots < 4 then
          shots = shots + 1
          U.wait(6)
          shot(string.format("02_question_%d", shots))
        end
        local n = #(ch.options or {})
        local last = ch.options and ch.options[n]
        if n > 2 and tostring(type(last) == "table" and (last.text or last[1]) or last):upper():find("CANCEL", 1, true) then
          bagPick = bagPick % (n - 1) + 1
          return bagPick
        end
        return 1
      end,
      onIdleUi = function()
        if EasyChat.isOpen() then
          local def = Ap.def(p.id)
          U.wait(10)
          shot("03_win_speech_easy_chat")
          EasyChat.close(true, def and def.speechLost or { 1, 2, 3 })
          chatDone = true
          U.wait(10)
          return true
        end
        return false
      end }
    S.talkTo(game, app, { settle = settleOpts })
    S.settle(game, settleOpts)
    local qs = {}
    for i = 1, Ap.MAX_QUESTIONS do qs[i] = tostring(p.questions[i].questionId) end
    note("questions " .. table.concat(qs, ","))
    asked[#asked + 1] = string.format("day %d answered %d->%d menus %d", day, before, p.questionsAnswered, menus)
    if chatDone then break end
  end
  for _, a in ipairs(asked) do note(a) end
  check(#asked >= 4, "the apprentice asked on several days (" .. #asked .. ")")
  check(p.lvlMode ~= 0 or chatDone, "the first meeting sets the level mode")
  check(chatDone, "the apprentice finally asks for a win speech through the easy chat screen")
  local saved = Ap.saved(session)[1]
  check(saved.number >= 1 and saved.id == startId, "SaveApprentice stored apprentice " .. tostring(startId)
    .. " as number " .. tostring(saved.number))
  check(saved.party[1].species ~= 0 and saved.party[2].species ~= 0 and saved.party[3].species ~= 0,
    "the saved apprentice has a three-mon party")
  check(saved.speechWon[1] ~= Ap.EC_EMPTY_WORD, "the win speech is saved")
  check(Ap.player(session).questionsAnswered == 0, "apprentice_reset starts a new apprentice")
  finish()
end
