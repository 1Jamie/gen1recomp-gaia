local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local M = {}

M.msgs = {}

local function mod(name) return require(name) end

function M.hookMessages()
  local Message = mod("src.ui.game3.message")
  if Message._miscHooked then return end
  Message._miscHooked = true
  local orig = Message.show
  Message.show = function(text, opts)
    local plain = text
    if type(text) == "table" then
      local ok, s = pcall(mod("src.core.game3.scripting.text_ir").toAscii, text, {})
      plain = ok and s or "?"
    end
    M.msgs[#M.msgs + 1] = tostring(plain)
    return orig(text, opts)
  end
end

function M.saw(pattern, from)
  for i = (from or 0) + 1, #M.msgs do
    if M.msgs[i]:find(pattern, 1, true) then return true, M.msgs[i] end
  end
  return false
end

function M.boot(game, d)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not d.check(game.boot ~= nil, "boot reached") then return false end
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  if not ok then d.note("new_game error " .. tostring(err)) end
  U.wait(30)
  local session = S.session()
  if not d.check(session and session.version == "emerald", "emerald session") then return false end
  S.setFlag("FLAG_SYS_POKEMON_GET", true)
  S.setFlag("FLAG_SYS_B_DASH", true)
  mod("src.core.game3.time_events").init(session)
  M.hookMessages()
  return session
end

function M.goTo(game, mapId, x, y, facing)
  local Map = mod("src.core.game3.map")
  local Player = mod("src.core.game3.player")
  local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
  if not ok then print("[driver] Map.load " .. mapId .. " error: " .. tostring(err)) end
  local s = S.session()
  if s then s.x, s.y, s.facing = x, y, facing end
  Player.cellX, Player.cellY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.targetX, Player.targetY = x, y
  Player.facing = facing
  U.wait(40)
  for _ = 1, 600 do
    if not S.busy() then break end
    U.wait(1)
  end
  return S.mapNow() == mapId
end

local function answerChoice(game, ans)
  local Choice = mod("src.ui.game3.choice")
  if ans == "b" then U.tap(game, "b") U.wait(6) return end
  local want = 1
  if ans == "no" then want = 2 elseif type(ans) == "number" then want = ans + 1 end
  for _ = 1, 16 do
    if Choice.cursor == want then break end
    U.tap(game, Choice.cursor < want and "down" or "up")
    U.wait(3)
  end
  U.tap(game, "a")
  U.wait(6)
end

local function pickList(index)
  local Menu = mod("src.core.game3.scripting.natives_listmenu").Menu
  if index == "b" then Menu.cancel() return end
  local maxShowed = Menu.maxShowed or 1
  Menu.scroll = math.max(0, math.min(index - maxShowed + 1, (Menu.count or 1) - maxShowed))
  if Menu.scroll < 0 then Menu.scroll = 0 end
  Menu.row = index - Menu.scroll + 1
  Menu.confirm()
end

function M.pump(game, opts)
  opts = opts or {}
  local answers = opts.answers or {}
  local ai = 1
  local Message = mod("src.ui.game3.message")
  local Choice = mod("src.ui.game3.choice")
  local EasyChat = mod("src.ui.game3.easy_chat")
  local Menu = mod("src.core.game3.scripting.natives_listmenu").Menu
  local Hud = mod("src.ui.game3.hud")
  local idle, n = 0, 0
  for _ = 1, opts.limit or 3000 do
    if opts.until_ and opts.until_() then return true end
    if opts.onFrame then opts.onFrame() end
    if EasyChat.isOpen() then
      local st = EasyChat._state
      local words = opts.easyChat and opts.easyChat(st)
      if opts.onEasyChat then opts.onEasyChat(st) end
      U.wait(20)
      if words == false then EasyChat.close(false) else EasyChat.close(true, words or st.words) end
      U.wait(4)
    elseif Choice.isOpen() then
      if opts.onChoice then opts.onChoice(Choice) end
      local ans = answers[ai]
      ai = ai + 1
      answerChoice(game, ans == nil and "yes" or ans)
    elseif Menu.isOpen() then
      if opts.onList then opts.onList(Menu) end
      local ans = answers[ai]
      ai = ai + 1
      U.wait(10)
      pickList(ans == nil and 0 or ans)
      U.wait(4)
    elseif Message.isOpen() and not (opts.holdMessage and opts.holdMessage()) then
      n = n + 1
      if Message.isTyping() then Message.skipReveal() end
      if n % 4 == 0 then U.tap(game, "a") else U.wait(1) end
    elseif opts.decor and package.loaded["src.ui.game3.rse.decoration"] and package.loaded["src.ui.game3.rse.decoration"].open_ then
      local D = package.loaded["src.ui.game3.rse.decoration"]
      U.wait(8)
      if D.state == "categories" then
        D.catCursor = opts.decor[1]
      elseif D.state == "items" then
        D.scroll, D.row = 0, opts.decor[2]
      end
      U.tap(game, "a")
      U.wait(4)
    elseif package.loaded["src.ui.game3.rse.pokeblock_case"] and package.loaded["src.ui.game3.rse.pokeblock_case"].isOpen() then
      if opts.onCase then opts.onCase() end
      U.wait(12)
      U.tap(game, "a")
    elseif Hud._waitButton then
      U.tap(game, "a")
      U.wait(2)
    else
      U.wait(1)
    end
    local caseOpen = package.loaded["src.ui.game3.rse.pokeblock_case"] and package.loaded["src.ui.game3.rse.pokeblock_case"].isOpen()
      or (package.loaded["src.ui.game3.rse.decoration"] and package.loaded["src.ui.game3.rse.decoration"].open_)
    if not S.busy() and not EasyChat.isOpen() and not Menu.isOpen() and not caseOpen then
      idle = idle + 1
      if idle > 6 then return true end
    else
      idle = 0
    end
  end
  local Warp = mod("src.core.game3.warp")
  print(string.format("[driver] pump gave up: vm=%s msg=%s choice=%s easychat=%s list=%s wait=%s locked=%s moving=%s warp=%s",
    S.vmWhere(), tostring(Message.isOpen()), tostring(Choice.isOpen()), tostring(EasyChat.isOpen()), tostring(Menu.isOpen()),
    tostring(Hud._waitButton ~= nil), tostring(mod("src.core.game3.field").locked), tostring(mod("src.core.game3.player").moving),
    tostring(Warp.isBusy())))
  return not S.busy()
end

function M.talk(game, label, opts)
  local eo = S.objectByScript(label)
  if not eo then return false, "no object " .. label end
  if not S.talkTo(game, eo) then return false, "could not talk to " .. label end
  return M.pump(game, opts)
end

function M.wav(path, pcm)
  local f = io.open(path, "wb")
  if not f then return false end
  local n, rate = pcm.samples, pcm.rate
  local function u32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  f:write("RIFF", u32(36 + n * 4), "WAVEfmt ", u32(16), u16(1), u16(2), u32(rate), u32(rate * 4), u16(4), u16(16), "data", u32(n * 4))
  local parts = {}
  for i = 1, n do
    local l = math.floor(math.max(-1, math.min(1, pcm.L[i] or 0)) * 32767)
    local r = math.floor(math.max(-1, math.min(1, pcm.R[i] or 0)) * 32767)
    parts[#parts + 1] = u16(l % 65536) .. u16(r % 65536)
    if #parts >= 4096 then f:write(table.concat(parts)) parts = {} end
  end
  f:write(table.concat(parts))
  f:close()
  return true
end

return M
