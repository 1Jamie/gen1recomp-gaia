package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local Copy = require("src.mods.Merge").deepCopy
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Save = require("src.core.gen2.Save")
local Codec = require("src.save_convert.Gen2Save")
local Syms = require("src.save_convert.Gen2Syms")
local Fixture = require("tests.fixtures.save.gen2_build")
local Data = require("tests.save_compat._codec").gen2Data
local World = require("src.world.gen2.World")
local Gen, Ops = require("Gen"), require("Ops")
local State, History = require("State"), require("History")
local Kit, Touch = require("Kit"), require("TouchEditor")
local Trainer, Items = require("Trainer"), require("Items")

Version.set("crystal")
local function state(save, version)
  local s = State.new()
  s.save, s.version, s.data = save, version or "crystal", Data
  s.save.pcItems = s.save.pcItems or {}
  Gen.ensureBoxes(s.save)
  return s
end
local function cartridge(balance)
  return Fixture.build({ version = "crystal", patch = function(t)
    t[Syms.crystal.wBuenasPassword] = 0x21
    t[Syms.crystal.wBlueCardBalance] = balance
    t[Syms.crystal.wCurDay] = 4
    t[Syms.crystal.wDailyFlags2] = 0x80
    t[Syms.crystal.wDailyRematchFlags] = 5
  end })
