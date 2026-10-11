package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
_G.love = require("tests.love_stub")

local State = require("State")
local Gen = require("Gen")
local Ops = require("Ops")
local History = require("History")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end
local function eq(a, b, msg)
  check(a == b, msg .. (" (got %s, want %s)"):format(tostring(a), tostring(b)))
end

print("== save editor box sort tests ==")

local function layout(boxes, count, capacity, key)
  local out = {}
  for b = 1, count do
    for s = 1, capacity do
      local mon = boxes[b] and boxes[b][s]
      if mon then out[#out + 1] = ("%d:%d=%s%s"):format(b, s, tostring(mon[key or "species"]), mon.isEgg and "*" or "") end
    end
  end
  return table.concat(out, " ")
end

do
  local data = { pokemon = {
    BULBASAUR = { name = "BULBASAUR", dex = 1 },
    CHARMANDER = { name = "CHARMANDER", dex = 4 },
    PIKACHU = { name = "PIKACHU", dex = 25 },
    RHYDON = { name = "RHYDON", dex = 112 },
    MEW = { name = "MEW", dex = 151 },
  }, moves = {}, items = {}, maps = {} }
  local S = State.new()
  S.data, S.version, S.save = data, "red", SaveData.newGame()
  local boxes = Ops.boxes(S)
  eq(Ops.boxCount(S), 12, "gen1 box count")
  eq(Ops.boxCapacity(S), 20, "gen1 box size")
  local function mon(species, level) return { species = species, level = level } end
  boxes[1][1], boxes[1][2] = mon("PIKACHU", 10), mon("RHYDON", 5)
  boxes[2][1] = mon("GLITCH", 3)
  boxes[3][1], boxes[3][2], boxes[3][3] = mon("BULBASAUR", 7), mon("PIKACHU", 30), mon("MEW", 50)
  boxes[12][1] = mon("CHARMANDER", 20)
  S.save.currentBox, S.selectedBox = 3, 3
  local current = boxes[3]
  check(Ops.setBoxOrder(S, "livingdex"), "gen1 living dex sort applies")
  eq(layout(boxes, 12, 20),
    "1:1=BULBASAUR 1:2=CHARMANDER 1:3=PIKACHU 1:4=RHYDON 1:5=MEW 1:6=PIKACHU 1:7=GLITCH",
    "gen1 living dex packs one of each by dex number, then duplicates, then unknown species")
  eq(boxes[1][3].level, 10, "gen1 living dex keeps the first copy in the dex slot")
  check(boxes[3] == current and #boxes[3] == 0, "gen1 stored current box stays the same list and is emptied")
  eq(S.save.currentBox, 3, "gen1 sort leaves the current box number alone")
  check(S.dirty and #S.undoStack == 1, "gen1 sort is one undoable edit")
  local back = SaveData.decode(SaveData.encode(S.save))
  eq(layout(back.boxes, 12, 20), layout(boxes, 12, 20), "gen1 sorted order survives the Lua save")
  check(not Ops.setBoxOrder(S, "livingdex") and #S.undoStack == 1, "gen1 re-sort is a no-op without history")
  check(Ops.setBoxOrder(S, "level"), "gen1 level sort applies")
  eq(layout(Ops.boxes(S), 12, 20),
    "1:1=MEW 1:2=PIKACHU 1:3=CHARMANDER 1:4=PIKACHU 1:5=BULBASAUR 1:6=RHYDON 1:7=GLITCH",
    "gen1 level sort runs high to low")
  check(History.undo(S), "gen1 undo")
  eq(layout(Ops.boxes(S), 12, 20),
    "1:1=BULBASAUR 1:2=CHARMANDER 1:3=PIKACHU 1:4=RHYDON 1:5=MEW 1:6=PIKACHU 1:7=GLITCH",
    "gen1 undo restores the previous order")
  check(History.undo(S), "gen1 second undo")
  eq(layout(Ops.boxes(S), 12, 20),
    "1:1=PIKACHU 1:2=RHYDON 2:1=GLITCH 3:1=BULBASAUR 3:2=PIKACHU 3:3=MEW 12:1=CHARMANDER",
    "gen1 undo restores the original boxes")
  check(History.redo(S), "gen1 redo")
  eq(Ops.boxes(S)[1][1].species, "BULBASAUR", "gen1 redo replays the sort")

  local S2 = State.new()
  S2.data, S2.version, S2.save = data, "red", SaveData.newGame()
  local b2 = Ops.boxes(S2)
  for i = 1, 20 do b2[1][i] = mon("MEW", i) end
  for i = 1, 5 do b2[2][i] = mon("BULBASAUR", i) end
  check(Ops.setBoxOrder(S2, "species"), "gen1 species sort applies")
  eq(#b2[1], 20, "gen1 sort fills box 1 to capacity")
  eq(#b2[2], 5, "gen1 sort spills into box 2")
  check(b2[1][1].species == "BULBASAUR" and b2[1][1].level == 5 and b2[1][5].level == 1,
    "gen1 species sort orders level high to low within a species")
  eq(b2[1][6].species .. b2[1][6].level, "MEW20", "gen1 species sort follows with the next dex number")
end

do
  local Save2 = require("src.core.gen2.Save")
  local prior = GameVersion.get()
  GameVersion.set("gold")
  local data = { pokemon = {
    CHIKORITA = { name = "CHIKORITA", dex = 152 },
    TOTODILE = { name = "TOTODILE", dex = 158 },
    PICHU = { name = "PICHU", dex = 172 },
    TOGEPI = { name = "TOGEPI", dex = 175 },
    LUGIA = { name = "LUGIA", dex = 249 },
  }, moves = {}, items = {}, maps = {} }
  local S = State.new()
  S.data, S.version, S.save = data, "gold", Save2.newGame()
  local boxes = Ops.boxes(S)
  eq(Ops.boxCount(S), 14, "gen2 box count")
  eq(Ops.boxCapacity(S), 20, "gen2 box size")
  boxes[1][1] = { species = "TOGEPI", level = 5, isEgg = true }
  boxes[1][2] = { species = "LUGIA", level = 40 }
  boxes[2][1] = { species = "PICHU", level = 5, isEgg = true }
  boxes[2][2] = { species = "TOTODILE", level = 18 }
  boxes[5][1] = { species = "CHIKORITA", level = 9 }
  boxes[5][2] = { species = "PICHU", level = 12 }
  S.save.currentBox, S.selectedBox = 5, 5
  check(Ops.setBoxOrder(S, "livingdex"), "gen2 living dex sort applies")
  eq(layout(boxes, 14, 20),
    "1:1=CHIKORITA 1:2=TOTODILE 1:3=PICHU 1:4=LUGIA 1:5=TOGEPI* 1:6=PICHU*",
    "gen2 living dex sorts eggs to the end in their old order")
  eq(#boxes[5], 0, "gen2 current box list is emptied in place")
  local back = SaveData.decode(SaveData.encode(S.save))
  eq(layout(back.boxes, 14, 20), layout(boxes, 14, 20), "gen2 sorted order survives the Lua save")
  check(History.undo(S) and Ops.boxes(S)[5][1].species == "CHIKORITA", "gen2 undo restores the current box")
  GameVersion.set(prior)
end

do
  local Schema = require("src.core.game3.save_schema_firered")
  local data = { pokemon = {
    [1] = { name = "BULBASAUR", dex = 1 },
    [25] = { name = "PIKACHU", dex = 25 },
    [277] = { name = "TREECKO", dex = 252 },
    [313] = { name = "WAILMER", dex = 320 },
    [315] = { name = "SKITTY", dex = 300 },
    [410] = { name = "DEOXYS", dex = 386 },
  }, moves = {}, items = {}, maps = {} }
  local S = State.new()
  S.data, S.version, S.save = data, "firered", Schema.newGame({ version = "firered" })
  local boxes = Ops.boxes(S)
  eq(Ops.boxCount(S), 14, "gen3 box count")
  eq(Ops.boxCapacity(S), 30, "gen3 box size")
  boxes[1][4] = { species = 313, level = 20 }
  boxes[1][9] = { species = 410, level = 30 }
  boxes[2][30] = { species = 315, level = 8 }
  boxes[4][2] = { species = 25, level = 15, isEgg = true }
  boxes[7][7] = { species = 277, level = 5 }
  boxes[14][30] = { species = 1, level = 12 }
  boxes[14][1] = { species = 25, level = 40 }
  boxes[3][3] = { species = 1, level = 3 }
  check(Ops.setBoxOrder(S, "species"), "gen3 species sort applies")
  boxes = S.save.boxes
  eq(layout(boxes, 14, 30),
    "1:1=1 1:2=1 1:3=25 1:4=277 1:5=315 1:6=313 1:7=410 1:8=25*",
    "gen3 species sort uses National Dex order, not internal species order")
  eq(boxes[1][1].level, 12, "gen3 duplicate species sort by level")
  check(S.save.storage.boxes[1].mons == boxes[1], "gen3 native storage box is the sorted table")
  check(History.undo(S), "gen3 undo")
  check(Ops.setBoxOrder(S, "livingdex"), "gen3 living dex sort applies")
  boxes = S.save.boxes
  eq(layout(boxes, 14, 30),
    "1:1=1 1:25=25 9:12=277 10:30=315 11:20=313 13:26=410 13:27=1 13:28=25*",
    "gen3 living dex puts each species in its National Dex slot, duplicates and eggs after")
  local back = SaveData.decode(SaveData.encode(S.save))
  eq(back.storage.boxes[9].mons[12].species, 277, "gen3 living dex slot survives the Lua save")
  eq(back.storage.boxes[13].mons[28].isEgg, true, "gen3 egg slot survives the Lua save")
  check(Ops.setBoxOrder(S, "compact"), "gen3 compact applies")
  eq(layout(Ops.boxes(S), 14, 30),
    "1:1=1 1:2=25 1:3=277 1:4=315 1:5=313 1:6=410 1:7=1 1:8=25*",
    "gen3 compact keeps order and removes gaps")
end

if failed > 0 then
  print(("save editor box sort tests: %d passed, %d failed"):format(passed, failed))
  os.exit(1)
end

local SaveConvert = require("src.save_convert.SaveConvert")

local function cartRoundTrip(version, S)
  local bytes, err = SaveConvert.exportSav(S.save, version)
  check(bytes ~= nil, version .. " .sav export: " .. tostring(err))
  if not bytes then return nil end
  local back, why = SaveConvert.importSav(bytes, version, version)
  check(back ~= nil, version .. " .sav import: " .. tostring(why))
  return back
end

local dataDir = os.getenv("POKEPORT_DATA_DIR")
local redRoot = dataDir and dataDir:match("^(.*)/data/generated/?$")
if not redRoot and io.open("data/generated/maps.lua", "rb") then redRoot = "." end
local redStub = redRoot and SaveConvert.gen1DataFromDir(redRoot)
local okRed, redData = false, nil
if redStub then
  okRed = pcall(function() redData = require("src.core.Data"); redData:load() end)
end
if okRed and redData.pokemon and redData.pokemon.MEW and redData.pokemon.MEW.baseStats then
  SaveConvert.setGen1DataStub(redStub, "red")
  GameVersion.set("red")
  local MonOps = require("MonOps")
  local S = State.new()
  S.data, S.version, S.save = redData, "red", SaveData.newGame()
  local boxes = Ops.boxes(S)
  boxes[2][1] = MonOps.create(redData, "MEW", 50)
  boxes[2][2] = MonOps.create(redData, "RHYDON", 30)
  boxes[4][1] = MonOps.create(redData, "BULBASAUR", 5)
  S.save.currentBox, S.selectedBox = 2, 2
  check(Ops.setBoxOrder(S, "livingdex"), "red living dex sort applies")
  local back = cartRoundTrip("red", S)
  if back then
    eq(layout(back.boxes, 12, 20), "1:1=BULBASAUR 1:2=RHYDON 1:3=MEW", "red .sav keeps the sorted boxes")
    eq(back.currentBox, 2, "red .sav keeps the current box")
  end
else
  print("[skip] save_editor_box_sort_2850 Red .sav round trip: no imported Red data")
end

local Game3Cache = require("tests.game3_cache")
if not Game3Cache.mount("pokemon/meta.lua") then
  print("[skip] save_editor_box_sort_2850 FireRed .sav round trip: " .. tostring(Game3Cache.reason))
  print(("save editor box sort tests: %d passed, %d failed"):format(passed, failed))
  os.exit(failed > 0 and 1 or 0)
end

do
  GameVersion.set("firered")
  local P = require("src.core.game3.pokemon")
  P.install(nil)
  local MonOps = require("MonOps")
  local Schema = require("src.core.game3.save_schema_firered")
  local App = require("tools.save-editor.App")
  local session = Schema.newGame({ name = "RED" })
  session.party = { MonOps.create({}, 25, 10, 3) }
  session.storage.boxes[1].mons[3] = MonOps.create({}, 313, 20, 3)
  session.storage.boxes[2].mons[9] = MonOps.create({}, 277, 5, 3)
  session.storage.boxes[5].mons[1] = MonOps.create({}, 315, 8, 3)
  session.storage.currentBox = 2
  local native = SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
  local path = os.tmpname()
  local f = assert(io.open(path, "wb"))
  f:write(SaveData.encode(native))
  f:close()
  App.load(path, { version = "firered", embedded = true })
  local S = App.getState()
  eq(require("BoxSort").dexNumber(S, { species = 313 }), 320, "firered cache maps internal Wailmer to National 320")
  check(Ops.setBoxOrder(S, "livingdex"), "firered living dex sort applies")
  check(App.save(), "firered sorted save writes")
  local saved = assert(require("SaveIO").load(path))
  os.remove(path)
  eq(saved.storage.boxes[9].mons[12] and saved.storage.boxes[9].mons[12].species, 277,
    "firered Lua save keeps Treecko in National slot 252")
  eq(saved.storage.boxes[10].mons[30] and saved.storage.boxes[10].mons[30].species, 315,
    "firered Lua save keeps Skitty in National slot 300")
  eq(saved.storage.boxes[11].mons[20] and saved.storage.boxes[11].mons[20].species, 313,
    "firered Lua save keeps Wailmer in National slot 320")
  App.unload()
  local back = cartRoundTrip("firered", { save = saved })
  if back then
    local box = back.storage.boxes
    eq(box[9].mons[12] and box[9].mons[12].species, 277, "firered .sav keeps the living dex slots")
    eq(box[11].mons[20] and box[11].mons[20].species, 313, "firered .sav keeps Wailmer after Skitty")
    eq(back.storage.currentBox, 2, "firered .sav keeps the current box")
  end
end

print(("save editor box sort tests: %d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
