package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local K = require("tests.save_compat._codec")
local D = require("tests.save_compat._gen3_decode")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")
local Compat = require("src.save_convert.Compat")
local Gen3Save = require("src.save_convert.Gen3Save")
local SaveConvert = require("src.save_convert.SaveConvert")

local VERSIONS = { "firered", "leafgreen", "emerald" }
local FAMILY = { firered = "frlg", leafgreen = "frlg", emerald = "emerald" }
local fixtures = {}
for _, c in ipairs(G3.cases()) do fixtures[c.id] = c end

local function fx(v, name) return fixtures["g3." .. v .. "." .. name].bytes end
local function import(v, bytes) return assert(K.import(3, v, bytes)) end
local function fresh(v, bytes)
  local s = import(v, bytes)
  s.modData.cartImage = nil
  return s
end
local function errors(bytes, v) return #Compat.check(bytes, v).errors end
local function w32(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 + s:byte(o + 3) * 65536 + s:byte(o + 4) * 16777216 end

local function build(v, edit)
  local w = G3.base(v)
  if edit then edit(w) end
  return G3.emit(w)
end

local function player(v)
  local w = G3.base(v)
  return B.getLE(w.sb2, 0x0A, 2), B.getLE(w.sb2, 0x0C, 2)
end

for _, v in ipairs(VERSIONS) do
  local fam = FAMILY[v]
  local s = fresh(v, fx(v, "basic"))
  s.encryptionKey, s.modData.cartKey = v == "emerald" and 0 or nil, nil
  local out = assert(K.export(3, v, s, false))
  local d = assert(D.decode(out, fam))
  check(Gen3Save.forVersion(v).keyValid(d.key, d.powder), v .. " derived key is valid")
  if fam == "frlg" then
    eq(d.code, 1, v .. " SB2 0xAC is the FRLG marker")
    check(d.powderWord ~= 0, v .. " SB2 0xAF8 is nonzero")
  else
    check(d.key ~= 0 and d.key ~= 1, v .. " SB2 0xAC is a real Emerald key")
  end
  eq(errors(out, v), 0, v .. " key-0 slot exports a reader-valid file")
  eq(K.export(3, v, s, false), out, v .. " the derived key is deterministic")
  eq(d.money, s.money, v .. " money is encrypted with the derived key")
  local back = import(v, out)
  eq(Gen3Save.forVersion(v).storedKey(back), d.key, v .. " import stores the key in the save")
  local s2 = fresh(v, fx(v, "basic"))
  s2.encryptionKey, s2.modData.cartKey = nil, nil
  s2.meta = { playthroughId = "other-run" }
  local d2 = D.decode(assert(K.export(3, v, s2, false)), fam)
  check(d2.key ~= d.key, v .. " a different playthrough derives a different key")

  local tid, sid = player(v)
  local s3 = fresh(v, fx(v, "basic"))
  s3.encryptionKey, s3.modData.cartKey = nil, nil
  s3.berryPowder = Gen3Save.forVersion(v).deriveKey(tid, sid, nil, 0)
  local d3 = D.decode(assert(K.export(3, v, s3, false)), fam)
  check(d3.key ~= s3.berryPowder, v .. " the derived key never equals the berry powder")
  check(d3.powderWord ~= 0, v .. " the powder word stays nonzero")
  eq(d3.powder, s3.berryPowder, v .. " berry powder survives")

  for _, bad in ipairs(fam == "frlg" and { 0 } or { 0, 1 }) do
    local cart = build(v, function(w)
      local o = w.F.key
      local key = B.getLE(w.sb2, o, 4)
      B.le(w.sb2, o, bad, 4)
      w.key = bad
      if fam == "emerald" then w.key = bad end
      G3.setMoney(w, 4242)
      G3.setPocket(w, 1, { { 13, 7 } })
      for i = 0, 63 do B.le(w.sb1, w.F.gameStats + i * 4, i * 3 + key % 7, 4) end
    end)
    local a = D.decode(cart, fam)
    local sv = import(v, cart)
    local out2 = assert(K.export(3, v, sv, cart))
    local b2 = D.decode(out2, fam)
    check(b2.key ~= bad and Gen3Save.forVersion(v).keyValid(b2.key, b2.powder), ("%s template key %d is replaced"):format(v, bad))
    eq(b2.money, 4242, v .. " re-keyed money")
    eq(b2.pockets[1][1][2], 7, v .. " re-keyed bag quantity")
    local statsSame = true
    for i = 0, 63 do if a.stats[i] ~= b2.stats[i] then statsSame = false end end
    check(statsSame, v .. " re-keyed game stats")
    eq(errors(out2, v), 0, v .. " re-keyed export is reader-valid")
  end
end

do
  local rs = build("emerald", function(w)
    for i = 0x890, w.sb2.size - 1 do w.sb2[i] = 0 end
    for i = 0x3AC0, w.sb1.size - 1 do w.sb1[i] = 0 end
  end)
  eq(Gen3Save.sniff(rs), "rs", "an RS-shaped image sniffs as Ruby/Sapphire")
  local s, err = SaveConvert.importSav(rs, "emerald", "emerald")
  eq(s, nil, "Emerald refuses a Ruby/Sapphire save")
  eq(err, Gen3Save.forVersion("emerald").MSG.rs, "the refusal names Ruby/Sapphire")
  local s2, err2 = SaveConvert.importSav(rs, "firered", "firered")
  eq(s2, nil, "FireRed refuses a Ruby/Sapphire save")
  eq(err2, Gen3Save.MSG.rs, "FireRed names Ruby/Sapphire")
  check(require("src.core.GameVersion").VERSIONS.ruby == nil, "no Ruby GameVersion exists")
end

do
  local out = assert(K.export(3, "emerald", fresh("emerald", fx("emerald", "basic")), false))
  local blk = Compat.gen3Blocks(out, "emerald")
  eq(blk.sb2:byte(0xEE1 + 1), 0xFF, "opponentNames[0][0] is EOS")
  eq(blk.sb2:byte(0xEE9 + 1), 0xFF, "opponentNames[1][0] is EOS")
end

for _, v in ipairs(VERSIONS) do
  local junk = {}
  for i = 1, 0x2000 do junk[i] = string.char((i * 37) % 256) end
  local cart = fx(v, "basic")
  cart = cart:sub(1, 0x1E000) .. table.concat(junk) .. cart:sub(0x20001)
  local out = assert(K.export(3, v, import(v, cart), cart))
  eq(out:sub(0x1E001, 0x20000), cart:sub(0x1E001, 0x20000), v .. " sectors 30/31 ride verbatim")
  local rep = Compat.check(out, v)
  eq(#rep.errors, 0, v .. " carried extra sectors are not an error")
  local warned = false
  for _, w in ipairs(rep.warnings) do if w.rule == "gen3.extraSector" then warned = true end end
  check(warned, v .. " carried invalid extra sectors raise a validator warning")
  local bare = assert(K.export(3, v, fresh(v, cart), false))
  eq(bare:sub(0x1E001, 0x20000), string.rep("\255", 0x2000), v .. " a templateless export leaves sectors 30/31 blank")
end

for _, v in ipairs(VERSIONS) do
  local cart = fx(v, "max_stacks")
  local s = import(v, cart)
  eq(Gen3Save.forVersion(v).slotTemplate(s), cart, v .. " import stores the cart image in the slot")
  local viaSlot = assert(K.export(3, v, s, nil))
  eq(viaSlot, assert(K.export(3, v, import(v, cart), cart)), v .. " the slot image is the same template as the file")
  eq(Gen3Save.forVersion(v).readBlocks(viaSlot).counter, Gen3Save.forVersion(v).readBlocks(cart).counter + 1,
    v .. " the slot-template export is the cart's next save")
  local other = import(v, cart)
  other.trainerId = (other.trainerId + 1) % 65536
  local d = Gen3Save.forVersion(v).decode(assert(K.export(3, v, other, nil)))
  eq(d.counter, 1, v .. " a slot image of another player is not used")
end

do
  local tid, sid = player("firered")
  local cart = build("firered", function(w)
    local mons = {}
    for i = 1, 3 do mons[i] = G3.mon({ pid = 0x7100 + i, tid = tid, sid = sid, origins = 5 + 5 * 128 + 4 * 2048 }) end
    G3.setParty(w, mons)
    for b = 1, 14 do for sl = 1, 30 do G3.setBoxMon(w, b, sl, nil) end end
  end)
  local s = SaveConvert.importSav(cart, "firered", "firered")
  eq(s.modData.cartGame, "leafgreen", "a cart whose own mons were met in LeafGreen is marked LeafGreen")
  local lg = SaveConvert.importSav(cart, "leafgreen", "leafgreen")
  eq(lg.modData.cartGame, "leafgreen", "LeafGreen into LeafGreen")
  local fr = SaveConvert.importSav(fx("firered", "basic"), "leafgreen", "leafgreen")
  eq(fr.modData.cartGame, "firered", "a FireRed cart imported into LeafGreen stays marked FireRed")
end

do
  local s = import("firered", fx("firered", "basic"))
  s.map = "FR_VIRIDIAN_CITY"
  local out, err = K.export(3, "firered", s, fx("firered", "basic"))
  eq(out, nil, "a map with no layout id refuses even with a template")
  eq(err, Gen3Save.MSG.noData, "the refusal asks for the ROM")
  local s2 = import("firered", fx("firered", "basic"))
  s2.x = s2.x + 1
  local opts = K.gen3Opts("firered", fx("firered", "basic"))
  opts.mapLayoutId = function() return nil end
  local ok = assert(Gen3Save.forVersion("firered").exportPort(s2, opts))
  local c = Gen3Save.decode(ok)
  eq(c.posX, s2.x, "same map: the template layout id carries the new position")
end

do
  local s = import("firered", fx("firered", "basic"))
  s.party[1].speciesNumbering, s.party[1].species = "national", 999
  local opts = K.gen3Opts("firered", nil)
  opts.speciesFromNational = function() return nil end
  local out, err = Gen3Save.forVersion("firered").exportPort(s, opts)
  eq(out, nil, "an unconvertible species refuses the export")
  check(type(err) == "string" and err:find("999", 1, true) and err:find("party slot 1", 1, true), "the error names the mon")
end

do
  local cart = build("firered", function(w)
    local r = 0x30D0
    B.le(w.sb1, r, 31 + 7 * 32 + 3 * 1024 + 2 ^ 30, 4)
    B.le(w.sb1, r + 4, 0xC8323459, 4)
    B.le(w.sb1, r + 8, 245, 2)
    B.le(w.sb1, r + 0x0A, 0xA4, 2)
    B.put(w.sb1, r + 0x0C, 50, 0x40)
    B.put(w.sb1, r + 0x13, 1)
    local lr = 0xA98
    local nm = G3.text("RIVAL", 8)
    for i = 1, 8 do w.sb2[lr + i - 1] = nm[i] end
    B.le(w.sb2, lr + 8, 4321, 2); B.le(w.sb2, lr + 10, 3, 2); B.le(w.sb2, lr + 12, 1, 2)
    for i = 1, 4 do B.put(w.sb2, lr + i * 16, 0xFF) end
    local tn = 0x3BA8
    B.le(w.sb1, tn, 0x00011234, 4)
    local nm2 = G3.text("FRIEND", 8)
    for i = 1, 8 do w.sb1[tn + 3 + i] = nm2[i] end
  end)
  local s = import("firered", cart)
  eq(s.roamer and s.roamer.species, 245, "FRLG roamer species imports")
  eq(s.roamer.ivs.attack, 7, "roamer IVs use the engine's key names")
  eq(s.roamer.active, true, "roamer active")
  eq(s.linkBattleRecords[1].name, "RIVAL", "FRLG link battle record imports")
  eq(s.linkBattleRecords[1].wins, 3, "link record wins")
  eq(s.trainerNameRecords[1].name, "FRIEND", "FRLG trainer name record imports")
  local out = assert(K.export(3, "firered", fresh("firered", cart), false))
  local a, b = Compat.gen3Blocks(cart, "frlg"), Compat.gen3Blocks(out, "frlg")
  eq(b.sb1:sub(0x30D1, 0x30DE), a.sb1:sub(0x30D1, 0x30DE), "templateless export keeps the roamer")
  eq(b.sb1:byte(0x30D0 + 0x13 + 1), 1, "roamer stays active")
  local again = import("firered", out)
  eq(again.linkBattleRecords[1] and again.linkBattleRecords[1].name, "RIVAL", "templateless export keeps the link record")
  eq(again.linkBattleRecords[1].wins + again.linkBattleRecords[1].losses * 100, 103, "link record counts survive")
  eq(b.sb1:sub(0x3BA9, 0x3BAA) .. b.sb1:sub(0x3BAD, 0x3BB4), a.sb1:sub(0x3BA9, 0x3BAA) .. a.sb1:sub(0x3BAD, 0x3BB4),
    "templateless export keeps the trainer name record")
  local port = Gen3Save.forVersion("firered").port
  check(port and type(port.finishImport) == "function", "FRLG has an import finisher")
  local save = import("firered", fx("firered", "all_dex"))
  local nat = {}
  for i = 1, 386 do nat[i] = i end
  port.finishImport(save, { national = { toSpecies = nat } })
  check(save.dex.seen[1] and save.dex.owned[1], "FRLG Pokedex resolves at import")
  eq(save.modData.cartImport.dexSeen, nil, "the deferred dex list is consumed")
end

for _, v in ipairs(VERSIONS) do
  local cart = build(v, function(w) for b = 0, 13 do w.storage[0x83C2 + b] = (b * 5) % 16 end end)
  local s = import(v, cart)
  for b = 1, 14 do eq(s.storage.boxes[b].wallpaper, (b - 1) * 5 % 16 + 1, v .. " box " .. b .. " wallpaper w + 1") end
  local out = Compat.gen3Blocks(assert(K.export(3, v, fresh(v, cart), false)), FAMILY[v])
  for b = 0, 13 do eq(out.storage:byte(0x83C2 + b + 1), (b * 5) % 16, v .. " box " .. (b + 1) .. " wallpaper round trip") end
  s = fresh(v, cart)
  s.storage.boxes[3] = nil
  s.storage.boxes[4].wallpaper = 18
  local o2 = Compat.gen3Blocks(assert(K.export(3, v, s, false)), FAMILY[v])
  eq(o2.storage:byte(0x83C2 + 2 + 1), 2, v .. " a sparse box takes the engine default wallpaper")
  eq(o2.storage:byte(0x83C2 + 3 + 1), v == "emerald" and 16 or 15, v .. " an out-of-range wallpaper clamps to the last one")
end

for _, v in ipairs(VERSIONS) do
  local s = fresh(v, fx(v, "full_party_statuses"))
  s.party[1].cartExtra, s.party[1].nickname, s.party[1].otName = nil, "Ré", "Ädé"
  local out = assert(K.export(3, v, s, false))
  local blk = Compat.gen3Blocks(out, FAMILY[v])
  local off = (FAMILY[v] == "emerald" and 0x238 or 0x38)
  eq(blk.sb1:sub(off + 9, off + 18), string.char(0xCC, 0x1B, 0xFF) .. string.rep("\255", 7), v .. " nickname 0xFF padded with é")
  eq(blk.sb1:sub(off + 0x15, off + 0x1B), string.char(0xF1, 0xD8, 0x1B, 0xFF, 0xFF, 0xFF, 0xFF), v .. " OT 0xFF padded with Ä")
  local back = import(v, out)
  eq(back.party[1].nickname, "Ré", v .. " Latin nickname decodes")
  eq(back.party[1].otName, "Ädé", v .. " Latin OT decodes")
end
do
  local codec = Gen3Save
  local bad = {}
  for c = 0, 0xF8 do
    local s = string.char(c, 0xFF)
    local again = codec.encodeString(codec.decodeString(s, 0, 2), 2, 0xFF)
    if again ~= s then bad[#bad + 1] = ("%02X"):format(c) end
  end
  eq(table.concat(bad, " "), "", "every name byte 0x00-0xF8 survives decode then encode")
end

do
  local cart = fx("emerald", "basic")
  local s = import("emerald", cart)
  local before = Gen3Save.forVersion("emerald").decode(cart)
  if before.player then
    s.facing = before.player.facing == 2 and "left" or "up"
    local out = assert(K.export(3, "emerald", s, cart))
    local after = Gen3Save.forVersion("emerald").decode(out)
    eq(require("src.save_convert.gen3_layouts.common").FACING[after.player.facing], s.facing, "the player's facing reaches the cart")
  end
  local n = fresh("emerald", cart)
  n.dex = n.dex or {}
  n.dex.national = true
  local d = Gen3Save.forVersion("emerald").decode(assert(K.export(3, "emerald", n, false)))
  eq(d.dexMode, 1, "unlocking the national dex sets DEX_MODE_NATIONAL")
end

for _, c in ipairs(G3.cases()) do
  if not c.refuse then
    local out = K.export(3, c.version, import(c.version, c.bytes), c.bytes)
    local mine = D.decode(out, FAMILY[c.version])
    local src = D.decode(c.bytes, FAMILY[c.version])
    local theirs = Gen3Save.forVersion(c.version).decode(out)
    local diffs = D.diff(src, mine)
    local allowed = { [".counter"] = true }
    local real = {}
    for _, p in ipairs(diffs) do if not allowed[p] then real[#real + 1] = p end end
    eq(table.concat(real, " "), "", c.id .. " independent decode of the export equals the source")
    eq(mine.money, theirs.money, c.id .. " codec and independent decoder agree on money")
    eq(mine.key, theirs.encryptionKey, c.id .. " agree on key")
    eq(#mine.party, #theirs.party, c.id .. " agree on party size")
  end
end

local seed = tonumber(os.getenv("SAVE_COMPAT_SEED")) or 3
local N = tonumber(os.getenv("SAVE_COMPAT_FUZZ_N")) or 25
local function rng()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed
end

for _, v in ipairs(VERSIONS) do
  local base = fx(v, "full_party_statuses")
  local raised = 0
  for i = 1, N do
    local bytes = base
    for _ = 1, 1 + rng() % 64 do
      local at = rng() % #bytes
      bytes = bytes:sub(1, at) .. string.char(rng() % 256) .. bytes:sub(at + 2)
    end
    local cut = ({ #bytes, 0x1FFFF, 0x10000, 0x20040, 100, 0x20010 })[i % 6 + 1]
    if cut < #bytes then bytes = bytes:sub(1, cut) else bytes = bytes .. string.rep("\0", cut - #bytes) end
    local ok, save = pcall(SaveConvert.importSav, bytes, v, v)
    if not ok then raised = raised + 1
    elseif save then
      local ok2 = pcall(SaveConvert.exportSav, save, v, bytes)
      if not ok2 then raised = raised + 1 end
      local ok3 = pcall(Gen3Save.forVersion(v).exportPort, save, K.gen3Opts(v, bytes))
      if not ok3 then raised = raised + 1 end
    end
  end
  eq(raised, 0, v .. " corruption and truncation never raise a Lua error")

  local sealedRaised, sealedImported = 0, 0
  for _ = 1, N do
    local cart = build(v, function(w)
      for _ = 1, 1 + rng() % 200 do
        local blk = ({ w.sb2, w.sb1, w.storage })[rng() % 3 + 1]
        blk[rng() % blk.size] = rng() % 256
      end
    end)
    local ok, save = pcall(SaveConvert.importSav, cart, v, v)
    if not ok then sealedRaised = sealedRaised + 1
    elseif save then
      sealedImported = sealedImported + 1
      local ok2, out = pcall(Gen3Save.forVersion(v).exportPort, save, K.gen3Opts(v, cart))
      if not ok2 then sealedRaised = sealedRaised + 1
      elseif out then
        local ok3 = pcall(SaveConvert.importSav, out, v, v)
        if not ok3 then sealedRaised = sealedRaised + 1 end
      end
    end
  end
  eq(sealedRaised, 0, v .. " checksum-valid corrupted sections never raise a Lua error")
  check(sealedImported > 0, v .. " the sealed fuzz reaches the decoder")

  local fam = FAMILY[v]
  local mism = 0
  for _ = 1, N do
    local money, coins = rng() % 1000000, rng() % 10000
    local cart = build(v, function(w)
      G3.setMoney(w, money)
      B.le(w.sb1, w.F.coins, require("bit").bxor(coins, w.key % 65536) % 65536, 2)
    end)
    local d = D.decode(assert(K.export(3, v, import(v, cart), cart)), fam)
    if d.money ~= money or d.coins ~= coins then mism = mism + 1 end
  end
  eq(mism, 0, v .. " mutated modeled fields reproduce through import/export")

  local carried = 0
  local region = fam == "frlg" and { "sb1", 0x3120, 0x300 } or { "sb1", 0x322C, 0x300 }
  for _ = 1, N do
    local at, val = region[2] + rng() % region[3], rng() % 256
    local cart = build(v, function(w) w[region[1]][at] = val end)
    local out = Compat.gen3Blocks(assert(K.export(3, v, import(v, cart), cart)), fam)
    if out[region[1]]:byte(at + 1) == val then carried = carried + 1 end
  end
  eq(carried, N, v .. " mutated unmodeled bytes are carried through")

  local wrong = 0
  for _ = 1, N do
    local s = fresh(v, fx(v, "basic"))
    s.money = rng() % 1000000
    for _, m in ipairs(s.party) do
      m.personality = rng() * 2 % 4294967296
      m.exp = rng() % 100000
    end
    local out = assert(K.export(3, v, s, false))
    local d = D.decode(out, fam)
    if d.money ~= s.money or errors(out, v) ~= 0 then wrong = wrong + 1 end
    for i, m in ipairs(s.party) do
      if not d.party[i] or d.party[i].pid ~= m.personality or d.party[i].exp ~= m.exp or not d.party[i].checksumOk then
        wrong = wrong + 1
      end
    end
  end
  eq(wrong, 0, v .. " random models export to what an independent decoder reads back")
end

T.finish()
