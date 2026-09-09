-- In-battle / post-battle learn-move flow (pret handlelearnnewmove).
-- Driven by ROM learnsets via Pokemon.movesLearnedAt.
-- Choices open only after the message queue is idle (see LearnMove.pump).

local Pokemon = require("src.core.game3.pokemon")

local LearnMove = {}

LearnMove._active = false
LearnMove._mon = nil
LearnMove._moveId = nil
LearnMove._name = nil
LearnMove._moveName = nil
LearnMove._pushMsg = nil
LearnMove._askYesNo = nil
LearnMove._askForget = nil
LearnMove._onDone = nil
LearnMove._headless = false
LearnMove._waitingChoice = false
LearnMove._pending = nil -- "delete" | "stop" | "forget"
LearnMove._forgetSlots = nil

function LearnMove.reset()
  LearnMove._active = false
  LearnMove._mon = nil
  LearnMove._moveId = nil
  LearnMove._name = nil
  LearnMove._moveName = nil
  LearnMove._pushMsg = nil
  LearnMove._askYesNo = nil
  LearnMove._askForget = nil
  LearnMove._onDone = nil
  LearnMove._waitingChoice = false
  LearnMove._pending = nil
  LearnMove._forgetSlots = nil
  LearnMove._queue = nil
  LearnMove._queueIdx = 0
  LearnMove._queueOpts = nil
end

function LearnMove.busy()
  return LearnMove._active == true
end

function LearnMove.waitingChoice()
  return LearnMove._waitingChoice == true
end

local function finish(learned)
  local cb = LearnMove._onDone
  LearnMove._active = false
  LearnMove._mon = nil
  LearnMove._moveId = nil
  LearnMove._waitingChoice = false
  LearnMove._pending = nil
  LearnMove._onDone = nil
  -- Leave _queue / _queueOpts for beginQueue's onDone → queue_next
  if cb then cb(learned == true) end
end

local function say(text)
  if LearnMove._pushMsg and text then
    LearnMove._pushMsg(text)
  end
end

local function move_name(moveId)
  return Pokemon.moveName(moveId) or ("MOVE " .. tostring(moveId))
end

local function schedule(kind)
  LearnMove._pending = kind
end

local function open_delete_prompt()
  if LearnMove._headless or not LearnMove._askYesNo then
    say(LearnMove._name .. " did not learn\n" .. LearnMove._moveName .. ".")
    finish(false)
    return
  end
  LearnMove._waitingChoice = true
  LearnMove._askYesNo(function(yes)
    LearnMove._waitingChoice = false
    if not yes then
      schedule("stop")
      return
    end
    schedule("forget")
  end)
end

local function open_stop_prompt()
  if LearnMove._headless or not LearnMove._askYesNo then
    say(LearnMove._name .. " did not learn\n" .. LearnMove._moveName .. ".")
    finish(false)
    return
  end
  say("Stop learning\n" .. LearnMove._moveName .. "?")
  LearnMove._waitingChoice = true
  LearnMove._askYesNo(function(stop)
    LearnMove._waitingChoice = false
    if stop then
      say(LearnMove._name .. " did not learn\n" .. LearnMove._moveName .. ".")
      finish(false)
    else
      say("Delete an older move to\nmake room for " .. LearnMove._moveName .. "?")
      schedule("delete")
    end
  end)
end

