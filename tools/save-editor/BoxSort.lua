local Gen = require("Gen")

local M = {}

M.MODES = {
  { id = "livingdex", label = "Living Dex order", icon = "book-open", done = "in Living Dex order" },
  { id = "species", label = "Species, then level", icon = "list-filter", done = "by species and level" },
  { id = "level", label = "Level, high to low", icon = "arrow-up-down", done = "by level" },
  { id = "compact", label = "Remove gaps", icon = "chevrons-up", done = "without gaps" },
}

local DONE = {}
for _, mode in ipairs(M.MODES) do DONE[mode.id] = mode.done end

local function isEgg(mon)
  return mon.isEgg == true or mon.egg == true
end

function M.dexNumber(S, mon)
  local species = mon.species or mon.speciesId
  if mon.speciesNumbering == "national" then
    return tonumber(species)
  end
  local pokemon = S.data and S.data.pokemon
  local def = pokemon and species ~= nil and pokemon[species]
  local dex = def and tonumber(def.dex or def.national)
  if dex then return dex end
  if Gen.ofState(S) == 3 then
    local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
    if ok and Pokemon and Pokemon.national then
      local okN, n = pcall(Pokemon.national, species)
      if okN and tonumber(n) then return tonumber(n) end
    end
  end
  return nil
end

local function collect(S, boxes, count, capacity)
  local entries = {}
  for b = 1, count do
    local box = boxes[b] or {}
    for slot = 1, math.max(capacity, #box) do
      local mon = box[slot]
      if type(mon) == "table" then
        local egg = isEgg(mon)
        entries[#entries + 1] = {
          mon = mon,
          order = #entries + 1,
          egg = egg,
          dex = not egg and M.dexNumber(S, mon) or nil,
          level = tonumber(mon.level) or 0,
        }
      end
    end
  end
  return entries
end

local function group(e)
  if e.egg then return 3 end
  if not e.dex then return 2 end
  return 1
end

local COMPARE = {
  species = function(a, b)
    if a.dex ~= b.dex then return a.dex < b.dex end
    if a.level ~= b.level then return a.level > b.level end
  end,
  level = function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    if a.dex ~= b.dex then return a.dex < b.dex end
  end,
}

local function sortEntries(list, mode)
  local cmp = COMPARE[mode]
  table.sort(list, function(a, b)
    local ga, gb = group(a), group(b)
    if ga ~= gb then return ga < gb end
    if ga == 1 and cmp then
      local r = cmp(a, b)
      if r ~= nil then return r end
    end
    return a.order < b.order
  end)
end

function M.plan(S, mode, boxes, count, capacity)
  local entries = collect(S, boxes, count, capacity)
  local total = count * capacity
  if #entries > total then return nil, "Not enough box space" end
  local slots = {}
  if mode == "compact" then
    for i, e in ipairs(entries) do slots[i] = e.mon end
    return slots, #entries
  end
  if mode ~= "livingdex" then
    sortEntries(entries, mode)
    for i, e in ipairs(entries) do slots[i] = e.mon end
    return slots, #entries
  end
  local firsts, rest, seen = {}, {}, {}
  for _, e in ipairs(entries) do
    if e.dex and not seen[e.dex] then
      seen[e.dex] = true
      firsts[#firsts + 1] = e
    else
      rest[#rest + 1] = e
    end
  end
  sortEntries(firsts, "species")
  sortEntries(rest, "species")
  if Gen.ofState(S) ~= 3 then
    local i = 0
    for _, e in ipairs(firsts) do i = i + 1; slots[i] = e.mon end
    for _, e in ipairs(rest) do i = i + 1; slots[i] = e.mon end
    return slots, i
  end
  local spill, top = {}, 0
  for _, e in ipairs(firsts) do
    if e.dex >= 1 and e.dex <= total and e.dex == math.floor(e.dex) then
      slots[e.dex] = e.mon
      top = math.max(top, e.dex)
    else
      spill[#spill + 1] = e
    end
  end
  for _, e in ipairs(rest) do spill[#spill + 1] = e end
  local cursor = top
  for _, e in ipairs(spill) do
    local placed = false
    for step = 1, total do
      local at = (cursor + step - 1) % total + 1
      if slots[at] == nil then
        slots[at] = e.mon
        cursor = at
        placed = true
        break
      end
    end
    if not placed then return nil, "Not enough box space" end
  end
  return slots, #entries
end

local function locate(boxes, count, capacity, mon)
  for b = 1, count do
    for slot = 1, capacity do
      if boxes[b][slot] == mon then return b, slot end
    end
  end
end

function M.apply(S, Ops, mode)
  if not DONE[mode] then return Ops.say(S, "Unknown box sort") end
  local boxes = Ops.boxes(S)
  local count, capacity = Ops.boxCount(S), Ops.boxCapacity(S)
  local slots, n = M.plan(S, mode, boxes, count, capacity)
  if not slots then return Ops.say(S, n) end
  if n == 0 then return Ops.say(S, "The boxes are empty", "info") end
  local changed = false
  for b = 1, count do
    local box = boxes[b]
    for slot = 1, capacity do
      if box[slot] ~= slots[(b - 1) * capacity + slot] then changed = true end
    end
  end
  if not changed then
    return Ops.say(S, "Boxes are already sorted " .. DONE[mode], "info")
  end
  for b = 1, count do
    local box = boxes[b]
    for slot = math.max(capacity, #box), 1, -1 do box[slot] = nil end
    for slot = 1, capacity do
      box[slot] = slots[(b - 1) * capacity + slot]
    end
  end
  local b, slot = nil, nil
  if S.editingMon then b, slot = locate(boxes, count, capacity, S.editingMon) end
  S.selectedBoxSlot = b == S.selectedBox and slot or 1
  return Ops.mark(S, ("Sorted %d Pokemon %s"):format(n, DONE[mode]))
end

return M
