package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local Ref = require("tests.save_compat._gen2_reference")

local ITEM_INDEX = {}
for id, def in pairs(K.gen2Data.items) do ITEM_INDEX[id] = def.index end
local function itemIndex(id)
  if id == nil then return 0 end
  if type(id) == "number" then return id end
  return ITEM_INDEX[id] or -1
end

local function sameMon(label, m, r, party)
  eq(m.species, r.species, label .. " species")
  eq(m.isEgg == true, r.listed == 0xFD, label .. " egg marker")
  if r.listed == 0xFD then
    eq(m.eggSteps, r.friendship, label .. " hatch counter")
  else
    eq(m.happiness, r.friendship, label .. " happiness")
  end
  eq(m.level, r.level, label .. " level")
  eq(m.experience, r.exp, label .. " exp")
  eq(m.otId, r.otId, label .. " OT id")
  eq(m.dvs.attack, r.dvAtk, label .. " atk DV")
  eq(m.dvs.defense, r.dvDef, label .. " def DV")
  eq(m.dvs.speed, r.dvSpe, label .. " spe DV")
  eq(m.dvs.special, r.dvSpc, label .. " spc DV")
  eq(itemIndex(m.item), r.item, label .. " item")
  eq(m.pokerus, r.pokerus, label .. " pokerus")
  local moves = {}
  for _, mv in ipairs(r.moves) do if mv ~= 0 then moves[#moves + 1] = mv end end
  eq(#m.moves, #moves, label .. " move count")
  for i, mv in ipairs(moves) do eq(m.moves[i] and m.moves[i].id, mv, label .. " move " .. i) end
  if not r.nick:find("<", 1, true) then eq(m.nickname, r.nick, label .. " nickname") end
  if not r.ot:find("<", 1, true) then eq(m.ot, r.ot, label .. " OT") end
  if party then
    eq(m.hp, r.hp, label .. " hp")
    eq(m.maxHp, r.maxHp, label .. " max hp")
  end
end

local function bagOf(r)
  local order, totals, seen = {}, {}, {}
  for _, pocketRows in ipairs({ r.items, r.keys, r.balls }) do
    for _, row in ipairs(pocketRows) do
      if not seen[row[1]] then seen[row[1]] = true; order[#order + 1] = row[1] end
      totals[row[1]] = (totals[row[1]] or 0) + row[2]
    end
  end
  return order, totals
end

local function agree(label, save, r, version)
  eq(save.player.id, r.id, label .. ": trainer id")
  if not r.name:find("<", 1, true) then eq(save.player.name, r.name, label .. ": player name") end
  if not r.rival:find("<", 1, true) then eq(save.rival.name, r.rival, label .. ": rival name") end
  eq(save.player.money, r.money, label .. ": money")
  local johto, kanto = 0, 0
  for i, name in ipairs({ "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING" }) do
    if save.player.badges[name] then johto = johto + 2 ^ (i - 1) end
  end
  for i, name in ipairs({ "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }) do
    if save.player.kantoBadges[name] then kanto = kanto + 2 ^ (i - 1) end
  end
  eq(johto, r.johto, label .. ": johto badges")
  eq(kanto, r.kanto, label .. ": kanto badges")
  eq(save.currentBox, r.curBox, label .. ": current box")
  eq(save.playTime.hours, r.hours, label .. ": hours")
  eq(save.playTime.minutes, r.minutes, label .. ": minutes")
  eq(save.playTime.seconds, r.seconds, label .. ": seconds")
  eq(save.playTime.frames, r.frames, label .. ": frames")
  if version == "crystal" then eq(save.player.gender == "female", r.female, label .. ": gender") end
  eq(#save.party, r.party.count, label .. ": party count")
  for i, rm in ipairs(r.party.mons) do sameMon(("%s: party %d"):format(label, i), save.party[i], rm, true) end
  for b = 1, 14 do
    eq(#save.boxes[b], r.boxes[b].count, ("%s: box %d count"):format(label, b))
    for i, rm in ipairs(r.boxes[b].mons) do
      sameMon(("%s: box %d slot %d"):format(label, b, i), save.boxes[b][i], rm, false)
    end
    if not r.boxNames[b]:find("<", 1, true) then
      eq(save.boxNames[b], r.boxNames[b], ("%s: box %d name"):format(label, b))
    end
  end
  local order, totals = bagOf(r)
  local got = {}
  for _, id in ipairs(save.bagOrder) do
    local n = itemIndex(id)
    if totals[n] then got[#got + 1] = n end
  end
  eq(table.concat(got, ","), table.concat(order, ","), label .. ": bag order")
  for n, total in pairs(totals) do
    local found
    for id, count in pairs(save.inventory) do if itemIndex(id) == n then found = count end end
    eq(found, total, ("%s: bag total for item 0x%02X"):format(label, n))
  end
  local pcTotals = {}
  for _, row in ipairs(r.pc) do pcTotals[row[1]] = (pcTotals[row[1]] or 0) + row[2] end
  for n, total in pairs(pcTotals) do
    local found
    for id, count in pairs(save.pcItems) do if itemIndex(id) == n then found = count end end
    eq(found, total, ("%s: PC total for item 0x%02X"):format(label, n))
  end
  local caught, seen = 0, 0
  for _ in pairs(save.pokedex.caught) do caught = caught + 1 end
  for _ in pairs(save.pokedex.seen) do seen = seen + 1 end
  eq(caught, r.caught, label .. ": dex caught")
  eq(seen, r.seen, label .. ": dex seen")
  for i = 0, 255 do
    if save.events[i] ~= r.events[i] then
      eq(save.events[i], r.events[i], ("%s: event byte %d"):format(label, i))
      break
    end
  end
end

local function sameRef(label, a, b)
  local function flat(v, path, out)
    if type(v) ~= "table" then out[path] = tostring(v) return end
    for k, x in pairs(v) do flat(x, path .. "." .. tostring(k), out) end
  end
  local fa, fb = {}, {}
  flat(a, "", fa)
  flat(b, "", fb)
  local bad = 0
  for k, v in pairs(fa) do
    if k ~= ".checksum1" and k ~= ".checksum2" and fb[k] ~= v then
      bad = bad + 1
      if bad <= 3 then eq(fb[k], v, label .. " " .. k) end
    end
  end
  eq(bad, 0, label .. ": every field the reference decoder reads is unchanged")
end

local function aggregated(r)
  local out = {}
  for k, v in pairs(r) do out[k] = v end
  for _, key in ipairs({ "items", "keys", "balls", "pc" }) do
    local order, totals = {}, {}
    for _, row in ipairs(r[key]) do
      if not totals[row[1]] then order[#order + 1] = row[1]; totals[row[1]] = 0 end
      totals[row[1]] = totals[row[1]] + row[2]
    end
    local rows = {}
    for _, id in ipairs(order) do rows[#rows + 1] = { id, totals[id] } end
    out[key] = rows
  end
  return out
end

local cases = 0
for _, c in ipairs(G2.cases()) do
  if not c.refuse then
    cases = cases + 1
    local src = Ref.decode(c.bytes, c.version)
    local save = K.import(2, c.version, c.bytes)
    check(save ~= nil, c.id .. ": imports")
    if save then
      agree(c.id .. " import", save, src, c.version)
      local r1 = K.export(2, c.version, save, c.bytes)
      local fresh = K.export(2, c.version, assert(K.import(2, c.version, c.bytes)), false)
      for label, out in pairs({ r1 = r1, fresh = fresh }) do
        check(out ~= nil, c.id .. " " .. label .. ": exports")
        if out then
          local ref = Ref.decode(out, c.version)
          eq(ref.checksum1, true, c.id .. " " .. label .. ": the reference finds checksum 1 valid")
          eq(ref.checksum2, true, c.id .. " " .. label .. ": and checksum 2")
          if label == "r1" then
            sameRef(c.id .. " r1", src, ref)
          else
            sameRef(c.id .. " fresh", aggregated(src), aggregated(ref))
          end
          agree(c.id .. " " .. label .. " reimport", assert(K.import(2, c.version, out)), ref, c.version)
        end
      end
    end
  end
end
check(cases >= 50, "every Gen 2 fixture went through the reference decoder")

T.finish()