end
local function snapshot(s)
  return { bytes = Serializer.encode(s.save), dirty = s.dirty, revision = s.revision,
    token = s.historyToken, undo = #(s.undoStack or {}), redo = #(s.redoStack or {}) }
end
local function unchanged(s, before, message)
  T.same(snapshot(s), before, message)
end

for _, revision in ipairs({ "crystal", "crystal11" }) do
  local primary = 0x2000 + (0xa009 - 0xa000) + (0xdc4b - 0xd47b)
  local backup = (0xb209 - 0xa000) + (0xdc4b - 0xd47b)
  T.eq(primary, 0x27d9, revision .. " main balance offset")
  T.eq(backup, 0x19d9, revision .. " backup balance offset")
  T.eq(Syms.crystal.wBlueCardBalance, primary, revision .. " port balance offset agrees")
end
for _, value in ipairs({ 0, 7, 30 }) do
  local raw = cartridge(15)
  local save = assert(Codec.decode(raw, "crystal", Data))
  local s = state(save)
  local before = Copy(s.save)
  local unedited = assert(Codec.encode(s.save, "crystal", raw, Data))
  local changed = Ops.setTrainerProperty(s, "buenaPoints", value)
  T.eq(changed, true, "accepted editor balance " .. value)
  assert(changed, "Actual editor Ops rejected Buena balance " .. value)
  before.crystal.buenaPassword.balance = value
  T.same(s.save, before, "only canonical balance changes")
  T.eq(s.dirty, true, "balance edit marks dirty")
  T.eq(#s.undoStack, 1, "one balance edit has one history entry")
  T.eq(s.revision, 1, "one balance edit marks once")
  T.eq(s.status, "Buena points updated", "edit status uses visible currency name")
  local native = assert(Serializer.decode(Serializer.encode(s.save)))
  Save.normalize(native)
  Gen.hydrateSave(Data, native)
  local world = setmetatable({ game = { save = native }, scriptVars = {} }, World)
  T.eq(world:readVar(0x18), value, "runtime variable sees editor balance")
  T.eq(native.crystal.buenaPassword.balance or 0, value, "native reload preserves balance")
  T.eq(native.crystal.buenaPassword.word, 0x21, "native reload preserves password")
  T.eq(native.crystal.buenaPassword.day, 4, "native reload preserves password day")
  local out = assert(Codec.encode(native, "crystal", raw, Data))
  T.eq(out:byte(0x27d9 + 1), value, "main SRAM balance")
  T.eq(out:byte(0x19d9 + 1), value, "backup SRAM balance")
  T.eq(out:byte(Syms.crystal.wDailyFlags2 + 1), 0x80, "daily flags preserved")
  T.eq(out:byte(Syms.crystal.wDailyRematchFlags + 1), 5, "adjacent rematch flags preserved")
  T.eq(Codec.checksumValid(out, Codec.layoutFor("crystal")), true, "main checksum valid")
  T.eq(Codec.backupValid(out, Codec.layoutFor("crystal")), true, "backup checksum valid")
  local allowed = { [0x27d9] = true, [0x19d9] = true, [0x2d0d] = true,
    [0x2d0e] = true, [0x1f0d] = true, [0x1f0e] = true }
  local unrelated = 0
  for at = 0, #out - 1 do
    if not allowed[at] and out:byte(at + 1) ~= unedited:byte(at + 1) then unrelated = unrelated + 1 end
  end
  T.eq(unrelated, 0, "no unrelated exported byte changes")
  local back = assert(Codec.decode(out, "crystal", Data))
  T.eq(back.crystal.buenaPassword.balance or 0, value, "cartridge reimport preserves edited points")
  T.eq(back.crystal.buenaPassword.word, 0x21, "cartridge reimport preserves password")
  T.eq(back.crystal.buenaPassword.day, 4, "cartridge reimport preserves day")
  T.eq(History.undo(s), true, "balance edit can undo")
  T.eq(Gen.buenaPoints(s.save, s.version), 15, "undo restores original balance")
  T.eq(s.dirty, false, "undo to initial save is clean")
  T.eq(History.redo(s), true, "balance edit can redo")
  T.eq(Gen.buenaPoints(s.save, s.version), value, "redo restores edited balance")
  T.same(s.save, before, "redo preserves all surrounding state")
  local noChange = snapshot(s)
  T.eq(Ops.setTrainerProperty(s, "buenaPoints", value), true, "equal value is accepted")
  unchanged(s, noChange, "equal value adds no history or dirty change")
end

local preserved = state(assert(Codec.decode(cartridge(7), "crystal", Data)))
preserved.save.crystal.buenaPassword.prizesToday = 2
preserved.save.crystal.buenaPassword.streak = 3
preserved.save.crystal.buenaPassword.unknown = { note = "keep" }
preserved.save.inventory.BLUE_CARD = 1
local expected = Copy(preserved.save)
expected.crystal.buenaPassword.balance = 18
T.eq(Ops.setTrainerProperty(preserved, "buenaPoints", "18"), true, "numeric exact draft is accepted")
T.same(preserved.save, expected, "counters, metadata, card and currencies preserved")
History.undo(preserved)
expected.crystal.buenaPassword.balance = 7
T.same(preserved.save, expected, "undo preserves complete canonical state")
History.redo(preserved)
expected.crystal.buenaPassword.balance = 18
T.same(preserved.save, expected, "redo preserves complete canonical state")

for _, draft in ipairs({ { -1 }, { 31 }, { 7.5 }, { 0/0 }, { math.huge }, { -math.huge },
    { "" }, { "seven" }, { "3.5" }, { false }, {} }) do
  local before = snapshot(preserved)
  T.eq(Ops.setTrainerProperty(preserved, "buenaPoints", draft[1]), false, "invalid balance refused")
  unchanged(preserved, before, "invalid balance makes no save/history change")
  T.eq(preserved.status, "Buena points must be a whole number from 0 to 30", "invalid balance has range feedback")
end

for _, variant in ipairs({ "no-crystal", "no-buena", "no-balance" }) do
  local legacy = state({ version = "crystal", generation = 2, player = { name = "CHRIS" } })
  if variant ~= "no-crystal" then legacy.save.crystal = {} end
  if variant == "no-balance" then legacy.save.crystal.buenaPassword = { word = 2, day = 4 } end
  local before = snapshot(legacy)
  T.eq(Gen.buenaPoints(legacy.save, legacy.version), 0, "legacy getter defaults zero")
  unchanged(legacy, before, "legacy getter is pure")
  T.eq(Ops.setTrainerProperty(legacy, "buenaPoints", 0), true, "legacy zero accepted")
  unchanged(legacy, before, "legacy zero creates no table/history")
  T.eq(Ops.setTrainerProperty(legacy, "buenaPoints", 7), true, "meaningful legacy edit accepted")
  T.eq(legacy.save.crystal.buenaPassword.balance, 7, "meaningful edit creates canonical state")
  T.eq(#legacy.undoStack, 1, "legacy edit has one history entry")
  History.undo(legacy)
  T.eq(Serializer.encode(legacy.save), before.bytes, "legacy undo restores absent state")
  History.redo(legacy)
  T.eq(legacy.save.crystal.buenaPassword.balance, 7, "legacy redo restores balance")
end

local rows, buttons = {}, {}
local realValue, realButton = Touch.value, Kit.button
Touch.value = function(s, kit, id, title, value, limits, x, y, w, apply, issue)
  rows[id] = { title = title, value = value, limits = limits, x = x, y = y, w = w, apply = apply }
  return realValue(s, kit, id, title, value, limits, x, y, w, apply, issue)
end
Kit.button = function(x, y, w, h, label, opts)
  buttons[(opts and opts.id) or label] = { x = x, y = y, w = w, h = h, invalid = opts and opts.invalid }
  return realButton(x, y, w, h, label, opts)
end
local function panel(s, which, w, h, mx, my, clicked)
  rows, buttons = {}, {}
  Kit.layout(w, h)
  Kit.blockClicks = false
  Kit.beginFrame(mx or -1, my or -1, clicked or false, 0)
  if which == "wallet" then s.itemView = "wallet"; Items.draw(s, Kit, 0, 0, w, h)
  else Trainer.draw(s, Kit, 0, 0, w, h) end
  Kit.endFrame()
  return rows[(which == "wallet" and "wallet-" or "trainer-") .. "buenaPoints"]
end
for _, edition in ipairs(Version.ORDER) do
  local info = assert(Version.info(edition))
  local s = state({ version = edition, generation = info.generation, player = { name = "ASH" },
    crystal = { buenaPassword = { balance = 7 } } }, edition)
  local eligible = edition == "crystal"
  Version.set(eligible and "gold" or "crystal")
  T.eq(Gen.hasBuenaPoints(s.save, s.version), eligible, "save edition controls eligibility " .. edition)
  local before = snapshot(s)
  T.eq(Ops.setTrainerProperty(s, "buenaPoints", 15), eligible, "Ops edition gate " .. edition)
  if not eligible then unchanged(s, before, "ineligible stray Crystal table unchanged") end
  for _, which in ipairs({ "trainer", "wallet" }) do
    local prior = snapshot(s)
    local row = panel(s, which, 720, 1400)
    T.eq(row ~= nil, eligible, which .. " edition row gate " .. edition)
    unchanged(s, prior, "panel drawing leaves save/history unchanged")
    if row then
      T.eq(row.title, "Buena points", "currency title")
      T.eq(row.value, 15, "panel reads canonical balance")
      T.eq(row.limits.lo, 0, "row lower limit")
      T.eq(row.limits.hi, 30, "row cap")
      T.check(row.limits.help:find("Blue Card", 1, true), "row explains Blue Card points")
    end
  end
end
Version.set("crystal")
for _, crystal in ipairs({ false, { buenaPassword = false } }) do
  local invalid = state({ version = "crystal", generation = 2, player = {}, crystal = crystal })
  local before = snapshot(invalid)
  T.eq(Ops.setTrainerProperty(invalid, "buenaPoints", 7), false, "malformed Crystal structure refused")
  unchanged(invalid, before, "malformed Crystal structure preserved")
end
local legacyDraw = state({ version = "crystal", generation = 2, player = {} })
local legacyBefore = snapshot(legacyDraw)
for _, which in ipairs({ "trainer", "wallet" }) do
  local row = assert(panel(legacyDraw, which, 720, 1400))
  T.eq(row.value, 0, "legacy panel displays zero")
  unchanged(legacyDraw, legacyBefore, "legacy panel draw creates no Buena table")
end
local s = state(assert(Codec.decode(cartridge(7), "crystal", Data)))
for _, which in ipairs({ "trainer", "wallet" }) do
  for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 1000, 650 } }) do
    local before = snapshot(s)
    panel(s, which, size[1], size[2])
    if which == "trainer" then s.trainerScroll = 10000 else s.walletScroll = 10000 end
    local row = assert(panel(s, which, size[1], size[2]))
    local rect = assert(buttons["value-" .. which .. "-buenaPoints"])
    T.check(rect.y >= 0 and rect.y + rect.h <= size[2], "Buena row reachable after scrolling")
    T.check(rect.h >= Kit.tapMin(), "Buena field touch target")
    unchanged(s, before, "layout/scroll never edits currency")
    if which == "trainer" then s.trainerScroll = 0 else s.walletScroll = 0 end
  end
