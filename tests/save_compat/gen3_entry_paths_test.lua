package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local K = require("tests.save_compat._codec")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")
local Gen3Save = require("src.save_convert.Gen3Save")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveFileIO = require("src.import.SaveFileIO")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local fixtures = {}
for _, c in ipairs(G3.cases()) do fixtures[c.id] = c end

local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
end

local realFs = love.filesystem
local function freshFs(version)
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set(version)
  return files
end

local function rsImage(version)
  local w = G3.base("emerald")
  for i = 0x890, w.sb2.size - 1 do w.sb2[i] = 0 end
  for i = 0x3AC0, w.sb1.size - 1 do w.sb1[i] = 0 end
  return G3.emit(w)
end

local function withMons(version, metGame, matchOwner)
  local w = G3.base(version)
  local tid, sid = B.getLE(w.sb2, 0x0A, 2), B.getLE(w.sb2, 0x0C, 2)
  local list = {}
  for i = 1, 3 do
    list[i] = G3.mon({
      pid = 0x01010101 * i, tid = matchOwner and tid or (tid + 1) % 65536, sid = matchOwner and sid or (sid + 1) % 65536,
      origins = 5 + metGame * 128 + 4 * 2048, species = 4 + i, nick = "M" .. i,
    })
  end
  B.fill(w.storage, 4, 14 * 30 * 80, 0)
  G3.setParty(w, list)
  return G3.emit(w)
end

local function importAs(bytes, version)
  return SaveConvert.importSav(bytes, version, version)
end

for _, cfg in ipairs({
  { version = "firered", met = 4, want = "firered" },
  { version = "firered", met = 5, want = "leafgreen" },
  { version = "leafgreen", met = 4, want = "firered" },
  { version = "leafgreen", met = 5, want = "leafgreen" },
}) do
  local bytes = withMons(cfg.version, cfg.met, true)
  local s = assert(importAs(bytes, cfg.version))
  eq(s.modData.cartGame, cfg.want, ("%s slot of a cart whose own mons were met in game %d is marked %s"):format(cfg.version, cfg.met, cfg.want))
  local traded = withMons(cfg.version, cfg.met == 4 and 5 or 4, false)
  local s2 = assert(importAs(traded, cfg.version))
  eq(s2.modData.cartGame, cfg.version, cfg.version .. ": mons the player did not catch never decide the marking")
  local fresh = assert(importAs(fixtures["g3." .. cfg.version .. ".basic"].bytes, cfg.version))
  check(fresh.modData.cartGame == "firered" or fresh.modData.cartGame == "leafgreen",
    cfg.version .. ": a cart without own mons is still marked FireRed or LeafGreen (" .. tostring(fresh.modData.cartGame) .. ")")
end
do
  local s = assert(importAs(fixtures["g3.emerald.basic"].bytes, "emerald"))
  eq(s.modData.cartGame, "emerald", "an Emerald slot is marked Emerald")
end

local variants = { { "synthetic RS-shaped image", rsImage() } }
local f = io.open(".claude/skills/pygba-headless/assets/pokemon-ruby.sav", "rb")
if f then
  variants[#variants + 1] = { "real Ruby save", f:read("*a") }
  f:close()
else
  print("[skip] real Ruby save not present")
end

for _, var in ipairs(variants) do
  local label, bytes = var[1], var[2]
  eq(Gen3Save.sniff(bytes), "rs", label .. " sniffs as Ruby/Sapphire")
  for _, v in ipairs({ "firered", "leafgreen", "emerald" }) do
    local s, err = SaveConvert.importSav(bytes, v, v)
    eq(s, nil, ("%s refused by importSav for %s"):format(label, v))
    check(type(err) == "string" and err:find("Ruby/Sapphire", 1, true) ~= nil,
      ("%s: importSav for %s names Ruby/Sapphire (%s)"):format(label, v, tostring(err)))
  end
  for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
    local ok, why = SaveConvert.mainChecksumValid(bytes, v)
    check(ok == nil and type(why) == "string" and why:find("Ruby/Sapphire", 1, true) ~= nil,
      ("%s: the %s launcher check names Ruby/Sapphire (%s)"):format(label, v, tostring(why)))
  end
  for _, v in ipairs({ "firered", "leafgreen", "emerald", "red", "gold" }) do
    local files = freshFs(v)
    files["picked.sav"] = bytes
    local ok, slotOrErr = SaveFileIO.importToSlot("picked.sav", v)
    eq(ok, false, ("%s: SaveFileIO refuses it for %s"):format(label, v))
    check(type(slotOrErr) == "string" and slotOrErr:find("Ruby/Sapphire", 1, true) ~= nil,
      ("%s: SaveFileIO message for %s names Ruby/Sapphire (%s)"):format(label, v, tostring(slotOrErr)))
    local created = false
    for path in pairs(files) do if path:find("^saves/") then created = true end end
    check(not created, ("%s: SaveFileIO leaves no slot behind for %s"):format(label, v))
  end
end

do
  local dir = os.getenv("TMPDIR") or "/tmp"
  local src = ("%s/pokeport-entry-paths-%d.sav"):format(dir:gsub("/$", ""), os.time())
  local out = src .. ".lua"
  local fh = assert(io.open(src, "wb"))
  fh:write(variants[1][2])
  fh:close()
  local cmd = ("luajit tools/save_convert/convert.lua import '%s' '%s' red >/dev/null 2>&1"):format(src, out)
  local rc = os.execute(cmd)
  check(rc ~= 0 and rc ~= true, "tools/save_convert/convert.lua refuses a Ruby/Sapphire image")
  local produced = io.open(out, "rb")
  check(produced == nil, "the CLI writes nothing for a Ruby/Sapphire image")
  if produced then produced:close() end
  os.remove(src)
  os.remove(out)
end

do
  local files = freshFs("firered")
  files["picked.sav"] = withMons("firered", 5, true)
  local ok, slot = SaveFileIO.importToSlot("picked.sav", "firered")
  check(ok == true, "SaveFileIO imports a LeafGreen-origin cart into the FireRed game")
  local save = ok and SaveData.load("firered")
  eq(save and save.modData.cartGame, "leafgreen", "the stored slot keeps the cart's LeafGreen marking")
  eq(save and save.version, "firered", "the slot belongs to the game it was imported into")
end

love.filesystem = realFs
T.finish()
