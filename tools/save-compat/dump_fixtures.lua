package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")

local out = arg[1]
if not out then
  io.stderr:write("usage: luajit tools/save-compat/dump_fixtures.lua <output dir>\n")
  os.exit(2)
end

local list = {}
local skipped = {}
local function write(name, bytes)
  local path = out .. "/" .. name
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
  list[#list + 1] = path
end

for _, gen in ipairs({ 1, 2, 3 }) do
  if gen == 1 and not K.gen1Available() then
    io.stderr:write("gen1 fixtures skipped (needs data/generated/ for the Gen 1 save codec)\n")
    skipped[#skipped + 1] = "g1."
  else
    for _, c in ipairs(require("tests.fixtures.save.gen" .. gen .. "_build").cases()) do
      if not c.refuse then
        write(c.id .. ".src.sav", c.bytes)
        local save = K.import(gen, c.version, c.bytes)
        if save then
          local r1 = K.export(gen, c.version, save, c.bytes)
          if r1 then write(c.id .. ".r1.sav", r1) end
          local again = K.import(gen, c.version, c.bytes)
          local r2 = again and K.export(gen, c.version, again, false)
          if r2 then write(c.id .. ".fresh.sav", r2) end
        end
      end
    end
  end
end

local f = assert(io.open(out .. "/list.txt", "w"))
f:write(table.concat(list, "\n"), "\n")
f:close()
local sk = assert(io.open(out .. "/skipped.txt", "w"))
sk:write(table.concat(skipped, "\n"), #skipped > 0 and "\n" or "")
sk:close()
print(("%d files in %s"):format(#list, out))
