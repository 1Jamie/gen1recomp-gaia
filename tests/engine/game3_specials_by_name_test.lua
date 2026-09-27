package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("firered")

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Constants = require("src.core.game3.constants")

Natives.bind("firered")

local FR = Constants.of("firered").specials
local EM = Constants.of("emerald").specials

local SNAPSHOT = {
  natives = { 0x0, 0x36, 0x38, 0x39, 0x3A, 0x3C, 0x5F, 0x60, 0x7C, 0x7D, 0x9D, 0x9E, 0x9F, 0xB4, 0xD6, 0xD7, 0xE6, 0xF9, 0xFA, 0xFB, 0x106, 0x107, 0x110, 0x137, 0x138, 0x139, 0x13A, 0x143, 0x156, 0x15B, 0x164, 0x166, 0x169, 0x16F, 0x172, 0x17D, 0x17E, 0x17F, 0x181, 0x184, 0x187, 0x188, 0x18F, 0x190, 0x193, 0x197, 0x198, 0x199, 0x1B2, 0xF001, 0xF002, 0xF003 },
  natives_corner = { 0x15E },
  natives_cutscene = { 0x108, 0x113, 0x114, 0x18B, 0x18C, 0x191, 0x1A1, 0x1A5, 0x1B5, 0x1B7, 0x1BA },
  natives_daycare = { 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0x15F, 0x176, 0x177, 0x178, 0x179, 0x17A },
  natives_elevator = { 0xD8, 0x111, 0x132, 0x160, 0x1B8 },
  natives_events = { 0x8D, 0x8E, 0xAB, 0xCD, 0xCE, 0x129, 0x135, 0x136, 0x155, 0x157, 0x15C, 0x15D, 0x161, 0x167, 0x168, 0x170, 0x171, 0x19A, 0x1AB, 0x1AC, 0x1B9, 0x1BB },
  natives_fame = { 0x173, 0x174 },
  natives_fan_club = { 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA },
  natives_gift = { 0x180, 0x186, 0x189 },
  natives_link = { 0x1, 0x2, 0x3, 0x4, 0x5, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x2A, 0x3D, 0x5D, 0x127, 0x128, 0x14B, 0x16A, 0x16B, 0x16C, 0x16D, 0x16E, 0x182, 0x183, 0x1B3 },
  natives_listmenu = { 0x158, 0x159 },
  natives_moveteach = { 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE0, 0x18D, 0x1A3, 0x1A4 },
  natives_queries = { 0x7B, 0x83, 0x84, 0x85, 0x94, 0x96, 0xBA, 0xC5, 0xC6, 0xD4, 0x11E, 0x11F, 0x130, 0x147, 0x148, 0x14F, 0x150, 0x153, 0x162, 0x163, 0x165, 0x17C, 0x18A, 0x196, 0x19B, 0x1AA, 0x1AD, 0x1AE, 0x1B0, 0x1B1, 0x1B4, 0x1B6 },
  natives_seagallop = { 0x17B, 0x1A7, 0x1A8, 0x1A9 },
  natives_size_record = { 0x77, 0x78, 0x79, 0x7A, 0xD5 },
  natives_tower = { 0x27, 0x28, 0x29, 0xC4, 0xEC, 0xF6, 0xF8, 0x194 },
  natives_trade = { 0xFC, 0xFD, 0xFE, 0xFF },
  natives_wireless = { 0xEB, 0x11D, 0x142, 0x18E, 0x192, 0x195, 0x19C, 0x19D, 0x19E, 0x19F, 0x1A0, 0x1A2, 0x1A6 },
}

local function sourceOf(fn)
  return debug.getinfo(fn, "S").short_src:match("([%w_]+)%.lua$")
end

local function boundIds()
  local ids = {}
  for key, fn in pairs(Natives.ALLOW) do
    local id = tonumber(key:match("^special:(%d+)$"))
    if id then ids[id] = fn end
  end
  return ids
end

local expected, expectedCount = {}, 0
for file, ids in pairs(SNAPSHOT) do
  for _, id in ipairs(ids) do
    expected[id] = file
    expectedCount = expectedCount + 1
  end
end

local frBound = boundIds()
local frCount = 0
for id, fn in pairs(frBound) do
  frCount = frCount + 1
  eq(sourceOf(fn), expected[id], string.format("FireRed special 0x%X is served by its snapshot module", id))
end
eq(frCount, expectedCount, "FireRed binds exactly the snapshot id set")

