package.path = package.path
  .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
_G.love = require("tests.love_stub")
require("tests.game3_cache").mountOrSkip("save_editor_property_legality_test", "pokemon/meta.lua")
local App = require("tools.save-editor.App")
local Ops = require("Ops")
local Gen = require("Gen")
local L = require("Legality")
local P = require("Properties")
local History = require("History")
local SD = require("src.core.SaveData")
local Copy = require("src.mods.Merge").deepCopy
local path = os.tmpname() .. "-properties.lua"
local file = assert(io.open(path, "wb"))
file:write(SD.encode(Gen.newGame("firered")))
file:close()
App.load(path, { version = "firered", embedded = true })
local S = App.getState()
assert(not S.loadError, S.status)
Ops.partyAdd(S)
Ops.selectParty(S, 1)
local function unique(list, field, records)
  local seen = {}
  for _, key in ipairs(list) do
    local id = tonumber(records[key][field])
    if id then
      assert(not seen[id], "duplicate picker alias " .. key)
      seen[id] = true
    end
  end
end
unique(S.cat.items, "itemId", S.data.items)
unique(S.cat.species, "speciesId", S.data.pokemon)
unique(S.cat.moves, "moveId", S.data.moves)
local potions = Ops.itemSearch(S, "potion")
assert(#potions >= 4, "Gen 3 search resolves display names")
local exact = Ops.itemSearch(S, "13")
local found = false
for _, id in ipairs(exact) do
  if tonumber(S.data.items[id].itemId) == 13 then
    found = true
  end
end
assert(found, "Gen 3 search resolves numeric item IDs")
local mon = S.editingMon
local count = 0
local function check(ok, message)
  count = count + 1
  assert(ok, message)
end
local function invalid(key, value)
  local bad = Copy(mon)
  bad[key] = value
  local ok, report = pcall(L.mon, S, bad)
  check(ok and report.errors > 0, "invalid " .. key .. " is reported without crashing")
end
check(L.mon(S, mon).errors == 0, "created Gen 3 properties pass")
check(L.mon(S, mon).status == "unchecked", "property success does not certify encounter legality")
for _, pair in ipairs({
  { "otId", 4321 },
  { "otSecretId", 1234 },
  { "otName", "ASH" },
  { "otGender", 1 },
  { "language", 7 },
  { "metLevel", 3 },
  { "metLocation", 88 },
  { "metGame", 2 },
  { "pokeball", 3 },
  { "markings", 9 },
  { "pokerus", 17 },
  { "contest.cool", 100 },
  { "ribbon.Cool", 4 },
  { "ribbon.Champion", true },
  { "modernFatefulEncounter", true },
}) do
  check(Ops.setMonProperty(S, mon, pair[1], pair[2]), "writes " .. pair[1])
  check(
    P.get(mon, P.find(S, pair[1])) == pair[2]
      or (pair[2] == true and P.get(mon, P.find(S, pair[1])) == 1),
    "reads " .. pair[1]
  )
end
check(require("src.core.game3.rse.ribbons").get(mon, "fateful") == 1, "native fateful bit agrees")
check(Ops.setMonProperty(S, mon, "modernFatefulEncounter", false), "fateful bit can clear")
check(require("src.core.game3.rse.ribbons").get(mon, "fateful") == 0, "native fateful bit clears")
check(not Ops.setMonProperty(S, mon, "language", 6), "unused language refused")
check(not Ops.setMonProperty(S, mon, "personality", 4294967296), "PID overflow refused")
check(not Ops.setMonProperty(S, mon, "ribbon.Cool", 5), "contest rank overflow refused")
local summary = require("src.core.game3.summary_data")
local pokemon = require("src.core.game3.pokemon")
local exp = summary.expForLevel(pokemon.growthRate(mon.species), 15) + 1
check(Ops.setExperience(S, mon, exp), "exact experience edited")
check(
  mon.level == 15 and Gen.exp(mon) == exp,
  "experience derives level and preserves exact remainder"
)
check(not Ops.setExperience(S, mon, 99999999), "experience overflow refused")
check(Ops.setCurrentHp(S, mon, 0) and mon.hp == 0, "fainted HP allowed")
check(not Ops.setCurrentHp(S, mon, mon.maxHp + 1), "HP above calculated maximum refused")
check(Ops.setMonStatus(S, mon, "SLP") and mon.sleep == 1, "sleep sets a valid duration")
check(not Ops.setMonStatus(S, mon, "unknown"), "unknown status refused")
check(Ops.setMonStatus(S, mon, nil), "status can clear")
check(Ops.setPpUps(S, mon, 1, 2), "table-form Gen 3 move PP Ups edited")
check(Ops.setPp(S, mon, 1, 3), "table-form Gen 3 move PP edited")
check(mon.moves[1].pp == 3 and mon.pp[1] == 3, "Gen 3 table and parallel PP agree")
require("MonOps").recalc(S.data, mon, 3)
check(mon.moves[1].pp == 3 and mon.pp[1] == 3, "recalculation preserves edited PP")
check(not Ops.itemHoldable(S, "364"), "TM Case cannot be held")
check(not Ops.itemHoldable(S, "339"), "HM cannot be held")
check(Ops.itemHoldable(S, "13"), "Potion can be held")
for _, pair in ipairs({
  { "ivs", "broken" },
  { "moves", false },
  { "abilityNum", "broken" },
  { "personality", -1 },
  { "ribbons", -1 },
  { "language", 6 },
  { "level", 101 },
  { "pokerus", 31 },
  { "metLevel", 99 },
  { "otSecretId", 65536 },
  { "status", "unknown" },
  { "friendship", 256 },
  { "happiness", -1 },
  { "ppBonusesPacked", -1 },
  { "ppBonuses", "broken" },
}) do
  invalid(pair[1], pair[2])
end
local bad = Copy(mon)
bad.evs = { hp = 255, atk = 255, def = 1, spe = 0, spa = 0, spd = 0 }
check(L.mon(S, bad).errors > 0, "EV total overflow detected")
bad = Copy(mon)
bad.moves[2] = Copy(bad.moves[1])
check(L.mon(S, bad).errors > 0, "duplicate moves detected")
bad = Copy(mon)
bad.egg = true
bad.isEgg = true
check(L.mon(S, bad).errors >= 3, "egg level, ball and language conflicts detected")
bad = Copy(mon)
bad.moves[2], bad.moves[3], bad.moves[4] = 0, 0, 0
bad.pp = { bad.moves[1].pp, 0, 0, 0 }
bad.ppBonusesPacked = 0
require("MonOps").maxAllPpUps(S.data, bad, 3)
check(
  (bad.pp[2] or 0) == 0 and require("MonOps").getPpUps(bad, 2) == 0,
  "max PP leaves empty native slots empty"
)
bad.egg, bad.isEgg = true, true
require("MonOps").maxAllPpUps(S.data, bad, 3)
check(require("MonOps").getPpUps(bad, 1) == 0, "egg max PP clears PP Ups")
bad.moves[1].pp = 0
local eggReport = L.mon(S, bad)
local ppError = false
for _, entry in ipairs(eggReport.checks) do
  if entry.message == "Egg moves must have base PP and no PP Ups" then
    ppError = true
  end
end
check(ppError, "egg depleted PP is reported")
check(L.mon(S, mon).errors == 0, "valid changes still pass property checks")
check(App.save(), "native edited save writes")
local output = assert(require("SaveIO").load(path))
for _, key in ipairs({
  "otId",
  "otSecretId",
  "otName",
  "otGender",
  "language",
  "metLevel",
  "metLocation",
  "metGame",
  "pokeball",
  "markings",
  "pokerus",
  "ribbons",
  "contest",
  "exp",
  "hp",
  "moves",
  "pp",
  "ppBonusesPacked",
  "maxPp",
}) do
  local function eq(a, b)
    if type(a) == "table" then
      for k, v in pairs(a) do
        eq(v, b[k])
      end
    else
      check(a == b, "saved " .. key .. " preserved")
    end
  end
  eq(mon[key], output.party[1][key])
end
local level = mon.level
check(History.undo(S), "undo after saving succeeds")
check(S.dirty, "undo away from saved state marks dirty")
check(History.redo(S), "redo after saving succeeds")
check(not S.dirty and S.save.party[1].level == level, "redo to saved state clears dirty")
-- The imported Gen 3 schema has nature, origin and ribbon controls that the
-- Gen 1 layout sweep cannot exercise. Include open named-choice grids and
-- the bottom of each form at phone, landscape and desktop sizes.
local Kit = require("Kit")
S.editingMon, S.mobileInspector, S.tab = S.save.party[1], true, "party"
for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 640, 360 }, { 1280, 720 } }) do
  local W, H = size[1], size[2]
  love.graphics.getDimensions = function()
    return W, H
  end
  love.window.getSafeArea = function()
    return 0, 0, W, H
  end
  for _, form in ipairs({
    { "main", "nature" },
    { "origin", "language" },
    { "origin", "pokeball" },
    { "origin", "metGame" },
    { "extras" },
    { "checks" },
  }) do
    for _, offset in ipairs({ 0, 400, 10000 }) do
      S.monSection, S.propertyChoice, S.inspectorScroll = form[1], form[2], offset
      Kit.audit = {}
      App.draw()
      for _, rect in ipairs(Kit.audit) do
        local clip = rect.clip or { x = 0, y = 0, w = W, h = H }
        local x1, y1 = math.max(rect.x, clip.x), math.max(rect.y, clip.y)
        local x2, y2 =
          math.min(rect.x + rect.w, clip.x + clip.w), math.min(rect.y + rect.h, clip.y + clip.h)
        if x1 < x2 and y1 < y2 then
          if rect.class == "control" or rect.class == "row" then
            check(rect.w >= 43.9 and rect.h >= 43.9, "native form touch target: " .. rect.label)
          end
          check(
            x1 >= -0.5 and y1 >= -0.5 and x2 <= W + 0.5 and y2 <= H + 0.5,
            "native form bounds: " .. rect.label
          )
          if rect.class == "scrollbar" then
            for _, control in ipairs(Kit.audit) do
              if control.class == "control" then
                local c = control.clip or { x = 0, y = 0, w = W, h = H }
                local cx1, cy1 = math.max(control.x, c.x), math.max(control.y, c.y)
                local cx2, cy2 =
                  math.min(control.x + control.w, c.x + c.w),
                  math.min(control.y + control.h, c.y + c.h)
                check(
                  math.min(x2, cx2) <= math.max(x1, cx1) or math.min(y2, cy2) <= math.max(y1, cy1),
                  "native form scrollbar covers " .. control.label
                )
              end
            end
          end
        end
      end
      Kit.audit = nil
    end
  end
end
App.unload()
os.remove(path)
print("save editor property legality: " .. count .. " checks passed")
