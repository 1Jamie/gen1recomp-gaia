local Theme = require("Theme")
local Touch = require("TouchEditor")
local PAL = Theme.PAL
local Form = {}

local ERROR_FILL = { 58, 31, 37 }

function Form.thousands(n)
  n = tonumber(n)
  if not n then return "?" end
  local str = tostring(math.floor(math.abs(n)))
  str = str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-" or "") .. str
end

function Form.range(l)
  return Form.thousands(l.lo) .. " – " .. Form.thousands(l.hi)
end

function Form.labelH(Kit)
  return Kit.textHeight("small") + 8 * Kit.scale
end

function Form.label(Kit, text, x, y, w, right, color, rightColor)
  local rw = right and Kit.textWidth("small", right) + 10 * Kit.scale or 0
  Kit.text("small", Kit.ellipsize("small", text, math.max(0, w - rw)), x, y, color or PAL.muted)
  if right then
    Kit.textRight("small", right, x + w, y, rightColor or PAL.muted)
  end
  return Form.labelH(Kit)
end

function Form.wrapH(Kit, font, text, w)
  local f = Kit.fonts[font] or Kit.fonts.small
  if not f or w <= 0 then return 0 end
  if not f.getWrap then return f:getHeight() end
  local _, lines = f:getWrap(tostring(text), w)
  return #lines * f:getHeight()
end

function Form.issueH(Kit, message, w)
  if not message then return 0 end
  local size, gap = 14 * Kit.scale, 6 * Kit.scale
  return math.max(size, Form.wrapH(Kit, "tiny", message, w - size - gap)) + gap
end

function Form.box(Kit, x, y, w, h, text, invalid, color)
  local r = Theme.radius()
  Theme.fillRounded(x, y, w, h, invalid and ERROR_FILL or PAL.rowBg, 0.7, r)
  Theme.stroke(x, y, w, h, r, invalid and PAL.red or PAL.cardBorder, invalid and 0.95 or 0.3,
    invalid and 2 * Kit.scale or 1)
  local pad = 14 * Kit.scale
  Kit.textBold("button", Kit.ellipsize("button", tostring(text), w - 2 * pad), x + pad,
    y + (h - Kit.textHeight("button")) / 2, color or (invalid and PAL.red or PAL.heading))
end

function Form.select(S, Kit, id, title, value, options, x, y, w, apply, issue, help)
  local shown
  for _, o in ipairs(options) do
    if o[1] == value then shown = o[2] end
  end
  shown = shown or ((issue and "Invalid saved value " or "Unknown saved value ") .. tostring(value))
  local opts = {
    face = "invert",
    font = "button",
    align = "left",
    trailingIcon = "chevron-down",
    id = "choice-" .. id,
    invalid = issue ~= nil,
  }
  local h = Kit.buttonHeight(shown, w, opts)
  if Kit.button(x, y, w, h, shown, opts) then
    Touch.open(S, Kit, {
      mode = "choice", id = id, title = title, value = value, options = options,
      apply = apply, help = help, issue = issue,
    })
  end
  return h
end

local function digits(v)
  return (tostring(v or ""):gsub("[^0-9]", ""):sub(1, 8))
end

function Form.number(S, Kit, id, value, x, y, w, h, apply, issue, preview)
  local key = "value-edit-" .. id
  local function commit(v)
    local n = tonumber(v)
    if not n then return require("Ops").say(S, "Enter a whole number") end
    if n ~= value then apply(n) end
  end
  local edit = S.valueEdit
  if edit and edit.id == id and Kit.focus ~= key then
    S.valueEdit = nil
    if edit.draft ~= tostring(value) then commit(edit.draft) end
    edit = nil
  end
  if edit and edit.id == id then
    local v = Kit.textfield(key, x, y, w, h, edit.draft, "", {
      sanitize = digits,
      invalid = issue ~= nil,
      onSubmit = function(text)
        S.valueEdit = nil
        commit(text)
      end,
      onCancel = function()
        S.valueEdit = nil
      end,
    })
    if S.valueEdit == edit then edit.draft = v end
    return
  end
  local opts = { face = "invert", font = "button", align = "left", id = "value-" .. id, invalid = issue ~= nil }
  if Kit.button(x, y, w, h, tostring(preview or value), opts) then
    S.valueEdit = { id = id, draft = tostring(value) }
    Kit.requestKeyboard(key)
    Kit._fieldHit, Kit._focusDrawn = true, true
  end
end

function Form.slider(S, Kit, id, value, l, x, y, w, h, apply, issue)
  local s = Kit.scale
  local knob = 9 * s
  local tx, tw = x + knob, math.max(1, w - 2 * knob)
  local function at(mx)
    return math.floor(l.lo + Theme.clamp((mx - tx) / tw, 0, 1) * (l.hi - l.lo) + 0.5)
  end
  local shown, committed = tonumber(value), false
  local d = S._slider
  if d and d.id == id then
    if Kit.mouseDown then
      if not d.live and not d.scroll then
        local dx, dy = math.abs(Kit.mouseX - d.x), math.abs(Kit.mouseY - d.y)
        if dx > 6 * s and dx >= dy then
          d.live = true
        elseif dy > 6 * s then
          d.scroll = true
        end
      end
      if d.live then
        d.value = at(Kit.mouseX)
        shown = d.value
      end
    else
      S._slider = nil
      if d.live then
        committed = true
        if d.value ~= value then apply(d.value) end
        shown = d.value
      end
    end
  elseif not d and Kit.mouseDown and not Kit.blockClicks and Kit.hit(x, y, w, h) then
    S._slider = { id = id, x = Kit.mouseX, y = Kit.mouseY }
  end
  if Kit.button(x, y, w, h, "", { face = "bare", id = "slider-" .. id }) and not committed then
    local v = at(Kit.mouseX)
    if v ~= value then apply(v) end
    shown = v
  end
  local ratio = shown and Theme.clamp((shown - l.lo) / math.max(1, l.hi - l.lo), 0, 1) or 0
  local color = issue and PAL.red or PAL.blue
  local trackH = 6 * s
  local cy = y + h / 2
  Theme.fillRounded(tx, cy - trackH / 2, tw, trackH, PAL.cardBorder, 0.3, trackH / 2)
  if ratio > 0 then
    Theme.fillRounded(tx, cy - trackH / 2, tw * ratio, trackH, color, 0.95, trackH / 2)
  end
  Theme.col(color)
  love.graphics.circle("fill", tx + tw * ratio, cy, knob, 32)
  return shown ~= tonumber(value) and shown or nil