local function open_forget_list()
  if LearnMove._headless or not LearnMove._askForget then
    say(LearnMove._name .. " did not learn\n" .. LearnMove._moveName .. ".")
    finish(false)
    return
  end
  local opts, slots = {}, {}
  for i = 1, 4 do
    local id = Pokemon.moveIdAt(LearnMove._mon, i)
    if id and id > 0 then
      local label = move_name(id)
      if Pokemon.isHmMove(id) then label = label .. " (HM)" end
      opts[#opts + 1] = label
      slots[#slots + 1] = i
    end
  end
  LearnMove._forgetSlots = slots
  LearnMove._waitingChoice = true
  LearnMove._askForget(opts, function(idx)
    LearnMove._waitingChoice = false
    if idx == nil or idx < 0 or idx >= #slots then
      schedule("stop")
      return
    end
    local slot = slots[idx + 1]
    local oldId = Pokemon.moveIdAt(LearnMove._mon, slot)
    if Pokemon.isHmMove(oldId) then
      say("HM moves can't be\nforgotten now.")
      say("Delete an older move to\nmake room for " .. LearnMove._moveName .. "?")
      schedule("delete")
      return
    end
    local forgotten = Pokemon.replaceMove(LearnMove._mon, slot, LearnMove._moveId)
    if forgotten then
      say("1, 2, and… Poof!")
      say(LearnMove._name .. " forgot\n" .. move_name(forgotten) .. "!")
      say("And…")
      say(LearnMove._name .. " learned\n" .. LearnMove._moveName .. "!")
      finish(true)
    else
      schedule("delete")
    end
  end)
end

--- Call when message queue is idle. Opens deferred Choice prompts.
-- Returns false while still busy.
function LearnMove.pump()
  if not LearnMove._active then return true end
  if LearnMove._waitingChoice then return false end
  local pending = LearnMove._pending
  if not pending then
    return false -- still active, waiting for finish from choice path or free teach
  end
  LearnMove._pending = nil
  if pending == "delete" then
    open_delete_prompt()
  elseif pending == "stop" then
    open_stop_prompt()
  elseif pending == "forget" then
    open_forget_list()
  end
  return not LearnMove._active
end

function LearnMove.begin(opts)
  opts = opts or {}
  local mon = opts.mon
  local moveId = tonumber(opts.moveId)
  if not mon or not moveId then
    if opts.onDone then opts.onDone(false) end
    return
  end
  if Pokemon.knowsMove(mon, moveId) then
    if opts.onDone then opts.onDone(false) end
    return
  end

  LearnMove._active = true
  LearnMove._mon = mon
  LearnMove._moveId = moveId
  LearnMove._name = opts.displayName or Pokemon.displayMonName(mon)
  LearnMove._moveName = move_name(moveId)
  LearnMove._pushMsg = opts.pushMsg
  LearnMove._askYesNo = opts.askYesNo
  LearnMove._askForget = opts.askForget
  LearnMove._onDone = opts.onDone
  LearnMove._headless = opts.headless and true or false
  LearnMove._waitingChoice = false
  LearnMove._pending = nil

  if Pokemon.moveSlotCount(mon) < 4 then
    local ok = Pokemon.teachMove(mon, moveId)
    if ok then
      say(LearnMove._name .. " learned\n" .. LearnMove._moveName .. "!")
    end
    finish(ok)
    return
  end

  say(LearnMove._name .. " is trying to\nlearn " .. LearnMove._moveName .. ".")
  say("But, " .. LearnMove._name .. " can't learn\nmore than four moves.")
  say("Delete an older move to\nmake room for " .. LearnMove._moveName .. "?")
  schedule("delete")
end

function LearnMove.movesForLevels(mon, levels)
  local species = tonumber(mon and (mon.species or mon.speciesId))
  local out = {}
  if not species then return out end
  local seen = {}
  for _, lv in ipairs(levels or {}) do
    for _, mv in ipairs(Pokemon.movesLearnedAt(species, lv)) do
      if not seen[mv] and not Pokemon.knowsMove(mon, mv) then
        seen[mv] = true
        out[#out + 1] = { level = lv, moveId = mv }
      end
    end
  end
  return out
end

local function queue_next()
  local opts = LearnMove._queueOpts
  local mon = opts and opts.mon
  LearnMove._queueIdx = (LearnMove._queueIdx or 0) + 1
  local item = LearnMove._queue and LearnMove._queue[LearnMove._queueIdx]
  if not item or not mon then
    local cb = opts and opts.onDone
    LearnMove._queue = nil
    LearnMove._queueOpts = nil
    if cb then cb() end
    return
  end
  LearnMove.begin({
    mon = mon,
    moveId = item.moveId,
    displayName = opts.displayName,
    pushMsg = opts.pushMsg,
    askYesNo = opts.askYesNo,
    askForget = opts.askForget,
    headless = opts.headless,
    onDone = function()
      queue_next()
    end,
  })
end

function LearnMove.beginQueue(mon, levels, opts)
  opts = opts or {}
  opts.mon = mon
  local q = LearnMove.movesForLevels(mon, levels)
  if #q == 0 then
    if opts.onDone then opts.onDone() end
    return false
  end
  LearnMove._queue = q
  LearnMove._queueIdx = 0
  LearnMove._queueOpts = opts
  queue_next()
  return true
end

return LearnMove
