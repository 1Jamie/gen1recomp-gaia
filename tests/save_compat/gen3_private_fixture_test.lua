package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local K = require("tests.save_compat._codec")
local D = require("tests.save_compat._gen3_decode")
local Compat = require("src.save_convert.Compat")
local Gen3Save = require("src.save_convert.Gen3Save")

local SOURCES = {
  { env = "POKEPORT_EMERALD_SAV_FIXTURE", version = "emerald", family = "emerald" },
  { env = "POKEPORT_FIRERED_SAV_FIXTURE", version = "firered", family = "frlg" },
}

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function monList(dec)
  local out = {}
  for i, m in ipairs(dec.party) do out[#out + 1] = { "party" .. i, m } end
  for b, box in ipairs(dec.boxes) do
    for s = 1, 30 do if box[s] then out[#out + 1] = { ("box%d.%d"):format(b, s), box[s] } end end
  end
  return out
end

local ran = 0
for _, src in ipairs(SOURCES) do
  local path = os.getenv(src.env)
  local bytes = path and read(path)
  if path and not bytes then check(false, src.env .. " points at a readable file (" .. path .. ")") end
  if bytes then
    ran = ran + 1
    local id = "F3 " .. src.version
    local orig = assert(D.decode(bytes, src.family), id .. " decodes independently")
    local save, err = K.import(3, src.version, bytes)
    check(save ~= nil, id .. " imports (" .. tostring(err) .. ")")
    if save then
      eq(Gen3Save.forVersion(src.version).slotTemplate(save), bytes, id .. " the slot carries the cart image")
      local variants = {
        { "explicit template", function() return K.export(3, src.version, save, bytes) end },
        { "slot template", function() return K.export(3, src.version, save, nil) end },
      }
      local out1
      for _, v in ipairs(variants) do
        local out, xerr = v[2]()
        check(out ~= nil, id .. " " .. v[1] .. " exports (" .. tostring(xerr) .. ")")
        if out then
          out1 = out1 or out
          local entries = K.r1Diff(3, src.version, bytes, out)
          check(#entries == 0, id .. " " .. v[1] .. " R1 logical round trip (" .. require("tests.save_compat._diff").format(entries, 6) .. ")")
          local dec = assert(D.decode(out, src.family))
          eq(dec.key, orig.key, id .. " " .. v[1] .. " keeps the cart key")
          eq(dec.counter, orig.counter + 1, id .. " " .. v[1] .. " is the cart's next save")
          local a, b = monList(orig), monList(dec)
          eq(#b, #a, id .. " " .. v[1] .. " mon count")
          local shinyLost, pidDiff = 0, 0
          for i, row in ipairs(a) do
            local m2 = b[i] and b[i][2]
            if not m2 or m2.pid ~= row[2].pid or m2.otid ~= row[2].otid then pidDiff = pidDiff + 1 end
            if row[2].shiny and not (m2 and m2.shiny) then shinyLost = shinyLost + 1 end
          end
          eq(pidDiff, 0, id .. " " .. v[1] .. " PID/OTID of every mon kept")
          eq(shinyLost, 0, id .. " " .. v[1] .. " every shiny stays shiny")
          local report = Compat.check(out, src.version)
          eq(#report.errors, 0, id .. " " .. v[1] .. " passes the reader validator (" .. Compat.describe(report) .. ")")
          local back = K.import(3, src.version, out)
          check(back ~= nil, id .. " " .. v[1] .. " re-imports")
        end
      end
      local bare = K.import(3, src.version, bytes)
      bare.modData.cartImage = nil
      local codec = Gen3Save.forVersion(src.version)
      local cart = assert(codec.decode(bytes))
      local opts = K.gen3Opts(src.version, nil)
      opts.mapLayoutId = function(g, n)
        if g == cart.location.group and n == cart.location.num then return cart.mapLayoutId end
      end
      opts.healWarp = function() return cart.lastHealLocation end
      local fresh, ferr = codec.exportPort(bare, opts)
      check(fresh ~= nil, id .. " templateless export (" .. tostring(ferr) .. ")")
      if fresh then
        local dec = assert(D.decode(fresh, src.family))
        eq(dec.key, orig.key, id .. " templateless export keeps the stored key")
        eq(#monList(dec), #monList(orig), id .. " templateless export keeps every mon")
        eq(dec.money, orig.money, id .. " templateless money")
        eq(#Compat.check(fresh, src.version).errors, 0, id .. " templateless export passes the reader validator")
      end
      local dir = os.getenv("POKEPORT_GEN3_PROBE_OUT")
      if dir and out1 then
        for name, data in pairs({ ["withcart"] = out1, ["nocart"] = fresh }) do
          local f = io.open(("%s/%s.%s.sav"):format(dir, src.version, name), "wb")
          if f then f:write(data); f:close() end
        end
      end
    end
  end
end
if ran == 0 then print("gen3_private_fixture_test: skipped (set POKEPORT_EMERALD_SAV_FIXTURE or POKEPORT_FIRERED_SAV_FIXTURE)") end
T.finish()
