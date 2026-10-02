package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
_G.love = require("tests.love_stub")
local native = os.getenv("POKEPORT_TOUCH_NATIVE") == "1"
local version = os.getenv("POKEPORT_TOUCH_VERSION") or (native and "firered" or "red")
if native then
	require("src.core.GameVersion").set(version)
	require("src.import.gba.versions").select(version)
end
if native then
	require("tests.game3_cache").mountOrSkip("save_editor_touch_controls_test", "pokemon/meta.lua")
end
local App = require("tools.save-editor.App")
local Ops, Gen, Kit = require("Ops"), require("Gen"), require("Kit")
local Touch, Limits, Actions = require("TouchEditor"), require("ValueLimits"), require("MonActions")
local Copy = require("src.mods.Merge").deepCopy
local SD = require("src.core.SaveData")
local path = os.tmpname() .. "-touch.lua"
local f = assert(io.open(path, "wb"))
f:write(SD.encode(Gen.newGame(version)))
f:close()
App.load(path, { version = version, embedded = true })
local S = App.getState()
assert(S.save and not S.loadError, S.status)
Ops.partyAdd(S)
Ops.selectParty(S, 1)
local mon = S.editingMon
local count = 0
local function check(ok, msg)
	count = count + 1
	assert(ok, msg)
end
-- Fractional wheels and a short drag preserve their precise pixel distance.
Kit.layout(360, 640)
Kit.beginFrame(50, 50, false, -0.25)
local state = { offset = 0 }
local _, shift = Kit.list(state, "offset", 0, 0, 200, 150, 30, 60)
check(shift == 12 * Kit.scale, "partial wheel does not jump a whole row")
Kit.endFrame()
Kit._touchDrag = { x = 50, startY = 50 }
Kit.touchDown = true
Kit.beginFrame(50, 33, false, 0)
Kit.dragAdd(17)
Kit.list(state, "offset", 0, 0, 200, 150, 30, 60)
check(math.abs(state._listState.offset.pixels - (12 * Kit.scale + 17)) < 0.001, "17px drag moves list 17px")
Kit.endFrame()
Kit.touchDown = false
-- Real App touch events drive the modal, including SDL's synthesized hold.
local oldDimensions, oldSafe, oldDown = love.graphics.getDimensions, love.window.getSafeArea, love.mouse.isDown
love.graphics.getDimensions = function()
	return 360, 640
end
love.window.getSafeArea = function()
	return 0, 0, 360, 640
end
local held = false
love.mouse.isDown = function()
	return held
end
S.tab, S.mobileInspector, S.monSection = "party", true, "main"
local initialLevel = mon.level
local function levelPopup()
	Touch.open(S, Kit, {
		mode = "number",
		title = "Level",
		value = initialLevel,
		limits = function()
			return Limits.mon(S, mon, "level")
		end,
		apply = function(v)
			return Ops.setLevel(S, mon, v)
		end,
	})
	App.draw()
	App.draw()
end
levelPopup()
local rect = S.editPopup.sliderRect
held = true
App.touchpressed("slider", rect.x + rect.w * 0.7, rect.y + rect.h / 2)
App.draw()
App.touchmoved("slider", rect.x + rect.w * 0.9, rect.y + rect.h / 2)
App.draw()
check(S.editPopup.value > initialLevel and mon.level == initialLevel, "touch slider previews without mutating")
App.touchreleased("slider", rect.x + rect.w * 0.9, rect.y + rect.h / 2)
App.draw()
check(S.editPopup ~= nil, "synthetic mouse hold does not activate behind modal")
held = false
App.keypressed("escape")
App.draw()
levelPopup()
rect = S.editPopup.wheelRect
for _ = 1, 4 do
	Kit.beginFrame(rect.x + rect.w / 2, rect.y + rect.h / 2, false, 0.25)
	Touch.draw(S, Kit, 360, 640)
	Kit.endFrame()
end
check(S.editPopup.value == initialLevel + 1, "fractional wheel motion accumulates whole values")
App.touchpressed("wheel", rect.x + rect.w / 2, rect.y + rect.h / 2)
App.draw()
App.touchmoved("wheel", rect.x + rect.w / 2 - 50, rect.y + rect.h / 2)
App.draw()
check(S.editPopup.value > initialLevel and mon.level == initialLevel, "touch number wheel fine-tunes a draft")
App.touchreleased("wheel", rect.x + rect.w / 2 - 50, rect.y + rect.h / 2)
App.draw()
App.mousepressed(1, 1, 1)
App.draw()
check(not S.editPopup and mon.level == initialLevel, "outside tap cancels a dragged value")
levelPopup()
S.editPopup.typing, S.editPopup.draft = true, "999"
check(not Touch.commit(S, Kit) and S.editPopup.error ~= nil, "invalid exact entry stays open with a range error")
Kit.audit = {}
App.draw()
local maxButton
for _, control in ipairs(Kit.audit) do
	if control.label == "Max" then
		maxButton = control
	end
