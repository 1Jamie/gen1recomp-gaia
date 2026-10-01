package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")

local VERSIONS = { "gold", "silver", "crystal" }
local DATA = {
  items = K.gen2Data.items, maps = K.gen2Data.maps,
  pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL", genderRatio = 0x1F },
              UNOWN = { index = 201, dex = 201, name = "UNOWN", genderRatio = 0xFF },
              PIKACHU = { index = 25, dex = 25, name = "PIKACHU", genderRatio = 0x7F } },
  moves = { TACKLE = { index = 33, pp = 35 }, GROWL = { index = 43, pp = 40 }, EMBER = { index = 52, pp = 25 } },
}

local function build(version, spec)
  spec.version = version
  return G2.build(spec)
end

local function decode(bytes, version) return assert(Gen2Save.decode(bytes, version, DATA)) end
local function fresh(save, version)
  local out, err = Gen2Save.encode(save, version, nil, DATA)
  return out, err
end
local function slice(s, at, n) return s:sub(at + 1, at + n) end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local at = L.wPartyMons

  local function monBytes(patch)
    return build(v, { party = { G2.mon() }, patch = function(b, LL)
      patch(b, LL.wPartyMons)
    end })
  end

  local gap = monBytes(function(b, o)
    b[o + 2], b[o + 3], b[o + 4], b[o + 5] = 33, 0, 43, 0
    b[o + 0x17], b[o + 0x18], b[o + 0x19], b[o + 0x1A] = 0x23, 0x05, 0x5E, 0x00
  end)
  local save = decode(gap, v)
  local m = save.party[1]
  eq(#m.moves, 2, v .. ": the engine sees the two real moves")
  eq(table.concat(m.cartMoveSlots or {}, ","), "1,3", v .. ": the gap rides as the slot list")
  eq(m.cartEmptyPp and m.cartEmptyPp[2], 5, v .. ": junk PP on an empty slot rides too")
  local out = fresh(save, v)
  eq(slice(out, at, 48), slice(gap, at, 48), v .. ": a templateless export keeps empty-before-filled move slots and the empty-slot PP")
  m.moves[1].id = 52
  out = fresh(save, v)
  eq(out:byte(at + 3), 52, v .. ": an engine edit of a move keeps its slot")
  eq(out:byte(at + 4), 0, v .. ": and the gap")
  m.moves[3] = { id = 33, pp = 1 }
  out = fresh(save, v)
  eq(table.concat({ out:byte(at + 3, at + 6) }, ","), "52,43,33,0", v .. ": a changed move count is laid out compactly")

  local cases = 0
  for byte = 0, 255 do
    local src = monBytes(function(b, o) b[o + 0x20] = byte end)
    local s = decode(src, v)
    local o2 = fresh(s, v)
    if o2:byte(at + 0x20 + 1) ~= byte then
      check(false, ("%s: status byte 0x%02X survives (got 0x%02X)"):format(v, byte, o2:byte(at + 0x20 + 1)))
    else
      cases = cases + 1
    end
  end
  eq(cases, 256, v .. ": every status byte value survives a templateless round trip")

  local multi = decode(monBytes(function(b, o) b[o + 0x20] = 0x48 end), v).party[1]
  eq(multi.cartStatus, 0x48, v .. ": PAR with PSN keeps its raw byte")
  multi.status = "burn"
  eq(fresh({ party = { multi }, position = { map = K.GEN2_MAP, x = 1, y = 1 } }, v):byte(at + 0x20 + 1), 0x10,
    v .. ": changing the status drops the carrier")

  local function statusOf(name, turns)
    local mon = decode(monBytes(function() end), v).party[1]
    mon.status, mon.statusTurns = name, turns
    local o = Gen2Save.encode({ party = { mon }, position = { map = K.GEN2_MAP, x = 1, y = 1 } }, v, nil, DATA)
    return o and o:byte(at + 0x20 + 1)
  end
  eq(statusOf("sleep", 4), 4, v .. ": sleep is its counter")
  eq(statusOf("sleep", 9), 7, v .. ": capped at 7")
  eq(statusOf("poison"), 8, v .. ": poison")
  eq(statusOf("toxic"), 8, v .. ": toxic is the PSN bit, the cart keeps the counter in battle only")
  eq(statusOf("burn"), 16, v .. ": burn")
  eq(statusOf("freeze"), 32, v .. ": freeze")
  eq(statusOf("paralyze"), 64, v .. ": paralyze")
  eq(statusOf("psn"), 8, v .. ": the short spelling still writes")
  eq(statusOf(nil), 0, v .. ": healthy")
  local none, why = Gen2Save.encode({ party = { (function()
    local mon = decode(monBytes(function() end), v).party[1]
    mon.status = "wrapped"
    return mon
  end)() }, position = { map = K.GEN2_MAP, x = 1, y = 1 } }, v, nil, DATA)
  eq(none, nil, v .. ": a mod status the cart cannot hold is refused")
  check(type(why) == "string" and why:find("wrapped", 1, true) ~= nil, v .. ": by name -- " .. tostring(why))
  local d = decode(monBytes(function(b, o) b[o + 0x20] = 3 end), v).party[1]
  eq(d.status, "sleep", v .. ": cart sleep imports under the engine's spelling")
  eq(d.statusTurns, 3, v .. ": with its counter")
  eq(decode(monBytes(function(b, o) b[o + 0x20] = 0x40 end), v).party[1].status, "paralyze", v .. ": paralysis")
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local function bagOf(items, pc, keys, balls)
    return build(v, { items = items, pcItems = pc, keyItems = keys, balls = balls })
  end
  local P, R, A, M = G2.ITEMS.POTION.index, G2.ITEMS.REPEL.index, G2.ITEMS.ANTIDOTE.index, G2.ITEMS.MAX_POTION.index
  local layouts = {
    { name = "non-adjacent duplicate", items = { { P, 3 }, { R, 4 }, { P, 5 } } },
    { name = "99 and 50", items = { { P, 99 }, { P, 50 } } },
    { name = "two short stacks", items = { { P, 40 }, { P, 40 } } },
    { name = "one stack past 99", items = { { P, 150 } } },
    { name = "zero quantity stack", items = { { P, 3 }, { R, 0 }, { A, 2 } } },
    { name = "pc non-adjacent duplicate", items = { { P, 1 } }, pc = { { M, 1 }, { P, 2 }, { M, 3 } } },
    { name = "pc single big stack", items = { { P, 1 } }, pc = { { M, 200 } } },
    { name = "cross pocket duplicate", items = { { P, 3 } }, balls = { { P, 4 }, { G2.ITEMS.POKE_BALL.index, 2 } } },
    { name = "duplicate key item", items = {}, keys = { { G2.ITEMS.BICYCLE.index }, { G2.ITEMS.BICYCLE.index } } },
    { name = "ball in item pocket", items = { { G2.ITEMS.POKE_BALL.index, 5 }, { P, 2 } } },
  }
  for _, c in ipairs(layouts) do
    local src = bagOf(c.items, c.pc, c.keys, c.balls)
    local save = decode(src, v)
    local out = fresh(save, v)
    local label = ("%s: %s is exact without a template"):format(v, c.name)
    eq(slice(out, L.wNumItems, 42), slice(src, L.wNumItems, 42), label .. " (items)")
    eq(slice(out, L.wNumKeyItems, 27), slice(src, L.wNumKeyItems, 27), label .. " (key items)")
    eq(slice(out, L.wNumBalls, 26), slice(src, L.wNumBalls, 26), label .. " (balls)")
    eq(slice(out, L.wNumPCItems, 102), slice(src, L.wNumPCItems, 102), label .. " (pc)")
    local again = decode(out, v)
    local out2 = fresh(again, v)
    eq(out2, out, label .. " and is a fixed point")
  end
  local save = decode(bagOf({ { P, 3 }, { R, 4 }, { P, 5 } }), v)
  save.inventory.POTION = 20
  local out = fresh(save, v)
  eq(out:byte(L.wNumItems + 1), 3, v .. ": an engine change keeps the surviving slots in place")
  eq(table.concat({ out:byte(L.wItems + 1, L.wItems + 6) }, ","), table.concat({ P, 15, R, 4, P, 5 }, ","),
    v .. ": the growth fills the first POTION slot, as PutItemInPocket does")
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local function mailImage(fill)
    return build(v, { party = { G2.mon({ item = G2.ITEMS.FLOWER_MAIL.index }) }, patch = function(b)
      fill(b)
    end })
  end
  local odd = mailImage(function(b)
    for _, base in ipairs({ L.sPartyMail, L.sPartyMailBackup }) do
      local m = { 0x87, 0x84, 0x8B, 0x8B, 0x8E, 0x50, 0x91, 0x92, 0x93 }
      for k = 0, 46 do b[base + k] = 0x55 end
      for k, c in ipairs(m) do b[base + k - 1] = c end
      b[base + 0x21], b[base + 0x22], b[base + 0x23] = 0x80, 0x81, 0x50
      b[base + 0x24] = 0x99
      b[base + 0x2B], b[base + 0x2C], b[base + 0x2D], b[base + 0x2E] = 0x12, 0x34, 25, 0x9E
    end
    for _, base in ipairs({ L.sMailboxCount, L.sMailboxCountBackup }) do
      b[base] = 1
      for k = 0, 46 do b[base + 1 + k] = (k * 5 + 1) % 200 + 1 end
      b[base + 1 + 0x2E] = 0x9E
    end
  end)
  local save = decode(odd, v)
  check(save.mail.party[1] and save.mail.party[1].cartRaw ~= nil, v .. ": a letter with junk after its terminators carries its raw bytes")
  check(save.mail.box[1] and save.mail.box[1].cartRaw ~= nil, v .. ": so does an odd mailbox letter")
  local out = fresh(save, v)
  eq(slice(out, L.sPartyMail, 47), slice(odd, L.sPartyMail, 47), v .. ": the party letter is exact without a template")
  eq(slice(out, L.sPartyMailBackup, 47), slice(odd, L.sPartyMailBackup, 47), v .. ": and its backup")
  eq(slice(out, L.sMailboxCount, 48), slice(odd, L.sMailboxCount, 48), v .. ": the mailbox letter is exact")
  eq(slice(out, L.sMailboxCountBackup, 48), slice(odd, L.sMailboxCountBackup, 48), v .. ": and its backup")
  save.mail.party[1].author = "CHANGED"
  out = fresh(save, v)
  check(slice(out, L.sPartyMail, 47) ~= slice(odd, L.sPartyMail, 47), v .. ": editing the letter writes the edit")
  eq(decode(out, v).mail.party[1].author, "CHANGED", v .. ": and reads back")
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local function put(b, at, bytes, n)
    for k = 0, n - 1 do b[at + k] = 0x50 end
    for k, c in ipairs(bytes) do b[at + k - 1] = c end
  end
  local sites = {}
  local function site(name, getAt, n)
    sites[#sites + 1] = { name = name, at = getAt, n = n }
  end
  site("player", function() return L.wPlayerName end, 11)
  site("rival", function() return L.wRivalName end, 11)
  site("mom", function() return L.wMomsName end, 11)
  site("party nickname", function() return L.wPartyMonNicknames end, 11)
  site("party ot", function() return L.wPartyMonOTs end, 11)
  site("box name", function() return L.wBoxNames + 9 end, 9)
  site("box nickname", function() return L.boxes[2] + 0x372 end, 11)
  site("box ot", function() return L.boxes[2] + 0x296 end, 11)
  local patterns = {
    { "unmapped control bytes", { 0x00, 0x01, 0x04, 0x14, 0x80 } },
    { "ligatures and accents", { 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xE0, 0xE1, 0xE2, 0xE4, 0xE5, 0xE6, 0xEF, 0xF5 } },
    { "full width no terminator", { 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A } },
    { "junk after the terminator", { 0x80, 0x50, 0x99, 0x42, 0x13 } },
    { "high bytes", { 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF } },
    { "ascii-looking", { 0xA0, 0xA1, 0xBF, 0xF6, 0xFF, 0x7F, 0x60 } },
  }
  for _, st in ipairs(sites) do
    for _, pat in ipairs(patterns) do
      local bytes = pat[2]
      local n = st.n
      local src = build(v, { boxes = { [2] = G2.boxOf(1, 3) }, party = { G2.mon() }, patch = function(b)
        put(b, st.at(), bytes, n)
      end })
      local save = decode(src, v)
      local out = fresh(save, v)
      local want = slice(src, st.at(), n)
      local got = slice(out, st.at(), n)
      if got ~= want then
        check(false, ("%s %s (%s): got %s want %s"):format(v, st.name, pat[1],
          (got:gsub(".", function(c) return ("%02X"):format(c:byte()) end)),
          (want:gsub(".", function(c) return ("%02X"):format(c:byte()) end))))
      else
        check(true, "ok")
      end
    end
  end
  local byteSurvives = 0
  for code = 0, 255 do
    if code ~= 0x50 then
      local src = build(v, { patch = function(b) put(b, L.wPlayerName, { 0x80, code, 0x81 }, 11) end })
      local out = fresh(decode(src, v), v)
      if slice(out, L.wPlayerName, 11) == slice(src, L.wPlayerName, 11) then byteSurvives = byteSurvives + 1
      else check(false, ("%s: name byte 0x%02X survives a templateless round trip"):format(v, code)) end
    end
  end
  eq(byteSurvives, 255, v .. ": every possible name byte survives")
  local src = build(v, { patch = function(b) put(b, L.wPlayerName, { 0x00, 0x80 }, 11) end })
  local save = decode(src, v)
  save.player.name = "RENAMED"
  local out = fresh(save, v)
  eq(decode(out, v).player.name, "RENAMED", v .. ": a rename wins over the carried bytes")
  eq(out:byte(L.wPlayerName + 8), 0x50, v .. ": and is padded the cartridge way")
  local templated = Gen2Save.encode(decode(src, v), v, src, DATA)
  eq(slice(templated, L.wPlayerName, 11), slice(src, L.wPlayerName, 11), v .. ": unchanged names with a template are exact too")
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local function exportMon(species, dvs, shiny, name)
    local save = decode(build(v, { party = { G2.mon({ species = species }) } }), v)
    local mon = save.party[1]
    mon.species = name
    mon.dvs = dvs
    mon.shiny = shiny
    local out, err = Gen2Save.encode(save, v, nil, DATA)
    return out, err, mon
  end
  local function dvBytes(out)
    local o = L.wPartyMons + 0x15
    return out:byte(o + 1), out:byte(o + 2)
  end
  local function isShiny(a, b)
    local atk, def, spd, spc = math.floor(a / 16), a % 16, math.floor(b / 16), b % 16
    return def == 10 and spd == 10 and spc == 10 and (atk % 4 == 2 or atk % 4 == 3)
  end
  local out = exportMon(155, { attack = 5, defense = 3, speed = 4, special = 9 }, true, "CYNDAQUIL")
  check(out ~= nil, v .. ": a forced shiny exports")
  local a, b = dvBytes(out)
  check(isShiny(a, b), v .. ": and carries a DV pattern the cartridge reads as shiny")
  local oldMale = 5 >= math.floor(0x1F / 16)
  local newMale = math.floor(a / 16) >= math.floor(0x1F / 16)
  eq(newMale, oldMale, v .. ": the attack DV choice keeps the gender")
  out = exportMon(155, { attack = 5, defense = 3, speed = 4, special = 9 }, false, "CYNDAQUIL")
  a, b = dvBytes(out)
  eq(a, 0x53, v .. ": a mon that is not shiny keeps its DVs")
  out = exportMon(155, { attack = 6, defense = 10, speed = 10, special = 10 }, true, "CYNDAQUIL")
  a, b = dvBytes(out)
  eq(a * 256 + b, 0x6AAA, v .. ": DVs that already read shiny are untouched")
  local none, why = exportMon(201, { attack = 0, defense = 0, speed = 0, special = 0 }, true, "UNOWN")
  eq(none, nil, v .. ": a forced-shiny Unown whose letter no shiny pattern can keep is refused")
  check(type(why) == "string" and why:find("UNOWN", 1, true) ~= nil, v .. ": by name -- " .. tostring(why))
  out = exportMon(201, { attack = 2, defense = 2, speed = 2, special = 2 }, true, "UNOWN")
  check(out == nil or isShiny(dvBytes(out)), v .. ": a letter a shiny pattern can keep is converted or refused, never dropped")
end

local Compat = require("src.save_convert.Compat")
local Syms = require("src.save_convert.Gen2State")

local function sum16s(s, from, toExcl)
  local v = 0
  for i = from, toExcl - 1 do v = (v + s:byte(i + 1)) % 65536 end
  return v
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local src
  for money = 0, 2000 do
    local candidate = build(v, { money = money })
    if sum16s(candidate, L.sGameData, L.sGameDataEnd) % 256 == 0 then src = candidate break end
  end
  check(src ~= nil, v .. ": a cart whose primary sum has low byte 0 exists in the sweep")
  if src then
    local save = decode(src, v)
    eq(Gen2Save.encode(save, v, src, DATA), src, v .. ": an unchanged export of such a cart is the cart itself")
    save.player.coins = 7
    local out = assert(Gen2Save.encode(save, v, src, DATA))
    eq(sum16s(out, L.sGameData, L.sGameDataEnd) % 256 ~= 0, true, v .. ": a changed export avoids a zero low byte")
    local report = Compat.check(out, v)
    eq(#report.errors, 0, v .. ": and passes every reader rule -- " .. Compat.describe(report))
    local diffs = {}
    for i = 1, #src do
      if src:byte(i) ~= out:byte(i) then diffs[#diffs + 1] = i - 1 end
    end
    local allowed = {}
    for _, seg in ipairs(L.backupSave.segments) do allowed[#allowed + 1] = { seg[2], seg[2] + seg[3] } end
    local stray = 0
    for _, o in ipairs(diffs) do
      local ok = o == L.wGreensName + 10 or o == L.wCoins or o == L.wCoins + 1 or o == L.sChecksum or o == L.sChecksum + 1 or o == L.backupSave.checksum
        or o == L.backupSave.checksum + 1
      for _, r in ipairs(allowed) do if o >= r[1] and o < r[2] then ok = true end end
      if not ok then stray = stray + 1 end
    end
    eq(stray, 0, v .. ": nothing but the pad byte, its mirror and the sums differ")
    eq(decode(out, v).player.money, save.player.money, v .. ": the data is unchanged")
    eq(decode(out, v).player.coins, 7, v .. ": and the edit is in")
  end
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local src = build(v, { boxes = { [1] = G2.boxOf(2, 3) }, currentBox = 0, patch = function(b, LL) b[LL.sBox] = 0x7F end })
  local save = decode(src, v)
  local out, why = Gen2Save.encode(save, v, src, DATA)
  check(out ~= nil, v .. ": a junk sBox does not stop the export -- " .. tostring(why))
  if out then
    eq(slice(out, L.sBox, Gen2Save.BOX_BYTES), slice(out, L.boxes[1], Gen2Save.BOX_BYTES), v .. ": sBox is rewritten from the archive the game loads")
    eq(#Compat.check(out, v).errors, 0, v .. ": and the file passes every reader rule")
  end
end

do
  local c = build("crystal", {})
  local g = build("gold", {})
  local none, why = Gen2Save.decode(c, "gold", DATA)
  eq(none, nil, "a Crystal save picked as Gold is refused")
  check(type(why) == "string" and why:find("Crystal", 1, true) ~= nil and why:find("Japanese", 1, true) == nil,
    "and named as Crystal, not as Japanese -- " .. tostring(why))
  none, why = Gen2Save.decode(g, "crystal", DATA)
  eq(none, nil, "a Gold save picked as Crystal is refused")
  check(type(why) == "string" and why:find("Gold or Silver", 1, true) ~= nil, "and named -- " .. tostring(why))
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local src = build(v, { party = { G2.mon() }, patch = function(b, LL)
    for k = 0, 10 do b[LL.wPartyMonNicknames + k] = 0x50 end
  end })
  local save = decode(src, v)
  eq(save.party[1].nickname, "", v .. ": a blank nickname imports blank")
  eq(slice(fresh(save, v), L.wPartyMonNicknames, 11), slice(src, L.wPartyMonNicknames, 11), v .. ": and exports blank, not as the species name")
end

for _, v in ipairs(VERSIONS) do
  local at = Syms.symsFor(v).wPlayerDirection
  local src = build(v, {})
  local save = decode(src, v)
  eq(save.position.facing, "down", v .. ": a zero direction byte imports as facing down")
  for name, bits in pairs({ down = 0, up = 4, left = 8, right = 12 }) do
    save.position.facing = name
    local out = fresh(save, v)
    eq(out:byte(at + 1) % 16 - out:byte(at + 1) % 4, bits, v .. ": " .. name .. " writes OW_" .. name:upper())
    eq(decode(out, v).position.facing, name, v .. ": " .. name .. " imports back")
  end
  local odd = build(v, { patch = function(b) b[at] = 0xF5 end })
  local d = decode(odd, v)
  eq(d.position.facing, "up", v .. ": other bits do not hide the facing")
  eq(Gen2Save.encode(d, v, odd, DATA):byte(at + 1), 0xF5, v .. ": and are kept with it under a template")
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save = decode(build(v, {}), v)
  save.bikeShopCall = true
  local out = fresh(save, v)
  eq(math.floor(out:byte(L.wStatusFlags2 + 1) / 16) % 2, 1, v .. ": the legacy bikeShopCall key sets ENGINE_BIKE_SHOP_CALL_ENABLED")
  save.engineFlags[v == "crystal" and 20 or 19] = nil
  save.bikeShopCall = false
  eq(math.floor(fresh(save, v):byte(L.wStatusFlags2 + 1) / 16) % 2, 0, v .. ": and cleared it is clear")
end

T.finish()
