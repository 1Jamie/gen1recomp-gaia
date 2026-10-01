local B = require("tests.fixtures.save.bytes")
local Gen2Layout = require("src.save_convert.Gen2Layout")

local G2 = {}

G2.SIZE = 0x8000
G2.NAME = 11
G2.EGG = 0xFD

function G2.layout(version)
  return version == "crystal" and Gen2Layout.crystal or Gen2Layout.goldSilver
end

-- ram/sram.asm:66
G2.GS_BACKUP = {
  { from = 0x2009, to = 0x15C7, size = 0x226 },
  { from = 0x222F, to = 0x3D96, size = 0x1AA },
  { from = 0x23D9, to = 0x0C6B, size = 0x47D },
  { from = 0x2856, to = 0x7E39, size = 0x34 },
  { from = 0x288A, to = 0x10E8, size = 0x4DF },
}
-- pokecrystal ram/sram.asm:64
G2.CRYSTAL_BACKUP = {
  { from = 0x2009, to = 0x1209, size = 0xB7A },
}

G2.ITEMS = {
  POTION = { index = 0x12, pocket = "ITEM" }, ANTIDOTE = { index = 0x09, pocket = "ITEM" },
  REPEL = { index = 0x1E, pocket = "ITEM" }, MAX_POTION = { index = 0x0F, pocket = "ITEM" },
  BICYCLE = { index = 0x07, pocket = "KEY_ITEM" }, POKE_BALL = { index = 0x05, pocket = "BALL" },
  GREAT_BALL = { index = 0x04, pocket = "BALL" }, FLOWER_MAIL = { index = 0x9E, pocket = "ITEM" },
  LEFTOVERS = { index = 0x92, pocket = "ITEM" },
  TM_DYNAMICPUNCH = { index = 0xBF, pocket = "TM_HM", tmNumber = 1 },
}
for i = 1, 26 do G2.ITEMS["ITEM_" .. i] = { index = 0x20 + i, pocket = "ITEM" } end
for i = 1, 25 do G2.ITEMS["KEY_" .. i] = { index = 0x40 + i, pocket = "KEY_ITEM" } end
for i = 1, 12 do G2.ITEMS["BALL_" .. i] = { index = 0x60 + i, pocket = "BALL" } end

function G2.mon(o)
  local m = {
    species = 155, item = 0, moves = { 33, 43, 0, 0 }, pp = { 35, 30, 0, 0 }, ppUps = { 1, 0, 0, 0 },
    otId = 0x1234, exp = 1000, statExp = { 1, 2, 3, 4, 5 }, dvs = { 9, 15, 6, 10 },
    happiness = 120, pokerus = 0, caught = 0, level = 12, status = 0, hp = 35, maxHp = 40,
    stats = { 30, 31, 32, 33, 34 }, ot = "ASH", nick = "FLAME", listed = nil,
  }
  for k, v in pairs(o or {}) do m[k] = v end
  return m
end

local function putShared(b, at, m)
  B.put(b, at, m.species, m.item)
  for i = 1, 4 do B.put(b, at + 1 + i, m.moves[i] or 0) end
  B.be(b, at + 6, m.otId, 2)
  B.be(b, at + 8, m.exp, 3)
  for i = 0, 4 do B.be(b, at + 0x0B + i * 2, m.statExp[i + 1], 2) end
  B.put(b, at + 0x15, m.dvs[1] * 16 + m.dvs[2], m.dvs[3] * 16 + m.dvs[4])
  for i = 1, 4 do
    local pp = (m.moves[i] or 0) ~= 0 and ((m.pp[i] or 0) + (m.ppUps[i] or 0) * 64) or 0
    B.put(b, at + 0x16 + i, pp)
  end
  B.put(b, at + 0x1B, m.happiness, m.pokerus)
  B.be(b, at + 0x1D, m.caught, 2)
  B.put(b, at + 0x1F, m.level)
end

