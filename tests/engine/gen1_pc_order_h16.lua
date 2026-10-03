package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("H16 actual Gen1 PC order")
local K = require("tests.save_compat._codec")
if not K.gen1Available() then print("SKIP H16 actual Gen1 conversion data unavailable"); os.exit(0) end
local SourceData = require("src.core.Data")
if os.getenv("H16_CANDIDATE_ROOT") then
  package.preload["src.ui.PlayerPC"] = assert(loadfile(os.getenv("H16_CANDIDATE_ROOT") .. "/src/ui/PlayerPC.lua"))
end
local PlayerPC = require("src.ui.PlayerPC")
local cases = require("tests.fixtures.save.gen1_build").cases()
local function ids(list)
  local out = {}
  for _, r in ipairs(list.items) do if r.value then out[#out + 1] = r.value end end
  return table.concat(out, ",")
end
local function row(list, id)
  for i, r in ipairs(list.items) do if r.value == id then list.index = i; return r end end
  error("missing actual row " .. id)
end
for _, version in ipairs({"red", "blue", "yellow"}) do
  local data = K.gen1Data(version)
  for k, v in pairs(data) do SourceData[k] = v end
  local fixture
  for _, c in ipairs(cases) do if c.id == "g1." .. version .. ".basic" then fixture = c end end
  local save = assert(K.import(1, version, assert(fixture).bytes))
  save.pcItems = {POTION = 1, ANTIDOTE = 2}
  save.pcOrder = {"POTION", "ANTIDOTE"}
  save.cartPc = nil
  save.inventory = {REPEL = 2, ANTIDOTE = 2}
  save.bagOrder = {"REPEL", "ANTIDOTE"}
  save.cartBag = nil
  local stack = {_items = {}}
  function stack:push(s) self._items[#self._items + 1] = s end
  function stack:pop() return table.remove(self._items) end
  function stack:top() return self._items[#self._items] end
  local game = {data = data, save = save, stack = stack,
    input = {wasPressed = function() return false end, isDown = function() return false end}}
  local pc = PlayerPC.new(game)
  local function open(i) stack._items = {}; pc.items[i].onSelect(); return stack:top() end
  local function transfer(i, id, qty)
    local list = open(i)
    list.onChoose(row(list, id), list)
    local quantity = stack:top()
    T.check(type(quantity.onDone) == "function", version .. " actual quantity route")
    quantity.onDone(qty)
    return list
  end
  T.eq(ids(open(1)), "POTION,ANTIDOTE", version .. " imported stored order reaches actual withdraw list")
  T.eq(ids(open(3)), "POTION,ANTIDOTE", version .. " imported stored order reaches actual toss list")
  local initialBytes = assert(K.export(1, version, save))
  T.eq(table.concat(assert(K.import(1, version, initialBytes)).pcOrder, ","), "POTION,ANTIDOTE", version .. " existing SRAM codec preserves initial order")
  transfer(2, "REPEL", 1)
  T.eq(save.pcItems.REPEL, 1, version .. " real deposit quantity")
  T.eq(table.concat(save.pcOrder, ","), "POTION,ANTIDOTE,REPEL", version .. " new deposit appends saved order")
  T.eq(ids(open(1)), "POTION,ANTIDOTE,REPEL", version .. " deposited order reaches reopened withdraw")
  transfer(1, "ANTIDOTE", 1)
  T.eq(save.pcItems.ANTIDOTE, 1, version .. " partial withdrawal leaves stack")
  T.eq(table.concat(save.pcOrder, ","), "POTION,ANTIDOTE,REPEL", version .. " partial withdrawal keeps order")
  transfer(1, "ANTIDOTE", 1)
  T.eq(save.pcItems.ANTIDOTE, nil, version .. " full withdrawal removes stack")
  T.eq(table.concat(save.pcOrder, ","), "POTION,REPEL", version .. " full withdrawal removes saved slot")
  transfer(2, "ANTIDOTE", 1)
  T.eq(table.concat(save.pcOrder, ","), "POTION,REPEL,ANTIDOTE", version .. " redeposit appends after surviving rows")
  local tossed = transfer(3, "POTION", 1)
  local choice = stack:top()
  T.check(type(choice.onChoose) == "function", version .. " real toss confirmation")
  choice.onChoose(true)
  T.eq(save.pcItems.POTION, nil, version .. " actual toss removes chosen stack")
  T.eq(table.concat(save.pcOrder, ","), "REPEL,ANTIDOTE", version .. " toss removes saved slot")
  T.eq(ids(open(1)), "REPEL,ANTIDOTE", version .. " survivor order reaches actual withdraw")
  local finalBytes = assert(K.export(1, version, save))
  local back = assert(K.import(1, version, finalBytes))
  T.eq(table.concat(back.pcOrder, ","), "REPEL,ANTIDOTE", version .. " actual SRAM export reload retains gameplay order")
  T.eq(back.pcItems.REPEL, save.pcItems.REPEL, version .. " SRAM survivor count")
  T.eq(back.pcItems.ANTIDOTE, save.pcItems.ANTIDOTE, version .. " SRAM other survivor count")
end

local Serializer = require("src.core.SaveSerializer")
local function stores(save)
  return Serializer.encode({pcItems = save.pcItems, pcOrder = save.pcOrder,
    inventory = save.inventory, bagOrder = save.bagOrder})
end
for _, version in ipairs({"red", "blue", "yellow"}) do
  local data = K.gen1Data(version)
  for k, v in pairs(data) do SourceData[k] = v end
  local fixture
  for _, c in ipairs(cases) do if c.id == "g1." .. version .. ".basic" then fixture = c end end
  local function fresh(pcItems, pcOrder, inventory, bagOrder)
    local save = assert(K.import(1, version, assert(fixture).bytes))
    save.pcItems, save.pcOrder, save.cartPc = pcItems, pcOrder, nil
    save.inventory, save.bagOrder, save.cartBag = inventory or {}, bagOrder or {}, nil
    local stack = {_items = {}}
    function stack:push(s) self._items[#self._items + 1] = s end
    function stack:pop() return table.remove(self._items) end
    function stack:top() return self._items[#self._items] end
    local input = {pressed = {}}
    function input:wasPressed(k) return self.pressed[k] or false end
    function input:isDown() return false end
    local copied = {}
    for k, v in pairs(data) do copied[k] = v end
    local game = {data = copied, save = save, stack = stack, input = input}
    local pc = PlayerPC.new(game)
    local function open(i) stack._items = {}; pc.items[i].onSelect(); return stack:top() end
    local function select(i, id, quantity)
      local list = open(i)
      list.onChoose(row(list, id), list)
      if quantity ~= false then
        local q = stack:top()
        assert(type(q.onDone) == "function", "actual quantity selector required")
        q.onDone(quantity)
      end
      return list
    end
    return game, open, select
  end
  do
    local order = {"POTION", "ANTIDOTE"}
    local g, open, select = fresh({POTION = 2, ANTIDOTE = 1}, order, {POTION = 3}, {"POTION"})
    select(2, "POTION", 1)
    T.eq(g.save.pcItems.POTION, 3, version .. " existing deposit adds count")
    T.check(g.save.pcOrder == order, version .. " existing saved order identity retained")
    T.eq(table.concat(order, ","), "POTION,ANTIDOTE", version .. " same stack deposit retains position")
    T.eq(ids(open(1)), "POTION,ANTIDOTE", version .. " same stack deposit does not duplicate visible row")
    local bytes = assert(K.export(1, version, g.save))
    T.eq(table.concat(assert(K.import(1, version, bytes)).pcOrder, ","), "POTION,ANTIDOTE", version .. " same stack SRAM ordered")
  end
  for _, menu in ipairs({1, 2, 3}) do
    local g, open, select = fresh({POTION = 2, ANTIDOTE = 1}, {"POTION", "ANTIDOTE"}, {REPEL = 2}, {"REPEL"})
    local before = stores(g.save)
    select(menu, menu == 2 and "REPEL" or "POTION", nil)
    T.eq(stores(g.save), before, version .. " menu " .. menu .. " quantity cancel preserves stores and order")
    local list = open(menu)
    list.onChoose(list.items[#list.items], list)
    T.eq(stores(g.save), before, version .. " menu " .. menu .. " CANCEL row preserves stores and order")
    T.eq(g.stack:top(), nil, version .. " menu " .. menu .. " CANCEL closes actual list")
  end
  do
    local g, open, select = fresh({POTION = 2, ANTIDOTE = 1}, {"POTION", "ANTIDOTE"})
    local before = stores(g.save)
    select(3, "POTION", 1)
    g.stack:top().onChoose(false)
    T.eq(stores(g.save), before, version .. " declined toss preserves storage order")
    select(3, "POTION", 1)
    g.stack:top().onChoose(true)
    T.eq(g.save.pcItems.POTION, 1, version .. " partial toss correct quantity")
    T.eq(table.concat(g.save.pcOrder, ","), "POTION,ANTIDOTE", version .. " partial toss retains order")
    T.eq(ids(open(3)), "POTION,ANTIDOTE", version .. " partial toss retains visible row")
  end
  do
    local g, open, select = fresh({POTION = 2, ANTIDOTE = 1}, {"POTION", "ANTIDOTE"}, {REPEL = 1}, {"REPEL"})
    g.data.constants = {bagSize = 1}
    local before = stores(g.save)
    local list = select(1, "POTION", 1)
    T.eq(stores(g.save), before, version .. " full Bag refuses withdrawal without reordering PC")
    T.check(not list.pcCompletion, version .. " refused withdrawal has no completion")
    g.save.inventory, g.save.bagOrder = {POTION = 99}, {"POTION"}
    before = stores(g.save)
    select(1, "POTION", 1)
    T.eq(stores(g.save), before, version .. " 99 stack refusal preserves all stores and order")
  end
  do
    local g, open, select = fresh({POTION = 1}, {"POTION"}, {ANTIDOTE = 2, POTION = 2}, {"ANTIDOTE", "POTION"})
    g.data.field = {pcItemCap = 1}
    local before = stores(g.save)
    local list = select(2, "ANTIDOTE", 1)
    T.eq(stores(g.save), before, version .. " full PC refuses new deposit without phantom order slot")
    T.check(not list.pcCompletion, version .. " full PC refusal has no completion")
    select(2, "POTION", 1)
    T.eq(g.save.pcItems.POTION, 2, version .. " full PC still permits existing stack")
    T.eq(table.concat(g.save.pcOrder, ","), "POTION", version .. " existing stack in full PC keeps order")
  end
  do
    local order = {"POTION", "ANTIDOTE"}
    local g, open, select = fresh({POTION = 2, ANTIDOTE = 1}, order, {POKE_FLUTE = 1, HM_CUT = 1}, {"POKE_FLUTE", "HM_CUT"})
    for _, id in ipairs({"POKE_FLUTE", "HM_CUT"}) do
      select(2, id, false)
      T.eq(g.save.pcItems[id], 1, version .. " actual key deposit moves one without quantity UI " .. id)
      T.eq(g.save.pcOrder[#g.save.pcOrder], id, version .. " key deposit appends once " .. id)
      T.check(g.stack:top().kind == "pc_item_deposit", version .. " key deposit bypasses quantity " .. id)
      local before = stores(g.save)
      local list = select(3, id, false)
      T.eq(stores(g.save), before, version .. " important-item toss refusal retains order " .. id)
      T.check(not list.pcCompletion, version .. " important-item refusal no completion " .. id)
      select(1, id, false)
      T.eq(g.save.pcItems[id], nil, version .. " key withdrawal empties storage " .. id)
      T.eq(table.concat(g.save.pcOrder, ","), "POTION,ANTIDOTE", version .. " key withdrawal removes saved slot " .. id)
    end
  end
  do
    local order = {"REPEL", "MISSING_ITEM", "POTION", "REPEL"}
    local g, open = fresh({REPEL = 2, POTION = 1, ANTIDOTE = 1}, order)
    T.eq(ids(open(1)), "REPEL,POTION,ANTIDOTE", version .. " stale duplicate order reconciles preserving first surviving positions")
    T.check(g.save.pcOrder == order, version .. " reconciliation preserves original order array")
    T.eq(table.concat(order, ","), "REPEL,POTION,ANTIDOTE", version .. " direct-added item appended once")
    g.save.pcItems.POTION = nil
    g.save.pcItems.FULL_HEAL = 1
    T.eq(ids(open(3)), "REPEL,ANTIDOTE,FULL_HEAL", version .. " direct delete/add reconciles actual toss consumer")
    local bytes = assert(K.export(1, version, g.save))
    T.eq(table.concat(assert(K.import(1, version, bytes)).pcOrder, ","), "REPEL,ANTIDOTE,FULL_HEAL", version .. " repaired order survives SRAM")
    T.eq(data.items.ANTIDOTE.index, 0x0B, version .. " exact source ANTIDOTE index")
    T.eq(data.items.POTION.index, 0x14, version .. " exact source POTION index")
    T.eq(data.items.REPEL.index, 0x1E, version .. " exact source REPEL index")
    local legacy, legacyOpen = fresh({ANTIDOTE = 1, POTION = 2, REPEL = 1}, nil)
    T.eq(ids(legacyOpen(1)), "ANTIDOTE,POTION,REPEL", version .. " legacy missing order uses exact item-index baseline")
    T.eq(table.concat(legacy.save.pcOrder or {}, ","), "ANTIDOTE,POTION,REPEL", version .. " legacy baseline persists once")
    local first = legacy.save.pcOrder
    legacyOpen(3)
    T.check(legacy.save.pcOrder == first, version .. " legacy order stable on reopened toss")
  end
end
do
  local data = K.gen1Data("red")
  for k, v in pairs(data) do SourceData[k] = v end
  local fixture
  for _, c in ipairs(cases) do if c.id == "g1.red.unknown_pc_item" then fixture = c end end
  local save = assert(K.import(1, "red", assert(fixture).bytes))
  local carrier, order = assert(save.cartPc), save.pcOrder
  local raw = Serializer.encode(carrier)
  save.inventory, save.bagOrder, save.cartBag = {REPEL = 1}, {"REPEL"}, nil
  local stack = {_items = {}}
  function stack:push(s) self._items[#self._items + 1] = s end
  function stack:pop() return table.remove(self._items) end
  function stack:top() return self._items[#self._items] end
  local game = {data = data, save = save, stack = stack, input = {wasPressed = function() return false end}}
  local pc = PlayerPC.new(game)
  pc.items[2].onSelect()
  local list = stack:top();list.onChoose(row(list, "REPEL"), list);stack:top().onDone(1)
  T.check(save.cartPc == carrier and save.pcOrder == order, "opaque PC carrier and supported order identities retained")
  T.eq(Serializer.encode(carrier), raw, "actual PC deposit never mutates opaque rows")
  T.eq(table.concat(order, ","), "POTION,REPEL", "carrier PC known deposit appends gameplay order")
  local bytes = assert(K.export(1, "red", save))
  local O = require("src.save_convert.GenSave").OFFSETS
  T.eq(bytes:sub(O.pcItems + 1, O.pcItems + 7), string.char(0x14, 4, 0x1E, 1, 0xFB, 2, 0xFF), "actual SRAM stores ordered known stacks and untouched unknown byte row")
  local back = assert(K.import(1, "red", bytes))
  T.eq(table.concat(back.pcOrder, ","), "POTION,REPEL", "carrier SRAM reload preserves known gameplay order")
  T.eq(back.pcItems.POTION, 4, "duplicate imported POTION quantity preserved")
  T.check(back.cartPc and back.cartPc[3][1] == 0xFB and back.cartPc[3][2] == 2, "unknown cartridge item retained after reload")
end

T.finish()
