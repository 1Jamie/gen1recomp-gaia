-- The launcher's view, drawn with the shared immediate-mode kit
-- (src/ui/kit/).  RomImporter owns every piece of state and all
-- import/platform logic; this module paints that state once per frame, so the
-- UI can never drift from the importer and every window size lays out fresh.
--
-- WHAT CHANGED, AND WHY.  This used to build a retained FlexLove element tree
-- every frame.  That cost ~9ms of build+draw on a real profile before a
-- single row of content existed (measure it yourself: POKEPORT_LAUNCHER_PROF=
-- 200 love .), because the engine hashed props per element, snapshotted every
-- public scalar for its immediate-mode persistence, and re-ran an O(n^2)
-- auto-size pass.  Painting the same screen directly is a small fraction of
-- that, and it removes a whole class of layout bug along with it: percentage
-- widths resolving against the wrong box, auto-sized buttons measuring zero
-- height, and flex-shrink compressing text until it overlapped.
--
-- THE RULES THIS FILE FOLLOWS:
--   * NO SCROLLING.  Every list paginates (Kit.pager).  Rows per page come
--     from the real viewport height, so a tall window shows more and a phone
--     shows fewer -- but a page's row count is bounded either way, which is
--     what makes a 500-mod index cost the same as a 10-mod one.
--   * Every click handler only QUEUES work (imp._uiActions); update() drains
--     the queue, so an action that tears the view down (Play, Edit save)
--     never runs inside the frame that dispatched it.
--   * Clicks are deduped per control key: a touch tap can surface as both a
--     touch release and a synthesized mouse click, and one action must not
--     fire twice (the shape of #553's double import).
--   * Anything that waits raises a non-dismissable loader (Loader.overlay),
--     driven by imp._busy / imp.workState.
--   * Layout is explicit pixels off Layout.metrics.  No percentages.

local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Layout = require("src.ui.kit.Layout")
local Loader = require("src.ui.kit.Loader")
local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")

local PAL = Theme.PAL
local LauncherView = {}

local COMMUNITY_URL = "https://bois.icu"

-- One dedup window covers a touch release plus the mouse click SDL
-- synthesizes for the same tap.
local ACT_DEDUP = 0.35
-- Finger travel past this (px) is a drag, not a tap.
local TAP_SLOP2 = 16 * 16

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ------------------------------------------------------------- lifecycle

local function ensureState(imp)
  if not imp._flex then
    imp._flex = true
    imp._hot = imp._hot or {}
    imp._actAt = imp._actAt or {}
    imp._uiActions = imp._uiActions or {}
    imp._pages = imp._pages or {}
    -- Held backspace/arrows must repeat in the text fields; restored on
    -- detach because the game's Input does its own per-step edge detection
    -- and never expects repeated keypressed events.
    if love.keyboard and love.keyboard.setKeyRepeat then
      pcall(love.keyboard.setKeyRepeat, true)
    end
  end
end

-- Kept as a no-op hook: the engine tier asserts this exists, and the guards
-- it used to apply were FlexLove's (performance monitoring, GC tuning).  The
-- kit has neither a profiler nor a GC strategy to tune -- it does not
-- allocate per frame -- so there is nothing left to guard.
function LauncherView.applyNxPerfGuards(imp)
  return imp ~= nil
end

-- Tear down before handing the screen to the game / editor.
function LauncherView.detach(imp)
  -- Restore the NX mouse shim even if _flex was never set (the bridge can
  -- install on the first update before the first draw).
  if imp and imp.parkNxPointerForHost then
    pcall(imp.parkNxPointerForHost, imp)
  elseif imp and imp._restoreNxPointerBridge then
    pcall(imp._restoreNxPointerBridge, imp)
  end
  if not imp or not imp._flex then return end
  imp._flex = nil
  if love.keyboard and love.keyboard.setKeyRepeat then
    pcall(love.keyboard.setKeyRepeat, false)
  end
  Kit.clearCaches()
end

-- ---------------------------------------------------------------- input
-- The kit is polled, not evented: update() samples the mouse and turns a
-- rising edge into a click point that the next draw consumes.  Host-forwarded
-- mousepressed stays unused, exactly as before, so Android's synthesized
-- mouse path cannot double-fire a tap (#553) -- the dedup window below is the
-- other half of that guarantee.
function LauncherView.update(imp, dt)
  if not imp._flex then return end

  local down = false
  if love.mouse and love.mouse.isDown then
    down = love.mouse.isDown(1) and true or false
  end
  if down and not imp._prevMouseDown and not imp._padCursorActive then
    local mx, my = love.mouse.getPosition()
    imp._clickPt = { x = mx, y = my }
  end
  imp._prevMouseDown = down

  -- Drain the action queue OUTSIDE the draw, so an action is free to destroy
  -- the view (Play/Edit) or block in a native picker.  The batch is resolved
  -- by RomImporter:runActions so the drop/disarm rules stay testable without
  -- a live view (#780).
  local queue = imp._uiActions
  if queue and #queue > 0 then
    imp._uiActions = {}
    imp:runActions(queue)
  end
end

function LauncherView.wheelmoved(imp, dx, dy)
  if not imp._flex then return end
  imp._wheelY = (imp._wheelY or 0) + (dy or 0)
end

function LauncherView.touchpressed(imp, id, x, y)
  if not imp._flex then return end
  imp._touchAt = imp._touchAt or {}
  imp._touchAt[tostring(id)] = { x = x, y = y }
end

function LauncherView.touchmoved(imp, id, x, y)
  if not imp._flex then return end
  local start = imp._touchAt and imp._touchAt[tostring(id)]
  if start then
    local ddx, ddy = x - start.x, y - start.y
    if ddx * ddx + ddy * ddy > TAP_SLOP2 then
      start.dragged = true
    end
  end
end

-- A tap dispatches on RELEASE (not press) so a drag can disqualify it.
function LauncherView.touchreleased(imp, id, x, y)
  if not imp._flex then return end
  local start = imp._touchAt and imp._touchAt[tostring(id)]
  if imp._touchAt then imp._touchAt[tostring(id)] = nil end
  if start and start.dragged then
    -- Suppress the mouse click SDL will synthesize for this same gesture.
    imp._suppressClickUntil = love.timer.getTime() + ACT_DEDUP
    return
  end
  imp._clickPt = { x = x, y = y }
end

-- Synthetic click for the gamepad virtual cursor.
function LauncherView.clickAt(imp, x, y)
  if not imp._flex then return end
  imp._clickPt = { x = x, y = y }
end

-- Keyboard focus ring.  Returns true when the key was consumed.  Arrows arm
-- the ring; Enter only activates a focused control once the user has actually
-- used the arrows this session, so the long-standing "Enter plays the visible
-- game" shortcut keeps working for anyone who never touches the ring.
function LauncherView.keypressed(imp, key)
  if not imp._flex then return false end
  if key == "up" or key == "down" or key == "left" or key == "right" then
    imp._ringArmed = true
    Kit.navigate(key)
    return true
  end
  if imp._ringArmed and (key == "return" or key == "kpenter" or key == "space") then
    Kit.activateFocused()
    return true
  end
  return false
end

-- ------------------------------------------------------------- actions

local function queueAction(imp, key, fn, keepArm)
  local now = love.timer.getTime()
  local last = imp._actAt[key]
  if last and now - last < ACT_DEDUP then return end
  local untilT = imp._suppressClickUntil
  if untilT and now < untilT then return end
  imp._actAt[key] = now
  -- Any press that is not a Delete's own second click disarms the pending
  -- delete confirm (#433's rule).  The disarm is applied by runActions when
  -- the batch drains, not here: one touch lands on a row AND on the chip
  -- inside it, and clearing the arm as the row queued left Delete stuck on
  -- its first press (#780).
  imp._uiActions[#imp._uiActions + 1] = { key = key, fn = fn, keepArm = keepArm }
end

-- Every interactive control in this file goes through one of these two, so
-- the queueing and dedup rules cannot be forgotten at a call site.
local function btn(imp, x, y, w, h, key, label, opts)
  opts = opts or {}
  opts.id = key
  if Kit.button(x, y, w, h, label, opts) and opts.action then
    queueAction(imp, key, opts.action, opts.keepArm)
  end
end

local function rowHit(imp, x, y, w, h, selected, key, action)
  local clicked, ink = Kit.row(x, y, w, h, selected, key)
  if clicked and action then queueAction(imp, key, action) end
  return ink
end

-- ------------------------------------------------------- shared widgets

-- Read-only text field.  The importer owns the string (its textinput /
-- keypressed routing writes it); this only renders it, keeps the TAIL
-- visible while typing, and blinks a caret on the importer's pulse clock.
local function textField(imp, x, y, w, h, key, rawText, placeholder, focused, action)
  Kit._audit("control", x, y, w, h, key)
  Kit.focusable(key, x, y, w, h)
  Theme.fill(x, y, w, h, PAL.bg, 1)
  Theme.stroke(x, y, w, h, PAL.line,
    focused and Theme.A.focus or
      (Kit.hover(x, y, w, h) and Theme.A.hover or Theme.A.hairline),
    focused and 2 or 1)
  local pad = math.floor(10 * Kit.scale)
  local ty = y + (h - Kit.textHeight("button")) / 2
  local text = rawText or ""
  if text == "" and not focused then
    Kit.text("button", Kit.ellipsize("button", placeholder or "", w - 2 * pad),
      x + pad, ty, PAL.faint)
  else
    local shown = Kit.ellipsizeLeft("button", text, w - 2 * pad)
    local tw = Kit.text("button", shown, x + pad, ty, PAL.heading)
    if focused and (imp.pulse * 2 % 1) < 0.5 then
      Theme.fill(x + pad + tw + 2, ty, math.max(1, Kit.scale),
        Kit.textHeight("button"), PAL.ink, 1)
    end
  end
  if action and (Kit.press(x, y, w, h) or Kit._activateId == key) then
    queueAction(imp, key, action)
  end
end

-- A filter/sort pill row that wraps.  Returns the height consumed.
local function chipRow(imp, x, y, w, m, items)
  local gap = math.floor(6 * m.s)
  local h = math.max(Kit.tapMin(), math.floor(28 * m.s))
  local cx, cy = x, y
  for _, it in ipairs(items) do
    local cw = Kit.textWidth("micro", it.label) + math.floor(20 * m.s)
    if cx > x and cx + cw > x + w then
      cx = x
      cy = cy + h + gap
    end
    if Kit.chip(cx, cy, cw, h, it.label, it.active, it.color, it.key) then
      queueAction(imp, it.key, it.action)
    end
    cx = cx + cw + gap
  end
  return (cy - y) + h
end

local function modStatusColor(status)
  if status == "ok" then return Strings("Ready"), PAL.green end
  if status == "conflict" then return Strings("Conflict"), PAL.red end
  return Strings("Incompatible"), PAL.yellow
end

local function findActionFor(entry, installedVersion)
  local ModIndex = require("src.mods.ModIndex")
  if not ModIndex.canInstall(entry) then
    return nil, Strings("Not installable from this index")
  end
  if not installedVersion then return Strings("Install"), nil end
  local listed = ModIndex.displayVersion(entry)
  local ModUpdate = require("src.mods.ModUpdate")
  if type(installedVersion) == "string"
      and ModUpdate.isNewer(installedVersion, listed) then
    return Strings("Update"), "Installed v" .. installedVersion
  end
  return Strings("Reinstall"), "Installed v" .. tostring(installedVersion)
end

local function DELETE_LABEL(armed)
  return armed and Strings("Sure?") or Strings("Delete")
end

local function deleteArmed(imp, kind, id, version)
  local a = imp._confirmDelete
  return a ~= nil and a.kind == kind and a.id == id and a.version == version
end

-- Page state lives on the importer keyed by list, so switching tabs and
-- coming back keeps your place -- the one thing scrolling did better.
local function page(imp, key)
  return imp._pages[key] or 1
end

local function setPage(imp, key, v)
  imp._pages[key] = v
end

-- ------------------------------------------------------------- header
-- Rail, logo row (update + settings on the right), tab bar.
-- Returns the y at which content may start.
local function buildHeader(imp, m)
  local y = m.top
  Theme.versionRail(m.x, y, m.w, m.railH)
  y = y + m.railH

  -- logo row
  local rowH = m.logoH + math.floor(12 * m.s)
  local gear = m.chip
  local gap = math.floor(8 * m.s)

  -- The logo is centred in the FULL row, then the right cluster is drawn over
  -- its own reserved space, so the wordmark never drifts as buttons appear.
  if imp.logo then
    local lw, lh = imp.logo:getDimensions()
    local maxW = math.min(320 * m.s, m.w * 0.55)
    local scale = math.min(maxW / lw, m.logoH / lh)
    local dw, dh = lw * scale, lh * scale
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(imp.logo, Theme.snap(m.x + (m.w - dw) / 2),
      Theme.snap(y + (rowH - dh) / 2), 0, scale, scale)
  end

  local rx = m.x + m.w - m.pad
  local by = y + (rowH - gear) / 2

  -- Settings gear, top-right corner.
  imp._gearIcon = imp._gearIcon
    or love.graphics.newImage("assets/launcher/gear.png")
  rx = rx - gear
  do
    local x = rx
    Kit._audit("control", x, by, gear, gear, "gear")
    local focused = Kit.focusable("gear", x, by, gear, gear)
    local hot = focused or Kit.hover(x, by, gear, gear)
    Theme.fill(x, by, gear, gear, hot and PAL.ink or PAL.bg, 1)
    Theme.stroke(x, by, gear, gear, PAL.line,
      hot and Theme.A.focus or Theme.A.hairline, 1)
    local iw, ih = imp._gearIcon:getDimensions()
    local pad = math.floor(gear * 0.22)
    local s = math.min((gear - 2 * pad) / iw, (gear - 2 * pad) / ih)
    if hot then love.graphics.setColor(0, 0, 0, 1)
    else love.graphics.setColor(1, 1, 1, 0.85) end
    love.graphics.draw(imp._gearIcon, Theme.snap(x + (gear - iw * s) / 2),
      Theme.snap(by + (gear - ih * s) / 2), 0, s, s)
    love.graphics.setColor(1, 1, 1, 1)
    if Kit.press(x, by, gear, gear) or Kit._activateId == "gear" then
      queueAction(imp, "gear", function() imp:_openSettings() end)
    end
  end

  -- In-app update, immediately left of the gear.  It GLOWS (a pulsing
  -- outline, no extra draw calls -- see Kit.button) whenever there is
  -- something to act on, which is the whole point of moving it out of the
  -- old bottom-of-page banner: an update you never scrolled to was an update
  -- you never saw.
  local upStatus, upLabel, upAction, upGlow = LauncherView._updateControl(imp)
  if upStatus then
    local uw = Kit.textWidth("small", upLabel) + math.floor(24 * m.s)
    rx = rx - gap - uw
    btn(imp, rx, by, uw, gear, "updater", upLabel, {
      kind = upGlow and "warn" or "ghost", font = "small",
      glow = upGlow, action = upAction,
    })
  end
  y = y + rowH

  -- tab bar
  imp._modsIcon = imp._modsIcon
    or love.graphics.newImage("assets/launcher/mods.png")
  imp._findIcon = imp._findIcon
    or love.graphics.newImage("assets/launcher/find.png")
  -- The three game tabs keep their cartridge colours -- that is the one piece
  -- of brand identity in the launcher, and "the red one" is how people
  -- actually refer to these.  The colour rides the outline and the glyph at
  -- rest and becomes the fill when active, the same rule the buttons follow.
  local tabs = {
    { id = "red",    letter = "R", label = Strings("RED"),    color = PAL.railRed },
    { id = "blue",   letter = "B", label = Strings("BLUE"),   color = PAL.railBlue },
    { id = "yellow", letter = "Y", label = Strings("YELLOW"), color = PAL.railGold },
    { id = "mods",   icon = imp._modsIcon, label = Strings("MODS") },
    { id = "find",   icon = imp._findIcon, label = Strings("FIND MODS") },
  }
  local tabH = m.chip
  local tx = m.x + m.pad
  local ty = y + math.floor(6 * m.s)
  for _, t in ipairs(tabs) do
    local active = imp.tab == t.id
    local key = "tab-" .. t.id
    local labelW = Kit.textWidth("tab", t.label)
    -- The active tab spells its name out; inactive tabs are the glyph alone,
    -- so five tabs fit a phone width without wrapping.
    local w = active and (tabH + math.floor(8 * m.s) + labelW + math.floor(12 * m.s))
      or tabH
    Kit._audit("control", tx, ty, w, tabH, key)
    local focused = Kit.focusable(key, tx, ty, w, tabH)
    local hot = focused or Kit.hover(tx, ty, w, tabH)
    local invert = active or hot
    local tint = t.color or PAL.ink
    Theme.fill(tx, ty, w, tabH, invert and tint or PAL.bg, 1)
    if not invert then
      Theme.stroke(tx, ty, w, tabH, tint,
        t.color and Theme.A.hover or Theme.A.hairline, 1)
    end
    -- Ink on a filled tab must contrast with THAT fill: black on the light
    -- red/blue/gold cartridge colours, which are all high-luminance.
    local ink = invert and PAL.inverse or (t.color or PAL.text)
    if t.icon then
      local iw, ih = t.icon:getDimensions()
      local pad = math.floor(tabH * 0.24)
      local s = math.min((tabH - 2 * pad) / iw, (tabH - 2 * pad) / ih)
      if invert then love.graphics.setColor(0, 0, 0, 1)
      else love.graphics.setColor(1, 1, 1, 0.9) end
      love.graphics.draw(t.icon, Theme.snap(tx + (tabH - iw * s) / 2),
        Theme.snap(ty + (tabH - ih * s) / 2), 0, s, s)
      love.graphics.setColor(1, 1, 1, 1)
    else
      Kit.textCenter("tab", t.letter, tx,
        ty + (tabH - Kit.textHeight("tab")) / 2, tabH, ink)
    end
    if active then
      Kit.text("tab", t.label, tx + tabH + math.floor(4 * m.s),
        ty + (tabH - Kit.textHeight("tab")) / 2, ink)
    end
    if Kit.press(tx, ty, w, tabH) or Kit._activateId == key then
      queueAction(imp, key, function() imp:_switchTab(t.id) end)
    end
    tx = tx + w + math.floor(6 * m.s)
  end

  -- "N of 3 ready", right-aligned on the tab line.
  local ready = 0
  for _, v in ipairs(GameVersion.ORDER) do
    if imp.ready[v] then ready = ready + 1 end
  end
  Kit.textRight("small", Strings("%d of 3 ready", ready), m.x + m.w - m.pad,
    ty + (tabH - Kit.textHeight("small")) / 2, PAL.muted)

  y = ty + tabH + math.floor(8 * m.s)
  Theme.fill(m.x, y, m.w, 1, PAL.line, Theme.A.hairline)
  return y + math.floor(10 * m.s)
end

-- The state of the self-updater, as a top-right control.
-- Returns status, label, action, glow.
function LauncherView._updateControl(imp)
  if not imp.Check then return nil end
  local ok, st = pcall(imp.Check.state)
  st = (ok and type(st) == "table") and st or nil
  local status = st and st.status or "idle"
  if status == "checking" then
    return status, Strings("Checking..."), nil, false
  elseif status == "downloading" then
    local pct = st.progress and math.floor(st.progress * 100) or 0
    return status, Strings("Updating %d%%", pct), nil, false
  elseif status == "available" then
    return status, st.latest and (Strings("Update v") .. st.latest)
      or Strings("Update"), function() pcall(imp.Check.download) end, true
  elseif status == "ready" then
    return status, Strings("Restart to update"),
      function() require("src.core.HostShell").restart() end, true
  elseif status == "needs_full" then
    return status, Strings("Open releases"),
      function() love.system.openURL(imp.Check.releaseUrl()) end, true
  end
  -- idle / uptodate / error: offer a manual check, with no glow.
  return status, Strings("Check for updates"),
    function() pcall(imp.Check.start) end, false
end

-- ------------------------------------------------------------ game panel

local function buildRomCard(imp, x, y, w, m, version, info, ready, locked, maxH)
  local dropHint = imp.isNX and Strings("Copy the .gb/.gbc via MTP into imports/.")
    or (imp.android and Strings("Copy the .gb/.gbc via USB.")
      or Strings("Or drop the .gb/.gbc file here."))
  local importLabel = imp.isNX and Strings("Scan again") or Strings("Import ROM")
  local romState, romDetail, romBtnLabel, romBtnEnabled, romProgress
  if locked then
    romState, romDetail = Strings("Not supported yet"),
      Strings("Support for this game is on the way.")
    romBtnLabel, romBtnEnabled = Strings("Import unavailable"), false
  else
    local importing = imp.importing == version
    local erroring = imp.workState == "error" and imp.errorVersion == version
    local notice = imp.notice and imp.notice.version == version and imp.notice
    if importing and (imp.workState == "working" or imp.workState == "complete") then
      romState = imp.status or Strings("Importing")
      romDetail = imp.detail or ""
      romProgress = imp.progress or 0
    elseif ready then
      romState = imp.romName[version] or Strings("ROM imported")
      romDetail = Strings("Verified.")
      romBtnLabel, romBtnEnabled = Strings("Re-import ROM"), true
    elseif erroring then
      romState = Strings("Import failed")
      romDetail = imp.detail or Strings("That ROM could not be imported.")
      romBtnLabel, romBtnEnabled = importLabel, true
    elseif notice then
      romState = Strings("No ROM imported")
      romDetail = ((notice.status or "") .. " " .. (notice.detail or ""))
        :gsub("^%s+", ""):gsub("%s+$", "")
      romBtnLabel, romBtnEnabled = importLabel, true
    elseif imp.returning[version] then
      romState = Strings("Update required")
      romDetail = Strings("This build needs a few more things from your ")
        .. info.label .. Strings(" ROM. Re-import to continue.")
      romBtnLabel, romBtnEnabled = Strings("Re-import ROM"), true
    else
      romState = Strings("No ROM imported")
      romDetail = Strings("The ROM is verified before any files are created. ")
        .. dropHint
      romBtnLabel, romBtnEnabled = importLabel, true
    end
  end

  local pad = math.floor(14 * m.s)
  local iw = w - 2 * pad
  -- The card's fixed furniture always fits; the DETAIL text is the elastic
  -- part, so it takes however many lines are left over.  Without this the
  -- card simply overflowed its budget and got clipped mid-button, which is
  -- the failure a no-scroll layout has to design out rather than hope away.
  local fixedH = pad + Kit.textHeight("caption") + math.floor(6 * m.s)
    + Kit.textHeight("button") + math.floor(4 * m.s)
    + math.floor(10 * m.s) + m.btnH + pad
  local lineH = Kit.textHeight("small")
  local maxLines = 3
  if maxH then
    maxLines = math.max(0, math.min(3, math.floor((maxH - fixedH) / lineH)))
  end
  local detailH = Kit.wrapHeight("small", romDetail, iw, maxLines)
  local h = fixedH + detailH

  Kit.card(x, y, w, h)
  local cy = y + pad
  cy = cy + Kit.caption(x + pad, cy, Strings("ROM")) + math.floor(6 * m.s)
  Kit.text("button", Kit.ellipsize("button", romState, iw), x + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(4 * m.s)
  cy = cy + Kit.textWrapped("small", romDetail, x + pad, cy, iw, PAL.detail, maxLines)
  cy = cy + math.floor(10 * m.s)
  if romProgress ~= nil then
    Kit.progress(x + pad, cy + (m.btnH - math.floor(10 * m.s)) / 2, iw,
      math.floor(10 * m.s), romProgress)
  else
    btn(imp, x + pad, cy, iw, m.btnH, "rom-" .. version, romBtnLabel, {
      kind = "accent",
      enabled = romBtnEnabled,
      action = romBtnEnabled and function()
        if imp.ready[version] then imp:reimport(version)
        else imp:choose(version) end
      end or nil,
    })
  end
  return h
end

local function buildSaveFilesCard(imp, x, y, w, m, version, ready, locked, maxH)
  local sfImportEnabled, sfExportEnabled = false, false
  if not locked then
    imp:_ensureSlots(version)
    sfImportEnabled = ready and true or false
    local activeId = imp.activeSlot[version]
    for _, sl in ipairs(imp.slots[version] or {}) do
      if sl.id == activeId and sl.exists then sfExportEnabled = true break end
    end
  end
  local sfNotice = (not locked) and imp.saveNotice[version] or nil
  local hintText, hintCol
  if sfNotice then
    hintText, hintCol = sfNotice.text, (sfNotice.ok and PAL.green or PAL.red)
  elseif locked then
    hintText, hintCol = Strings("Not available yet."), PAL.muted
  else
    hintText, hintCol = imp:_savesDefaultHint(version), PAL.muted
  end
  local savImportLabel = imp.isNX and Strings("Scan again") or Strings("Import save")

  local pad = math.floor(14 * m.s)
  local iw = w - 2 * pad
  -- Same elastic rule as the ROM card: the buttons and the caption are fixed,
  -- the hint takes whatever lines remain (possibly none).
  local folderRow = sfNotice and sfNotice.dir
  local fixedH = pad + Kit.textHeight("caption") + math.floor(8 * m.s) + m.btnH
    + math.floor(8 * m.s) + pad
    + (folderRow and (math.floor(6 * m.s) + Kit.textHeight("small")) or 0)
  local lineH = Kit.textHeight("small")
  local maxLines = 3
  if maxH then
    maxLines = math.max(0, math.min(3, math.floor((maxH - fixedH) / lineH)))
  end
  local hintH = Kit.wrapHeight("small", hintText, iw, maxLines)
  local h = fixedH + hintH

  Kit.card(x, y, w, h)
  local cy = y + pad
  cy = cy + Kit.caption(x + pad, cy, Strings("SAVE FILES")) + math.floor(8 * m.s)
  local gap = math.floor(10 * m.s)
  local halfW = math.floor((iw - gap) / 2)
  btn(imp, x + pad, cy, halfW, m.btnH, "sav-import-" .. version, savImportLabel, {
    kind = "accent", enabled = sfImportEnabled,
    action = sfImportEnabled and function() imp:chooseSaveImport(version) end or nil,
  })
  btn(imp, x + pad + halfW + gap, cy, halfW, m.btnH, "sav-export-" .. version,
    Strings("Export save"), {
      kind = "accent", enabled = sfExportEnabled,
      action = sfExportEnabled and function() imp:exportSave(version) end or nil,
    })
  cy = cy + m.btnH + math.floor(8 * m.s)
  cy = cy + Kit.textWrapped("small", hintText, x + pad, cy, iw, hintCol, maxLines)
  if folderRow then
    cy = cy + math.floor(6 * m.s)
    local key = "sav-folder-" .. version
    local label = Strings("Open folder")
    local lw = Kit.textWidth("small", label)
    local lh = Kit.textHeight("small")
    Kit.focusable(key, x + pad, cy, lw, lh)
    Kit.text("small", label, x + pad, cy, PAL.blue)
    Theme.fill(x + pad, cy + lh - 1, lw, 1, PAL.blue, 0.6)
    if Kit.press(x + pad, cy, lw, lh) or Kit._activateId == key then
      local dir = sfNotice.dir
      queueAction(imp, key, function()
        love.system.openURL(imp:fileUrl(dir))
      end)
    end
  end
  return h
end

-- Save slots, PAGINATED.  This was a fixed-height scroller with momentum; it
-- is now a page of rows sized to whatever height the column has left, which
-- is why 40 slots cost exactly what 4 do.
local function buildSlotCard(imp, x, y, w, availH, m, version)
  imp:_ensureSlots(version)
  local slots = imp.slots[version] or {}
  local active = imp.activeSlot[version]
  local n = #slots
  local pad = math.floor(14 * m.s)
  local iw = w - 2 * pad
  local gap = math.floor(8 * m.s)

  -- A slot row: name + LOADED tag, meta line, action buttons.
  local chipH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local rowH = math.floor(8 * m.s) + Kit.textHeight("button")
    + math.floor(4 * m.s) + Kit.textHeight("small")
    + math.floor(8 * m.s) + chipH + math.floor(8 * m.s)

  local headH = Kit.textHeight("caption") + math.floor(8 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local newBtnH = m.btnH
  -- Rows get whatever is left after the card's fixed furniture.
  local listH = availH - (pad * 2 + headH + pagerH + gap + newBtnH + gap)
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 12)
  local pageKey = "slots-" .. version
  local first, last, cur, pages = Kit.pageBounds(page(imp, pageKey), n, perPage)
  setPage(imp, pageKey, cur)

  local shown = math.max(0, last - first + 1)
  local usedListH = (n == 0) and math.floor(70 * m.s)
    or (shown * rowH + math.max(0, shown - 1) * gap)
  local h = pad + headH + usedListH + gap
    + (pages > 1 and (pagerH + gap) or 0) + newBtnH + pad

  Kit.card(x, y, w, h)
  local cy = y + pad
  Kit.caption(x + pad, cy, Strings("SAVE SLOT"))
  Kit.textRight("small", n == 1 and Strings("1 slot") or Strings("%d slots", n),
    x + w - pad, cy, PAL.muted)
  cy = cy + headH

  if n == 0 then
    Kit.emptyBox(x + pad, cy, iw, usedListH,
      Strings("No saves yet - start a new game or import one."))
    cy = cy + usedListH + gap
  else
    -- Wheel over the list turns pages; the page index is bounded, so there is
    -- no scroll offset to interpolate and nothing to clamp against content.
    setPage(imp, pageKey,
      Kit.wheelPage(x + pad, cy, iw, usedListH, cur, n, perPage))
    for i = first, last do
      local slot = slots[i]
      local selected = slot.id == active
      local rowKey = "slot-" .. version .. "-" .. slot.id
      local ry = cy + (i - first) * (rowH + gap)
      local ink = rowHit(imp, x + pad, ry, iw, rowH, selected, rowKey,
        function() imp:_selectSlot(version, slot.id) end)

      local px = x + pad + math.floor(10 * m.s)
      local inner = iw - math.floor(20 * m.s)
      local ly = ry + math.floor(8 * m.s)
      local name = slot.label or slot.name or Strings("NEW GAME")
      local tagW = 0
      if selected then
        tagW = Kit.textWidth("micro", Strings("LOADED")) + math.floor(16 * m.s)
        Kit.tag(x + pad + iw - math.floor(10 * m.s) - tagW, ly,
          tagW, Kit.textHeight("button"), Strings("LOADED"),
          selected and PAL.inverse or PAL.green)
        tagW = tagW + math.floor(8 * m.s)
      end
      Kit.text("button", Kit.ellipsize("button", name, inner - tagW), px, ly, ink)
      ly = ly + Kit.textHeight("button") + math.floor(4 * m.s)
      local metaTxt
      if slot.exists and slot.meta then
        metaTxt = Strings("%d badges - %s - %d caught", slot.meta.badges or 0,
          slot.meta.timeText or "0:00", slot.meta.dexCount or 0)
      else
        metaTxt = Strings("empty slot")
      end
      Kit.text("small", Kit.ellipsize("small", metaTxt, inner), px, ly,
        selected and PAL.inverse or PAL.muted)
      ly = ly + Kit.textHeight("small") + math.floor(8 * m.s)

      -- Action chips, right-aligned.  A selected row is a white fill, so its
      -- chips invert too or they would vanish.
      local place = Layout.rightCluster(px, inner, math.floor(6 * m.s))
      local armed = deleteArmed(imp, "slot", slot.id, version)
      -- Width pinned to the WIDER of the two captions so arming to "Sure?"
      -- never reflows the row under the pointer (#433), and a translation
      -- whose "delete" is shorter than its "sure?" is not clipped.
      local delW = math.max(Kit.textWidth("small", DELETE_LABEL(false)),
        Kit.textWidth("small", DELETE_LABEL(true))) + math.floor(20 * m.s)
      btn(imp, place(delW), ly, delW, chipH, rowKey .. "-del", DELETE_LABEL(armed), {
        kind = "danger", font = "small", keepArm = true,
        action = function()
          imp:pressDelete("slot", slot.id, version, function()
            imp:_deleteSlot(version, slot.id)
          end)
        end,
      })
      if imp.onEditSave and slot.exists then
        local ew = Kit.textWidth("small", Strings("Edit")) + math.floor(20 * m.s)
        btn(imp, place(ew), ly, ew, chipH, rowKey .. "-edit", Strings("Edit"), {
          kind = "accent", font = "small",
          action = function() imp.onEditSave(version, slot.id) end,
        })
      end
      if not imp.android then
        local rw = Kit.textWidth("small", Strings("Rename")) + math.floor(20 * m.s)
        btn(imp, place(rw), ly, rw, chipH, rowKey .. "-rename", Strings("Rename"), {
          kind = "accent", font = "small",
          action = function() imp:_beginRename(version, slot.id) end,
        })
      end
    end
    cy = cy + usedListH + gap
  end

  if pages > 1 then
    local newPage = Kit.pager(x + pad, cy, iw, cur, n, perPage, pageKey)
    setPage(imp, pageKey, newPage)
    cy = cy + pagerH + gap
  end
  btn(imp, x + pad, cy, iw, newBtnH, "slot-new-" .. version,
    Strings("+ New save slot"), {
      kind = "good",
      action = function() imp:_newSlot(version) end,
    })
  return h
end

local function buildGamePanel(imp, x, y, w, availH, m, version)
  imp.panelVersion = version
  local info = GameVersion.info(version)
  local locked = info == nil
  local gameName = info and (info.launcherName or info.displayName)
    or tostring(version)
  local ready = (not locked) and imp.ready[version] or false

  -- title + status tag
  local titleH = Kit.textHeight("title")
  Kit.text("title", Kit.ellipsize("title", gameName, w * 0.6), x, y, PAL.heading)
  local tagText, tagCol
  if ready then tagText, tagCol = Strings("GOOD TO GO"), PAL.green
  elseif locked then tagText, tagCol = Strings("COMING SOON"), PAL.steel
  else tagText, tagCol = Strings("ROM REQUIRED"), PAL.yellow end
  local tagW = Kit.textWidth("micro", tagText) + math.floor(18 * m.s)
  local tagH = Kit.textHeight("micro") + math.floor(10 * m.s)
  Kit.tag(x + Kit.textWidth("title", Kit.ellipsize("title", gameName, w * 0.6))
    + math.floor(12 * m.s), y + (titleH - tagH) / 2, tagW, tagH, tagText, tagCol)
  local cy = y + titleH + math.floor(12 * m.s)
  local remaining = availH - (titleH + math.floor(12 * m.s))

  local gap = m.gap
  local lx, lw, rx2, rw
  if m.twoCol then
    lx, lw = x, m.colW
    rx2, rw = x + m.colW + m.colGap, m.colW
  else
    lx, lw, rx2, rw = x, w, x, w
  end

  -- LEFT COLUMN.  The controls that must always be reachable -- Play, and the
  -- control-reset pair -- are PINNED to the bottom of the column and laid out
  -- upward; the informational cards fill downward from the top into whatever
  -- is left.  Without that pinning the column is a stack whose height depends
  -- on how much text the ROM and save-file cards happen to carry, and at a
  -- large UI scale on a short window the Play button is what falls off the
  -- bottom -- the one thing that must never happen, and with no scrollbar to
  -- rescue it.
  local playH = math.max(m.btnH, math.floor(52 * m.s))
  local bottom = cy + remaining
  local py = bottom - playH
  btn(imp, lx, py, lw, playH, "play-" .. version,
    ready and (Strings("Play ") .. gameName)
      or (locked and Strings("Coming soon") or Strings("Import a ROM to play")),
    {
      kind = ready and "primary" or "ghost", font = "stat",
      enabled = ready,
      action = ready and function() imp:play(version) end or nil,
    })

  if imp.controlsNotice then
    local nh = Kit.wrapHeight("small", imp.controlsNotice.text, lw, 2)
    py = py - nh - math.floor(4 * m.s)
    Kit.textWrapped("small", imp.controlsNotice.text, lx, py, lw,
      imp.controlsNotice.ok and PAL.green or PAL.red, 2)
  end
  -- Reset rebinds, directly under the touch controls.  Rebinds are additive
  -- (Input:applyBindings layers them over the defaults), so there is no
  -- in-game way to undo one -- this is the way back.  Two-press confirm,
  -- same as every other destructive control here.
  do
    py = py - math.floor(6 * m.s) - m.btnH
    local armed = deleteArmed(imp, "rebinds", "all", nil)
    btn(imp, lx, py, lw, m.btnH, "reset-rebinds",
      armed and Strings("Sure? Reset all rebinds") or Strings("Reset rebinds"), {
        kind = "danger", font = "small", keepArm = true,
        action = function()
          imp:pressDelete("rebinds", "all", nil, function()
            imp:_resetRebinds()
          end)
        end,
      })
  end
  if imp.onEditTouchControls then
    py = py - math.floor(6 * m.s) - m.btnH
    btn(imp, lx, py, lw, m.btnH, "touch-controls", Strings("Touch Controls"), {
      kind = "accent",
      action = function() imp.onEditTouchControls() end,
    })
  end

  -- Cards fill the space above the pinned block, clipped so a long ROM error
  -- message can never paint over the controls below it.
  -- Split the leftover space between the two cards.  The ROM card gets what
  -- it needs up to half, the save-file card takes the rest; each trims its own
  -- elastic text to fit.  The clip is a backstop, not the mechanism.
  local cardsH = py - gap - cy
  Kit.pushClip(lx, cy, lw, math.max(0, cardsH))
  local ly = cy
  -- In one column the save-slot card shares this region, so the two info
  -- cards get a bounded share of it rather than the whole thing.
  local infoBudget = m.twoCol and cardsH or math.floor(cardsH * 0.42)
  local romH = buildRomCard(imp, lx, ly, lw, m, version, info, ready, locked,
    math.floor(infoBudget * 0.55))
  ly = ly + romH + gap
  local savH = buildSaveFilesCard(imp, lx, ly, lw, m, version, ready, locked,
    infoBudget - romH - gap)
  ly = ly + savH + gap
  Kit.popClip()

  -- Save slots.  Two columns put them beside the info cards; ONE column
  -- stacks them underneath, in the space between those cards and the pinned
  -- controls at the bottom.  Placing them after the pinned block (the
  -- obvious reading of "stack it under the left column") drew them off the
  -- bottom of the window and over the footer, with no scrollbar to reach
  -- them -- in a no-scroll layout, anything below the fold is simply gone.
  if not locked then
    local slotY = m.twoCol and cy or ly
    local slotAvail = m.twoCol and remaining or (py - gap - ly)
    if slotAvail > 80 * m.s then
      Kit.pushClip(rx2, slotY, rw, math.max(0, slotAvail))
      buildSlotCard(imp, rx2, slotY, rw, slotAvail, m, version)
      Kit.popClip()
    end
  end
end

-- --------------------------------------------------------------- mods panel

-- The sort row both mod panels share, including its persisted choice.
local function sortChips(imp, x, y, w, m, prefix)
  local sortKey = imp.modSort or "name"
  if imp.modSort == nil then
    local ok, opts = pcall(require("src.core.SaveData").loadOptions)
    if ok and type(opts) == "table" and type(opts.modSort) == "string" then
      sortKey = opts.modSort
      imp.modSort = sortKey
    end
  end
  local defs = {
    { key = "name", label = Strings("Name") },
    { key = "popularity", label = Strings("Popularity") },
    { key = "release", label = Strings("Release date") },
    { key = "updated", label = Strings("Last updated") },
  }
  local items = {}
  for _, s in ipairs(defs) do
    items[#items + 1] = {
      label = s.label, active = sortKey == s.key, key = prefix .. s.key,
      action = function()
        imp.modSort = s.key
        pcall(function()
          local SaveData = require("src.core.SaveData")
          local opts = SaveData.loadOptions()
          opts.modSort = s.key
          SaveData.saveOptions(opts)
        end)
      end,
    }
  end
  local labW = Kit.textWidth("small", Strings("Sort:")) + math.floor(8 * m.s)
  Kit.text("small", Strings("Sort:"), x, y + math.floor(6 * m.s), PAL.detail)
  return sortKey, chipRow(imp, x + labW, y, w - labW, m, items)
end

local function buildModsPanel(imp, x, y, w, availH, m)
  imp:_ensureMods()
  local ModUpdate = require("src.mods.ModUpdate")
  local mods = imp.mods or {}
  local enabledCount = 0
  for _, mod in ipairs(mods) do
    if mod.enabled then enabledCount = enabledCount + 1 end
  end
  local gap = m.gap
  local cy = y

  -- header: title, count, actions
  local titleH = Kit.textHeight("title")
  Kit.text("title", Strings("Mods"), x, cy, PAL.heading)
  Kit.text("small", Strings("%d of %d enabled", enabledCount, #mods),
    x + Kit.textWidth("title", Strings("Mods")) + math.floor(12 * m.s),
    cy + titleH - Kit.textHeight("small") - 2, PAL.muted)
  local place = Layout.rightCluster(x, w, math.floor(6 * m.s))
  local bh = m.btnH
  local importLabel = imp:_modsImportButtonLabel()
  local iw2 = Kit.textWidth("small", importLabel) + math.floor(24 * m.s)
  btn(imp, place(iw2), cy, iw2, bh, "mods-import", importLabel, {
    kind = "accent", font = "small",
    action = function() imp:chooseMod() end })
  if #mods > 0 then
    local dw = Kit.textWidth("small", Strings("Disable all")) + math.floor(20 * m.s)
    btn(imp, place(dw), cy, dw, bh, "mods-disable-all", Strings("Disable all"), {
      kind = "warn", font = "small",
      action = function() imp:_setAllMods(false) end })
    local ew = Kit.textWidth("small", Strings("Enable all")) + math.floor(20 * m.s)
    btn(imp, place(ew), cy, ew, bh, "mods-enable-all", Strings("Enable all"), {
      kind = "good", font = "small",
      action = function() imp:_setAllMods(true) end })
  end
  cy = cy + math.max(titleH, bh) + math.floor(8 * m.s)

  -- notice line
  local noticeText, noticeCol
  if imp.modNotice then
    noticeText = imp.modNotice.text
    noticeCol = imp.modNotice.ok and PAL.green or PAL.red
  else
    noticeText, noticeCol = imp:_modsDefaultHint(), PAL.muted
  end
  cy = cy + Kit.textWrapped("small", noticeText, x, cy, w, noticeCol, 2)
    + math.floor(8 * m.s)

  if #mods == 0 then
    Kit.emptyBox(x, cy, w, math.floor(110 * m.s), imp:_modsEmptyHint())
    return
  end

  local sortKey
  sortKey, cy = (function()
    local k, h = sortChips(imp, x, cy, w, m, "mod-sort-")
    return k, cy + h + math.floor(8 * m.s)
  end)()

  -- Immediate mode paints this panel every frame; re-sorting the whole list
  -- per frame (with lowercased-string allocations in the comparator) fed the
  -- GC for nothing.  Cache the sorted array, keyed on the list identity, the
  -- sort mode, and the update-info revision the fetch pump bumps.
  local cache = imp._modSortCache
  if cache and cache.src == mods and cache.n == #mods
      and cache.key == sortKey and cache.rev == (imp._modUpdateRev or 0) then
    mods = cache.list
  else
    local sorted = {}
    for i, v in ipairs(mods) do sorted[i] = v end
    table.sort(sorted, function(a, b)
      local function value(mod)
        if sortKey == "name" then return (mod.name or ""):lower() end
        local info = mod.github and mod.github ~= "" and imp:_modUpdateInfo(mod.id)
        if sortKey == "popularity" then
          return info and info.downloads and info.downloads.total or -1
        end
        local date = info and info.dates
        if sortKey == "release" then return date and date.first or "0000-00-00" end
        return date and date.latest or "0000-00-00"
      end
      local va, vb = value(a), value(b)
      if va ~= vb then
        if sortKey == "name" then return va < vb end
        return va > vb  -- data sorts newest / most popular first
      end
      return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    imp._modSortCache = { src = imp.mods, n = #mods, key = sortKey,
      rev = imp._modUpdateRev or 0, list = sorted }
    mods = sorted
  end

  -- A mod row is a fixed height: name line, version + status line, one line
  -- of description, and an action row.  Fixed because a page of uniform rows
  -- is what lets perPage come from the viewport.
  local chipH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  -- Text block on the left, chips right-aligned beside it: one row, not a
  -- text block with a button strip stacked under it.
  local textH = Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small") + math.floor(2 * m.s) + Kit.textHeight("small")
  local rowH = math.floor(8 * m.s) + math.max(textH, chipH)
    + math.floor(8 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = availH - (cy - y) - pagerH - gap
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 20)
  local first, last, cur, pages = Kit.pageBounds(page(imp, "mods"), #mods, perPage)
  setPage(imp, "mods", cur)
  local listTop = cy
  setPage(imp, "mods",
    Kit.wheelPage(x, listTop, w, listH, cur, #mods, perPage))

  for i = first, last do
    local mod = mods[i]
    local ry = listTop + (i - first) * (rowH + gap)
    local key = "mod-" .. mod.id
    Kit.card(x, ry, w, rowH)
    local pad = math.floor(12 * m.s)
    local px, inner = x + pad, w - 2 * pad
    local ly = ry + math.floor(10 * m.s)

    -- name + badge + enable toggle (right)
    local togW = math.floor(56 * m.s)
    local togH = math.floor(26 * m.s)
    local info = mod.github and mod.github ~= "" and imp:_modUpdateInfo(mod.id)

    -- Right cluster first (toggle, then the action chips), all on one
    -- vertically-centred line, so the text block knows the width it has left.
    local chipY = ry + (rowH - chipH) / 2
    local place2 = Layout.rightCluster(px, inner, math.floor(6 * m.s))
    local togKey = "mod-toggle-" .. mod.id
    -- The toggle reports its own new value, but the importer owns the state:
    -- queue the flip and let _toggleMod (which may raise an experimental-mod
    -- confirm) decide what actually happens.
    local _, flipped = Kit.toggle(place2(togW),
      ry + (rowH - togH) / 2, togW, togH, mod.enabled, togKey)
    if flipped then
      queueAction(imp, togKey, function() imp:_toggleMod(mod.id) end)
    end
    local chipsW = togW + math.floor(6 * m.s)

    local armed = deleteArmed(imp, "mod", mod.id, nil)
    local delW = math.max(Kit.textWidth("small", DELETE_LABEL(false)),
      Kit.textWidth("small", DELETE_LABEL(true))) + math.floor(20 * m.s)
    btn(imp, place2(delW), chipY, delW, chipH, "mod-del-" .. mod.id,
      DELETE_LABEL(armed), {
        kind = "danger", font = "small", keepArm = true,
        action = function()
          imp:pressDelete("mod", mod.id, nil, function()
            imp:_deleteMod(mod.id)
          end)
        end,
      })
    chipsW = chipsW + delW + math.floor(6 * m.s)
    if mod.github and mod.github ~= "" then
      local vw = Kit.textWidth("small", Strings("Versions")) + math.floor(20 * m.s)
      btn(imp, place2(vw), chipY, vw, chipH, "mod-ver-" .. mod.id,
        Strings("Versions"), { kind = "accent", font = "small",
          action = function() imp:_modGithubAction(mod.id, "versions") end })
      local updLabel, updKind = Strings("Check for updates"), "ghost"
      if info and info.status == "available" then
        updLabel, updKind = Strings("Update"), "warn"
      elseif info and info.status == "current" then
        updLabel = Strings("Check again")
      end
      local uw = Kit.textWidth("small", updLabel) + math.floor(20 * m.s)
      btn(imp, place2(uw), chipY, uw, chipH, "mod-upd-" .. mod.id, updLabel, {
        kind = updKind, font = "small",
        action = function() imp:_modGithubAction(mod.id, "update") end })
      chipsW = chipsW + vw + uw + math.floor(12 * m.s)
    end
    local textW = inner - chipsW - math.floor(12 * m.s)

    local badgeW = Kit.textWidth("micro", mod.badge) + math.floor(12 * m.s)
    local nameShown = Kit.ellipsize("button", mod.name,
      textW - badgeW - math.floor(8 * m.s))
    Kit.text("button", nameShown, px, ly, PAL.heading)
    Kit.tag(px + Kit.textWidth("button", nameShown) + math.floor(8 * m.s), ly,
      badgeW, Kit.textHeight("button"), mod.badge,
      mod.experimental and PAL.yellow or PAL.muted)
    ly = ly + Kit.textHeight("button") + math.floor(4 * m.s)

    -- version + status + update state
    local statusText, statusCol = modStatusColor(mod.status)
    local line = "v" .. tostring(mod.version or "?") .. "   " .. statusText
    Kit.text("small", line, px, ly, statusCol)
    local lx = px + Kit.textWidth("small", line) + math.floor(12 * m.s)
    if imp:_modInfoPending(mod.id) then
      -- An inline spinner, because this row's release check is genuinely in
      -- flight -- the list stays usable while it resolves.
      Loader.dot(lx, ly, Kit.textHeight("small"))
      Kit.text("small", Strings("Checking..."),
        lx + Kit.textHeight("small") + math.floor(6 * m.s), ly, PAL.muted)
    elseif info and info.status == "available" then
      Kit.text("small", Strings("v%s available", tostring(info.latest)),
        lx, ly, PAL.yellow)
    elseif info and info.status == "current" then
      Kit.text("small", Strings("up to date"), lx, ly, PAL.muted)
    elseif info and info.status == "error" then
      Kit.text("small", Strings("check failed"), lx, ly, PAL.red)
    end
    ly = ly + Kit.textHeight("small") + math.floor(2 * m.s)

    -- one line of description, or the download stats when we have them
    local sub = mod.description or ""
    if info and info.downloads then
      local d = info.dates
      sub = ModUpdate.statsLine(info.downloads.total, d and d.first,
        d and d.latest)
    end
    if sub ~= "" then
      Kit.text("small", Kit.ellipsize("small", sub, textW), px, ly, PAL.detail)
    end
  end

  local pagerY = listTop + (last - first + 1) * (rowH + gap)
  local newPage = Kit.pager(x, pagerY, w, cur, #mods, perPage, "mods")
  setPage(imp, "mods", newPage)
end

-- ---------------------------------------------------------- find mods panel

local function buildFindPanel(imp, x, y, w, availH, m)
  imp:_ensureFind()
  imp:_ensureMods()
  local ModIndex = require("src.mods.ModIndex")
  local ModUpdate = require("src.mods.ModUpdate")
  local sources = imp.findSources or {}
  local rows = imp:_findRows()
  local total = #((imp.findIndex and imp.findIndex.mods) or {})
  local gap = m.gap
  local cy = y

  -- header
  local titleH = Kit.textHeight("title")
  Kit.text("title", Strings("Find Mods"), x, cy, PAL.heading)
  if #sources > 0 then
    local count = (#rows == total) and Strings("%d mods listed", total)
      or Strings("%d of %d mods", #rows, total)
    Kit.text("small", count,
      x + Kit.textWidth("title", Strings("Find Mods")) + math.floor(12 * m.s),
      cy + titleH - Kit.textHeight("small") - 2, PAL.muted)
  end
  local place = Layout.rightCluster(x, w, math.floor(6 * m.s))
  local bh = m.btnH
  local addLabel = (#sources == 0) and Strings("Add an index") or Strings("Add index")
  local aw = Kit.textWidth("small", addLabel) + math.floor(24 * m.s)
  btn(imp, place(aw), cy, aw, bh, "find-add", addLabel, {
    kind = "accent", font = "small",
    action = function() imp:_promptAddIndex() end })
  if #sources > 0 then
    local rw = Kit.textWidth("small", Strings("Refresh")) + math.floor(24 * m.s)
    btn(imp, place(rw), cy, rw, bh, "find-refresh", Strings("Refresh"), {
      kind = "accent", font = "small",
      action = function()
        imp._findSearchFocus = false
        imp:_disarmTextInput()
        imp:_refreshFind(true)
      end })
  end
  cy = cy + math.max(titleH, bh) + math.floor(8 * m.s)

  local noticeText, noticeCol
  if imp.findNotice then
    noticeText = imp.findNotice.text
    noticeCol = imp.findNotice.ok and PAL.green or PAL.red
  else
    noticeText = Strings(
      "Mods here are listed, not reviewed - read the source and trust the author.")
    noticeCol = PAL.muted
  end
  cy = cy + Kit.textWrapped("small", noticeText, x, cy, w, noticeCol, 2)
    + math.floor(8 * m.s)

  if #sources == 0 then
    local h = math.floor(140 * m.s)
    Kit.card(x, cy, w, h)
    Kit.textCenter("button", Strings("No mod index added"), x,
      cy + math.floor(40 * m.s), w, PAL.heading)
    Kit.textWrapped("small", Strings(
      "Add an index to browse mods. An index is a published list; paste its URL or its owner/repo."),
      x + math.floor(24 * m.s), cy + math.floor(70 * m.s),
      w - math.floor(48 * m.s), PAL.muted, 3)
    return
  end

  -- source rows
  for _, source in ipairs(sources) do
    local h = math.max(Kit.tapMin(), math.floor(28 * m.s))
    local rmW = Kit.textWidth("small", Strings("Remove")) + math.floor(20 * m.s)
    Kit.text("small", Kit.ellipsize("small", source.label or source.feed,
      w - rmW - math.floor(12 * m.s)), x, cy + (h - Kit.textHeight("small")) / 2,
      PAL.detail)
    local feed = source.feed
    btn(imp, x + w - rmW, cy, rmW, h, "find-src-rm-" .. tostring(feed),
      Strings("Remove"), { kind = "danger", font = "small",
        action = function() imp:_removeIndex(feed) end })
    cy = cy + h + math.floor(4 * m.s)
  end
  cy = cy + math.floor(4 * m.s)

  -- search field
  local fieldH = math.max(Kit.tapMin(), math.floor(36 * m.s))
  textField(imp, x, cy, w, fieldH, "find-search", imp.findQuery or "",
    Strings("Search mods"), imp._findSearchFocus == true,
    function() imp:_toggleFindSearchFocus() end)
  cy = cy + fieldH + math.floor(8 * m.s)

  -- category chips
  local cats = (imp.findIndex and imp.findIndex.categories) or {}
  if #cats > 0 then
    local items = { {
      label = Strings("All"), active = imp.findCategory == nil,
      key = "find-cat-all", action = function() imp.findCategory = nil end,
    } }
    for _, cat in ipairs(cats) do
      items[#items + 1] = {
        label = cat, active = imp.findCategory == cat,
        key = "find-cat-" .. cat,
        action = function()
          imp.findCategory = (imp.findCategory ~= cat) and cat or nil
          setPage(imp, "find", 1)
        end,
      }
    end
    cy = cy + chipRow(imp, x, cy, w, m, items) + math.floor(8 * m.s)
  end

  if #rows == 0 then
    Kit.emptyBox(x, cy, w, math.floor(110 * m.s),
      (total == 0) and Strings("This index lists no mods yet.")
        or Strings("No mods match that search."))
    return
  end

  local sortKey
  sortKey, cy = (function()
    local k, h = sortChips(imp, x, cy, w, m, "find-sort-")
    return k, cy + h + math.floor(8 * m.s)
  end)()

  -- Same caching rule as the MODS tab: the comparator allocates, so only
  -- re-sort when the inputs actually change.
  local fcache = imp._findSortCache
  if fcache and fcache.src == rows and fcache.key == sortKey
      and fcache.rev == (imp._findStatsRev or 0) then
    rows = fcache.list
  else
    local sorted = {}
    for i, v in ipairs(rows) do sorted[i] = v end
    table.sort(sorted, function(a, b)
      local function value(entry)
        if sortKey == "name" then return (entry.title or entry.id or ""):lower() end
        local stats = imp:_findStats(entry)
        if sortKey == "popularity" then return stats and stats.total or -1 end
        if sortKey == "release" then return stats and stats.first or "0000-00-00" end
        return stats and stats.latest or "0000-00-00"
      end
      local va, vb = value(a), value(b)
      if va ~= vb then
        if sortKey == "name" then return va < vb end
        return va > vb
      end
      return (a.title or a.id or ""):lower() < (b.title or b.id or ""):lower()
    end)
    imp._findSortCache = { src = rows, key = sortKey,
      rev = imp._findStatsRev or 0, list = sorted }
    rows = sorted
  end

  local installed = imp:_findInstalledMap()
  -- The thumbnail sits BESIDE the text and the action chips share the title
  -- line's row, so a card is only as tall as its text block.  The old layout
  -- stacked chips under a 64px thumbnail and got ~2 rows per screen; this
  -- fits roughly twice as many without shrinking a single tap target.
  local thumb = math.floor(44 * m.s)
  local chipH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  -- TWO text lines, not three: the version/author/category meta and the
  -- download stats share a line.  A third line cost every row ~20px, which
  -- at this UI scale was the difference between one and two rows per page.
  local textH = Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small")
  local rowH = math.floor(8 * m.s) + math.max(thumb, textH, chipH)
    + math.floor(8 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = availH - (cy - y) - pagerH - gap
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 20)
  local first, last, cur, pages = Kit.pageBounds(page(imp, "find"), #rows, perPage)
  setPage(imp, "find", cur)
  local listTop = cy
  setPage(imp, "find", Kit.wheelPage(x, listTop, w, listH, cur, #rows, perPage))

  for i = first, last do
    local entry = rows[i]
    local ry = listTop + (i - first) * (rowH + gap)
    Kit.card(x, ry, w, rowH)
    local pad = math.floor(12 * m.s)
    local px, inner = x + pad, w - 2 * pad
    local ly = ry + math.floor(8 * m.s)

    -- Action chips are right-aligned on the SAME rows as the text, so the
    -- card needs no separate button strip.  Reserve their width first.
    local chipY = ry + (rowH - chipH) / 2
    local place2 = Layout.rightCluster(px, inner, math.floor(6 * m.s))
    local action, note = findActionFor(entry, installed[entry.id])
    local chipsW = 0
    if action then
      local iw4 = Kit.textWidth("small", action) + math.floor(20 * m.s)
      btn(imp, place2(iw4), chipY, iw4, chipH, "find-inst-" .. entry.id, action, {
        kind = "accent", font = "small",
        action = function() imp:_findConfirmInstall(entry) end })
      chipsW = chipsW + iw4 + math.floor(6 * m.s)
    else
      local uw = Kit.textWidth("micro", Strings("Unavailable")) + math.floor(16 * m.s)
      Kit.tag(place2(uw), chipY, uw, chipH, Strings("Unavailable"), PAL.yellow)
      chipsW = chipsW + uw + math.floor(6 * m.s)
    end
    if entry.repo then
      local sw = Kit.textWidth("small", Strings("Source")) + math.floor(20 * m.s)
      local repo = entry.repo
      btn(imp, place2(sw), chipY, sw, chipH, "find-repo-" .. entry.id,
        Strings("Source"), { kind = "accent", font = "small",
          action = function() love.system.openURL(repo) end })
      chipsW = chipsW + sw + math.floor(6 * m.s)
    end
    local dw = Kit.textWidth("small", Strings("Details")) + math.floor(20 * m.s)
    btn(imp, place2(dw), chipY, dw, chipH, "find-det-" .. entry.id,
      Strings("Details"), { kind = "accent", font = "small",
        action = function() imp:_findShowDetails(entry) end })
    chipsW = chipsW + dw + math.floor(12 * m.s)

    -- thumbnail (or its placeholder while the async fetch is in flight)
    local image = imp:_findThumb(entry)
    if image then
      local iw3, ih3 = image:getDimensions()
      local s = math.min(thumb / iw3, thumb / ih3)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, Theme.snap(px), Theme.snap(ly), 0, s, s)
    else
      Theme.stroke(px, ly, thumb, thumb, PAL.line, Theme.A.hairline, 1)
      Kit.textCenter("micro", "MOD", px,
        ly + (thumb - Kit.textHeight("micro")) / 2, thumb, PAL.faint)
    end

    local bx = px + thumb + math.floor(10 * m.s)
    local bw = inner - thumb - math.floor(10 * m.s) - chipsW
    Kit.text("button", Kit.ellipsize("button", entry.title or entry.id, bw),
      bx, ly, PAL.heading)
    local by2 = ly + Kit.textHeight("button") + math.floor(4 * m.s)
    local meta = "v" .. tostring(ModIndex.displayVersion(entry))
    if entry.author then meta = meta .. "  -  " .. entry.author end
    if entry.categories and entry.categories[1] then
      meta = meta .. "  -  " .. entry.categories[1]
    end
    -- meta and stats on one line, stats first because they are what the
    -- Popularity/date sorts are ordering by
    local stats = imp:_findStats(entry)
    local tail = entry.summary or ""
    if stats and (stats.total ~= nil or stats.first or stats.latest) then
      tail = ModUpdate.statsLine(stats.total, stats.first, stats.latest)
    end
    if note then tail = note .. "  -  " .. tail end
    local line2 = meta
    if tail ~= "" then line2 = line2 .. "  -  " .. tail end
    Kit.text("small", Kit.ellipsize("small", line2, bw), bx, by2,
      note and PAL.green or PAL.detail)
  end

  local pagerY = listTop + (last - first + 1) * (rowH + gap)
  setPage(imp, "find", Kit.pager(x, pagerY, w, cur, #rows, perPage, "find"))
end

-- ------------------------------------------------------------------ footer

local TRUST_WARNING = "if you did not get this from bryanthaboi's github "
  .. "or a link from the discord that bryanthaboi himself posted, just know "
  .. "it might have been tampered with. go to the discord to verify "
  .. COMMUNITY_URL .. " (or click the logo above)"

-- Pinned to the bottom of the window; returns the y it starts at, so the
-- panels above know how much room they have.
-- Deliberately compact: at a large UI scale the footer is pure overhead
-- competing with the panel for a short window's height, so the mark and the
-- link share one line and the trust warning is capped at a single line.
local function footerHeight(imp, m)
  local bh = math.floor(22 * m.s)
  return bh + math.floor(4 * m.s) + Kit.textHeight("micro")
    + math.floor(8 * m.s)
end

local function buildFooter(imp, m, y)
  Theme.fill(m.x, y, m.w, 1, PAL.line, Theme.A.hairline)
  local cy = y + math.floor(8 * m.s)
  -- The BCG mark is dark ink; invert it for the black field.
  imp.invertShader = imp.invertShader or love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      return vec4((vec3(1.0) - p.rgb) * color.rgb, p.a * color.a);
    }
  ]])
  local bw, bh = imp.bcg:getDimensions()
  local scale = math.min((130 * m.s) / bw, (22 * m.s) / bh)
  local dw, dh = bw * scale, bh * scale
  -- Mark on the left of the line, link on the right, so the footer is one row
  -- instead of three stacked ones.
  local linkW = Kit.textWidth("small", COMMUNITY_URL)
  local bx = m.contentX
  local hot = Kit.hover(bx, cy, dw, dh)
  love.graphics.setShader(imp.invertShader)
  love.graphics.setColor(1, 1, 1, hot and 1 or 0.85)
  love.graphics.draw(imp.bcg, Theme.snap(bx), Theme.snap(cy), 0, scale, scale)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  if Kit.press(bx, cy, dw, dh) then
    queueAction(imp, "bcg", function() love.system.openURL(COMMUNITY_URL) end)
  end
  local lx = m.contentX + m.contentW - linkW
  local lyy = cy + (dh - Kit.textHeight("small")) / 2
  Kit.text("small", COMMUNITY_URL, lx, lyy, PAL.blue)
  Theme.fill(lx, lyy + Kit.textHeight("small") - 1, linkW, 1, PAL.blue, 0.6)
  if Kit.press(lx, lyy, linkW, Kit.textHeight("small")) then
    queueAction(imp, "bois", function() love.system.openURL(COMMUNITY_URL) end)
  end
  cy = cy + dh + math.floor(4 * m.s)
  Kit.text("micro", Kit.ellipsize("micro", TRUST_WARNING, m.contentW),
    m.contentX, cy, PAL.muted)
end

-- ------------------------------------------------------------------ modals
-- A modal draws its own scrim, then raises Kit.blockClicks so everything
-- underneath is inert, then lowers it for its own panel.  There is no
-- z-ordered hit test, so this ordering IS the z-order.

local function modalPanel(m, w, h)
  Theme.fill(0, 0, m.W, m.H, PAL.bg, 0.82)
  Kit.blockClicks = true
  local pw = math.floor(math.min(w, m.W - 2 * m.pad))
  local ph = math.floor(math.min(h, m.H - 2 * m.pad))
  local px = math.floor((m.W - pw) / 2)
  local py = math.floor((m.H - ph) / 2)
  Kit.card(px, py, pw, ph, true)
  Kit.blockClicks = false
  return px, py, pw, ph
end

-- Shared prompt: title, read-only field over the importer's text, buttons.
local function buildPrompt(imp, m, spec)
  local pad = math.floor(18 * m.s)
  local fieldH = math.max(Kit.tapMin(), math.floor(36 * m.s))
  local w = math.floor(460 * m.s)
  local hintH = spec.hint and (Kit.wrapHeight("small", spec.hint,
    w - 2 * pad, 2) + math.floor(6 * m.s)) or 0
  local footH = spec.footnote and (Kit.textHeight("micro")
    + math.floor(8 * m.s)) or 0
  local h = pad + Kit.textHeight("button") + math.floor(10 * m.s) + hintH
    + fieldH + math.floor(12 * m.s) + m.btnH + footH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", spec.title, px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(10 * m.s)
  if spec.hint then
    cy = cy + Kit.textWrapped("small", spec.hint, px + pad, cy,
      pw - 2 * pad, PAL.detail, 2) + math.floor(6 * m.s)
  end
  textField(imp, px + pad, cy, pw - 2 * pad, fieldH, spec.key .. "-field",
    spec.text or "", nil, true)
  cy = cy + fieldH + math.floor(12 * m.s)

  local place = Layout.rightCluster(px + pad, pw - 2 * pad, math.floor(8 * m.s))
  local okW = Kit.textWidth("small", spec.okLabel or Strings("Save"))
    + math.floor(28 * m.s)
  btn(imp, place(okW), cy, okW, m.btnH, spec.key .. "-ok",
    spec.okLabel or Strings("Save"),
    { kind = "primary", font = "small", action = spec.commit })
  local cw = Kit.textWidth("small", Strings("Cancel")) + math.floor(28 * m.s)
  btn(imp, place(cw), cy, cw, m.btnH, spec.key .. "-cancel", Strings("Cancel"),
    { font = "small", action = spec.cancel })
  if spec.paste then
    local pwid = Kit.textWidth("small", Strings("Paste")) + math.floor(28 * m.s)
    btn(imp, px + pad, cy, pwid, m.btnH, spec.key .. "-paste", Strings("Paste"),
      { kind = "accent", font = "small", action = spec.paste })
  end
  cy = cy + m.btnH + math.floor(8 * m.s)
  if spec.footnote then
    Kit.text("micro", spec.footnote, px + pad, cy, PAL.muted)
  end
end

local function buildConfirmModal(imp, m)
  local c = imp._modConfirm
  local pad = math.floor(22 * m.s)
  local w = math.floor(520 * m.s)
  local lineH = Kit.textHeight("small") + math.floor(4 * m.s)
  local h = pad + Kit.textHeight("stat") + math.floor(12 * m.s)
    + #(c.lines or {}) * lineH + math.floor(12 * m.s) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("stat", c.title or Strings("Confirm"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("stat") + math.floor(12 * m.s)
  for _, line in ipairs(c.lines or {}) do
    Kit.text("small", Kit.ellipsize("small", line, pw - 2 * pad),
      px + pad, cy, PAL.detail)
    cy = cy + lineH
  end
  cy = cy + math.floor(12 * m.s)
  local gap = math.floor(10 * m.s)
  local halfW = math.floor((pw - 2 * pad - gap) / 2)
  btn(imp, px + pad, cy, halfW, m.btnH, "confirm-yes",
    c.yesLabel or Strings("OK"), {
      kind = "primary", font = "small",
      action = function()
        imp._modConfirm = nil
        if c.indexEntry then
          imp:_findInstall(c.indexEntry)
        elseif c.kind == "update" then
          imp:_confirmModUpdate(c.id, c.release)
        elseif c.kind == "enableAll" then
          imp:_setAllMods(true, true)
        else
          imp:_toggleMod(c.id, true)
        end
      end,
    })
  btn(imp, px + pad + halfW + gap, cy, halfW, m.btnH, "confirm-no",
    Strings("Cancel"), { font = "small",
      action = function() imp._modConfirm = nil end })
end

-- A body of text, paginated rather than scrolled (release notes, mod
-- descriptions).  Long-form text is the one place a scrollbar was genuinely
-- convenient, so the pager here moves a LINE window instead of a row window.
local function buildTextModal(imp, m, key, title, body, closeFn)
  local pad = math.floor(18 * m.s)
  local w = math.floor(520 * m.s)
  local h = math.floor(math.min(m.H - 2 * m.pad, 460 * m.s))
  local px, py, pw, ph = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button", title, pw - 2 * pad),
    px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(10 * m.s)

  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local bodyH = (py + ph - pad) - cy - m.btnH - math.floor(10 * m.s)
    - pagerH - math.floor(8 * m.s)
  local lineH = Kit.textHeight("small")
  local perPage = math.max(1, math.floor(bodyH / lineH))
  local lines = Kit.wrapLines("small", body, pw - 2 * pad) or { "" }
  local first, last, cur = Kit.pageBounds(page(imp, key), #lines, perPage)
  setPage(imp, key, cur)
  setPage(imp, key, Kit.wheelPage(px, cy, pw, bodyH, cur, #lines, perPage))
  for i = first, last do
    Kit.text("small", lines[i], px + pad, cy + (i - first) * lineH, PAL.detail)
  end
  cy = cy + bodyH + math.floor(8 * m.s)
  setPage(imp, key, Kit.pager(px + pad, cy, pw - 2 * pad, cur, #lines,
    perPage, key))
  cy = cy + pagerH + math.floor(10 * m.s)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, key .. "-close",
    Strings("Close"), { font = "small", action = closeFn })
end

local function buildVersionsModal(imp, m)
  local ModUpdate = require("src.mods.ModUpdate")
  local v = imp._modVersions
  local pad = math.floor(18 * m.s)
  local w = math.floor(520 * m.s)
  local h = math.floor(math.min(m.H - 2 * m.pad, 480 * m.s))
  local px, py, pw, ph = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button",
    Strings("Other versions: ") .. tostring(v.name), pw - 2 * pad),
    px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(6 * m.s)

  local info = imp:_modUpdateInfo(v.id)
  local statusTxt = Strings("Installed: v") .. tostring(v.current)
  local statusCol = PAL.detail
  if info and info.status == "available" then
    statusTxt = statusTxt .. "  -  " .. Strings("Update v") .. tostring(info.latest)
    statusCol = PAL.yellow
  elseif info and info.status == "current" then
    statusTxt = statusTxt .. "  -  " .. Strings("Up to date")
    statusCol = PAL.green
  end
  Kit.text("small", statusTxt, px + pad, cy, statusCol)
  cy = cy + Kit.textHeight("small") + math.floor(10 * m.s)

  local chipH = math.max(Kit.tapMin(), math.floor(28 * m.s))
  local rowH = math.floor(8 * m.s) + Kit.textHeight("small")
    + math.floor(4 * m.s) + chipH + math.floor(8 * m.s)
  local gap = math.floor(6 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = (py + ph - pad) - cy - m.btnH - math.floor(10 * m.s)
    - pagerH - math.floor(8 * m.s)
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 12)
  local n = #v.releases
  local first, last, cur = Kit.pageBounds(page(imp, "versions"), n, perPage)
  setPage(imp, "versions", cur)
  setPage(imp, "versions",
    Kit.wheelPage(px, cy, pw, listH, cur, n, perPage))

  for i = first, last do
    local rel = v.releases[i]
    local ry = cy + (i - first) * (rowH + gap)
    Theme.stroke(px + pad, ry, pw - 2 * pad, rowH, PAL.line, Theme.A.hairline, 1)
    local ix = px + pad + math.floor(10 * m.s)
    local inner = pw - 2 * pad - math.floor(20 * m.s)
    local text = "v" .. rel.version
    if rel.version == v.current then text = text .. Strings(" (installed)") end
    if rel.prerelease then text = text .. " pre" end
    Kit.text("small", text, ix, ry + math.floor(8 * m.s),
      rel.version == v.current and PAL.yellow or PAL.heading)
    local preview = ModUpdate.previewLine(rel.body or "", 90)
    if preview ~= "" then
      Kit.text("micro", Kit.ellipsize("micro", preview,
        inner - math.floor(180 * m.s)),
        ix + Kit.textWidth("small", text) + math.floor(10 * m.s),
        ry + math.floor(8 * m.s), PAL.muted)
    end
    local ly = ry + math.floor(8 * m.s) + Kit.textHeight("small")
      + math.floor(4 * m.s)
    local place = Layout.rightCluster(ix, inner, math.floor(6 * m.s))
    if rel.version ~= v.current then
      local iw5 = Kit.textWidth("small", Strings("Install")) + math.floor(20 * m.s)
      btn(imp, place(iw5), ly, iw5, chipH, "ver-inst-" .. i, Strings("Install"), {
        kind = "accent", font = "small",
        action = function() imp:_installModVersion(v.id, rel) end })
    end
    if type(rel.body) == "string" and rel.body:match("%S") then
      local rw = Kit.textWidth("small", Strings("Read more")) + math.floor(20 * m.s)
      btn(imp, place(rw), ly, rw, chipH, "ver-notes-" .. i, Strings("Read more"), {
        kind = "accent", font = "small",
        action = function()
          imp._modReleaseNotes = { version = rel.version, body = rel.body or "" }
        end })
    end
  end
  cy = cy + listH + math.floor(8 * m.s)
  setPage(imp, "versions",
    Kit.pager(px + pad, cy, pw - 2 * pad, cur, n, perPage, "versions"))
  cy = cy + pagerH + math.floor(10 * m.s)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "versions-close",
    Strings("Close"), { font = "small",
      action = function() imp._modVersions = nil end })
end

local function buildSettingsModal(imp, m)
  local model = imp._settings
  local pad = math.floor(18 * m.s)
  local w = math.floor(640 * m.s)
  local h = math.floor(math.min(m.H - 2 * m.pad, m.H * 0.9))
  local px, py, pw, ph = modalPanel(m, w, h)
  local cy = py + pad

  Kit.text("stat", Strings("Settings"), px + pad, cy, PAL.heading)
  local cw = Kit.textWidth("small", Strings("Close")) + math.floor(24 * m.s)
  btn(imp, px + pw - pad - cw, cy, cw, m.btnH, "settings-close",
    Strings("Close"), { font = "small",
      action = function() imp:_closeSettings() end })
  cy = cy + math.max(Kit.textHeight("stat"), m.btnH) + math.floor(6 * m.s)
  Kit.text("micro", Strings(
    "Saved to your options file; the game applies these on its next start."),
    px + pad, cy, PAL.muted)
  cy = cy + Kit.textHeight("micro") + math.floor(10 * m.s)

  -- Settings rows are PAGINATED, flattened across sections so a page is a
  -- uniform run of rows.  Section titles ride along as their own entry.
  local flat = imp._settingsFlat
  if not flat or flat.model ~= model then
    flat = { model = model }
    for _, section in ipairs(model.sections) do
      flat[#flat + 1] = { header = section.title }
      for _, row in ipairs(section.rows) do
        flat[#flat + 1] = { row = row }
      end
    end
    imp._settingsFlat = flat
  end

  local rowH = math.max(Kit.tapMin(), math.floor(36 * m.s))
  local gap = math.floor(4 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = (py + ph - pad) - cy - pagerH - math.floor(8 * m.s)
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 24)
  local n = #flat
  -- POKEPORT_LAUNCHER_SETTINGS_PAGE jumps straight to a page, so a shot can
  -- capture a row that is not on page one.
  local wanted = tonumber(os.getenv("POKEPORT_LAUNCHER_SETTINGS_PAGE") or "")
  if wanted and not imp._settingsPaged then
    imp._settingsPaged = true
    setPage(imp, "settings", wanted)
  end
  local first, last, cur = Kit.pageBounds(page(imp, "settings"), n, perPage)
  setPage(imp, "settings", cur)
  setPage(imp, "settings", Kit.wheelPage(px, cy, pw, listH, cur, n, perPage))

  for i = first, last do
    local item = flat[i]
    local ry = cy + (i - first) * (rowH + gap)
    if item.header then
      Kit.caption(px + pad, ry + (rowH - Kit.textHeight("caption")) / 2,
        item.header)
    else
      local row = item.row
      local key = "set-" .. i
      Theme.stroke(px + pad, ry, pw - 2 * pad, rowH, PAL.line,
        Theme.A.hairline, 1)
      local ix = px + pad + math.floor(12 * m.s)
      local inner = pw - 2 * pad - math.floor(24 * m.s)
      local ly = ry + (rowH - Kit.textHeight("small")) / 2
      if row.editText then
        local ew = Kit.textWidth("small", Strings("Edit")) + math.floor(20 * m.s)
        local vw = math.floor(160 * m.s)
        Kit.text("small", Kit.ellipsize("small", row.label,
          inner - ew - vw - math.floor(20 * m.s)), ix, ly, PAL.text)
        Kit.textRight("small", Kit.ellipsize("small", tostring(row.value()), vw),
          ix + inner - ew - math.floor(10 * m.s), ly, PAL.detail)
        btn(imp, ix + inner - ew, ry + (rowH - m.btnH) / 2, ew, m.btnH,
          key .. "-edit", Strings("Edit"), { kind = "accent", font = "small",
            action = function()
              imp._settingsText = { row = row, text = tostring(row.value() or ""),
                maxLen = row.editText.maxLen }
              imp:_armTextInput()
            end })
      elseif row.action then
        -- A plain action row (Reset rebinds): the whole right side is one
        -- button rather than a value ladder.
        local aw = Kit.textWidth("small", row.actionLabel or Strings("Run"))
          + math.floor(24 * m.s)
        Kit.text("small", Kit.ellipsize("small", row.label,
          inner - aw - math.floor(12 * m.s)), ix, ly, PAL.text)
        btn(imp, ix + inner - aw, ry + (rowH - m.btnH) / 2, aw, m.btnH,
          key .. "-act", row.actionLabel or Strings("Run"), {
            kind = row.danger and "danger" or "ghost", font = "small",
            action = function()
              if row.action() ~= false then model.save() end
            end })
      else
        local stepW = math.floor(34 * m.s)
        local valW = math.floor(140 * m.s)
        Kit.text("small", Kit.ellipsize("small", row.label,
          inner - 2 * stepW - valW - math.floor(24 * m.s)), ix, ly, PAL.text)
        local rx = ix + inner
        btn(imp, rx - stepW, ry + (rowH - m.btnH) / 2, stepW, m.btnH,
          key .. "-next", ">", { font = "small",
            action = function() if row.step and row.step(1) then model.save() end end })
        Kit.textCenter("small", Kit.ellipsize("small", tostring(row.value()), valW),
          rx - stepW - valW, ly, valW, PAL.heading)
        btn(imp, rx - stepW - valW - stepW, ry + (rowH - m.btnH) / 2, stepW,
          m.btnH, key .. "-prev", "<", { font = "small",
            action = function() if row.step and row.step(-1) then model.save() end end })
      end
    end
  end
  cy = cy + listH + math.floor(8 * m.s)
  setPage(imp, "settings",
    Kit.pager(px + pad, cy, pw - 2 * pad, cur, n, perPage, "settings"))
end

local function buildModals(imp, m)
  if imp._settingsText then
    local st = imp._settingsText
    buildPrompt(imp, m, {
      key = "settext", title = st.row.label, text = st.text,
      okLabel = Strings("Save"),
      commit = function() imp:_commitSettingsText() end,
      cancel = function()
        imp._settingsText = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel"),
    })
    return true
  end
  if imp._settings then buildSettingsModal(imp, m) return true end
  if imp._rename then
    buildPrompt(imp, m, {
      key = "rename", title = Strings("Name save slot"),
      text = imp._rename.text, okLabel = Strings("Save"),
      commit = function() imp:_commitRename() end,
      cancel = function()
        imp._rename = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel - empty clears"),
    })
    return true
  end
  if imp._indexPrompt then
    buildPrompt(imp, m, {
      key = "index", title = Strings("Add a mod index"),
      hint = Strings("Paste the index URL, or its owner/repo."),
      text = imp._indexPrompt.text or "", okLabel = Strings("Add"),
      commit = function() imp:_commitAddIndex() end,
      cancel = function()
        imp._indexPrompt = nil
        imp:_disarmTextInput()
      end,
      paste = function() imp:_pasteIndexUrl() end,
      footnote = Strings("Enter to add - Esc to cancel"),
    })
    return true
  end
  if imp._modConfirm then buildConfirmModal(imp, m) return true end
  if imp._modReleaseNotes then
    local ModUpdate = require("src.mods.ModUpdate")
    local n = imp._modReleaseNotes
    local body = ModUpdate.cleanBody(n.body or "", 0)
    if body == "" then body = Strings("(No release notes.)") end
    buildTextModal(imp, m, "release-notes",
      "v" .. tostring(n.version) .. Strings(" notes"), body,
      function() imp._modReleaseNotes = nil end)
    return true
  end
  if imp._findDetails then
    local ModUpdate = require("src.mods.ModUpdate")
    local d = imp._findDetails
    local body = ModUpdate.cleanBody(d.body or "", 0)
    if body == "" then body = Strings("(No description.)") end
    buildTextModal(imp, m, "find-details", d.title, body,
      function() imp._findDetails = nil end)
    return true
  end
  if imp._modVersions then buildVersionsModal(imp, m) return true end
  return false
end

-- --------------------------------------------------------------- overlays

-- The blocking loader.  imp.workState drives the ROM import (which reports
-- real progress); imp._busy drives every async network operation.
local function loaderSpec(imp)
  if imp.workState == "working" then
    return {
      title = imp.status or Strings("Working"),
      detail = imp.detail,
      progress = imp.progress,
    }
  end
  local b = imp._busy
  if b then
    return { title = b.title, detail = b.detail, progress = b.progress,
             onCancel = b.cancel }
  end
  -- The boot prewarm runs without an overlay (the user did not ask for it and
  -- must be able to use the launcher meanwhile), but if they reach the Find
  -- Mods tab before it lands, THEN they are waiting on it and it earns one.
  if imp.tab == "find" and imp._findFetch and not imp.findLoaded then
    return { title = Strings("Loading mod index") }
  end
  return nil
end

local function drawPadCursor(imp)
  if not imp._padCursorActive then return end
  -- Pixel-snap on NX: subpixel polygon edges shimmer on the 720p Switch
  -- framebuffer when the stick advances by fractional pixels each frame.
  local x, y = imp._padCursor.x, imp._padCursor.y
  if imp.isNX then
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.polygon("fill",
    x + 2, y + 2, x + 2, y + 22, x + 8, y + 16, x + 14, y + 26,
    x + 18, y + 24, x + 11, y + 14, x + 20, y + 14)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.polygon("fill",
    x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
    x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.polygon("line",
    x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
    x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
  love.graphics.pop()
end

-- ------------------------------------------------------------ frame assembly

function LauncherView.draw(imp)
  ensureState(imp)
  local m = Layout.metrics(1200)

  -- The pointer is the pad cursor while it is active, so the ring, hover and
  -- clicks all agree on where "the pointer" is.
  local mx, my = 0, 0
  if imp._padCursorActive then
    mx, my = imp._padCursor.x, imp._padCursor.y
  elseif love.mouse and love.mouse.getPosition then
    mx, my = love.mouse.getPosition()
  end
  local click = imp._clickPt
  if click then mx, my = click.x, click.y end

  Kit.beginFrame(mx, my, click ~= nil, imp._wheelY or 0)
  imp._clickPt = nil
  imp._wheelY = 0

  Theme.field()

  local contentY = buildHeader(imp, m)
  local footH = footerHeight(imp, m)
  local footY = m.top + m.h - footH
  local availH = footY - contentY - m.gap

  local x, w = m.contentX, m.contentW
  if imp.tab == "mods" then
    buildModsPanel(imp, x, contentY, w, availH, m)
  elseif imp.tab == "find" then
    buildFindPanel(imp, x, contentY, w, availH, m)
  else
    buildGamePanel(imp, x, contentY, w, availH, m, imp.tab)
  end

  buildFooter(imp, m, footY)
  buildModals(imp, m)

  -- The loader sits above everything, including modals: it is the one thing
  -- that must never be clicked around.
  local spec = loaderSpec(imp)
  if spec then
    if Loader.overlay(m, spec) and spec.onCancel then
      queueAction(imp, "loader-cancel", spec.onCancel)
    end
  end

  Kit.endFrame()
  drawPadCursor(imp)
end

return LauncherView
