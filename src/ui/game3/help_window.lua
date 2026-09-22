-- Help MESSAGE window behind the `loadhelp` / `unloadhelp` seam
-- (docs/game3/e10-opcode-spec.md sections 5.5/5.6).
--
-- pret: DrawHelpMessageWindowWithText(text) (src/new_menu_helpers.c:701-705)
-- creates the bottom-bar help window, prints, and returns;
-- DestroyHelpMessageWindow_() (src/new_menu_helpers.c:707-710) tears it down.
-- Both are idempotent (src/help_message.c:23-31 create, :35-51 destroy), the
-- window template is {left=0, top=15, width=30, height=5, paletteNum=15}
-- (src/help_message.c:13-19), and the same window carries the Start menu item
-- descriptions (src/start_menu.c:332 draw, :440 destroy). This is NOT the L/R
-- context browser in src/ui/game3/help_system.lua, and it is deliberately not
-- capability-gated: pret's window is generic menu plumbing, while the
-- `helpSystem` capability maps to the FireRed-only src/help_system.c.
--
-- Text arrives as a plain string — the `loadhelp` word is resolved by the
-- script handler with resolve_text (ops_a.lua:36-45), not here.
--
-- New file, unwired: `loadhelp`/`unloadhelp` dispatch cases and the frame hook
-- are the Finisher's handoff; the engine canvas is 30x20x8 (display.lua:9-11),
-- so pret's bottom five tile rows map 1:1.

local Window = require("src.ui.game3.window")

local HelpWindow = {}

-- pret sHelpMessageWindowTemplate (src/help_message.c:13-19)
HelpWindow.OUTER = { left = 0, top = 15, width = 30, height = 5, paletteNum = 15 }
-- Engine stdFrame draws the nine-slice *outside* the content rect (chrome.lua
-- stdFrame fallback fills (tx*8-8, ty*8-8, (tw+2)*8, (th+2)*8)), so the content
-- rect is pret's outer rect inset by one tile: the frame lands exactly on
-- 0,15..30,20. Content is 28x3 tiles.
HelpWindow.CONTENT = { left = 1, top = 16, width = 28, height = 3 }
-- pret PrintHelpMessageText prints at x=2, y=5 inside its window
-- (src/help_message.c:95-98). pret's own msg_window gfx supplies that window's
-- border; the engine draws a std nine-slice instead, so the same pixel offsets
-- are applied to the content rect (one tile in) rather than to the outer
-- origin, which would put the text under the frame's left border tile.
HelpWindow.TEXT_OFFSET = { x = 2, y = 5 }

local open = false
local text = ""

local function contentTemplate()
  local c = HelpWindow.CONTENT
  return Window.template(c.left, c.top, c.width, c.height,
    { paletteNum = HelpWindow.OUTER.paletteNum })
end

--- Show the help window (pret DrawHelpMessageWindowWithText). Re-showing with
-- text replaces the content, matching pret's second PrintText call.
function HelpWindow.show(value)
  text = type(value) == "string" and value or ""
  open = true
  return true
end

--- Hide it (pret DestroyHelpMessageWindow_): safe with nothing open.
function HelpWindow.close()
  open = false
  text = ""
  return true
end

function HelpWindow.isOpen()
  return open
end

--- The current text ("" when closed) — the seam's test surface.
function HelpWindow.getText()
  return text
end

--- Draw one frame. No-op when closed; the draw path calls it unconditionally.
function HelpWindow.draw()
  if not open then return false end
  local tpl = contentTemplate()
  -- pret FillWindowPixelBuffer before printing (src/help_message.c:41): clear
  -- the interior with the window's background (white, as in the engine's other
  -- fill user new_game_scene.lua:1640), then the std nine-slice on top.
  Window.fill(tpl, 1, 1, 1, 1)
  Window.stdFrame(tpl)
  if text ~= "" then
    local c = HelpWindow.CONTENT
    local off = HelpWindow.TEXT_OFFSET
    Window.printPx(text, c.left * 8 + off.x, c.top * 8 + off.y, {
      maxWidth = c.width * 8 - off.x * 2,
    })
  end
  return true
end

--- Test/tool hook: close and forget everything.
function HelpWindow.reset()
  HelpWindow.close()
end

return HelpWindow
