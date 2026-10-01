package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local K = require("tests.save_compat._codec")
local G3 = require("tests.fixtures.save.gen3_build")

local fixtures = {}
for _, c in ipairs(G3.cases()) do fixtures[c.id] = c end

local cases = {}
local function add(id, from, edit, extra)
  local c = fixtures[from]
  local save = assert(K.import(3, c.version, c.bytes))
  if edit then edit(save) end
  cases[#cases + 1] = { id = id, version = c.version, save = save, extra = extra }
end

for _, v in ipairs({ "firered", "leafgreen", "emerald" }) do
  local p = "g3.r2." .. v .. "."
  add(p .. "imported_basic", "g3." .. v .. ".basic")
  add(p .. "imported_full_party", "g3." .. v .. ".full_party_statuses")
  add(p .. "imported_full_boxes", "g3." .. v .. ".full_boxes")
  add(p .. "imported_eggs", "g3." .. v .. ".eggs")
  add(p .. "imported_bad_egg", "g3." .. v .. ".bad_checksum_mon")
  add(p .. "imported_wallpapers", "g3." .. v .. ".wallpaper_collision")
  add(p .. "no_stored_key", "g3." .. v .. ".basic", function(s)
    s.encryptionKey, s.modData.cartKey = nil, nil
  end)
end

local R2 = require("tests.save_compat._r2")
local EXCLUDED_ROOTS = {
  meta = "slot metadata, not part of a cart",
  continueGameWarp = "N4: the continue warp is recomputed from the player position on a templateless export (src/overworld.c:1706)",
  specialSaveWarpFlags = "N4: CONTINUE_GAME_WARP is always set by an export",
  facing = "the player always faces down after a continue-game warp (verified in mGBA), so the cart object event facing is not an engine input",
  rtcSkew = "wall-clock offset derived at import",
}
local roots, seen = {}, {}
for _, c in ipairs(cases) do
  for k in pairs(c.save) do
    if not seen[k] and not EXCLUDED_ROOTS[k] then
      seen[k] = true
      roots[#roots + 1] = k
    end
  end
end
table.sort(roots)
R2.ROOTS[3] = roots
R2.EXCLUDED.cartImage = "compact copy of the source cart"
R2.EXCLUDED.cartGame = "import stamp"
R2.EXCLUDED.cartKey = "import stamp"
R2.run(T, 3, cases)
T.finish()
