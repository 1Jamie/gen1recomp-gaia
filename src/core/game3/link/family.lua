local GameVersion = require("src.core.GameVersion")

local Family = {}

-- pokeemerald/include/constants/global.h:8
Family.VERSION = { SAPPHIRE = 1, RUBY = 2, EMERALD = 3, FIRE_RED = 4, LEAF_GREEN = 5 }
-- pokeemerald/src/link.c:330
Family.VERSION_TAG = 0x4000
-- pokeemerald/src/link.c:332
Family.PROGRESS_NATIONAL = 0x01
Family.PROGRESS_LINK_NATIONALLY = 0x10

-- pokeemerald/include/constants/trade.h:27
Family.TRADE = { BOTH_PLAYERS_READY = 0, PLAYER_NOT_READY = 1, PARTNER_NOT_READY = 2 }
-- pokeemerald/include/constants/union_room.h:86
Family.UR_TRADE = { READY = 0, PLAYER_NOT_READY = 1, PARTNER_NOT_READY = 2 }
-- pokeemerald/include/constants/trade.h:14
Family.CAN_TRADE_MON = 0
Family.CANT_TRADE_LAST_MON = 1
Family.CANT_TRADE_NATIONAL = 2
Family.CANT_TRADE_EGG_YET = 3
Family.CANT_TRADE_INVALID_MON = 4
Family.CANT_TRADE_PARTNER_EGG_YET = 5
-- pokeemerald/include/save_location.h:13
Family.CHAMPION_SAVEWARP = 0x80

-- pokeemerald/include/constants/union_room.h:20
local ACTIVITY_COMMON = {
  NONE = 0, BATTLE_SINGLE = 1, BATTLE_DOUBLE = 2, BATTLE_MULTI = 3, TRADE = 4, CHAT = 5,
  CARD = 8, POKEMON_JUMP = 9, BERRY_CRUSH = 10, BERRY_PICK = 11, SEARCH = 12, SPIN_TRADE = 13,
  RECORD_CORNER = 15, BERRY_BLENDER = 16, ACCEPT = 17, DECLINE = 18, NPCTALK = 19,
  PLYRTALK = 20, WONDER_CARD = 21, WONDER_NEWS = 22,
}

Family.ACTIVITY_EXTRA = {
  -- pokefirered/include/constants/union_room.h:35
  frlg = { ITEM_TRADE = 14 },
  -- pokeemerald/include/constants/union_room.h:26
  rse = {
    WONDER_CARD_DUP = 6, WONDER_NEWS_DUP = 7, BATTLE_TOWER_OPEN = 14,
    CONTEST_COOL = 23, CONTEST_BEAUTY = 24, CONTEST_CUTE = 25, CONTEST_SMART = 26,
    CONTEST_TOUGH = 27, BATTLE_TOWER = 28,
  },
}

local function cap(activity, min, max)
  return { activity = activity, min = min, max = max }
end

Family.GROUP_ACTIVITY = {
  -- pokefirered/src/data/union_room.h:43
  frlg = {
    [0] = cap("BATTLE_SINGLE", 0, 2), [1] = cap("BATTLE_DOUBLE", 0, 2),
    [2] = cap("BATTLE_MULTI", 0, 4), [3] = cap("TRADE", 0, 2),
    [4] = cap("POKEMON_JUMP", 2, 5), [5] = cap("BERRY_CRUSH", 2, 5),
    [6] = cap("BERRY_PICK", 3, 5), [7] = cap("SPIN_TRADE", 3, 5), [8] = cap("ITEM_TRADE", 3, 5),
  },
  -- pokeemerald/src/data/union_room.h:641
  rse = {
    [0] = cap("BATTLE_SINGLE", 0, 2), [1] = cap("BATTLE_DOUBLE", 0, 2),
    [2] = cap("BATTLE_MULTI", 0, 4), [3] = cap("TRADE", 0, 2),
    [4] = cap("POKEMON_JUMP", 2, 5), [5] = cap("BERRY_CRUSH", 2, 5),
    [6] = cap("BERRY_PICK", 3, 5), [7] = cap("NONE", 0, 0), [8] = cap("NONE", 0, 0),
    [9] = cap("NONE", 0, 0), [10] = cap("NONE", 0, 0), [11] = cap("NONE", 0, 0),
    [12] = cap("RECORD_CORNER", 2, 4), [13] = cap("BERRY_BLENDER", 2, 4),
    [14] = cap("NONE", 0, 0), [15] = cap("CONTEST_COOL", 2, 4),
    [16] = cap("CONTEST_BEAUTY", 2, 4), [17] = cap("CONTEST_CUTE", 2, 4),
    [18] = cap("CONTEST_SMART", 2, 4), [19] = cap("CONTEST_TOUGH", 2, 4),
    [20] = cap("BATTLE_TOWER", 0, 2), [21] = cap("BATTLE_TOWER_OPEN", 0, 2),
  },
}

