package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = os.getenv("POKEPORT_POKEEMERALD") or "../pokeemerald"
local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or (PRET .. "/pokeemerald.gba")
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_scripts_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local rom = { md5 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7", size = #data }
function rom:get(o) return data:byte(o + 1) end
function rom:u16(o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom:u32(o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom:readString(o, n) return data:sub(o + 1, o + n) end
function rom:readBytes(o, n)
  local t = {}
  for i = 1, n do t[i] = data:byte(o + i) end
  return t
end
function rom:ptrOffset(p)
  if not p or p < 0x08000000 or p >= 0x0A000000 then return nil end
  return p - 0x08000000
end

local files = {}
local cache = {
  write = function(_, rel, s) files[rel] = s; return true end,
  read = function(_, rel) return files[rel] end,
  exists = function(_, rel) return files[rel] ~= nil end,
}
local function load_file(rel)
  local src = assert(files[rel], rel .. " was not written")
  return assert(load(src, "@" .. rel, "t", {}))()
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local Versions = require("src.import.gba.versions")
Versions.select("emerald")
local S = Versions.SYMS
local Opcodes = require("src.core.game3.scripting.opcodes")
local TextIR = require("src.core.game3.scripting.text_ir")
local ExtractScripts = require("src.import.gba.extract_scripts")
local MovementEmerald = require("src.import.gba.movement_emerald")
local Constants = require("src.core.game3.constants")

eq(Opcodes.active().game, "emerald", "BFS runs on the emerald opcode table")

local ROOT = "data/generated/gba"
local res = ExtractScripts.run(rom, cache, { cacheRoot = ROOT })
eq(res.maps, 518, "every Emerald map header seeds the BFS")
eq(res.unknownOps, 0, "0 unknown opcodes across all Emerald seeds")
eq(res.unknownMoves, 0, "0 untranslated movement bytes")
check(res.seedCount > 10000, "seed count covers map events, std scripts and script labels (" .. res.seedCount .. ")")
check(res.scriptCount > 7500, "script count " .. res.scriptCount)
check(res.stoppedAtData >= 5, "scripts ending in warp+waitstate stop at the next data label")

for _, rel in ipairs(ExtractScripts.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "wrote " .. rel)
end
check(ExtractScripts.ready(cache, ROOT), "step ready after run")
check(files[ROOT .. "/flags_table.lua"] == nil, "no FireRed flags table in the Emerald cache")

local scripts = load_file(ROOT .. "/scripts/scripts.lua")
local text = load_file(ROOT .. "/scripts/text.lua")
local movements = load_file(ROOT .. "/scripts/movements.lua")
local events = load_file(ROOT .. "/scripts/events.lua")
local labels = load_file(ROOT .. "/scripts/labels.lua")
local meta = files[ROOT .. "/scripts/meta.json"]
check(meta:find('"movement":"canonical"', 1, true) ~= nil, "meta marks canonical movement")
check(meta:find('"cache_version":' .. Versions.CACHE_VERSION, 1, true) ~= nil, "meta carries the Emerald cache stamp")

local unknownRows, opaque, total = 0, 0, 0
for _, rows in pairs(scripts) do
  for _, row in ipairs(rows) do
    total = total + 1
    if row.op == "unknown" then unknownRows = unknownRows + 1 end
    if row.op == "trainerbattle" and row.opaque then opaque = opaque + 1 end
  end
end
eq(unknownRows, 0, "no unknown rows in scripts.lua")
eq(opaque, 0, "no opaque trainerbattle rows")
check(total > 60000, "row count " .. total)

for i = 0, Versions.STD_SCRIPTS_COUNT - 1 do
  check(type(scripts["std:" .. i]) == "table", "std:" .. i .. " aliased")
end
eq(Versions.STD_SCRIPTS_COUNT, 11, "Emerald has 11 std scripts")
for name in pairs(Versions.NAMED_SCRIPTS) do
  check(type(scripts[name]) == "table", name .. " aliased")
  eq(labels[name], Opcodes.key(S.addr(name)), name .. " label key")
end

local nLabels = 0
for name, key in pairs(labels) do
  nLabels = nLabels + 1
  if S.has(name) and Opcodes.key(S.addr(name)) ~= key then
    check(false, "label " .. name .. " key mismatch")
  end
end
check(nLabels > 7000, "labels index " .. nLabels .. " script symbols")
check(labels.LittlerootTown_EventScript_TownSign ~= nil, "Littleroot sign script label")

local nMaps, missing = 0, 0
for mapId, ev in pairs(events) do
  nMaps = nMaps + 1
  for _, o in ipairs(ev.objects or {}) do
    if o.scriptKey and not scripts[o.scriptKey] then missing = missing + 1 end
  end
  for _, b in ipairs(ev.bgEvents or {}) do
    if b.scriptKey and b.scriptPtr and not scripts[b.scriptKey] then missing = missing + 1 end
  end
  for _, c in ipairs(ev.coordEvents or {}) do
    if c.scriptKey and not scripts[c.scriptKey] then missing = missing + 1 end
  end
end
eq(nMaps, 518, "events for every map")
eq(missing, 0, "every event script was extracted")
check(events.EM_LITTLEROOT_TOWN ~= nil, "events keyed by EM_ engine id")

local sign = labels.LittlerootTown_EventScript_TownSign and scripts[labels.LittlerootTown_EventScript_TownSign]
local signText
for _, row in ipairs(sign or {}) do
  if row.op == "loadword" and type(row.value) == "string" then signText = text[row.value] end
end
check(signText ~= nil, "Littleroot sign text extracted")
if signText then
  local plain = TextIR.toPlain(signText)
  check(plain:find("LITTLEROOT TOWN", 1, true) ~= nil, "sign text decodes: " .. plain)
end

local em = Constants.of("emerald").movement.byId.MOVEMENT_ACTION_
local mv = MovementEmerald.forGame("emerald")
local nMoves, badEnd, nonCanon, applyMissing = 0, 0, 0, 0
for _, stream in pairs(movements) do
  nMoves = nMoves + 1
  if stream[#stream] ~= mv.stepEnd then badEnd = badEnd + 1 end
  for _, v in ipairs(stream) do
    if not MovementEmerald.nameOf(v) then nonCanon = nonCanon + 1 end
  end
end
for _, rows in pairs(scripts) do
  for _, row in ipairs(rows) do
    if (row.op == "applymovement" or row.op == "applymovementat") and not movements[row.movement] then
      applyMissing = applyMissing + 1
    end
  end
end
check(nMoves > 900, "movement streams " .. nMoves)
eq(badEnd, 0, "every movement stream ends with step_end")
eq(nonCanon, 0, "every stored movement value is a canonical action")
eq(applyMissing, 0, "every applymovement target was extracted")

-- pokeemerald/data/maps/LittlerootTown/scripts.inc:163
local probe = "LittlerootTown_Movement_MomExitHouse"
if S.has(probe) then
  local key = Opcodes.key(S.addr(probe))
  local stream = movements[key]
  check(stream ~= nil, probe .. " extracted")
  local off = S.off(probe)
  for i, v in ipairs(stream or {}) do
    local raw = data:byte(off + i)
    eq(MovementEmerald.nameOf(v), em[raw], probe .. " byte " .. i .. " keeps its action name")
  end
end

local dialogs = load_file(ROOT .. "/trainers/dialogs.lua")
local nd = 0
for _ in pairs(dialogs) do nd = nd + 1 end
check(nd > 500, "trainer dialogs indexed from scripts (" .. nd .. ")")

T.finish("emerald_scripts_test")
