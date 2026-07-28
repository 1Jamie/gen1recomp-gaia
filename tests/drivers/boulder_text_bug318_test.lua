-- Driver: manual check that a boulder answers an A press (#318).
--
-- pokered home/overworld_text.asm:16 is the whole of the behavior:
--     BoulderText::
--             text_far _BoulderText
--             text_end
-- and _BoulderText (data/text/text_1.asm:44) is "This requires\nSTRENGTH to
-- move!".  Every boulder object on every map points its text at that one
-- label, which the extractor records as `asm = true` with a label and no
-- text -- so Data:resolveText returned nil and pressing A at a boulder did
-- nothing at all, no box, no sound.
--
-- The data half is asserted in tests/parity_asm_plain_text.lua.  What this
-- driver adds is the end-to-end path an assertion does not cover: that
-- OverworldState:showMapText actually reaches the fallback for a real map
-- object, and that the box looks right on screen.
--
-- Do NOT add POKEPORT_SPEED: the text box types on the logic clock while
-- Press_AB and the box sounds run on the real-time audio accumulator
-- (src/core/Game.lua), so a fast run misrepresents the moment.
--
--   POKEPORT_DRIVER=tests/drivers/boulder_text_bug318_test.lua \
--     POKEPORT_IDENTITY=bug318 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- pokered data/maps/objects/VictoryRoad1F.asm: BOULDER3 sits at (2, 10).
  -- Its east and west neighbours are both wall, so the free approach is the
  -- floor directly below it, facing up.  (Verified against data/generated/
  -- maps.lua rather than assumed: the two side cells report walkable=false.)
  -- Talking to a boulder needs no STRENGTH and no badge.
  local MAP = "VICTORY_ROAD_1F"
  local BOULDER = "VICTORYROAD1F_BOULDER3"
  local TEXT = "TEXT_VICTORYROAD1F_BOULDER3"
  local MAP_LABEL = "VictoryRoad1F"
  local STAND = { x = 2, y = 11, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- A missing string, a renamed label or a text entry the fallback does not
  -- reach all produce the same nothing-happens as the bug did.
  local text = game.data:resolveText(MAP_LABEL, TEXT)
  check(MAP_LABEL .. "/" .. TEXT .. " resolves to a string",
        type(text) == "string" and text ~= "")
  check("it is _BoulderText verbatim", text == game.data.text._BoulderText)
  check("it mentions STRENGTH",
        type(text) == "string" and text:find("STRENGTH", 1, true) ~= nil)
  if type(text) == "string" then
    U.log("boulder text reads:", (text:gsub("\n", " / ")))
  end

  -- ---- park the player against the boulder -------------------------------
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  local function boulderIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == BOULDER then return n end
    end
    return nil
  end

  -- re-reads game.overworld every call: the fallback below teleports again,
  -- which rebuilds the state and its npc list
  local function facingTheBoulder()
    local ow = game.overworld
    local rock = ow and boulderIn(ow)
    if not rock then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == rock
  end

  local ow = game.overworld
  local rock = ow and boulderIn(ow)
  check("boulder object loaded on " .. MAP, rock ~= nil)

  if rock and not facingTheBoulder() then
    -- the hard-coded approach cell stopped working (map edit, or a mod moved
    -- the object): take any free walkable neighbour and turn back toward it.
    -- {dx, dy, facing} is the offset from the boulder to the stand cell plus
    -- the direction that looks back at it, so +1 on x means facing left.
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = rock.cellX + s[1], rock.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("approach cell (%d, %d) is blocked, standing on")
                :format(STAND.x, STAND.y), cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing against the boulder", facingTheBoulder())

  -- ---- press A once, so the box is already open on hand-off ---------------
  -- The eye cannot tell "no text entry" from "the A press never reached the
  -- boulder", so open the box here and report which of the two happened.
  local TextBox = require("src.render.TextBox")
  U.tap(game, "a")
  U.wait(30)

  local top = game.stack:top()
  local isBox = getmetatable(top) == TextBox
  check("pressing A opened a text box", isBox)
  if isBox then
    local shown = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    local joined = table.concat(shown, " / ")
    U.log("box reads:", joined)
    check("the box is the boulder line, not something else",
          joined:find("STRENGTH", 1, true) ~= nil)
    local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
    U.shot(game, SHOT_DIR .. "/bug318_boulder.png")
    U.log("captured", SHOT_DIR .. "/bug318_boulder.png")
  end

  -- ---- hand off, then stay out of the way --------------------------------
  U.log("........................................................")
  U.log("LOOK NOW: the boulder has already been talked to for you -- the")
  U.log("box on screen is the result.  Press A or B to close it, then press")
  U.log("A again at the boulder to repeat it as often as you like.")
  U.log("  RIGHT: the box types \"This requires\" / \"STRENGTH to move!\"")
  U.log("         over two lines, then the arrow blinks and it waits for")
  U.log("         your A or B.")
  U.log("  BUG #318 looks like: pressing A does nothing whatsoever -- no")
  U.log("         box, no sound, the boulder just sits there.")
  U.log("  ALSO WRONG: the box opens empty or blank, opens and closes")
  U.log("         itself without waiting, or the second line lands on the")
  U.log("         box's bottom border instead of inside it (that one is")
  U.log("         #314, fixed alongside this).")
  U.log("Input is yours from here on -- press A as many times as you like.")
  U.log("There are two more boulders on this floor, at (5,15) and (14,2).")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
