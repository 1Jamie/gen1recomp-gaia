package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local B = require("tests.fixtures.save.bytes")
local G2 = require("tests.fixtures.save.gen2_build")
local G3 = require("tests.fixtures.save.gen3_build")
local D3 = require("tests.save_compat._gen3_decode")
local Ref2 = require("tests.save_compat._gen2_reference")
local Compat = require("src.save_convert.Compat")
local SaveConvert = require("src.save_convert.SaveConvert")
local Gen2Save = require("src.save_convert.Gen2Save")

local N = tonumber(os.getenv("SAVE_COMPAT_FUZZ_N")) or 40
local state = tonumber(os.getenv("SAVE_COMPAT_FUZZ_SEED")) or 77123
local function rnd(a, b)
  state = (state * 48271) % 2147483647
  return a + state % (b - a + 1)
end

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local L = G2.layout(v)
  local ref = Ref2
  local base = G2.build({ version = v, party = { G2.mon(), G2.mon({ species = 25 }) },
    items = { { G2.ITEMS.POTION.index, 5 } }, currentBox = 3 })
  local bad = 0
  for n = 1, N do
    local b = B.fromString(base)
    local field = rnd(1, 6)
    local want
    if field == 1 then want = rnd(0, 65535); B.be(b, L.wPlayerID, want, 2)
    elseif field == 2 then want = rnd(0, 999999); B.be(b, L.wMoney, want, 3)
    elseif field == 3 then want = rnd(0, 9999); B.be(b, L.wCoins, want, 2)
    elseif field == 4 then want = rnd(0, 255); b[L.wBadges] = want
    elseif field == 5 then want = rnd(0, 255); b[L.wKantoBadges] = want
    else want = rnd(0, 9999); B.be(b, L.wGameTimeHours, want, 2) end
    G2.seal(b, v)
    local src = B.pack(b)
    local save = K.import(2, v, src)
    local out = save and K.export(2, v, save, src)
    local got = out and ref.decode(out, v)
    local read
    if got then
      read = ({ got.id, got.money, nil, got.johto, got.kanto, got.hours })[field]
    end
    if not (out == src and (field == 3 or read == want)) then
      bad = bad + 1
      if bad <= 3 then check(false, ("%s modeled field %d = %s does not round trip"):format(v, field, tostring(want))) end
    end
  end
  eq(bad, 0, ("%s: %d mutated modeled offsets round trip byte for byte"):format(v, N))
end

