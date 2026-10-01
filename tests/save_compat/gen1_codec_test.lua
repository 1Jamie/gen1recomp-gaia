package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_codec skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local SaveConvert = require("src.save_convert.SaveConvert")
local GenSave = require("src.save_convert.GenSave")
local Compat = require("src.save_convert.Compat")
local Ref = require("tests.save_compat._gen1_reference")
local G1 = require("tests.fixtures.save.gen1_build")
local B = require("tests.fixtures.save.bytes")

local O = GenSave.OFFSETS
local cases = G1.cases()
local byId = {}
for _, c in ipairs(cases) do byId[c.id] = c end

local function import(id)
  local c = byId[id]
  return assert(K.import(1, c.version, c.bytes)), c
end

local function patchByte(s, off, v)
  return s:sub(1, off) .. string.char(v) .. s:sub(off + 2)
end

local function reseal(s)
  local sum = 0
  for i = O.checksumStart + 1, O.checksumEnd do sum = (sum + s:byte(i)) % 256 end
  return patchByte(s, O.mainChecksum, 255 - sum)
end

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

local function first(list, n)
  local out = {}
  for i = 1, math.min(#list, n or 3) do out[i] = list[i] end
  return table.concat(out, "; ")
end

for _, c in ipairs(cases) do
  if not c.refuse then
    local save = assert(K.import(1, c.version, c.bytes), c.id)
    local want = Ref.decode(c.bytes)
    local out, xerr = K.export(1, c.version, deepCopy(save))
    if c.id == "g1.red.box_index_invalid" then
      check(out == nil and tostring(xerr):find("currentBoxIndex"), c.id .. ": the Compat gate refuses the export")
    else
    assert(out, xerr)
    local diffs = Ref.compare(want, Ref.decode(out))
    eq(#diffs, 0, c.id .. ": reference decode of the templated export matches -- " .. first(diffs))
    local bare = deepCopy(save)
    local outB, err = K.export(1, c.version, bare, false)
    check(outB ~= nil, c.id .. ": templateless export -- " .. tostring(err))
    if outB then
      local skip = {}
      if c.id:match("saved_once") then skip[1] = "^%.boxByte: " end
      if c.id:match("all_trades") then skip[1] = "^%.tradeFlags: " end
      if c.id == "g1.red.safari_stale_balls" then skip = { "^%.safariBalls: ", "^%.safariSteps: " } end
      if c.id == "g1.red.fossil_stale" then skip[1] = "^%.fossil: " end
      if c.id == "g1.red.forced_bike" or c.id == "g1.red.used_pokecenter" or c.id == "g1.red.beat_gym_mismatch" then
        skip[1] = "^%.statusFlags: "
      end
      local d2 = Ref.compare(want, Ref.decode(outB), skip)
      eq(#d2, 0, c.id .. ": reference decode of the templateless export matches -- " .. first(d2))
      local cw = GenSave.crosswalks(K.gen1Data(c.version))
      eq(save.player.id, want.playerId, c.id .. ": codec and reference agree on the trainer id")
      eq(save.money, want.money, c.id .. ": money")
      eq(#save.party, want.party.count, c.id .. ": party size")
      for i, m in ipairs(save.party) do
        if m.cartRaw then
          eq(m.cartRaw:sub(1, 2), ("%02X"):format(want.party[i].species), c.id .. ": carrier keeps its species byte")
        else
          eq(cw.pokemonIndex[m.species], want.party[i].species, ("%s: party %d species"):format(c.id, i))
          eq(m.level, want.party[i].level, ("%s: party %d level"):format(c.id, i))
          eq(m.exp, want.party[i].exp, ("%s: party %d exp"):format(c.id, i))
        end
      end
      eq(#(save.hallOfFame or {}), #want.hof, c.id .. ": Hall of Fame team count")
      eq(math.floor(save.playTime / 3600), tonumber(want.playTime:sub(1, 2), 16), c.id .. ": play time hours")
    end
    end
  end
end

do
  local yellow = require("src.save_convert.data.toggle_objects_yellow")
  local red = require("src.save_convert.data.toggle_objects")
  eq(yellow.count, 236, "pokeyellow has 236 toggleable object rows")
  eq(yellow.byBit[3] and yellow.byBit[3][2], "VIRIDIANCITY_OLD_MAN2", "Yellow bit 3 is the second Viridian old man")
  check(red.byBit[3][2] ~= "VIRIDIANCITY_OLD_MAN2", "Red bit 3 is not")
  local data = SaveConvert.loadData("yellow")
  check(data.toggleObjects == yellow, "loadData(yellow) selects the Yellow toggle table")
  check(SaveConvert.loadData("red").toggleObjects == red, "loadData(red) keeps the Red table")
  local save = import("g1.yellow.toggles")
  for _, bitIdx in ipairs({ 1, 3, 63, 64, 74, 96, 97, 152, 153, 235 }) do
    local e = yellow.byBit[bitIdx]
    if e then
      eq(save.objectToggles[e[1]][e[2]], false, ("Yellow bit %d hides %s"):format(bitIdx, e[2]))
    end
  end
  local asm = io.open("../pokeyellow/data/maps/toggleable_objects.asm", "r")
  if asm then
    local text = asm:read("*a")
    asm:close()
    local bitIdx, mismatches = 0, 0
    for line in text:match("ToggleableObjectStates:(.*)$"):gmatch("[^\n]+") do
      local obj = line:gsub(";.*", ""):match("^%s*toggle_object_state%s+([^,%s]+)")
      if obj then
        local e = yellow.byBit[bitIdx]
        if e and e[2] ~= obj then mismatches = mismatches + 1 end
        bitIdx = bitIdx + 1
      end
    end
    eq(bitIdx, yellow.count, "the Yellow table has one bit per pokeyellow row")
    eq(mismatches, 0, "every Yellow table row names the pokeyellow object at that bit")
  end
end

do
  local save, c = import("g1.yellow.all_trades")
  local yellowTrades = require("src.save_convert.data.trade_flags_yellow")
  for _, name in pairs(yellowTrades) do check(save.flags[name], "Yellow trade flag " .. name) end
  check(not save.flags.EVENT_TRADED_SPEAROW_FOR_FARFETCHD, "Yellow slot 4 is unused, not a Red trade")
  save.flags.EVENT_TRADED_ABRA_FOR_MR_MIME = nil
  local out = assert(K.export(1, "yellow", save))
  eq(out:byte(O.tradeFlags + 1), 0xFD, "clearing a Yellow trade clears only its bit")
  eq(out:byte(O.tradeFlags + 2), 0x03, "the second trade byte is untouched")
  local red = import("g1.red.all_trades")
  check(red.flags.EVENT_TRADED_SPEAROW_FOR_FARFETCHD, "Red slot 4 is DUX")
  check(c.version == "yellow", "fixture is Yellow")
end

do
  local save = import("g1.red.unnamed_events")
  check(save.flagsRaw ~= nil, "unnamed event bits are carried in flagsRaw")
  check(save.flags.EVENT_FOLLOWED_OAK_INTO_LAB, "bit 0 is a named flag")
  save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = nil
  save.rawImport = nil
  local out = assert(K.export(1, "red", save, false))
  eq(out:byte(O.eventFlags + 1), 0x8E, "bit 0 cleared; unnamed bits 1, 2, 7 and named bit 3 kept")
  eq(out:byte(O.eventFlags + 320), 0x80, "unnamed bit 2559 survives a templateless export")
end

do
  local data = K.gen1Data("red")
  local headers = data.trainerHeaders and data.trainerHeaders.PewterGym
  local event = headers and headers[2] and headers[2].event
  if event then
    local save = import("g1.red.basic")
    save.defeatedTrainers = { PEWTER_GYM_obj_2 = true }
    local out = assert(K.export(1, "red", save))
    local back = assert(K.import(1, "red", out))
    check(back.flags[event], "a beaten trainer exports its " .. event .. " bit")
    check(back.defeatedTrainers.PEWTER_GYM_obj_2, "and imports back as defeatedTrainers")
  end
end

do
  local c = byId["g1.red.glitch_species_party"]
  local save = import("g1.red.glitch_species_party")
  local carrier = save.party[2]
  check(carrier.cartRaw ~= nil and carrier.species == nil, "an unknown species imports as a raw carrier")
  table.remove(save.party, 2)
  save.orphaned = { mons = { carrier }, items = {} }
  local out = assert(K.export(1, "red", save))
  check(out == c.bytes, "the quarantined carrier is written back into party slot 2 byte for byte")
  local box = import("g1.red.glitch_species_box")
  check(box.boxes[1][1].cartRaw ~= nil, "a glitch box mon is a carrier too")
  local mv = import("g1.red.unknown_move")
  check(mv.party[1].cartRaw ~= nil, "an unknown move index keeps the whole mon raw")
  local pc = import("g1.red.unknown_pc_item")
  check(pc.cartPc ~= nil, "an unknown PC item keeps the raw item rows")
  pc.pcItems.POTION = 9
  local out2 = assert(K.export(1, "red", pc))
  local found = false
  for i = 0, 49 do
    local id = out2:byte(O.pcItems + i * 2 + 1)
    if id == 0xFF then break end
    if id == 0xFB then found = true end
  end
  check(found, "an edited PC still carries the unknown item row")
  for _, bad in ipairs({ { species = "NOT_A_MON", level = 5 } }) do
    local s = import("g1.red.basic")
    s.party[1] = bad
    local bytes, err = SaveConvert.exportSav(s, "red")
    check(bytes == nil and tostring(err):find("species index"), "an unmappable species refuses the export: " .. tostring(err))
  end
end

do
  local save = import("g1.red.basic")
  save.inventory.POTION = 150
  save.bagOrder = { "POTION" }
  save.rawImport = nil
  local out = assert(K.export(1, "red", save, false))
  eq(out:sub(O.bagItems + 1, O.bagItems + 4), string.char(0x14, 99, 0x14, 51), "150 POTIONs write two stacks")
  local back = assert(K.import(1, "red", out))
  eq(back.inventory.POTION, 150, "and import back as 150")
  local dup = import("g1.red.duplicate_stacks")
  eq(dup.inventory.POTION, 149, "duplicate rows fold into one count")
  check(dup.cartBag ~= nil, "the raw rows are kept for the round trip")
end

do
  local save = import("g1.red.saved_once")
  local n = 0
  for b = 1, 12 do n = n + #save.boxes[b] end
  eq(n, 0, "0xFF bank junk does not import as mons")
  local withBox = import("g1.red.saved_once_box")
  eq(#withBox.boxes[1], 5, "the current box comes from sCurBoxData")
  withBox.boxes[3] = { withBox.boxes[1][1] }
  local out = assert(K.export(1, "red", withBox))
  check(out:byte(O.currentBoxNum + 1) >= 0x80, "writing another box sets BIT_HAS_CHANGED_BOXES")
  eq(out:byte(O.box1 + 1), 0, "the current box's bank slot is marked empty")
  eq(out:byte(O.box1 + 2), 0xFF, "with its list terminated")
  local back = assert(K.import(1, "red", out))
  eq(#back.boxes[3], 1, "the deposited mon reads back from bank 2")
  eq(#back.boxes[1], 5, "the current box still reads back")
  eq(#Compat.check(out, "red").errors, 0, "the export is a valid cart: " .. Compat.describe(Compat.check(out, "red")))
end

do
  local save = import("g1.red.hof_overflow")
  eq(#save.hallOfFame, 50, "50 stored teams")
  eq(save.hallOfFameTotal, 120, "wNumHoFTeams 120 survives")
  local Screens = require("src.ui.Screens")
  local oldPush = Screens.push
  Screens.push = function() end
  local induction = coroutine.create(function()
    require("src.script.Commands").record_hall_of_fame({
      save = save, game = {}, runner = { yield = coroutine.yield },
    })
  end)
  local ok, err = coroutine.resume(induction)
  Screens.push = oldPush
  check(ok, "the in-engine Hall of Fame induction starts: " .. tostring(err))
  eq(#save.hallOfFame, 51, "an in-engine induction appends the new team")
  for _, template in ipairs({ true, false }) do
    local advanced = deepCopy(save)
    if not template then advanced.rawImport = nil end
    local out = assert(K.export(1, "red", advanced))
    eq(out:byte(O.numHoFTeams + 1), 121, "an in-engine induction advances the imported total with template " .. tostring(template))
    local back = assert(K.import(1, "red", out))
    eq(#back.hallOfFame, 50, "the inducted export still stores only the last 50 teams")
    eq(back.hallOfFame[50][1].species, save.party[1].species, "the newest induction is the final stored team")
    eq(back.hallOfFame[50][1].level, save.party[1].level, "the newest induction keeps its level")
  end
  save.hallOfFameTotal = 255
  eq(assert(K.export(1, "red", save)):byte(O.numHoFTeams + 1), 255, "an induction at 255 wins saturates the cart count")
  local s = import("g1.red.basic")
  s.hallOfFame = {}
  for t = 1, 60 do s.hallOfFame[t] = { { species = "MEW", level = t } } end
  s.rawImport = nil
  local out = assert(K.export(1, "red", s, false))
  eq(out:byte(O.numHoFTeams + 1), 60, "60 teams counted")
  eq(out:byte(O.hallOfFame + 2), 11, "the oldest stored team is team 11")
  eq(out:byte(O.hallOfFame + 49 * 96 + 2), 60, "the newest is last")
  eq(out:byte(O.hallOfFame + 49 * 96 + 16 + 1), 0xFF, "a one-mon team is terminated")
end

do
  local save = import("g1.red.blackout_viridian")
  eq(save.lastHeal.map, "VIRIDIAN_CITY", "wLastBlackoutMap imports as the heal town")
  save.lastHeal = { map = "VIRIDIAN_POKECENTER", x = 3, y = 3, outdoor = { id = "PEWTER_CITY", x = 1, y = 1 } }
  local out = assert(K.export(1, "red", save))
  local cw = GenSave.crosswalks(K.gen1Data("red"))
  eq(out:byte(O.lastBlackoutMap + 1), cw.mapsIndex.PEWTER_CITY, "a Pokemon Center heal exports its town")
  check(import("g1.red.surfing").player.surfing, "wWalkBikeSurfState 2 imports surfing")
  check(import("g1.red.biking").onBike, "wWalkBikeSurfState 1 imports the bike")
  local s = import("g1.red.basic")
  s.player.surfing = true
  eq(assert(K.export(1, "red", s)):byte(O.walkBikeSurf + 1), 2, "surfing exports state 2")
end

do
  local s = import("g1.red.basic")
  s.player.name = "ABCDEFGHIJ"
  s.party[1].otId = nil
  s.party[2] = { species = "PIDGEY", level = 3, moves = {}, traded = true, ot = "JOE" }
  local out = assert(K.export(1, "red", s))
  local back = assert(K.import(1, "red", out))
  eq(back.player.name, "ABCDEFG", "player names stop at 7 characters")
  eq(back.party[1].otId, s.player.id, "an engine mon with no OT id takes the player's")
  eq(back.party[2].otId, 0, "a traded mon with no OT id does not")
end

do
  local s = import("g1.red.basic")
  local raw = patchByte(byId["g1.red.basic"].bytes, O.playerName + 1, 0x01)
  raw = reseal(raw)
  local save = assert(K.import(1, "red", raw))
  check(save.player.name:find("<$01>", 1, true), "an unmapped name byte imports as a token: " .. save.player.name)
  save.rawImport = nil
  local out = assert(K.export(1, "red", save, false))
  eq(out:byte(O.playerName + 2), 0x01, "and exports as the same byte")
  check(s ~= nil, "basic imports")
end

do
  local s = import("g1.red.basic")
  s.playTime = 300 * 3600
  local back = assert(K.import(1, "red", assert(K.export(1, "red", s))))
  eq(math.floor(back.playTime / 3600), 255, "300h exports as 255h")
  eq(back.playTimeMaxed, 0xFF, "with wPlayTimeMaxed set the way engine/play_time.asm:36 sets it")
  local m = import("g1.red.playtime_maxed")
  eq(m.playTimeMaxed, 1, "a cart's own maxed byte is kept as is")
end

do
  local s = import("g1.red.basic")
  s.rawImport = nil
  local used, misdetect = 0, 0
  for m = 0, 600 do
    s.money = m
    local out = assert(K.export(1, "red", s, false))
    if out:byte(O.padByte + 1) ~= 0 then used = used + 1 end
    for _, e in ipairs(Compat.check(out, "red").errors) do
      if e.rule == "gen1.openhomeMisdetect" then misdetect = misdetect + 1 end
    end
  end
  check(used > 0, ("the pad byte moved in %d of 601 exports"):format(used))
  eq(misdetect, 0, "none of them reads as a Gen 2 save")
end

do
  local c = byId["g1.red.full_boxes"]
  local a = assert(K.export(1, "red", assert(K.import(1, "red", c.bytes)), false))
  local b = assert(K.export(1, "red", assert(K.import(1, "red", c.bytes)), false))
  check(a == b, "two templateless exports of one save are byte-identical")
  local s = assert(K.import(1, "red", c.bytes))
  s.rawImport = nil
  local inv = {}
  local keys = {}
  for k in pairs(s.inventory) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return x > y end)
  for _, k in ipairs(keys) do inv[k] = s.inventory[k] end
  s.inventory, s.bagOrder = inv, nil
  local t1 = assert(K.export(1, "red", s, false))
  s.inventory = deepCopy(inv)
  local t2 = assert(K.export(1, "red", s, false))
  check(t1 == t2, "bag order without bagOrder does not depend on table insertion order")
end

local rng = 0x2545F491
local function rand(n)
  rng = (rng * 1103515245 + 12345) % 2147483648
  return rng % n
end

do
  local data = K.gen1Data("red")
  local cw = GenSave.crosswalks(data)
  local species, items, moves, flagNames = {}, {}, {}, {}
  for idx, id in pairs(cw.pokemonByIndex) do species[#species + 1] = { idx, id } end
  for idx, id in pairs(cw.itemsByIndex) do
    if idx <= 0x53 and idx ~= 0x15 and not id:match("BADGE$") then items[#items + 1] = id end
  end
  for idx, id in pairs(cw.movesByIndex) do moves[#moves + 1] = id end
  for _, name in pairs(data.eventFlags.byBit) do flagNames[#flagNames + 1] = name end
  table.sort(species, function(a, b) return a[1] < b[1] end)
  table.sort(items)
  table.sort(moves)
  table.sort(flagNames)
  local towns = {}
  for _, row in ipairs(require("src.save_convert.data.blackout_maps")) do towns[#towns + 1] = row[1] end
  local function randMon()
    local sp = species[rand(#species) + 1][2]
    local m = { species = sp, level = rand(100) + 1, exp = rand(1000000), hp = rand(500),
      otId = rand(65536), ot = "OT" .. rand(10), moves = {},
      dvs = { attack = rand(16), defense = rand(16), speed = rand(16), special = rand(16) },
      statExp = { hp = rand(65536), attack = rand(65536), defense = rand(65536), speed = rand(65536), special = rand(65536) },
      stats = { hp = rand(500), attack = rand(500), defense = rand(500), speed = rand(500), special = rand(500) } }
    for i = 1, rand(4) + 1 do m.moves[i] = { id = moves[rand(#moves) + 1], pp = rand(40), ppUps = rand(4) } end
    if rand(3) == 0 then m.nickname = "NICK" .. rand(100) end
    return m
  end
  local misdetect, padded, failures = 0, 0, 0
  for n = 1, 1000 do
    local save = SaveConvert.mergeDefaults({ player = { name = "P" .. rand(1000), rival = "R" .. rand(100), id = rand(65536),
      map = "PALLET_TOWN", x = rand(10), y = rand(9) }, money = rand(1000000), coins = rand(10000),
      inventory = {}, pcItems = {}, pokedex = { seen = {}, owned = {} }, flags = {}, party = {}, boxes = {},
      currentBox = rand(12) + 1, playTime = rand(255 * 3600) + rand(60) / 60 }, "red")
    for _ = 1, rand(15) do save.inventory[items[rand(#items) + 1]] = rand(99) + 1 end
    for _ = 1, rand(6) + 1 do save.party[#save.party + 1] = randMon() end
    for b = 1, 12 do
      save.boxes[b] = {}
      for _ = 1, rand(4) do save.boxes[b][#save.boxes[b] + 1] = randMon() end
    end
    for _ = 1, rand(30) do save.flags[flagNames[rand(#flagNames) + 1]] = true end
    for i = 1, rand(151) do
      local sp = species[rand(#species) + 1][2]
      save.pokedex.seen[sp] = true
      if i % 2 == 0 then save.pokedex.owned[sp] = true end
    end
    save.options = { textSpeed = ({ 1, 3, 5 })[rand(3) + 1], battleStyle = rand(2) == 0 and "set" or "shift",
      animations = rand(2) == 0 }
    if rand(4) == 0 then
      save.hallOfFame = {}
      for t = 1, rand(5) + 1 do save.hallOfFame[t] = { { species = species[rand(#species) + 1][2], level = rand(100) + 1 } } end
    end
    local town = towns[rand(#towns) + 1]
    save.lastHeal = { map = town, x = data.field.flyWarps[town].x, y = data.field.flyWarps[town].y }
    if rand(5) == 0 then save.player.surfing = true elseif rand(5) == 0 then save.onBike = true end
    local out, err = K.export(1, "red", save, false)
    if not out then
      failures = failures + 1
      check(false, ("fuzz %d: export failed: %s"):format(n, tostring(err)))
    else
      local report = Compat.check(out, "red")
      for _, e in ipairs(report.errors) do
        if e.rule == "gen1.openhomeMisdetect" then misdetect = misdetect + 1 end
      end
      if out:byte(O.padByte + 1) ~= 0 then padded = padded + 1 end
      local back = K.import(1, "red", out)
      local why
      local function need(cond, what) if not cond and not why then why = what end end
      need(back ~= nil, "import")
      if back then
        need(back.player.id == save.player.id and back.money == save.money and back.coins == save.coins, "trainer")
        need(#back.party == #save.party and back.currentBox == save.currentBox, "party size or current box")
        need(back.lastHeal.map == town, "lastHeal")
        need(back.options.textSpeed == save.options.textSpeed, "options")
        need(math.abs(back.playTime - save.playTime) < 0.02, "playTime")
        need((back.player.surfing or false) == (save.player.surfing or false), "surfing")
        need(#(back.hallOfFame or {}) == #(save.hallOfFame or {}), "hallOfFame")
        for i, m in ipairs(save.party) do
          local g = back.party[i]
          need(g and g.species == m.species and g.exp == m.exp and g.level == m.level and #g.moves == #m.moves,
            "party mon " .. i)
        end
        for b = 1, 12 do need(#back.boxes[b] == #save.boxes[b], "box " .. b) end
        for name in pairs(save.flags) do need(back.flags[name], "flag " .. name) end
        for id, q in pairs(save.inventory) do need(back.inventory[id] == q, "item " .. id) end
        local ref = Ref.decode(out)
        need(ref.money == save.money and ref.playerId == save.player.id and ref.party.count == #save.party, "reference")
        back.rawImport = nil
        local again = K.export(1, "red", back, false)
        if again ~= out and not why then
          local D = require("tests.save_compat._diff")
          why = "fixed point (" .. D.format(D.diff(out, again or "", D.regionsFor(1, "red")), 4) .. ")"
        end
      end
      local ok = why == nil
      if not ok then
        failures = failures + 1
        if failures <= 3 then check(false, ("fuzz %d: %s differs after the round trip"):format(n, why)) end
      end
    end
  end
  eq(failures, 0, "1000 random models round trip and reach a fixed point")
  eq(misdetect, 0, "no export is mistaken for a Gen 2 save by OpenHome")
  check(padded >= 0, ("pad byte used by %d exports"):format(padded))
end

do
  local c = byId["g1.red.full_boxes"]
  local regions = require("src.save_convert.regions.gen1").regions
  local Diff = require("tests.save_compat._diff")
  local modeled = {
    { O.money, function() local d = rand(100); return math.floor(d / 10) * 16 + d % 10 end },
    { O.playerId, function() return rand(256) end },
    { O.badges, function() return rand(256) end },
    { O.pokedexOwned + 3, function() return rand(256) end },
    { O.playTimeMinutes, function() return rand(60) end },
    { O.options, function() return rand(256) end },
    { O.coins + 1, function() local d = rand(100); return math.floor(d / 10) * 16 + d % 10 end },
    { O.partyMons + 14, function() return rand(256) end },
    { O.partyMons + 27, function() return rand(256) end },
    { O.boxMons + 33 + 17, function() return rand(256) end },
    { O.lastBlackoutMap, function() return rand(11) end },
    { O.walkBikeSurf, function() return rand(3) end },
  }
  local bad = 0
  for n = 1, 200 do
    local spec = modeled[rand(#modeled) + 1]
    local v = spec[2]()
    local src = reseal(patchByte(c.bytes, spec[1], v))
    local save = K.import(1, "red", src)
    local out = save and K.export(1, "red", save)
    if not (out and out:byte(spec[1] + 1) == v and out == src) then
      bad = bad + 1
      if bad <= 3 then check(false, ("modeled mutation %d at 0x%04X = %02X does not round trip"):format(n, spec[1], v)) end
    end
  end
  eq(bad, 0, "200 modeled-byte mutations survive import -> export")

  local t2 = {}
  for o = 0, 0x7FFF do
    local r = Diff.regionAt(regions, o)
    if r.tier == "T2" and o ~= O.padByte and o ~= O.padByteTagged
       and not (o >= O.mainData + 0x6F and o < O.mainData + 0x6F + 0x1D4) then
      t2[#t2 + 1] = o
    end
  end
  bad = 0
  for n = 1, 200 do
    local off = t2[rand(#t2) + 1]
    local v = rand(256)
    local src = patchByte(c.bytes, off, v)
    if off >= O.checksumStart and off < O.checksumEnd then src = reseal(src) end
    local save = K.import(1, "red", src)
    local out = save and K.export(1, "red", save)
    if not (out and out:byte(off + 1) == v) then
      bad = bad + 1
      if bad <= 3 then check(false, ("carried byte 0x%04X = %02X is lost"):format(off, v)) end
    end
  end
  eq(bad, 0, "200 unmodeled-byte mutations are carried through")
end

do
  local raised = 0
  for n = 1, 300 do
    local c = cases[rand(#cases) + 1]
    local s = c.bytes
    for _ = 1, rand(40) + 1 do s = patchByte(s, rand(#s), rand(256)) end
    if n % 2 == 0 then s = reseal(s) end
    local ok, save = pcall(SaveConvert.importSav, s, c.version, c.version)
    if not ok then raised = raised + 1 end
    if ok and save then
      local ok2 = pcall(SaveConvert.exportSav, save, c.version)
      if not ok2 then raised = raised + 1 end
      save.rawImport = nil
      local ok3 = pcall(SaveConvert.exportSav, save, c.version)
      if not ok3 then raised = raised + 1 end
    end
  end
  eq(raised, 0, "300 corrupted carts never raise out of importSav/exportSav")
  local base = byId["g1.red.basic"].bytes
  for _, size in ipairs({ 0, 1, 0x3523, 0x7FFF, 0x8001, 0x8030, 0x10000 }) do
    local s = size <= #base and base:sub(1, size) or (base .. string.rep("\0", size - #base))
    local ok, save, err = pcall(SaveConvert.importSav, s, "red", "red")
    check(ok and save == nil and type(err) == "string", ("a %d-byte file is refused with a message"):format(size))
  end
end

do
  local b = B.new(G1.SIZE)
  B.put(b, 0x2ED5, 1, 0x99, 0xFF)
  B.put(b, 0x302D, 0, 0xFF)
  B.put(b, O.mainChecksum, B.complement8(b, O.checksumStart, O.checksumEnd))
  B.put(b, 0x3594, B.complement8(b, 0x2598, 0x3594))
  local bytes = B.pack(b)
  check(GenSave.mainChecksumValid(bytes), "the Japanese fixture also passes the international main checksum")
  check(GenSave.looksLikeJapaneseSave(bytes), "the Japanese party and 30-mon box layout are identified")
  local blueData = K.gen1Data("blue")
  SaveConvert.setGen1DataStub({}, "blue")
  local noCache, noCacheErr = SaveConvert.importSav(bytes, "blue", "blue")
  check(noCache == nil and tostring(noCacheErr):find("Japanese Gen 1"), "Japanese refusal precedes missing-cache diagnostics")
  SaveConvert.setGen1DataStub(blueData, "blue")
  local padded, paddedErr = SaveConvert.mainChecksumValid(bytes .. string.rep("\0", 48), "blue")
  check(padded == nil and tostring(paddedErr):find("Japanese Gen 1"), "a padded Japanese save is named before truncation confirmation")
  for _, version in ipairs({ "red", "blue", "yellow" }) do
    local save, err = K.import(1, version, bytes)
    check(save == nil and tostring(err):find("Japanese Gen 1"), version .. ": a Japanese save is refused before decoding")
  end
  check(not GenSave.looksLikeJapaneseSave(bytes:sub(1, 0x3594)), "a truncated Japanese checksum cannot identify a save")
  local broken = patchByte(bytes, 0x3594, (bytes:byte(0x3595) + 1) % 256)
  check(not GenSave.looksLikeJapaneseSave(broken), "a Japanese layout with a bad checksum is not falsely identified")
  for _, c in ipairs(cases) do
    check(not GenSave.looksLikeJapaneseSave(c.bytes), c.id .. ": an international layout is not identified as Japanese")
  end
end

T.finish()
