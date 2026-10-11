package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Codec = require("src.save_convert.Gen3Save")
local Compat = require("src.save_convert.Compat")
local Gen = require("Gen")
local State, History = require("State"), require("History")
local Kit, Touch = require("Kit"), require("TouchEditor")
local Items = require("Items")
local ok, P = pcall(require, "PokeblockOps")
T.check(ok, "PokeblockOps module exists")
if not ok then T.finish("save_editor_pokeblocks_2788") return end

-- pokeemerald/include/global.h:1011; pokeruby/include/global.h:693
local OFFSET = { emerald = 0x848, ruby = 0x7F8, sapphire = 0x7F8 }
local PREFIX = { ruby = "RU_", sapphire = "SA_", emerald = "EM_" }

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
local function seed(v)
  local blocks = {}
  for i = 1, 40 do blocks[i] = { color = 0, spicy = 0, dry = 0, sweet = 0, bitter = 0, sour = 0, feel = 0 } end
  blocks[1] = { color = 1, spicy = 20, dry = 0, sweet = 0, bitter = 0, sour = 0, feel = 25 }
  return { version = v, generation = 3, map = PREFIX[v] .. "LITTLEROOT_TOWN", x = 5, y = 8,
    name = "BRENDAN", trainerId = 1234, secretId = 5678, gender = 0,
    money = 123456, coins = 4321, party = {}, pcItems = {}, boxes = {}, pokeblocks = blocks }
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
local function raw(v, out, slot)
  local sb1 = assert(Compat.gen3Blocks(out, v == "emerald" and "emerald" or "rs")).sb1
  local b = OFFSET[v] + (slot - 1) * 8
  return { sb1:byte(b + 1, b + 8) }
end

for _, v in ipairs({ "ruby", "sapphire", "emerald" }) do
  Version.set(v)
  local C = Codec.forVersion(v)
  local s = state(assert(C.importPort(export(v, seed(v)), v)), v)
  T.eq(P.count(s.save), 1, v .. " imports one block")
  T.eq(P.block(s.save, 1).feel, 25, v .. " imported feel")

  T.eq(P.add(s, nil, { color = 14, spicy = 1, dry = 2, sweet = 3, bitter = 4, sour = 5, feel = 99 }), true, v .. " add")
  T.eq(s.pokeblockSlot, 2, v .. " add selects first free slot")
  T.eq(P.set(s, 2, "sweet", 255), true, v .. " edit sweet")
  T.eq(P.set(s, 1, "color", 9), true, v .. " recolor")
  T.eq(P.clear(s, 1), true, v .. " delete")
  T.eq(P.add(s, 40, { color = 7 }), true, v .. " add at last slot")
  T.eq(#s.undoStack, 5, v .. " each edit records one undo")
  T.eq(s.dirty, true, v .. " dirty")

  local persisted = Serializer.decode(Serializer.encode(s.save))
  T.eq(P.block(persisted, 2).sweet, 255, v .. " Lua save keeps edit")
  local out = export(v, persisted)
  T.same(raw(v, out, 1), { 0, 0, 0, 0, 0, 0, 0, 0 }, v .. " deleted slot cleared on cart")
  T.same(raw(v, out, 2), { 14, 1, 2, 255, 4, 5, 99, 0 }, v .. " edited slot on cart")
  T.same(raw(v, out, 40), { 7, 0, 0, 0, 0, 0, 0, 0 }, v .. " last slot on cart")
  local back = assert(C.importPort(out, v))
  T.eq(P.count(back), 2, v .. " cart reimport count")
  T.eq(P.block(back, 2).sweet, 255, v .. " cart reimport keeps edit")

  for _ = 1, 5 do History.undo(s) end
  T.eq(P.count(s.save), 1, v .. " undo restores import")
  T.eq(P.block(s.save, 1).color, 1, v .. " undo restores color")
  T.eq(s.dirty, false, v .. " undo to initial is clean")
  History.redo(s)
  T.eq(P.count(s.save), 2, v .. " redo re-adds")

  local before = snapshot(s)
  for _, bad in ipairs({ { 2, "spicy", 256 }, { 2, "spicy", -1 }, { 2, "dry", 1.5 }, { 2, "feel", "x" },
    { 2, "color", 0 }, { 2, "color", 15 }, { 3, "spicy", 1 }, { 41, "spicy", 1 }, { 2, "nope", 1 } }) do
    T.eq(P.set(s, bad[1], bad[2], bad[3]), false, v .. " rejects " .. bad[2] .. "=" .. tostring(bad[3]))
  end
  T.eq(P.add(s, 1), false, v .. " rejects add on taken slot")
  T.eq(P.add(s, nil, { color = 0 }), false, v .. " rejects add of empty color")
  T.eq(P.clear(s, 3), false, v .. " rejects clearing empty slot")
  T.eq(P.set(s, 2, "spicy", P.block(s.save, 2).spicy), true, v .. " same value accepted")
  T.same(snapshot(s), before, v .. " rejections and no-ops leave save and history alone")

  for i = 1, 40 do if P.isEmpty(s.save, i) then P.add(s, i) end end
  T.eq(P.count(s.save), 40, v .. " case fills")
  T.eq(P.add(s), false, v .. " full case rejects add")
end

local seen
local realChoice = Touch.choice
Touch.choice = function(s, kit, id, ...)
  if id == "pokeblock-color" then seen = true end
  return realChoice(s, kit, id, ...)
end
local function views(s)
  local labels = {}
  local Chooser = require("Chooser")
  local real = Chooser.navigation
  Chooser.navigation = function(st, kit, key, title, options, ...)
    if key == "itemView" then for _, o in ipairs(options) do labels[o[1]] = true end end
    return real(st, kit, key, title, options, ...)
  end
  Kit.layout(720, 1400)
  Kit.blockClicks = false
  Kit.beginFrame(-1, -1, false, 0)
  Items.draw(s, Kit, 0, 0, 720, 1400)
  Kit.endFrame()
  Chooser.navigation = real
  return labels
end
for _, v in ipairs(Version.ORDER) do
  local info = assert(Version.info(v))
  Version.set(v)
  local eligible = info.layout == "rse"
  local s = state({ version = v, generation = info.generation, player = { name = "ASH" },
    pokeblocks = { { color = 3, spicy = 1, dry = 0, sweet = 0, bitter = 0, sour = 0, feel = 0 } } }, v)
  T.eq(P.has(s.save, v), eligible, v .. " edition gate")
  T.eq(views(s).pokeblocks == true, eligible, v .. " Items shows Pokéblocks view")
  local before = snapshot(s)
  T.eq(P.set(s, 1, "spicy", 9), eligible, v .. " operation gate")
  if not eligible then T.same(snapshot(s), before, v .. " unsupported save untouched") end
  if eligible then
    s.itemView, s.pokeblockSlot, seen = "pokeblocks", 1, false
    before = snapshot(s)
    views(s)
    T.eq(seen, true, v .. " panel draws the color editor")
    T.same(snapshot(s), before, v .. " drawing does not mutate")
  else
    s.itemView = "pokeblocks"
    views(s)
    T.eq(s.itemView, "bag", v .. " stale Pokéblocks view falls back to bag")
  end
end
Touch.choice = realChoice

local f = assert(io.open("tests/quick.list", "r"))
local quick = f:read("*a"); f:close()
T.check(quick:find("tests/engine/save_editor_pokeblocks_2788.lua", 1, true), "registered in quick suite")
Version.set("red")
T.finish("save_editor_pokeblocks_2788")
