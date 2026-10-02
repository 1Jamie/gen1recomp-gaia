package.path = package.path
  .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
_G.love = require("tests.love_stub")
local Ops = require("Ops")
local Kit = require("Kit")
local App = require("tools.save-editor.App")
local P = require("Properties")
local L = require("Legality")
local History = require("History")
local Copy = require("src.mods.Merge").deepCopy
local SD = require("src.core.SaveData")
local checks = 0
local function check(on, msg)
  checks = checks + 1
  assert(on, msg)
end
-- Exercise the actual paint dispatch for every layout below, including
-- selected, disabled and offscreen controls. Legacy raised-key overrides
-- and character arrows must never slip back through a forgotten panel.
local Paint = require("src.ui.kit.Button")
local Icons = require("src.ui.kit.Icons")
local realPaint, paintChecks = Paint.draw, 0
local labelFailures = {}
local function labelCheck(ok, message)
  if not ok then
    labelFailures[#labelFailures + 1] = message
  end
  assert(ok, message)
end
local navigationRects, saveRect, speciesY = {}, nil, nil
Paint.draw = function(owner, x, y, w, h, label, opts, hot, focused)
  if owner == Kit then
    if opts.id and opts.id:match("^navigate%-") then
      navigationRects[opts.id:sub(10)] = { x = x, y = y, w = w, h = h }
    end
    if opts.icon == "save" then
      saveRect = { x = x, y = y, w = w, h = h }
    end
    if label == "Change species" then
      speciesY = y
    end
    local theme = require("Theme")
    assert(
      opts.emboss == false
        and opts.radius == theme.radius()
        and opts.segments == theme.CONTROL.segments,
      "legacy or coarse button shape"
    )
    assert(not opts.icon or Icons.has(opts.icon), "missing icon " .. tostring(opts.icon))
    assert(
      label ~= "<"
        and label ~= ">"
        and label ~= "v"
        and label ~= "^"
        and label ~= "+"
        and label ~= "-",
      "character icon"
    )
    assert(not label or not label:match(" v$"), "character dropdown caret")
    if label and label ~= "" then
      labelCheck(opts.labelLayout, "missing full label layout " .. label)
      local layout = opts.labelLayout
      labelCheck(opts.fullLabel, "button may truncate " .. label)
      labelCheck(layout.width <= layout.available + 1, "button word does not fit " .. label)
      labelCheck(layout.height <= h - 4 * Kit.scale + 1, "button label too tall " .. label)
      labelCheck(table.concat(layout.lines, " ") == label, "button label shortened " .. label)
    end
    assert(opts.face ~= "tab", "legacy filled tab face")
    if opts.face == "selection" then
      assert(opts.color == nil, "legacy selected tab tint")
    end
    paintChecks = paintChecks + 1
  end
  return realPaint(owner, x, y, w, h, label, opts, hot, focused)
end
-- The selected paint must stay on the same dark surface, including old
-- call sites that still request the retired tab face.
local SharedTheme = require("src.ui.kit.Theme")
local oldFill, fills = SharedTheme.fillRounded, {}
SharedTheme.fillRounded = function(x, y, w, h, color, alpha, radius, segments)
  fills[#fills + 1] = color
  return oldFill(x, y, w, h, color, alpha, radius, segments)
end
Kit.beginFrame(-1, -1, false, 0)
Kit.chip(0, 0, 100, 44, "Party", true)
check(fills[1] == SharedTheme.PAL.surface, "selected chip keeps the dark surface")
fills = {}
Kit.button(0, 0, 100, 44, "Selected", { face = "tab", active = true })
check(fills[1] == SharedTheme.PAL.surface, "legacy tab call uses the new selected face")
SharedTheme.fillRounded = oldFill
local oldStroke, strokes = SharedTheme.strokeRounded, {}
SharedTheme.strokeRounded = function(x, y, w, h, color, alpha, width, radius, segments)
  strokes[#strokes + 1] = color
  return oldStroke(x, y, w, h, color, alpha, width, radius, segments)
end
Kit.mouseX, Kit.mouseY = 10, 10
Kit.chip(0, 0, 100, 44, "Party", true)
check(strokes[#strokes] == SharedTheme.PAL.blue, "hover preserves the selected accent outline")
SharedTheme.strokeRounded = oldStroke
Kit.endFrame()
local path = os.tmpname() .. "-mobile-editor.lua"
local seed = SD.newGame()
local f = assert(io.open(path, "wb"))
f:write(SD.encode(seed))
f:close()
App.load(path, { version = "red", embedded = true })
local S = App.getState()
Ops.partyAdd(S)
Ops.selectParty(S, 1)
local mon = S.editingMon
local original = mon.level
Ops.setLevel(S, mon, original + 2)
check(History.undo(S), "undo succeeds")
check(S.save.party[1].level == original, "undo restores level")
check(History.redo(S), "redo succeeds")
check(S.save.party[1].level == original + 2, "redo restores level")
check(Ops.setTrainerProperty(S, "name", "ASH"), "trainer name changes")
check(not Ops.setTrainerProperty(S, "name", "12345678"), "overlong trainer name refused")
check(not Ops.setTrainerProperty(S, "id", "0/0"), "invalid trainer ID refused")
check(Ops.setStatExp(S, S.save.party[1], "speed", 65535), "stat experience can be edited")
check(not Ops.setStatExp(S, S.save.party[1], "speed", 65536), "stat experience cap enforced")
local clean = L.mon(S, S.save.party[1])
check(clean.errors == 0, "valid Gen 1 properties pass")
check(clean.status == "unchecked", "valid properties never claim encounter legality")
local bad = Copy(S.save.party[1])
bad.dvs.hp = (bad.dvs.hp + 1) % 16
check(L.mon(S, bad).errors > 0, "inconsistent HP DV detected")
bad = Copy(S.save.party[1])
bad.moves[2] = Copy(bad.moves[1])
check(L.mon(S, bad).errors > 0, "duplicate move detected")
local MonOps = require("MonOps")
check(
  MonOps.calcMaxPp(40, 3, 1) == 61 and MonOps.calcMaxPp(40, 3, 2) == 61,
  "GB PP-Up bonus caps at seven"
)
check(MonOps.calcMaxPp(40, 3, 3) == 64, "GBA uses its own PP-Up bonus")
bad = Copy(S.save.party[1])
bad.moves[1] = { id = "GROWL", pp = 64, ppUps = 3, maxPp = 64 }
check(L.mon(S, bad).errors > 0, "GB PP beyond 61 is rejected")
MonOps.setPpUps(S.data, bad, 1, 3, 1)
MonOps.setPp(S.data, bad, 1, 64, 1)
check(bad.moves[1].pp == 61 and bad.moves[1].maxPp == 61, "GB PP edits respect native cap")
local before = #S.undoStack
Ops.setTrainerProperty(S, "id", "wrong")
check(#S.undoStack == before, "refused edit creates no history")
S.save.party[1].unknownMetadata = { sentinel = "preserve" }
Ops.cloneMonToBox(S, S.save.party[1])
check(S.editingMon.unknownMetadata.sentinel == "preserve", "cloning preserves unknown metadata")

-- An outside tap lowers mobile keyboard even on blank space. A second field
-- takes focus without lowering it in between; UTF-8 deletion removes a glyph.
local calls = {}
love.system.getOS = function()
  return "Android"
end
love.keyboard.setTextInput = function(on)
  calls[#calls + 1] = on
end
Kit.layout(360, 640)
Kit.beginFrame(20, 20, true, 0)
Kit.textfield("first", 0, 0, 120, 44, "", "")
Kit.endFrame()
check(Kit.focus == "first" and calls[#calls] == true, "tap raises keyboard")
Kit.beginFrame(300, 600, true, 0)
Kit.textfield("first", 0, 0, 120, 44, "", "")
Kit.endFrame()
check(Kit.focus == nil and calls[#calls] == false, "blank tap closes keyboard")
Kit.focus = "utf"
Kit.beginFrame(-1, -1, false, 0)
Kit.keypressed("backspace")
local utf = Kit.textfield("utf", 0, 0, 120, 44, "Aé", "")
Kit.endFrame()
check(utf == "A", "backspace removes one UTF-8 glyph")
Kit.blur()

-- Reload is a fresh history boundary on Gen 1/2 as well as Gen 3. Stale
-- form values and undo snapshots must never overwrite the file just loaded.
check(App.save(), "scratch save writes before reload")
Ops.setTrainerProperty(S, "name", "MISTY")
S.trainerDrafts = { name = "STALE" }
Ops.openItemPicker(S, Kit, "bag")
local revision = S.revision
check(App.reload(), "reload succeeds")
check(S.save.player.name == "ASH", "reload restores saved trainer")
check(#S.undoStack == 0 and #S.redoStack == 0 and not S.dirty, "reload clears history")
check(S.itemPicker == nil and Kit.focus == nil, "reload closes picker and keyboard")
check(
  next(S.trainerDrafts) == nil and S.revision > revision,
  "reload clears drafts and check cache"
)
check(not History.undo(S), "undo cannot revive edits from before reload")
Ops.selectParty(S, 1)

-- Audit every visible control at phone, landscape and desktop sizes,
-- including all inspector sections at several scroll positions.
local function clipped(r)
  local x1, y1, x2, y2 = r.x, r.y, r.x + r.w, r.y + r.h
  if r.clip then
    x1 = math.max(x1, r.clip.x)
    y1 = math.max(y1, r.clip.y)
    x2 = math.min(x2, r.clip.x + r.clip.w)
    y2 = math.min(y2, r.clip.y + r.clip.h)
  end
  if x2 <= x1 or y2 <= y1 then
    return
  end
  return x1, y1, x2, y2
end
local function frame(label, W, H)
  label = label .. " " .. W .. "x" .. H
  Kit.audit = {}
  App.draw()
  local list, scrollbars = {}, {}
  for _, r in ipairs(Kit.audit) do
    if r.class == "control" or r.class == "row" then
      local x1, y1, x2, y2 = clipped(r)
      if x1 then
        check(
          r.w >= 43.9 and r.h >= 43.9,
          label .. ": undersized " .. r.label .. " " .. r.w .. "x" .. r.h
        )
        check(
          x1 >= -0.5 and y1 >= -0.5 and x2 <= W + 0.5 and y2 <= H + 0.5,
          label .. ": outside window " .. r.label
        )
        if r.class == "control" then
          list[#list + 1] = r
        end
      end
    elseif r.class == "scrollbar" then
      local x1, y1, x2, y2 = clipped(r)
      if x1 then
        check(x1 >= 0 and x2 <= W and y1 >= 0 and y2 <= H, label .. ": scrollbar outside window")
        scrollbars[#scrollbars + 1] = r
      end
    end
  end
  for _, bar in ipairs(scrollbars) do
    local bx1, by1, bx2, by2 = clipped(bar)
    for _, control in ipairs(list) do
      local cx1, cy1, cx2, cy2 = clipped(control)
      check(
        math.min(bx2, cx2) <= math.max(bx1, cx1) or math.min(by2, cy2) <= math.max(by1, cy1),
        label .. ": scrollbar paints over " .. control.label
      )
    end
  end
  for i, a in ipairs(list) do
    local ax1, ay1, ax2, ay2 = clipped(a)
    for j = i + 1, #list do
      local bx1, by1, bx2, by2 = clipped(list[j])
      check(
        math.min(ax2, bx2) - math.max(ax1, bx1) <= 1 or math.min(ay2, by2) - math.max(ay1, by1) <= 1,
        label .. ": overlap " .. a.label .. " / " .. list[j].label
      )
    end
  end
  Kit.audit = nil
end
for _, size in ipairs({
  { 320, 568 },
  { 360, 640 },
  { 390, 844 },
  { 720, 480 },
  { 640, 360 },
  {
    1280,
    720,
  },
}) do
  local W, H = size[1], size[2]
  love.graphics.getDimensions = function()
    return W, H
  end
  love.window.getSafeArea = function()
    return 0, 0, W, H
  end
  for _, tab in ipairs({ "party", "boxes", "items", "events", "dex", "map", "trainer", "legality" }) do
    S.tab = tab
    S.pageScroll = {}
    frame(tab, W, H)
  end
  S.tab = "party"
  S.editingMon = S.save.party[1]
  S.mobileInspector = true
  for _, section in ipairs({ "main", "stats", "moves", "origin", "extras", "checks" }) do
    S.monSection = section
    for _, offset in ipairs({ 0, 120, 300, 600, 10000 }) do
      S.inspectorScroll = offset
      frame(section, W, H)
    end
  end
  S.tab = "map"
  for _, section in ipairs({ "maps", "view", "spawn" }) do
    S.mapSection = section
    frame("map " .. section, W, H)
    S.mapSpawnScroll = 10000
    frame("map scrolled " .. section, W, H)
  end
  S.mapSection, S.mapFocused = "view", true
  frame("focused landscape map", W, H)
  S.mapFocused = false
  S.chromeMenu = true
  frame("More menu", W, H)
  S.chromeMenu = false
  S.tab = "party"
  S.editingMon = S.save.party[1]
  for _, picker in ipairs({ "species", "move", "held" }) do
    if picker == "species" then
      Ops.openSpeciesPicker(S, Kit)
    elseif picker == "move" then
      Ops.openMovePicker(S, Kit, 1)
    else
      Ops.openItemPicker(S, Kit, "held")
    end
    App.draw()
    frame("picker " .. picker, W, H)
    Ops.closeSpeciesPicker(S, Kit)
    Ops.closeMovePicker(S, Kit)
    Ops.closeItemPicker(S, Kit)
  end
  S.tab = "items"
  for _, view in ipairs({ "bag", "pc", "wallet", "badges" }) do
    S.itemView = view
    frame(view, W, H)
  end
  S.itemView = "bag"
  for _, menu in ipairs({ "tools" }) do
    S.itemMenu = menu
    frame("item menu " .. menu, W, H)
  end
  S.itemMenu = nil
  -- Full-text bulk tools use the same modal shield as navigation, while
  -- choosing a sort remains a view change and never edits the save.
  S.tab, S.pageScroll = "dex", {}
  navigationRects = {}
  frame("Pokédex full labels", W, H)
  local dexActions = assert(navigationRects.dexActions, "missing Pokédex action menu")
  local beforeDexMenu = SD.encode(S.save)
  App.mousepressed(dexActions.x + dexActions.w / 2, dexActions.y + dexActions.h / 2, 1)
  App.draw()
  check(S.navPopup and S.navPopup.mode == "actions", "Pokédex tools open as actions")
  check(#S.navPopup.options == 6, "all Gen 1 Pokédex tools remain available")
  frame("Pokédex action labels", W, H)
  check(SD.encode(S.save) == beforeDexMenu, "opening tools never edits the save")
  App.keypressed("end")
  App.keypressed("return")
  check(S.dexSort == "name" and S.navPopup == nil, "keyboard chooses the full-name sort")
  check(S.dexActions == nil and SD.encode(S.save) == beforeDexMenu, "sort only changes the view")
  -- Open the real dropdown controls, rather than setting a menu flag. Each
  -- chooser overlays a stable page and exposes only its own touch targets.
  for _, case in ipairs({
    { "party", "tab", 8 },
    { "party", "monSection", 6 },
    { "items", "itemView", 4 },
    { "boxes", "boxView", 2 },
    { "events", "eventsTab", 4 },
    { "map", "mapSection", 3 },
  }) do
    S.tab, S.monSection, S.itemView, S.boxView, S.mapSection =
      case[1], "main", "bag", "storage", "view"
    S.mobileInspector, S.inspectorScroll, S.pageScroll = true, 0, {}
    navigationRects = {}
    frame("dropdown page " .. case[2], W, H)
    local rect = navigationRects[case[2]]
    if rect then
      local previous, selected, anchor = S[case[2]], S.editingMon, speciesY
      Kit.focus = "property-level"
      App.mousepressed(rect.x + rect.w / 2, rect.y + rect.h / 2, 1)
      App.draw()
      check(S.navPopup and S.navPopup.key == case[2], "dropdown opens " .. case[2])
      check(#S.navPopup.options == case[3], "all destinations remain available " .. case[2])
      check(S[case[2]] == previous and Kit.focus == nil, "opening only blurs text focus")
      if case[2] == "monSection" then
        check(speciesY == anchor, "opening section chooser keeps the form in place")
      end
      frame("popup " .. case[2], W, H)
      App.keypressed("escape")
      check(not S.navPopup and S[case[2]] == previous, "Escape cancels " .. case[2])
      check(S.editingMon == selected, "Escape preserves the Pokemon selection")
    else
      check(case[2] == "mapSection" and W > H, "only the simultaneous map columns omit a chooser")
    end
  end
end

-- Short landscape popups scroll to the keyboard choice; clicks outside
-- dismiss without reaching Save, and choosing a destination is view state.
love.graphics.getDimensions = function()
  return 640, 360
end
love.window.getSafeArea = function()
  return 0, 0, 640, 360
end
S.tab, S.mobileInspector = "party", true
App.draw()
local rect = navigationRects.tab
App.mousepressed(rect.x + rect.w / 2, rect.y + rect.h / 2, 1)
App.draw()
local realSave, saved = App.save, 0
App.save = function()
  saved = saved + 1
end
App.mousepressed(saveRect.x + saveRect.w / 2, saveRect.y + saveRect.h / 2, 1)
App.draw()
check(saved == 0 and S.navPopup == nil, "outside tap dismisses without activating Save underneath")
App.save = realSave
App.draw()
rect = navigationRects.tab
App.mousepressed(rect.x + rect.w / 2, rect.y + rect.h / 2, 1)
App.draw()
App.keypressed("end")
App.draw()
check(
  S.navPopup.scroll > 0 and S.navPopup.index == 8,
  "keyboard reveals the final page on a short screen"
)
local historyCount, beforeNavigation = #S.undoStack, SD.encode(S.save)
App.keypressed("return")
check(S.tab == "legality" and S.navPopup == nil, "Enter chooses the highlighted page")
check(
  #S.undoStack == historyCount and SD.encode(S.save) == beforeNavigation,
  "navigation never edits save data"
)
require("Motion").reset()
Kit.blockClicks = false

-- A notched safe area bounds the popup itself, while the scrim still covers
-- the entire window. Selecting the current page just closes the popup.
S.tab, S.mobileInspector = "party", true
love.graphics.getDimensions = function()
  return 390, 844
end
love.window.getSafeArea = function()
  return 0, 47, 390, 763
end
App.draw()
rect = navigationRects.tab
App.mousepressed(rect.x + rect.w / 2, rect.y + rect.h / 2, 1)
App.draw()
frame("safe-area popup", 390, 844)
local popup = S.navPopup
check(
  popup.rect.y >= 47 and popup.rect.y + popup.rect.h <= 810,
  "popup clears notch and home indicator"
)
App.keypressed("return")
check(
  S.tab == "party" and not S.navPopup and not require("Motion").active(),
  "current choice closes without a slide"
)

-- Option taps change the intended nested screen. A drag inside a short
-- popup scrolls the options without selecting the row under its release.
App.draw()
rect = navigationRects.monSection
App.mousepressed(rect.x + rect.w / 2, rect.y + rect.h / 2, 1)
App.draw()
Kit.audit = {}
App.draw()
local stats
for _, control in ipairs(Kit.audit) do
  if control.label == "Stats" then
    stats = control
  end
end
Kit.audit = nil
check(stats ~= nil, "section popup exposes Stats")
App.mousepressed(stats.x + stats.w / 2, stats.y + stats.h / 2, 1)
App.draw()
check(S.monSection == "stats" and S.navPopup == nil, "option tap changes the nested section")
require("Motion").reset()
Kit.blockClicks = false
love.graphics.getDimensions = function()
  return 640, 360
end
love.window.getSafeArea = function()
  return 0, 0, 640, 360
end
S.tab, S.mapSection, S.mapZoom = "map", "view", 2
App.draw()
rect = navigationRects.tab
App.mousepressed(rect.x + rect.w / 2, rect.y + rect.h / 2, 1)
App.draw()
App.draw()
popup = S.navPopup
local px, py = popup.rect.x + popup.rect.w / 2, popup.rect.y + popup.rect.h - 50
App.touchpressed("popup-drag", px, py)
App.draw()
App.touchmoved("popup-drag", px, py - 80)
App.draw()
App.touchreleased("popup-drag", px, py - 80)
App.draw()
check(
  S.navPopup and S.navPopup.scroll > 0 and S.tab == "map",
  "popup drag scrolls without activating a page"
)
local previousPointer = love.mouse.getPosition
love.mouse.getPosition = function()
  return px, py - 80
end
App.wheelmoved(0, -1)
App.draw()
check(S.mapZoom == 2, "popup wheel never zooms the map underneath")
love.mouse.getPosition = previousPointer
App.mousepressed(1, 1, 1)
App.draw()
check(S.navPopup == nil and S.tab == "map", "outside tap cancels without changing page")

-- Dragging a touch scrolls without queuing an activation. Tapping fires once
-- on release, on both mobile platforms.
love.graphics.getDimensions = function()
  return 360, 640
end
love.window.getSafeArea = function()
  return 0, 0, 360, 640
end
S.tab, S.mobileInspector = "party", true
S.monSection = "stats"
S.inspectorScroll = 0
App.draw()
App.touchpressed("finger", 160, 550)
App.draw()
App.touchmoved("finger", 160, 470)
App.draw()
App.touchreleased("finger", 160, 470)
App.draw()
check(S.inspectorScroll > 0, "touch drag scrolls inspector")
check(Kit.focus == nil, "touch drag does not activate a field")
-- A mobile IME can deliver text and Enter in the same frame. Picker
-- commits must use that final query instead of the prior draw's string.
Ops.openItemPicker(S, Kit, "bag")
local potionId = assert(Ops.itemSearch(S, "potion")[1], "dataset has a potion search result")
local potion = S.save.inventory[potionId] or 0
App.textinput("potion")
App.keypressed("return")
check(S.save.inventory[potionId] == potion + 1, "picker Enter includes queued search typing")
Ops.closeItemPicker(S, Kit)

-- Navigation animates two clipped pages using the same transition engine
-- as the launcher, blocks actions in flight and honors reduced motion.
local Motion = require("Motion")
local Transition = require("src.ui.kit.Transition")
local oldClock = love.timer.getTime
local clock = 10
love.timer.getTime = function()
  return clock
end
Transition.armed = true
Transition.reduceMotion = false
Motion.reset()
Kit.blockClicks = false
local state = { monSection = "main", inspectorScroll = 120 }
check(Motion.change(state, "monSection", "stats", 1), "section starts navigation")
check(state.inspectorScroll == 0 and Kit.focus == nil, "navigation clears focus and scroll")
local drawn = {}
local function page(st, kit, x, y, w, h)
  drawn[#drawn + 1] =
    { section = st.monSection, x = x, scroll = st.inspectorScroll, clip = kit._clipRect }
  check(not kit.press(x, y, w, h), "moving page cannot dispatch an action")
end
Kit.beginFrame(20, 20, true, 0)
clock = 10.09
Motion.update()
Motion.pages(state, Kit, "monSection", 0, 0, 320, 200, page)
check(#drawn == 2, "slide draws outgoing and incoming pages")
check(drawn[1].section == "main" and drawn[2].section == "stats", "slide draws the correct pages")
check(drawn[1].x < 0 and drawn[2].x > 0, "forward slide moves left from the right")
check(drawn[1].scroll == 120 and drawn[2].scroll == 0, "outgoing scroll is preserved")
check(
  drawn[1].clip.w == 320 and state.monSection == "stats",
  "slide clips and restores current section"
)
clock = 10.19
Motion.update()
check(not Motion.active(), "slide completes at launcher duration")
Kit.blockClicks = false
check(Motion.change(state, "monSection", "main", -1), "back navigation starts")
clock = 10.28
Motion.update()
drawn = {}
Motion.pages(state, Kit, "monSection", 0, 0, 320, 200, page)
check(drawn[1].x > 0 and drawn[2].x < 0, "back slide reverses direction")
Motion.reset()
Kit.blockClicks = false
Transition.reduceMotion = true
check(Motion.change(state, "monSection", "origin", 1), "reduced-motion navigation changes section")
check(not Motion.active(), "reduced motion switches instantly")
Transition.reduceMotion = false
Transition.armed = false
love.timer.getTime = oldClock
Kit.blockClicks = false
Kit.endFrame()

-- Enter includes the last queued nickname characters even without a draw
-- between textinput and keypressed.
S.editingMon = S.save.party[1]
S.nicknameDraft = "A"
Kit.focus = "mon-nickname"
App.textinput("SH")
App.keypressed("return")
check(S.editingMon.nickname == "ASH", "Enter drains queued nickname typing")
-- Bulk tools dispatch the real editor mutations. Wipe retains its two-tap
-- confirmation, and undo restores the dex after choosing the popup action.
S.tab, S.pageScroll = "dex", {}
love.graphics.getDimensions = function()
  return 390, 844
end
love.window.getSafeArea = function()
  return 0, 0, 390, 844
end
local function dexTool(label)
  App.draw()
  local trigger = navigationRects.dexActions
  App.mousepressed(trigger.x + trigger.w / 2, trigger.y + trigger.h / 2, 1)
  App.draw()
  Kit.audit = {}
  App.draw()
  local target
  for _, control in ipairs(Kit.audit) do
    if control.class == "control" and control.label == label then
      target = control
    end
  end
  Kit.audit = nil
  check(target ~= nil, "full Pokédex action available: " .. label)
  App.mousepressed(target.x + target.w / 2, target.y + target.h / 2, 1)
  App.draw()
  check(S.navPopup == nil, "choosing an action closes the popup")
end
dexTool("Own all")
local seen, owned, total = Ops.dexCounts(S)
check(seen == total and owned == total, "Own all still marks the complete dex")
dexTool("Wipe Pokédex")
seen, owned = Ops.dexCounts(S)
check(S.armed == "dex-clear" and owned == total, "first wipe tap only arms confirmation")
dexTool("Confirm?")
seen, owned = Ops.dexCounts(S)
check(seen == 0 and owned == 0, "confirmed wipe clears both flags")
check(History.undo(S), "confirmed wipe is undoable")
seen, owned = Ops.dexCounts(S)
check(seen == total and owned == total, "undo restores seen and owned")
App.unload()
os.remove(path)
Paint.draw = realPaint
check(
  #labelFailures == 0,
  "button labels failed inside a guarded panel: " .. table.concat(labelFailures, "; ")
)
check(paintChecks > 1000, "paint audit exercised the page and selection states")
print(
  "save editor mobile properties: "
    .. checks
    .. " checks passed; "
    .. paintChecks
    .. " button paints audited"
)
