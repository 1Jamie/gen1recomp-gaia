-- scripts/VermilionOldRodHouse.asm:44
-- scripts/ViridianCity.asm:263
-- scripts/CeladonMart3F.asm:24
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
  local TextBox = require("src.render.TextBox")
  local Sound = require("src.core.Sound")

  local played = {}
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    played[#played + 1] = name
    return realPlay(data, name, ...)
  end

  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end

  local function finish()
    Sound.play = realPlay
    U.log(failed and "RESULT FAIL" or "RESULT PASS")
    love.event.quit(failed and 1 or 0)
    U.wait(600)
  end

  local function boxText(top)
    if getmetatable(top) ~= TextBox then return nil end
    local out = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do out[#out + 1] = tostring(line) end
      else
        out[#out + 1] = tostring(page)
      end
    end
    return table.concat(out, " / ")
  end

  local function npcWith(textConst)
    local ow = game.overworld
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.def and n.def.text == textConst then return n end
    end
  end

  local function standBy(map, textConst)
    U.teleport(game, map, 1, 1, "down")
    U.wait(10)
    local npc = npcWith(textConst)
    if not check(textConst .. " is loaded on " .. map, npc ~= nil) then
      return false
    end
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
      { 0, 2, "up" }, { 2, 0, "left" }, { -2, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = npc.cellX + s[1], npc.cellY + s[2]
      U.teleport(game, map, cx, cy, s[3])
      U.wait(10)
      local ow = game.overworld
      local fx, fy = ow.player:facingCell()
      local target = npcWith(textConst)
      if target and ow.player.cellX == cx and ow.player.cellY == cy
          and (ow:npcAtCell(fx, fy) == target
            or (math.abs(s[1]) == 2 or math.abs(s[2]) == 2)) then
        U.log("standing on", cx, cy, "facing", s[3])
        return true
      end
    end
    return check("found a cell facing " .. textConst, false)
  end

  local function idle()
    local ow = game.overworld
    return ow and game.stack:top() == ow
      and not (ow.runner and ow.runner:isRunning())
  end

  local function talk(shotName)
    local boxes, seen = {}, {}
    local shot, quiet = false, 0
    U.tap(game, "a")
    for _ = 1, 3000 do
      U.wait(2)
      local top = game.stack:top()
      local s = boxText(top)
      if s and not seen[top] then
        seen[top] = true
        boxes[#boxes + 1] = s
        U.log("box", #boxes, s)
      end
      if s and top.done and not shot and shotName and DIR
          and s:find("received", 1, true) then
        shot = true
        U.still(game, DIR .. "/" .. shotName)
      end
      if #boxes > 0 and idle() then
        quiet = quiet + 1
        if quiet > 30 then break end
      else
        quiet = 0
      end
      if top and top ~= game.overworld
          and (top.waiting or top.done or getmetatable(top) ~= TextBox) then
        U.tap(game, "a")
      end
    end
    U.wait(10)
    return boxes
  end

  local function contains(list, needle)
    for _, v in ipairs(list) do if v == needle then return true end end
    return false
  end

  local function firstLine(label)
    local s = game.data.text[label]
    if type(s) ~= "string" then return nil end
    return (s:match("^[^\n\011\012]+") or s):gsub("{[^}]*}", "")
  end

  local function hasExplain(boxes, label)
    local needle = firstLine(label)
    if not needle or needle == "" then return false end
    for _, b in ipairs(boxes) do
      if b:find(needle, 1, true) then return true end
    end
    return false
  end

  if not U.newGame(game) then
    check("reached the overworld", false)
    return finish()
  end
  local f = game.save.flags

  if standBy("VERMILION_OLD_ROD_HOUSE", "TEXT_VERMILIONOLDRODHOUSE_FISHING_GURU") then
    played = {}
    talk("2555_01_old_rod_received.png")
    check("2555 OLD ROD reached the bag",
      (game.save.inventory.OLD_ROD or 0) > 0)
    check("2555 OLD ROD plays Get_Item1", contains(played, "Get_Item1"))
    check("2555 OLD ROD does not play Get_Key_Item",
      not contains(played, "Get_Key_Item"))
  end

  if standBy("VIRIDIAN_CITY", "TEXT_VIRIDIANCITY_FISHER") then
    played = {}
    local boxes = talk("2592_01_tm42_received.png")
    check("2583 TM42 flag set", f.EVENT_GOT_TM42 == true)
    check("2592 TM42 plays Get_Item2", contains(played, "Get_Item2"))
    check("2592 TM42 does not play Get_Item1", not contains(played, "Get_Item1"))
    check("2583 TM42 first talk shows no explanation",
      not hasExplain(boxes, "_ViridianCityFisherTM42ExplanationText"))
    boxes = talk()
    check("2583 TM42 second talk is one box", #boxes == 1)
    check("2583 TM42 second talk is the explanation",
      hasExplain(boxes, "_ViridianCityFisherTM42ExplanationText"))
  end

  if standBy("CELADON_MART_3F", "TEXT_CELADONMART3F_CLERK") then
    played = {}
    local boxes = talk("2583_01_tm18_received.png")
    check("2583 TM18 flag set", f.EVENT_GOT_TM18 == true)
    check("2583 TM18 plays Get_Item1", contains(played, "Get_Item1"))
    check("2583 TM18 first talk ends on the receipt",
      #boxes == 2 and not hasExplain(boxes, "_CeladonMart3FClerkTM18ExplanationText"))
    boxes = talk()
    check("2583 TM18 second talk is one box", #boxes == 1)
    check("2583 TM18 second talk is the explanation",
      hasExplain(boxes, "_CeladonMart3FClerkTM18ExplanationText"))
  end

  finish()
end
