package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local K = require("tests.save_compat._codec")
local D = require("tests.save_compat._gen3_decode")
local G3 = require("tests.fixtures.save.gen3_build")
local H = require("tests.save_compat._gen3_sections")
local Layout = require("src.save_convert.Gen3Layout")

local VERSIONS = { "firered", "leafgreen", "emerald" }

for _, v in ipairs(VERSIONS) do
  local fam = H.family(v)
  local cart = H.cart(v, function(w)
    G3.setParty(w, {
      G3.mon({ moves = { 10, 0, 45, 35 }, pp = { 35, 7, 40, 25 }, nick = "GAP" }),
      G3.mon({ moves = { 0, 0, 0, 0 }, pp = { 0, 0, 0, 0 }, pid = 0x5151, nick = "NONE" }),
      G3.mon({ moves = { 10, 45, 0, 0 }, pp = { 35, 40, 9, 0 }, pid = 0x6161, nick = "JUNKPP" }),
      G3.mon({ moves = { 10, 45, 0, 0 }, pp = { 35, 40, 0, 0 }, pid = 0x7171, nick = "PLAIN", status = 0x80 + 5 * 256 }),
    })
  end)
  local save = H.import(v, cart)
  eq(#K.r1Diff(3, v, cart, H.withTemplate(v, save, cart)), 0, v .. ": move slot gaps and stray PP survive the template round trip")
  local fresh = D.deep(H.fresh(v, H.import(v, cart)), fam)
  eq(table.concat(fresh.party[1].moves, ","), "10,0,45,35", v .. ": a gap mon keeps its slot layout without a template")
  eq(table.concat(fresh.party[1].pp, ","), "35,7,40,25", v .. ": the PP of every slot is kept")
  eq(table.concat(fresh.party[3].pp, ","), "35,40,9,0", v .. ": PP stored for an empty slot is kept")
  eq(fresh.party[4].status, 0x80 + 5 * 256, v .. ": the toxic counter is kept")

  local edited = H.import(v, cart)
  edited.party[1].moves[#edited.party[1].moves + 1] = 33
  edited.party[1].pp[#edited.party[1].pp + 1] = 35
  local after = D.deep(H.fresh(v, edited), fam)
  eq(table.concat(after.party[1].moves, ","), "10,45,35,33", v .. ": a changed move list compacts instead of resurrecting the old layout")
  eq(table.concat(after.party[1].pp, ","), "35,40,25,35", v .. ": a changed move list carries its own PP")
end

for _, v in ipairs(VERSIONS) do
  local L = Layout.forVersion(v)
  local bytes = H.cart(v)
  local out = H.fresh(v, H.import(v, bytes))
  local blocks = H.blocks(out, v)
  local party = L.PARTY_OFFSET
  local emptyMail = true
  for i = 0, L.PARTY_SIZE - 1 do
    local count = blocks.sb1:byte(L.PARTY_COUNT_OFFSET and L.PARTY_COUNT_OFFSET + 1 or (v == "emerald" and 0x234 or 0x34) + 1)
    if i >= count and blocks.sb1:byte(party + i * 100 + 85 + 1) ~= 0xFF then emptyMail = false end
  end
  check(emptyMail, v .. ": unused party slots carry MAIL_NONE like ZeroMonData (src/pokemon.c)")
  local M = L.MAIL
  local clear = true
  local save = H.import(v, bytes)
  save.mail = {}
  local cleared = H.blocks(H.fresh(v, save), v)
  for i = 0, M.count - 1 do
    local o = M.off + i * M.size
    for k = 0, M.playerNameLength - 1 do
      if cleared.sb1:byte(o + M.playerName + k + 1) ~= 0xFF then clear = false end
    end
    for k = 0, M.wordCount - 1 do
      local w = cleared.sb1:byte(o + k * 2 + 1) + cleared.sb1:byte(o + k * 2 + 2) * 256
      if w ~= L.EC_WORD_UNDEFINED then clear = false end
    end
    if cleared.sb1:byte(o + M.itemId + 1) ~= 0 or cleared.sb1:byte(o + M.itemId + 2) ~= 0 then clear = false end
  end
  check(clear, v .. ": an empty mail record is exactly what ClearMail writes (src/mail_data.c:19)")
end

for _, v in ipairs(VERSIONS) do
  local fam = H.family(v)
  local cart = H.cart(v, function(w)
    local key = w.key
    local base = w.F.gameStats
    local B = require("tests.fixtures.save.bytes")
    for id, val in pairs({ [23] = 7, [24] = 3, [25] = 1, [5] = 9 }) do
      B.le(w.sb1, base + id * 4, require("bit").bxor(val, key) % 4294967296, 4)
    end
  end)
  local save = H.import(v, cart)
  eq(save.gameStats[23], 7, v .. ": the cart's link wins import as game stat 23")
  eq(save.gameStats.linkBattleWins, 7, v .. ": the engine's named link win counter starts from the cart value")
  eq(save.gameStats.linkBattleLosses, 3, v .. ": the engine's named link loss counter starts from the cart value")
  eq(save.gameStats.linkBattleDraws, 1, v .. ": the engine's named link draw counter starts from the cart value")
  save.gameStats.linkBattleWins = 8
  save.gameStats.linkBattleDraws = nil
  local out = D.deep(H.withTemplate(v, save, cart), fam)
  eq(out.stats[23], 8, v .. ": a named link win counter bumped by the engine reaches stat 23")
  eq(out.stats[24], 3, v .. ": an untouched link loss counter keeps its value")
  eq(out.stats[25], 1, v .. ": a missing named counter falls back to the numeric stat")
  eq(out.stats[5], 9, v .. ": other game stats are unaffected")
  local named = H.import(v, cart)
  named.gameStats = { linkBattleWins = 4 }
  local only = D.deep(H.fresh(v, named), fam)
  eq(only.stats[23], 4, v .. ": a save table with only the named counter exports it")
end

for _, v in ipairs({ "firered", "leafgreen" }) do
  local B = require("tests.fixtures.save.bytes")
  local rng = H.rng(77)
  local expect = {}
  local cart = H.cart(v, function(w)
    for i = 0, 15 do
      local pick, flavor, unk = rng(3), rng(4096), rng(4)
      expect[i + 1] = { pickState = pick, flavorTextFlags = flavor, unk = unk }
      B.le(w.sb1, 0x3A54 + i * 4, pick + flavor * 4 + unk * 16384, 2)
      B.le(w.sb1, 0x3A54 + i * 4 + 2, 0xA000 + i, 2)
    end
  end)
  local save = H.import(v, cart)
  local fc = save.modData.fameChecker
  local same = type(fc) == "table"
  for i = 1, 16 do
    same = same and fc[i] and fc[i].pickState == expect[i].pickState and fc[i].flavorTextFlags == expect[i].flavorTextFlags
  end
  check(same, v .. ": the Fame Checker is read at the 4 byte stride of struct FameCheckerSaveData (include/global.h:631)")
  eq(#K.r1Diff(3, v, cart, H.withTemplate(v, save, cart)), 0, v .. ": the Fame Checker survives the template round trip")
  save.modData.fameChecker[3].pickState = 3
  save.modData.fameChecker[3].flavorTextFlags = 0x155
  local out = H.blocks(H.withTemplate(v, save, cart), v).sb1
  local w3 = out:byte(0x3A54 + 8 + 1) + out:byte(0x3A54 + 8 + 2) * 256
  eq(w3 % 4, 3, v .. ": an edited pick state lands in entry 3")
  eq(math.floor(w3 / 4) % 4096, 0x155, v .. ": an edited flavor mask lands in entry 3")
  eq(out:byte(0x3A54 + 8 + 3) + out:byte(0x3A54 + 8 + 4) * 256, 0xA002, v .. ": the upper half of the entry is untouched")
  eq(out:byte(0x3A54 + 4 + 3) + out:byte(0x3A54 + 4 + 4) * 256, 0xA001, v .. ": neighbouring entries are untouched")
  local fresh = H.blocks(H.fresh(v, H.import(v, cart)), v).sb1
  eq(fresh:byte(0x3A54 + 4 + 3) + fresh:byte(0x3A54 + 4 + 4) * 256, 0, v .. ": a templateless export leaves the upper halves zero")
end

for _, v in ipairs(VERSIONS) do
  local fam = H.family(v)
  local F = G3.F[fam]
  local cart = H.cart(v, function(w)
    w.sb2[0x28 + 51] = 0xFF
    w.sb2[0x5C + 51] = 0xFF
    w.sb1[F.dexSeen[1] + 51] = 0xFF
    w.sb1[F.dexSeen[2] + 51] = 0xFF
  end)
  local save = H.import(v, cart)
  local out = H.blocks(H.withTemplate(v, save, cart), v)
  eq(out.sb2:byte(0x28 + 51 + 1), 0xFF, v .. ": dex owned bits past the National Dex survive an untouched export")
  eq(out.sb2:byte(0x5C + 51 + 1), 0xFF, v .. ": dex seen bits past the National Dex survive in SB2")
  eq(out.sb1:byte(F.dexSeen[1] + 51 + 1), 0xFF, v .. ": the first SB1 seen copy keeps its high bits")
  eq(out.sb1:byte(F.dexSeen[2] + 51 + 1), 0xFF, v .. ": the second SB1 seen copy keeps its high bits")
  eq(#K.r1Diff(3, v, cart, H.withTemplate(v, save, cart)), 0, v .. ": R1 holds with edited dex bytes")
end

for _, v in ipairs(VERSIONS) do
  local fam = H.family(v)
  local cart = H.cart(v, function(w)
    G3.setParty(w, { G3.mon({ nick = "RIB", contest = { 1, 2, 3, 4, 5, 6 }, ribbons = 0x00001234 }) })
  end)
  local save = H.import(v, cart)
  local mon = save.party[1]
  eq(mon.contest.cool, 1, v .. ": contest stats import onto the mon")
  eq(mon.contest.sheen, 6, v .. ": sheen imports onto the mon")
  eq(mon.ribbons, 0x1234, v .. ": the ribbon word imports onto the mon")
  mon.contest.cool, mon.contest.tough = 200, 77
  mon.ribbons = 0x1234 + 2 ^ 20
  mon.championRibbon = true
  mon.modernFatefulEncounter = true
  local out = D.deep(H.withTemplate(v, save, cart), fam).party[1]
  eq(table.concat(out.contest, ","), "200,2,3,4,77,6", v .. ": engine contest stats reach the cart")
  eq(out.ribbons, 0x1234 + 2 ^ 20 + 2 ^ 15 + 2 ^ 31, v .. ": engine ribbons, champion and fateful flags reach the cart")
  mon.championRibbon, mon.modernFatefulEncounter = false, false
  local cleared = D.deep(H.withTemplate(v, save, cart), fam).party[1]
  eq(cleared.ribbons, 0x1234 + 2 ^ 20 - (math.floor((0x1234 + 2 ^ 20) / 2 ^ 15) % 2) * 2 ^ 15, v .. ": clearing the flags clears their bits")
  local legacy = H.import(v, cart)
  legacy.party[1].contest, legacy.party[1].ribbons, legacy.party[1].championRibbon = nil, nil, nil
  legacy.party[1].cartExtra.contest, legacy.party[1].cartExtra.ribbons = { cool = 9, beauty = 8, cute = 7, smart = 6, tough = 5, sheen = 4 }, 0x77
  local old = D.deep(H.withTemplate(v, legacy, cart), fam).party[1]
  eq(table.concat(old.contest, ","), "9,8,7,6,5,4", v .. ": a slot imported by an older build still exports its carried contest stats")
  eq(old.ribbons, 0x77, v .. ": and its carried ribbons")
end

for _, v in ipairs(VERSIONS) do
  local fam = H.family(v)
  local F = G3.F[fam]
  local B = require("tests.fixtures.save.bytes")
  local mailOff = fam == "emerald" and 0x2BE0 or 0x2CD0
  local cart = H.cart(v, function(w)
    local o = mailOff + 6 * 36
    for k = 0, 8 do B.le(w.sb1, o + k * 2, 0xFFFF, 2) end
    B.put(w.sb1, o + 18, 0xBB, 0xBC, 0xBD, 0, 0, 0, 0xFF, 0xFF)
    B.le(w.sb1, o + 26, 0x59650100, 4)
    B.le(w.sb1, o + 30, 1, 2)
    B.le(w.sb1, o + 32, 121, 2)
    local o2 = mailOff + 7 * 36
    for k = 0, 8 do B.le(w.sb1, o2 + k * 2, 0xFFFF, 2) end
    B.put(w.sb1, o2 + 18, 0xBB, 0xBC, 0xBD, 0, 0, 0, 0xFF, 0xFF)
    B.le(w.sb1, o2 + 26, 0x00000200, 4)
    B.le(w.sb1, o2 + 30, 1, 2)
    B.le(w.sb1, o2 + 32, 122, 2)
  end)
  local save = H.import(v, cart)
  save.mail[1] = save.mail[1] or { words = {}, playerName = "", trainerId = 0, species = 1, itemId = 0 }
  save.mail[2] = { words = { 5, 6, 7, 8, 9, 10, 11, 12, 13 }, playerName = "EDIT", trainerId = 0, species = 1, itemId = 121 }
  local out = D.deep(H.withTemplate(v, save, cart), fam)
  eq(out.mail[7].trainerId, 0x59650100, v .. ": foreign mail keeps the sender's secret id when other mail is edited")
  eq(out.mail[8].trainerId, 0x00000200, v .. ": foreign mail with no secret id is unchanged")
  eq(#K.r1Diff(3, v, cart, H.withTemplate(v, H.import(v, cart), cart)), 0, v .. ": R1 holds with foreign mail")
end

for _, v in ipairs(VERSIONS) do
  local fam = H.family(v)
  local cap = fam == "emerald" and 50 or 30
  local save = H.import(v, H.cart(v))
  save.modData.cartImage = nil
  save.storage.items = {}
  for i = 1, cap + 5 do save.storage.items[i] = { id = 13 + i, qty = 1 } end
  local out, note = K.export(3, v, save, false)
  check(out ~= nil, v .. ": an oversized PC item list still exports")
  check(type(note) == "string" and note:find("5 item slot", 1, true) ~= nil, v .. ": the export says how many PC items were left out (" .. tostring(note) .. ")")
  eq(#D.deep(out, fam).pcItems, cap, v .. ": exactly the cartridge's capacity is written")
  local fit = H.import(v, H.cart(v))
  fit.modData.cartImage = nil
  local _, noNote = K.export(3, v, fit, false)
  eq(noNote, nil, v .. ": no note when everything fits")
end

T.finish()
