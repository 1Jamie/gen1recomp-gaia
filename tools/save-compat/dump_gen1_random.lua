package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local Random = require("tests.save_compat._gen1_random")

local out, first, last = arg[1], tonumber(arg[2]) or 1, tonumber(arg[3]) or 12
if not out then
  io.stderr:write("usage: luajit tools/save-compat/dump_gen1_random.lua <dir> [first seed] [last seed]\n")
  os.exit(2)
end

local function json(v)
  if type(v) == "table" then
    if #v > 0 or next(v) == nil then
      local t = {}
      for i, x in ipairs(v) do t[i] = json(x) end
      return "[" .. table.concat(t, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local t = {}
    for _, k in ipairs(keys) do t[#t + 1] = ("%q:%s"):format(k, json(v[k])) end
    return "{" .. table.concat(t, ",") .. "}"
  end
  if type(v) == "string" then return ("%q"):format(v) end
  return tostring(v)
end

local versions = { "red", "blue", "yellow" }
local manifest = {}
for seed = first, last do
  local version = versions[(seed - 1) % 3 + 1]
  local data = Random.data(version)
  local cw = GenSave.crosswalks(data)
  local save = Random.build(seed, version)
  local bytes = assert(SaveConvert.exportSav(save, version))
  local file = ("g1_%03d_%s.sav"):format(seed, version)
  local f = assert(io.open(out .. "/" .. file, "wb"))
  f:write(bytes)
  f:close()
  local species, levels, hp = {}, {}, {}
  for i, mon in ipairs(save.party) do
    species[i], levels[i], hp[i] = cw.pokemonIndex[mon.species], mon.level, mon.hp
  end
  local heal = save.lastHeal
  local rolling = save.player.map:match("^ROUTE_1[678]$") ~= nil
  local badges = 0
  for i, id in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE",
      "VOLCANOBADGE", "EARTHBADGE" }) do
    if save.inventory[id] then badges = badges + 2 ^ (i - 1) end
  end
  local opts = save.options
  manifest[#manifest + 1] = {
    file = file, version = version, seed = seed,
    expect = {
      wCurMap = (not rolling) and cw.mapsIndex[save.player.map] or nil, wXCoord = (not rolling) and save.player.x or nil,
      wYCoord = (not rolling) and save.player.y or nil,
      money = save.money, badges = badges, playerId = save.player.id,
      options = opts.textSpeed + (opts.battleStyle == "set" and 0x40 or 0) + (opts.animations == false and 0x80 or 0),
      partyCount = #save.party, partySpecies = species, partyLevels = levels, partyHP = (not rolling) and hp or nil,
      lastBlackoutMap = cw.mapsIndex[(heal.outdoor and heal.outdoor.id) or heal.map],
      dayCareInUse = save.daycare and 1 or 0,
      numSafariBalls = save.safari and save.safari.balls or nil,
      safariSteps = save.safari and save.safari.steps or nil,
      trashCans = save.trashPuzzle and { save.trashPuzzle.first, save.trashPuzzle.second } or nil,
    },
  }
end
local f = assert(io.open(out .. "/manifest.json", "w"))
f:write(json(manifest))
f:close()
print(("wrote %d saves and manifest.json into %s"):format(#manifest, out))
