local B = require("tests.fixtures.save.bytes")

local G1 = {}

G1.SIZE = 0x8000
G1.NAME = 11
G1.BOX_REGION = 0x462

G1.OFF = {
  spriteBuffers = 0x0000,
  hallOfFame = 0x0598,
  playerName = 0x2598,
  dexOwned = 0x25A3,
  dexSeen = 0x25B6,
  numBag = 0x25C9,
  bag = 0x25CA,
  money = 0x25F3,
  rivalName = 0x25F6,
  options = 0x2601,
  badges = 0x2602,
  playerId = 0x2605,
  curMap = 0x260A,
  yCoord = 0x260D,
  xCoord = 0x260E,
  lastMap = 0x2611,
  pikachuHappiness = 0x271C,
  pikachuMood = 0x271D,
  numPc = 0x27E6,
  pc = 0x27E7,
  curBoxNum = 0x284C,
  numHofTeams = 0x284E,
  coins = 0x2850,
  dayCare = 0x2CF4,
  safariBalls = 0x2CF3,
  safariSteps = 0x29B9,
  safariGate = 0x28CB,
  fossil = 0x29BB,
  trash = 0x29EF,
  hiddenCoins = 0x29AA,
  statusFlags4 = 0x29DA,
  statusFlags6 = 0x29DE,
  beatGym = 0x29D6,
  palOffset = 0x2609,
  surfHi = 0x2741,
  toggleFlags = 0x2852,
  walkBikeSurf = 0x29AC,
  rivalStarter = 0x29C1,
  lastBlackoutMap = 0x29C5,
  tradeFlags = 0x29E3,
  eventFlags = 0x29F3,
  playerStarter = 0x29C3,
  playTime = 0x2CED,
  party = 0x2F2C,
  curBoxData = 0x30C0,
  tileAnimations = 0x3522,
  checksum = 0x3523,
  bank2 = 0x4000,
  bank3 = 0x6000,
}

local O = G1.OFF

G1.SPECIES = {
  RHYDON = 0x01, NIDOKING = 0x07, MEW = 0x15, GENGAR = 0x0E, SNORLAX = 0x84,
  MEWTWO = 0x83, PIKACHU = 0x54, BULBASAUR = 0x99, CHARMANDER = 0xB0,
  SQUIRTLE = 0xB1, PIDGEY = 0x24, RATTATA = 0xA5, ARBOK = 0x2D, DRAGONITE = 0x42,
  EEVEE = 0x66, MAGIKARP = 0x85, GYARADOS = 0x16, LAPRAS = 0x13,
}

G1.GLITCH_SPECIES = {
  0x1F, 0x20, 0x32, 0x34, 0x38, 0x3D, 0x3E, 0x3F, 0x43, 0x44, 0x45, 0x4F, 0x50,
  0x51, 0x56, 0x57, 0x5E, 0x5F, 0x73, 0x79, 0x7A, 0x7F, 0x86, 0x87, 0x89, 0x8C,
  0x92, 0x9C, 0x9F, 0xA0, 0xA1, 0xA2, 0xAC, 0xAE, 0xAF, 0xB5, 0xB6, 0xB7, 0xB8,
}

