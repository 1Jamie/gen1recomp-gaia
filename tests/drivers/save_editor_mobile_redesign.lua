local U = require("tests.drivers.util")
return function(game)
  U.wait(20)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local App = require("tools.save-editor.App")
  local Ops = require("Ops")
  local Gen = require("Gen")
  local SD = require("src.core.SaveData")
  local Chooser = require("Chooser")
  local Kit = require("Kit")
  local Paint = require("src.ui.kit.Button")
  local realPaint, navigationRects = Paint.draw, {}
  local labelFailures, labelChecks = {}, 0
  local function labelCheck(ok, message)
    if not ok then
      labelFailures[#labelFailures + 1] = message
    end
    assert(ok, message)
  end
  Paint.draw = function(owner, x, y, w, h, label, opts, hot, focused)
    if owner == Kit and label and label ~= "" then
      labelCheck(opts.labelLayout, "missing complete button label " .. label)
      local layout = opts.labelLayout
      labelCheck(opts.fullLabel, "truncated button label " .. label)
      labelCheck(layout.width <= layout.available + 1, "button word does not fit " .. label)
      labelCheck(layout.height <= h - 4 * Kit.scale + 1, "button label does not fit " .. label)
      labelCheck(table.concat(layout.lines, " ") == label, "button text shortened " .. label)
      labelChecks = labelChecks + 1
    end
    if owner == Kit and opts.id and opts.id:match("^navigate%-") then
      navigationRects[opts.id:sub(10)] = { x = x, y = y, w = w, h = h }
    end
    return realPaint(owner, x, y, w, h, label, opts, hot, focused)
  end
  local version = os.getenv("POKEPORT_VERSION") or "red"
  local path = os.tmpname() .. "-editor-preview.lua"
  local seed = Gen.newGame(version)
  local f = assert(io.open(path, "wb"))
  f:write(SD.encode(seed))
  f:close()
  App.load(path, { version = version, embedded = true })
  local S = App.getState()
  assert(S.save and not S.loadError, S.status)
  Ops.partyAdd(S)
  Ops.selectParty(S, 1)
  Ops.addToBag(S, S.cat.items[1])
  Ops.addToBag(S, S.cat.items[2])
  Ops.boxAdd(S)
  Ops.selectParty(S, 1)
  local dim, safe = love.graphics.getDimensions, love.window.getSafeArea
  local dir = assert(os.getenv("POKEPORT_SHOT_DIR"))
  -- Check rendered pixels with MSAA disabled, not only the options passed
  -- to the painter. Both bright fills must leave all four corner cutouts
  -- and have a smooth arc, including small icon actions and hover states.
  local function cornerProbe(w, h, opts, hot)
    local canvas = love.graphics.newCanvas(w + 16, h + 16, { msaa = 0 })
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setShader()
    love.graphics.clear(0, 0, 0, 0)
    Kit.beginFrame(hot and 20 or -1, hot and 20 or -1, false, 0)
    Kit.button(8, 8, w, h, "", opts)
    Kit.endFrame()
    love.graphics.setCanvas()
    love.graphics.pop()
    local pixels = canvas:newImageData()
    canvas:release()
    local function alpha(x, y)
      local _, _, _, a = pixels:getPixel(x, y)
      return a
    end
    local rounded = alpha(10, 10) < 0.02
      and alpha(w + 5, 10) < 0.02
      and alpha(10, h + 5) < 0.02
      and alpha(w + 5, h + 5) < 0.02
    assert(alpha(8 + math.floor(w / 2), 8 + math.floor(h / 2)) > 0.3, "missing button body")
    local smooth = false
    for py = 8, 21 do
      for px = 8, 21 do
        local a = alpha(px, py)
        smooth = smooth or (a > 0.02 and a < 0.98)
      end
    end
    pixels:release()
    return rounded, smooth
  end
  local control = require("Theme").CONTROL
  local newRadius = control.radius
  control.radius = 8
  local oldRounded = cornerProbe(100, 44, { kind = "accent" }, false)
  control.radius = newRadius
  assert(not oldRounded, "old corner regression was not reproduced")
  local paints = {
    { kind = "accent" },
    { kind = "good" },
    { kind = "primary" },
    { kind = "ghost" },
    { kind = "danger" },
    { face = "selection", active = true },
    { face = "selection", active = false },
    { face = "invert" },
    { kind = "accent", enabled = false },
    { kind = "good", enabled = false },
  }
  local cornerChecks = 0
  for _, size in ipairs({ { 44, 44 }, { 100, 44 }, { 320, 44 }, { 160, 64 } }) do
    for _, opts in ipairs(paints) do
      for _, hot in ipairs({ false, true }) do
        local rounded, smooth = cornerProbe(size[1], size[2], opts, hot)
        assert(rounded, "squared button corner: " .. (opts.kind or opts.face))
        if opts.enabled ~= false then
          assert(smooth, "aliased button arc: " .. (opts.kind or opts.face))
        end
        cornerChecks = cornerChecks + 1
      end
    end
  end
  print("PASS rendered corner checks: " .. cornerChecks .. " button variants, old shape reproduced")
  local function shot(name, W, H, settle)
    local canvas = love.graphics.newCanvas(W, H)
    love.graphics.getDimensions = function()
      return W, H
    end
    love.window.getSafeArea = function()
      return 0, 0, W, H
    end
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setShader()
    require("src.render.GameViewport").reset()
    love.graphics.clear(0, 0, 0, 1)
    App.draw()
    if settle then
      settle()
    end
    App.draw()
    love.graphics.setCanvas()
    love.graphics.pop()
    local bytes = canvas:newImageData():encode("png"):getString()
    local out = assert(io.open(dir .. "/" .. version .. "-" .. name .. ".png", "wb"))
    out:write(bytes)
    out:close()
    canvas:release()
    love.graphics.getDimensions, love.window.getSafeArea = dim, safe
    print("PASS captured " .. name)
    U.wait(1)
  end
  local function popupShot(name, W, H, key)
    Chooser.close(S)
    navigationRects = {}
    shot(name, W, H, function()
      local rect = assert(navigationRects[key], "missing dropdown " .. key)
      App.mousepressed(rect.x + rect.w / 2, rect.y + rect.h / 2, 1)
      App.draw()
      assert(S.navPopup and S.navPopup.key == key, "dropdown did not open " .. key)
    end)
    Chooser.close(S)
  end
  for _, tab in ipairs({ "party", "boxes", "items", "events", "dex", "map", "trainer", "legality" }) do
    S.tab = tab
    S.pageScroll = {}
    S.inspectorScroll = 0
    S.monSection = "main"
    S.mobileInspector = true
    shot(tab, 360, 640)
    shot("full-label-" .. tab, 320, 568)
  end
  S.tab = "dex"
  S.pageScroll = {}
  shot("pokedex-full-labels", 390, 844)
  shot("pokedex-small-phone", 320, 568)
  popupShot("pokedex-actions", 390, 844, "dexActions")
  popupShot("pokedex-actions-small-phone", 320, 568, "dexActions")
  -- Audit complete labels on armed confirmations and every inventory mode,
  -- including the state whose longer label used to overflow a small chip.
  S.tab = "items"
  for _, view in ipairs({ "bag", "pc", "wallet", "badges" }) do
    S.itemView = view
    shot("full-label-items-" .. view, 320, 568)
  end
  S.itemView = "bag"
  local bagId = require("src.inventory.Bag").order(S.save, S.data)[1]
  if bagId then
    Ops.arm(S, "bag-drop-" .. tostring(bagId))
    shot("full-label-item-confirmation", 320, 568)
    Ops.disarm(S)
  end
  S.tab = "boxes"
  for _, view in ipairs({ "storage", "party" }) do
    S.boxView = view
    shot("full-label-boxes-" .. view, 320, 568)
  end
  S.boxView = "storage"
  Ops.arm(S, "box-release")
  shot("full-label-box-confirmation", 320, 568)
  Ops.disarm(S)
  if Gen.ofState(S) == 3 and S.game3Events and S.game3Events.story[1] then
    local flag = S.game3Events.story[1]
    Gen.setFlag(S.save, flag.name or flag.id, true)
    S.tab = "events"
    shot("selected-events", 390, 844)
  end
  S.tab = "map"
  for _, section in ipairs({ "maps", "view", "spawn" }) do
    S.mapSection = section
    shot("map-" .. section, 360, 640)
    shot("map-" .. section .. "-landscape", 640, 360)
  end
  S.mapSection, S.mapFocused = "view", true
  shot("map-focus-landscape", 640, 360)
  S.mapFocused = false
  S.tab = "party"
  S.mobileInspector = false
  shot("party-roster", 360, 640)
  S.mobileInspector = true
  for _, section in ipairs({ "stats", "moves", "origin", "extras", "checks" }) do
    S.monSection = section
    S.inspectorScroll = 0
    shot(section, 390, 844)
    shot("full-label-" .. section, 320, 568)
  end
  local Touch=require("TouchEditor")
  local mon=S.editingMon
  for _,size in ipairs({{320,568},{390,844},{640,360}}) do
    Touch.open(S,Kit,{mode="number",id="level",title="Level",value=mon.level,
      limits=function() return require("ValueLimits").mon(S,mon,"level") end,
      apply=function(v) return Ops.setLevel(S,mon,v) end})
    shot("value-wheel-"..size[1],size[1],size[2])
    S.editPopup.scroll=10000
    shot("value-wheel-footer-"..size[1],size[1],size[2])
    Touch.close(S,Kit)
  end
  if Gen.ofState(S)==3 then
    Touch.open(S,Kit,{mode="choice",title="Found at",value=mon.metLocation,
      options=require("NamedChoices").locations(S),apply=function(v) return Ops.setMonProperty(S,mon,"metLocation",v) end})
    shot("searchable-locations",390,844)
    S.editPopup.query="route"
    shot("searchable-locations-filtered",320,568)
    Touch.close(S,Kit)
    Ops.setEv(S,mon,"hp",255);Ops.setEv(S,mon,"atk",200)
    S.monSection,S.inspectorScroll="stats",0
    shot("ev-budget",390,844)
    Touch.open(S,Kit,{mode="number",title="Defense EV",value=0,
      limits=function() return require("ValueLimits").mon(S,mon,"ev-def") end,
      apply=function(v) return Ops.setEv(S,mon,"def",v) end})
    shot("ev-budget-wheel",390,844)
    Touch.close(S,Kit)
  end
  Touch.open(S,Kit,{mode="help",title="Randomize Pokémon",help="Replaces this Pokémon with a wild one from this game. Real level range, normal moves. Undo brings yours back."})
  shot("action-help",320,568)
  Touch.close(S,Kit)
  local originalMon = require("src.mods.Merge").deepCopy(mon)
  mon.level, mon.hp, mon.status = 105, -20, "UNKNOWN"
  if Gen.ofState(S) == 3 then
    mon.ivs.hp, mon.language = 99, 6
    mon.evs.hp, mon.evs.atk, mon.evs.def = 255, 255, 100
  else
    mon.dvs.attack = 25
  end
  S.monSection, S.inspectorScroll = "main", 0
  shot("invalid-saved-main", 390, 844)
  S.monSection, S.inspectorScroll = "stats", 0
  shot("invalid-saved-stats", 390, 844)
  if Gen.ofState(S) == 3 then
    S.monSection, S.inspectorScroll = "origin", 0
    shot("invalid-saved-origin", 320, 568)
    S.inspectorScroll = 300
    shot("invalid-saved-language", 320, 568)
  end
  for k in pairs(mon) do mon[k] = nil end
  for k, v in pairs(originalMon) do mon[k] = v end
  S.monSection = "main"
  shot("selected-buttons", 390, 844)
  shot("rounded-buttons", 390, 844)
  S.tab = "dex"
  shot("rounded-actions", 390, 844)
  S.tab = "party"
  shot("desktop", 1280, 800)
  shot("landscape", 640, 360)
  popupShot("tab-menu", 360, 640, "tab")
  popupShot("page-popup-desktop", 1280, 800, "tab")
  popupShot("page-popup-landscape", 640, 360, "tab")
  popupShot("section-popup", 390, 844, "monSection")
  popupShot("section-popup-desktop", 1280, 800, "monSection")
  for _, entry in ipairs({
    { "items", "itemView" },
    { "boxes", "boxView" },
    { "events", "eventsTab" },
    { "map", "mapSection" },
  }) do
    S.tab = entry[1]
    S.pageScroll = {}
    popupShot(entry[1] .. "-popup", 390, 844, entry[2])
  end
  S.tab = "party"
  S.chromeMenu = true
  shot("more-menu", 360, 640)
  S.chromeMenu = false
  for _, picker in ipairs({ "species", "move", "held" }) do
    if picker == "species" then
      Ops.openSpeciesPicker(S, require("Kit"))
    elseif picker == "move" then
      Ops.openMovePicker(S, require("Kit"), 1)
    else
      Ops.openItemPicker(S, require("Kit"), "held")
    end
    shot("picker-" .. picker, 360, 640)
    Ops.closeSpeciesPicker(S, require("Kit"))
    Ops.closeMovePicker(S, require("Kit"))
    Ops.closeItemPicker(S, require("Kit"))
  end
  assert(App.save(), "scratch save writes for saved-button preview")
  shot("saved-button", 390, 844)
  S.allowSave = false
  shot("locked-save-button", 390, 844)
  S.allowSave = true
  local Motion = require("Motion")
  local Transition = require("src.ui.kit.Transition")
  local oldClock = love.timer.getTime
  local clock = 100
  love.timer.getTime = function()
    return clock
  end
  Transition.armed = true
  Transition.reduceMotion = false
  Motion.change(S, "monSection", "stats", 1)
  clock = 100.045
  shot("section-slide", 390, 844)
  clock = 100.20
  Motion.update()
  require("Kit").blockClicks = false
  Motion.change(S, "tab", "items", 1)
  clock = 100.245
  shot("tab-slide", 390, 844)
  Motion.reset()
  love.timer.getTime = oldClock
  assert(#labelFailures == 0, table.concat(labelFailures, "\n"))
  print("PASS complete button labels: " .. labelChecks .. " real-font layouts audited")
  App.unload()
  Paint.draw = realPaint
  os.remove(path)
  love.event.quit(0)
end
