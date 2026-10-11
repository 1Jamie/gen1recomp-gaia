package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Codec = require("src.save_convert.Gen3Save")
local Compat = require("src.save_convert.Compat")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Gen, Ops = require("Gen"), require("Ops")
local State, History = require("State"), require("History")
local Kit = require("Kit")
local Trainer = require("Trainer")
local RND_H, RND_L = 0x4024, 0x4025 -- pokeemerald/include/constants/vars.h:54
local PREFIX = { ruby = "RU_", sapphire = "SA_", emerald = "EM_" }
local PID = 0x89ABCDEF

local function state(save, version)
  local s = State.new()
  s.save, s.version = save, version
  s.save.pcItems = s.save.pcItems or {}
  Gen.ensureBoxes(s.save)
  return s
end
local function snapshot(s)
  return { bytes = Serializer.encode(s.save), dirty = s.dirty, revision = s.revision,
    token = s.historyToken, undo = #(s.undoStack or {}), redo = #(s.redoStack or {}) }
end
local function seed(v, party)
  return { version = v, generation = 3, map = PREFIX[v] .. "LITTLEROOT_TOWN", x = 5, y = 8,
    name = "BRENDAN", trainerId = 1234, secretId = 5678, gender = 0, money = 1000, coins = 0,
    vars = { [RND_H] = 0x1111, [RND_L] = 0x2222 }, party = party or {}, pcItems = {}, boxes = {} }
end
local function export(v, save)
  local bytes, err = Codec.forVersion(v).exportPort(save, {
    version = v, metGame = Version.gameCode(v), itemId = tonumber,
    toNational = function() return nil end,
    mapLayoutId = function() return 1 end,
    healWarp = function() return { group = 0, num = 9, warpId = -1, x = 5, y = 8 } end,
  })
  return assert(bytes, err)
end
local function gamePresent(v, save)
  Version.set(v)
  Space.store = Flags.newStore()
  Flags.loadInto(Space.store, { flags = save.flags, vars = save.vars })
  local present = require("src.core.game3.scripting.natives_field_rse").isMirageIslandPresent(save)
  Space.store = nil
  return present
end

T.check(type(Gen.hasMirageIsland) == "function", "Gen.hasMirageIsland exists")
T.check(type(Ops.setMirageIslandFromParty) == "function", "Ops.setMirageIslandFromParty exists")

for _, v in ipairs({ "ruby", "sapphire", "emerald" }) do
  Version.set(v)
  local mon = { species = 25, personality = PID, level = 5 }
  local s = state(seed(v, { { species = 0 }, mon }), v)
  T.eq(Gen.hasMirageIsland(s.save, v), true, v .. " edition gate")
  T.eq(Gen.mirageIslandValue(s.save, v), 0x1111, v .. " reads VAR_MIRAGE_RND_H")
  T.eq(Gen.mirageIslandVisible(s.save, v), false, v .. " hidden before edit")
  T.eq(gamePresent(v, s.save), false, v .. " game agrees island hidden")
  T.eq(Ops.setMirageIslandFromParty(s), true, v .. " appear button succeeds")
  T.eq(s.save.vars[RND_H], PID % 0x10000, v .. " high var takes first party PID low half")
  T.eq(s.save.vars[RND_L], 0x2222, v .. " low var untouched")
  T.eq(Gen.mirageIslandVisible(s.save, v), true, v .. " editor reports visible")
  T.eq(#s.undoStack, 1, v .. " one undo entry")
  T.eq(s.dirty, true, v .. " dirty")
  local persisted = Serializer.decode(Serializer.encode(s.save))
  T.eq(gamePresent(v, persisted), true, v .. " game sees Mirage Island after Lua save")
  local before = snapshot(s)
  T.eq(Ops.setMirageIslandFromParty(s), false, v .. " already visible is a no-op")
  T.same(snapshot(s), before, v .. " no-op adds no history")
  T.eq(History.undo(s), true, v .. " undo")
  T.eq(s.save.vars[RND_H], 0x1111, v .. " undo restores value")
  T.eq(History.redo(s), true, v .. " redo")
  T.eq(s.save.vars[RND_H], PID % 0x10000, v .. " redo reapplies")

  T.eq(Ops.setTrainerProperty(s, "mirageIsland", "4660"), true, v .. " typed value accepted")
  T.eq(s.save.vars[RND_H], 4660, v .. " typed value stored")
  T.eq(Gen.mirageIslandVisible(s.save, v), false, v .. " typed mismatch hides island")
  for _, bad in ipairs({ -1, 65536, 1.5, 0/0, "", "x", false }) do
    before = snapshot(s)
    T.eq(Ops.setTrainerProperty(s, "mirageIsland", bad), false, v .. " rejects " .. tostring(bad))
    T.same(snapshot(s), before, v .. " rejected value leaves save alone")
  end

  local empty = state(seed(v), v)
  before = snapshot(empty)
  T.eq(Ops.setMirageIslandFromParty(empty), false, v .. " empty party refused")
  T.same(snapshot(empty), before, v .. " empty party unchanged")

  local cartSave = seed(v)
  local baseline = export(v, cartSave)
  local es = state(Serializer.decode(Serializer.encode(cartSave)), v)
  T.eq(Ops.setTrainerProperty(es, "mirageIsland", 0xBEEF), true, v .. " set for export")
  local out = export(v, Serializer.decode(Serializer.encode(es.save)))
  local cart = assert(Codec.forVersion(v).decode(out))
  T.eq(cart.vars[RND_H], 0xBEEF, v .. " cart VAR_MIRAGE_RND_H")
  T.eq(cart.vars[RND_L], 0x2222, v .. " cart VAR_MIRAGE_RND_L unchanged")
  local family = v == "emerald" and "emerald" or "rs"
  local blocks = assert(Compat.gen3Blocks(out, family))
  local original = assert(Compat.gen3Blocks(baseline, family))
  local off = (v == "emerald" and 0x139C or 0x1340) + (RND_H - 0x4000) * 2
  T.eq(blocks.sb1:byte(off + 1) + blocks.sb1:byte(off + 2) * 256, 0xBEEF, v .. " raw cart word")
  local normalized = blocks.sb1:sub(1, off) .. original.sb1:sub(off + 1, off + 2) .. blocks.sb1:sub(off + 3)
  T.eq(normalized, original.sb1, v .. " other SaveBlock1 bytes preserved")
  T.eq(Gen.mirageIslandValue(assert(Codec.forVersion(v).importPort(out, v)), v), 0xBEEF, v .. " reimport keeps value")
end

local function panelText(s)
  local seen, realText, realButton = {}, Kit.text, Kit.button
  Kit.text = function(font, str, ...) seen[#seen + 1] = str; return realText(font, str, ...) end
  Kit.button = function(x, y, w, h, label, ...) seen[#seen + 1] = label; return realButton(x, y, w, h, label, ...) end
  Kit.layout(720, 1400)
  Kit.blockClicks = false
  Kit.beginFrame(-1, -1, false, 0)
  Trainer.draw(s, Kit, 0, 0, 720, 1400)
  Kit.endFrame()
  Kit.text, Kit.button = realText, realButton
  return table.concat(seen, "\n")
end
for _, v in ipairs(Version.ORDER) do
  local info = assert(Version.info(v))
  Version.set(v)
  local eligible = PREFIX[v] ~= nil
  local s = state({ version = v, generation = info.generation, player = { name = "ASH" },
    vars = { [RND_H] = PID % 0x10000 }, party = { { species = 25, personality = PID } } }, v)
  local before = snapshot(s)
  local text = panelText(s)
  T.eq(text:find("Make Mirage Island appear", 1, true) ~= nil, eligible, v .. " button gated")
  if eligible then T.check(text:find("Mirage Island: visible", 1, true), v .. " shows visible state") end
  T.same(snapshot(s), before, v .. " drawing does not mutate")
  T.eq(Ops.setMirageIslandFromParty(s), false, v .. " op refuses or no-ops")
  if not eligible then
    T.eq(Ops.setTrainerProperty(s, "mirageIsland", 1), false, v .. " value edit refused")
    T.same(snapshot(s), before, v .. " unsupported save not mutated")
  end
end

local f = assert(io.open("tests/quick.list", "r"))
local quick = f:read("*a"); f:close()
T.check(quick:find("tests/engine/save_editor_mirage_island_2811.lua", 1, true), "registered in quick suite")
Version.set("red")
T.finish("save_editor_mirage_island_2811")
