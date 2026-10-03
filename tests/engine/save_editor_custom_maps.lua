package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"

local Fixture = {}

function Fixture.load(version, opts)
  opts = opts or {}
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  local generation = GameVersion.generation(version)
  local Merge = require("src.mods.Merge")
  local Gen = require("Gen")
  local baseId = generation == 3 and "FR_EDITOR_BASE" or "EDITOR_BASE"
  local newId = generation == 3 and "FR_EDITOR_NEW" or "EDITOR_NEW"
  local lazyId = "FR_EDITOR_LAZY"
  local missingId = generation == 3 and "FR_EDITOR_MISSING" or "EDITOR_MISSING"
  local pair, mid = opts.pair or "editor_fixture", opts.mid or 7
  local atlas = opts.atlas or "mods/editor_map_fixture/atlas.png"
  local base = opts.base or {
    id = baseId, width = 3, height = 2, tileset = "EDITOR_TILES", blocks = { 1, 1, 1, 1, 1, 1 },
    warps = {}, midLayout = generation == 3 and {
      width = 3, height = 2, pair = pair, midAt = function() return 0 end,
    } or nil,
  }
  local data = { maps = { [baseId] = Merge.deepCopy(base) }, tilesets = {} }
  if generation == 3 then data.game3Maps = { [baseId] = base }
  elseif generation == 2 then Gen.bindGoldData(data) end
  local source
  if generation == 3 then
    source = ([[return function(mod)
      local function layout(pair)
        return { width = 6, height = 4, pair = pair, midAt = function() return %d end }
      end
      mod.content.maps:patch(%q, { width = 6, height = 4, midLayout = layout(%q), pair = %q, weather = 2 })
      mod.content.maps:register(%q, { id = %q, width = 6, height = 4, midLayout = layout(%q), pair = %q, warps = {} })
      mod.content.maps:register(%q, { id = %q, width = 6, height = 4, pair = %q, warps = {} })
      mod.content.maps:register(%q, { id = %q, width = 6, height = 4, warps = {} })
    end]]):format(mid, baseId, pair, pair, newId, newId, pair, pair, lazyId, lazyId, pair, missingId, missingId)
  else
    source = ([[return function(mod)
      local row = {}; for i = 1, 16 do row[i] = 0 end
      mod.content.tilesets:register("EDITOR_TILES", {
        id = "EDITOR_TILES", image = %q, tilesPerRow = 1, blocks = { row, row },
        walkable = { 0 }, collision = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }, trueColor = true,
      })
      mod.content.maps:patch(%q, { width = 4, height = 3, blocks = { 1,1,1,1,1,1,1,1,1,1,1,1 } })
      mod.content.maps:register(%q, {
        id = %q, tileset = "EDITOR_TILES", width = 4, height = 3,
        blocks = { 1,1,1,1,1,1,1,1,1,1,1,1 }, warps = {}, objects = {}, signs = {},
      })
      mod.content.tilesets:register("EDITOR_MISSING_TILES", { image = "mods/editor_map_fixture/missing.png", blocks = { row }, walkable = {} })
      mod.content.maps:register(%q, { id = %q, tileset = "EDITOR_MISSING_TILES", width = 2, height = 2, blocks = { 0,0,0,0 }, warps = {} })
    end]]):format(atlas, baseId, newId, newId, missingId, missingId)
  end
  local files = {
    ["mods/editor_map_fixture/manifest.json"] = ([[{"id":"editor_map_fixture","name":"Editor map fixture","version":"1.0.0","api":2,"entry":"main.lua","games":[%q]}]]):format(version),
    ["mods/editor_map_fixture/main.lua"] = source,
  }
  local fs = {}
  function fs.read(path) return files[path] end
  function fs.write(path, bytes) files[path] = bytes; return true end
  function fs.getInfo(path)
    if files[path] then return { type = "file" } end
    for key in pairs(files) do if key:sub(1, #path + 1) == path .. "/" then return { type = "directory" } end end
  end
  function fs.load(path) return loadstring(assert(files[path]), "@" .. path) end
  function fs.getDirectoryItems(path)
    local found, items = {}, {}
    for key in pairs(files) do
      if key:sub(1, #path + 1) == path .. "/" then
        local name = key:sub(#path + 2):match("^[^/]+")
        if not found[name] then found[name], items[#items + 1] = true, name end
      end
    end
    table.sort(items)
    return items
  end
  local loader = require("src.mods.Loader").new({ fs = fs, generation = generation, version = version })
  assert(loader:load(data), table.concat(loader.errors, "; "))
  assert(#loader:status().loaded == 1, "fixture mod did not load")
  return data, loader, { base = baseId, new = newId, lazy = lazyId, missing = missingId, pair = pair, mid = mid }
end

if ... == "tests.engine.save_editor_custom_maps" then return Fixture end

love = require("tests.love_stub")
local T = require("tests.harness")
local Gen = require("Gen")
local Browser = require("MapBrowser")
local State = require("State")
local Kit = require("Kit")
local realImage = love.graphics.newImage
love.graphics.newImage = function(path)
  if type(path) == "string" and path:find("missing.png", 1, true) then error("missing fixture image") end
  return realImage(path)
end
local function state(data, version, id)
  local s = State.new()
  s.data, s.version, s.tab, s.mapId = data, version, "map", id
  s.save = { version = version, generation = require("src.core.GameVersion").generation(version), player = { map = id, x = 1, y = 1 } }
  return s
end
local function draw(s)
  Kit.beginFrame(-1, -1, false, 0)
  Browser.draw(s, Kit, 0, 0, 1200, 760)
  Kit.endFrame()
end

for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local data, loader, ids = Fixture.load(version)
  local maps = Gen.maps(data)
  local generation = require("src.core.GameVersion").generation(version)
  T.eq(maps[ids.base].width, generation == 3 and 6 or 4, version .. " mod patch reaches preview map lookup")
  T.check(maps[ids.new] ~= nil, version .. " loaded mod's new map is discoverable")
  if generation == 3 then
    T.eq(maps[ids.base].weather, 2, version .. " existing mod patch is authoritative")
    T.eq(maps[ids.base].midLayout:midAt(0, 0), 7, version .. " mod-supplied layout survives base binding")
  end
  local missing = state(data, version, ids.missing)
  draw(missing)
  T.check(type(missing.mapPreviewReason) == "string" and missing.mapPreviewReason:find("unavailable", 1, true), version .. " missing artwork is explained in the actual map panel")
  if Browser.preview then
    local s = state(data, version, ids.new)
    if generation < 3 then
      local ok, map, reason = Browser.preview(s)
      T.check(ok and map.renderer and not reason, version .. " loaded custom atlas builds a terrain renderer")
      T.eq(map.widthCells, 8, version .. " block dimensions use walking cells")
    else
      local Dataset = require("src.core.game3.dataset")
      local Extract = require("src.import.gba.extract_island1")
      local root = "editor-custom-map-fixture"
      Extract.NATIVE_ROOT = root
      Dataset.invalidateManifestCache()
      local cells = {}; for i = 1, 24 do cells[i] = { mid = 7, coll = 0, elev = 0 } end
      love.filesystem.write(root .. "/layouts/" .. ids.lazy .. ".mid", require("src.import.gba.native_pack").encodeMidLayout({ width = 6, height = 4, cells = cells }))
      local original = data.maps[ids.new].midLayout
      Browser.preview(s)
      T.eq(data.maps[ids.new].midLayout, original, version .. " preview preserves supplied layout identity")
      s.mapId = ids.lazy
      local ok, map = Browser.preview(s)
      T.check(ok and data.maps[ids.lazy].midLayout and data.maps[ids.lazy].midLayout:midAt(2, 2) == 7, version .. " gameplay API lazily attaches a mod-added native MID file")
      T.check(map:inBounds(5, 3) and not map:inBounds(6, 3), version .. " native grid preserves placement bounds")
      s.mapId = ids.missing
      local _, grid, reason = Browser.preview(s)
      T.check(grid:inBounds(5, 3) and reason:find("missing native map layout", 1, true), version .. " missing layout retains the coordinate grid")
      data.maps[ids.missing].midLayout = { midAt = function() return 0 end }
      local _, _, pairReason = Browser.preview(s)
      T.check(pairReason:find("missing native tileset pair", 1, true), version .. " missing pair is distinguished from missing layout")
    end
  end
  require("src.mods.Runtime").reset()
end

T.finish()