end
local row = assert(panel(s, "trainer", 720, 1400))
panel(s, "trainer", 720, 1400, row.x + 20, row.y + 20, true)
T.check(s.editPopup and s.editPopup.id == "trainer-buenaPoints", "actual Trainer field opens numeric popup")
local function popupClick(label)
  buttons = {}
  s.editPopup.scroll = 10000
  Kit.blockClicks = false
  Kit.beginFrame(-1, -1, false, 0)
  Touch.draw(s, Kit, 720, 1400)
  Kit.endFrame()
  Kit.beginFrame(-1, -1, false, 0)
  Touch.draw(s, Kit, 720, 1400)
  Kit.endFrame()
  local r = assert(buttons[label], "missing popup control " .. label)
  Kit.beginFrame(r.x + r.w / 2, r.y + r.h / 2, true, 0)
  Touch.draw(s, Kit, 720, 1400)
  Kit.endFrame()
end
local before = snapshot(s)
popupClick("Max")
T.eq(s.editPopup.value, 30, "actual Max control selects cap")
unchanged(s, before, "Max changes draft only")
popupClick("Min")
T.eq(s.editPopup.value, 0, "actual Min control selects zero")
unchanged(s, before, "Min changes draft only")
for _ = 1, 2 do
  s.editPopup.scroll = 0
  Kit.beginFrame(-1, -1, false, 0)
  Touch.draw(s, Kit, 720, 1400)
  Kit.endFrame()
