package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local Compat = require("src.save_convert.Compat")

local INVALID_ON_PURPOSE = {
  ["g1.red.box_index_invalid"] = true,
  ["g2.crystal.corrupt_primary"] = true,
}

local checked = 0
for _, gen in ipairs({ 1, 2, 3 }) do
  if gen == 1 and not K.gen1Available() then
    print("[skip] gen1 fixture exports need data/generated/")
  else
    for _, c in ipairs(require("tests.fixtures.save.gen" .. gen .. "_build").cases()) do
      if not c.refuse and not INVALID_ON_PURPOSE[c.id] then
        local save = K.import(gen, c.version, c.bytes)
        check(save ~= nil, c.id .. " imports")
        if save then
          local r1 = K.export(gen, c.version, save, c.bytes)
          check(r1 ~= nil, c.id .. " exports over its own cart")
          if r1 then
            checked = checked + 1
            local report = Compat.check(r1, c.version)
            eq(#report.errors, 0, c.id .. " r1 export passes every reader rule -- " .. Compat.describe(report))
          end
          local again = K.import(gen, c.version, c.bytes)
          local fresh = again and K.export(gen, c.version, again, false)
          check(fresh ~= nil, c.id .. " exports with no template")
          if fresh then
            checked = checked + 1
            local report = Compat.check(fresh, c.version)
            eq(#report.errors, 0, c.id .. " fresh export passes every reader rule -- " .. Compat.describe(report))
          end
        end
      end
    end
  end
end
check(checked > 0, "fixture exports were audited")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local specs = {}
for entry in (os.getenv("SAVE_COMPAT_REAL_SAVES") or ""):gmatch("[^;]+") do
  local version, path = entry:match("^(%a+)=(.+)$")
  if version then specs[#specs + 1] = { version, path } end
end
for _, e in ipairs({
  { "POKEPORT_SAV_FIXTURE", "red" }, { "POKEPORT_EMERALD_SAV_FIXTURE", "emerald" },
  { "POKEPORT_FIRERED_SAV_FIXTURE", "firered" }, { "POKEPORT_GEN2_SAV_FIXTURE", os.getenv("POKEPORT_GEN2_SAV_VERSION") or "crystal" },
}) do
  local path = os.getenv(e[1])
  if path and path ~= "" then specs[#specs + 1] = { e[2], path } end
end

if #specs == 0 then
  print("[skip] SAVE_COMPAT_REAL_SAVES not set: real carts are never committed")
end
for _, spec in ipairs(specs) do
  local bytes = read(spec[2])
  check(bytes ~= nil, spec[2] .. " is readable")
  if bytes then
    local report = Compat.check(bytes, spec[1])
    eq(#report.errors, 0, ("real %s cart %s passes every reader rule -- %s"):format(spec[1], spec[2]:match("[^/]*$"),
      Compat.describe(report)))
  end
end

T.finish()
