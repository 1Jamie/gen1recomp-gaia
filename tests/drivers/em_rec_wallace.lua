local Rec = require("tests.drivers.em_rec")
local inner = assert(loadfile("tests/drivers/em_story_seg4.lua"))()
local DIR = os.getenv("EM_REC_DIR") or ".bazinga/emerald/rec/wallace"
local STOP_AFTER_SCENE = tonumber(os.getenv("EM_REC_STOP_SCENE") or "")

return function(game)
  Rec.install(game, { dir = DIR, fast = tonumber(os.getenv("POKEPORT_SPEED")) or 200 })
  local last = {}
  local creditsSeen, scenes = false, 0
  Rec.onTickHook = function()
    local Runtime = package.loaded["src.core.game3.runtime"]
    local s = Runtime and Runtime.getSession and Runtime.getSession()
    local map = s and s.map
    if not Rec.armed and not Rec.done and map == "EM_EVER_GRANDE_CITY_CHAMPIONS_ROOM" then
      Rec.arm("champions_room")
    end
    if not Rec.armed then return end
    local function edge(key, v, label)
      if last[key] ~= v then
        last[key] = v
        Rec.mark(label .. "=" .. tostring(v))
      end
    end
    edge("map", map, "map")
    local T = package.loaded["src.core.game3.battle_transition"]
    edge("transition", T and T.isActive() or false, "transition")
    local B = package.loaded["src.core.game3.battle"]
    edge("battle", B and B.isActive() or false, "battle")
    local H = package.loaded["src.ui.game3.hall_of_fame"]
    edge("hof", H and H.isOpen() or false, "hof")
    if H and H.isOpen() then edge("hofphase", H.phase(), "hofphase") end
    local C = package.loaded["src.ui.game3.rse.credits"]
    local open = C and C.isOpen() or false
    edge("credits", open, "credits")
    if open then
      creditsSeen = true
      local st = C.state
      local ok, d7 = pcall(function() return st.m.tasks:get(st.mainId).data[7] end)
      if ok then
        if last.scene ~= d7 and d7 ~= nil then scenes = scenes + 1 end
        edge("scene", d7, "scene")
      end
      edge("showMons", st.showMons or false, "showMons")
      edge("theEnd", st.theEnd or false, "theEnd")
    end
    local M = package.loaded["src.ui.game3.message"]
    edge("msg", M and M.isOpen() or false, "msg")
    local stop = (creditsSeen and not open) or game.phase == "boot"
    if STOP_AFTER_SCENE and scenes > STOP_AFTER_SCENE then stop = true end
    if stop then
      Rec.mark("stop")
      Rec.done = true
      Rec.finish()
      love.event.quit(0)
    end
  end
  inner(game)
end