end
Kit.audit = nil
assert(maxButton, "numeric popup has a Max button")
local maxX, maxY = maxButton.x + maxButton.w / 2, maxButton.y + maxButton.h / 2
App.touchpressed("max", maxX, maxY)
App.touchreleased("max", maxX, maxY)
App.draw()
check(
	not S.editPopup.typing and not S.editPopup.error and S.editPopup.value == 100,
	"Max replaces an invalid typed draft and clears its error"
)
check(Touch.commit(S, Kit) and mon.level == 100, "Apply uses the tapped Max instead of stale text")
require("History").undo(S)
Ops.selectParty(S, 1)
mon = S.editingMon
Touch.close(S, Kit)
love.graphics.getDimensions, love.window.getSafeArea, love.mouse.isDown = oldDimensions, oldSafe, oldDown
-- Changing a slider is only a draft. Outside/escape cancel it; Apply commits once.
local oldLevel = mon.level
Touch.open(S, Kit, {
	mode = "number",
	title = "Level",
	value = oldLevel,
	limits = function()
		return Limits.mon(S, mon, "level")
	end,
	apply = function(v)
		return Ops.setLevel(S, mon, v)
	end,
})
Touch.keypressed(S, Kit, "up")
check(mon.level == oldLevel, "wheel draft does not change save")
Touch.keypressed(S, Kit, "escape")
check(mon.level == oldLevel and not S.editPopup, "escape cancels draft")
local before = #S.undoStack
Touch.open(S, Kit, {
	mode = "number",
	title = "Level",
	value = oldLevel + 5,
	limits = function()
		return Limits.mon(S, mon, "level")
	end,
	apply = function(v)
		return Ops.setLevel(S, mon, v)
	end,
})
check(Touch.commit(S, Kit) and mon.level == oldLevel + 5, "apply changes level by five")
check(#S.undoStack == math.min(require("History").LIMIT, before + 1), "value apply has one undo snapshot")
require("History").undo(S)
Ops.selectParty(S, 1)
mon = S.editingMon
check(mon.level == oldLevel, "undo restores coupled level/stats/experience")
-- Named results never depend on the old bare number labels.
Touch.open(S, Kit, {
	mode = "choice",
	title = "Status",
	options = { { "healthy", "Healthy" }, { "PSN", "Poisoned" } },
	apply = function(v)
		return Ops.setMonStatus(S, mon, v)
	end,
})
S.editPopup.query = "poison"
S.editPopup.index = 2
check(#Touch.results(S.editPopup) == 1, "named popup filters")
check(Touch.commit(S, Kit) and mon.status == "PSN", "search commits a named choice")
-- Corrupted properties repair together and metadata is retained.
mon.level, mon.hp, mon.status = 105, -50, "garbage"
mon.nickname = "ABCDEFGHIJKLMNO"
mon.customPreserved = { note = "keep me" }
if native then
	mon.ivs.hp = 99
	mon.evs = { hp = 255, atk = 255, def = 255 }
	mon.language = 6
	mon.metLevel = 120
else
	mon.dvs.attack = 99
	mon.dvs.hp = 0
	mon.statExp.hp = 999999
end
local Paint, PAL = require("src.ui.kit.Button"), require("Theme").PAL
local realPaint, marked = Paint.draw, {}
Paint.draw = function(owner, x, y, w, h, label, opts, hot, focused)
  if owner == Kit and opts.invalid and opts.id then
    marked[opts.id] = opts
    check(opts.ink == PAL.red and opts.stroke == PAL.red, "invalid control uses red ink and outline")
  end
  return realPaint(owner, x, y, w, h, label, opts, hot, focused)
end
local unchanged = SD.encode(S.save)
for _, section in ipairs({ "main", "stats", "origin" }) do
  S.monSection, S.inspectorScroll = section, 0
  App.draw()
end
check(marked["value-level"] ~= nil, "saved invalid level is visibly marked")
check(marked["choice-status"] ~= nil, "saved invalid choice is visibly marked")
check(marked[native and "value-iv-hp" or "value-dv-attack"] ~= nil, "saved invalid stat is visibly marked")
if native then
  check(marked["choice-language"] ~= nil, "unsupported saved language is visibly marked")
  check(marked["value-ev-spa"] ~= nil, "shared EV limit marks affected controls")
end
check(SD.encode(S.save) == unchanged, "highlighting never changes the saved values")
local highlights = require("Legality").highlights(require("Legality").mon(S, mon), mon)
check(highlights.sections.main > 0 and highlights.sections.stats > 0, "sections expose their error counts")
before = #S.undoStack
local ok = Ops.fixMonErrors(S, mon)
check(ok, S.status)
marked = {}
for _, section in ipairs({ "main", "stats", "origin" }) do
  S.monSection, S.inspectorScroll = section, 0
  App.draw()
end
check(next(marked) == nil, "red issue styling clears after repair while origin stays unchecked")
local coupled = Copy(mon)
require("MonOps").setLevel(S.data, coupled, 50, Gen.ofState(S))
coupled.metLevel = 0
local wrongExp = Limits.expAt(S, coupled, 50) - 1
coupled.exp, coupled.experience = wrongExp, wrongExp
local coupledIssues = require("Legality").highlights(require("Legality").mon(S, coupled), coupled)
check(coupledIssues.fields.experience ~= nil, "experience/level mismatch marks the experience field")
marked = {}
Kit.beginFrame(-1, -1, false, 0)
Touch.value(S, Kit, "experience", "Experience", wrongExp, function()
  return Limits.mon(S, coupled, "experience")
end, 0, 0, 280, function() end, coupledIssues.fields.experience)
Kit.endFrame()
check(marked["value-experience"] ~= nil, "in-range number with a coupled error still paints red")
Paint.draw = realPaint
check(require("Legality").mon(S, mon).errors == 0, "repair passes actual property validator")
check(mon.customPreserved.note == "keep me", "repair preserves unrelated metadata")
check(#S.undoStack == math.min(require("History").LIMIT, before + 1), "repair is one undo")
require("History").undo(S)
Ops.selectParty(S, 1)
mon = S.editingMon
check(mon.level == 105 and mon.hp == -50, "repair undo restores original bad values")
Ops.fixMonErrors(S, mon)
before = #S.undoStack
check(Ops.maxMon(S, mon), S.status)
check(mon.level == 100 and mon.hp == (mon.maxHp or mon.stats.hp), "max sets level and fills resulting HP")
check(require("Legality").mon(S, mon).errors == 0, "max passes actual property validator")
check(#S.undoStack == math.min(require("History").LIMIT, before + 1), "max is one undo")
if native then
	Ops.clearEvs(S, mon)
	Ops.setEv(S, mon, "hp", 255)
	Ops.setEv(S, mon, "atk", 255)
	check(Limits.mon(S, mon, "ev-def").hi == 0, "full EV budget visibly caps another stat")
	Ops.setEv(S, mon, "atk", 200)
	check(Limits.mon(S, mon, "ev-def").hi == 55, "lowering EVs exposes newly available max")
	local hp = Limits.mon(S, mon, "current-hp").hi
	Ops.setLevel(S, mon, 50)
	check(Limits.mon(S, mon, "current-hp").hi < hp, "HP cap follows level")
	Ops.setPpUps(S, mon, 1, 0)
	local pp = Limits.mon(S, mon, "pp-1").hi
	Ops.setPpUps(S, mon, 1, 3)
	check(Limits.mon(S, mon, "pp-1").hi > pp, "PP cap follows PP Ups")
	local locations = require("NamedChoices").locations(S)
	local found = false
	for _, entry in ipairs(locations) do
		if entry[2]:lower():find("route", 1, true) then
			found = true
		end
	end
	check(found, "native locations come from named ROM sections")
end
local candidates = Actions.encounters(S)
check(#candidates > 0, "wild encounter recipes exist for loaded game")
local beforeMon = Copy(mon)
local rng = native and require("src.core.game3.rng").getState()
before = #S.undoStack
check(Ops.randomizeMon(S, mon), S.status)
check(require("Legality").mon(S, mon).errors == 0, "randomized Pokémon passes properties")
check(require("Legality").mon(S, mon).status == "unchecked", "randomization does not falsely certify origin")
check(#S.undoStack == math.min(require("History").LIMIT, before + 1), "randomization is one undo")
if native then
	local now = require("src.core.game3.rng").getState()
	check(
		now.value == rng.value and now.value2 == rng.value2 and now.wild == rng.wild,
		"randomization does not advance gameplay RNG"
	)
end
require("History").undo(S)
Ops.selectParty(S, 1)
mon = S.editingMon
check(mon.species == beforeMon.species and mon.level == beforeMon.level, "randomize undo restores original")
-- Save-wide repair fixes party and box entries without skipping box slot gaps.
Ops.cloneMonToBox(S, mon)
S.save.party[1].level = -2
S.editingMon.hp = -5
before = #S.undoStack
check(Ops.fixAllErrors(S), S.status)
check(require("Legality").save(S).errors == 0, "fix all repairs party and boxes")
check(#S.undoStack == math.min(require("History").LIMIT, before + 1), "fix all is one undo")
if native or Gen.ofState(S) == 2 then
  for i = 1, 100 do
		check(Ops.randomizeMon(S, S.save.party[1]), S.status)
		check(require("Legality").mon(S, S.save.party[1]).errors == 0, "random recipe passes validator " .. i)
	end
end
check(App.save(), "bulk-edited save writes")
check(App.reload(), "bulk-edited save reloads")
S = App.getState()
check(require("Legality").save(S).errors == 0, "bulk edits survive save round trip")
os.remove(path)
print("save editor touch controls: " .. count .. " checks passed (" .. version .. ")")