for _, v in ipairs({ "firered", "leafgreen", "emerald" }) do
  local fam = v == "emerald" and "emerald" or "frlg"
  local bad = 0
  for n = 1, N do
    local want = { tid = rnd(0, 65535), sid = rnd(0, 65535), hours = rnd(0, 999), minutes = rnd(0, 59),
      gender = rnd(0, 1), money = rnd(0, 999999) }
    local cart = G3.emit((function()
      local w = G3.base(v)
      B.le(w.sb2, 0x0A, want.tid, 2)
      B.le(w.sb2, 0x0C, want.sid, 2)
      B.le(w.sb2, 0x0E, want.hours, 2)
      w.sb2[0x10] = want.minutes
      w.sb2[8] = want.gender
      G3.setMoney(w, want.money)
      return w
    end)())
    local save = K.import(3, v, cart)
    local out = save and K.export(3, v, save, cart)
    local d = out and D3.decode(out, fam)
    if not (d and d.tid == want.tid and d.sid == want.sid and d.playHours == want.hours
        and d.playMinutes == want.minutes and d.gender == want.gender and d.money == want.money
        and #Compat.check(out, v).errors == 0) then
      bad = bad + 1
      if bad <= 3 then check(false, ("%s trainer mutation %d does not round trip"):format(v, n)) end
    end
  end
  eq(bad, 0, ("%s: %d mutated trainer fields round trip through import/export"):format(v, N))

  bad = 0
  local source = G3.cases()
  local template
  for _, c in ipairs(source) do if c.id == "g3." .. v .. ".full_party_statuses" then template = c.bytes end end
  for n = 1, N do
    local save = K.import(3, v, template)
    local keep = rnd(1, #save.party)
    while #save.party > keep do save.party[#save.party] = nil end
    save.money, save.coins = rnd(0, 999999), rnd(0, 9999)
    for _, m in ipairs(save.party) do
      m.personality = rnd(1, 2147483647)
      m.exp = rnd(0, 1000000)
      m.nickname = ("N%d"):format(rnd(0, 99))
    end
    local out = K.export(3, v, save, false)
    local d = out and D3.decode(out, fam)
    local ok = d and d.money == save.money and d.coins == save.coins and #d.party == keep
      and #Compat.check(out, v).errors == 0
    for i, m in ipairs(save.party) do
      local g = d and d.party[i]
      if not (g and g.pid == m.personality and g.exp == m.exp and g.checksumOk) then ok = false end
    end
    local back = ok and K.import(3, v, out)
    if ok then ok = back and #back.party == keep and back.money == save.money end
    if not ok then
      bad = bad + 1
      if bad <= 3 then check(false, ("%s random model %d does not export and re-import"):format(v, n)) end
    end
  end
  eq(bad, 0, ("%s: %d random models export to what the independent decoder reads and re-import"):format(v, N))

  local Diff = require("tests.save_compat._diff")
  local regions = Diff.regionsFor(3, v)
  local layout = require("src.save_convert.gen3_layouts." .. fam)
  local carried, tried = 0, 0
  while tried < N do
    local blk = layout.BLOCKS[rnd(1, #layout.BLOCKS)]
    local off = rnd(0, blk.size - 1)
    local r = Diff.regionAt(regions, off, blk.key)
    if r and r.tier == "T2" and r.name ~= blk.key and not r.derived then
      tried = tried + 1
      local val = rnd(0, 255)
      local cart = G3.emit((function()
        local w = G3.base(v)
        w[blk.key][off] = val
        return w
      end)())
      local out = K.export(3, v, K.import(3, v, cart), cart)
      local got = out and Compat.gen3Blocks(out, fam)
      if got and got[blk.key]:byte(off + 1) == val then
        carried = carried + 1
      elseif tried - carried <= 3 then
        check(false, ("%s: unmodeled byte %s+0x%X (%s) = %02X is not carried"):format(v, blk.key, off, r.name, val))
      end
    end
  end
  eq(carried, tried, ("%s: %d mutated unmodeled bytes across every T2 region are carried through"):format(v, tried))
end

SaveConvert.setGen2DataStub(K.gen2Data)
local corpus = {}
for _, gen in ipairs({ 1, 2, 3 }) do
  if gen == 1 and not K.gen1Available() then
    print("[skip] gen1 corruption corpus needs data/generated/")
  else
    for _, c in ipairs(require("tests.fixtures.save.gen" .. gen .. "_build").cases()) do
      if not c.refuse then corpus[#corpus + 1] = c end
    end
  end
end

local function answered(ok, a, b)
  if not ok then return false end
  if a == nil then return type(b) == "string" end
  return true
end

local raised = 0
for n = 1, N * 4 do
  local c = corpus[rnd(1, #corpus)]
  local s = c.bytes
  for _ = 1, rnd(1, 24) do
    local at = rnd(1, #s)
    s = s:sub(1, at - 1) .. string.char(rnd(0, 255)) .. s:sub(at + 1)
  end
  local sizes = { #s, #s, rnd(0, #s), #s + rnd(1, 0x40), 0x7FFF, 0x8001, 0x1FFFF, 0x20001 }
  local size = sizes[rnd(1, #sizes)]
  s = size <= #s and s:sub(1, size) or s .. string.rep(rnd(0, 1) == 0 and "\0" or "\255", size - #s)
  if c.gen == 1 then K.gen1Data(c.version) end
  local ok, save, err = pcall(SaveConvert.importSav, s, c.version, c.version)
  if not answered(ok, save, err) then
    raised = raised + 1
    if raised <= 3 then check(false, ("%s corruption %d: import raised or answered nothing -- %s"):format(c.id, n, tostring(save))) end
  elseif save then
    local ok2, out, err2 = pcall(SaveConvert.exportSav, save, c.version, s)
    if not answered(ok2, out, err2) then
      raised = raised + 1
      if raised <= 3 then check(false, ("%s corruption %d: export raised or answered nothing -- %s"):format(c.id, n, tostring(out))) end
    end
  end
end
eq(raised, 0, ("%d corrupted, truncated and padded carts never raise out of importSav/exportSav"):format(N * 4))
SaveConvert.setGen2DataStub(nil)

T.finish()
