package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Story = assert(loadfile("data/scripts/story.lua"))()
local script = Story.BLUES_HOUSE.talk.TEXT_BLUESHOUSE_DAISY_SITTING
local give, hide, text
for i, row in ipairs(script) do
  if row[1] == "give_item" and row[2] == "TOWN_MAP" then give = i end
  if row[1] == "hide_object" and row[3] == "BLUESHOUSE_TOWN_MAP" then hide = i end
  if row[1] == "show_text" and row[2] == "_GotMapText" then text = i end
end
T.check(give ~= nil, "Daisy grants the Town Map")
T.eq(script[give] and script[give][4], false,
  "Town Map grant does not block on the received-item textbox")
T.check(hide and give and hide > give,
  "the wall map is hidden only after the Town Map grant succeeds")
T.check(text and hide and text > hide,
  "the received-item textbox starts after the wall map is hidden")
T.finish("blues_house_town_map_order_2523")
