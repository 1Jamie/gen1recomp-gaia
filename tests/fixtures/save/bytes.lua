local B = {}

function B.new(size, fill)
  local b = { size = size }
  fill = fill or 0
  for i = 0, size - 1 do b[i] = fill end
  return b
end

function B.fromString(s)
  local b = { size = #s }
  for i = 0, #s - 1 do b[i] = s:byte(i + 1) end
  return b
end

function B.put(b, at, ...)
  local vals = { ... }
  for i = 1, #vals do b[at + i - 1] = vals[i] % 256 end
end

function B.fill(b, at, n, v)
  for i = 0, n - 1 do b[at + i] = v % 256 end
end

function B.copy(b, from, to, n)
  for i = 0, n - 1 do b[to + i] = b[from + i] end
end

function B.be(b, at, v, n)
  for i = n - 1, 0, -1 do b[at + i] = v % 256; v = math.floor(v / 256) end
end

function B.le(b, at, v, n)
  for i = 0, n - 1 do b[at + i] = v % 256; v = math.floor(v / 256) end
end

function B.getLE(b, at, n)
  local v = 0
  for i = n - 1, 0, -1 do v = v * 256 + b[at + i] end
  return v
end

function B.sum8(b, from, toExcl)
  local s = 0
  for i = from, toExcl - 1 do s = (s + b[i]) % 256 end
  return s
end

function B.complement8(b, from, toExcl)
  return 255 - B.sum8(b, from, toExcl)
end

function B.sum16(b, from, toExcl)
  local s = 0
  for i = from, toExcl - 1 do s = (s + b[i]) % 65536 end
  return s
end

function B.setBit(b, base, index, on)
  local at = base + math.floor(index / 8)
  local mask = 2 ^ (index % 8)
  local cur = b[at]
  local has = math.floor(cur / mask) % 2 == 1
  if on and not has then b[at] = cur + mask elseif not on and has then b[at] = cur - mask end
end

function B.pack(b)
  local out = {}
  for i = 0, b.size - 1 do out[i + 1] = string.char(b[i]) end
  return table.concat(out)
end

function B.gbText(name)
  local out = {}
  for i = 1, #name do
    local c = name:sub(i, i)
    if c:match("%u") then out[i] = 0x80 + c:byte() - 65
    elseif c:match("%l") then out[i] = 0xA0 + c:byte() - 97
    elseif c:match("%d") then out[i] = 0xF6 + c:byte() - 48
    elseif c == " " then out[i] = 0x7F
    else out[i] = 0xE6 end
  end
  return out
end

function B.putGbName(b, at, name, len, pad)
  local codes = B.gbText(name)
  for i = 1, #codes do b[at + i - 1] = codes[i] end
  b[at + #codes] = 0x50
  for i = #codes + 1, len - 1 do b[at + i] = pad or 0x50 end
end

return B
