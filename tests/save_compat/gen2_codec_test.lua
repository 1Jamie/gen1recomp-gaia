package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2MapContext = require("src.save_convert.Gen2MapContext")
local Compat = require("src.save_convert.Compat")

local fixtures = {}
for _, c in ipairs(G2.cases()) do fixtures[c.id] = c end

local VERSIONS = { "gold", "silver", "crystal" }

local function u8(s, at) return s:byte(at + 1) end
local function be(s, at, n)
  local v = 0
  for i = 0, n - 1 do v = v * 256 + s:byte(at + i + 1) end
  return v
end
local function le16(s, at) return s:byte(at + 1) + s:byte(at + 2) * 256 end
local function sum16(s, from, toExcl)
  local v = 0
  for i = from, toExcl - 1 do v = (v + s:byte(i + 1)) % 65536 end
  return v
end

local function import(id)
  local c = fixtures[id]
  return assert(K.import(2, c.version, c.bytes)), c
end

local function export(version, save, template)
  local out, err = K.export(2, version, save, template)
  check(out ~= nil, ("%s: export -- %s"):format(version, tostring(err)))
  return out
end

local function noErrors(label, bytes, version)
  local report = Compat.check(bytes, version)
  eq(#report.errors, 0, label .. " passes every reader rule -- " .. Compat.describe(report))
end

-- engine/pokemon/breeding.asm:219, :224
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save = import("g2." .. v .. ".egg_party")
  local egg = save.party[2]
  eq(egg.isEgg, true, v .. ": a 0xFD list byte imports as an egg")
  eq(egg.eggSteps, 10, v .. ": the hatch counter comes off byte 0x1B")
  eq(egg.happiness, Gen2Save.HATCH_HAPPINESS, v .. ": and happiness is what hatching writes")
  eq(egg.species, 172, v .. ": the struct keeps the real species")

  local box = import("g2." .. v .. ".egg_box")
  eq(box.boxes[2][2].isEgg, true, v .. ": a box egg imports instead of refusing the save")
  eq(box.boxes[2][2].eggSteps, 20, v .. ": with its hatch counter")
  eq(box.boxes[2][1].isEgg, nil, v .. ": and its neighbour is not an egg")

  egg.eggSteps = 3
  save.party[1].isEgg, save.party[1].eggSteps, save.party[1].nickname = true, 7, nil
  local out = export(v, save, false)
  eq(u8(out, L.wPartySpecies), Gen2Save.EGG, v .. ": an engine egg exports list byte 0xFD")
  eq(u8(out, L.wPartyMons), 155, v .. ": with the species in the struct")
  eq(u8(out, L.wPartyMons + 0x1B), 7, v .. ": and eggSteps in byte 0x1B")
  eq(u8(out, L.wPartyMons + 48 + 0x1B), 3, v .. ": for every egg in the party")
  local nick = {}
  for i = 0, 3 do nick[#nick + 1] = u8(out, L.wPartyMonNicknames + i) end
  eq(table.concat(nick, ","), "132,134,134,80", v .. ": an egg with no nickname is EGG")
end

do
  local named = {
    pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL" },
                CHIKORITA = { index = 152, dex = 152, name = "CHIKORITA" } },
    items = K.gen2Data.items, maps = K.gen2Data.maps,
  }
  local c = fixtures["g2.gold.basic"]
  local save = assert(Gen2Save.decode(c.bytes, "gold", named))
  save.party[1].nickname = nil
  local out = assert(Gen2Save.encode(save, "gold", nil, named))
  eq(assert(Gen2Save.decode(out, "gold", named)).party[1].nickname, "CYNDAQUIL",
    "an un-nicknamed mon exports its species name")

  save.party[1].species = "MISSINGMON"
  local none, why = Gen2Save.encode(save, "gold", nil, named)
  eq(none, nil, "a species this game cannot index is refused, not written as 0")
  check(type(why) == "string" and why:find("MISSINGMON", 1, true) ~= nil, "and named -- " .. tostring(why))
  save.party[1].species = "CYNDAQUIL"
  save.party[1].item = "MOD_ITEM"
  none, why = Gen2Save.encode(save, "gold", nil, named)
  eq(none, nil, "so is a held item")
  check(type(why) == "string" and why:find("MOD_ITEM", 1, true) ~= nil, "named too -- " .. tostring(why))
  save.party[1].item = nil
  save.inventory.MOD_BALL = 1
  none, why = Gen2Save.encode(save, "gold", nil, named)
  eq(none, nil, "and a bag item")
  save.inventory.MOD_BALL = nil
  save.party[1].moves[1].id = "MOD_MOVE"
  none, why = Gen2Save.encode(save, "gold", nil, named)
  eq(none, nil, "and a move")

  local unk = fixtures["g2.gold.unknown_species"]
  local glitch = assert(Gen2Save.decode(unk.bytes, "gold", named))
  eq(glitch.party[2].species, 252, "an unnamed species index stays its number")
  check(type(glitch.party[2].cartRaw) == "string" and #glitch.party[2].cartRaw == 96,
    "and carries its struct bytes")
  local L = Gen2Save.layoutFor("gold")
  local same = assert(Gen2Save.encode(glitch, "gold", unk.bytes, named))
  eq(same:sub(L.wPartyMons + 48 + 1, L.wPartyMons + 96), unk.bytes:sub(L.wPartyMons + 48 + 1, L.wPartyMons + 96),
    "the carried struct is written back byte for byte while it is unchanged")
  glitch.party[2].otId = 1
  glitch.party[2].level = 99
  local back = assert(Gen2Save.encode(glitch, "gold", unk.bytes, named))
  eq(u8(back, L.wPartyMons + 48 + 0x1F), 99, "an edit of a carried mon is written, not overwritten by the carrier")
  eq(be(back, L.wPartyMons + 48 + 6, 2), 1, "including its trainer id")
  eq(u8(back, L.wPartySpecies + 1), 252, "never as species 0")
end

for _, v in ipairs(VERSIONS) do
  local save = import("g2." .. v .. ".basic")
  save.party[1].item = 0xFA
  local out = export(v, save, false)
  eq(u8(out, Gen2Save.layoutFor(v).wPartyMons + 1), 0xFA, v .. ": a raw held item number is written as-is")
  local ok, a, b = pcall(Gen2Save.encode, { party = { { species = {}, moves = 3 } }, position = 7 }, v)
  check(ok and a == nil and type(b) == "string", v .. ": a malformed save is refused, never raised -- " .. tostring(b))
end

-- macros/ram.asm:193 mailmsg; ram/sram.asm:8, :14
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local crystal = v == "crystal"
  local save, c = import("g2." .. v .. ".mail")
  local letter = { type = "FLOWER_MAIL", message = "HELLO THERE FRIEND", author = "ASH", authorId = 0x4321, species = 155 }
  save.mail.party[1] = letter
  save.mail.box = { { type = "FLOWER_MAIL", message = "HI", author = "GARY", authorId = 7, species = 7 } }
  local out = export(v, save, c.bytes)
  eq(out:sub(1, 0x600), c.bytes:sub(1, 0x600), v .. ": sScratch is never written")
  for _, base in ipairs({ L.sPartyMail, L.sPartyMailBackup }) do
    local tag = ("%s 0x%04X"):format(v, base)
    eq(u8(out, base), 0x87, tag .. ": message starts at +0")
    eq(u8(out, base + 16), 0x4E, tag .. ": '<NEXT>' at MAIL_LINE_LENGTH")
    eq(u8(out, base + 17), 0x8D, tag .. ": the second line after it")
    eq(u8(out, base + 0x21), 0x80, tag .. ": author at +0x21")
    eq(u8(out, base + 0x24), 0x50, tag .. ": terminated")
    eq(be(out, base + 0x2B, 2), 0x4321, tag .. ": author id at +0x2B")
    eq(u8(out, base + 0x2D), 155, tag .. ": species at +0x2D")
    eq(u8(out, base + 0x2E), 0x9E, tag .. ": mail item at +0x2E")
  end
  for _, base in ipairs({ L.sMailboxCount, L.sMailboxCountBackup }) do
    eq(u8(out, base), 1, ("%s 0x%04X: mailbox count"):format(v, base))
    eq(u8(out, base + 1 + 0x2E), 0x9E, ("%s 0x%04X: first letter's item"):format(v, base))
  end
  local back = assert(K.import(2, v, out))
  eq(back.mail.party[1].message, "HELLO THERE FRIEND", v .. ": the letter reads back without a split")
  eq(back.mail.party[1].author, "ASH", v .. ": author")
  eq(back.mail.box[1].message, "HI", v .. ": the mailbox reads back")
  if crystal then eq(L.sPartyMail, 0x600, "crystal sPartyMail") end
  local untouched = export(v, assert(K.import(2, v, c.bytes)), c.bytes)
  eq(untouched:sub(0x601, 0x834 + 1 + 470), c.bytes:sub(0x601, 0x834 + 1 + 470),
    v .. ": unchanged mail keeps every byte")
end

-- pokegold ram/sram.asm:66 Backup Save 1-3; engine/menus/save.asm:495
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save, c = import("g2." .. v .. ".full_party")
  save.player.money = 4242
  for label, out in pairs({ templated = export(v, save, c.bytes), fresh = export(v, save, false) }) do
    local tag = v .. " " .. label
    noErrors(tag, out, v)
    eq(Gen2Save.checksumValid(out, L), true, tag .. ": primary sealed")
    eq(Gen2Save.backupValid(out, L), true, tag .. ": backup sealed")
    local primary = sum16(out, L.sGameData, L.sGameDataEnd)
    eq(le16(out, L.backupSave.checksum), primary, tag .. ": PKHeX checksum 2 equals the primary sum")
    for _, seg in ipairs(L.backupSave.segments) do
      eq(out:sub(seg[2] + 1, seg[2] + seg[3]), out:sub(seg[1] + 1, seg[1] + seg[3]),
        ("%s: backup segment 0x%04X mirrors 0x%04X"):format(tag, seg[2], seg[1]))
    end
    eq(out:sub(L.backupSave.options + 1, L.backupSave.options + 8), out:sub(0x2001, 0x2008), tag .. ": backup options")
    eq(u8(out, L.backupSave.checkValue1), 0x63, tag .. ": backup check value 1")
    eq(u8(out, L.backupSave.checkValue2), 0x7F, tag .. ": backup check value 2")
  end
  local broken = c.bytes:sub(1, 0x2100) .. string.char((u8(c.bytes, 0x2100) + 1) % 256) .. c.bytes:sub(0x2102)
  local fromBackup = assert(Gen2Save.decode(broken, v, K.gen2Data))
  check(fromBackup.warnings and fromBackup.warnings[1]:find("backup", 1, true) ~= nil,
    v .. ": a failed primary imports from the backup and says so")
  local healed = export(v, fromBackup, broken)
  eq(u8(healed, 0x2100), u8(c.bytes, 0x2100), v .. ": the corrupt primary byte is not carried into the export")
end

-- engine/menus/intro_menu.asm:175, engine/link/mystery_gift.asm:1374
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local blank = assert(Gen2Save.blankImage(v, { position = { map = K.GEN2_MAP, x = 1, y = 1 } }, K.gen2Data))
  eq(u8(blank, L.sMysteryGiftItem), 0, v .. ": sMysteryGiftItem")
  eq(u8(blank, L.sMysteryGiftUnlocked), 0xFF, v .. ": sMysteryGiftUnlocked")
  eq(u8(blank, L.sBackupMysteryGiftItem), 0, v .. ": sBackupMysteryGiftItem")
  eq(u8(blank, L.sNumDailyMysteryGiftPartnerIDs), 0xFF, v .. ": the backup of the unlocked byte")
  eq(Gen2Save.checksumValid(blank, L), true, v .. ": the blank image is sealed")
  eq(Gen2Save.backupValid(blank, L), true, v .. ": backup included")
  eq(blank:sub(L.wBoxNames + 1, L.wBoxNames + 9), string.char(0x81, 0x8E, 0x97, 0xF7, 0x50, 0, 0, 0, 0),
    v .. ": SetDefaultBoxNames leaves the zero tail")
end

-- home/copy_name.asm:5
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save, c = import("g2." .. v .. ".basic")
  save.boxNames[1] = "AB"
  local out = export(v, save, c.bytes)
  eq(out:sub(L.wBoxNames + 1, L.wBoxNames + 9),
    string.char(0x80, 0x81, 0x50) .. c.bytes:sub(L.wBoxNames + 4, L.wBoxNames + 9),
    v .. ": a renamed box keeps the old tail after its terminator")
  eq(out:sub(L.wBoxNames + 10, L.wBoxNames + 14 * 9), c.bytes:sub(L.wBoxNames + 10, L.wBoxNames + 14 * 9),
    v .. ": untouched box names keep every byte")
end

-- engine/menus/save.asm:825 GetBoxAddress
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save, c = import("g2." .. v .. ".box_index_14")
  eq(save.currentBox, 1, v .. ": wCurBox 14 is box 1, as the cart resets it")
  local out = export(v, save, c.bytes)
  eq(u8(out, L.wCurBox), 14, v .. ": and the byte is carried while the box is unchanged")
  save.currentBox = 3
  out = export(v, save, c.bytes)
  eq(u8(out, L.wCurBox), 2, v .. ": a real change is written")
  eq(out:sub(L.sBox + 1, L.sBox + Gen2Save.BOX_BYTES), out:sub(L.boxes[3] + 1, L.boxes[3] + Gen2Save.BOX_BYTES),
    v .. ": and sBox is that box")

  local bytes = B.fromString(fixtures["g2." .. v .. ".full_boxes"].bytes)
  bytes[L.sBox] = 3
  G2.seal(bytes, v)
  local warned = assert(Gen2Save.decode(B.pack(bytes), v, K.gen2Data))
  eq(#warned.boxes[7], 20, v .. ": the archive is the box the cart loads")
  check(warned.warnings and warned.warnings[1]:find("active box", 1, true) ~= nil,
    v .. ": a stale sBox is reported")
end

-- data/maps/setup_scripts.asm MapSetupScript_Continue, home/map.asm:1829
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local O = Gen2MapContext.offsetsFor(v)
  local save, c = import("g2." .. v .. ".basic")
  save.position.x = 1
  local out = export(v, save, c.bytes)
  eq(u8(out, L.wXCoord), 1, v .. ": the coordinate is written")
  eq(u8(out, O.objectStructs + Gen2MapContext.STRUCT_MAP_X), 5, v .. ": the player struct follows it")
  eq(u8(out, O.mapObjects + 3), 5, v .. ": so does the player's map object")
  eq(out:sub(O.mapObjects + 17, O.mapObjects + 256), c.bytes:sub(O.mapObjects + 17, O.mapObjects + 256),
    v .. ": every other map object is the template's")
  local again = export(v, assert(K.import(2, v, out)), out)
  eq(again, out, v .. ": and the export is a fixed point")
end

for _, v in ipairs(VERSIONS) do
  local c = fixtures["g2." .. v .. ".rtc_footer"]
  local decoded = assert(Gen2Save.decode(c.bytes, v, K.gen2Data))
  local merged = Gen2Save.mergeDefaults(decoded, v)
  eq(merged.rawImport, c.bytes, v .. ": the whole image, footer included, rides the slot")
  local out = assert(Gen2Save.encode(merged, v, nil, K.gen2Data))
  eq(#out, #c.bytes, v .. ": an export from the slot alone keeps the footer")
  eq(out:sub(0x8001), c.bytes:sub(0x8001), v .. ": byte for byte")
  eq(out, c.bytes, v .. ": and the whole image is unchanged")
end

-- engine/items/items.asm:208
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save = import("g2." .. v .. ".basic")
  save.inventory.POTION = 149
  save.pcItems = { REPEL = 120 }
  save.pcOrder = { "REPEL" }
  local out = export(v, save, false)
  eq(u8(out, L.wNumItems), 2, v .. ": 149 potions are two stacks")
  eq(u8(out, L.wItems + 1), 99, v .. ": the first full")
  eq(u8(out, L.wItems + 3), 50, v .. ": the second the rest")
  eq(u8(out, L.wItems + 4), 0xFF, v .. ": then the terminator")
  eq(u8(out, L.wNumPCItems), 2, v .. ": the PC box is written too")
  eq(u8(out, L.wPCItems), 0x1E, v .. ": with the item")
  eq(u8(out, L.wPCItems + 1), 99, v .. ": in stacks of 99")
end

-- engine/pokedex/unown_dex.asm:1, data/events/engine_flags.asm:65
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save = import("g2." .. v .. ".basic")
  save.unownDex = { 5, 2 }
  save.firstUnownSeen = 5
  save.engineFlags[v == "crystal" and 44 or 43] = true
  local out = export(v, save, false)
  eq(u8(out, L.wUnownDex), 5, v .. ": wUnownDex in catching order")
  eq(u8(out, L.wUnownDex + 1), 2, v .. ": second letter")
  eq(u8(out, L.wUnownDex + 2), 0, v .. ": zero-terminated")
  eq(u8(out, L.wFirstUnownSeen), 5, v .. ": wFirstUnownSeen")
  eq(u8(out, L.wUnlockedUnowns), 2, v .. ": ENGINE_UNLOCKED_UNOWNS_L_TO_R is bit 1")
end

-- constants/ram_constants.asm:43-78, :254-257, :300-304; pokecrystal engine/pokemon/caught_data.asm:169
for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save = import("g2." .. v .. ".basic")
  save.options = { textSpeed = "SLOW", battleScene = false, battleStyle = "SET", sound = "STEREO",
                   frame = 8, print = "DARKEST", menuAccount = false }
  save.mom = { name = "MOM", savedMoney = 70000, active = true, savingMoney = false, whichItem = 2,
               triggerBalance = 3000 }
  save.playerState = "bike"
  local out = export(v, save, false)
  eq(u8(out, L.sOptions), 0x05 + 0x80 + 0x40 + 0x20, v .. ": wOptions bits")
  eq(u8(out, L.sOptions + 2) % 8, 7, v .. ": frame 8 is wTextboxFrame 7")
  eq(u8(out, L.sOptions + 4), 0x7F, v .. ": GB printer DARKEST")
  eq(u8(out, L.sOptions + 5) % 2, 0, v .. ": menu account off")
  eq(be(out, L.wMomsMoney, 3), 70000, v .. ": wMomsMoney")
  eq(u8(out, L.wMomSavingMoney), 0x80, v .. ": MOM_ACTIVE_F alone")
  eq(u8(out, L.wWhichMomItem), 2, v .. ": wWhichMomItem")
  eq(be(out, L.wMomItemTriggerBalance, 3), 3000, v .. ": wMomItemTriggerBalance")
  eq(u8(out, L.wPlayerState), 1, v .. ": PLAYER_BIKE")
  if v == "crystal" then
    local m = save.party[1]
    m.caughtTime, m.caughtLevel, m.caughtLocation, m.caughtByGender = 2, 9, 5, "girl"
    out = export(v, save, false)
    eq(u8(out, L.wPartyMons + 0x1D), 0x89, "crystal: caught time and level")
    eq(u8(out, L.wPartyMons + 0x1E), 0x85, "crystal: caught gender bit and location")
  end
end

for _, v in ipairs(VERSIONS) do
  local L = Gen2Save.layoutFor(v)
  local save = import("g2." .. v .. ".basic")
  local padded, low = 0, 0
  for money = 0, 300 do
    save.player.money = money
    local out = export(v, save, false)
    if sum16(out, L.sGameData, L.sGameDataEnd) % 256 == 0 then low = low + 1 end
    if u8(out, L.wGreensName + 10) ~= 0 then padded = padded + 1 end
  end
  eq(low, 0, v .. ": no fresh export has a primary sum whose low byte is 0")
  check(padded > 0, v .. ": the pad byte after GREEN's terminator is what keeps it nonzero")
end

do
  local save = import("g2.crystal.full_party")
  local saved = { random = math.random, time = os.time, date = os.date, clock = os.clock }
  local function trap() error("export consulted the clock or the RNG") end
  math.random, os.time, os.date, os.clock = trap, trap, trap, trap
  local a, aerr = Gen2Save.encode(save, "crystal", nil, K.gen2Data)
  local b = Gen2Save.encode(save, "crystal", nil, K.gen2Data)
  math.random, os.time, os.date, os.clock = saved.random, saved.time, saved.date, saved.clock
  check(a ~= nil, "a fresh export needs neither -- " .. tostring(aerr))
  eq(a, b, "and is byte-identical every time")
end

do
  local b = B.new(0x8000, 0)
  b[0x2008] = 0x63
  b[0x2009] = 0x12
  B.le(b, 0x2D0D, B.sum16(b, 0x2009, 0x2C8C), 2)
  local none, why = Gen2Save.decode(B.pack(b), "gold", K.gen2Data)
  eq(none, nil, "a Japanese Gold save is refused")
  check(type(why) == "string" and why:find("Japanese", 1, true) ~= nil, "by name, not as a checksum -- " .. tostring(why))
end

do
  local c = fixtures["g2.gold.basic"]
  local none, why = Gen2Save.decode(c.bytes, "gold", { pokemon = { ABRA = { index = 148, dex = 63 } } })
  eq(none, nil, "Red's tables in place of Gold's are refused")
  check(type(why) == "string" and why:find("data cache is missing", 1, true) ~= nil, "and the reason says so -- " .. tostring(why))
  none, why = Gen2Save.decode(c.bytes, "gold", {})
  eq(none, nil, "so is no data at all")
  check(Gen2Save.decode(c.bytes, "gold") ~= nil, "while no crosswalk on purpose keeps the raw numbers")
  local raw = assert(Gen2Save.decode(c.bytes, "gold"))
  none, why = Gen2Save.encode(raw, "gold", c.bytes, { pokemon = { ABRA = { index = 148, dex = 63 } } })
  eq(none, nil, "an export against Red's tables is refused too")
  check(type(why) == "string" and why:find("data cache is missing", 1, true) ~= nil, "with the same reason -- " .. tostring(why))
end

do
  local L = Gen2Save.layoutFor("gold")
  local bytes = B.fromString(fixtures["g2.gold.full_party"].bytes)
  bytes[L.wPartySpecies + 2] = 99
  G2.seal(bytes, "gold")
  local src = B.pack(bytes)
  local save = assert(Gen2Save.decode(src, "gold", K.gen2Data))
  eq(save.party[3].species, 120, "a list byte that disagrees with its struct keeps the struct's species")
  local out = assert(Gen2Save.encode(save, "gold", src, K.gen2Data))
  eq(u8(out, L.wPartySpecies + 2), 99, "and the list byte is carried while the struct is unchanged")
end

T.finish()
