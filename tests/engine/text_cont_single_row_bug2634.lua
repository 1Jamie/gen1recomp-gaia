package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Font = require("src.render.Font")
Font.load({ font = require("tests.fixture_data.font") })
local TextBox = require("src.render.TextBox")
local Version = require("src.core.GameVersion")
local Timing = require("src.core.Timing")
package.loaded["src.core.Sound"] = { play = function() end, playPress = function() end }

local function make(text, opts, save)
  local pressed, pops, calls = false, 0, 0
  local game = {
    data = {}, save = save or { options = { textSpeed = 1 } },
    input = { wasPressed = function(_, key) return pressed == key end,
      isDown = function() return false end },
    stack = { pop = function() pops = pops + 1 end },
  }
  local box = TextBox.new(game, text, function() calls = calls + 1 end, opts)
  return box, function(key)
    pressed = key or false
    box:update(1 / 60)
    pressed = false
  end, function() return pops, calls end
end

local function prompt(box, tick)
  for _ = 1, 200 do
    if box.waiting or box.done then return true end
    tick()
  end
  return false
end

local function advance(box, tick, key)
  for _ = 1, Timing.TEXT_PRE_ADVANCE do tick() end
  tick(key or "a")
end

local function rows(box, expected, label)
  T.eq(#box.shown, #expected, label .. " physical row count")
  for i, text in ipairs(expected) do
    T.same(box.shown[i], Font.encode(text), label .. " glyph row " .. i)
  end
  T.same(box:visibleText(), expected, label .. " visibleText")
  local drawCode, drawBox = Font.drawCode, Font.drawBox
  local drawn = {}
  Font.drawCode = function(code, x, y)
    drawn[#drawn + 1] = { code = code, x = x, y = y }
  end
  Font.drawBox = function() end
  local blink = box.blink
  box.blink = 30
  box:draw()
  box.blink = blink
  Font.drawCode, Font.drawBox = drawCode, drawBox
  local want = {}
  for i, text in ipairs(expected) do
    local x = box.textX
    for _, code in ipairs(Font.encode(text)) do
      want[#want + 1] = { code = code, x = x, y = i == 1 and box.line1Y or box.line2Y }
      x = x + Font.advanceOf(code)
    end
  end
  T.same(drawn, want, label .. " drawn glyph positions")
end

-- pokered/home/text.asm:262
for _, edition in ipairs({ "red", "blue", "yellow" }) do
  Version.set(edition)
  local box, tick, counts = make("A\vB{DONE}")
  T.check(prompt(box, tick), edition .. " reaches cont")
  T.check(box.waiting and box.contAdvance, edition .. " waits before scrolling")
  rows(box, { "A" }, edition .. " before cont")
  tick("a")
  T.check(box.waiting, edition .. " protected wait rejects early A")
  advance(box, tick, "b")
  T.eq(box.holdFrames, Timing.TEXT_SCROLL_PAIR, edition .. " scroll timing")
  T.same(box.shown, { {}, {} }, edition .. " old upper row cleared before typing")
  for _ = 1, Timing.TEXT_SCROLL_PAIR do tick() end
  T.eq(box.charIndex, 0, edition .. " scroll hold suppresses typing")
  T.check(prompt(box, tick), edition .. " completes after one cont press")
  T.check(box.done and not box.waiting, edition .. " has no extra cont prompt")
  rows(box, { "", "B" }, edition .. " single-row cont")
  tick("a")
  local pops, calls = counts()
  T.eq(pops, 1, edition .. " closes once")
  T.eq(calls, 1, edition .. " resumes callback once")
  rows(make("A\vB{DONE}", { instant = true }), { "", "B" }, edition .. " instant cont")
  local plain, plainTick = make("A\nB{DONE}")
  T.check(prompt(plain, plainTick) and plain.done, edition .. " ordinary line has no cont wait")
  rows(plain, { "A", "B" }, edition .. " ordinary line")
end

Version.set("red")
for _, case in ipairs({
  { "A\nB\vC", { "B", "C" }, "two-row cont" },
  { "\vB", { "", "B" }, "leading cont" },
  { "A\v\vB", { "", "B" }, "empty cont" },
  { "A\vB\vC", { "B", "C" }, "successive cont" },
}) do
  local box, tick = make(case[1])
  for _ = 1, 4 do
    T.check(prompt(box, tick), case[3] .. " reaches next prompt")
    if box.done then break end
    advance(box, tick)
  end
  T.check(box.done, case[3] .. " completes")
  rows(box, case[2], case[3])
  rows(make(case[1], { instant = true }), case[2], case[3] .. " instant")
end

local para, tick = make("X\fA\vB")
T.check(prompt(para, tick) and not para.contAdvance, "para waits before clearing")
advance(para, tick)
T.eq(para.holdFrames, Timing.TEXT_PAGE_CLEAR, "para clear timing")
for _ = 1, Timing.TEXT_PAGE_CLEAR do tick() end
T.check(prompt(para, tick) and para.contAdvance, "para restarts at a one-row cont")
rows(para, { "A" }, "para restarts at top")
advance(para, tick)
T.check(prompt(para, tick) and para.done, "para then cont completes")
rows(para, { "", "B" }, "para then cont")

for _, edition in ipairs({ "gold", "firered" }) do
  Version.set(edition)
  local box, tick = make("A\vB")
  T.check(prompt(box, tick) and box.contAdvance, edition .. " reaches cont")
  advance(box, tick)
  T.check(prompt(box, tick) and box.done, edition .. " completes cont")
  rows(box, { "A", "B" }, edition .. " existing row semantics")
  rows(make("A\vB", { instant = true }), { "A", "B" }, edition .. " instant unchanged")
end

Version.set("red")
local save2, tick2 = make("A\vB", nil, { generation = 2, options = { textSpeed = 1 } })
T.check(prompt(save2, tick2), "Gen 2 save reaches cont under default version")
advance(save2, tick2)
T.check(prompt(save2, tick2), "Gen 2 save completes cont")
rows(save2, { "A", "B" }, "Gen 2 save unchanged")

T.finish("text_cont_single_row_bug2634")