local GLITCH = {}
for _, i in ipairs(G1.GLITCH_SPECIES) do GLITCH[i] = true end
G1.VALID_SPECIES = {}
for i = 1, 190 do
  if not GLITCH[i] then G1.VALID_SPECIES[#G1.VALID_SPECIES + 1] = i end
end

function G1.boxBase(box)
  if box <= 6 then return O.bank2 + (box - 1) * G1.BOX_REGION end
  return O.bank3 + (box - 7) * G1.BOX_REGION
end

function G1.mon(o)
  local m = {
    species = G1.SPECIES.BULBASAUR, hp = 20, boxLevel = 5, level = 5, status = 0,
    types = { 0x16, 0x03 }, catchRate = 45, moves = { 0x21, 0x2D }, pp = { 35, 40 },
    ppUps = { 0, 0 }, otId = 0x3039, exp = 135, statExp = { 0, 0, 0, 0, 0 },
    dvs = { 9, 15, 6, 10 }, stats = { 20, 11, 10, 12, 11 }, ot = "RED", nick = "BULBY",
  }
  for k, v in pairs(o or {}) do m[k] = v end
  return m
end

local function putStruct(b, at, m, party)
  B.put(b, at, m.species)
  B.be(b, at + 1, m.hp, 2)
  B.put(b, at + 3, m.boxLevel, m.status, m.types[1], m.types[2], m.catchRate)
  for i = 0, 3 do
    B.put(b, at + 8 + i, m.moves[i + 1] or 0)
    local pp = (m.pp[i + 1] or 0) + (m.ppUps[i + 1] or 0) * 64
    B.put(b, at + 29 + i, m.moves[i + 1] and m.moves[i + 1] ~= 0 and pp or 0)
  end
  B.be(b, at + 12, m.otId, 2)
  B.be(b, at + 14, m.exp, 3)
  for i = 0, 4 do B.be(b, at + 17 + i * 2, m.statExp[i + 1], 2) end
  B.put(b, at + 27, m.dvs[1] * 16 + m.dvs[2], m.dvs[3] * 16 + m.dvs[4])
  if party then
    B.put(b, at + 33, m.level)
    for i = 0, 4 do B.be(b, at + 34 + i * 2, m.stats[i + 1], 2) end
  end
end

function G1.putDayCare(b, mon)
  B.put(b, O.dayCare, 1)
  B.putGbName(b, O.dayCare + 1, mon.nick, G1.NAME)
  B.putGbName(b, O.dayCare + 12, mon.ot, G1.NAME)
  putStruct(b, O.dayCare + 23, mon, false)
end

local function putList(b, base, mons, cap, party)
  local structSize = party and 44 or 33
  local n = #mons
  B.put(b, base, n)
  for i = 1, n do B.put(b, base + i, mons[i].species) end
  B.put(b, base + 1 + n, 0xFF)
  local monsAt = base + 2 + cap
  local otAt = monsAt + cap * structSize
  local nickAt = otAt + cap * G1.NAME
  for i = 1, n do
    putStruct(b, monsAt + (i - 1) * structSize, mons[i], party)
    B.putGbName(b, otAt + (i - 1) * G1.NAME, mons[i].ot, G1.NAME)
    B.putGbName(b, nickAt + (i - 1) * G1.NAME, mons[i].nick, G1.NAME)
  end
end

local function putItems(b, countAt, listAt, items)
  B.put(b, countAt, #items)
  for i, it in ipairs(items) do B.put(b, listAt + (i - 1) * 2, it[1], it[2]) end
  B.put(b, listAt + #items * 2, 0xFF)
end

local function bcd(b, at, n, v)
  for i = n - 1, 0, -1 do
    local d = v % 100
    v = math.floor(v / 100)
    b[at + i] = math.floor(d / 10) * 16 + d % 10
  end
end

local function sealBanks(b)
  for bank = 0, 1 do
    local base = bank == 0 and O.bank2 or O.bank3
    for i = 0, 5 do
      local at = base + i * G1.BOX_REGION
      b[base + 6 * G1.BOX_REGION + 1 + i] = B.complement8(b, at, at + G1.BOX_REGION)
    end
    b[base + 6 * G1.BOX_REGION] = B.complement8(b, base, base + 6 * G1.BOX_REGION)
  end
end

function G1.build(spec)
  spec = spec or {}
  local b = B.new(G1.SIZE, 0)
  B.putGbName(b, O.playerName, spec.player or "RED", G1.NAME)
  B.putGbName(b, O.rivalName, spec.rival or "BLUE", G1.NAME)
  B.be(b, O.playerId, spec.playerId or 0x3039, 2)
  bcd(b, O.money, 3, spec.money or 3000)
  bcd(b, O.coins, 2, spec.coins or 0)
  B.put(b, O.badges, spec.badges or 0)
  B.put(b, O.options, spec.options or 0x03)
  B.put(b, O.curMap, spec.map or 0)
  B.put(b, O.yCoord, spec.y or 6)
  B.put(b, O.xCoord, spec.x or 5)
  B.put(b, O.lastMap, spec.lastMap or spec.map or 0)

  local dex = spec.dex
  if dex == "all" then
    for i = 0, 150 do B.setBit(b, O.dexOwned, i, true); B.setBit(b, O.dexSeen, i, true) end
  elseif type(dex) == "table" then
    for _, n in ipairs(dex) do B.setBit(b, O.dexOwned, n - 1, true); B.setBit(b, O.dexSeen, n - 1, true) end
  end

  putItems(b, O.numBag, O.bag, spec.bag or { { 0x14, 3 } })
  putItems(b, O.numPc, O.pc, spec.pc or { { 0x14, 1 } })

  if spec.version == "yellow" then
    B.put(b, O.playerStarter, G1.SPECIES.PIKACHU)
    B.put(b, O.rivalStarter, spec.yellowRival or 0)
    B.put(b, O.pikachuHappiness, spec.pikachuHappiness or 90)
    B.put(b, O.pikachuMood, spec.pikachuMood or 0x80)
  else
    B.put(b, O.playerStarter, spec.starter or G1.SPECIES.CHARMANDER)
    B.put(b, O.rivalStarter, spec.rivalStarterByte or G1.SPECIES.SQUIRTLE)
  end

  local pt = spec.playTime or { 1, 0, 2, 3, 4 }
  B.put(b, O.playTime, pt[1], pt[2], pt[3], pt[4], pt[5])

  if spec.hofTeams then
    for t = 0, spec.hofTeams - 1 do
      for s = 0, 5 do
        local at = O.hallOfFame + t * 96 + s * 16
        B.put(b, at, G1.VALID_SPECIES[(t * 6 + s) % #G1.VALID_SPECIES + 1], 50 + s)
        B.putGbName(b, at + 2, "HOF" .. (t % 10), G1.NAME)
      end
    end
    B.put(b, O.numHofTeams, spec.hofTeams)
  end

  putList(b, O.party, spec.party or { G1.mon() }, 6, true)
  if spec.partyRaw then spec.partyRaw(b) end

  local cur = spec.currentBox or 0
  local initialized = spec.boxesInitialized ~= false
  B.put(b, O.curBoxNum, (initialized and 0x80 or 0) + cur)
  local boxes = spec.boxes or {}
  local curMons = boxes[cur + 1] or {}

  if initialized then
    for box = 1, 12 do
      local base = G1.boxBase(box)
      B.fill(b, base, G1.BOX_REGION, 0)
      putList(b, base, boxes[box] or {}, 20, false)
    end
    if spec.genuineCurrentSlot ~= false and cur <= 11 then
      local base = G1.boxBase(cur + 1)
      B.put(b, base, 0, 0xFF)
    end
  else
    B.fill(b, O.bank2, 0x2000, spec.bankFill or 0xFF)
    B.fill(b, O.bank3, 0x2000, spec.bankFill or 0xFF)
  end
  putList(b, O.curBoxData, curMons, 20, false)
  if spec.boxRaw then spec.boxRaw(b) end

  if spec.patch then spec.patch(b) end
  if initialized then sealBanks(b) end
  if spec.staleBankChecksums then
    b[O.bank2 + 6 * G1.BOX_REGION + 1] = (b[O.bank2 + 6 * G1.BOX_REGION + 1] + 1) % 256
    b[O.bank3 + 6 * G1.BOX_REGION] = (b[O.bank3 + 6 * G1.BOX_REGION] + 7) % 256
  end

  b[O.checksum] = B.complement8(b, O.playerName, O.checksum)
  if spec.after then spec.after(b) end
  return B.pack(b)
end

local function boxOf(n, startSpecies, otName)
  local mons = {}
  for i = 1, n do
    local sp = G1.VALID_SPECIES[(startSpecies + i) % #G1.VALID_SPECIES + 1]
    mons[i] = G1.mon({ species = sp, hp = 30 + i, boxLevel = 10 + i, exp = 1000 + i * 37,
      otId = 0x1000 + i, nick = "M" .. i, ot = otName or "RED", moves = { 0x21, 0x2D, 0x0A, 0 },
      pp = { 35, 30, 20, 0 }, ppUps = { 1, 2, 3, 0 }, dvs = { (i * 3) % 16, (i * 5) % 16, (i * 7) % 16, (i * 11) % 16 },
      statExp = { i * 100, i * 200, i * 300, i * 400, i * 500 } })
  end
  return mons
end
G1.boxOf = boxOf

local function statusParty()
  local statuses = { 0, 0x08, 0x10, 0x20, 0x40, 0x07 }
  local party = {}
  for i = 1, 6 do
    party[i] = G1.mon({ species = G1.VALID_SPECIES[i * 13], status = statuses[i], level = 40 + i,
      boxLevel = 40 + i, hp = 100 + i, nick = "P" .. i, dvs = { 10, 10, 10, 10 },
      stats = { 100 + i, 90, 80, 70, 60 }, exp = 70000 + i, moves = { 0x21, 0x2D, 0x0A, 0x55 },
      pp = { 35, 40, 30, 15 }, ppUps = { 3, 3, 3, 3 }, statExp = { 65535, 65535, 65535, 65535, 65535 } })
  end
  return party
end

function G1.cases()
  local C = {}
  local function add(id, version, spec, extra)
    spec.version = version
    local c = { id = id, gen = 1, version = version, spec = spec }
    for k, v in pairs(extra or {}) do c[k] = v end
    c.bytes = G1.build(spec)
    C[#C + 1] = c
  end

  C[#C + 1] = { id = "g1.red.fresh_cart", gen = 1, version = "red", refuse = true,
    bytes = string.rep("\255", G1.SIZE) }
  add("g1.red.saved_once", "red", { boxesInitialized = false })
  add("g1.red.basic", "red", { boxes = { boxOf(1, 3) } })
  add("g1.blue.basic", "blue", { boxes = { boxOf(2, 9) } })
  add("g1.yellow.basic", "yellow", { boxes = { boxOf(1, 4) }, yellowRival = 2, pikachuHappiness = 140 })
  add("g1.red.full_party_statuses", "red", { party = statusParty() })
  add("g1.red.sleep_counter", "red", { party = { G1.mon({ status = 3, nick = "NAPPY" }) } })
  local full = {}
  for i = 1, 12 do full[i] = boxOf(20, i * 20, "RED") end
  add("g1.red.full_boxes", "red", { boxes = full, currentBox = 4 })
  add("g1.red.box_index_0", "red", { boxes = { boxOf(3, 1), boxOf(2, 5) }, currentBox = 0 })
  local last = {}
  last[12] = boxOf(4, 7); last[1] = boxOf(1, 2)
  add("g1.red.box_index_11", "red", { boxes = last, currentBox = 11 })
  add("g1.red.box_index_invalid", "red", { boxes = { boxOf(1, 2) }, currentBox = 12,
    genuineCurrentSlot = false })
  add("g1.red.glitch_species_party", "red", { party = { G1.mon(), G1.mon({ species = 0x1F, nick = "GLITCH" }) } })
  add("g1.red.glitch_species_box", "red", { boxes = { boxOf(1, 2) }, currentBox = 1,
    patch = function(b) local base = G1.boxBase(1); b[base + 1] = 0xB5; b[base + 22] = 0xB5 end })
  add("g1.red.unknown_item", "red", { bag = { { 0x14, 3 }, { 0x62, 1 }, { 0x04, 5 } } })
  local maxBag, maxPc = {}, {}
  for i = 1, 20 do maxBag[i] = { 0x28 + i, 99 } end
  for i = 1, 50 do maxPc[i] = { i <= 47 and (i + 0x1C) or (0xC8 + i - 47), 99 } end
  add("g1.red.max_stacks", "red", { bag = maxBag, pc = maxPc })
  add("g1.red.duplicate_stacks", "red", { bag = { { 0x14, 99 }, { 0x14, 50 }, { 0x04, 0 } } })
  add("g1.red.all_dex", "red", { dex = "all" })
  add("g1.red.hall_of_fame", "red", { hofTeams = 50 })
  add("g1.red.move_gap", "red", { party = { G1.mon({ moves = { 0x21, 0, 0x2D, 0 }, pp = { 35, 0, 40, 0 } }) } })
  add("g1.red.playtime_maxed", "red", { playTime = { 255, 1, 59, 59, 59 } })
  add("g1.red.playtime_255_unmaxed", "red", { playTime = { 255, 0, 10, 20, 30 } })
  add("g1.red.party_box_level_stale", "red", { party = { G1.mon({ boxLevel = 5, level = 31 }) } })
  add("g1.red.stale_bank_checksums", "red", { boxes = { boxOf(2, 1), boxOf(3, 8) }, staleBankChecksums = true })
  add("g1.red.unnicknamed", "red", { party = { G1.mon({ nick = "BULBASAUR" }) } })
  add("g1.red.map_viridian", "red", { map = 1, x = 18, y = 20, lastMap = 1 })
  add("g1.red.blackout_viridian", "red", { patch = function(b) b[G1.OFF.lastBlackoutMap] = 1 end })
  add("g1.red.surfing", "red", { patch = function(b) b[G1.OFF.walkBikeSurf] = 2 end })
  add("g1.red.biking", "red", { patch = function(b) b[G1.OFF.walkBikeSurf] = 1 end })
  add("g1.red.options_all_bits", "red", { options = 0xF1 })
  add("g1.red.hof_overflow", "red", { hofTeams = 50, patch = function(b) b[G1.OFF.numHofTeams] = 120 end })
  add("g1.red.hof_short_teams", "red", { hofTeams = 3, patch = function(b)
    b[G1.OFF.hallOfFame + 96 + 2 * 16] = 0xFF
    b[G1.OFF.hallOfFame + 2 * 96] = 0x1F
  end })
  add("g1.red.unnamed_events", "red", { patch = function(b)
    for _, bitIdx in ipairs({ 0, 1, 2, 3, 7, 1000, 2559 }) do B.setBit(b, G1.OFF.eventFlags, bitIdx, true) end
  end })
  add("g1.red.all_trades", "red", { patch = function(b) b[G1.OFF.tradeFlags] = 0xFF; b[G1.OFF.tradeFlags + 1] = 0x03 end })
  add("g1.yellow.all_trades", "yellow", { patch = function(b) b[G1.OFF.tradeFlags] = 0xFF; b[G1.OFF.tradeFlags + 1] = 0x03 end })
  add("g1.yellow.toggles", "yellow", { patch = function(b)
    for _, bitIdx in ipairs({ 1, 3, 63, 64, 74, 96, 97, 152, 153, 235 }) do B.setBit(b, G1.OFF.toggleFlags, bitIdx, true) end
  end })
  add("g1.red.status_combo", "red", { party = { G1.mon({ status = 0x48 }), G1.mon({ status = 0x0B, nick = "DOZY" }) } })
  add("g1.red.unknown_move", "red", { party = { G1.mon({ moves = { 0x21, 0xF0 }, pp = { 35, 10 } }) } })
  add("g1.red.unknown_pc_item", "red", { pc = { { 0x14, 1 }, { 0xFB, 2 }, { 0x14, 3 } } })
  add("g1.red.long_names", "red", { player = "ABCDEFG", rival = "HIJKLMN" })
  add("g1.red.saved_once_box", "red", { boxesInitialized = false, boxes = { boxOf(5, 3) } })
  add("g1.yellow.hall_of_fame", "yellow", { hofTeams = 7 })
  add("g1.yellow.glitch_species_party", "yellow", { party = { G1.mon(), G1.mon({ species = 0x1F, nick = "GLITCH" }) } })
  add("g1.yellow.duplicate_stacks", "yellow", { bag = { { 0x14, 99 }, { 0x14, 50 }, { 0x04, 0 } } })
  add("g1.yellow.saved_once_box", "yellow", { boxesInitialized = false, boxes = { boxOf(4, 6) } })
  add("g1.yellow.full_boxes", "yellow", { boxes = full, currentBox = 8 })
  add("g1.yellow.surfing_blackout", "yellow", { patch = function(b)
    b[G1.OFF.walkBikeSurf] = 2
    b[G1.OFF.lastBlackoutMap] = 4
  end })
  add("g1.yellow.unnamed_events", "yellow", { patch = function(b)
    for _, bitIdx in ipairs({ 1, 2, 900, 2559 }) do B.setBit(b, G1.OFF.eventFlags, bitIdx, true) end
  end })
  add("g1.yellow.playtime_maxed", "yellow", { playTime = { 255, 0xFF, 0, 0, 0 } })
  local function eventBit(b, idx) B.setBit(b, G1.OFF.eventFlags, idx, true) end
  add("g1.red.daycare", "red", { patch = function(b)
    G1.putDayCare(b, G1.mon({ species = G1.SPECIES.EEVEE, nick = "FLUFFY", ot = "RED", boxLevel = 12, exp = 1900,
      hp = 33, moves = { 0x21, 0x2D }, pp = { 35, 40 } }))
  end })
  add("g1.red.daycare_default_name", "red", { patch = function(b)
    G1.putDayCare(b, G1.mon({ species = G1.SPECIES.EEVEE, nick = "EEVEE", ot = "JOE", boxLevel = 30, exp = 27000 }))
  end })
  add("g1.red.daycare_carrier", "red", { patch = function(b)
    G1.putDayCare(b, G1.mon({ species = 0x1F, nick = "GLITCH", ot = "RED" }))
  end })
  add("g1.red.safari_in_game", "red", { map = 220, x = 10, y = 12, patch = function(b)
    eventBit(b, 591)
    b[G1.OFF.safariBalls] = 17
    B.be(b, G1.OFF.safariSteps, 300, 2)
    b[G1.OFF.safariGate] = 5
  end })
  add("g1.red.safari_game_over", "red", { patch = function(b) eventBit(b, 590) end })
  add("g1.red.safari_stale_balls", "red", { patch = function(b)
    b[G1.OFF.safariBalls] = 9
    B.be(b, G1.OFF.safariSteps, 77, 2)
  end })
  add("g1.red.fossil_in_lab", "red", { patch = function(b)
    eventBit(b, 736)
    b[G1.OFF.fossil] = 0x29
    b[G1.OFF.fossil + 1] = 0x5A
  end })
  add("g1.red.fossil_stale", "red", { patch = function(b)
    b[G1.OFF.fossil] = 0x2A
    b[G1.OFF.fossil + 1] = 0x62
  end })
  add("g1.red.trash_cans", "red", { patch = function(b)
    b[G1.OFF.trash] = 6
    b[G1.OFF.trash + 1] = 8
  end })
  add("g1.red.trash_first_zero", "red", { patch = function(b) b[G1.OFF.trash + 1] = 5 end })
  add("g1.red.hidden_coins", "red", { patch = function(b)
    b[G1.OFF.hiddenCoins] = 0x55
    b[G1.OFF.hiddenCoins + 1] = 0x0A
  end })
  add("g1.red.forced_bike", "red", { map = 28, x = 12, y = 5, patch = function(b)
    b[G1.OFF.statusFlags6] = 0x21
    b[G1.OFF.walkBikeSurf] = 1
  end })
  add("g1.red.used_pokecenter", "red", { patch = function(b) b[G1.OFF.statusFlags4] = 0x0C end })
  add("g1.red.dark_cave", "red", { map = 82, x = 15, y = 3, patch = function(b) b[G1.OFF.palOffset] = 6 end })
  add("g1.red.dark_cave_lit", "red", { map = 82, x = 15, y = 3, patch = function(b) b[G1.OFF.palOffset] = 0 end })
  add("g1.yellow.surf_score", "yellow", { patch = function(b)
    b[G1.OFF.surfHi] = 0x34
    b[G1.OFF.surfHi + 1] = 0x12
  end })
  add("g1.yellow.surf_score_invalid_bcd", "yellow", { patch = function(b)
    b[G1.OFF.surfHi] = 0xFA
    b[G1.OFF.surfHi + 1] = 0x12
  end })
  add("g1.red.beat_gym_mismatch", "red", { badges = 0x01, patch = function(b) b[G1.OFF.beatGym] = 0x03 end })
  add("g1.red.blackout_invalid", "red", { patch = function(b) b[G1.OFF.lastBlackoutMap] = 0x55 end })
  return C
end

return G1
