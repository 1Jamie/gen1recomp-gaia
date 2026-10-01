package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("r2_gen1 skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local G1 = require("tests.fixtures.save.gen1_build")

local fixtures = {}
for _, c in ipairs(G1.cases()) do fixtures[c.id] = c end

local function imported(id)
  local c = fixtures[id]
  local save = assert(K.import(1, c.version, c.bytes))
  save.rawImport = nil
  return save, c.version
end

local cases = {}
local function add(id, from, edit, extra)
  local save, version = imported(from)
  if edit then edit(save) end
  cases[#cases + 1] = { id = id, version = version, save = save, extra = extra }
end

add("g1.r2.red.imported_basic", "g1.red.basic")
add("g1.r2.yellow.imported_basic", "g1.yellow.basic")
add("g1.r2.red.imported_full_party", "g1.red.full_party_statuses")
add("g1.r2.red.imported_full_boxes", "g1.red.full_boxes")
add("g1.r2.red.imported_all_dex", "g1.red.all_dex")
add("g1.r2.red.imported_max_stacks", "g1.red.max_stacks")
add("g1.r2.red.engine_starter", "g1.red.basic", function(s)
  s.party[1] = { species = "SQUIRTLE", level = 5, exp = 135, hp = 20,
    stats = { hp = 20, attack = 11, defense = 13, speed = 10, special = 11 },
    moves = { { id = "TACKLE", pp = 35, ppUps = 0 }, { id = "TAIL_WHIP", pp = 30, ppUps = 0 } },
    dvs = { attack = 9, defense = 8, speed = 7, special = 6 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }, ot = s.player.name }
end, function(back)
  if back.party[1].otId ~= back.player.id then
    return { { "field:party[].otId", ("engine starter exported OT ID %s, player is %s"):format(
      tostring(back.party[1].otId), tostring(back.player.id)) } }
  end
end)
add("g1.r2.red.hall_of_fame", "g1.red.basic", function(s)
  s.hallOfFame = { { { species = "MEW", level = 50 }, { species = "CHARMANDER", level = 36, nickname = "CHAR" } } }
end)
add("g1.r2.red.last_heal", "g1.red.basic", function(s)
  s.lastHeal = { map = "VIRIDIAN_CITY", x = 23, y = 26 }
end)
add("g1.r2.red.options", "g1.red.basic", function(s)
  s.options = { textSpeed = 1, battleStyle = "set", animations = false }
end)
add("g1.r2.yellow.options_sound", "g1.yellow.basic", function(s)
  s.options = { textSpeed = 5, battleStyle = "shift", animations = true, sound = 2 }
end)
add("g1.r2.red.hall_of_fame_overflow", "g1.red.basic", function(s)
  s.hallOfFame = {}
  for t = 1, 50 do s.hallOfFame[t] = { { species = "MEW", level = t }, { species = "PIDGEY", level = 9, nickname = "BIRD" } } end
  s.hallOfFameTotal = 77
end)
add("g1.r2.red.surfing", "g1.red.basic", function(s) s.player.surfing = true end)
add("g1.r2.red.bike", "g1.red.basic", function(s) s.onBike = true end)
add("g1.r2.red.flags_raw", "g1.red.unnamed_events")
add("g1.r2.red.carriers", "g1.red.glitch_species_party")
add("g1.r2.red.glitch_box", "g1.red.glitch_species_box")
add("g1.r2.red.unknown_move", "g1.red.unknown_move")
add("g1.r2.red.sleep_and_combo_status", "g1.red.status_combo")
add("g1.r2.red.move_gap", "g1.red.move_gap")
add("g1.r2.red.stale_box_level", "g1.red.party_box_level_stale")
add("g1.r2.red.duplicate_stacks", "g1.red.duplicate_stacks")
add("g1.r2.red.unknown_pc_item", "g1.red.unknown_pc_item")
add("g1.r2.red.big_stack", "g1.red.basic", function(s)
  s.inventory.POTION = 150
  s.bagOrder = { "POTION" }
end)
add("g1.r2.red.playtime_maxed", "g1.red.playtime_maxed")
add("g1.r2.yellow.toggles", "g1.yellow.toggles")
add("g1.r2.yellow.trades", "g1.yellow.all_trades")
add("g1.r2.red.box_bank_only", "g1.red.saved_once_box", function(s)
  s.boxes[7] = { s.boxes[1][2] }
end)

require("tests.save_compat._r2").run(T, 1, cases)
T.finish()