local function putList(b, base, mons, cap, party)
  local size = party and 48 or 32
  B.put(b, base, #mons)
  for i, m in ipairs(mons) do B.put(b, base + i, m.listed or m.species) end
  B.put(b, base + 1 + #mons, 0xFF)
  local monsAt = base + 2 + cap
  local otAt = monsAt + cap * size
  local nickAt = otAt + cap * G2.NAME
  for i, m in ipairs(mons) do
    local at = monsAt + (i - 1) * size
    putShared(b, at, m)
    if party then
      B.put(b, at + 0x20, m.status)
      B.be(b, at + 0x22, m.hp, 2)
      B.be(b, at + 0x24, m.maxHp, 2)
      for k = 0, 4 do B.be(b, at + 0x26 + k * 2, m.stats[k + 1], 2) end
    end
    B.putGbName(b, otAt + (i - 1) * G2.NAME, m.ot, G2.NAME)
    B.putGbName(b, nickAt + (i - 1) * G2.NAME, m.nick, G2.NAME)
  end
end

function G2.boxOf(n, start)
  local mons = {}
  for i = 1, n do
    mons[i] = G2.mon({ species = (start + i * 7) % 251 + 1, nick = "B" .. i, level = 5 + i % 90,
      exp = 500 + i * 13, dvs = { i % 16, (i * 3) % 16, (i * 5) % 16, (i * 7) % 16 }, otId = 0x2000 + i,
      happiness = 70, moves = { 33, 0, 0, 0 }, pp = { 35, 0, 0, 0 }, ppUps = { 0, 0, 0, 0 } })
  end
  return mons
end

local function putItems(b, countAt, listAt, list, pairs_)
  B.put(b, countAt, #list)
  for i, it in ipairs(list) do
    if pairs_ then B.put(b, listAt + (i - 1) * 2, it[1], it[2]) else B.put(b, listAt + i - 1, it[1]) end
  end
  B.put(b, listAt + #list * (pairs_ and 2 or 1), 0xFF)
end

function G2.seal(b, version)
  local L = G2.layout(version)
  B.put(b, L.sCheckValue1, 0x63)
  B.put(b, L.sCheckValue2, 0x7F)
  B.le(b, L.sChecksum, B.sum16(b, L.sGameData, L.sGameDataEnd), 2)
  if version == "crystal" then
    for _, seg in ipairs(G2.CRYSTAL_BACKUP) do B.copy(b, seg.from, seg.to, seg.size) end
    B.copy(b, 0x2000, 0x1200, 8)
    B.put(b, 0x1208, 0x63)
    B.put(b, 0x1F0F, 0x7F)
    B.le(b, 0x1F0D, B.sum16(b, 0x1209, 0x1D83), 2)
  else
    for _, seg in ipairs(G2.GS_BACKUP) do B.copy(b, seg.from, seg.to, seg.size) end
    B.copy(b, 0x2000, 0x7E30, 8)
    B.put(b, 0x7E38, 0x63)
    B.put(b, 0x7E6F, 0x7F)
    B.le(b, 0x7E6D, B.sum16(b, L.sGameData, L.sGameDataEnd), 2)
  end
end

function G2.build(spec)
  local version = spec.version
  local L = G2.layout(version)
  local b = B.new(G2.SIZE, 0)
  if spec.scratchJunk then
    for i = 0, 0x5FF do b[i] = (i * 37 + 11) % 256 end
  end
  B.put(b, 0x2000, 0x03, 0x01, 0x00, 0x01, 0x40, 0x01, 0x00, 0x00)
  B.putGbName(b, L.wPlayerName, spec.player or "ASH", G2.NAME)
  B.putGbName(b, L.wRivalName, "GARY", G2.NAME)
  B.putGbName(b, L.wMomsName, "MOM", G2.NAME)
  B.putGbName(b, L.wRedsName, "RED", G2.NAME)
  B.putGbName(b, L.wGreensName, "GREEN", G2.NAME)
  B.be(b, L.wPlayerID, spec.playerId or 0x1234, 2)
  B.be(b, L.wMoney, spec.money or 123456, 3)
  B.be(b, L.wCoins, spec.coins or 0, 2)
  B.put(b, L.wBadges, spec.badges or 0x05)
  B.put(b, L.wSavedAtLeastOnce, 1)
  B.put(b, L.wMapGroup, 24, 7)
  B.put(b, L.wYCoord, 4, 3)
  B.put(b, L.wGameTimeHours, 0, 12, 34, 56, 7)
  if L.wPlayerGender then B.put(b, L.wPlayerGender, spec.female and 1 or 0) end

  local items = spec.items or { { G2.ITEMS.POTION.index, 3 } }
  local keys = spec.keyItems or { { G2.ITEMS.BICYCLE.index } }
  local balls = spec.balls or { { G2.ITEMS.POKE_BALL.index, 9 } }
  putItems(b, L.wNumItems, L.wItems, items, true)
  putItems(b, L.wNumKeyItems, L.wKeyItems, keys, false)
  putItems(b, L.wNumBalls, L.wBalls, balls, true)
  for n, q in pairs(spec.tms or {}) do B.put(b, L.wTMsHMs + n - 1, q) end
  putItems(b, L.wNumPCItems, L.wNumPCItems + 1, spec.pcItems or {}, true)

  for i = 1, 14 do
    local name = B.gbText("BOX" .. i)
    for k, c in ipairs(name) do b[L.wBoxNames + (i - 1) * 9 + k - 1] = c end
    b[L.wBoxNames + (i - 1) * 9 + #name] = 0x50
  end
  local cur = spec.currentBox or 0
  B.put(b, L.wCurBox, cur)

  if spec.dex == "all" then
    for i = 0, 250 do B.setBit(b, L.wPokedexCaught, i, true); B.setBit(b, L.wPokedexSeen, i, true) end
  end
  if spec.unownDex then
    local base = version == "crystal" and 0x2A67 or 0x2A8C
    for i = 0, 25 do b[base + i] = i + 1 end
    b[base + 27] = 1
  end

  putList(b, L.wPartyCount, spec.party or { G2.mon() }, 6, true)
  local boxes = spec.boxes or {}
  for i, base in ipairs(L.boxes) do putList(b, base, boxes[i] or {}, 20, false) end
  putList(b, L.sBox, boxes[cur + 1] or {}, 20, false)

  if spec.hallOfFame then
    local base = version == "crystal" and 0x32C0 or 0x321A
    for i = 0, 0xB7B do b[base + i] = (i * 7) % 256 end
  end
  if spec.mail then
    for slot = 0, 5 do
      local at = 0x0600 + slot * 47
      for k = 0, 46 do b[at + k] = (slot * 47 + k) % 200 + 1 end
      B.copy(b, at, 0x071A + slot * 47, 47)
    end
  end
  if spec.patch then spec.patch(b, L) end
  if spec.lowByteZero then
    local pad = L.wGreensName + G2.NAME - 1
    local sum = B.sum16(b, L.sGameData, L.sGameDataEnd)
    b[pad] = ((b[pad] or 0) + 256 - sum % 256) % 256
  end
  G2.seal(b, version)
  if spec.after then spec.after(b, L) end
  local out = B.pack(b)
  if spec.footer then out = out .. spec.footer end
  return out
end

function G2.cases()
  local C = {}
  local function add(id, version, spec, extra)
    spec.version = version
    local c = { id = id, gen = 2, version = version, spec = spec }
    for k, v in pairs(extra or {}) do c[k] = v end
    c.bytes = G2.build(spec)
    C[#C + 1] = c
  end
  for _, v in ipairs({ "gold", "silver", "crystal" }) do
    local p = "g2." .. v .. "."
    C[#C + 1] = { id = p .. "fresh_cart", gen = 2, version = v, refuse = true, bytes = string.rep("\255", G2.SIZE) }
    add(p .. "basic", v, { boxes = { [1] = G2.boxOf(1, 3), [3] = G2.boxOf(2, 9) } })
    add(p .. "egg_party", v, { party = { G2.mon(), G2.mon({ species = 172, listed = G2.EGG, nick = "EGG",
      happiness = 10, level = 5, hp = 0, exp = 125 }) } })
    local eggBox = G2.boxOf(2, 1)
    eggBox[2].listed = G2.EGG; eggBox[2].nick = "EGG"; eggBox[2].happiness = 20
    add(p .. "egg_box", v, { boxes = { [2] = eggBox } })
    local statuses = { 0, 0x08, 0x10, 0x20, 0x40, 0x05 }
    local party = {}
    for i = 1, 6 do
      party[i] = G2.mon({ species = i * 40, status = statuses[i], pokerus = i == 2 and 0x13 or 0,
        dvs = { 10, 10, 10, 10 }, item = G2.ITEMS.LEFTOVERS.index, caught = v == "crystal" and 0x4A85 or 0,
        nick = "P" .. i, level = 50 + i })
    end
    add(p .. "full_party", v, { party = party })
    local full = {}
    for i = 1, 14 do full[i] = G2.boxOf(20, i * 20) end
    add(p .. "full_boxes", v, { boxes = full, currentBox = 6 })
    add(p .. "box_index_13", v, { boxes = { [14] = G2.boxOf(3, 5) }, currentBox = 13 })
    add(p .. "box_index_14", v, { boxes = {}, currentBox = 14 })
    add(p .. "unknown_species", v, { party = { G2.mon(), G2.mon({ species = 252, nick = "GLITCH" }) } })
    add(p .. "unknown_held_item", v, { party = { G2.mon({ item = 0xFA }) } })
    local maxItems, maxKeys, maxBalls, tms = {}, {}, {}, {}
    for i = 1, 20 do maxItems[i] = { 0x20 + i, 99 } end
    for i = 1, 25 do maxKeys[i] = { 0x40 + i } end
    for i = 1, 12 do maxBalls[i] = { 0x60 + i, 99 } end
    for i = 1, 57 do tms[i] = 99 end
    local pc = {}
    for i = 1, 50 do pc[i] = { 0x20 + (i % 20) + 1, 99 } end
    add(p .. "max_stacks", v, { items = maxItems, keyItems = maxKeys, balls = maxBalls, tms = tms, pcItems = pc })
    add(p .. "bag_order", v, { items = { { G2.ITEMS.REPEL.index, 4 }, { G2.ITEMS.POTION.index, 3 },
      { G2.ITEMS.ANTIDOTE.index, 2 } } })
    add(p .. "duplicate_stacks", v, { items = { { G2.ITEMS.POTION.index, 99 }, { G2.ITEMS.POTION.index, 50 } } })
    add(p .. "all_dex_unown", v, { dex = "all", unownDex = true })
    add(p .. "hall_of_fame", v, { hallOfFame = true })
    add(p .. "mail", v, { mail = true, scratchJunk = true,
      party = { G2.mon({ item = G2.ITEMS.FLOWER_MAIL.index }) } })
    add(p .. "rtc_footer", v, { footer = string.rep("\0", 0x28) .. "\97\226\117\106\0\0\0\0" })
  end
  add("g2.crystal.female", "crystal", { female = true })
  add("g2.crystal.corrupt_primary", "crystal", {
    after = function(b, L) b[L.sChecksum] = (b[L.sChecksum] + 1) % 256 end })
  return C
end

return G2
