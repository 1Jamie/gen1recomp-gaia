#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Message = { open = false, _stay = false, _done = nil, _waiting = false, shown = {} }
function Message.show(text, opts)
  opts = type(opts) == "table" and opts or {}
  Message.open = true
  Message._stay = opts.stay and true or false
  Message._done = opts.done
  Message._waiting = false
  Message.shown[#Message.shown + 1] = tostring(text)
  return Message
end
function Message.showStay(text, opts)
  opts = opts or {}
  opts.stay = true
  return Message.show(text, opts)
end
function Message.isOpen() return Message.open end
function Message.isWaiting() return Message.open and Message._waiting end
function Message.isTyping() return Message.open and not Message._waiting end
function Message.tick()
  if Message.open then Message._waiting = true end
end
function Message.skipReveal()
  if Message.open then Message._waiting = true end
end
function Message.close()
  local done = Message._done
  Message.open = false
  Message._stay = false
  Message._waiting = false
  Message._done = nil
  if done then done() end
end
package.loaded["src.ui.game3.message"] = Message

local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local LearnMove = require("src.core.game3.battle.learn_move")
local Choice = require("src.ui.game3.choice")

local function idx_of(shown, needle, from)
  for i = from or 1, #shown do
    if shown[i]:find(needle, 1, true) then return i end
  end
  return nil
end

local function in_order(shown, needles)
  local at = 0
  for _, n in ipairs(needles) do
    local i = idx_of(shown, n, at + 1)
    if not i then return false, n end
    at = i
  end
  return true
end

local function run(moves, answers)
  Ui.reset({ headless = false })
  LearnMove.reset()
  Choice.active = false
  Message.open = false
  Message._done = nil
  Message.shown = {}
  Battle._headless = false
  local hooks = Battle._choiceHooksForTests and Battle._choiceHooksForTests() or {
    pushMsg = function(text, cb) Ui.push(text, cb) end,
    askYesNo = function(a, b) Ui.askYesNo(a, b) end,
    askForget = function(labels, cb) Ui.askForget(labels, cb) end,
    headless = false,
  }
  local mon = { species = 4, level = 19, moves = moves, pp = { 35, 40, 35, 30 }, maxPp = { 35, 40, 35, 30 } }
  local result
  local prompts = {}
  local openedWhileTyping = false
  local ok, err = pcall(function()
    LearnMove.begin({
      mon = mon,
      moveId = 52,
      displayName = "CHARMANDER",
      pushMsg = hooks.pushMsg,
      askYesNo = hooks.askYesNo,
      askForget = hooks.askForget,
      headless = hooks.headless,
      onDone = function(learned) result = learned end,
    })
    for _ = 1, 200 do
      if result ~= nil then break end
      if Choice.active then
        if Message.open and not Message._waiting then openedWhileTyping = true end
        prompts[#prompts + 1] = Message.open and Message.shown[#Message.shown] or ""
        local ans = table.remove(answers, 1)
        if ans == "cancel" then Choice.cancel() else Choice.autoPick(ans) end
      elseif Message.open and Message._waiting and not Message._stay then
        Message.close()
      else
        Ui.pump()
        LearnMove.pump()
        Message.tick()
      end
    end
  end)
  return {
    ok = ok, err = err, result = result, mon = mon, shown = Message.shown,
    prompts = prompts, active = LearnMove.busy(), open = Message.open,
    openedWhileTyping = openedWhileTyping,
  }
end

print("[test] 1. free slot: learned message dismissed finishes")
local r = run({ 10, 45 }, {})
check(r.ok, "no error " .. tostring(r.err))
check(r.result == true, "onDone(true)")
check(r.mon.moves[3] == 52, "EMBER in slot 3")
check(not r.active, "LearnMove idle")

print("[test] 2. four moves: NO delete, YES stop -> did not learn")
r = run({ 10, 45, 33, 39 }, { false, true })
check(r.ok, "no error " .. tostring(r.err))
local ord, miss = in_order(r.shown, { "wants to learn", "already", "Should a move be deleted", "Stop trying", "did not learn" })
check(ord, "message order (missing " .. tostring(miss) .. ")")
check(r.result == false, "onDone(false)")
check(not r.active, "LearnMove idle")
check(r.prompts[1] and r.prompts[1]:find("Should a move be deleted", 1, true) ~= nil, "delete prompt text stays up under YES/NO")
check(r.prompts[2] and r.prompts[2]:find("Stop trying", 1, true) ~= nil, "stop prompt text stays up under YES/NO")
check(not r.openedWhileTyping, "YES/NO never opens while the prompt is still typing")
check(not r.open, "no message left open")
check(r.mon.moves[1] == 10 and r.mon.moves[4] == 39, "moves unchanged")

print("[test] 3. four moves: YES delete, forget slot 1 -> Poof chain")
r = run({ 10, 45, 33, 39 }, { true, 0 })
check(r.ok, "no error " .. tostring(r.err))
ord, miss = in_order(r.shown, { "wants to learn", "Should a move be deleted", "Poof", "forgot how to", "And...", "learned" })
check(ord, "message order (missing " .. tostring(miss) .. ")")
check(r.result == true, "onDone(true)")
check(r.mon.moves[1] == 52, "EMBER replaced slot 1")
check(not r.active, "LearnMove idle")

print("[test] 4. HM refusal then stop")
r = run({ 15, 45, 33, 39 }, { true, 0, false, true })
check(r.ok, "no error " .. tostring(r.err))
ord, miss = in_order(r.shown, { "Should a move be deleted", "HM moves can't", "Should a move be deleted", "Stop trying", "did not learn" })
check(ord, "message order (missing " .. tostring(miss) .. ")")
check(r.result == false, "onDone(false)")
check(r.mon.moves[1] == 15, "CUT kept")

print("[test] 5. forget list B-cancel returns to stop prompt")
r = run({ 10, 45, 33, 39 }, { true, "cancel", true })
check(r.ok, "no error " .. tostring(r.err))
check(r.result == false, "onDone(false)")
check(idx_of(r.shown, "did not learn") ~= nil, "did not learn shown")

print("[test] 6. Ui.askYesNo(cb) single-arg form still works")
Ui.reset({ headless = false })
Message.open = false
Message.shown = {}
local got
Ui.askYesNo(function(yes) got = yes end)
check(Choice.active and not Message.open, "choice open without a prompt message")
Choice.autoPick(true)
check(got == true, "cb(true)")

print("[test] 6b. Ui.askYesNo(prompt, cb) waits for the prompt to finish printing")
Ui.reset({ headless = false })
Message.open = false
Message.shown = {}
Choice.active = false
got = nil
Ui.askYesNo("Should a move be deleted?", function(yes) got = yes end)
check(Message.open and Message._stay and not Message._waiting, "prompt shown as a typing stay message")
check(not Choice.active, "YES/NO not open while typing")
check(Ui.pump() == false and not Choice.active, "pump while typing keeps YES/NO closed")
Message.tick()
check(Ui.pump() == false and Choice.active and Choice.kind == "yesno", "YES/NO opens once the text is waiting")
Choice.autoPick(false)
check(got == false and not Message.open, "cb(false) and prompt closed")

print("[test] 7. Ui.push cb fires on dismiss and in headless pump")
Ui.reset({ headless = false })
local fired = 0
Ui.push("hello", function() fired = fired + 1 end)
Ui.push("plain")
check(Ui.log()[1] == "hello" and Ui.log()[2] == "plain", "log stays strings")
Ui.pump()
check(fired == 0 and Message.open, "cb waits for dismiss")
Message.close()
check(fired == 1, "cb fired on dismiss")
Ui.reset({ headless = true })
Ui.push("x", function() fired = fired + 1 end)
Ui.pump()
check(fired == 2, "headless pump fires cb")
Ui.push("", function() fired = fired + 1 end)
check(fired == 3, "empty text fires cb immediately")

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3 learn move battle contract")
