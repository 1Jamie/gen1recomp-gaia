local Gen = require("Gen")
local Ops = require("Ops")
local History = require("History")
local GameVersion = require("src.core.GameVersion")
local Pokeblock = require("src.core.game3.rse.pokeblock")

local P = {}

P.COUNT = Pokeblock.COUNT
P.FIELDS = Pokeblock.FIELDS
P.FLAVORS = Pokeblock.FLAVORS
P.MAX_BYTE = 255
P.FIRST_COLOR = Pokeblock.COLOR.RED
P.LAST_COLOR = Pokeblock.COLOR.GOLD

local function titleCase(key)
  return (key:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

P.COLOR_NAMES = {}
for key, id in pairs(Pokeblock.COLOR) do
  if id ~= Pokeblock.COLOR.NONE then P.COLOR_NAMES[id] = titleCase(key) end
end

P.FIELD_NAMES = { spicy = "Spicy", dry = "Dry", sweet = "Sweet", bitter = "Bitter", sour = "Sour", feel = "Feel" }

function P.has(save, version)
  if type(save) ~= "table" or Gen.of(save, version) ~= 3 then return false end
  return GameVersion.layout(Gen.versionOf(save, version)) == "rse"
end

function P.colorName(color)
  return P.COLOR_NAMES[tonumber(color)] or ("Color " .. tostring(color))
end

function P.colorOptions()
  local out = {}
  for id = P.FIRST_COLOR, P.LAST_COLOR do out[#out + 1] = { id, P.COLOR_NAMES[id] } end
  return out
end

local function byte(v)
  local n = tonumber(v)
  if not n or n ~= n or n ~= math.floor(n) or n < 0 or n > P.MAX_BYTE then return nil end
  return n
end

function P.block(save, slot)
  local list = type(save) == "table" and type(save.pokeblocks) == "table" and save.pokeblocks or nil
  local b = list and list[slot]
  local out = Pokeblock.empty()
  if type(b) == "table" then
    for _, k in ipairs(P.FIELDS) do out[k] = tonumber(b[k]) or 0 end
  end
  return out
end

function P.isEmpty(save, slot)
  return P.block(save, slot).color == Pokeblock.COLOR.NONE
end

function P.count(save)
  local n = 0
  for i = 1, P.COUNT do
    if not P.isEmpty(save, i) then n = n + 1 end
  end
  return n
end

-- pokeemerald/src/pokeblock.c:1346
function P.firstFree(save)
  for i = 1, P.COUNT do
    if P.isEmpty(save, i) then return i end
  end
  return nil
end

local function slotOf(slot)
  local n = tonumber(slot)
  if not n or n ~= math.floor(n) or n < 1 or n > P.COUNT then return nil end
  return n
end

local function list(S)
  local save = S.save
  if save.pokeblocks ~= nil and type(save.pokeblocks) ~= "table" then return nil end
  save.pokeblocks = save.pokeblocks or {}
  local l = save.pokeblocks
  for i = 1, P.COUNT do
    if type(l[i]) ~= "table" then l[i] = Pokeblock.empty() end
  end
  return l
end

local function gate(S)
  if not P.has(S.save, S.version) then
    return Ops.say(S, "Pokéblocks are only in Ruby, Sapphire and Emerald")
  end
  if S.save.pokeblocks ~= nil and type(S.save.pokeblocks) ~= "table" then
    return Ops.say(S, "Invalid Pokéblock case state")
  end
  return true
end

local function recorded(fn)
  return function(S, ...)
    if S._historyDepth then return fn(S, ...) end
    local before = History.capture(S)
    local revision = S.revision or 0
    S._historyDepth = true
    local ok, result = pcall(fn, S, ...)
    S._historyDepth = nil
    if not ok then error(result, 0) end
    if (S.revision or 0) ~= revision then History.record(S, before) end
    return result
  end
end

P.set = recorded(function(S, slot, field, value)
  if not gate(S) then return false end
  slot = slotOf(slot)
  if not slot then return Ops.say(S, "Pokéblock slot must be 1 to " .. P.COUNT) end
  if P.isEmpty(S.save, slot) then return Ops.say(S, "That Pokéblock slot is empty") end
  local n = byte(value)
  if field == "color" then
    if not n or n < P.FIRST_COLOR or n > P.LAST_COLOR then
      return Ops.say(S, "Pokéblock color must be one of the 14 game colors")
    end
  elseif P.FIELD_NAMES[field] then
    if not n then return Ops.say(S, P.FIELD_NAMES[field] .. " must be a whole number from 0 to 255") end
  else
    return Ops.say(S, "Unknown Pokéblock field")
  end
  if P.block(S.save, slot)[field] == n then return true end
  list(S)[slot][field] = n
  return Ops.mark(S, "Pokéblock " .. slot .. " updated")
end)

P.add = recorded(function(S, slot, block)
  if not gate(S) then return false end
  if slot ~= nil then
    slot = slotOf(slot)
    if not slot then return Ops.say(S, "Pokéblock slot must be 1 to " .. P.COUNT) end
    if not P.isEmpty(S.save, slot) then return Ops.say(S, "That Pokéblock slot is taken") end
  else
    slot = P.firstFree(S.save)
    if not slot then return Ops.say(S, "The Pokéblock Case is full") end
  end
  local b = Pokeblock.empty()
  b.color = P.FIRST_COLOR
  if type(block) == "table" then
    for _, k in ipairs(P.FIELDS) do
      if block[k] ~= nil then
        local n = byte(block[k])
        if not n or (k == "color" and (n < P.FIRST_COLOR or n > P.LAST_COLOR)) then
          return Ops.say(S, "Invalid Pokéblock " .. k)
        end
        b[k] = n
      end
    end
  end
  list(S)[slot] = b
  S.pokeblockSlot = slot
  return Ops.mark(S, "Pokéblock added to slot " .. slot)
end)

-- pokeemerald/src/pokeblock.c:1374
P.clear = recorded(function(S, slot)
  if not gate(S) then return false end
  slot = slotOf(slot)
  if not slot then return Ops.say(S, "Pokéblock slot must be 1 to " .. P.COUNT) end
  if P.isEmpty(S.save, slot) then return Ops.say(S, "That Pokéblock slot is already empty") end
  list(S)[slot] = Pokeblock.empty()
  return Ops.mark(S, "Pokéblock " .. slot .. " deleted")
end)

return P
