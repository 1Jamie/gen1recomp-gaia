-- the OPTION row and its ladder, the launcher gear row, the mod-facing member
-- table -- plus the band geometry Game2 paints, asserted as rectangles rather
-- than as pixels.
--
-- What colour those bands actually come out is not a claim this file makes;
-- tests/drivers/gold_battle_bg_bug1709_test.lua is where a human judges that.

package.path = "./?.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or { random = function(a, b) return b and a or 0.5 end }
love.image = love.image or {}
love.timer = love.timer or { getTime = function() return 0 end }
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
require("src.core.Logger").warn = function() end

local BattleState = require("src.ui.gen2.BattleState")
local Chrome = require("src.ui.gen2.Chrome")
local Game2 = require("src.core.Game2")
local Gen2Compat = require("src.mods.Gen2Compat")
local LauncherSettings = require("src.import.LauncherSettings")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Save = require("src.core.gen2.Save")
local ScreenPosition = require("src.core.ScreenPosition")

local checks, failures = 0, 0
local function check(label, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(label, tostring(got),
      tostring(want)))
  end
end

-- --------------------------------------------------------------- the key

check("the default surround is the cart's paper white",
  Save.DEFAULT_OPTIONS.battleBg, "white")
check("and a fresh options table carries it",
  Save.defaultOptions().battleBg, "white")

check("the default battle size is the whole-pixel blit",
  Save.DEFAULT_OPTIONS.battleFit, "fixed")
check("and a fresh options table carries that too",
  Save.defaultOptions().battleFit, "fixed")

-- --------------------------------------------------------------- the row

local function rowNamed(label)
  for i, row in ipairs(OptionsMenu.ROWS) do
    if row.label == label then return i, row end
  end
end

