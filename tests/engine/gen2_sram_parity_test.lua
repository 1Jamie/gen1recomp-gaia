package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2Layout = require("src.save_convert.Gen2Layout")
local Gen2MapContext = require("src.save_convert.Gen2MapContext")

local function fixture()
  return {
    pokemon = {
      PIKACHU = { index = 25 },
      CYNDAQUIL = { index = 155 },
      TOTODILE = { index = 158 },
      CHIKORITA = { index = 152 },
    },
    moves = {
      TACKLE = { index = 33, pp = 35 },
      GROWL = { index = 45, pp = 40 },
    },
    items = {
      POKE_BALL = { index = 4, pocket = "BALL" },
      POTION = { index = 20, pocket = "ITEM" },
      FLOWER_MAIL = { index = 158, pocket = "ITEM" },
    },
    maps = { PLAYERS_HOUSE_2F = {
      group = 24, map = 7, objectEventsAddr = 0x5CF0,
      width = 4, height = 3,
      blocks = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 },
      objects = {},
    } },
  }
end

local function u8(bytes, at) return bytes:byte(at + 1) end
local function be(bytes, at, n)
  local v = 0
  for i = 0, n - 1 do v = v * 256 + bytes:byte(at + i + 1) end
  return v
end

print("[test] 1. Active Box (sBox) in Bank 1 serialization & parity")
do
  for _, version in ipairs({ "gold", "crystal" }) do
    local L = Gen2Save.layoutFor(version)
    local save = {
      generation = 2,
      player = { name = "ASH", id = 12345, money = 5000 },
      rival = { name = "GARY" }, mom = { name = "MOM" },
      position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
      party = {},
      currentBox = 2,
      boxes = {
        [1] = {
          { species = "CYNDAQUIL", level = 5, moves = { { id = "TACKLE" } } }
        },
        [2] = {
          { species = "TOTODILE", level = 10, nickname = "TOTO", ot = "ASH", otId = 12345,
            moves = { { id = "TACKLE", pp = 35, ppUps = 0 } } },
          { species = "PIKACHU", level = 12, nickname = "PIKA", ot = "ASH", otId = 12345,
            moves = { { id = "GROWL", pp = 40, ppUps = 1 } } }
        }
      },
      playTime = { hours = 10, minutes = 25, seconds = 42, frames = 15 }
    }

    local bytes, err = Gen2Save.encode(save, version, nil, fixture())
    check(bytes ~= nil, version .. ": save encodes with active box -- " .. tostring(err))
    eq(#bytes, Gen2Save.SAVE_SIZE, version .. ": 32 KB save size")

    -- Check sBox in Bank 1
    eq(u8(bytes, L.sBox), 2, version .. ": sBox count matches active box (box 2)")
    eq(u8(bytes, L.sBox + 1), 158, version .. ": sBox species 1 is TOTODILE (158)")
    eq(u8(bytes, L.sBox + 2), 25, version .. ": sBox species 2 is PIKACHU (25)")
    eq(u8(bytes, L.sBox + 3), 0xFF, version .. ": sBox species list terminated with 0xFF")

    -- sBox in Bank 1 matches sBox2 in Bank 2 byte-for-byte
    local box2Base = L.boxes[2]
    local sBoxSlice = bytes:sub(L.sBox + 1, L.sBox + 1102)
    local box2Slice = bytes:sub(box2Base + 1, box2Base + 1102)
    eq(sBoxSlice, box2Slice, version .. ": sBox in Bank 1 is byte-identical to active sBox2 in Bank 2")

    -- Check primary checksum validity
    eq(Gen2Save.checksumValid(bytes, L), true, version .. ": primary checksum is valid")
  end
end

print("[test] 2. Crystal Bank 0 Backup Save & Checksums")
do
  local L = Gen2Save.layoutFor("crystal")
  local save = {
    generation = 2,
    player = { name = "KRIS", id = 54321, money = 9999, gender = "female" },
    rival = { name = "SILVER" }, mom = { name = "MOM" },
    position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
    party = {
      { species = "CHIKORITA", level = 5, moves = { { id = "TACKLE" } } }
    },
    boxes = {},
    playTime = { hours = 1, minutes = 2, seconds = 3, frames = 4 }
  }

  local bytes, err = Gen2Save.encode(save, "crystal", nil, fixture())
  check(bytes ~= nil, "crystal: encode succeeds")

  -- Verify Backup Check Values in Bank 0
  eq(u8(bytes, L.backupSave.checkValue1), 0x63, "sBackupCheckValue1 at 0x1208 is 0x63")
  eq(u8(bytes, L.backupSave.checkValue2), 0x7F, "sBackupCheckValue2 at 0x1F0F is 0x7F")

  eq(Gen2Save.backupValid(bytes, L), true, "backup save checksum validates cleanly in Bank 0")
  eq(be(bytes, L.backupSave.checksum, 1) + be(bytes, L.backupSave.checksum + 1, 1) * 256,
     be(bytes, L.sChecksum, 1) + be(bytes, L.sChecksum + 1, 1) * 256, "backup checksum equals the primary's")

  -- Verify player name in backup
  local backName = {}
  for i = 0, 10 do
    local c = u8(bytes, L.wPlayerName - L.sGameData + L.backupSave.segments[1][2] + i)
    if c == 0x50 then break end
    backName[#backName + 1] = Gen2Layout.charmap[c]
  end
  eq(table.concat(backName), "KRIS", "backup wPlayerName matches primary")
end

print("[test] 3. String Padding & 0x50 Fill (No Buffer Overrun)")
do
  local L = Gen2Save.layoutFor("gold")
  local save = {
    generation = 2,
    player = { name = "RED", id = 100 },
    rival = { name = "BLUE" }, mom = { name = "MOMMY" },
    position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
    party = {
      { species = "PIKACHU", nickname = "SPARK", ot = "RED", otId = 100 }
    },
    boxNames = { [1] = "MAIN" },
    boxes = {},
  }

  local bytes, err = Gen2Save.encode(save, "gold", nil, fixture())
  check(bytes ~= nil, "encode succeeds")

  -- Verify 11-byte player name: 'R', 'E', 'D', followed by eight 0x50 bytes
  eq(u8(bytes, L.wPlayerName + 0), 0x91, "P1 'R'")
  eq(u8(bytes, L.wPlayerName + 1), 0x84, "P2 'E'")
  eq(u8(bytes, L.wPlayerName + 2), 0x83, "P3 'D'")
  for i = 3, 10 do
    eq(u8(bytes, L.wPlayerName + i), 0x50, "Player name padded with 0x50 at byte " .. i)
  end

  -- engine/menus/intro_menu.asm:148, home/copy_name.asm:5
  eq(u8(bytes, L.wBoxNames + 0), 0x8C, "B1 'M'")
  eq(u8(bytes, L.wBoxNames + 1), 0x80, "B2 'A'")
  eq(u8(bytes, L.wBoxNames + 2), 0x88, "B3 'I'")
  eq(u8(bytes, L.wBoxNames + 3), 0x8D, "B4 'N'")
  eq(u8(bytes, L.wBoxNames + 4), 0x50, "Box name terminated with 0x50")
  for i = 5, 8 do
    eq(u8(bytes, L.wBoxNames + i), 0x00, "Box name keeps the zero tail after its terminator at byte " .. i)
  end

  -- Verify party mon nickname padding
  local nickBase = L.wPartyMonNicknames
  eq(u8(bytes, nickBase + 0), 0x92, "N1 'S'")
  eq(u8(bytes, nickBase + 1), 0x8F, "N2 'P'")
  eq(u8(bytes, nickBase + 2), 0x80, "N3 'A'")
  eq(u8(bytes, nickBase + 3), 0x91, "N4 'R'")
  eq(u8(bytes, nickBase + 4), 0x8A, "N5 'K'")
  for i = 5, 10 do
    eq(u8(bytes, nickBase + i), 0x50, "Nickname padded with 0x50 at byte " .. i)
  end
end

print("[test] 4. Play Time Seconds & Frames Roundtrip")
do
  local save = {
    generation = 2,
    player = { name = "TIME", id = 999 },
    position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
    party = {}, boxes = {},
    playTime = { hours = 123, minutes = 45, seconds = 56, frames = 29 }
  }

  local bytes = Gen2Save.encode(save, "gold", nil, fixture())
  local decoded = Gen2Save.decode(bytes, "gold")
  eq(decoded.playTime.hours, 123, "hours roundtrip")
  eq(decoded.playTime.minutes, 45, "minutes roundtrip")
  eq(decoded.playTime.seconds, 56, "seconds roundtrip")
  eq(decoded.playTime.frames, 29, "frames roundtrip")
end

print("[test] 5. Default Base Happiness to 70")
do
  local save = {
    generation = 2,
    player = { name = "HAP", id = 111 },
    position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
    party = {
      { species = "CYNDAQUIL", level = 5 } -- happiness is nil
    },
    boxes = {
      [1] = {
        { species = "TOTODILE", level = 5 } -- happiness is nil
      }
    }
  }

  local bytes = Gen2Save.encode(save, "gold", nil, fixture())
  local decoded = Gen2Save.decode(bytes, "gold")
  eq(decoded.party[1].happiness, 70, "party mon unset happiness defaults to 70")
  eq(decoded.boxes[1][1].happiness, 70, "box mon unset happiness defaults to 70")
end

print("[test] 6. Bank 0 Party Mail Struct Synchronization")
do
  local save = {
    generation = 2,
    player = { name = "MAILER", id = 7777 },
    position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
    party = {
      { species = "PIKACHU", item = "FLOWER_MAIL", ot = "MAILER", otId = 7777 },
      { species = "TOTODILE", item = "POTION" } -- not holding mail
    },
    mail = {
      party = {
        [1] = {
          type = "FLOWER_MAIL",
          message = "HELLO WORLD",
          author = "MAILER",
          authorId = 7777,
          species = "PIKACHU",
        }
      }
    },
    boxes = {},
  }

  local bytes = Gen2Save.encode(save, "crystal", nil, fixture())
  local L = Gen2Save.layoutFor("crystal")
  -- ram/sram.asm:8 sPartyMail, :14 sPartyMailBackup
  for _, base in ipairs({ L.sPartyMail, L.sPartyMailBackup }) do
    eq(be(bytes, base + 43, 2), 7777, ("0x%04X: slot 1 mail authorId matches"):format(base))
    eq(u8(bytes, base + 45), 25, ("0x%04X: slot 1 mail species matches PIKACHU (25)"):format(base))
    eq(u8(bytes, base + 46), 158, ("0x%04X: slot 1 mail type matches FLOWER_MAIL (158)"):format(base))
    eq(u8(bytes, base + 47), 0, ("0x%04X: slot 2 (no mail) is 0x00"):format(base))
  end
  for i = 0, 0x5FF do
    if u8(bytes, i) ~= 0 then check(false, ("sScratch byte 0x%04X is untouched"):format(i)) break end
  end
  local back = assert(Gen2Save.decode(bytes, "crystal", fixture()))
  eq(back.mail.party[1].message, "HELLO WORLD", "the letter imports back")
  eq(back.mail.party[1].author, "MAILER", "with its author")
  eq(back.mail.party[2], nil, "and a mon holding a POTION has no letter")
end

print("[test] 7. Full Save Roundtrip & Parity Verification")
do
  local fullFixture = {
    pokemon = {
      CHIKORITA = { index = 152 },
      BAYLEEF = { index = 153 },
      CYNDAQUIL = { index = 155 },
      TYPHLOSION = { index = 157 },
      TOTODILE = { index = 158 },
      PIKACHU = { index = 25 },
      TOGEPI = { index = 175 },
      MAREEP = { index = 179 },
      AMPHAROS = { index = 181 },
    },
    moves = {
      TACKLE = { index = 33, pp = 35 },
      GROWL = { index = 45, pp = 40 },
      EMBER = { index = 52, pp = 25 },
      THUNDERSHOCK = { index = 84, pp = 30 },
    },
    items = {
      MASTER_BALL = { index = 1, pocket = "BALL" },
      POKE_BALL = { index = 4, pocket = "BALL" },
      POTION = { index = 20, pocket = "ITEM" },
      BERRY = { index = 77, pocket = "ITEM" },
      FLOWER_MAIL = { index = 158, pocket = "ITEM" },
      BICYCLE = { index = 7, pocket = "KEY_ITEM" },
      TM01 = { index = 191, pocket = "TM_HM", tmNumber = 1 },
      HM01 = { index = 241, pocket = "TM_HM", tmNumber = 51 },
    },
    maps = { PLAYERS_HOUSE_2F = {
      group = 24, map = 7, objectEventsAddr = 0x5CF0,
      width = 4, height = 3,
      blocks = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 },
      objects = {},
    } },
  }

  for _, version in ipairs({ "gold", "crystal" }) do
    local richSave = {
      generation = 2,
      player = {
        name = "GOLD", id = 42105, gender = "female", money = 87654, coins = 1250,
        badges = { ZEPHYR = true, HIVE = true, PLAIN = true, FOG = true },
        kantoBadges = { BOULDER = true, CASCADE = true },
      },
      rival = { name = "SILVER" }, mom = { name = "MOM" },
      position = { map = "PLAYERS_HOUSE_2F", mapGroup = 24, mapNumber = 7, x = 3, y = 3 },
      playTime = { hours = 48, minutes = 32, seconds = 17, frames = 45 },
      currentBox = 2,
      boxNames = { [1] = "STARTERS", [2] = "ELECTRIC" },
      party = {
        {
          species = "TYPHLOSION", level = 42, nickname = "CINDER", ot = "GOLD", otId = 42105,
          item = "BERRY", experience = 84500, hp = 135, maxHp = 135,
          stats = { hp = 135, attack = 95, defense = 88, speed = 110, specialAttack = 119, specialDefense = 95 },
          statExp = { hp = 1200, attack = 1500, defense = 900, speed = 2100, special = 1800 },
          dvs = { attack = 14, defense = 12, speed = 15, special = 13 },
          moves = { { id = "EMBER", pp = 25, ppUps = 0 } },
          happiness = 220, pokerus = 0, caughtData = 0x4815,
        },
      },
      boxes = {
        [1] = {
          { species = "CHIKORITA", level = 5, nickname = "CHIQUI", ot = "GOLD", otId = 42105,
            moves = { { id = "TACKLE", pp = 35, ppUps = 0 } }, dvs = { attack = 12, defense = 11, speed = 10, special = 14 } },
        },
        [2] = {
          { species = "PIKACHU", level = 20, nickname = "SPARK", ot = "ASH", otId = 10001,
            moves = { { id = "THUNDERSHOCK", pp = 30, ppUps = 0 } }, dvs = { attack = 15, defense = 15, speed = 15, special = 15 } },
        },
      },
      inventory = {
        POTION = 5, BERRY = 10, MASTER_BALL = 1, POKE_BALL = 20,
        BICYCLE = 1, TM01 = 1, HM01 = 1,
      },
      pokedex = {
        caught = { CYNDAQUIL = true, TYPHLOSION = true, PIKACHU = true },
        seen = { CHIKORITA = true, BAYLEEF = true, CYNDAQUIL = true, TYPHLOSION = true, PIKACHU = true },
      },
      events = { [0] = 0x55, [1] = 0xAA },
    }

    local savBytes, encErr = Gen2Save.encode(richSave, version, nil, fullFixture)
    check(savBytes ~= nil, version .. ": full save encode succeeds -- " .. tostring(encErr))
    local decoded, decErr = Gen2Save.decode(savBytes, version, fullFixture)
    check(decoded ~= nil, version .. ": full save decode succeeds -- " .. tostring(decErr))

    eq(decoded.player.name, richSave.player.name, version .. ": player name matches")
    eq(decoded.player.id, richSave.player.id, version .. ": player ID matches")
    eq(decoded.player.money, richSave.player.money, version .. ": player money matches")
    eq(decoded.player.coins, richSave.player.coins, version .. ": player coins matches")
    if version == "crystal" then
      eq(decoded.player.gender, richSave.player.gender, version .. ": player gender matches")
    end
    eq(decoded.playTime.hours, richSave.playTime.hours, version .. ": play hours match")
    eq(decoded.playTime.minutes, richSave.playTime.minutes, version .. ": play minutes match")
    eq(decoded.playTime.seconds, richSave.playTime.seconds, version .. ": play seconds match")
    eq(decoded.playTime.frames, richSave.playTime.frames, version .. ": play frames match")
    eq(decoded.currentBox, richSave.currentBox, version .. ": current box matches")
    eq(decoded.boxNames[1], "STARTERS", version .. ": box 1 name matches")
    eq(decoded.boxNames[2], "ELECTRIC", version .. ": box 2 name matches")
    eq(#decoded.party, 1, version .. ": party length matches")
    eq(decoded.party[1].species, "TYPHLOSION", version .. ": party 1 species matches")
    eq(decoded.party[1].nickname, "CINDER", version .. ": party 1 nickname matches")
    eq(decoded.party[1].happiness, 220, version .. ": party 1 happiness matches")
    eq(decoded.boxes[1][1].species, "CHIKORITA", version .. ": box 1 mon matches")
    eq(decoded.boxes[2][1].species, "PIKACHU", version .. ": active box mon matches")
    for item, count in pairs(richSave.inventory) do
      eq(decoded.inventory[item], count, version .. ": inventory " .. item .. " count matches")
    end
    for mon in pairs(richSave.pokedex.caught) do
      eq(decoded.pokedex.caught[mon], true, version .. ": dex caught " .. mon .. " matches")
    end
  end
end

T.finish()
