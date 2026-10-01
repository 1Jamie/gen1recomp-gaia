local K = require("tests.save_compat._codec")
local GenSave = require("src.save_convert.GenSave")
local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")
local Boxes = require("src.pokemon.Boxes")
local Party = require("src.pokemon.Party")
local Bag = require("src.inventory.Bag")

local R = {}

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local ALIASES = { EVENT_RECEIVED_BIKE_VOUCHER = true, EVENT_GOT_HM_FLASH = true }
local BADGES = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE",
  "VOLCANOBADGE", "EARTHBADGE" }
local STATUSES = { "PSN", "BRN", "FRZ", "PAR", "SLP" }

local function lcg(seed)
  local state = (seed * 2654435761 + 12345) % 4294967296
  local function nextInt()
    state = (state * 1664525 + 1013904223) % 4294967296
    return state
  end
  return function(lo, hi)
    if hi == nil then lo, hi = 1, lo end
    return lo + math.floor(nextInt() / 4294967296 * (hi - lo + 1))
  end
end

local function sortedKeys(t, filter)
  local out = {}
  for k, v in pairs(t) do
    if type(k) == "string" and type(v) == "table" and (not filter or filter(k, v)) then out[#out + 1] = k end
  end
  table.sort(out)
  return out
end

local pools = {}
local cacheApplied = {}
function R.data(version)
  local data = K.gen1Data(version)
  local dir = os.getenv("GEN1_" .. version:upper() .. "_CACHE")
  if dir and not cacheApplied[version] then
    cacheApplied[version] = true
    for _, name in ipairs({ "pokemon", "moves", "items", "maps", "field", "tilesets", "audio", "encounters" }) do
      local chunk = assert(loadfile(dir .. "/data/generated/" .. name .. ".lua"))
      data[name] = chunk()
    end
  end
  return data
end

local function poolFor(version)
  if pools[version] then return pools[version] end
  local data = R.data(version)
  local cw = GenSave.crosswalks(data)
  local pool = { data = data, cw = cw }
  pool.species = sortedKeys(data.pokemon, function(id, def) return cw.pokemonIndex[id] and def.index end)
  pool.moves = sortedKeys(data.moves, function(id) return cw.movesIndex[id] end)
  pool.items = sortedKeys(data.items, function(id)
    return cw.itemsIndex[id] and not id:match("BADGE$") and id ~= "COIN_CASE" and id ~= "COIN"
  end)
  pool.flags = {}
  for _, name in pairs(data.eventFlags.byBit) do
    if not ALIASES[name] and not name:match("^EVENT_CHOSE_") and not name:match("SAFARI")
        and name ~= "EVENT_GAVE_FOSSIL_TO_LAB" and name ~= "EVENT_GOT_STARTER" then
      pool.flags[#pool.flags + 1] = name
    end
  end
  table.sort(pool.flags)
  pool.maps = sortedKeys(data.maps, function(id, m) return m.sram and cw.mapsIndex[id] end)
  pool.towns = {}
  for _, row in ipairs(require("src.save_convert.data.blackout_maps")) do pool.towns[#pool.towns + 1] = row end
  pools[version] = pool
  return pool
end

local function name(rng, max)
  local t = {}
  for i = 1, rng(1, max or 7) do
    local k = rng(1, #LETTERS)
    t[i] = LETTERS:sub(k, k)
  end
  return table.concat(t)
end

local function randomMon(rng, pool, ownerName, ownerId, boxed)
  local data = pool.data
  local id = pool.species[rng(#pool.species)]
  local level = rng(2, 100)
  local mon = Pokemon.new(data, id, level, rng)
  local def = data.pokemon[id]
  local lo = Growth.expForLevel(def.growthRate, level)
  local hi = level >= 100 and lo or Growth.expForLevel(def.growthRate, level + 1) - 1
  mon.exp = rng(lo, math.max(lo, hi))
  mon.statExp = { hp = rng(0, 65535), attack = rng(0, 65535), defense = rng(0, 65535), speed = rng(0, 65535),
    special = rng(0, 65535) }
  mon.stats = Stats.calc(def, level, mon.dvs, mon.statExp)
  mon.hp = rng(0, 4) == 0 and 0 or rng(1, mon.stats.hp)
  mon.moves = {}
  local seen = {}
  for _ = 1, rng(1, 4) do
    local mid = pool.moves[rng(#pool.moves)]
    if not seen[mid] then
      seen[mid] = true
      local mdef = data.moves[mid]
      local ups = rng(0, 3)
      mon.moves[#mon.moves + 1] = { id = mid, pp = rng(0, math.min(63, (mdef.pp or 10))), ppUps = ups }
    end
  end
  if rng(1, 3) == 1 then
    local st = STATUSES[rng(#STATUSES)]
    mon.status = st
    if st == "SLP" then mon.sleepTurns = rng(1, 7) end
  end
  mon.catchRate = rng(1, 255)
  if rng(1, 3) == 1 then mon.nickname = name(rng, 10) end
  if rng(1, 4) == 1 then
    mon.traded = true
    mon.ot = name(rng, 7)
    mon.otId = rng(0, 65535)
  else
    mon.ot = ownerName
    mon.otId = ownerId
  end
  if boxed then
    mon.stats = nil
  end
  return mon
end

function R.build(seed, version)
  local pool = poolFor(version)
  local data, cw = pool.data, pool.cw
  local rng = lcg(seed)
  math.randomseed(seed)
  local save = SaveData.newGame({})
  save.version = version
  save.player.name = name(rng, 7)
  save.player.rival = name(rng, 7)
  save.player.id = rng(0, 65535)
  save.money = rng(0, 999999)
  save.coins = rng(0, 9999)
  save.options = { textSpeed = ({ 1, 3, 5 })[rng(3)], battleStyle = rng(2) == 1 and "set" or "shift", animations = rng(2) == 1 }

  save.party = {}
  for _ = 1, rng(1, 6) do Party.add(save.party, randomMon(rng, pool, save.player.name, save.player.id)) end
  save.boxes = nil
  Boxes.ensure(save)
  for b = 1, 12 do
    for _ = 1, rng(0, 20) do
      if rng(1, 3) ~= 1 then
        table.insert(save.boxes[b], randomMon(rng, pool, save.player.name, save.player.id, true))
      end
    end
  end
  save.currentBox = rng(1, 12)
  for _ = 1, rng(0, 6) do Boxes.deposit(save, randomMon(rng, pool, save.player.name, save.player.id, true)) end

  save.inventory = {}
  save.bagOrder = nil
  for _ = 1, rng(0, 20) do
    Bag.add(save, pool.items[rng(#pool.items)], rng(1, 40), data)
  end
  for _, b in ipairs(BADGES) do
    if rng(1, 2) == 1 then save.inventory[b] = 1 end
  end
  save.pcItems = {}
  local pcCount = 0
  for _ = 1, rng(0, 50) do
    local id = pool.items[rng(#pool.items)]
    if not save.pcItems[id] and pcCount < 50 then
      save.pcItems[id] = rng(1, 99)
      pcCount = pcCount + 1
    end
  end
  if rng(1, 2) == 1 then Bag.add(save, "COIN_CASE", 1, data) end

  save.pokedex = { seen = {}, owned = {} }
  for _, id in ipairs(pool.species) do
    if rng(1, 2) == 1 then
      save.pokedex.seen[id] = true
      if rng(1, 2) == 1 then save.pokedex.owned[id] = true end
    end
  end

  save.flags = {}
  for _ = 1, rng(0, 60) do save.flags[pool.flags[rng(#pool.flags)]] = true end
  if rng(1, 2) == 1 then
    save.flags.EVENT_GOT_STARTER = true
    local starters = version == "yellow" and { "PIKACHU" } or { "BULBASAUR", "CHARMANDER", "SQUIRTLE" }
    save.flags["EVENT_CHOSE_" .. starters[rng(#starters)]] = true
  end
  if version == "yellow" then save.rivalStarter = rng(0, 3) end
  if rng(1, 6) == 1 then
    save.flags.EVENT_RECEIVED_BIKE_VOUCHER = true
    save.flags.EVENT_GOT_BIKE_VOUCHER = true
  end

  save.hiddenTaken = {}
  for _, row in ipairs(data.hiddenItems) do
    if rng(1, 3) == 1 then save.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] = true end
  end
  for _, row in ipairs(require("src.save_convert.data.hidden_coins")) do
    if rng(1, 3) == 1 then save.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] = true end
  end

  save.visited = {}
  for idx = 0, 10 do
    local id = cw.mapsByIndex[idx]
    if id and rng(1, 2) == 1 then save.visited[id] = true end
  end

  local safariOn = rng(1, 4) == 1
  local forcedOn = not safariOn and rng(1, 4) == 1
  local mapId = pool.maps[rng(#pool.maps)]
  if safariOn then mapId = ({ "SAFARI_ZONE_CENTER", "SAFARI_ZONE_EAST", "SAFARI_ZONE_NORTH", "SAFARI_ZONE_WEST" })[rng(4)] end
  if forcedOn then mapId = "ROUTE_17" end
  local def = data.maps[mapId]
  save.player.map = mapId
  save.player.x = rng(0, def.width * 2 - 1)
  save.player.y = rng(0, def.height * 2 - 1)
  save.player.facing = ({ "up", "down", "left", "right" })[rng(4)]
  save.lastOutdoor = { id = pool.towns[rng(#pool.towns)][1] }
  local heal = pool.towns[rng(#pool.towns)]
  if rng(1, 2) == 1 then
    save.lastHeal = { map = heal[1], x = heal[2], y = heal[3] }
  else
    save.lastHeal = { map = heal[1] == "ROUTE_4" and "MT_MOON_POKECENTER" or "VIRIDIAN_POKECENTER", x = 3, y = 4,
      outdoor = { id = heal[1], x = heal[2], y = heal[3] } }
  end
  local ride = rng(3)
  if ride == 2 then save.onBike = true elseif ride == 3 then save.player.surfing = true end
  if forcedOn then save.onBike, save.player.surfing = true, nil end
  save.playTime = rng(0, 255 * 3600 - 1) + rng(0, 59) / 60

  if rng(1, 2) == 1 then
    save.hallOfFame = {}
    for t = 1, rng(1, 8) do
      local team = {}
      for _ = 1, rng(1, 6) do
        local team1 = { species = pool.species[rng(#pool.species)], level = rng(1, 100) }
        if rng(1, 3) == 1 then team1.nickname = name(rng, 10) end
        team[#team + 1] = team1
      end
      save.hallOfFame[t] = team
    end
  end

  if safariOn then save.safari = { balls = rng(1, 30), steps = rng(1, 502) } end
  if rng(1, 3) == 1 then
    local mon = randomMon(rng, pool, save.player.name, save.player.id, true)
    save.daycare = { mon = mon, steps = rng(0, 200), depositLevel = mon.level }
  end
  if forcedOn then save.forcedBike = true end
  if rng(1, 2) == 1 then save.usedPokecenter = true end
  if rng(1, 3) == 1 then save.trashPuzzle = { first = rng(0, 7) * 2, second = rng(0, 14) } end
  if rng(1, 4) == 1 then
    save.labFossilMon = ({ "KABUTO", "OMANYTE", "AERODACTYL" })[rng(3)]
    save.flags.EVENT_GAVE_FOSSIL_TO_LAB = true
  end
  local dark = data.field.darkMaps and data.field.darkMaps.maps or {}
  for _, id in ipairs(dark) do if id == mapId and rng(1, 2) == 1 then save.flashLit = true end end
  if version == "yellow" then
    save.pikachuHappiness = rng(0, 255)
    save.pikachuMood = rng(0, 255)
    if rng(1, 2) == 1 then save.pikachuEmotionModifier = rng(1, 255) end
    if rng(1, 2) == 1 then save.surfingHighScore = rng(1, 9999) end
  end
  return save
end

return R
