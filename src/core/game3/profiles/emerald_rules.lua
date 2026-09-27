local Rules = {}

local GAME = "emerald"

local function block()
  return require("src.core.game3.profile").of(GAME).save
end

local function constants()
  return require("src.core.game3.constants").of(GAME)
end

Rules.DEFAULT_NAME = nil
Rules.DEFAULT_RIVAL = nil
Rules.EASY_CHAT_PROFILE = nil
Rules.OWN_MON_MET_LOCATION = nil
-- pokeemerald/src/pokemon.c:6078
Rules.POKERUS = true

function Rules.newGameMoney()
  return block().money
end

function Rules.newGameFlags()
  return {}
end

function Rules.newVsSeeker()
  return nil
end

function Rules.restoreVsSeeker(_)
  return nil
end

-- pokeemerald/src/player_pc.c:358
function Rules.newGamePcItems(storage)
  local C = constants()
  storage.items = {}
  for _, row in ipairs(block().pcItems) do
    storage.items[#storage.items + 1] = { id = C:require("items", row.item), qty = row.qty }
  end
end

local function run_script_immediately(session, key)
  local Space = require("src.core.game3.scripting.space")
  local bundle = Space.ensureBundle(nil)
  assert(bundle and bundle.scripts and bundle.scripts[key], "script bundle has no " .. tostring(key))
  local Vm = require("src.core.game3.scripting.vm")
  local vm = Vm.new({
    store = session,
    scripts = bundle.scripts,
    text = bundle.text,
    movements = bundle.movements,
    version = session.version,
  })
  vm:start(key)
  for _ = 1, 1024 do
    if not vm:isRunning() then break end
    vm:tick()
  end
end

Rules.runScriptImmediately = run_script_immediately

function Rules.newGameInit(session, opts)
  local save = block()
  local C = constants()
  -- pokeemerald/src/new_game.c:178
  session.vars = session.vars or {}
  for _, name in ipairs(save.sizeRecordVars) do
    session.vars[C:require("vars", name)] = save.sizeRecordDefault
  end
  -- pokeemerald/src/new_game.c:196
  local run = (opts and opts.runScript) or run_script_immediately
  run(session, save.resetScript)
end

-- pokeemerald/src/overworld.c:1711
function Rules.resetStateOnContinue(session)
  local Flags = require("src.core.game3.scripting.flags")
  Flags.setFlag(session, nil, constants():require("flags", "FLAG_SYS_SAFARI_MODE"), false)
  session.safari = nil
end

local CONTINUE_GAME_WARP = 0x01

-- pokeemerald/src/load_save.c:134
function Rules.useContinueGameWarp(session)
  local Bit = require("bit")
  local f = tonumber(session.specialSaveWarpFlags) or 0
  local w = session.continueGameWarp
  session._continueWarpDeferred = nil
  if Bit.band(f, CONTINUE_GAME_WARP) ~= 0 and type(w) == "table" and type(w.map) == "string" then
    -- pokeemerald/src/overworld.c:1741
    session.specialSaveWarpFlags = Bit.band(f, Bit.bnot(CONTINUE_GAME_WARP))
    session.map, session.x, session.y, session.facing = w.map, tonumber(w.x), tonumber(w.y), "down"
  end
end

function Rules.saveWarpFields(session)
  return tonumber(session.specialSaveWarpFlags) or 0, session.continueGameWarp
end

return Rules