Family.PROGRESS_FLAG = {
  -- pokefirered/src/link.c:353
  frlg = "FLAG_SYS_CAN_LINK_WITH_RS",
  -- pokeemerald/src/link.c:333
  rse = "FLAG_IS_CHAMPION",
}

Family.LINK_BATTLE_SONGS = {
  -- pokefirered/src/cable_club.c:656
  frlg = { leader = "MUS_RS_VS_GYM_LEADER", trainer = "MUS_RS_VS_TRAINER" },
  -- pokeemerald/src/cable_club.c:863
  rse = { leader = "MUS_VS_GYM_LEADER", trainer = "MUS_VS_TRAINER" },
}

-- pokeemerald/data/maps/map_groups.json:459
Family.MAPS = {
  unionRoom = "UNION_ROOM",
  colosseum2P = "BATTLE_COLOSSEUM_2P",
  colosseum4P = "BATTLE_COLOSSEUM_4P",
  tradeCenter = "TRADE_CENTER",
  recordCorner = "RECORD_CORNER",
}

local function profileOf(version)
  return require("src.core.game3.profile").of(version)
end

function Family.activeVersion()
  local rt = package.loaded["src.core.game3.runtime"]
  local s = rt and rt.getSession and rt.getSession()
  if type(s) == "table" and type(s.version) == "string" and GameVersion.VERSIONS[s.version] then
    return s.version
  end
  local v = GameVersion.get and GameVersion.get() or nil
  if v and GameVersion.VERSIONS[v] and GameVersion.generation(v) == 3 then return v end
  return "firered"
end

function Family.of(version)
  version = version or Family.activeVersion()
  local ok, row = pcall(profileOf, version)
  return ok and type(row) == "table" and row.family or "frlg"
end

function Family.isGame3(version)
  return type(version) == "string" and GameVersion.VERSIONS[version] ~= nil
    and GameVersion.generation(version) == 3
end

function Family.cartVersion(version)
  return tonumber(GameVersion.gameCode(version or Family.activeVersion())) or Family.VERSION.FIRE_RED
end

function Family.versionForCart(code)
  code = (tonumber(code) or 0) % 0x100
  for id, info in pairs(GameVersion.VERSIONS) do
    if info.generation == 3 and tonumber(info.gameCode) == code then return id end
  end
  return nil
end

function Family.familyForCart(code)
  code = (tonumber(code) or 0) % 0x100
  if code == Family.VERSION.FIRE_RED or code == Family.VERSION.LEAF_GREEN then return "frlg" end
  if code >= Family.VERSION.SAPPHIRE and code <= Family.VERSION.EMERALD then return "rse" end
  return nil
end

function Family.activity(version)
  local family = Family.of(version)
  local out = {}
  for k, v in pairs(ACTIVITY_COMMON) do out[k] = v end
  for k, v in pairs(Family.ACTIVITY_EXTRA[family] or {}) do out[k] = v end
  return out
end

function Family.groupActivity(version, group)
  local family = Family.of(version)
  local row = (Family.GROUP_ACTIVITY[family] or Family.GROUP_ACTIVITY.frlg)[tonumber(group) or -1]
  if not row then return nil end
  return { activity = Family.activity(version)[row.activity], name = row.activity,
           min = row.min, max = row.max }
end

function Family.mapId(version, key)
  version = version or Family.activeVersion()
  local suffix = Family.MAPS[key]
  if not suffix then error("link family: no map " .. tostring(key), 2) end
  local row = profileOf(version)
  local prefix = row and row.map and row.map.enginePrefix or "FR_"
  return prefix .. suffix
end