local bgIndex, bgRow = rowNamed("BATTLE BG")
check("OPTION has a BATTLE BG row", bgRow ~= nil, true)
if bgRow then
  check("it edits battleBg", bgRow.key, "battleBg")
  check("it is a port row, not one of the cart's seven", bgRow.port, true)
  check("WHITE, BLACK and WORLD are the whole ladder", #bgRow.values, 3)
  check("stored lowercase, shown WHITE", bgRow.display.white, "WHITE")
  check("and BLACK", bgRow.display.black, "BLACK")
  check("and WORLD", bgRow.display.world, "WORLD")
  -- Appended at the tail, so nothing the other suites index by position moves.
  check("it follows BATTLE SIZE",
    OptionsMenu.ROWS[bgIndex - 1].label, "BATTLE SIZE")
  check("and CANCEL still ends the list",
    OptionsMenu.ROWS[bgIndex + 1].cancel, true)
  check("CANCEL is last", bgIndex + 1, #OptionsMenu.ROWS)
end

local sizeIndex, sizeRow = rowNamed("BATTLE SIZE")
check("OPTION has a BATTLE SIZE row", sizeRow ~= nil, true)
if sizeRow then
  check("it edits battleFit", sizeRow.key, "battleFit")
  check("it is a port row, not one of the cart's seven", sizeRow.port, true)
  check("FIXED and FILL are the whole ladder", #sizeRow.values, 2)
  check("stored lowercase, shown FIXED", sizeRow.display.fixed, "FIXED")
  check("and FILL, padded to the value column",
    sizeRow.display.fill, "FILL ")
  check("it sits in the port's tail, past the cart's seven",
    sizeIndex > 7, true)
  check("BATTLE BG comes straight after it", sizeIndex + 1, bgIndex)
end
check("the cart's rows are unmoved", OptionsMenu.ROWS[7].key, "frame")
check("the rebind screen is unmoved", OptionsMenu.ROWS[8].id, "controls")
check("the port's audio group is unmoved", OptionsMenu.ROWS[9].key, "musicVol")

-- The screen is built from ROWS, so the row has to survive buildRows too.
local menu = OptionsMenu.new({ options = Save.defaultOptions() },
  { options = Save.defaultOptions() })
local built
for _, row in ipairs(menu.rows) do
  if row.key == "battleBg" then built = row end
end
check("buildRows keeps it", built ~= nil, true)
if built then
  check("and gives it the mod-facing id battleBg", built.id, "battleBg")
  check("the menu starts on WHITE", menu.options.battleBg, "white")
  menu:cycle(built, 1)
  check("right stores black, not the display string",
    menu.options.battleBg, "black")
  menu:cycle(built, 1)
  check("right again reaches world", menu.options.battleBg, "world")
  menu:cycle(built, 1)
  check("and wraps to white", menu.options.battleBg, "white")
  menu:cycle(built, -1)
  check("left walks the ladder the other way", menu.options.battleBg, "world")
  menu:cycle(built, -1)
  check("still the other way", menu.options.battleBg, "black")
  menu:cycle(built, -1)
  check("and back", menu.options.battleBg, "white")
end

local builtFit
for _, row in ipairs(menu.rows) do
  if row.key == "battleFit" then builtFit = row end
end
check("buildRows keeps BATTLE SIZE", builtFit ~= nil, true)
if builtFit then
  check("and gives it the mod-facing id battleFit", builtFit.id, "battleFit")
  check("the menu starts on FIXED", menu.options.battleFit, "fixed")
  menu:cycle(builtFit, 1)
  check("right stores fill, not the display string",
    menu.options.battleFit, "fill")
  menu:cycle(builtFit, 1)
  check("right again wraps to fixed", menu.options.battleFit, "fixed")
  menu:cycle(builtFit, -1)
  check("left walks the ladder the other way", menu.options.battleFit, "fill")
  menu:cycle(builtFit, -1)
  check("and back", menu.options.battleFit, "fixed")
end

-- ------------------------------------------------------ the launcher gear

local model = LauncherSettings.open(nil, "gold")
local gearRow
for _, section in ipairs(model.sections) do
  for _, row in ipairs(section.rows) do
    if row.label == "BATTLE BG" then gearRow = row end
  end
end
check("the gold gear offers BATTLE BG", gearRow ~= nil, true)
if gearRow then
  model.opts.gold.battleBg = nil
  check("an options.lua with no battleBg reads WHITE", gearRow.value(), "WHITE")
  gearRow.step(1)
  check("stepping writes the gold block, not the flat Gen 1 one",
    model.opts.gold.battleBg, "black")
  check("and the row reads BLACK", gearRow.value(), "BLACK")
  gearRow.step(1)
  check("stepping again reaches world", model.opts.gold.battleBg, "world")
  check("and the row reads WORLD", gearRow.value(), "WORLD")
  gearRow.step(1)
  check("stepping again returns to white", model.opts.gold.battleBg, "white")
end

local gearSize
for _, section in ipairs(model.sections) do
  for _, row in ipairs(section.rows) do
    if row.label == "BATTLE SIZE" then gearSize = row end
  end
end
check("the gold gear offers BATTLE SIZE", gearSize ~= nil, true)
if gearSize then
  model.opts.gold.battleFit = nil
  check("an options.lua with no battleFit reads FIXED", gearSize.value(),
    "FIXED")
  gearSize.step(1)
  check("stepping writes the gold block, not the flat Gen 1 one",
    model.opts.gold.battleFit, "fill")
  check("and the row reads FILL", gearSize.value(), "FILL")
  gearSize.step(1)
  check("stepping again returns to fixed", model.opts.gold.battleFit, "fixed")
end

-- ---------------------------------------------------------- the battle end

local bgMode = BattleState.bgMode
check("the Gold battle screen answers bgMode", type(bgMode), "function")
if type(bgMode) == "function" then
  check("black when the option says so",
    bgMode({ game = { options = { battleBg = "black" } } }), "black")
  check("white when it says white",
    bgMode({ game = { options = { battleBg = "white" } } }), "white")
  check("white on an options table that predates the key",
    bgMode({ game = { options = {} } }), "white")
  check("white with no game at all", bgMode({}), "white")
  check("and WORLD is the third rung, not a stray value",
    bgMode({ game = { options = { battleBg = "world" } } }), "world")
  check("an unknown mode still falls back to white",
    bgMode({ game = { options = { battleBg = "plaid" } } }), "white")
end

check("the battle screen is opaque in every mode", BattleState.isOpaque, true)

check("the dim the WORLD veil is painted at is published",
  BattleState.BG_WORLD_DIM, 0.55)

check("and mods are told bgMode is backed on this side",
  Gen2Compat.memberStatus("src.battle.BattleState", "bgMode"), "backed")
check("as is the dim they would read off it",
  Gen2Compat.memberStatus("src.battle.BattleState", "BG_WORLD_DIM"), "backed")

-- ------------------------------------------------------------- the bands
--
-- Game2 paints the surround, not the battle screen: the widescreen layer
-- resolves to the TOP state, so a party menu or text box opened over the
-- battle would otherwise repaint the void white under itself.

local G = love.graphics
local realRect, realSetColor = G.rectangle, G.setColor
local painter = Game2.paintBattleSurround
check("Game2 owns the surround repaint", type(painter), "function")

local function paint(states, w, h)
  if type(painter) ~= "function" then return {} end
  local rects, pen = {}, { 1, 1, 1, 1 }
  G.setColor = function(r, g, b, a)
    pen = { r or 0, g or 0, b or 0, a or 1 }
  end
  G.rectangle = function(_, x, y, rw, rh)
    rects[#rects + 1] = { x = x, y = y, w = rw, h = rh, pen = pen }
  end
  local ok, err = pcall(painter, { stack = { states = states } }, w, h)
  G.rectangle, G.setColor = realRect, realSetColor
  if not ok then
    check("paintBattleSurround ran: " .. tostring(err), false, true)
  end
  return rects
end

local blackBattle = { bgMode = function() return "black" end }
local whiteBattle = { bgMode = function() return "white" end }
local worldBattle = {
  bgMode = function() return "world" end,
  BG_WORLD_DIM = BattleState.BG_WORLD_DIM,
}
local plainMenu = {}
local overworld = {}

check("BLACK paints the four bands", #paint({ blackBattle }, 1024, 768), 4)
check("WHITE paints nothing at all", #paint({ whiteBattle }, 1024, 768), 0)
check("WORLD paints the same four bands, as a veil",
  #paint({ worldBattle }, 1024, 768), 4)
check("the overworld alone paints nothing",
  #paint({ overworld, plainMenu }, 1024, 768), 0)

-- A menu over the battle keeps the battle's void: the walk goes down the
-- stack past states that have no bgMode of their own.
check("a party menu over the battle still finds the battle's mode",
  #paint({ overworld, blackBattle, plainMenu }, 1024, 768), 4)
check("and the same under WORLD",
  #paint({ overworld, worldBattle, plainMenu }, 1024, 768), 4)

local blackPen = paint({ blackBattle }, 1024, 768)[1]
local worldPen = paint({ worldBattle }, 1024, 768)[1]
check("BLACK is opaque", blackPen and blackPen.pen[4], 1)
check("WORLD is the published dim", worldPen and worldPen.pen[4],
  BattleState.BG_WORLD_DIM)
check("and a zero dim paints nothing", #paint({
  { bgMode = function() return "world" end, BG_WORLD_DIM = 0 } }, 1024, 768), 0)

local function panelSafe(states, w, h, label, scale)
  scale = scale or Chrome.fitScale(w, h)
  local ox, oy = Chrome.fitOrigin(w, h, scale)
  local pw, ph = 160 * scale, 144 * scale
  local rects = paint(states, w, h)
  local covered, overlap, offColour = 0, 0, 0
  for _, r in ipairs(rects) do
    covered = covered + r.w * r.h
    if r.pen[1] ~= 0 or r.pen[2] ~= 0 or r.pen[3] ~= 0 then
      offColour = offColour + 1
    end
    local ix = math.max(0, math.min(r.x + r.w, ox + pw) - math.max(r.x, ox))
    local iy = math.max(0, math.min(r.y + r.h, oy + ph) - math.max(r.y, oy))
    overlap = overlap + ix * iy
  end
  -- The band maths has to tile the void exactly: any overlap with the panel is
  -- a black frame eating the HUD or the message box, and any shortfall is a
  -- strip of white left behind on one edge.
  check(label .. ": no band touches the battle panel", overlap, 0)
  check(label .. ": the void is covered edge to edge",
    math.abs(covered - (w * h - pw * ph)) < 1, true)
  check(label .. ": every band is black", offColour, 0)
end

for _, size in ipairs({ { 1024, 768 }, { 1280, 840 }, { 1920, 1080 },
    { 800, 600 }, { 1366, 768 } }) do
  panelSafe({ blackBattle }, size[1], size[2],
    ("%dx%d"):format(size[1], size[2]))
  panelSafe({ worldBattle }, size[1], size[2],
    ("world %dx%d"):format(size[1], size[2]))
end

-- SCREEN POS lifts the panel off centre, which is the other way the four
-- bands can stop agreeing with where the panel actually landed.
for _, mode in ipairs({ "center", "upper", "top" }) do
  ScreenPosition.setMode(mode)
  panelSafe({ blackBattle, plainMenu }, 1280, 840, "screen pos " .. mode)
end
ScreenPosition.setMode("center")

-- A window smaller than the GB screen has no void to paint; the bands must
-- not wrap around to the far edge on the negative origin.
check("nothing to paint under 160x144", #paint({ blackBattle }, 100, 90), 0)

local wantsFill = BattleState.wantsFillScale
check("the Gold battle screen answers wantsFillScale", type(wantsFill),
  "function")
if type(wantsFill) == "function" then
  check("FILL asks for the fill scale",
    wantsFill({ game = { options = { battleFit = "fill" } } }), true)
  check("FIXED does not",
    wantsFill({ game = { options = { battleFit = "fixed" } } }), false)
  check("nor does an options table that predates the key",
    wantsFill({ game = { options = {} } }), false)
  check("nor a screen with no game at all", wantsFill({}), false)
end

check("FIXED is the integer fit", BattleState.panelScale(1280, 840, false),
  Chrome.fitScale(1280, 840))
check("FILL is min(w/160, h/144)", BattleState.fillScale(1280, 840), 840 / 144)
check("and FILL is not the integer fit here",
  BattleState.fillScale(1280, 840) ~= Chrome.fitScale(1280, 840), true)
check("FILL never goes below one whole pixel",
  BattleState.fillScale(100, 90), 1)

local fillBattle = {
  bgMode = function() return "black" end,
  battlePanelScale = function(_, w, h) return BattleState.fillScale(w, h) end,
}
for _, size in ipairs({ { 1280, 840 }, { 1366, 768 }, { 1024, 768 } }) do
  panelSafe({ fillBattle }, size[1], size[2],
    ("fill %dx%d"):format(size[1], size[2]),
    BattleState.fillScale(size[1], size[2]))
  panelSafe({ fillBattle, plainMenu }, size[1], size[2],
    ("fill under a menu %dx%d"):format(size[1], size[2]),
    BattleState.fillScale(size[1], size[2]))
end

local widescreenMenu = { drawsWidescreen = function() return true end }
panelSafe({ fillBattle, widescreenMenu }, 1280, 840,
  "a widescreen menu over a fill battle", Chrome.fitScale(1280, 840))

-- ----------------------------------------------------- the call site

local function scene(mode, opts)
  opts = opts or {}
  local log = {}
  local function note(what)
    log[#log + 1] = { what = what, flag = Chrome.worldSurround }
  end
  local battle = {
    isOpaque = true,
    drawsWidescreen = function() return true end,
    drawWidescreen = function() note("widescreen") end,
    bgMode = function() return mode end,
    BG_WORLD_DIM = BattleState.BG_WORLD_DIM,
  }
  if opts.fill then
    battle.battlePanelScale = function(_, w, h)
      return BattleState.fillScale(w, h)
    end
  end
  local states = { battle }
  if opts.menu then states[2] = plainMenu end
  local game = {
    stack = {
      states = states,
      top = function(self) return self.states[#self.states] end,
      renderVisible = function(_, state) return state ~= nil end,
      visibleBase = function() return 1 end,
      draw = function() note("stack") end,
    },
    world = { map = {}, draw = function() note("world") end },
    inFillBoot = function() return false end,
    letterbox = function(_, _, _, worldActive)
      note(worldActive and "letterbox(world)" or "letterbox")
    end,
    paintBattleSurround = function() note("surround") end,
  }
  local scales = {}
  local realScale = G.scale
  G.scale = function(sx, sy) scales[#scales + 1] = sx; realScale(sx, sy) end
  Chrome.worldSurround = true -- a stale flag drawScene has to clear itself
  local ok, err = pcall(Game2.drawScene, game, 1280, 840)
  G.scale = realScale
  Chrome.worldSurround = false
  if not ok then check("drawScene ran: " .. tostring(err), false, true) end
  local order, flags = {}, {}
  for i, entry in ipairs(log) do
    order[i], flags[entry.what] = entry.what, entry.flag
  end
  return table.concat(order, ","), flags, game, scales
end

do
  local order, flags, game = scene("world")
  check("a WORLD battle puts the map up before the widescreen layer",
    order, "letterbox(world),world,widescreen,surround,letterbox")
  check("the widescreen layer paints with the paper suppressed",
    flags["widescreen"], true)
  check("and so does the surround", flags["surround"], true)
  check("the flag is down again by the closing letterbox",
    flags["letterbox"], false)
  check("and down when drawScene returns", Chrome.worldSurround, false)
  check("the frame is marked as having drawn the world",
    game.frameWorldActive, true)
end

do
  local order, flags, game = scene("black")
  check("BLACK never draws the map", order, "widescreen,surround,letterbox")
  check("and never suppresses the paper", flags["widescreen"], false)
  check("nor marks the frame", game.frameWorldActive, false)
end

do
  local order, _, _, scales = scene("black", { fill = true, menu = true })
  check("a menu over the battle blits over the widescreen layer",
    order, "widescreen,surround,letterbox,stack")
  check("at the battle's own panel scale", scales[1],
    BattleState.fillScale(1280, 840))
end

do
  local painted = 0
  local rect, setColor = G.rectangle, G.setColor
  G.rectangle = function() painted = painted + 1 end
  G.setColor = function() end
  local ok = pcall(Chrome.letterbox, 320, 288, 1, 1, 1)
  local down = painted
  Chrome.worldSurround = true
  local okUp = pcall(Chrome.letterbox, 320, 288, 1, 1, 1)
  Chrome.worldSurround = false
  G.rectangle, G.setColor = rect, setColor
  check("Chrome.letterbox paints the paper by default", ok and down, 1)
  check("and stands down for a WORLD surround", okUp and painted, 1)
end
check("and the flag is down by default", Chrome.worldSurround, false)

print(("gen2 battle options: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
