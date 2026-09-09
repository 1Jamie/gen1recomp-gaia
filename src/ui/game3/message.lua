-- game3 dialog TextPrinter (FRLG field message semantics).
-- Variable-width latin_normal glyphs, typewriter pacing, explicit \\n only.

local TextIR = require("src.core.game3.scripting.text_ir")
local FrlgFont = require("src.ui.game3.frlg_font")
local Chrome = require("src.ui.game3.chrome")
local Display = require("src.core.game3.display")

local Message = {}

Message.open = false
Message._pages = nil
Message._page = 1
Message._done = nil
Message._stay = false
Message._choice = nil
Message._frame = "dialogue" -- "dialogue" | "sign" | "battle"

-- Typewriter state for the current page.
Message._revealed = 0
Message._total = 0
Message._delay = 0
Message._waiting = false -- page fully revealed; waiting for A/B
Message._speedIdx = 1 -- 0 slow / 1 mid / 2 fast
Message._speedUp = false

-- pret sTextSpeedFrameDelays (options 0/1/2)
local SPEED_DELAYS = { 8, 4, 1 }

local function split_pages(box)
  local pages = {}
  for page in (box .. "\f"):gmatch("(.-)\f") do
    if page ~= "" then pages[#pages + 1] = page end
  end
  if #pages == 0 then pages[1] = box or "" end
  return pages
end

local function beginPage()
  local page = Message.currentPage() or ""
  Message._total = FrlgFont.countChars(page)
  Message._revealed = 0
  Message._delay = 0
  Message._waiting = (Message._total == 0)
  Message._speedUp = false
end

function Message.setFrame(kind)
  if kind == "sign" then
    Message._frame = "sign"
  elseif kind == "battle" then
    Message._frame = "battle"
  else
    Message._frame = "dialogue"
  end
end

function Message.frameKind()
  return Message._frame or "dialogue"
end

function Message.show(text, opts)
  opts = opts or {}
  Message.open = true
  Message._stay = opts.stay and true or false
  Message._done = opts.done
  Message._choice = nil
  if opts.frame == "sign" or opts.sign then
    Message._frame = "sign"
  elseif opts.frame == "battle" or opts.battle then
    Message._frame = "battle"
  else
    -- Default field dialogue. Do not keep a sticky "battle" frame after fights
    -- (battle Ui draws its own textbox; field msgs need Chrome.dialogueFrame).
    Message._frame = "dialogue"
  end
  -- Prefer session options text speed when not overridden.
  local speed = opts.speed
  if speed == nil then
    local ok, Options = pcall(require, "src.core.game3.options")
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    if ok and okR and Runtime.getSession then
      speed = Options.textSpeed(Runtime.getSession())
    end
  end
  -- Also honor save-schema alias text_speed if Options path missed.
  if speed == nil and opts.session and opts.session.options then
    speed = opts.session.options.text_speed or opts.session.options.textSpeed
  end
  Message._speedIdx = tonumber(speed) or 1
  if Message._speedIdx < 0 then Message._speedIdx = 0 end
  if Message._speedIdx > 2 then Message._speedIdx = 2 end
  if tonumber(speed) == 0 then
    -- Instant print (Oak repeat question)
    Message._speedIdx = 0
  end

  local plain
  if type(text) == "table" then
    plain = TextIR.toTextBox(text, opts.ctx or {})
  else
    local ir = TextIR.fromAscii(tostring(text or ""))
    plain = TextIR.toTextBox(ir, opts.ctx or {})
  end
  Message._pages = split_pages(plain)
  Message._page = 1
  beginPage()
  if tonumber(speed) == 0 then
    Message.skipReveal()
  end
  return Message
end

function Message.showStay(text, opts)
  opts = opts or {}
  opts.stay = true
  return Message.show(text, opts)
end

function Message.currentPage()
  if not Message._pages then return "" end
  return Message._pages[Message._page] or ""
end

function Message.isOpen()
  return Message.open
end

function Message.isWaiting()
  return Message.open and Message._waiting
end

function Message.isTyping()
  return Message.open and not Message._waiting
end

--- Instantly finish the current page reveal.
function Message.skipReveal()
  if not Message.open then return end
  Message._revealed = Message._total
  Message._delay = 0
  Message._waiting = true
end

function Message.advance()
  if not Message.open then return end
  if Message._choice then return end

  -- While typing: first A/B finishes the page (pret canABSpeedUpPrint).
  if not Message._waiting then
    Message.skipReveal()
    return
  end

  if Message._page < #Message._pages then
    Message._page = Message._page + 1
    beginPage()
    return
  end
  if Message._stay then
    return
  end
  Message.close()
end

function Message.close()
  local done = Message._done
  Message.open = false
  Message._pages = nil
  Message._page = 1
  Message._done = nil
  Message._stay = false
  Message._choice = nil
  Message._revealed = 0
  Message._total = 0
  Message._waiting = false
  if done then done() end
end

function Message.tick()
  if not Message.open or Message._waiting then return end
  if Message._revealed >= Message._total then
    Message._waiting = true
    return
  end
  -- Held A/B: zero inter-glyph delay (canABSpeedUpPrint).
  if Message._speedUp then
    Message._delay = 0
  end
  if Message._delay > 0 then
    Message._delay = Message._delay - 1
    return
  end
  Message._revealed = Message._revealed + 1
  if Message._revealed >= Message._total then
    Message._waiting = true
  else
    local d = SPEED_DELAYS[Message._speedIdx + 1] or 4
    -- Match AddTextPrinter quirk: nonzero speed is stored decremented.
    if d > 0 then d = d - 1 end
    Message._delay = Message._speedUp and 0 or d
  end
end

--- Hold A/B to run at fast speed (field message canABSpeedUpPrint).
function Message.setSpeedUp(held)
  Message._speedUp = held and true or false
end

--- Draw dialogue frame + text (and optional prompt).
function Message.draw()
  if not Message.open then return end
  if Message._frame == "sign" then
    Chrome.signFrame()
  elseif Message._frame == "battle" then
    -- Battle textbox chrome is drawn by battle Ui; text only here.
  else
    Chrome.dialogueFrame()
  end
  Message.drawText()
end

--- Draw dialogue text (and optional prompt) into the content window.
-- Caller draws frame first unless using Message.draw().
function Message.drawText()
  if not Message.open then return end
  local page = Message.currentPage() or ""
  local baseX, baseY, maxW
  if Message._frame == "battle" then
    -- Window at tile (1,15)=px(8,120); printer x=2,y=2 → (10,122).
    -- Panel chrome now drawn from y=112.
    baseX, baseY, maxW = 10, 122, 224
  else
    baseX = Chrome.DLG_LEFT * Display.TILE
    baseY = Chrome.DLG_TOP * Display.TILE + 1
    maxW = Chrome.DLG_W * Display.TILE
  end
  FrlgFont.draw(page, baseX, baseY, {
    maxWidth = maxW,
    limitChars = Message._revealed,
    colors = (Message._frame == "battle") and FrlgFont.COLOR.WHITE or FrlgFont.COLOR.NORMAL,
  })

  if Message._waiting and not Message._stay then
    local t = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
    local frame = math.floor(t * 8) % 8
    local bounce = ({ 0, 1, 2, 1 })[1 + (math.floor(t * 8) % 4)] or 0
    local ax, ay
    if Message._frame == "battle" then
      ax, ay = 222, 148 - bounce
    else
      ax = (Chrome.DLG_LEFT + Chrome.DLG_W - 2) * Display.TILE
      ay = (Chrome.DLG_TOP + Chrome.DLG_H - 1) * Display.TILE - bounce
    end
    Chrome.promptArrow(ax, ay, frame)
  end
end

return Message
