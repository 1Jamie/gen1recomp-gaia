package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveConvert = require("src.save_convert.SaveConvert")
local Gen2Save = require("src.save_convert.Gen2Save")
local Compat = require("src.save_convert.Compat")
local Ref = require("tests.save_compat._gen2_reference")
local Diff = require("tests.save_compat._diff")

local N = tonumber(os.getenv("SAVE_COMPAT_ENGINE_N")) or 200
local SEED = tonumber(os.getenv("SAVE_COMPAT_ENGINE_SEED")) or 20261001

local HOME = os.getenv("HOME") or ""
local ROOTS = {
  gold = os.getenv("GOLD_CACHE") or HOME .. "/Library/Application Support/LOVE/gold-bsa0925-gameplay/gold",
  silver = os.getenv("SILVER_CACHE") or HOME .. "/Library/Application Support/LOVE/pokemon-love2d/silver",
  crystal = os.getenv("CRYSTAL_CACHE") or HOME .. "/Library/Application Support/LOVE/crystal-bsa0925-gameplay/crystal",
}

local DATA = {}
for version, dir in pairs(ROOTS) do
  DATA[version] = SaveConvert.gen2DataFromDir(dir)
end
if not (DATA.gold and DATA.silver and DATA.crystal) then
  print("SKIP engine fuzz: no extracted Gen 2 caches on this machine")
  T.finish()
  return
end

local EngineSave = require("src.core.gen2.Save")
local Mon = require("src.battle.gen2.Mon")
local Boxes = require("src.core.gen2.Boxes")
local Mail = require("src.core.gen2.Mail")

local state = SEED
local function rnd(a, b)
  state = (state * 48271) % 2147483647
  return a + state % (b - a + 1)
