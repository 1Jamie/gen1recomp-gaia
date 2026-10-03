local U = require("tests.drivers.util")

return function(game)
  U.wait(10)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local Fixture = require("tests.engine.save_editor_custom_maps")
  local GameVersion = require("src.core.GameVersion")
  local version = os.getenv("POKEPORT_VERSION") or GameVersion.get()
  local generation = GameVersion.generation(version)
  local Browser, Gen, Kit = require("MapBrowser"), require("Gen"), require("Kit")
  local State, Theme = require("State"), require("Theme")
  local opts, restoreNativeRoot = {}, nil
  local root = "save-editor-custom-map-fixture"
  assert(love.filesystem.createDirectory(root))
  if generation < 3 then
    opts.atlas = root .. "/atlas.png"
    local pixels = love.image.newImageData(8, 8)
    for y = 0, 7 do
      for x = 0, 7 do
        pixels:setPixel(x, y, x < 4 and 0.1 or 0.8, y < 4 and 0.9 or 0.2, 0.65, 1)
      end
    end
    assert(love.filesystem.write(opts.atlas, pixels:encode("png"):getString()))
    pixels:release()
  else
    local Dataset = require("src.core.game3.dataset")
    local maps = Dataset.buildMaps()
    Dataset.attachMidLayouts(maps)
    local source = maps[generation == 3 and GameVersion.layout(version) == "rse" and "EM_LITTLEROOT_TOWN" or "FR_PALLET_TOWN"]
    if not (source and source.midLayout) then
      for _, def in pairs(maps) do if def.midLayout then source = def; break end end
    end
    assert(source and source.midLayout, "no imported native map for custom-map visual probe")
    opts.pair = source.pair or source.midLayout.pair
    opts.mid = assert(source.midLayout:midAt(2, 2), "source metatile missing")
    local Native = require("src.core.game3.tileset_native")
    if not Native._cache then Native.install(Dataset.cache()) end
    assert(Native.get(opts.pair), "native source tileset did not load")
  end
  local data, loader, ids = Fixture.load(version, opts)
  if generation == 3 then
    local Extract = require("src.import.gba.extract_island1")
    restoreNativeRoot = Extract.NATIVE_ROOT
    Extract.NATIVE_ROOT = root .. "/native"
    require("src.core.game3.dataset").invalidateManifestCache()
    assert(love.filesystem.createDirectory(Extract.NATIVE_ROOT .. "/layouts"))
    local cells = {}; for i = 1, 24 do cells[i] = { mid = ids.mid, coll = 0, elev = 0 } end
    assert(love.filesystem.write(Extract.NATIVE_ROOT .. "/layouts/" .. ids.lazy .. ".mid",
      require("src.import.gba.native_pack").encodeMidLayout({ width = 6, height = 4, cells = cells })))
  end
  local S = State.new()
  S.data, S.version, S.tab = data, version, "map"
  S.save = { generation = generation, version = version, player = { map = ids.new, x = 1, y = 1 } }
  if generation == 3 then S.save.engine = "game3"; S.save.map = ids.new; S.save.x = 1; S.save.y = 1 end
  local originalDraw, originalUpdate = game.draw, game.update
  game.update = function() end
  game.draw = function()
    require("src.render.GameViewport").reset()
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setShader()
    love.graphics.clear(0.035, 0.045, 0.075, 1)
    local w, h = love.graphics.getDimensions()
    Kit.layout(w, h)
    Kit.beginFrame(-1, -1, false, 0)
    Kit.text("small", "Installed mod map preview · " .. version, 20, 12, Theme.PAL.heading)
    Browser.draw(S, Kit, 20, 45, w - 40, h - 65)
    Kit.endFrame()
  end
  local errors, captures = {}, 0
  local function check(ok, message)
    if not ok then errors[#errors + 1] = message; print("FAIL " .. message)
    else print("PASS " .. message) end
  end
  local function select(id, label)
    Browser.select(S, id)
    S.mapSection, S.mapAutoFit = "view", true
    local dir = assert(os.getenv("POKEPORT_SHOT_DIR"), "POKEPORT_SHOT_DIR is required")
    assert(U.still(game, dir .. "/" .. version .. "-custom-map-" .. label .. ".png"))
    captures = captures + 1
    check(S._mapViewRect and S._mapViewRect.w > 0, label .. " actual editor viewport is visible")
  end
  local function terrainPixels(id)
    if not Browser.preview then return nil end
    S.mapId = id
    local ok, map, reason = Browser.preview(S)
    if not (ok and map.renderer and not reason) then return nil end
    local canvas = love.graphics.newCanvas(96, 64, { msaa = 0, dpiscale = 1 })
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setShader()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    map.renderer:draw(0, 0, 96, 64)
    love.graphics.setCanvas()
    love.graphics.pop()
    local pixels = canvas:newImageData()
    canvas:release()
    local r, g, b, a = pixels:getPixel(1, 1)
    if generation < 3 then
      check(math.abs(r - 0.1) < 0.02 and math.abs(g - 0.9) < 0.02 and math.abs(b - 0.65) < 0.02 and a > 0.98,
        id .. " actual custom atlas pixels reach terrain renderer")
    else
      local opaque = 0
      for y = 0, 15 do for x = 0, 15 do
        local _, _, _, alpha = pixels:getPixel(x, y)
        if alpha > 0.9 then opaque = opaque + 1 end
      end end
      check(opaque > 200, id .. " imported native metatile pixels render after mod load")
    end
    pixels:release()
    return map
  end
  select(ids.base, "patched")
  local expectedWidth = generation == 3 and 6 or 4
  check(Gen.maps(data)[ids.base].width == expectedWidth, "existing map uses installed mod dimensions")
  if generation == 3 then
    check(Gen.maps(data)[ids.base].midLayout:midAt(0, 0) == ids.mid, "existing map uses installed mod layout")
  end
  check(terrainPixels(ids.base) ~= nil, "patched existing map has artwork")
  select(ids.new, "new")
  check(terrainPixels(ids.new) ~= nil, "new registered map has artwork")
  if generation == 3 then
    select(ids.lazy, "native-file")
    check(data.maps[ids.lazy].midLayout ~= nil, "new mod map lazily loads its native file")
    check(terrainPixels(ids.lazy) ~= nil, "lazy native map has artwork")
  end
  select(ids.missing, "missing-art")
  check(S.mapPreviewReason and S.mapPreviewReason:find("unavailable", 1, true), "missing map artwork has a visible explanation")
  if Browser.preview then
    local ok, grid = Browser.preview(S)
    check(ok and grid:inBounds(1, 1), "missing art preserves coordinate placement bounds")
    local rect = S._mapViewRect
    local x = rect.x + (16 * 1.5 - S.mapCamX) * S.mapZoom
    local y = rect.y + (16 * 1.5 - S.mapCamY) * S.mapZoom
    local w, h = love.graphics.getDimensions()
    Kit.beginFrame(x, y, true, 0)
    Browser.draw(S, Kit, 20, 45, w - 40, h - 65)
    Kit.endFrame()
    check(S.mapClickCell and S.mapClickCell.cx == 1 and S.mapClickCell.cy == 1, "actual missing-art grid still selects a spawn cell")
  end
  game.draw, game.update = originalDraw, originalUpdate
  if restoreNativeRoot then
    require("src.import.gba.extract_island1").NATIVE_ROOT = restoreNativeRoot
    require("src.core.game3.dataset").invalidateManifestCache()
  end
  print(("custom maps %s: loaded=%d captures=%d failures=%d"):format(version, #loader:status().loaded, captures, #errors))
  love.event.quit(#errors == 0 and 0 or 1)
end
