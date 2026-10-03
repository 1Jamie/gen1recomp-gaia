-- pokered/scripts/SilphCo10F.asm:72
-- pokered/text/SilphCo10F.asm:1
-- pokeyellow/text/SilphCo10F.asm:1
return function(game)
  local U = require("tests.drivers.util")
  local TextBox = require("src.render.TextBox")
  local Font = require("src.render.Font")
  local Version = require("src.core.GameVersion")
  local Timing = require("src.core.Timing")
  local dir = assert(os.getenv("POKEPORT_SHOT_DIR"), "POKEPORT_SHOT_DIR is required")
  local edition = Version.get()
  local fails = 0

  local function check(ok, label)
    U.log((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function same(a, b)
    if #a ~= #b then return false end
    for i, value in ipairs(a) do if value ~= b[i] then return false end end
    return true
  end
  local function rows(box, expected, label)
    local good = #box.shown == #expected and same(box:visibleText() or {}, expected)
    for i, text in ipairs(expected) do
      good = good and same(box.shown[i] or {}, Font.encode(text))
    end
    return check(good, label)
  end
  local function prompt(box)
    for _ = 1, 400 do
      if game.stack:top() ~= box then return false end
      if box.waiting or box.done then return true end
      U.wait(1)
    end
    return false
  end
  local function capture(box, file)
    for _ = 1, 60 do
      if box.blink % 60 < 20 then break end
      U.wait(1)
    end
    check(U.still(game, dir .. "/" .. file), "screenshot " .. file)
  end
  local function close(box)
    U.tap(game, "a")
    for _ = 1, 120 do
      if game.stack:top() == game.overworld and not game.overworld.runner:isRunning() then
        return check(true, "NPC callback returns to overworld")
      end
      U.wait(1)
    end
    return check(false, "NPC callback returns to overworld")
  end
  local function talk()
    U.teleport(game, "SILPH_CO_10F", 8, 15, "right")
    local ow = game.overworld
    local worker
    for _, npc in ipairs(ow.npcs) do
      if npc.def.name == "SILPHCO10F_SILPH_WORKER_F" then worker = npc end
    end
    if not check(worker ~= nil, "real Silph 10F worker is loaded") then return nil end
    -- pokered/data/maps/objects/SilphCo10F.asm:25
    worker.wanders = false
    worker:resetToSpawn()
    worker.cellX, worker.cellY = 9, 15
    worker.px, worker.py = 9 * 16, 15 * 16
    U.tap(game, "a")
    for _ = 1, 120 do
      local box = game.stack:top()
      if getmetatable(box) == TextBox then return box end
      U.wait(1)
    end
    check(false, "NPC A dispatch opens textbox")
  end
  local function cachedRows(key, marker)
    local raw = game.data.text[key]
    if not check(type(raw) == "string", "cache contains " .. key) then return nil end
    local text = TextBox.strip(TextBox.substitute(game, raw))
    local first, actual, last = text:match("^(.-)([\n\v])(.-)$")
    if not check(first and last and actual == marker and not last:find("[\n\v\f]"),
      edition .. " cached control for " .. key) then return nil end
    return { first, last }
  end

  if not check(edition == "red" or edition == "blue" or edition == "yellow",
    "supported Gen 1 edition") then love.event.quit(1) return end
  game.save.flags.EVENT_BEAT_SILPH_CO_10F_TRAINER_0 = true
  game.save.flags.EVENT_BEAT_SILPH_CO_10F_TRAINER_1 = true
  game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = nil
  local scared = cachedRows("_SilphCo10FSilphWorkerFImScaredText", edition == "yellow" and "\n" or "\v")
  local quiet = cachedRows("_SilphCo10FSilphWorkerFQuietAboutMyCryingText", "\n")
  if not scared or not quiet then love.event.quit(1) return end
  local box = talk()
  if not box or not check(prompt(box), "scared text reaches prompt") then
    love.event.quit(1) return
  end
  if edition == "yellow" then
    local good = check(box.done and not box.waiting, "Yellow ordinary line needs no cont press")
    good = rows(box, scared, "Yellow scared text keeps both rows") and good
    if good then capture(box, "2634_yellow_scared_two_rows.png") end
  else
    local good = check(box.waiting and box.contAdvance, "Red Blue scared text waits on cont")
    good = rows(box, { scared[1] }, "Red Blue initial scared text upper row") and good
    if good then capture(box, "2634_scared_cont_arrow.png") end
    U.wait(Timing.TEXT_PRE_ADVANCE)
    U.tap(game, "a")
    check(prompt(box) and box.done and not box.waiting, "one cont press completes scared text")
    local expected = { "", scared[2] }
    if rows(box, expected, "Red Blue scared text blank upper bottom sentence") then
      capture(box, "2634_scared_blank_upper_bottom_sentence.png")
    end
    local instant = TextBox.new(game, game.data.text._SilphCo10FSilphWorkerFImScaredText,
      nil, { instant = true })
    rows(instant, expected, "instant scared text matches physical rows")
  end
  if not close(box) then love.event.quit(1) return end
  game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = true
  box = talk()
  if not box or not check(prompt(box), "quiet text reaches prompt") then
    love.event.quit(1) return
  end
  local good = check(box.done and not box.waiting, "quiet text needs no cont press")
  good = rows(box, quiet, "post Giovanni quiet text keeps both rows") and good
  if good then capture(box, "2634_post_giovanni_quiet_two_rows.png") end
  close(box)
  U.log(fails == 0 and "PASS silph10f_cont_bug2634 " .. edition or "FAIL silph10f_cont_bug2634 " .. edition)
  love.event.quit(fails == 0 and 0 or 1)
end
