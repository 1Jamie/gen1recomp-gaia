-- rse-seams e10 spec 5.5/5.6: loadhelp/unloadhelp drive a dedicated help
-- MESSAGE window (not the L/R Help browser).
--   pret src/scrcmd.c:1274-1280         (loadhelp: ScriptReadWord, fallback ctx->data[0])
--   pret src/scrcmd.c:1285-1289         (unloadhelp)
--   pret src/new_menu_helpers.c:701-705 (DrawHelpMessageWindowWithText)
--   pret src/new_menu_helpers.c:707-710 (DestroyHelpMessageWindow_ — safe when closed)
--   lua: luajit tests/engine/game3_help_window_opcode_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Ops = require("src.core.game3.scripting.ops_a")
local Opcodes = require("src.core.game3.scripting.opcodes")
local TextIR = require("src.core.game3.scripting.text_ir")
local HelpWindow = require("src.ui.game3.help_window")

local store = Flags.newStore()
local function vm(texts)
  local c = Ctx.new({})
  c.mode, c.status = "bytecode", "running"
  return {
    ctx = c,
    store = store,
    adapters = { log = function() end },
    setPc = function() end,
    texts = texts or {},
    -- getText hands the dispatcher an IR table like the real Vm does
    -- (Vm:getText returns the bundle's parsed text, ops_a then runs toPlain).
    getText = function(self, key)
      local s = self.texts[key]
      return s and TextIR.fromAscii(s)
    end,
  }
end

-- 1. loadhelp opens the window with the resolved string.
HelpWindow.close()
local v = vm({ [Opcodes.key(0xABC)] = "Some HELP text." })
eq(Ops.dispatch(v, { op = "loadhelp", [1] = 0xABC }), false, "loadhelp does not yield")
eq(HelpWindow.isOpen(), true, "the help message window is open")
eq(HelpWindow.getText(), "Some HELP text.", "the resolved text reached the window")

-- 2. unloadhelp closes it; closing again with nothing open is a no-op
--    (pret DestroyHelpMessageWindow_ is safe either way).
eq(Ops.dispatch(v, { op = "unloadhelp" }), false, "unloadhelp does not yield")
eq(HelpWindow.isOpen(), false, "the window closed")
eq(Ops.dispatch(v, { op = "unloadhelp" }), false, "unloadhelp with no window is a no-op")
eq(HelpWindow.isOpen(), false, "still closed")

-- 3. resolve_text fallback: pointer 0/nil falls back to ctx.data[0] and an
--    unresolved pointer opens the window without raising.
v.ctx.data = v.ctx.data or {}
v.ctx.data[0] = "T_FALLBACK"
local v2 = vm()
v2.ctx.data = { [0] = "T_FALLBACK" }
v2.texts = { T_FALLBACK = "Fallback text." }
local ok = pcall(Ops.dispatch, v2, { op = "loadhelp", [1] = 0 })
check(ok, "pointer 0 falls back through resolve_text without raising")
HelpWindow.close()

T.finish("game3_help_window_opcode_test")
