package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local bit = require("bit")
local Gen3Save = require("src.save_convert.Gen3Save")
local Layout = require("src.save_convert.Gen3Layout")
local Rse = require("src.save_convert.gen3_port.rse")
local F = require("tests.fixture_data.gen3_saves_emerald")
local FR = require("tests.fixture_data.gen3_saves")

local E = Gen3Save.forVersion("emerald")
local L = E.L

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

local IMAGES, FR_IMAGES = {}, {}
for name, r in pairs(F.images) do IMAGES[name] = unrle(r) end
for name, r in pairs(FR.images) do FR_IMAGES[name] = unrle(r) end

local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. show(x) end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

local function same_eq(a, b, label)
  check(Rse.same(a, b), label .. " (" .. show(a) .. " vs " .. show(b) .. ")")
end

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function unhex(h)
  return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end

local function pairsList(list)
  local out = {}
  for _, it in ipairs(list) do out[#out + 1] = { it.id, it.qty } end
  return out
end

local function plain(t)
  local out = {}
  for k, v in pairs(t or {}) do out[tonumber(k) or k] = v end
  return out
end

-- pokeemerald/src/save.c:57
do
  local sizes = {}
  for id = 0, 13 do sizes[id + 1] = L.CHUNK_SIZES[id] end
  same_eq(sizes, { 0xF2C, 0xF80, 0xF80, 0xF80, 0xF08, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0 },
    "emerald chunk sizes")
  eq(L.BLOCKS[1].size, 0xF2C, "SaveBlock2 size")
  eq(L.BLOCKS[2].size, 0x3D88, "SaveBlock1 size")
  eq(L.KEY_OFF, 0xAC, "emerald key lives at SB2 0xAC")
  eq(L.PC_ITEMS.count, 50, "PC holds 50 items")
  eq(L.DAYCARE.offspringKind, "u32", "daycare offspring personality is u32")
  eq(L.DAYCARE.stepCounter, 0x11C, "daycare step counter after the u32")
  eq(L.LINK_BATTLE_RECORDS.block, "sb1", "link battle records moved to SB1")
  eq(L.FAME_CHECKER, nil, "no fame checker on emerald")
  eq(L.TRAINER_TOWER, nil, "no trainer tower on emerald")
  eq(L.ROUTE5_DAYCARE, nil, "no route 5 daycare on emerald")
  eq(L.RSE.sb2.battlePoints, 0xEB8, "battle points at SB2 0xEB8")
  local fr = Layout.forVersion("firered")
  eq(fr, Layout, "firered keeps the top-level layout table")
  eq(Layout.forVersion("leafgreen"), Layout, "leafgreen shares it")
  eq(Layout.forVersion("emerald"), L, "emerald resolves its own family")
  eq(fr.CHUNK_SIZES[0], 0xF24, "firered SB2 chunk unchanged")
  eq(fr.CHUNK_SIZES[4], 0xEE8, "firered SB1 tail chunk unchanged")
  eq(fr.KEY_OFF, 0xF20, "firered key stays at 0xF20")
  eq(Gen3Save.forVersion("firered"), Gen3Save, "firered codec is the module")
  eq(Gen3Save.forVersion("emerald"), E, "emerald codec is cached")
end

for name, img in pairs(IMAGES) do eq(Gen3Save.sniff(img), "emerald", name .. " sniffs as emerald") end
for name, img in pairs(FR_IMAGES) do eq(Gen3Save.sniff(img), "frlg", name .. " sniffs as frlg") end

local function checkMon(label, m, o)
  eq(m.personality, o.pid, label .. " personality")
  eq(m.otIdRaw, o.otid, label .. " OT id")
  eq(m.species, o.species, label .. " species")
  eq(m.heldItem, o.heldItem, label .. " held item")
  eq(m.exp, o.exp, label .. " exp")
  same_eq(m.moves, o.moves, label .. " moves")
  eq(m.ribbons, o.ribbons, label .. " ribbons")
  eq(hex(m.nicknameRaw), o.nickRaw, label .. " nickname bytes")
  eq(hex(m.otNameRaw), o.otRaw, label .. " OT name bytes")
  check(m.checksumOk, label .. " checksum")
end

local function checkOracle(name, c, blocks, o, loose)
  eq(E.decodeString(unhex(o.nameRaw), 0, 8), c.name, name .. " player name")
  eq(c.gender, o.gender, name .. " gender")
  eq(c.trainerId, o.tid, name .. " TID")
  eq(c.secretId, o.sid, name .. " SID")
  if not loose then
    same_eq({ c.playHours, c.playMinutes, c.playSeconds }, o.playTime, name .. " play time")
    eq(c.encryptionKey, o.key, name .. " encryption key")
    eq(c.specialSaveWarpFlags, o.warpFlags, name .. " save warp flags")
  end
  eq(c.money, o.money, name .. " money")
  eq(c.coins, o.coins, name .. " coins")
  eq(c.berryPowder, o.berryPowder, name .. " berry powder")
  eq(c.registeredItem, o.registeredItem, name .. " registered item")
  eq(c.optionsWord, o.options, name .. " options word")
  eq(c.dexNationalMagic, o.nationalMagic, name .. " national magic at SB2 0x1A")
  same_eq({ c.posX, c.posY }, o.pos, name .. " position")
  local w = c.location
  same_eq({ w.group, w.num, w.warpId, w.x, w.y }, o.location, name .. " location")
  w = c.lastHealLocation
  same_eq({ w.group, w.num, w.warpId, w.x, w.y }, o.heal, name .. " last heal location")
  eq(c.weather, o.weather, name .. " saved weather")
  if not loose then eq(c.weatherCycleStage, o.weatherCycleStage, name .. " weather cycle stage") end
  eq(#c.party, #o.party, name .. " party count")
  for i, pm in ipairs(o.party) do
    local m = c.party[i]
    checkMon(name .. " party " .. i, m, pm)
    eq(m.level, pm.level, name .. " party " .. i .. " level")
    eq(m.hp, pm.hp, name .. " party " .. i .. " HP")
    eq(m.maxHp, pm.maxHp, name .. " party " .. i .. " max HP")
    eq(m.mail, pm.mail, name .. " party " .. i .. " mail slot")
  end
  local count, first = 0, nil
  for b = 1, 14 do
    for sl = 1, 30 do
      local m = c.storage.boxes[b].mons[sl]
      if m then
        count = count + 1
        first = first or { m = m, slot = (b - 1) * 30 + sl - 1 }
      end
    end
  end
  eq(count, o.boxCount, name .. " boxed mons")
  eq(c.storage.currentBox, o.currentBox, name .. " current box")
  if o.firstBoxMon then
    eq(first and first.slot, o.firstBoxMon.slot, name .. " first boxed slot")
    if first then checkMon(name .. " first boxed mon", first.m, o.firstBoxMon) end
  end
  for key, list in pairs(o.pockets) do same_eq(pairsList(c.pockets[key]), list, name .. " pocket " .. key) end
  same_eq(pairsList(c.pcItems), o.pcItems, name .. " PC items")
  same_eq(c.flags, o.flags, name .. " flags (300 bytes)")
  if not loose then same_eq(c.vars, plain(o.vars), name .. " vars") end
  same_eq(c.gameStats, plain(o.gameStats), name .. " game stats (xor key)")
  same_eq(c.dexOwned, o.dexOwned, name .. " dex owned")
  same_eq(c.dexSeen, o.dexSeen, name .. " dex seen")
  eq(c.daycare.offspringPersonality, o.daycare.offspringPersonality, name .. " daycare offspring personality (u32)")
  eq(c.daycare.stepCounter, o.daycare.stepCounter, name .. " daycare step counter")
  for i = 1, 2 do
    eq(c.daycare.mons[i] and c.daycare.mons[i].species or 0, o.daycare.species[i], name .. " daycare mon " .. i)
    eq(c.daycare.steps[i], o.daycare.steps[i], name .. " daycare steps " .. i)
  end
  local mailItems = {}
  for i, m in ipairs(c.mail) do mailItems[i] = m.itemId end
  same_eq(mailItems, o.mailItems, name .. " mail items")
  eq(c.roamer.species, o.roamer.species, name .. " roamer species")
  eq(c.roamer.level, o.roamer.level, name .. " roamer level")
  eq(c.roamer.active, o.roamer.active, name .. " roamer active")
  eq(c.roamer.personality, o.roamer.personality, name .. " roamer personality")
  eq(c.roamer.ivs, o.roamer.ivs, name .. " roamer IVs")

  local s = Rse.readSections(E, blocks, {})
  local trees = {}
  for id, t in pairs(s.berryTrees) do trees[id] = { t.berry, t.stage, t.minutesUntilNextStage, t.berryYield } end
  same_eq(trees, plain(o.berryTrees), name .. " berry trees")
  local blocksList = {}
  for _, b in ipairs(s.pokeblocks) do
    if b.color + b.spicy + b.dry + b.sweet + b.bitter + b.sour + b.feel > 0 then
      blocksList[#blocksList + 1] = { b.color, b.spicy, b.dry, b.sweet, b.bitter, b.sour, b.feel }
    end
  end
  same_eq(blocksList, o.pokeblocks, name .. " pokeblocks")
  if not loose then
    local t = s.localTimeOffset
    same_eq({ t.days, t.hours, t.minutes, t.seconds }, o.localTimeOffset, name .. " local time offset")
    t = s.lastBerryTreeUpdate
    same_eq({ t.days, t.hours, t.minutes, t.seconds }, o.lastBerryTreeUpdate, name .. " last berry tree update")
  end
  eq(s.trainerRematchStepCounter, o.trainerRematchStepCounter, name .. " rematch step counter")
  same_eq(s.trainerRematches, plain(o.rematches), name .. " rematch table")
  same_eq(s.giftRibbons, o.giftRibbons, name .. " gift ribbons")
  local inv = {}
  for cat = 0, 7 do for _, d in ipairs(s.decorationInventory[cat]) do inv[#inv + 1] = d end end
  same_eq(inv, o.decorInventory, name .. " decoration inventory")
  same_eq(s.playerRoomDecorations, o.playerRoomDecorations, name .. " player room decorations")
  eq(s.outbreakPokemonSpecies, o.outbreakSpecies, name .. " outbreak species")
  local words = {}
  for i, t in ipairs(s.dewfordTrends) do words[i] = t.words[1] end
  if not loose then same_eq(words, o.dewfordWords, name .. " dewford trend words") end
  local species = {}
  for i, w in ipairs(s.contestWinners) do species[i] = w.species end
  same_eq(species, o.contestWinnerSpecies, name .. " contest winner species")
  eq(s.secretBases[1].secretBaseId, o.secretBaseId, name .. " own secret base id")
  local lr = s.linkBattleRecords[1]
  local raw = unhex(o.linkRecord0)
  if raw:byte(1) ~= 0xFF and raw:byte(1) ~= 0 then
    eq(lr and lr.name, E.decodeString(raw, 0, 8), name .. " link record name")
    eq(lr and lr.wins, raw:byte(11) + raw:byte(12) * 256, name .. " link record wins")
  else
    eq(lr, nil, name .. " no link record")
  end
  eq(E.u16(blocks.sb2, L.RSE.sb2.battlePoints), o.battlePoints, name .. " battle points")
end

local decoded = {}
for _, name in ipairs({ "em_battle", "em_fresh", "em_doctored" }) do
  local c, blocks = E.decode(IMAGES[name])
  check(c ~= nil, name .. " decodes (" .. tostring(blocks) .. ")")
  if c then
    decoded[name] = { c = c, blocks = blocks }
    eq(c.olderSlot, false, name .. " newest slot valid")
    checkOracle(name, c, blocks, F.oracle[name])
  end
end

do
  local c = decoded.em_doctored.c
  eq(c.encryptionKey, 0, "doctored save carries key 0")
  eq(c.daycare.offspringPersonality, 0xDEADBEEF, "doctored daycare egg personality keeps the high half")
  eq(#c.pcItems, 50, "doctored PC holds 50 items")
  eq(c.pcItems[50].qty, 50, "PC slot 50 quantity is not xor'd")
  eq(c.mail[7].itemId, 121, "PC mailbox mail decodes")
  eq(c.mail[7].playerName, "RIVAL", "mail author name")
  eq(c.mail[7].trainerIdRaw, 0x12345678, "mail trainer id")
  eq(c.roamer.cool, 1, "roamer contest stats decode")
  check(decoded.em_fresh.c.encryptionKey ~= 0, "a fresh save is re-keyed by the truck map load")
end

do
  local img = IMAGES.em_battle
  local newest = decoded.em_battle.blocks.slot
  local base = (newest * 14 + 3) * 0x1000 + 100
  local broken = img:sub(1, base) .. string.char((img:byte(base + 1) + 1) % 256) .. img:sub(base + 2)
  local c, blocks = E.decode(broken)
  check(c ~= nil, "bundled slot decodes once the newest slot is damaged")
  if c then
    eq(c.olderSlot, true, "the older slot is the bundled all-shiny save")
    checkOracle("em_shiny", c, blocks, F.oracle.em_shiny, true)
    eq(F.meta.em_shiny.ramAfterContinue, true, "the shiny oracle came from RAM after CONTINUE")
  end
end

local function rebuild(bytes, counter)
  local c, blocks = E.decode(bytes)
  return E.buildFlash(E.encodeBlocks(c, blocks), { counter = counter or (blocks.counter + 1), image = blocks.image }), c
end

for name, d in pairs(decoded) do
  local img, before = rebuild(IMAGES[name])
  local c, blocks = E.decode(img)
  check(c ~= nil, name .. " re-encoded flash decodes")
  if c then
    eq(blocks.counter, d.blocks.counter + 1, name .. " counter advanced")
    eq(blocks.slot, (d.blocks.slot + 1) % 2, name .. " save went to the other slot")
    for _, blk in ipairs(L.BLOCKS) do
      if name ~= "em_battle" then
        check(blocks[blk.key] == d.blocks[blk.key], name .. " " .. blk.key .. " bytes survive re-encode")
      end
    end
    checkOracle(name .. " re-encoded", c, blocks, F.oracle[name])
    for sec = 0, 13 do
      local phys = blocks.slot * 14 + (sec + blocks.counter) % 14
      local o = phys * 0x1000
      local id = E.u16(img, o + 0xFF4)
      eq(E.u16(img, o + 0xFF6), E.checksum(img, o, L.CHUNK_SIZES[id]), name .. " sector " .. phys .. " checksum")
    end
    for sec = 28, 31 do
      local o = sec * 0x1000
      check(img:sub(o + 1, o + 0x1000) == IMAGES[name]:sub(o + 1, o + 0x1000), name .. " sector " .. sec .. " kept")
    end
  end
  local wrapped = rebuild(IMAGES[name], 0xFFFFFFFF)
  local w = E.decode(wrapped)
  eq(w and w.counter, 0xFFFFFFFF, name .. " counter at the wrap edge")
  local after = rebuild(wrapped, 0)
  local z = E.decode(after)
  eq(z and z.counter, 0, name .. " counter wraps to 0 and still wins")
  eq(z and z.money, before.money, name .. " wrapped save keeps money")
end

local function opts(template)
  return {
    template = template, version = "emerald", metGame = 3,
    toNational = function() return nil end,
    itemId = function(id) return tonumber(id) end,
  }
end

for _, name in ipairs({ "em_battle", "em_fresh", "em_doctored" }) do
  local bytes = IMAGES[name]
  local save, err = E.importPort(bytes, "emerald")
  check(save ~= nil, name .. " imports (" .. tostring(err) .. ")")
  if save then
    eq(save.version, "emerald", name .. " tagged emerald")
    eq(save.rivalName, nil, name .. " has no stored rival name")
    eq(save.encryptionKey, F.oracle[name].key, name .. " native encryption key")
    check(type(save.modData.emerald_daycare) == "table", name .. " daycare under modData.emerald_daycare")
    eq(save.modData.firered_daycare, nil, name .. " no FireRed daycare")
    eq(save.modData.fameChecker, nil, name .. " no fame checker")
    check(type(save.map) == "string" and save.map:sub(1, 3) == "EM_", name .. " map " .. tostring(save.map))
    local out, xerr = E.exportPort(save, opts(bytes))
    check(out ~= nil, name .. " exports (" .. tostring(xerr) .. ")")
    if out then
      local a, b = E.readBlocks(bytes), E.readBlocks(out)
      for _, blk in ipairs(L.BLOCKS) do
        check(a[blk.key] == b[blk.key], name .. " " .. blk.key .. " byte-identical after import/export")
      end
      for sec = 28, 31 do
        local o = sec * 0x1000
        check(out:sub(o + 1, o + 0x1000) == bytes:sub(o + 1, o + 0x1000), name .. " sector " .. sec .. " byte-identical")
      end
      eq(b.counter, a.counter + 1, name .. " export bumps the save counter")
    end
  end
end

do
  local bytes = IMAGES.em_doctored
  local save = assert(E.importPort(bytes, "emerald"))
  save.money = 424242
  save.coins = 77
  table.insert(save.bag.pockets.ITEMS, { id = 13, qty = 9 })
  save.flags[0x867] = true
  save.vars[0x4046] = nil
  save.berryTrees[20] = { berry = 3, stage = 2, stopGrowth = true, minutesUntilNextStage = 60, berryYield = 0,
    regrowthCount = 1, watered1 = true, watered2 = false, watered3 = true, watered4 = false }
  save.pokeblocks[2] = { color = 3, spicy = 0, dry = 40, sweet = 0, bitter = 0, sour = 0, feel = 25 }
  save.trainerRematches[10] = 3
  save.linkBattleRecords = { { name = "MAY", trainerId = 7, wins = 9, losses = 2, draws = 1 } }
  save.modData.emerald_daycare.daycare.offspringPersonality = 0xFEDCBA98
  save.localTimeOffset = { days = 3, hours = -1, minutes = 2, seconds = 0 }
  local out = assert(E.exportPort(save, opts(bytes)))
  local c, blocks = E.decode(out)
  eq(c.money, 424242, "edited money exports under the save's key")
  eq(c.coins, 77, "edited coins export")
  local last = c.pockets.ITEMS[#c.pockets.ITEMS]
  same_eq({ last.id, last.qty }, { 13, 9 }, "added bag item exports")
  local has = false
  for _, id in ipairs(c.flags) do if id == 0x867 then has = true end end
  check(has, "set flag exports into the 300-byte flag array")
  eq(c.daycare.offspringPersonality, 0xFEDCBA98, "u32 egg personality exports")
  local s = Rse.readSections(E, blocks, {})
  eq(s.berryTrees[20] and s.berryTrees[20].stopGrowth, true, "berry tree stopGrowth bit")
  eq(s.berryTrees[20] and s.berryTrees[20].watered3, true, "berry tree watered bits")
  eq(s.berryTrees[20] and s.berryTrees[20].regrowthCount, 1, "berry tree regrowth")
  eq(s.pokeblocks[2].dry, 40, "pokeblock exports")
  eq(s.trainerRematches[10], 3, "rematch table exports")
  eq(s.linkBattleRecords[1].name, "MAY", "link record exports to SB1")
  eq(s.linkBattleRecords[1].wins, 9, "link record wins")
  eq(s.localTimeOffset.hours, -1, "local time offset keeps its sign")
  eq(s.localTimeOffset.days, 3, "local time offset days")
  local again = assert(E.importPort(out, "emerald"))
  eq(again.money, 424242, "re-import sees the edit")
end

do
  local fr = FR_IMAGES.fr_rich_game
  local _, why = E.decode(fr)
  eq(why, "frlg", "a FireRed save is named for the emerald slot")
  local _, msg = E.importPort(fr, "emerald")
  eq(msg, E.MSG.frlg, "FireRed-into-Emerald message")
  local _, frWhy = Gen3Save.decode(IMAGES.em_battle)
  eq(frWhy, "notFrlg", "an Emerald save is refused by the FireRed codec")
  local _, small = E.importPort(string.rep("\0", 32768), "emerald")
  eq(small, E.MSG.size:format(32768), "size sentence names Emerald")
  local _, empty = E.importPort(string.rep("\255", 0x20000), "emerald")
  eq(empty, E.MSG.empty, "an erased flash is empty")
  local blocks = assert(E.readBlocks(IMAGES.em_fresh))
  local sb2 = blocks.sb2:sub(1, 0x890) .. string.rep("\0", #blocks.sb2 - 0x890)
  local sb1 = blocks.sb1:sub(1, 0x3AC0) .. string.rep("\0", #blocks.sb1 - 0x3AC0)
  local rs = E.buildFlash({ sb2 = sb2, sb1 = sb1, storage = blocks.storage }, { counter = 3 })
  eq(Gen3Save.sniff(rs), "rs", "zeroed Emerald tails sniff as Ruby/Sapphire")
  local _, rsWhy = E.decode(rs)
  eq(rsWhy, "rs", "Ruby/Sapphire save named for the emerald slot")
  local mgba = IMAGES.em_fresh
  eq(#mgba, 0x20010, "fixture keeps the emulator RTC footer")
  check(E.decode(mgba) ~= nil, "an mGBA RTC footer is dropped by normalizeSize")
end

do
  local fr = FR_IMAGES.fr_rich_game
  local a = Gen3Save.decode(fr)
  local b = Gen3Save.forVersion("leafgreen").decode(fr)
  eq(a.money, b.money, "leafgreen uses the FireRed codec")
  eq(a.nicknameRaw, nil, "FireRed decode carries no raw name fields")
  check(a.party[1] and a.party[1].nicknameRaw == nil, "FireRed mons carry no raw name bytes")
end

do
  local names = { "rtc", "encryptionKey", "berryTrees", "tv", "decorations", "weather", "matchCall", "giftRibbons",
    "dewfordTrends", "contests", "lilycoveLady", "lottery", "pokeblocks", "secretBases", "oldMan" }
  for _, n in ipairs(names) do check(Rse.SECTIONS[n] ~= nil, "port mapper covers save section " .. n) end
end

T.finish("gen3_save_emerald_codec")
