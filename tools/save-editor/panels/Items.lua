local Ops = require("Ops")
local Gen = require("Gen")
local Bag = require("src.inventory.Bag")
local PAL = require("Theme").PAL
local M = {}
local Motion = require("Motion")
local Chooser = require("Chooser")
local function drawView(S, Kit, x, y, w, h)
  local s, pad, gap, row = Kit.scale, 12 * Kit.scale, 8 * Kit.scale, Kit.controlH()
  Kit.card(x, y, w, h)
  Ops.pcItems(S)
  local cx, cy, inner = x + pad, y + pad, w - 2 * pad
  S.itemView = S.itemView or "bag"
  local compact = h < 430 * s
  local views = { { "bag", "Bag" }, { "pc", "PC" }, { "wallet", "Wallet" }, { "badges", "Badges" } }
  if compact then
    local addW = math.max(row, Kit.textWidth("small", "Add") + 20 * s)
    local toolsW = math.max(row, Kit.textWidth("small", "Tools") + 20 * s)
    local viewW = inner - addW - toolsW - 2 * gap
    Chooser.navigation(S, Kit, "itemView", "Inventory view", views, cx, cy, viewW, row, function()
      S.itemMenu = nil
    end)
    local storage = S.itemView == "bag" or S.itemView == "pc"
    if
      Kit.button(cx + viewW + gap, cy, addW, row, "Add", { font = "small", enabled = storage })
    then
      Ops.openItemPicker(S, Kit, S.itemView)
    end
    if
      Kit.button(
        cx + inner - toolsW,
        cy,
        toolsW,
        row,
        "Tools",
        { font = "small", enabled = storage }
      )
    then
      if S.itemMenu == "tools" then
        S.itemMenu = nil
      else
        S.itemMenu = "tools"
      end
      Kit.blur()
    end
    cy = cy + row + gap
  else
    Chooser.navigation(
      S,
      Kit,
      "itemView",
      "Inventory view",
      views,
      cx,
      cy,
      math.min(inner, 360 * s),
      row,
      function()
        S.itemMenu = nil
      end
    )
    cy = cy + row + gap
  end
  if S.itemView == "wallet" then
    local ch = 2 * (row + gap + Kit.textHeight("small") + gap) + (row + gap) * 2
    S.walletScroll =
      Kit.scrollPixels(cx, cy, inner, math.max(0, y + h - pad - cy), S.walletScroll or 0, ch)
    Kit.pushClip(cx, cy, inner, math.max(0, y + h - pad - cy))
    cy = cy - S.walletScroll
    for _, f in ipairs({
      { "money", "Money", Gen.money(S.save), Ops.maxMoney },
      { "coins", "Coins", Gen.coins(S.save), Ops.maxCoins },
    }) do
      Kit.text("small", f[2], cx, cy, PAL.text)
      cy = cy + Kit.textHeight("small") + gap
      S.walletDrafts = S.walletDrafts or {}
      local function apply(v)
        if Ops.setTrainerProperty(S, f[1], v) then
          S.walletDrafts[f[1]] = nil
        end
      end
      local bw = math.max(row, 64 * s)
      S.walletDrafts[f[1]] = Kit.textfield(
        "wallet-" .. f[1],
        cx,
        cy,
        inner - bw - gap,
        row,
        S.walletDrafts[f[1]] or tostring(f[3]),
        "value",
        { onSubmit = apply }
      )
      if Kit.button(cx + inner - bw, cy, bw, row, "Set", { kind = "accent", font = "small" }) then
        apply(S.walletDrafts[f[1]])
        Kit.blur()
      end
      cy = cy + row + gap
      if Kit.button(cx, cy, inner, row, "Max " .. f[2], { kind = "good", font = "small" }) then
        f[4](S)
      end
      cy = cy + row + gap
    end
    Kit.popClip()
    return
  elseif S.itemView == "badges" then
    local ids = Ops.badgeIds(S)
    local bc = inner >= 480 * s and 4 or 2
    local bw = (inner - (bc - 1) * gap) / bc
    local bodyH = math.max(0, y + h - pad - cy)
    S.badgeScroll =
      Kit.scrollPixels(cx, cy, inner, bodyH, S.badgeScroll or 0, math.ceil(#ids / bc) * (row + gap))
    Kit.pushClip(cx, cy, inner, bodyH)
    for i, id in ipairs(ids) do
      if
        Kit.chip(
          cx + (i - 1) % bc * (bw + gap),
          cy + math.floor((i - 1) / bc) * (row + gap) - S.badgeScroll,
          bw,
          row,
          id:gsub("BADGE$", ""),
          Gen.hasBadge(S.save, id)
        )
      then
        Ops.toggleBadge(S, id)
      end
    end
    Kit.popClip()
    return
  end
  local pc = S.itemView == "pc"
  local prefix = pc and "pc" or "bag"
  local function call(verb, id, value)
    return Ops[prefix .. verb](S, id, value)
  end
  if not compact then
    local half = (inner - gap) / 2
    if Kit.button(cx, cy, half, row, "Add item", { kind = "good", font = "small" }) then
      Ops.openItemPicker(S, Kit, pc and "pc" or "bag")
    end
    if
      Kit.button(cx + half + gap, cy, half, row, "Max all", { kind = "accent", font = "small" })
    then
      call("MaxAll")
    end
    cy = cy + row + gap
    if Kit.button(cx, cy, half, row, "Sort A-Z", { font = "small" }) then
      call("Sort", "name")
    end
    if Kit.button(cx + half + gap, cy, half, row, "Sort #", { font = "small" }) then
      call("Sort", "index")
    end
    cy = cy + row + gap
  elseif S.itemMenu == "tools" then
    local tools = {
      {
        "Max all",
        function()
          call("MaxAll")
        end,
      },
      {
        "Sort A-Z",
        function()
          call("Sort", "name")
        end,
      },
      {
        "Sort #",
        function()
          call("Sort", "index")
        end,
      },
    }
    local bw = (inner - 2 * gap) / 3
    for i, a in ipairs(tools) do
      if Kit.button(cx + (i - 1) * (bw + gap), cy, bw, row, a[1], { font = "small" }) then
        a[2]()
        S.itemMenu = nil
      end
    end
    return
  end
  local order = pc and Ops.pcOrder(S) or Bag.order(S.save, S.data)
  local quantities = pc and S.save.pcItems or S.save.inventory
  local pagerY = y + h - pad - row
  local bodyH = math.max(0, pagerY - gap - cy)
  -- Reserve the complete confirmation label before arming Drop, so its
  -- button never shrinks or changes the surrounding layout on a second tap.
  local actionMin = Kit.buttonWidth("Confirm?", { font = "small", iconStack = true }, row)
  local actionCols = inner >= 5 * actionMin + 4 * gap and 5 or 3
  local actionRows = math.ceil(5 / actionCols)
  local itemH = actionRows * row + (actionRows - 1) * gap + Kit.textHeight("small") + 3 * gap
  local visible = math.max(1, math.floor(bodyH / itemH))
  local offsetKey = prefix .. "Offset"
  S[offsetKey] = Kit.scroll(cx, cy, inner, bodyH, S[offsetKey] or 0, #order, visible)
  Kit.pushClip(cx, cy, inner, bodyH)
  for i = 1, visible do
    local id = order[S[offsetKey] + i]
    if id == nil then
      break
    end
    local by = cy + (i - 1) * itemH
    local def = S.data.items[id]
    Kit.text(
      "small",
      Kit.ellipsize(
        "small",
        tostring(def and def.name or id) .. " x" .. tostring(quantities[id] or 0),
        inner
      ),
      cx,
      by,
      PAL.text
    )
    by = by + Kit.textHeight("small") + gap
    local labels = {
      "Decrease",
      "Increase",
      "Max",
      pc and "Bag" or "PC",
      Ops.armLabel(S, prefix .. "-drop-" .. tostring(id), "Drop"),
    }
    for j, label in ipairs(labels) do
      local actionRow = math.floor((j - 1) / actionCols)
      local first = actionRow * actionCols + 1
      local cols = math.min(actionCols, #labels - first + 1)
      local bw = (inner - (cols - 1) * gap) / cols
      if
        Kit.button(cx + (j - first) * (bw + gap), by + actionRow * (row + gap), bw, row, label, {
          font = "small",
          icon = ({ "minus", "plus", "chevrons-up", pc and "backpack" or "package", "trash" })[j],
          iconOnly = j == 1 or j == 2,
          iconStack = j >= 3,
          kind = j == 5 and "danger" or "ghost",
          enabled = j ~= 4 or Ops.moveCount(S, not pc, id) > 0,
        })
      then
        if j == 1 then
          call("Adjust", id, -1)
        elseif j == 2 then
          call("Adjust", id, 1)
        elseif j == 3 then
          call("Max", id)
        elseif j == 4 then
          call(pc and "ToBag" or "ToPc", id)
        elseif
          Ops.arm(
            S,
            prefix .. "-drop-" .. tostring(id),
            "Drop this entire stack? Tap again to confirm"
          )
        then
          call("Drop", id)
        end
      end
    end
  end
  Kit.popClip()
  S[offsetKey] = Kit.pager(cx, pagerY, inner, S[offsetKey], #order, visible)
end
function M.draw(S, Kit, x, y, w, h)
  Motion.pages(S, Kit, "itemView", x, y, w, h, drawView)
end
return M
