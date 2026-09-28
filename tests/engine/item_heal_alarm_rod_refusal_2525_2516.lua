package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness").suite("item heal alarm and rod refusal")
local Fixtures = require("tests.modkit.fixtures")
local ItemEffects = require("src.inventory.ItemEffects")
local Sound = require("src.core.Sound")
local Data = Fixtures.fresh()
local save = { player = { name = "RED" }, party = {}, inventory = {} }
local stopped = 0
local oldStop = Sound.stopLoop
Sound.stopLoop = function(name)
  if name == "Low_Health_Alarm" then stopped = stopped + 1 end
end
local target = { hp = 5, stats = { hp = 51 }, species = "FIXMON_A",
                moves = {}, status = nil }
local result = ItemEffects.use(Data, save, "POTION", target, {})
T.eq(result, "consumed", "a valid battle Potion succeeds")
T.eq(stopped, 1, "successful battle healing stops the alarm synchronously")
stopped = 0
target.hp = target.stats.hp
result = ItemEffects.use(Data, save, "POTION", target, {})
T.eq(result, "failed", "a no-effect Potion is refused")
T.eq(stopped, 0, "a failed heal leaves alarm ownership unchanged")
Sound.stopLoop = oldStop
local dryLand = { player = { surfing = false },
  facingIsShoreOrWater = function() return false end }
for _, rod in ipairs({ "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }) do
  local rodResult, messages = ItemEffects.use(Data, save, rod, nil, false, nil, dryLand)
  T.eq(rodResult, "failed", rod .. " refuses away from shore or water")
  T.check(messages and messages[1] and messages[1]:find("isn't the", 1, true),
    rod .. " uses the generic not-time ROM text")
end
local water = { player = { surfing = false },
  facingIsShoreOrWater = function() return true end }
T.eq(ItemEffects.use(Data, save, "SUPER_ROD", nil, false, nil, water),
  "fish", "a rod still starts fishing at water")
Data.items.SUPER_ROD = { id = "SUPER_ROD", name = "SUPER ROD", keyItem = true }
local Bag = require("src.inventory.Bag")
Bag.add(save, "SUPER_ROD", 1)
local realTextBox = package.loaded["src.render.TextBox"]
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done)
    return { textBox = true, text = text, done = done }
  end,
}
package.loaded["src.ui.BagMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local game = {
  data = Data,
  save = save,
  overworld = dryLand,
  stack = { states = {} },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
function game.stack:push(state) self.states[#self.states + 1] = state end
function game.stack:pop() return table.remove(self.states) end
function game.stack:top() return self.states[#self.states] end
local list = BagMenu.new(game, {})
game.stack:push(list)
local rodRow
for i, row in ipairs(list.items) do
  if row.value == "SUPER_ROD" then rodRow = i end
end
T.check(rodRow ~= nil, "the rod is available in the bag")
list.index = rodRow
list.onChoose(list.items[rodRow], list)
local options = game.stack:top()
T.check(options and options.items and options.items[1], "the rod USE/TOSS menu opens")
options.items[1].onSelect()
local textBox = game.stack:top()
T.check(textBox and textBox.textBox and textBox.text:find("isn't the", 1, true),
  "the bag displays the not-time message")
T.check(game.stack.states[1] == list, "the bag remains open after rod refusal")

local noOverworld = {
  data = Data,
  save = save,
  stack = { states = {} },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
function noOverworld.stack:push(state) self.states[#self.states + 1] = state end
function noOverworld.stack:pop() return table.remove(self.states) end
function noOverworld.stack:top() return self.states[#self.states] end
local noOverworldList = BagMenu.new(noOverworld, {})
noOverworld.stack:push(noOverworldList)
local noOverworldRod
for i, row in ipairs(noOverworldList.items) do
  if row.value == "SUPER_ROD" then noOverworldRod = i end
end
noOverworldList.index = noOverworldRod
noOverworldList.onChoose(noOverworldList.items[noOverworldRod], noOverworldList)
noOverworld.stack:top().items[1].onSelect()
local noOverworldText = noOverworld.stack:top()
T.check(noOverworldText and noOverworldText.textBox
    and noOverworldText.text:find("No good!", 1, true),
  "the bag handles a rod selection without an overworld")
package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.ui.BagMenu"] = nil
T.finish()
