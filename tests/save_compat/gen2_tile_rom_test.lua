package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Ctx = require("src.save_convert.Gen2MapContext")
local Extractor = require("src.import.RomExtractorGen2")
local Json = require("src.link.Json")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local cases = {
  { "gold", "../pokegold/pokegold.gbc", 18 },
  { "silver", "../pokegold/pokesilver.gbc", 18 },
  { "crystal", "../pokecrystal/pokecrystal.gbc", 24 },
}

for _, row in ipairs(cases) do
  local version, path = row[1], row[2]
  local rom = read(os.getenv("GEN2_" .. version:upper() .. "_ROM") or path)
  if rom then
    local manifest = assert(Json.decode(assert(read("tools/rom_manifest_" .. version .. ".json"))))
    local extractor = Extractor.new(rom, manifest)
    extractor.write = function() end
    local maps = extractor:extractMaps()
    local scripts = extractor:extractScriptsAndText(maps, {}).scripts
    local data = { maps = maps, scripts = scripts }
    local count = 0
    for id, def in pairs(maps) do
      for _, callback in ipairs(def.callbacks or {}) do
        if callback.callback == "MAPCALLBACK_TILES" and id ~= "PLAYERS_HOUSE_2F" then
          count = count + 1
          for pattern = 0, 3 do
            local state = { events = {}, engineFlags = {} }
            for i = 0, 255 do
              state.events[i] = pattern == 0 and 0 or pattern == 1 and 255 or (i * 71 + pattern * 49) % 256
            end
            for i = 0, 200 do state.engineFlags[i] = pattern == 1 or pattern > 1 and i % pattern == 0 end
            local patched = {}
            for i, block in ipairs(def.blocks) do patched[i] = block end
            local vm = Vm.new(scripts, {}, Events.new():restore(state.events), {
              getEngineFlag = function(flag) return state.engineFlags[flag] end,
              changeBlock = function(x, y, block) patched[y * def.width + x + 1] = block end,
            })
            T.eq(vm:runCallback(callback.scriptKey), true, version .. " " .. id .. " original callback runs in the runtime")
            local callbacks, blocks = def.callbacks, def.blocks
            for y = 0, def.height * 2 - 1, 2 do
              for x = 0, def.width * 2 - 1, 2 do
                local actual = assert(Ctx.reposition(data, version, def.group, def.map, x, y, state))
                def.callbacks, def.blocks = {}, patched
                local expected = assert(Ctx.reposition(data, version, def.group, def.map, x, y, {}))
                def.callbacks, def.blocks = callbacks, blocks
                local off = Ctx.offsetsFor(version).screenSave
                T.eq(table.concat(actual.writes[off], ","), table.concat(expected.writes[off], ","),
                  version .. " " .. id .. " window matches the runtime callback at " .. x .. "," .. y)
              end
            end
          end
        end
      end
    end
    T.eq(count, row[3], version .. " covers every non-bedroom tile callback")
  else
    io.write("SKIP " .. version .. " original-ROM callback checks: ROM not available\n")
  end
end

T.finish()
