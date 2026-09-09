-- Native Fire Red save schema (engine SaveData JSON). No GBA Flash dumps.

local MapIds = require("src.core.game3.map_ids")
local Options = require("src.core.game3.options")

local Schema = {}

Schema.VERSION = 1

local function empty_string_vars()
  return { [1] = "", [2] = "", [3] = "" }
end

local function empty_special_vars()
  local t = {}
  for i = 0x8000, 0x8014 do
    t[i] = 0
  end
  return t
end

--- Factory for a pristine New Game after Oak intro finishes.
function Schema.newGame(opts)
  opts = opts or {}
  local start = opts.start or MapIds.NEW_GAME_START
  local Flags = require("src.core.game3.scripting.flags")
  local Bag = require("src.core.game3.bag")
  local hide = {}
  for _, id in ipairs(Flags.NEW_GAME_HIDE_FLAGS or {}) do
    hide[tostring(id)] = true
  end
  local session = {
    schemaVersion = Schema.VERSION,
    engine = "game3",
    version = opts.version or "firered",
    generation = 3,
    party = {},
    bag = Bag.new(),
    dex = { seen = {}, owned = {}, national = false },
    money = tonumber(opts.money) or 3000,
    coins = 0,
    name = opts.name or "RED",
    rivalName = opts.rivalName or "BLUE",
    gender = opts.gender or 0, -- 0 boy / 1 girl
    map = start.map,
    x = start.x,
    y = start.y,
    facing = start.facing or "down",
    healMap = start.healMap or start.map,
    healX = start.healX or start.x,
    healY = start.healY or start.y,
    stringVars = empty_string_vars(),
    specialVars = empty_special_vars(),
    flags = hide,
    vars = {},
    playtime = { hours = 0, minutes = 0, seconds = 0 },
    options = nil,
    pc = { items = {} },
    registeredItem = nil,
    move_overlay = {},
    trainerId = nil,
    rng = nil,
  }
  -- pret new_game.c: SeedWildEncounterRng(Random()) after title SeedRngAndSetTrainerId.
  local Rng = require("src.core.game3.rng")
  session.trainerId = Rng.seedNewGame({ seed = opts.rngSeed })
  Rng.captureToSession(session)
  Options.ensure(session)
  -- Plan naming: text_speed / l_equals_a aliases mirror Options fields.
  session.options.text_speed = session.options.textSpeed
  session.options.l_equals_a = (session.options.buttonMode == 2)
  return session
end

function Schema.toSaveTable(session)
  if type(session) ~= "table" then return nil end
  Options.ensure(session)
  local Rng = require("src.core.game3.rng")
  Rng.captureToSession(session)
  return {
    schemaVersion = session.schemaVersion or Schema.VERSION,
    engine = "game3",
    version = "firered",
    name = session.name,
    rivalName = session.rivalName,
    gender = session.gender,
    money = session.money,
    coins = session.coins,
    party = session.party,
    bag = session.bag,
    inventory = session.bag, -- SaveData compatibility alias
    dex = session.dex,
    map = session.map,
    x = session.x,
    y = session.y,
    facing = session.facing,
    healMap = session.healMap,
    healX = session.healX,
    healY = session.healY,
    stringVars = session.stringVars or empty_string_vars(),
    specialVars = session.specialVars or empty_special_vars(),
    flags = session.flags or {},
    vars = session.vars or {},
    playTime = session.playtime or session.playTime or { hours = 0, minutes = 0, seconds = 0 },
    options = session.options,
    pc = session.pc,
    registeredItem = session.registeredItem,
    move_overlay = session.move_overlay or {},
    trainerId = session.trainerId,
    rng = session.rng,
  }
end

function Schema.fromSaveTable(save)
  if type(save) ~= "table" then return Schema.newGame() end
  local Bag = require("src.core.game3.bag")
  local bag = save.bag or save.inventory or {}
  if type(bag) ~= "table" or not bag.pockets then
    bag = Bag.migrate(type(bag) == "table" and bag or {})
  else
    Bag.migrate(bag) -- ensure stacks mirror
  end
  local session = {
    schemaVersion = save.schemaVersion or Schema.VERSION,
    party = save.party or {},
    bag = bag,
    dex = save.dex or {},
    money = save.money or 0,
    coins = save.coins or 0,
    name = save.name or save.playerName or "RED",
    rivalName = save.rivalName or "BLUE",
    gender = save.gender or 0,
    map = save.map or MapIds.NEW_GAME_START.map,
    x = save.x or MapIds.NEW_GAME_START.x,
    y = save.y or MapIds.NEW_GAME_START.y,
    facing = save.facing or "down",
    healMap = save.healMap,
    healX = save.healX,
    healY = save.healY,
    stringVars = save.stringVars or empty_string_vars(),
    specialVars = save.specialVars or empty_special_vars(),
    flags = save.flags or {},
    vars = save.vars or {},
    playtime = save.playTime or save.playtime or { hours = 0, minutes = 0, seconds = 0 },
    options = save.options,
    pc = save.pc or { items = {} },
    registeredItem = save.registeredItem,
    move_overlay = save.move_overlay or {},
    trainerId = save.trainerId,
    rng = save.rng,
  }
  Options.ensure(session)
  return session
end

return Schema
