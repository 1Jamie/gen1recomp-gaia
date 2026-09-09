-- FRLG-style start menu on Sevii (pret start_menu.c SetUpStartMenu_NormalField).
-- Window at tilemapLeft=22 (right column), double-spaced entries.

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")

local StartMenu = {}

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

StartMenu.open = false
StartMenu.cursor = 1
StartMenu.ENTRIES = {}

-- pret MENU_POKEDEX..MENU_EXIT order for normal field.
local function build_entries(session)
  local entries = {}
  local Flags = package.loaded["src.core.game3.scripting.flags"]
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.store
  local hasDex = true
  -- Retail gates Pokédex on FLAG_SYS_POKEDEX_GET (SYS_FLAGS+0x29 = 0x829).
  if store and Flags and Flags.getFlag then
    hasDex = Flags.getFlag(store, nil, Flags.IDS and Flags.IDS.SYS_POKEDEX_GET or 0x829) == true
  end
  if hasDex then
    entries[#entries + 1] = { id = "pokedex", label = "POKéDEX" }
  end
  entries[#entries + 1] = { id = "pokemon", label = "POKéMON" }
  entries[#entries + 1] = { id = "bag", label = "BAG" }
  local name = (session and (session.name or session.playerName)) or "PLAYER"
  name = tostring(name)
  if #name > 7 then name = name:sub(1, 7) end
  entries[#entries + 1] = { id = "trainer", label = string.upper(name) }
  entries[#entries + 1] = { id = "save", label = "SAVE" }
  entries[#entries + 1] = { id = "option", label = "OPTION" }
  entries[#entries + 1] = { id = "exit", label = "EXIT" }
  return entries
end

function StartMenu.show(opts)
  opts = opts or {}
  StartMenu.open = true
  StartMenu.cursor = 1
  StartMenu._session = opts.session
  StartMenu._onClose = opts.onClose
  StartMenu.ENTRIES = build_entries(opts.session)
  Stack.push("start", StartMenu, { hideBelow = true })
  se(6) -- SE_WIN_OPEN
end

function StartMenu.close()
  StartMenu.open = false
  Stack.pop("start")
  local cb = StartMenu._onClose
  StartMenu._onClose = nil
  se(9) -- SE_EXIT
  if cb then cb() end
end

function StartMenu.move(delta)
  local n = #StartMenu.ENTRIES
  if n < 1 then return end
  StartMenu.cursor = ((StartMenu.cursor - 1 + delta) % n) + 1
  se(5) -- SE_SELECT
end

function StartMenu.confirm()
  se(5)
  local e = StartMenu.ENTRIES[StartMenu.cursor]
  if not e then return end
  local session = StartMenu._session
  if e.id == "exit" then
    StartMenu.close()
  elseif e.id == "bag" then
    local BagMenu = require("src.ui.game3.bag_menu")
    BagMenu.show(session and session.bag, {
      session = session,
      onClose = function() end,
    })
  elseif e.id == "pokedex" then
    local Pokedex = require("src.ui.game3.pokedex")
    Pokedex.show(session and session.dex, { session = session })
  elseif e.id == "pokemon" then
    local PartyMenu = require("src.ui.game3.party_menu")
    PartyMenu.show(session and session.party, session and session.move_overlay, {
      session = session,
    })
  elseif e.id == "trainer" then
    local TrainerCard = require("src.ui.game3.trainer_card")
    TrainerCard.show({ session = session })
  elseif e.id == "save" then
    local SaveMenu = require("src.ui.game3.save_menu")
    SaveMenu.show({ session = session })
  elseif e.id == "option" then
    local OptionMenu = require("src.ui.game3.option_menu")
    OptionMenu.show({ session = session })
  end
end

function StartMenu.isOpen()
  return StartMenu.open
end

--- pret: content at (22,1), width 7; labels at +8px, rows every 15px.
function StartMenu.contentTemplate()
  local n = math.max(1, #StartMenu.ENTRIES)
  -- Window height in tiles: pret (numActions*2)+2 includes frame padding;
  -- content height for n×15px rows ≈ ceil(n*15/8) tiles.
  local contentH = math.max(2, math.ceil((n * Window.OPTION_HEIGHT) / 8))
  return Window.template(22, 1, 7, contentH)
end

function StartMenu.draw()
  if not StartMenu.open then return end
  local tpl = StartMenu.contentTemplate()
  Window.stdFrame(tpl)
  local leftPx = tpl.left * 8
  local topPx = tpl.top * 8
  for i, e in ipairs(StartMenu.ENTRIES) do
    -- pret: cursor (0, i*15), text (8, i*15) inside the window.
    local yPx = Window.menuRowPx(topPx, i)
    if i == StartMenu.cursor then
      Window.cursorPx(leftPx, yPx)
    end
    Window.printPx(e.label, leftPx + Window.CURSOR_WIDTH, yPx)
  end
end

return StartMenu