end
local slider = s.editPopup.sliderRect
Kit.beginFrame(slider.x + slider.w - 12 * Kit.scale, slider.y + slider.h / 2, true, 0)
Touch.draw(s, Kit, 720, 1400)
Kit.endFrame()
T.eq(s.editPopup.value, 30, "actual slider selects capped endpoint")
unchanged(s, before, "slider changes draft only")
local p = s.editPopup
for _, value in ipairs({ "31", "-1", "2.5", "bad", "" }) do
  p.typing, p.draft, Kit.focus = true, value, "touch-exact"
  T.eq(Touch.commit(s, Kit), false, "typed invalid value refused by actual popup")
  T.eq(s.editPopup, p, "invalid popup stays open")
  T.eq(p.error, "Choose a whole number from 0 to 30", "popup shows range validation")
  unchanged(s, before, "invalid popup leaves save/history unchanged")
end
p.typing, p.draft, Kit.focus = true, "1", "touch-exact"
T.eq(Kit.textinput("5"), true, "exact input queues typed text")
T.eq(Touch.commit(s, Kit), true, "valid popup applies")
T.eq(Gen.buenaPoints(s.save), 15, "popup callback writes canonical balance")
T.eq(s.editPopup, nil, "successful apply closes popup")
T.eq(Kit.focus, nil, "successful apply clears keyboard focus")
T.eq(#s.undoStack, 1, "popup mutation has one history entry")
local walletRow = assert(panel(s, "wallet", 720, 1400))
T.eq(walletRow.value, 15, "Wallet reflects Trainer popup edit")
walletRow.apply(30)
T.eq(Gen.buenaPoints(s.save), 30, "Wallet callback uses canonical Ops route")
local cancelBefore = snapshot(s)
Touch.open(s, Kit, { mode = "number", title = walletRow.title, value = 0,
  limits = walletRow.limits, apply = walletRow.apply })
Touch.keypressed(s, Kit, "escape")
unchanged(s, cancelBefore, "popup cancel makes no mutation")
T.eq(Kit.focus, nil, "cancel clears focus")
s.save.crystal.buenaPassword.balance = 50
local invalidBefore = snapshot(s)
panel(s, "trainer", 720, 1400)
T.eq(rows["trainer-buenaPoints"].value, 50, "invalid loaded value remains visible")
T.eq(buttons["value-trainer-buenaPoints"].invalid, true, "invalid loaded value has warning")
unchanged(s, invalidBefore, "invalid-value draw never silently clamps balance")
Touch.value, Kit.button = realValue, realButton
T.finish("save_editor_buena_points_2640")
