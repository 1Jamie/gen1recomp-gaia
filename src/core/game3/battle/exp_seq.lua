-- Post-faint EXP presentation: gained → bar → level-up → learn moves (ROM learnset).

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local LearnMove = require("src.core.game3.battle.learn_move")
local Pokemon = require("src.core.game3.pokemon")

local ExpSeq = {}

ExpSeq._steps = nil
ExpSeq._i = 1
ExpSeq._waiting = false
ExpSeq._pushMsg = nil
ExpSeq._askYesNo = nil
ExpSeq._askForget = nil
ExpSeq._headless = false
ExpSeq._leveled = nil -- {[partyIndex]=true}

function ExpSeq.reset()
  ExpSeq._steps = nil
  ExpSeq._i = 1
  ExpSeq._waiting = false
  ExpSeq._pushMsg = nil
  ExpSeq._askYesNo = nil
  ExpSeq._askForget = nil
  ExpSeq._leveled = nil
  LearnMove.reset()
end

function ExpSeq.busy()
  return ExpSeq._steps ~= nil or LearnMove.busy()
end

function ExpSeq.leveledSet()
  return ExpSeq._leveled
end

local function finish()
  ExpSeq._steps = nil
  ExpSeq._i = 1
  ExpSeq._waiting = false
end

local function advance()
  ExpSeq._waiting = false
  ExpSeq._i = ExpSeq._i + 1
end

local function mon_name(entry)
  if entry.battler then return State.displayName(entry.battler) end
  return Pokemon.displayMonName(entry.mon)
end

--- awards: Experience.awardFoe results
--- opts: pushMsg, askYesNo, askForget, headless, thenMsgs
function ExpSeq.begin(awards, pushMsg, thenMsgs, opts)
  opts = opts or {}
  ExpSeq.reset()
  ExpSeq._pushMsg = pushMsg or opts.pushMsg
  ExpSeq._askYesNo = opts.askYesNo
  ExpSeq._askForget = opts.askForget
  ExpSeq._headless = opts.headless and true or false
  ExpSeq._leveled = {}

  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data }
  end

  for _, entry in ipairs(awards or {}) do
    local mon = entry.mon
    local result = entry.result or {}
    local name = mon_name(entry)
    local gained = result.gained or entry.amount or 0
    local pi = entry.partyIndex or 1
    local isBench = (entry.battler == nil)
    if gained > 0 then
      add("msg", { text = name .. " gained\n" .. tostring(gained) .. " EXP. Points!" })
      for _, step in ipairs(result.steps or {}) do
        if not isBench then
          add("exp", {
            side = "player",
            level = step.level,
            fromRatio = step.fromRatio,
            toRatio = step.toRatio,
          })
        end
        if step.grewTo then
          ExpSeq._leveled[pi] = true
          add("level", {
            side = "player",
            isBench = isBench,
            level = step.grewTo,
            hp = step.hp or (mon and tonumber(mon.hp)),
            maxHp = step.maxHp or (mon and tonumber(mon.maxHp)),
            text = name .. " grew to\nLV. " .. tostring(step.grewTo) .. "!",
          })
          -- ROM learnset moves at this exact level
          local moves = Pokemon.movesLearnedAt(
            tonumber(mon and (mon.species or mon.speciesId)),
            step.grewTo
          )
          for _, mv in ipairs(moves) do
            add("learn", {
              mon = mon,
              moveId = mv,
              displayName = name,
              partyIndex = pi,
            })
          end
        end
      end
    end
  end

  for _, t in ipairs(thenMsgs or opts.thenMsgs or {}) do
    add("msg", { text = t })
  end

  if #steps == 0 then
    finish()
    return false
  end
  ExpSeq._steps = steps
  ExpSeq._i = 1
  ExpSeq._waiting = false
  return true
end

local function run_step(step)
  if not step then
    finish()
    return
  end
  local kind = step.kind
  local d = step.data or {}

  if kind == "msg" then
    if ExpSeq._pushMsg and d.text then
      ExpSeq._pushMsg(d.text)
    end
    advance()
    return
  end

  if kind == "exp" then
    ExpSeq._waiting = true
    local p = Anim.present(d.side or "player")
    if p and d.level then p.displayLevel = d.level end
    do
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      Audio.playSe(SE.SE_EXP)
    end
    Anim.tweenExp(d.side or "player", d.fromRatio, d.toRatio, {
      level = d.level,
      onComplete = function()
        advance()
      end,
    })
    if not Anim.busy() and ExpSeq._waiting then
      advance()
    end
    return
  end

  if kind == "level" then
    if not d.isBench then
      local p = Anim.present(d.side or "player")
      if p then
        p.displayLevel = d.level
        p.displayExp = 0
        if d.maxHp then
          p.displayMaxHp = d.maxHp
          p.displayHp = d.hp or d.maxHp
        end
      end
    end
    do
      local Audio = require("src.core.game3.audio")
      Audio.playFanfare(Audio.role("levelUp") or 257)
    end
    if ExpSeq._pushMsg and d.text then
      ExpSeq._pushMsg(d.text)
    end
    advance()
    return
  end

  if kind == "learn" then
    ExpSeq._waiting = true
    local started = true
    LearnMove.begin({
      mon = d.mon,
      moveId = d.moveId,
      displayName = d.displayName,
      pushMsg = ExpSeq._pushMsg,
      askYesNo = ExpSeq._askYesNo,
      askForget = ExpSeq._askForget,
      headless = ExpSeq._headless,
      onDone = function()
        advance()
      end,
    })
    -- Free-slot teach may finish synchronously
    if not LearnMove.busy() and ExpSeq._waiting then
      -- onDone already advanced
      if ExpSeq._waiting then advance() end
    end
    return
  end

  advance()
end

function ExpSeq.update()
  if LearnMove.busy() then
    LearnMove.pump()
    return false
  end
  if not ExpSeq._steps then return true end
  if ExpSeq._waiting then
    if LearnMove.busy() then
      return false
    end
    if not Anim.busy() then
      advance()
    else
      return false
    end
  end
  local step = ExpSeq._steps[ExpSeq._i]
  if not step then
    finish()
    return true
  end
  run_step(step)
  return false
end

return ExpSeq