end
local function chance(p) return rnd(1, 1000) <= p * 1000 end
local function pick(list) return list[rnd(1, #list)] end

local function lists(version)
  local d = DATA[version]
  local out = { species = {}, items = { ITEM = {}, KEY_ITEM = {}, BALL = {}, TM_HM = {} }, maps = {}, moves = {}, sprites = {} }
  for id, def in pairs(d.pokemon) do
    if type(def) == "table" and def.index and def.index >= 1 and def.index <= 251 and def.baseStats then
      out.species[#out.species + 1] = id
    end
  end
  for id, def in pairs(d.items) do
    if type(def) == "table" and def.index and out.items[def.pocket] and not Mail.isMail(id)
        and not tostring(id):find("BADGE", 1, true) then
      table.insert(out.items[def.pocket], id)
    end
  end
  for id, def in pairs(d.maps) do
    if type(def) == "table" and def.group and def.map and def.width and def.width >= 2 and def.height and def.height >= 2
        and def.blocks and def.objectEventsAddr then
      out.maps[#out.maps + 1] = id
    end
  end
  for id, name in ipairs(d.constants.spriteOrder) do
    if d.constants.spriteContext.rows[id] or id >= 0x80 and id < 0xF0 and name ~= "UNUSED" and d.sprites[name] then
      out.sprites[#out.sprites + 1] = id
    end
  end
  for id, def in pairs(d.moves) do
    if type(def) == "table" and def.index and def.index >= 1 and def.index <= 251 then out.moves[#out.moves + 1] = id end
  end
  for _, l in pairs({ out.species, out.maps, out.moves, out.sprites, out.items.ITEM, out.items.KEY_ITEM, out.items.BALL, out.items.TM_HM }) do
    table.sort(l)
  end
  return out
end
local POOL = { gold = lists("gold"), silver = lists("silver"), crystal = lists("crystal") }

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function name(lo, hi)
  local out = {}
  for i = 1, rnd(lo, hi) do
    local k = rnd(1, #LETTERS)
    out[i] = LETTERS:sub(k, k)
  end
  return table.concat(out)
end

local MAIL_ITEMS = { "FLOWER_MAIL", "SURF_MAIL", "LITEBLUEMAIL", "PORTRAITMAIL", "LOVELY_MAIL", "EON_MAIL",
                     "MORPH_MAIL", "BLUESKY_MAIL", "MUSIC_MAIL", "MIRAGE_MAIL" }
local STATUSES = { "poison", "burn", "freeze", "paralyze", "toxic" }
local ENGINE_IDS = { 0, 1, 2, 3, 4, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 42, 43, 44, 45, 46, 47, 48, 49 }
for i = 50, 76 do ENGINE_IDS[#ENGINE_IDS + 1] = i end

local stats = { saves = 0, mons = 0, eggs = 0, forced = 0 }

local function newMon(version, data, pool, party)
  local species = pick(pool.species)
  local level = rnd(2, 100)
  local mon = Mon.new(data, species, level, {
    nickname = chance(0.3) and name(1, 10) or nil,
    item = chance(0.3) and pick(pool.items.ITEM) or nil,
    pokerus = chance(0.1) and rnd(1, 255) or 0,
    happiness = chance(0.5) and rnd(0, 255) or nil,
  })
  mon.statExp = { hp = rnd(0, 65535), attack = rnd(0, 65535), defense = rnd(0, 65535), speed = rnd(0, 65535),
                  special = rnd(0, 65535) }
  mon.experience = math.min(mon.experience + rnd(0, 20), 0xFFFFFF)
  mon.ot = name(1, 7)
  mon.otId = rnd(0, 65535)
  if version == "crystal" then
    mon.caughtTime, mon.caughtLevel, mon.caughtLocation = rnd(0, 3), rnd(0, 63), rnd(0, 127)
    mon.caughtByGender = chance(0.5) and "girl" or "boy"
  end
  for _ = 1, rnd(0, 3) do
    local id = pick(pool.moves)
    Mon.learnMove(mon, id, data)
  end
  for _, mv in ipairs(mon.moves) do
    mv.ppUps = rnd(0, 3)
    mv.maxPp = Mon.maxPpOf(mv, data)
    mv.pp = rnd(0, mv.maxPp)
  end
  if party then
    Mon.refreshStats(mon, data)
    mon.hp = rnd(0, mon.maxHp)
    if chance(0.35) then
      local kind = rnd(1, 6)
      if kind == 1 then mon.status, mon.statusTurns = "sleep", rnd(1, 7)
      else mon.status = STATUSES[kind - 1] end
    end
  else
    Boxes.enterBox(mon, data)
  end
  if chance(0.06) and species ~= "UNOWN" then
    mon.shiny = true
    stats.forced = stats.forced + 1
  end
  if chance(0.08) then
    mon.isEgg, mon.eggSteps, mon.happiness, mon.nickname = true, rnd(0, 255), 120, nil
    mon.hp = 0
  end
  return mon
end

local function buildSave(version)
  local data = DATA[version]
  local pool = POOL[version]
  local save = EngineSave.newGame({ playerName = name(1, 7), rivalName = name(1, 7), gender = chance(0.5) and "female" or "male",
                                    trainerId = rnd(0, 65535) })
  save.version = version
  if version ~= "crystal" then save.player.gender = "male" end
  save.player.money = rnd(0, 999999)
  save.player.coins = rnd(0, 9999)
  for _, b in ipairs(Gen2Save.JOHTO_BADGES) do if chance(0.5) then save.player.badges[b] = true end end
  for _, b in ipairs(Gen2Save.KANTO_BADGES) do if chance(0.5) then save.player.kantoBadges[b] = true end end
  save.mom = { name = name(1, 7), active = chance(0.5), savingMoney = chance(0.5), savedMoney = rnd(0, 999999),
               whichItem = rnd(0, 20), triggerBalance = rnd(0, 999999) }
  for i = 1, rnd(1, 6) do
    local mon = newMon(version, data, pool, true)
    save.party[i] = mon
    Mon.stampOT(save, mon)
  end
  for i, mon in ipairs(save.party) do
    if chance(0.25) and not mon.isEgg then
      local id = pick(MAIL_ITEMS)
      mon.item = id
      Mail.set(save, i, Mail.entry(id, name(0, 30), name(1, version == "crystal" and 8 or 10), rnd(0, 65535), mon.species))
    end
  end
  for b = 1, 14 do
    save.boxes[b] = {}
    if chance(0.4) then
      for i = 1, rnd(0, 20) do save.boxes[b][i] = newMon(version, data, pool, false) end
    end
    save.boxNames[b] = chance(0.4) and ("BOX" .. b) or name(1, 9)
  end
  Boxes.setCurrent(save, rnd(1, 14))
  for k = 1, rnd(0, 10) do
    local id = pick(MAIL_ITEMS)
    save.mail.box[k] = Mail.entry(id, name(0, 30), name(1, version == "crystal" and 8 or 10), rnd(0, 65535),
      pick(pool.species))
  end
  local function stock(poolList, cap, perStack, target, order)
    local used, slots = {}, 0
    while slots < cap and chance(0.8) do
      local id = pick(poolList)
      if not used[id] then
        local n = perStack and rnd(1, 250) or 1
        local need = perStack and math.ceil(n / 99) or 1
        if slots + need > cap then break end
        used[id] = true
        slots = slots + need
        target[id] = n
        order[#order + 1] = id
      end
    end
  end
  save.bagOrder = {}
  stock(pool.items.ITEM, 20, true, save.inventory, save.bagOrder)
  stock(pool.items.KEY_ITEM, 25, false, save.inventory, save.bagOrder)
  stock(pool.items.BALL, 12, true, save.inventory, save.bagOrder)
  for _, id in ipairs(pool.items.TM_HM) do
    if chance(0.3) then
      save.inventory[id] = rnd(1, 99)
      save.bagOrder[#save.bagOrder + 1] = id
    end
  end
  save.pcOrder = {}
  stock(pool.items.ITEM, 50, true, save.pcItems, save.pcOrder)
  for i = 1, 251 do
    local species
    for id, def in pairs(DATA[version].pokemon) do
      if type(def) == "table" and def.index == i then species = id break end
    end
    if species then
      if chance(0.3) then save.pokedex.caught[species] = true end
      if chance(0.5) then save.pokedex.seen[species] = true end
    end
  end
  local letters = {}
  for i = 1, 26 do letters[i] = i end
  save.unownDex = {}
  for i = 1, rnd(0, 26) do
    local k = rnd(i, 26)
    letters[i], letters[k] = letters[k], letters[i]
    save.unownDex[i] = letters[i]
  end
  save.firstUnownSeen = #save.unownDex > 0 and save.unownDex[1] or 0
  for i = 0, 255 do save.events[i] = rnd(0, 255) end
  local L = Gen2Save.layoutFor(version)
  for mapId in pairs(L.sceneVars) do
    if chance(0.2) then save.mapScenes[mapId] = rnd(1, 255) end
  end
  save.engineFlags = {}
  for _, id in ipairs(ENGINE_IDS) do
    if chance(0.5) then save.engineFlags[(version == "crystal" and id >= 16) and id + 1 or id] = true end
  end
  save.variableSprites = {}
  for i = 0, 15 do if chance(0.3) then save.variableSprites[i] = pick(pool.sprites) end end
  save.playerState = pick({ "normal", "bike", "surf", "surf_pika" })
  save.options = { textSpeed = pick({ "FAST", "MID", "SLOW" }), battleScene = chance(0.5), battleStyle = pick({ "SHIFT", "SET" }),
                   sound = pick({ "MONO", "STEREO" }), frame = rnd(1, 8),
                   print = pick({ "LIGHTEST", "LIGHTER", "NORMAL", "DARKER", "DARKEST" }), menuAccount = chance(0.5) }
  local mapId = pick(pool.maps)
  local def = DATA[version].maps[mapId]
  save.position = { map = mapId, x = rnd(0, def.width * 2 - 1), y = rnd(0, def.height * 2 - 1) }
  if mapId == "PLAYERS_HOUSE_2F" then
    local Decorations = require("src.core.gen2.Decorations")
    for _, row in ipairs(Decorations.visibility(Decorations.state(save))) do
      local index, mask = math.floor(row.flag / 8), 2 ^ (row.flag % 8)
      local byte = save.events[index] or 0
      save.events[index] = byte - math.floor(byte / mask) % 2 * mask + (row.hidden and mask or 0)
      if not row.hidden then save.variableSprites[row.sprite] = row.byte end
    end
  end
  save.playTime = { hours = rnd(0, 999), minutes = rnd(0, 59), seconds = rnd(0, 59), frames = rnd(0, 59) }
  return save
end

local function speciesIndex(version, id) return DATA[version].pokemon[id].index end
local function moveIndex(version, id) return DATA[version].moves[id].index end
local function itemIndex(version, id) return DATA[version].items[id].index end

local function statusByte(mon)
  if not mon.status then return 0 end
  if mon.status == "sleep" then return mon.statusTurns end
  return ({ poison = 8, toxic = 8, burn = 16, freeze = 32, paralyze = 64 })[mon.status]
end

local function compareMon(label, version, mon, ref, party, fails)
  local function chk(what, want, got)
    if want ~= got then fails[#fails + 1] = ("%s %s: %s != %s"):format(label, what, tostring(want), tostring(got)) end
  end
  chk("species", speciesIndex(version, mon.species), ref.species)
  chk("listed", mon.isEgg and 0xFD or ref.species, ref.listed)
  chk("item", mon.item and itemIndex(version, mon.item) or 0, ref.item)
  for i = 1, 4 do
    local mv = mon.moves[i]
    chk("move" .. i, mv and moveIndex(version, mv.id) or 0, ref.moves[i])
    chk("pp" .. i, mv and ((mv.ppUps or 0) * 64 + mv.pp) or 0, ref.pp[i])
  end
  chk("otId", mon.otId, ref.otId)
  chk("exp", mon.experience, ref.exp)
  local se = mon.statExp
  chk("statExp", table.concat({ se.hp, se.attack, se.defense, se.speed, se.special }, ","), table.concat(ref.statExp, ","))
  local d = mon.dvs
  if mon.shiny then
    chk("shiny dvs", true, ref.dvDef == 10 and ref.dvSpe == 10 and ref.dvSpc == 10 and (ref.dvAtk % 4 >= 2))
  else
    chk("dvs", table.concat({ d.attack, d.defense, d.speed, d.special }, ","),
      table.concat({ ref.dvAtk, ref.dvDef, ref.dvSpe, ref.dvSpc }, ","))
  end
  chk("friendship", mon.isEgg and mon.eggSteps or mon.happiness, ref.friendship)
  chk("pokerus", mon.pokerus or 0, ref.pokerus)
  chk("level", mon.level, ref.level)
  chk("ot", mon.ot, ref.ot)
  local nick = mon.nickname
  if not nick or nick == "" then nick = mon.isEgg and "EGG" or mon.name end
  chk("nick", nick, ref.nick)
  if version == "crystal" then
    local b0 = (mon.caughtTime % 4) * 64 + mon.caughtLevel % 64
    local b1 = (mon.caughtByGender == "girl" and 128 or 0) + mon.caughtLocation % 128
    chk("caught", b0 * 256 + b1, ref.caught)
  end
  if party then
    chk("status", statusByte(mon), ref.status)
    chk("hp", mon.hp, ref.hp)
    chk("maxHp", mon.maxHp, ref.maxHp)
    local st = mon.stats
    chk("stats", table.concat({ st.attack, st.defense, st.speed, st.specialAttack, st.specialDefense }, ","),
      table.concat(ref.stats, ","))
  end
end

local PROJECT = { "rival", "mom", "currentBox", "pokedex", "unownDex", "firstUnownSeen", "events",
                  "mapScenes", "engineFlags", "boxNames", "variableSprites", "playerState", "options", "playTime" }

local function flat(v, path, out)
  if type(v) ~= "table" then out[path] = tostring(v) return end
  local any = false
  for k, x in pairs(v) do
    any = true
    flat(x, path .. (type(k) == "number" and ("[" .. k .. "]") or ("." .. tostring(k))), out)
  end
  if not any then out[path] = "{}" end
end

local function project(save)
  local out = {}
  for _, root in ipairs(PROJECT) do if save[root] ~= nil then flat(save[root], root, out) end end
  return out
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local bad = 0
  stats.saves, stats.mons, stats.eggs, stats.forced = 0, 0, 0, 0
  for n = 1, N do
    local save = buildSave(version)
    local tag = ("%s seed %d"):format(version, n)
    local out, err = Gen2Save.encode(save, version, nil, DATA[version])
    local fails = {}
    if not out then
      fails[#fails + 1] = "export refused: " .. tostring(err)
    else
      stats.saves = stats.saves + 1
      local dumpDir = os.getenv("SAVE_COMPAT_ENGINE_DUMP")
      if dumpDir and n <= (tonumber(os.getenv("SAVE_COMPAT_ENGINE_DUMP_N")) or 8) then
        local f = io.open(("%s/gen2.%s.engine%03d.sav"):format(dumpDir, version, n), "wb")
        if f then f:write(out) f:close() end
        local function arr(list) return "[" .. table.concat(list, ",") .. "]" end
        local function str(v) return '"' .. tostring(v) .. '"' end
        local mdef = DATA[version].maps[save.position.map]
        local parts = {}
        for i, mon in ipairs(save.party) do
          local mv, pp = {}, {}
          for k = 1, 4 do
            local m = mon.moves[k]
            mv[k] = m and moveIndex(version, m.id) or 0
            pp[k] = m and ((m.ppUps or 0) * 64 + m.pp) or 0
          end
          parts[i] = ("{\"species\":%d,\"item\":%d,\"moves\":%s,\"pp\":%s,\"level\":%d,\"status\":%d,\"hp\":%d,\"max_hp\":%d,\"listed\":%d}")
            :format(speciesIndex(version, mon.species), mon.item and itemIndex(version, mon.item) or 0, arr(mv), arr(pp),
              mon.level, statusByte(mon), mon.hp, mon.maxHp, mon.isEgg and 0xFD or speciesIndex(version, mon.species))
        end
        local counts, names = {}, {}
        for b = 1, 14 do counts[b] = #save.boxes[b]; names[b] = str(save.boxNames[b]) end
        local f2 = io.open(("%s/gen2.%s.engine%03d.expect.json"):format(dumpDir, version, n), "wb")
        if f2 then
          f2:write(("{\"player_name\":%s,\"player_id\":%d,\"money\":%d,\"party_count\":%d,\"party\":[%s],\"cur_box\":%d,"
            .. "\"box_names\":%s,\"map_group\":%d,\"map_number\":%d,\"x\":%d,\"y\":%d,\"sram_box_counts\":%s,"
            .. "\"sram_cur_box_count\":%d}"):format(str(save.player.name), save.player.id, save.player.money, #save.party,
            table.concat(parts, ","), save.currentBox - 1, "[" .. table.concat(names, ",") .. "]", mdef.group, mdef.map,
            save.position.x, save.position.y, arr(counts), #save.boxes[save.currentBox]))
          f2:close()
        end
      end
      local report = Compat.check(out, version)
      if #report.errors > 0 then fails[#fails + 1] = "compat: " .. Compat.describe(report) end
      local ref = Ref.decode(out, version)
      if not (ref.checksum1 and ref.checksum2) then fails[#fails + 1] = "reference checksum" end
      for i, mon in ipairs(save.party) do
        stats.mons = stats.mons + 1
        if mon.isEgg then stats.eggs = stats.eggs + 1 end
        compareMon(("party%d"):format(i), version, mon, ref.party.mons[i] or {}, true, fails)
      end
      eq(ref.party.count, #save.party, tag .. ": party count")
      eq(ref.id, save.player.id, tag .. ": trainer id")
      eq(ref.name, save.player.name, tag .. ": player name")
      eq(ref.rival, save.rival.name, tag .. ": rival name")
      eq(ref.money, save.player.money, tag .. ": money")
      eq(ref.coins, save.player.coins, tag .. ": coins")
      eq(ref.hours, save.playTime.hours, tag .. ": play hours")
      eq(ref.minutes, save.playTime.minutes, tag .. ": play minutes")
      eq(ref.curBox, save.currentBox, tag .. ": current box")
      for b = 1, 14 do
        if ref.boxes[b].count ~= #save.boxes[b] then fails[#fails + 1] = ("box%d count"):format(b) end
        for i, mon in ipairs(save.boxes[b]) do
          stats.mons = stats.mons + 1
          compareMon(("box%d.%d"):format(b, i), version, mon, ref.boxes[b].mons[i] or {}, false, fails)
        end
        if ref.boxNames[b] ~= save.boxNames[b] then fails[#fails + 1] = ("boxName%d"):format(b) end
      end
      for i = 0, 255 do
        if ref.events[i] ~= save.events[i] then fails[#fails + 1] = ("event byte %d"):format(i) break end
      end
      local back, derr = Gen2Save.decode(out, version, DATA[version])
      if not back then
        fails[#fails + 1] = "reimport: " .. tostring(derr)
      else
        eq(back.player.name, save.player.name, tag .. ": player name reimports")
        eq(back.player.money, save.player.money, tag .. ": money reimports")
        local want, got = project(save), project(back)
        for path, value in pairs(want) do
          if got[path] ~= value then
            fails[#fails + 1] = ("field %s: %s -> %s"):format(path, value, tostring(got[path]))
            break
          end
        end
        eq(back.position.map, save.position.map, tag .. ": the map comes back by name")
        eq(back.position.x, save.position.x, tag .. ": x")
        eq(back.position.y, save.position.y, tag .. ": y")
        for id, qty in pairs(save.inventory) do
          if back.inventory[id] ~= qty then fails[#fails + 1] = ("bag %s: %s -> %s"):format(id, qty, tostring(back.inventory[id])) break end
        end
        for id, qty in pairs(save.pcItems) do
          if back.pcItems[id] ~= qty then fails[#fails + 1] = ("pc %s"):format(id) break end
        end
        for i, mon in ipairs(save.party) do
          local bm = back.party[i]
          if (bm.status or "") ~= ((mon.status == "toxic" and "poison") or mon.status or "") then
            fails[#fails + 1] = ("party%d status came back %s"):format(i, tostring(bm.status))
          end
        end
        for i, entry in pairs(save.mail.party) do
          local be = back.mail.party[i]
          if not be or be.message ~= entry.message or be.author ~= entry.author or be.authorId ~= entry.authorId
              or be.species ~= entry.species then
            fails[#fails + 1] = ("party mail %d"):format(i)
          end
        end
        for i, entry in ipairs(save.mail.box) do
          local be = back.mail.box[i]
          if not be or be.message ~= entry.message or be.author ~= entry.author then fails[#fails + 1] = ("box mail %d"):format(i) end
        end
        local again, aerr = Gen2Save.encode(back, version, nil, DATA[version])
        if again ~= out then
          fails[#fails + 1] = "not a fixed point: " .. (again and Diff.format(Diff.diff(out, again, Diff.regionsFor(2, version)), 4) or tostring(aerr))
        end
        local templated, terr = Gen2Save.encode(back, version, out, DATA[version])
        if templated ~= out then
          fails[#fails + 1] = "templated export differs: " .. (templated and Diff.format(Diff.diff(out, templated, Diff.regionsFor(2, version)), 4) or tostring(terr))
        end
      end
    end
    if #fails > 0 then
      bad = bad + 1
      if bad <= 4 then check(false, tag .. ": " .. table.concat(fails, "; ", 1, math.min(#fails, 6))) end
    end
  end
  eq(bad, 0, ("%s: %d engine-built saves (%d mons, %d eggs, %d forced shiny) export, decode independently, reimport and reach a fixed point")
    :format(version, N, stats.mons, stats.eggs, stats.forced))
end

T.finish()
