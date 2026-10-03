-- pokered/scripts/ViridianCity.asm:150
-- pokeyellow/scripts/ViridianCity_2.asm:10
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity Viridian gambler #2632")
local GameVersion = require("src.core.GameVersion")
local TextBox = require("src.render.TextBox")
local StateStack = require("src.core.StateStack")
local bit = require("bit")
local oldVersion = GameVersion.get()
local savedModules = {}
for name, value in pairs(package.loaded) do
  if name:match("^data%.scripts%.") or name == "src.script.MapScripts" then
    savedModules[name] = value
  end
end

local badges = {
  "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
  "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
}

local function clearRegistry()
  local names = {}
  for name in pairs(package.loaded) do
    if name:match("^data%.scripts%.") or name == "src.script.MapScripts" then
      names[#names + 1] = name
    end
  end
  for _, name in ipairs(names) do package.loaded[name] = nil end
end

local function exercise(handler, version, mask, flagName)
  local inventory = {}
  for i, badge in ipairs(badges) do
    if bit.band(mask, bit.lshift(1, i - 1)) ~= 0 then inventory[badge] = true end
  end
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local pressed = false
  local game = {
    data = { text = {
      _ViridianCityGambler1GymLeaderReturnedText = "RETURNED{DONE}",
      _ViridianCityGambler1GymAlwaysClosedText = "CLOSED{DONE}",
    } },
    save = { inventory = inventory, flags = {}, options = { textSpeed = 1 } },
    stack = stack,
    input = {
      wasPressed = function(_, key) return pressed and key == "a" end,
      isDown = function() return false end,
    },
  }
  if flagName then game.save.flags[flagName] = true end
  local completed = 0
  local label = version .. " mask=" .. mask .. " event=" .. (flagName or "none")
  handler(game, nil, nil, function() completed = completed + 1 end)
  local box = stack:top()
  S.check(getmetatable(box) == TextBox, label .. " opens the actual TextBox")
  if getmetatable(box) ~= TextBox then return end
  local expected = (mask == 127 or flagName ~= nil) and "RETURNED" or "CLOSED"
  S.eq(table.concat(box.pages[1], "\n"), expected, label .. " cartridge branch")
  S.eq(completed, 0, label .. " callback waits for dismissal")
  for _ = 1, 100 do
    if box.done then break end
    stack:update(1 / 60)
  end
  S.check(box.done, label .. " finishes revealing")
  pressed = true
  stack:update(1 / 60)
  S.eq(stack:top(), nil, label .. " dismisses the TextBox")
  S.eq(completed, 1, label .. " completes callback exactly once")
  stack:update(1 / 60)
  S.eq(completed, 1, label .. " callback stays completed")
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  GameVersion.set(version)
  clearRegistry()
  local scripts = require("data.scripts.init")
  local handler = scripts.talkScript("VIRIDIAN_CITY", "TEXT_VIRIDIANCITY_GAMBLER1")
  S.check(type(handler) == "function", version .. " resolves the actual registry handler")
  if type(handler) == "function" then
    for mask = 0, 255 do
      exercise(handler, version, mask, nil)
      exercise(handler, version, mask, "EVENT_BEAT_GIOVANNI")
      exercise(handler, version, mask, "EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI")
    end
  end
end

clearRegistry()
for name, value in pairs(savedModules) do package.loaded[name] = value end
GameVersion.set(oldVersion)
S.finish()