end

function Form.numberRow(S, Kit, id, title, value, l, x, y, w, apply, issue)
  local s, row = Kit.scale, Kit.controlH()
  if not require("Legality").integer(value, l.lo, l.hi) then
    issue = issue or ("Saved value must be a whole number from " .. l.lo .. " to " .. l.hi)
  end
  local right = Form.range(l)
  if l.remaining ~= nil then right = right .. "  ·  " .. l.remaining .. " free" end
  local cy = y + Form.label(Kit, title, x, y, w, right, issue and PAL.red or PAL.muted)
  local boxW = math.floor(math.min(math.max(110 * s, Kit.textWidth("button", tostring(l.hi)) + 40 * s), w * 0.42))
  local gap = 16 * s
  local preview = Form.slider(S, Kit, id, value, l, x + boxW + gap, cy, w - boxW - gap, row, apply, issue)
  Form.number(S, Kit, id, value, x, cy, boxW, row, apply, issue, preview)
  cy = cy + row
  if issue then
    cy = cy + 6 * s + Touch.issue(Kit, issue, x, cy + 6 * s, w)
  end
  return cy - y
end

function Form.segmented(Kit, id, options, value, x, y, w, h, apply, issue)
  local s = Kit.scale
  local inset, r = 4 * s, Theme.radius()
  Theme.fillRounded(x, y, w, h, PAL.rowBg, 0.7, r)
  Theme.stroke(x, y, w, h, r, issue and PAL.red or PAL.cardBorder, issue and 0.95 or 0.3, issue and 2 * s or 1)
  local segW = w / #options
  for i, o in ipairs(options) do
    local sx = x + (i - 1) * segW
    local active = o[1] == value
    if active then
      Theme.fillRounded(sx + inset, y + inset, segW - 2 * inset, h - 2 * inset, PAL.ink, 1, r - inset)
    elseif not Kit.blockClicks and Kit.hover(sx, y, segW, h) then
      Theme.fillRounded(sx + inset, y + inset, segW - 2 * inset, h - 2 * inset, PAL.raised, 1, r - inset)
    end
    local opts = { face = "bare", font = "button", ink = active and PAL.inverse or PAL.text, id = id .. "-" .. tostring(o[1]) }
    if Kit.button(sx, y, segW, h, o[2], opts) and not active then
      apply(o[1])
    end
  end
end

local function flow(Kit, caption, actions, x, y, w, draw)
  local s, row = Kit.scale, Kit.controlH()
  local gap = 10 * s
  local cx, cy = x, y
  if caption then
    if draw then Kit.caption(x, y + (row - Kit.textHeight("caption")) / 2, caption) end
    cx = x + Kit.captionWidth(caption) + 18 * s
  end
  for _, a in ipairs(actions) do
    local opts = {}
    for k, v in pairs(a[3] or {}) do opts[k] = v end
    opts.font = opts.font or "button"
    local bw = math.min(w, Kit.buttonWidth(a[1], opts, row))
    if cx > x and cx + bw > x + w then
      cx, cy = x, cy + row + gap
    end
    if draw and Kit.button(cx, cy, bw, row, a[1], opts) then a[2]() end
    cx = cx + bw + gap
  end
  return cy + row - y
end

function Form.flowH(Kit, caption, actions, w)
  return flow(Kit, caption, actions, 0, 0, w, false)
end

function Form.flow(Kit, caption, actions, x, y, w)
  return flow(Kit, caption, actions, x, y, w, true)
end

function Form.tabsFit(Kit, options, w, h)
  local s = Kit.scale
  local widths, total = {}, 0
  for i, o in ipairs(options) do
    local tw = Kit.textWidth("button", o[2]) + 28 * s + (Theme.BOLD_OFFSET or 1)
    if (o.errors or 0) > 0 then tw = tw + math.floor(h * 0.42) + math.floor(7 * s) end
    widths[i] = math.max(Kit.tapMin(), math.ceil(tw))
    total = total + widths[i]
  end
  return total <= w, widths
end

function Form.tabs(S, Kit, key, options, x, y, w, h, pick)
  local fits, widths = Form.tabsFit(Kit, options, w, h)
  if not fits then return false end
  local s = Kit.scale
  local tx = x
  for i, o in ipairs(options) do
    local active = S[key] == o[1]
    local err = (o.errors or 0) > 0
    local opts = {
      face = "bare",
      font = "button",
      bold = active,
      ink = err and PAL.red or (active and PAL.heading or PAL.muted),
      icon = err and "triangle-alert" or nil,
      id = "tab-" .. key .. "-" .. tostring(o[1]),
    }
    if Kit.button(tx, y, widths[i], h, o[2], opts) and not active then
      pick(o[1], i)
    end
    if active then
      Theme.fillRounded(tx + 4 * s, y + h - 3 * s, widths[i] - 8 * s, 3 * s, err and PAL.red or PAL.heading, 1, 1.5 * s)
    end
    tx = tx + widths[i]
  end
  return true
end

return Form
