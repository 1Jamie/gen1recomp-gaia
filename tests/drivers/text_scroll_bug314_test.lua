-- Driver: manual look at scrolling text staying inside its box (#314).
--
-- Reported against Oak's speech after the champion, which is where players
-- meet it, but the defect was in every text box that scrolls.  TextBox:draw
-- added the scroll offset to both visible lines, so for the four frames of
-- the slide the incoming line was drawn 8px low -- exactly on the box's
-- bottom border row -- and whenever the typewriter got a character out
-- during those frames, that character appeared on the border.
--
-- pokered does not do a sub-tile scroll at all: ScrollTextUpOneLine
-- (home/text.asm:283) copies the three text rows up a whole row, blanks the
-- bottom one, and waits 5 frames.  Nothing is ever drawn between two rows.
--
-- tests/parity_text_scroll_bounds.lua asserts the invariant directly (no
-- body glyph below line2Y at any point in the scroll), which is a tighter
-- check than an eye can make.  This driver exists so the exact reported
-- moment can be watched without beating the Elite Four: it opens the real
-- _HallOfFameOakText, the same string the Hall of Fame script shows.
--
-- Do NOT add POKEPORT_SPEED: the scroll is four frames long and the
-- typewriter races it, so scaling the logic clock changes the very overlap
-- being judged.
--
--   POKEPORT_DRIVER=tests/drivers/text_scroll_bug314_test.lua \
--     POKEPORT_IDENTITY=bug314 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")

  local TEXT_KEY = "_HallOfFameOakText"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- The bug only shows on a box that scrolls, and a box only scrolls when
  -- the text carries \v (cont) markers.  A text with none would look fine
  -- while proving nothing.
  local text = game.data.text[TEXT_KEY]
  check(TEXT_KEY .. " is in the extracted text", type(text) == "string")
  local conts = 0
  for _ in tostring(text):gmatch("\v") do conts = conts + 1 end
  check("it carries \\v cont markers (this is what scrolls)", conts > 0)
  U.log("   " .. TEXT_KEY .. " has", conts, "cont markers and",
        select(2, tostring(text):gsub("\f", "")), "page breaks")

  -- the page geometry the glyphs have to stay inside
  local probe = TextBox.new(game, "probe")
  U.log("   box rows: line1Y =", probe.line1Y, " line2Y =", probe.line2Y,
        " bottom border row starts at y =",
        (probe.boxTy + probe.boxTh - 1) * 8)
  check("the two text rows are two tiles apart",
        probe.line2Y - probe.line1Y == 16)

  local speed = game.save.options and game.save.options.textSpeed
  U.log("TEXT SPEED (1 fast / 3 mid / 5 slow):", tostring(speed))
  if speed == 5 then
    U.log("NOTE: the overlap is easiest to catch on FAST text speed, where")
    U.log("      the typewriter most often beats the four-frame scroll.")
  end

  -- ---- put the speech on screen ------------------------------------------
  -- somewhere quiet with a plain background, so the box border is easy to
  -- read against it
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(10)

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local box = TextBox.new(game, text)
  game.stack:push(box)
  U.wait(24)
  U.shot(game, SHOT_DIR .. "/bug314_hof_speech.png")
  U.log("captured", SHOT_DIR .. "/bug314_hof_speech.png")

  -- Drive the first few cont scrolls and capture one mid-slide: scrollPx
  -- starts at 8 and drains 2 per drawn frame, so the border overlap (when
  -- it exists at all) is on screen for about four frames and is very easy
  -- to blink past by hand.
  local shots, scrolls = 0, 0
  for _ = 1, 240 do
    if box.waiting then
      U.tap(game, "a")
      U.wait(1)
      if (box.scrollPx or 0) > 0 then
        scrolls = scrolls + 1
        if shots < 2 then
          shots = shots + 1
          U.shot(game, SHOT_DIR .. "/bug314_midscroll_" .. shots .. ".png")
          U.log("captured mid-scroll frame", shots,
                "scrollPx =", box.scrollPx)
        end
      end
    end
    if box.done or game.stack:top() ~= box then break end
    U.wait(1)
  end
  check("the box actually scrolled at least once", scrolls > 0)

  -- ---- hand off, then stay out of the way --------------------------------
  U.log("........................................................")
  U.log("LOOK NOW: Oak's Hall of Fame speech is open, the same string the")
  U.log("champion cutscene shows, already advanced through its first few")
  U.log("scrolls (see the mid-scroll captures above).  Press A to walk")
  U.log("through the rest and watch the BOTTOM BORDER of the box each")
  U.log("time a line scrolls up.")
  U.log("  RIGHT: the old line slides up into the top row while the new")
  U.log("         line types along the bottom row, always clear of the")
  U.log("         border.  The blinking arrow sits in the border corner --")
  U.log("         that one belongs there.")
  U.log("  BUG #314 looks like: as a line scrolls, the first character or")
  U.log("         two of the incoming line flash ON the bottom border,")
  U.log("         cutting through the box edge, then jump up into place.")
  U.log("  ALSO WRONG: the two lines bunch together mid-scroll and never")
  U.log("         separate, or the top line slides up through the top")
  U.log("         border instead of stopping at the first text row.")
  U.log("Input is yours from here on.  Re-run with TEXT SPEED on FAST if")
  U.log("nothing shows -- that is when the typewriter beats the scroll.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
