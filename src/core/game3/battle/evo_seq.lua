-- Post-win evolution presentation (pret TryEvolvePokemon, EVO_LEVEL MVP).

local Evolution = require("src.core.game3.evolution")
local LearnMove = require("src.core.game3.battle.learn_move")
local Pokemon = require("src.core.game3.pokemon")

local EvoSeq = {}

EvoSeq._steps = nil
EvoSeq._i = 1
EvoSeq._waiting = false
EvoSeq._pushMsg = nil
EvoSeq._askYesNo = nil
EvoSeq._askForget = nil
EvoSeq._headless = false

function EvoSeq.reset()
  EvoSeq._steps = nil
  EvoSeq._i = 1
  EvoSeq._waiting = false
  EvoSeq._pushMsg = nil
  LearnMove.reset()
end

function EvoSeq.busy()
  return EvoSeq._steps ~= nil or LearnMove.busy()
end

local function finish()
  EvoSeq._steps = nil
  EvoSeq._i = 1
  EvoSeq._waiting = false
end

local function advance()
  EvoSeq._waiting = false
  EvoSeq._i = EvoSeq._i + 1
end

--- pending: Evolution.pending() results
function EvoSeq.begin(pending, opts)
  opts = opts or {}
  EvoSeq.reset()
  EvoSeq._pushMsg = opts.pushMsg
  EvoSeq._askYesNo = opts.askYesNo
  EvoSeq._askForget = opts.askForget
  EvoSeq._headless = opts.headless and true or false

  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data }
  end

  for _, entry in ipairs(pending or {}) do
    local mon = entry.mon
    local fromName = Pokemon.displayMonName(mon)
    -- If nicknamed, pret still says nickname is evolving / evolved into SPECIES
    local intoName = Pokemon.name(entry.toSpecies) or ("POKéMON")
    add("msg", { text = "What?\n" .. fromName .. " is evolving!" })
    add("apply", {
      mon = mon,
      toSpecies = entry.toSpecies,
      fromName = fromName,
      intoName = intoName,
    })
    add("msg", {
      text = "Congratulations! Your " .. fromName
        .. "\nevolved into " .. intoName .. "!",
    })
    add("learn_evo", {
      mon = mon,
      displayName = fromName, -- nickname kept; species name changed after apply
    })
  end

  if #steps == 0 then
    finish()
    return false
  end
  EvoSeq._steps = steps
  EvoSeq._i = 1
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
    if EvoSeq._pushMsg and d.text then
      EvoSeq._pushMsg(d.text)
    end
    advance()
    return
  end

  if kind == "apply" then
    Evolution.apply(d.mon, d.toSpecies)
    -- After evolve, display name for learn may still prefer nickname
    advance()
    return
  end

  if kind == "learn_evo" then
    -- Learn moves the new species gets at the mon's current level (exact).
    local mon = d.mon
    local lv = tonumber(mon and mon.level) or 1
    EvoSeq._waiting = true
    local started = LearnMove.beginQueue(mon, { lv }, {
      displayName = Pokemon.displayMonName(mon),
      pushMsg = EvoSeq._pushMsg,
      askYesNo = EvoSeq._askYesNo,
      askForget = EvoSeq._askForget,
      headless = EvoSeq._headless,
      onDone = function()
        advance()
      end,
    })
    if not started then
      advance()
    elseif not LearnMove.busy() and EvoSeq._waiting then
      if EvoSeq._waiting then advance() end
    end
    return
  end

  advance()
end

function EvoSeq.update()
  if LearnMove.busy() then
    LearnMove.pump()
    return false
  end
  if not EvoSeq._steps then return true end
  if EvoSeq._waiting then
    if LearnMove.busy() then return false end
    advance()
  end
  local step = EvoSeq._steps[EvoSeq._i]
  if not step then
    finish()
    return true
  end
  run_step(step)
  return false
end

return EvoSeq
