local U = require("tests.drivers.util")
return function(game)
  U.wait(20)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local App, Paint, Kit, path, tmp, oldPaint
  local dim, safe, osName
  local ok, err = xpcall(function()
    App = require("tools.save-editor.App")
    local Gen, P, History = require("Gen"), require("PokeblockOps"), require("History")
    local Serializer = require("src.core.SaveSerializer")
    local version = require("src.core.GameVersion").get()
    local dir = assert(os.getenv("POKEPORT_SHOT_DIR"))
    Kit, Paint = require("Kit"), require("src.ui.kit.Button")
    dim, safe, osName = love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS
    local controls = {}
    oldPaint = Paint.draw
    Paint.draw = function(owner, x, y, w, h, label, opts, hot, focused)
      if owner == Kit then controls[opts.id or label] = { x = x, y = y, w = w, h = h } end
      return oldPaint(owner, x, y, w, h, label, opts, hot, focused)
    end
    tmp = os.tmpname()
    path = tmp .. "-pokeblocks-2788.lua"
    local seed = Gen.newGame(version)
    seed.pokeblocks = {}
    for i = 1, 40 do seed.pokeblocks[i] = { color = 0, spicy = 0, dry = 0, sweet = 0, bitter = 0, sour = 0, feel = 0 } end
    seed.pokeblocks[1] = { color = 1, spicy = 30, dry = 0, sweet = 0, bitter = 0, sour = 0, feel = 20 }
    seed.pokeblocks[2] = { color = 9, spicy = 0, dry = 12, sweet = 0, bitter = 0, sour = 4, feel = 31 }
    seed.pokeblocks[3] = { color = 14, spicy = 40, dry = 40, sweet = 40, bitter = 0, sour = 0, feel = 11 }
    local file = assert(io.open(path, "wb"))
    file:write(Serializer.encode(seed)); file:close()
    App.load(path, { version = version, embedded = true })
    local S = App.getState()
    assert(S.save and not S.loadError and not S.missingCache, S.status)
    local W, H, platform = 390, 844, "Android"
    local function frame(name)
      controls = {}
      love.graphics.getDimensions = function() return W, H end
      love.window.getSafeArea = function() return 0, 0, W, H end
      love.system.getOS = function() return platform end
      local canvas = love.graphics.newCanvas(W, H, { msaa = 0 })
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      require("src.render.GameViewport").reset()
      love.graphics.clear(0, 0, 0, 1)
      App.draw()
      love.graphics.setCanvas()
      love.graphics.pop()
      if name then
        local pixels = canvas:newImageData()
        local bytes = pixels:encode("png"):getString()
        pixels:release()
        local out = assert(io.open(dir .. "/2788_" .. version .. "_" .. name .. ".png", "wb"))
        out:write(bytes); out:close()
        print("PASS captured " .. name)
      end
      canvas:release()
      love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName
    end
    local function tap(id)
      local r = assert(controls[id], "missing control " .. id)
      assert(r.y >= 0 and r.y + r.h <= H, "control must be visible " .. id)
      App.mousepressed(r.x + r.w / 2, r.y + r.h / 2, 1)
      frame()
      frame()
    end
    S.tab, S.itemView, S.pokeblockSlot = "items", "pokeblocks", 3
    frame(); frame()
    frame("01_case_phone")
    assert(controls["pokeblock-slot-1"], "slot grid drawn")
    print("PASS slot grid drawn")
    S.pokeblockScroll = 10000
    frame(); frame("02_gold_block_editor_phone")
    S.pokeblockScroll = 0
    frame(); frame()
    tap("Add block")
    assert(P.count(S.save) == 4 and S.pokeblockSlot == 4 and S.dirty, "Add block fills slot 4")
    print("PASS add block")
    frame("03_added_slot4_phone")
    assert(History.undo(S) and P.count(S.save) == 3, "undo add")
    assert(History.redo(S) and P.count(S.save) == 4, "redo add")
    print("PASS undo/redo")
    W, H, platform = 1280, 720, "Linux"
    S.pokeblockSlot, S.pokeblockScroll = 2, 0
    frame(); frame()
    frame("04_case_desktop")
    assert(P.set(S, 2, "sour", 200), "edit sour")
    assert(App.save() and not S.dirty, "native save")
    App.unload()
    App.load(path, { version = version, embedded = true })
    S = App.getState()
    assert(P.count(S.save) == 4 and P.block(S.save, 2).sour == 200, "reopen keeps blocks")
    print("PASS save/reopen keeps Pokéblocks")
  end, debug.traceback)
  if App then App.unload() end
  if Paint and oldPaint then Paint.draw = oldPaint end
  if dim then love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName end
  if path then
    os.remove(path)
    for _, backup in ipairs(require("tests.fs_io").globPrefix(path .. ".bak-")) do os.remove(backup) end
  end
  if tmp then os.remove(tmp) end
  if not ok then print("FAIL save_editor_pokeblocks_2788: " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
