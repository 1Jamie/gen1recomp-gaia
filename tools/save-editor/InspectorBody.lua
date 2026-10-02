local Ops = require("Ops")
local Gen = require("Gen")
local P = require("Properties")
local MonOps = require("MonOps")
local PAL = require("Theme").PAL
local Body = {}
local Motion = require("Motion")
local Chooser = require("Chooser")

local function drawSection(S, Kit, x, y, w, h)
  local mon = S.editingMon
  if not mon then
    Kit.textWrapped(
      "button",
      "Select a Pokemon to edit its properties, stats, moves and origin.",
      x + 16,
      y + 24,
      w - 32,
      PAL.muted
    )
    return
  end
  local s, pad, gap = Kit.scale, 14 * Kit.scale, 10 * Kit.scale
  local row = Kit.controlH()
  local cx, inner = x + pad, w - 2 * pad
  local g = Gen.ofState(S)
  local sections = {
    { "main", "Main" },
    { "stats", "Stats" },
    { "moves", "Moves" },
    { "origin", "Origin" },
    { "extras", "Extras" },
    { "checks", "Checks" },
  }
  S.monSection = S.monSection or "main"
  local navY = y + pad
  local navX = cx
  if S.inspectorBack then
    if Kit.iconButton(cx, navY, row, row, "chevron-left", "Back to party") then
      Motion.change(S, "mobileInspector", false, -1)
    end
    navX = cx + row + gap
  end
  Chooser.navigation(
    S,
    Kit,
    "monSection",
    "Pokemon section",
    sections,
    navX,
    navY,
    math.min(cx + inner - navX, 360 * s),
    row
  )
  local bodyY = navY + row + gap
  local bodyH = math.max(0, y + h - pad - bodyY)
  if S.formMon ~= mon then
    S.formMon, S.monDrafts, S.inspectorScroll = mon, {}, 0
    S._formHeight = 0
    S.propertyChoice = nil
    if Kit.focus and Kit.focus:match("^property%-") then
      Kit.blur()
    end
  end
  S.monDrafts = S.monDrafts or {}
  S.inspectorScroll =
    Kit.scrollPixels(cx, bodyY, inner, bodyH, S.inspectorScroll or 0, S._formHeight or 0)
  Kit.pushClip(cx, bodyY, inner, bodyH)
  local cy = bodyY - S.inspectorScroll
  local start = cy
  local function text(str, color)
    cy = cy + Kit.textWrapped("small", str, cx, cy, inner, color or PAL.caption) + gap
  end
  local function button(label, fn, kind)
    local opts = { kind = kind, font = "small" }
    local buttonH = Kit.buttonHeight(label, inner, opts)
    if Kit.button(cx, cy, inner, buttonH, label, opts) then
      fn()
    end
    cy = cy + buttonH + gap
  end
  local function field(id, label, value, fn, sanitize)
    text(label, PAL.text)
    local key = "property-" .. id
    local draft = S.monDrafts[id]
    if Kit.focus ~= key and draft == nil then
      draft = tostring(value or "")
    end
    local function apply(v)
      if type(value) == "number" then
        local n = tonumber(v)
        if not n or n ~= math.floor(n) then
          return Ops.say(S, "Enter a whole number")
        end
      end
      if fn(v) then
        S.monDrafts[id] = nil
      end
    end
    local applyW = math.max(row, Kit.textWidth("small", "Set") + 24 * s)
    S.monDrafts[id] = Kit.textfield(
      key,
      cx,
      cy,
      inner - applyW - gap,
      row,
      draft or tostring(value or ""),
      "value",
      { sanitize = sanitize, onSubmit = apply }
    )
    if
      Kit.button(cx + inner - applyW, cy, applyW, row, "Set", { kind = "accent", font = "small" })
    then
      apply(S.monDrafts[id])
      Kit.blur()
    end
    cy = cy + row + 2 * gap
  end
  local function choice(id, label, value, options, apply)
    local shown = "Unknown (" .. tostring(value) .. ")"
    for _, v in ipairs(options) do
      if v[1] == value then
        shown = v[2]
      end
    end
    text(label, PAL.text)
    if
      Kit.button(cx, cy, inner, row, shown, {
        face = "invert",
        font = "small",
        trailingIcon = S.propertyChoice == id and "chevron-up" or "chevron-down",
      })
    then
      if S.propertyChoice == id then
        S.propertyChoice = nil
      else
        S.propertyChoice = id
        S._choiceScroll = S.inspectorScroll
      end
      Kit.blur()
    end
    cy = cy + row + gap
    if S.propertyChoice == id then
      local cw = (inner - gap) / 2
      for i, v in ipairs(options) do
        if
          Kit.chip(
            cx + (i - 1) % 2 * (cw + gap),
            cy + math.floor((i - 1) / 2) * (row + gap),
            cw,
            row,
            v[2],
            v[1] == value,
            PAL.blue
          )
        then
          apply(v[1])
          S.propertyChoice = nil
          S.inspectorScroll = math.min(S._choiceScroll or 0, S.inspectorScroll or 0)
        end
      end
      cy = cy + math.ceil(#options / 2) * (row + gap)
    end
    cy = cy + gap
  end
  local function props(list)
    for _, d in ipairs(list) do
      if d.toggle then
        local on = P.get(mon, d)
        on = on == true or on == 1
        if Kit.chip(cx, cy, inner, row, d.label .. ": " .. (on and "ON" or "OFF"), on) then
          Ops.setMonProperty(S, mon, d.key, not on)
        end
        cy = cy + row + gap
      elseif d.choices then
        choice(d.key, d.label, P.get(mon, d), d.choices, function(v)
          return Ops.setMonProperty(S, mon, d.key, v)
        end)
      else
        field(d.key, d.label, P.get(mon, d), function(v)
          return Ops.setMonProperty(S, mon, d.key, v)
        end)
      end
    end
  end
  local def = (S.data and S.data.pokemon and S.data.pokemon[mon.species or mon.speciesId]) or {}
  if S.monSection == "main" then
    text(def.name or tostring(mon.species or mon.speciesId), PAL.heading)
    button("Change species", function()
      Ops.openSpeciesPicker(S, Kit)
    end, "accent")
    if S.nicknameMon ~= mon then
      S.nicknameMon, S.nicknameDraft = mon, mon.nickname or ""
    end
    text("Nickname (up to 10 game characters)", PAL.text)
    local setW = math.max(row, 64 * s)
    S.nicknameDraft = Kit.textfield(
      "mon-nickname",
      cx,
      cy,
      inner - setW - gap,
      row,
      S.nicknameDraft or "",
      "no nickname",
      {
        sanitize = function(v)
          return Ops.nicknameSanitize(S, v)
        end,
      }
    )
    if Kit.button(cx + inner - setW, cy, setW, row, "Set", { kind = "accent", font = "small" }) then
      Ops.setNickname(S, mon, S.nicknameDraft)
      Kit.blur()
    end
    cy = cy + row + gap
    button("Clear nickname", function()
      Ops.clearNickname(S, mon)
      S.nicknameDraft = ""
    end, "danger")
    field("level", "Level (1-100)", mon.level, function(v)
      local n = tonumber(v)
      if not require("Legality").integer(n, 1, 100) then
        return Ops.say(S, "Level must be a whole number from 1 to 100")
      end
      return Ops.setLevel(S, mon, n)
    end)
    field("experience", "Experience", Gen.exp(mon), function(v)
      return Ops.setExperience(S, mon, v)
    end)
    field(
      "current-hp",
      "Current HP (max " .. tostring(mon.maxHp or (mon.stats and mon.stats.hp) or 0) .. ")",
      mon.hp or 0,
      function(v)
        return Ops.setCurrentHp(S, mon, v)
      end
    )
    button("Status: " .. tostring(mon.status or "healthy"), function()
      local choices = g == 1 and { "", "SLP", "PSN", "BRN", "FRZ", "PAR" }
        or { "", "SLP", "PSN", "BRN", "FRZ", "PAR", "TOX" }
      local at = 1
      for i, v in ipairs(choices) do
        if v == (mon.status or "") then
          at = i
        end
      end
      local want = choices[at % #choices + 1]
      Ops.setMonStatus(S, mon, want ~= "" and want or nil)
    end)
    if g >= 2 then
      button("Held item: " .. tostring(mon.heldItem or mon.item or "none"), function()
        Ops.openItemPicker(S, Kit, "held")
      end, "accent")
      button("Clear held item", function()
        Ops.setHeldItem(S, mon, nil)
      end, "danger")
      field("friendship", "Friendship (0-255)", mon.friendship or mon.happiness or 0, function(v)
        local n = tonumber(v)
        if not require("Legality").integer(n, 0, 255) then
          return Ops.say(S, "Friendship must be 0-255")
        end
        return Ops.setHappiness(S, mon, n)
      end)
    end
    if g == 3 then
      local Pokemon = require("src.core.game3.pokemon")
      local Summary = require("src.core.game3.summary_data")
      local nature = (mon.personality or 0) % 25
      local natures = {}
      for id = 0, 24 do
        local ok, name = pcall(function()
          return Summary.NATURES[id]
        end)
        natures[#natures + 1] = { id, ok and name or tostring(id) }
      end
      choice("nature", "Nature", nature, natures, function(v)
        return Ops.setNature(S, mon, v)
      end)
      local slot = mon.abilityNum or (mon.personality or 0) % 2
      button(
        "Ability: "
          .. tostring(
            Pokemon.abilityName(mon.ability or Pokemon.abilityId(mon.species, mon.personality))
          )
          .. " / slot "
          .. (slot + 1),
        function()
          Ops.setAbility(S, mon, 1 - slot)
        end,
        "accent"
      )
      local gender = Pokemon.gender(mon.species, mon.personality)
      button("Gender: " .. gender, function()
        Ops.setMonGender(S, mon, gender == "M" and "F" or "M")
      end)
      button("Shiny: " .. (Pokemon.isShiny(mon) and "ON" or "OFF"), function()
        Ops.setShiny(S, mon, not Pokemon.isShiny(mon))
      end, "warn")
      text(
        "Nature, ability, gender and shiny changes regenerate PID. Use Checks to review the result."
      )
    elseif g == 2 then
      field("pokerus", "Pokerus (packed strain / days)", mon.pokerus or 0, function(v)
        local n = tonumber(v)
        if not require("Legality").integer(n, 0, 255) then
          return Ops.say(S, "Pokerus must be 0-255")
        end
        return Ops.setPokerus(S, mon, n)
      end)
      text("Gender, shininess and Unown form follow DVs.")
    end
    button("Full heal", function()
      Ops.healMon(S, mon)
    end, "good")
    button("Clone to a box", function()
      Ops.cloneMonToBox(S, mon)
    end, "accent")
  elseif S.monSection == "stats" then
    local keys = g == 3 and { "hp", "atk", "def", "spa", "spd", "spe" }
      or { "hp", "attack", "defense", "speed", "special" }
    local stats = mon.stats or {}
    text(
      ("Calculated: HP %s / Atk %s / Def %s / Spe %s"):format(
        tostring(stats.hp or mon.maxHp or "?"),
        tostring(stats.attack or mon.attack or "?"),
        tostring(stats.defense or mon.defense or "?"),
        tostring(stats.speed or mon.speed or "?")
      ),
      PAL.heading
    )
    text(
      g == 1 and ("Special: " .. tostring(stats.special or "?"))
        or (
          "Sp. Atk: "
          .. tostring(stats.specialAttack or stats.spAtk or mon.spAtk or "?")
          .. " / Sp. Def: "
          .. tostring(stats.specialDefense or stats.spDef or mon.spDef or "?")
        ),
      PAL.heading
    )
    text(
      g == 3 and "IVs 0-31. EVs 0-255 with a total limit of 510."
        or "DVs 0-15. HP DV follows the other DVs. Stat experience 0-65535."
    )
    if g == 3 then
      button("Max all (31)", function()
        Ops.maxIvs(S, mon)
      end, "good")
      button("Clear EVs", function()
        Ops.clearEvs(S, mon)
      end, "danger")
      local total = 0
      for _, k in ipairs(keys) do
        total = total + (mon.evs and mon.evs[k] or 0)
      end
      text("Total EVs: " .. total .. " / 510", total > 510 and PAL.red or PAL.green)
    end
    for _, k in ipairs(keys) do
      if g == 3 then
        field("iv-" .. k, k:upper() .. " IV", mon.ivs and mon.ivs[k] or 0, function(v)
          return Ops.setIv(S, mon, k, tonumber(v) or 0)
        end)
        field("ev-" .. k, k:upper() .. " EV", mon.evs and mon.evs[k] or 0, function(v)
          return Ops.setEv(S, mon, k, tonumber(v) or 0)
        end)
      else
        if k ~= "hp" then
          field("dv-" .. k, k:upper() .. " DV", mon.dvs and mon.dvs[k] or 0, function(v)
            return Ops.setDv(S, mon, k, tonumber(v) or 0)
          end)
        end
        field(
          "se-" .. k,
          k:upper() .. " stat experience",
          mon.statExp and mon.statExp[k] or 0,
          function(v)
            return Ops.setStatExp(S, mon, k, v)
          end
        )
      end
    end
  elseif S.monSection == "moves" then
    for slot = 1, 4 do
      local mv = mon.moves and mon.moves[slot]
      local id = type(mv) == "table" and (mv.moveId or mv.id) or mv
      local md = id and S.data.moves and S.data.moves[id]
      button("Slot " .. slot .. ": " .. tostring(md and md.name or id or "empty"), function()
        Ops.openMovePicker(S, Kit, slot)
      end, "accent")
      if id and id ~= 0 then
        local pp = type(mv) == "table" and mv.pp or mon.pp and mon.pp[slot] or 0
        local ups = MonOps.getPpUps(mon, slot)
        local max = MonOps.calcMaxPp(MonOps.getBasePp(S.data, mon, slot), ups, g)
        field("pp-" .. slot, "Current PP (max " .. max .. ")", pp, function(v)
          return Ops.setPp(S, mon, slot, tonumber(v) or 0)
        end)
        field("ppup-" .. slot, "PP Ups (0-3)", ups, function(v)
          return Ops.setPpUps(S, mon, slot, tonumber(v) or 0)
        end)
        button("Clear slot " .. slot, function()
          Ops.clearMove(S, mon, slot)
        end, "danger")
      end
    end
    button("Reset to learnset", function()
      Ops.resetMoves(S, mon)
    end)
    button("Max all PP", function()
      Ops.maxAllPpUps(S, mon)
    end, "good")
  elseif S.monSection == "origin" then
    props(P.identity(S))
    if g == 2 and Gen.hasCaughtData(S.save, S.version) then
      button("Caught by: " .. tostring(mon.caughtByGender or "none"), function()
        Ops.setCaughtByGender(S, mon, mon.caughtByGender == "boy" and "girl" or "boy")
      end)
    end
  elseif S.monSection == "extras" then
    if g == 3 then
      text("Contest conditions")
      props(P.contest)
      text("Ribbons: setting a ribbon does not establish award or event eligibility.")
      props(P.ribbons)
    else
      text("This generation has no contest conditions or ribbons.")
    end
  else
    local report = require("Legality").mon(S, mon)
    text(
      report.errors > 0 and (report.errors .. " property errors")
        or "Property checks passed; encounter legality is unchecked",
      report.errors > 0 and PAL.red or PAL.yellow
    )
    for _, check in ipairs(report.checks) do
      text(
        check.kind:upper() .. ": " .. check.message,
        check.kind == "error" and PAL.red or check.kind == "pass" and PAL.green or PAL.yellow
      )
    end
  end
  S._formHeight = cy - start
  Kit.popClip()
  Kit.scrollbar(cx, bodyY, inner, bodyH, S.inspectorScroll, S._formHeight, bodyH)
end
function Body.draw(S, Kit, x, y, w, h)
  Motion.pages(S, Kit, "monSection", x, y, w, h, drawSection)
end
return Body
