local K = require("tests.save_compat._codec")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")
local Compat = require("src.save_convert.Compat")
local Structs = require("src.save_convert.gen3_port.structs")
local Gen3Save = require("src.save_convert.Gen3Save")

local H = {}

H.Structs = Structs

function H.family(version) return version == "emerald" and "emerald" or "frlg" end

function H.codec(version) return Gen3Save.forVersion(version) end

function H.rng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  return function(n)
    state = (state * 48271) % 2147483647
    if n then return state % n end
    return state
  end
end

function H.cart(version, edit)
  local w = G3.base(version)
  if edit then edit(w) end
  return G3.emit(w)
end

function H.randomize(w, block, off, size, rng)
  for i = 0, size - 1 do w[block][off + i] = rng(256) end
end

function H.import(version, bytes)
  return assert(K.import(3, version, bytes))
end

function H.fresh(version, save)
  save.modData = type(save.modData) == "table" and save.modData or {}
  save.modData.cartImage = nil
  return assert(K.export(3, version, save, false))
end

function H.withTemplate(version, save, bytes)
  return assert(K.export(3, version, save, bytes))
end

function H.blocks(bytes, version)
  return assert(Compat.gen3Blocks(bytes, H.family(version)))
end

function H.spec(blocks, block, off, spec, version)
  return Structs.read(blocks[block], off, spec, H.codec(version))
end

function H.deepEqual(a, b, path, out)
  out = out or {}
  path = path or ""
  if type(a) ~= type(b) then
    out[#out + 1] = path .. ": " .. tostring(a) .. " ~= " .. tostring(b)
    return out
  end
  if type(a) ~= "table" then
    if a ~= b then out[#out + 1] = path .. ": " .. tostring(a) .. " ~= " .. tostring(b) end
    return out
  end
  for k, v in pairs(a) do H.deepEqual(v, b[k], path .. "." .. tostring(k), out) end
  for k in pairs(b) do
    if a[k] == nil then out[#out + 1] = path .. "." .. tostring(k) .. ": missing on left" end
  end
  return out
end

function H.sameBytes(a, b, block, off, size)
  return a[block]:sub(off + 1, off + size) == b[block]:sub(off + 1, off + size)
end

return H