local function constants(version)
  return require("src.core.game3.constants").of(version)
end

function Family.var(version, name)
  return constants(version or Family.activeVersion()):require("vars", name)
end

function Family.flag(version, name)
  return constants(version or Family.activeVersion()):require("flags", name)
end

function Family.species(version, name)
  return constants(version or Family.activeVersion()):require("species", name)
end

function Family.linkBattleSongs(version)
  return Family.LINK_BATTLE_SONGS[Family.of(version)] or Family.LINK_BATTLE_SONGS.frlg
end

function Family.cableClubVar(version)
  return Family.var(version, "VAR_CABLE_CLUB_STATE")
end

local function storeOf(session)
  if type(session) ~= "table" then return nil end
  local store = session.store
  if type(store) == "table" then return store end
  if type(session.flags) == "table" or type(session.vars) == "table" then
    return { flags = session.flags or {}, vars = session.vars or {} }
  end
  return nil
end

local function flagSet(store, id)
  if type(store) ~= "table" or type(store.flags) ~= "table" or id == nil then return false end
  local v = store.flags[id]
  return v == true or v == 1
end

function Family.nationalDex(session, version)
  local ok, PokedexData = pcall(require, "src.core.game3.pokedex_data")
  if not (ok and PokedexData and PokedexData.isNationalUnlocked) then return false end
  local view = session
  if type(session) == "table" and version and session.version ~= version then
    view = setmetatable({ version = version }, { __index = session })
  end
  local okU, unlocked = pcall(PokedexData.isNationalUnlocked, view, type(session) == "table" and session.dex or nil)
  return okU and unlocked == true
end

function Family.canLinkNationally(session, version)
  version = version or (type(session) == "table" and session.version) or Family.activeVersion()
  local name = Family.PROGRESS_FLAG[Family.of(version)]
  if not name then return false end
  return flagSet(storeOf(session), Family.flag(version, name))
end

-- pokeemerald/src/link.c:324 InitLocalLinkPlayer
function Family.localLinkPlayer(session, version)
  version = version or (type(session) == "table" and session.version) or Family.activeVersion()
  local flags = Family.nationalDex(session, version) and Family.PROGRESS_NATIONAL or 0
  if Family.canLinkNationally(session, version) then
    flags = flags + Family.PROGRESS_LINK_NATIONALLY
  end
  return {
    version = Family.cartVersion(version) + Family.VERSION_TAG,
    gameVersion = Family.cartVersion(version),
    progressFlags = flags,
    family = Family.of(version),
    versionId = version,
  }
end

local function low8(v)
  return (tonumber(v) or 0) % 0x100
end

local function hiNibble(v)
  return math.floor((tonumber(v) or 0) / 16) % 16 ~= 0
end

local function loNibble(v)
  return (tonumber(v) or 0) % 16 ~= 0
end

local PROGRESS = {
  -- pokefirered/src/trade.c:2820 GetGameProgressForLinkTrade
  frlg = function(mine, partner)
    local v = low8(partner.version)
    local versionId
    if v == Family.VERSION.FIRE_RED or v == Family.VERSION.LEAF_GREEN then
      versionId = 0
    elseif v == Family.VERSION.RUBY or v == Family.VERSION.SAPPHIRE then
      versionId = 1
    else
      versionId = 2
    end
    if versionId > 0 then
      if hiNibble(mine.progressFlags) then
        if versionId == 2 then
          if hiNibble(partner.progressFlags) then return Family.TRADE.BOTH_PLAYERS_READY end
          return Family.TRADE.PARTNER_NOT_READY
        end
      else
        return Family.TRADE.PLAYER_NOT_READY
      end
    end
    return Family.TRADE.BOTH_PLAYERS_READY
  end,
  -- pokeemerald/src/trade.c:2453 GetGameProgressForLinkTrade
  rse = function(mine, partner)
    local v = low8(partner.version)
    local versionId = 0
    if v == Family.VERSION.RUBY or v == Family.VERSION.SAPPHIRE or v == Family.VERSION.EMERALD then
      versionId = 0
    elseif v == Family.VERSION.FIRE_RED or v == Family.VERSION.LEAF_GREEN then
      versionId = 2
    end
    if versionId > 0 then
      if hiNibble(mine.progressFlags) then
        if versionId == 2 then
          if hiNibble(partner.progressFlags) then return Family.TRADE.BOTH_PLAYERS_READY end
          return Family.TRADE.PARTNER_NOT_READY
        end
      else
        return Family.TRADE.PLAYER_NOT_READY
      end
    end
    return Family.TRADE.BOTH_PLAYERS_READY
  end,
}

