package.path = "./?.lua;./?/init.lua;" .. package.path

local function romTextPlain(key, ctx) return tostring(key or ""):gsub("{PLAYER}", ctx and ctx.playerName or "") end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j, ctx) return romTextPlain(n, ctx) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local T = require("tests.harness")
local check, eq = T.check, T.eq

local StartMenu = require("src.ui.game3.start_menu")
local Stack = require("src.ui.game3.stack")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local NativesMatchCall = require("src.core.game3.scripting.natives_match_call")
local Runtime = require("src.core.game3.runtime")

local session = {
  version = "emerald",
  playerName = "AUTUMN",
  party = {},
  bag = {},
  options = {},
}

Runtime._session = session
Runtime.getSession = function() return session end

print("[test] 1. Tutorial start menu opens with all 8 entries for Emerald")
local selected = nil
StartMenu.show({
  session = session,
  tutorial = true,
  onTutorialSelect = function(sel)
    selected = sel
  end,
})

check(StartMenu.isOpen(), "StartMenu is open")
eq(#StartMenu.ENTRIES, 8, "8 entries present in tutorial mode")
eq(StartMenu.ENTRIES[1].id, "pokedex", "entry 1 is pokedex")
eq(StartMenu.ENTRIES[2].id, "pokemon", "entry 2 is pokemon")
eq(StartMenu.ENTRIES[3].id, "bag", "entry 3 is bag")
eq(StartMenu.ENTRIES[4].id, "pokenav", "entry 4 is pokenav")
eq(StartMenu.ENTRIES[5].id, "trainer", "entry 5 is trainer")
eq(StartMenu.ENTRIES[6].id, "save", "entry 6 is save")
eq(StartMenu.ENTRIES[7].id, "option", "entry 7 is option")
eq(StartMenu.ENTRIES[8].id, "exit", "entry 8 is exit")

local tpl = StartMenu.contentTemplate()
eq(tpl.left, 22, "window left is 22")
eq(tpl.top, 1, "window top is 1")
eq(tpl.width, 7, "window width is 7")
eq(tpl.height, 18, "window height is 18 (8*2 + 2)")

print("[test] 2. Confirming POKéNAV returns index 3")
StartMenu.cursor = 4 -- 1-indexed for 4th item (pokenav)
StartMenu.confirm()
check(not StartMenu.isOpen(), "StartMenu closed after confirm")
eq(selected, 3, "selected index is 3 (0-indexed for POKéNAV)")

print("[test] 3. Canceling (B press) returns 127 (MULTI_B_PRESSED)")
selected = nil
StartMenu.show({
  session = session,
  tutorial = true,
  onTutorialSelect = function(sel)
    selected = sel
  end,
})
check(StartMenu.isOpen(), "StartMenu reopened")
StartMenu.cancel()
check(not StartMenu.isOpen(), "StartMenu closed after cancel")
eq(selected, 127, "canceled selection is 127 (MULTI_B_PRESSED)")

print("[test] 4. ScriptMenu_CreateStartMenuForPokenavTutorial runs via VM/Native")
local ctx = {
  getVar = function(self, id) return self[id] or 0 end,
  setVar = function(self, id, val) self[id] = val end,
}
local fn = NativesMatchCall.BY_NAME.ScriptMenu_CreateStartMenuForPokenavTutorial
check(type(fn) == "function", "native exists")

local yielded = fn(ctx, {})

check(StartMenu.isOpen(), "StartMenu opened via native")
StartMenu.cursor = 4 -- POKéNAV
StartMenu.confirm()
check(not StartMenu.isOpen(), "StartMenu closed")
local varResultId = require("src.core.game3.constants").active(session):var("VAR_RESULT")
eq(ctx[varResultId], 3, "VAR_RESULT set to 3 for POKéNAV")

T.finish()