local aliases = Std.SPECIAL_ALIASES
for name, id in pairs(Std.SPECIAL) do
  local pret = aliases[name] or name
  if id < Std.SPECIAL_ENGINE_BASE then
    eq(FR.byId[id], pret, "Std.SPECIAL." .. name .. " is pret special " .. pret)
  end
  local fn = Natives.BY_NAME[pret]
  if fn then
    check(Natives.ALLOW["special:" .. id] == fn,
      string.format("FireRed id 0x%X resolves through its name %s to the same handler", id, pret))
  end
end

for base, mod in pairs(Natives.MODULES) do
  check(type(mod.BY_NAME) == "table", base .. " exports handlers by pret name")
  for name, fn in pairs(mod.BY_NAME or {}) do
    check(FR.byName[name] ~= nil or EM.byName[name] ~= nil or Std.SPECIAL[name] ~= nil,
      base .. "." .. name .. " is a pret special name")
    for id, legacy in pairs(mod.HANDLERS or {}) do
      if FR.byId[id] == name then
        check(legacy == fn, string.format("%s legacy HANDLERS[0x%X] is the %s handler", base, id, name))
      end
    end
  end
end
for name in pairs(Natives.CORE) do
  check(FR.byName[name] ~= nil or Std.SPECIAL[name] ~= nil,
    "core handler " .. name .. " is a pret special name or an engine special")
end

GameVersion.set("emerald")
Natives.resetLog()
check(Natives.ensureBound() == true, "an Emerald session rebinds the natives")
eq(Natives.boundGame, "emerald", "bound to the Emerald special table")
local SHARED = { natives_daycare = true, natives_elevator = true }
for m in pairs(Natives.MODULES) do
  local Capabilities = require("src.core.game3.capabilities")
  check(SHARED[m] or (Capabilities.nativeFeature(m) ~= nil and not Capabilities.nativeAllowed({ version = "firered" }, m)),
    "Emerald loads only RSE-gated natives modules (" .. m .. ")")
end

local emBound = boundIds()
for id, fn in pairs(emBound) do
  local name = Std.specialName("emerald", id)
  check(name ~= nil, string.format("Emerald bound id 0x%X has a pret name", id))
  check(Natives.BY_NAME[name] == fn, string.format("Emerald 0x%X runs the %s handler", id, tostring(name)))
end
eq(emBound[EM.byName.HealPlayerParty], Natives.CORE.HealPlayerParty, "Emerald HealPlayerParty is the shared heal handler")
check(emBound[EM.byName.ShouldTryRematchBattle] ~= Natives.CORE.ShouldTryRematchBattle, "the VS Seeker rematch handler is not bound on Emerald")
eq(emBound[FR.byName.ShouldTryRematchBattle], nil, "the FireRed id of ShouldTryRematchBattle does not leak into Emerald")
eq(emBound[0xF001], Natives.CORE.FadeScreen, "engine specials stay bound on Emerald")

local logs = {}
local adapters = { log = function(m) logs[#logs + 1] = m end }
local wallClock = EM.byName.Unused_SetWeatherSunny
check(wallClock ~= nil, "Emerald has Unused_SetWeatherSunny")
local yield, value, known = Natives.special({ specialVars = {} }, wallClock, adapters)
eq(yield, false, "an unbound Emerald special does not yield")
eq(value, nil, "an unbound Emerald special returns no value")
eq(known, false, "an unbound Emerald special reports unknown")
eq(#logs, 1, "an unbound Emerald special logs once")
check(logs[1] and logs[1]:find("Unused_SetWeatherSunny", 1, true) ~= nil, "the log names the pret special")
Natives.special({ specialVars = {} }, wallClock, adapters)
eq(#logs, 1, "the second call does not log again")

GameVersion.set("firered")
check(Natives.ensureBound() == true, "switching back to FireRed rebinds")
local again = boundIds()
local same = true
for id, fn in pairs(frBound) do
  if again[id] ~= fn then same = false end
end
for id in pairs(again) do
  if frBound[id] == nil then same = false end
end
check(same, "FireRed binding is identical after an Emerald round trip")
eq(Natives.MODULES.natives_queries, Natives.Queries, "Natives.Queries tracks the bound module set")

GameVersion.set("leafgreen")
eq(Natives.ensureBound(), false, "LeafGreen shares the FireRed binding")

GameVersion.set(prevVersion)
Natives.bind(prevVersion)
T.finish("game3_specials_by_name_test")
