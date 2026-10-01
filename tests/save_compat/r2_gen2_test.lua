package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local R2 = require("tests.save_compat._r2")

R2.ROOTS[2] = { "player", "rival", "mom", "party", "boxes", "inventory", "bagOrder", "pcItems", "pcOrder",
                "mail", "currentBox", "pokedex", "unownDex", "firstUnownSeen", "position", "playTime", "events",
                "mapScenes", "engineFlags", "boxNames", "variableSprites", "playerState", "options" }

local fixtures = {}
for _, c in ipairs(G2.cases()) do fixtures[c.id] = c end

local cases = {}
local function add(id, from, edit, extra)
  local c = fixtures[from]
  local save = assert(K.import(2, c.version, c.bytes))
  save.rawImport = nil
  if edit then edit(save) end
  cases[#cases + 1] = { id = id, version = c.version, save = save, extra = extra }
end

local function letter(message, author, species)
  return { type = "FLOWER_MAIL", message = message, author = author, authorId = 0x1234, species = species }
end

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local p = "g2.r2." .. v .. "."
  add(p .. "imported_basic", "g2." .. v .. ".basic")
  add(p .. "imported_full_boxes", "g2." .. v .. ".full_boxes")
  add(p .. "unnicknamed", "g2." .. v .. ".basic", function(s) s.party[1].nickname = nil end, function(back)
    if (back.party[1].nickname or "") == "" then
      return { { "field:party[].nickname", "an un-nicknamed mon exports a blank nickname" } }
    end
  end)
  add(p .. "egg", "g2." .. v .. ".basic", function(s)
    local egg = {}
    for k, x in pairs(s.party[1]) do egg[k] = x end
    egg.isEgg, egg.eggSteps, egg.nickname = true, 10, "EGG"
    s.party[2] = egg
  end)
  add(p .. "egg_unnamed", "g2." .. v .. ".basic", function(s)
    local egg = {}
    for k, x in pairs(s.party[1]) do egg[k] = x end
    egg.isEgg, egg.eggSteps, egg.nickname = true, 0, nil
    s.party[2] = egg
  end, function(back)
    if back.party[2].nickname ~= "EGG" then
      return { { "field:party[].nickname", "an egg with no nickname exports EGG" } }
    end
  end)
  add(p .. "imported_egg_box", "g2." .. v .. ".egg_box")
  add(p .. "imported_egg_party", "g2." .. v .. ".egg_party")
  add(p .. "raw_item", "g2." .. v .. ".basic", function(s) s.party[1].item = 0xFA end)
  add(p .. "bag_reordered", "g2." .. v .. ".bag_order", function(s)
    s.bagOrder = { "ANTIDOTE", "POTION", "REPEL", "BICYCLE", "POKE_BALL" }
  end)
  add(p .. "stack_split", "g2." .. v .. ".basic", function(s)
    s.inventory.POTION = 149
    s.inventory.REPEL = 3
    s.bagOrder = { "REPEL", "POTION", "BICYCLE", "POKE_BALL" }
  end)
  add(p .. "pc_items", "g2." .. v .. ".basic", function(s)
    s.pcItems = { POTION = 120, REPEL = 3, MAX_POTION = 1 }
    s.pcOrder = { "REPEL", "POTION", "MAX_POTION" }
  end)
  add(p .. "mail", "g2." .. v .. ".basic", function(s)
    s.party[1].item = "FLOWER_MAIL"
    s.mail = {
      party = { [1] = letter("HELLO THERE FRIEND OF MINE", "ASH", 155) },
      box = { letter("SHORT", "GARY", 7), letter("TWO\nLINES", "MOM", 155) },
    }
  end)
  add(p .. "unown", "g2." .. v .. ".basic", function(s)
    s.unownDex = { 3, 1, 26 }
    s.firstUnownSeen = 3
    s.engineFlags[v == "crystal" and 43 or 42] = true
  end)
  add(p .. "options", "g2." .. v .. ".basic", function(s)
    s.options = { textSpeed = "FAST", battleScene = false, battleStyle = "SET", sound = "STEREO",
                  frame = 5, print = "DARKER", menuAccount = false }
  end)
  add(p .. "mom", "g2." .. v .. ".basic", function(s)
    s.mom = { name = "MAMA", savedMoney = 12345, active = true, savingMoney = true,
              whichItem = 3, triggerBalance = 4000 }
  end)
  add(p .. "player_state", "g2." .. v .. ".basic", function(s) s.playerState = "surf" end)
  add(p .. "renamed_box", "g2." .. v .. ".basic", function(s)
    s.boxNames[1] = "PARTY"
    s.boxNames[14] = "LAST1234"
  end)
  add(p .. "current_box", "g2." .. v .. ".full_boxes", function(s) s.currentBox = 14 end)
  add(p .. "imported_box_index_14", "g2." .. v .. ".box_index_14")
  add(p .. "imported_mail", "g2." .. v .. ".mail")
  add(p .. "imported_max_stacks", "g2." .. v .. ".max_stacks")
  add(p .. "imported_all_dex_unown", "g2." .. v .. ".all_dex_unown")
end
add("g2.r2.crystal.caught_data", "g2.crystal.basic", function(s)
  local m = s.party[1]
  m.caughtData = nil
  m.caughtTime, m.caughtLevel, m.caughtLocation, m.caughtByGender = 2, 9, 5, "girl"
end)
add("g2.r2.crystal.female", "g2.crystal.female")

R2.run(T, 2, cases)
T.finish()
