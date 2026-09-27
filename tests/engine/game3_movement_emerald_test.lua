package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Constants = require("src.core.game3.constants")
local MovementEmerald = require("src.import.gba.movement_emerald")
local ExtractScripts = require("src.import.gba.extract_scripts")
local OwExtract = require("src.import.gba.ow_extract")
local GameVersion = require("src.core.GameVersion")

local em = Constants.of("emerald")
local fr = Constants.of("firered")
local EM = em.movement.byId.MOVEMENT_ACTION_
local FR = fr.movement.byId.MOVEMENT_ACTION_

local M = MovementEmerald.forGame("emerald")
eq(M.game, "emerald", "table game")
eq(M.stepEnd, 0xFE, "emerald MOVEMENT_ACTION_STEP_END")

local emIds = 0
local frNames = {}
for id, name in pairs(FR) do frNames[name] = id end
local shared, rse, maxRse = 0, 0, 0
local seenCanon = {}
for raw, name in pairs(EM) do
  emIds = emIds + 1
  local v = M.toCanon[raw]
  check(v ~= nil, name .. " translates")
  eq(MovementEmerald.nameOf(v), name, name .. " round trips by name")
  check(not seenCanon[v], name .. " canonical id is unique")
  seenCanon[v] = true
  if frNames[name] then
    shared = shared + 1
    eq(v, fr:id("movement", name), name .. " keeps the FireRed number")
  else
    rse = rse + 1
    check(v >= MovementEmerald.RSE_BASE, name .. " is in the RSE-only range")
    if v > maxRse then maxRse = v end
  end
end
eq(emIds, 160, "every Emerald MOVEMENT_ACTION id covered")
eq(M.count, 160, "table count")
eq(rse, MovementEmerald.canon().rseCount, "RSE-only count")
eq(shared + rse, 160, "shared + RSE-only")
eq(maxRse, MovementEmerald.RSE_BASE + rse - 1, "RSE-only ids are dense from 0x100")

eq(M.toCanon[em:id("movement", "MOVEMENT_ACTION_WALK_NORMAL_DOWN")], 0x10, "EM walk_normal_down 0x08 -> FR 0x10")
eq(M.toCanon[em:id("movement", "MOVEMENT_ACTION_WALK_SLOW_DOWN")],
  fr:id("movement", "MOVEMENT_ACTION_WALK_SLOW_DOWN"), "EM walk_slow_down -> FR walk_slow_down")
eq(M.toCanon[0xFE], 0xFE, "step_end stays 0xFE")
eq(MovementEmerald.canonOf("MOVEMENT_ACTION_EMOTE_HEART"), MovementEmerald.RSE_BASE, "first RSE-only action")
eq(MovementEmerald.canonOf("MOVEMENT_ACTION_FIGURE_8"), MovementEmerald.RSE_BASE + rse - 1, "last RSE-only action")

local out, unknown = M.translate({ 0x08, 0x58, 0xFE })
eq(out[1], 0x10, "translate walk")
eq(out[2], MovementEmerald.canonOf("MOVEMENT_ACTION_EMOTE_HEART"), "translate emote heart")
eq(out[3], 0xFE, "translate end")
eq(unknown, nil, "no unknown bytes")
local _, bad = M.translate({ 0xF0, 0xFE })
eq(bad and bad[1], 0xF0, "undefined action byte reported")

check(ExtractScripts.movementTable("firered") == nil, "FireRed movement bytes are stored raw")
check(ExtractScripts.movementTable("leafgreen") == nil, "LeafGreen movement bytes are stored raw")
check(ExtractScripts.movementTable("emerald") == M, "Emerald movement bytes are translated")

local big = {}
for i = 1, 600 do big["g3:" .. string.format("%08x", i)] = { { op = "end", n = i } } end
local src = ExtractScripts.serializeChunked(big)
local back = assert(load(src, "@chunked", "t", {}))()
local n = 0
for k, v in pairs(back) do
  n = n + 1
  if v[1].n ~= tonumber(k:sub(4), 16) then check(false, "chunked value " .. k) end
end
eq(n, 600, "chunked serializer round trips every key")
eq(select(2, src:gsub("%(function%(T%)", "")), 3, "600 entries split into 3 chunks")

local bytes = {}
local function put(off, ...)
  for i, b in ipairs({ ... }) do bytes[off + i - 1] = b end
end
put(0, 0, 89, 1, 90, 63, 91, 2, 92, 111, 112, 3, 93, 137, 138, 191, 192)
put(16, 100, 105, 101, 106, 102, 107, 103, 108, 111, 112, 104, 109, 137, 138, 191, 192)
put(32, 230, 231, 235, 236)
put(36, 0, 1, 1, 2, 63, 4, 2, 8, 111, 16, 89, 1, 90, 2, 91, 4, 92, 8, 112, 16)
local fake = { get = function(_, o) return bytes[o] or 0 end }
local spec = {
  genders = 2,
  stateNames = { "NORMAL", "MACH_BIKE", "ACRO_BIKE", "SURFING", "UNDERWATER", "FIELD_MOVE", "FISHING", "WATERING" },
  player = 0, player_states = 8, rival = 16, rival_states = 8,
  link_frlg = 32, link_rs = 34, state_flags = 36, state_flag_count = 5,
}
local av = OwExtract.readAvatars(fake, spec)
eq(av.player[1].state, "NORMAL", "state name")
eq(av.player[3].male, 63, "acro bike male")
eq(av.player[8].female, 192, "watering female")
eq(av.rival[4].female, 108, "rival surfing female")
eq(av.linkRs.female, 236, "link RS female")
eq(av.stateFlags.female[5].gfx, 112, "female underwater state row")
eq(av.stateFlags.female[5].flag, 16, "underwater flag bit")

local prev = GameVersion.get()
GameVersion.set("firered")
eq(OwExtract.readAvatars(fake), nil, "FireRed has no avatar table key")
GameVersion.set(prev)

T.finish("game3_movement_emerald_test")