function Family.gameProgressForLinkTrade(family, mine, partner)
  if type(partner) ~= "table" then return Family.TRADE.BOTH_PLAYERS_READY end
  local fn = PROGRESS[family] or PROGRESS.frlg
  return fn(type(mine) == "table" and mine or {}, partner)
end

local HOME_VERSIONS = {
  -- pokefirered/src/union_room.c:1505
  frlg = { [Family.VERSION.FIRE_RED] = true, [Family.VERSION.LEAF_GREEN] = true },
  -- pokeemerald/src/union_room.c:1270
  rse = { [Family.VERSION.EMERALD] = true },
}

-- pokeemerald/src/union_room.c:1266 IsTryingToTradeAcrossVersionTooSoon
function Family.tradeAcrossVersionTooSoon(family, opts)
  opts = type(opts) == "table" and opts or {}
  local home = HOME_VERSIONS[family] or HOME_VERSIONS.frlg
  if opts.trading and not home[low8(opts.partnerVersion)] then
    if (tonumber(opts.specialSaveWarpFlags) or 0) % 256 < Family.CHAMPION_SAVEWARP then
      return Family.UR_TRADE.PLAYER_NOT_READY
    elseif opts.partnerCanLinkNationally then
      return Family.UR_TRADE.READY
    end
    return Family.UR_TRADE.PARTNER_NOT_READY
  end
  return Family.UR_TRADE.READY
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

local function isEggMon(mon)
  if not mon then return false end
  if mon.isEgg or mon.egg then return true end
  return false
end

local function inRegional(species, version)
  local ok, v = pcall(require("src.core.game3.dex").inRegional, species, version)
  return ok and v == true
end

-- pokeemerald/src/trade.c:2389 CanTradeSelectedMon
local function canTradeRse(party, monIdx, opts, version)
  local idx = (tonumber(monIdx) or 0) + 1
  local count = tonumber(opts.partyCount) or #party
  local EGG = Family.species(version, "SPECIES_EGG")
  local MEW = Family.species(version, "SPECIES_MEW")
  local DEOXYS = Family.species(version, "SPECIES_DEOXYS")
  local species2, species = {}, {}
  for i = 1, count do
    species[i] = speciesOf(party[i])
    species2[i] = isEggMon(party[i]) and EGG or species[i]
  end
  local national = opts.nationalDex
  if national == nil then national = Family.nationalDex(opts.session, version) end
  if not national then
    if species2[idx] == EGG then return Family.CANT_TRADE_EGG_YET end
    if not inRegional(species2[idx], version) then return Family.CANT_TRADE_NATIONAL end
  end
  local partner = opts.partner
  if type(partner) == "table" then
    local v = low8(partner.version)
    if v ~= Family.VERSION.RUBY and v ~= Family.VERSION.SAPPHIRE then
      if not loNibble(partner.progressFlags) then
        if species2[idx] == EGG then return Family.CANT_TRADE_PARTNER_EGG_YET end
        if not inRegional(species2[idx], version) then return Family.CANT_TRADE_INVALID_MON end
      end
    end
  end
  if species[idx] == DEOXYS or species[idx] == MEW then
    if party[idx] and party[idx].fatefulEncounter == false then
      return Family.CANT_TRADE_INVALID_MON
    end
  end
  local left = 0
  for i = 1, count do
    if i ~= idx and species2[i] ~= EGG then left = left + (species2[i] or 0) end
  end
  if left ~= 0 then return Family.CAN_TRADE_MON end
  return Family.CANT_TRADE_LAST_MON
end

function Family.canTradeSelectedMon(version, party, monIdx, opts)
  version = version or Family.activeVersion()
  opts = type(opts) == "table" and opts or {}
  party = type(party) == "table" and party or {}
  if Family.of(version) == "rse" then
    return canTradeRse(party, monIdx, opts, version)
  end
  return require("src.core.game3.scripting.natives_trade").canTradeSelectedMon(party, monIdx, opts)
end

return Family
