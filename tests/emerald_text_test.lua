package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_text_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local raw = f:read("*a")
f:close()

local rom = { size = #raw }
function rom:get(o) return raw:byte(o + 1) end
function rom:u16(o) local a, b = raw:byte(o + 1, o + 2); return a + b * 256 end
function rom:u32(o)
  local a, b, c, d = raw:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom:ptrOffset(p)
  if p and p >= 0x08000000 and p < 0x0A000000 then return p - 0x08000000 end
end

local Versions = require("src.import.gba.versions")
Versions.select("emerald")
local TextIR = require("src.core.game3.scripting.text_ir")

local rse = TextIR.dialect("rse")
local extra = rse.CHARMAP_EXTRA or {}
-- pokeemerald/charmap.txt:45
local PENDING = { [0x34] = true, [0x55] = true, [0x56] = true, [0x57] = true, [0x58] = true, [0x59] = true,
  [0x77] = true, [0x79] = true, [0x7A] = true, [0x7B] = true, [0x7C] = true }

local function unknownBytes(off, pending)
  local out, i = {}, off
  while i - off < 2048 do
    local c = raw:byte(i + 1)
    if c == 0xFF then break end
    if c == 0xFD or c == 0xF7 or c == 0xF8 or c == 0xF9 then
      i = i + 2
    elseif c == 0xFC then
      i = i + 2 + (TextIR.EXT_ARGS[raw:byte(i + 2)] or 0)
    elseif c == 0xFA or c == 0xFB or c == 0xFE then
      i = i + 1
    else
      if not (TextIR.CHARMAP[c] or TextIR.LIGATURE[c] or extra[c]) and not (pending and PENDING[c]) then
        out[#out + 1] = c
      end
      i = i + 1
    end
  end
  return out
end

local function japanese(name)
  return name:find("JP", 1, true) or name:find("Jpn", 1, true) or name:find("Japanese", 1, true)
end

local names = {}
for name in pairs(Versions.NAMED_TEXTS) do
  if not japanese(name) then names[#names + 1] = name end
end
table.sort(names)

local seed = tonumber(os.getenv("POKEPORT_TEXT_SEED") or "") or os.time()
math.randomseed(seed)
local picked = {}
for _ = 1, 20 do
  local name = names[math.random(#names)]
  local bytes = {}
  local off = Versions.NAMED_TEXTS[name]
  for i = 0, 1023 do
    local b = raw:byte(off + i + 1)
    bytes[#bytes + 1] = b
    if b == 0xFF then break end
  end
  local ir = TextIR.decode(bytes, { dialect = "rse" })
  check(ir[#ir] and ir[#ir].t == "eos", name .. " decodes to an EOS-terminated IR")
  local bad = unknownBytes(off, true)
  eq(#bad, 0, "random named text " .. name .. " has no unknown glyph bytes (seed " .. seed .. ")")
  picked[#picked + 1] = name
end

local seenUnknown, firstAt = {}, {}
local function scan(label, off)
  for _, c in ipairs(unknownBytes(off, false)) do
    seenUnknown[c] = (seenUnknown[c] or 0) + 1
    firstAt[c] = firstAt[c] or label
  end
end
for _, name in ipairs(names) do scan(name, Versions.NAMED_TEXTS[name]) end
for name, off in pairs(Versions.NAMED_BATTLE_TEXTS) do
  if not japanese(name) then scan(name, off) end
end
local slots, nonPointer = 0, 0
for _, t in ipairs(Versions.TEXT_TABLES) do
  if not japanese(t.name) then
    for i = 0, t.count * (t.inner or 1) - 1 do
      slots = slots + 1
      if t.inline then
        scan(t.name, t.addr + i * t.stride)
      else
        local p = rom:u32(t.addr + i * t.stride)
        if p ~= 0 then
          if rom:ptrOffset(p) then
            local target = Versions.SYMS.namesAt(p - 0x08000000)[1] or ""
            if not (japanese(target) or t.name:find("Debug", 1, true)) then
              scan(t.name .. "[" .. i .. "]", p - 0x08000000)
            end
          else
            nonPointer = nonPointer + 1
          end
        end
      end
    end
  end
end
eq(nonPointer, 0, "every non-null text table slot (" .. slots .. ") is a ROM pointer")
local outside = {}
for c, n in pairs(seenUnknown) do
  if not PENDING[c] then outside[#outside + 1] = string.format("0x%02X x%d (%s)", c, n, firstAt[c]) end
end
table.sort(outside)
eq(#outside, 0, "no unknown glyph bytes outside the rse charmap gap list: " .. table.concat(outside, ", "))
local pending = {}
for c in pairs(PENDING) do
  if seenUnknown[c] then pending[#pending + 1] = string.format("0x%02X", c) end
end
table.sort(pending)
if #pending > 0 then
  print("emerald_text_test: rse charmap still lacks " .. table.concat(pending, " ") .. " (crossfile W1-T)")
end

local Placeholders = require("src.import.gba.text_placeholders_extract")
local files = {}
local cache = {
  write = function(_, rel, data) files[rel] = data; return true end,
  exists = function(_, rel) return files[rel] ~= nil end,
  read = function(_, rel) return files[rel] end,
}
local ph = Placeholders.run(rom, cache, {})
eq(ph.VERSION, "EMERALD", "placeholder VERSION")
eq(ph.AQUA, "AQUA", "placeholder AQUA")
eq(ph.MAGMA, "MAGMA", "placeholder MAGMA")
eq(ph.ARCHIE, "ARCHIE", "placeholder ARCHIE")
eq(ph.MAXIE, "MAXIE", "placeholder MAXIE")
eq(ph.KYOGRE, "KYOGRE", "placeholder KYOGRE")
eq(ph.GROUDON, "GROUDON", "placeholder GROUDON")
eq(ph.byGender.RIVAL.male, "MAY", "rival placeholder for a male player")
eq(ph.byGender.RIVAL.female, "BRENDAN", "rival placeholder for a female player")
local src = files["data/generated/gba/text/placeholders.lua"]
check(src ~= nil, "placeholders.lua written")
local loaded = src and load(src, "placeholders", "t", {})()
eq(loaded and loaded.KYOGRE, "KYOGRE", "placeholders.lua round trips")
local ir = TextIR.decode({ 0xFD, 0x07, 0x00, 0xFD, 0x0D, 0xFF }, { dialect = "rse" })
eq(TextIR.toPlain(ir, { placeholders = loaded, dialect = "rse" }), "EMERALD GROUDON",
  "FD 07 / FD 0D expand from the cached placeholders")

local Chrome = require("src.import.gba.rse.text_chrome_extract")
check(Chrome.run(rom, cache, {}), "rse text chrome extract runs")
local root = "data/generated/gba/chrome/"
local frames = 0
for i = 0, 19 do
  local d = files[root .. "user_frame_" .. i .. ".rgba"]
  if d and #d == 24 * 24 * 4 then frames = frames + 1 end
end
eq(frames, 20, "20 user_frame_N.rgba at 24x24")
eq(files[root .. "user_frame_20.rgba"], nil, "no user_frame_20")
for _, face in ipairs(Chrome.LATIN) do
  local w = load(files[root .. "fonts/" .. Chrome.WIDTH_FILES[face]], "w", "t", {})()
  local n = 0
  for k in pairs(w) do if k >= 0 then n = n + 1 end end
  eq(n, 512, face .. " width table has 512 entries")
  eq(#files[root .. "fonts/latin_" .. face .. "_fg.rgba"], 256 * 512 * 4, face .. " fg sheet size")
end
local widths = load(files[root .. "fonts/latin_widths.lua"], "w", "t", {})()
eq(widths[0xBB], 6, "normal font 'A' is 6px wide")
eq(widths[0x00], 3, "normal font space is 3px wide")
eq(#files[root .. "message_box.rgba"], 56 * 16 * 4, "message box sheet 56x16")
eq(#files[root .. "fonts/down_arrow.idx"], 8 * 48, "down arrow index map 8x48")
local metrics = load(files[root .. "fonts/metrics.lua"], "m", "t", {})()
eq(metrics[1].name, "FONT_NORMAL", "font 1 is FONT_NORMAL")
eq(metrics[1].maxLetterHeight, 16, "FONT_NORMAL maxLetterHeight")
eq(metrics[0].maxLetterHeight, 12, "FONT_SMALL maxLetterHeight")

local function pngIndices(png)
  local tmp = os.tmpname()
  local cmd = string.format(
    "python3 -c \"import sys;from PIL import Image;im=Image.open(sys.argv[1]);open(sys.argv[2],'wb').write(bytes([im.size[0]//256,im.size[0]%%256,im.size[1]//256,im.size[1]%%256])+im.tobytes())\" '%s' '%s' 2>/dev/null",
    png, tmp)
  local ok = os.execute(cmd)
  local h = io.open(tmp, "rb")
  local data = h and h:read("*a")
  if h then h:close() end
  os.remove(tmp)
  if not (ok == 0 or ok == true) or not data or #data < 4 then return nil end
  local w = data:byte(1) * 256 + data:byte(2)
  local hgt = data:byte(3) * 256 + data:byte(4)
  return data:sub(5), w, hgt
end

local PRET_FONTS = ROM_PATH:gsub("[^/]*$", "") .. "graphics/fonts/"
local idx, pw = pngIndices(PRET_FONTS .. "latin_normal.png")
if not idx then
  print("emerald_text_test: glyph pixel check skipped (python3 + PIL or pret graphics missing)")
else
  local fg = files[root .. "fonts/latin_normal_fg.rgba"]
  local sh = files[root .. "fonts/latin_normal_shadow.rgba"]
  local function sheetValue(x, y)
    local i = (y * 256 + x) * 4 + 4
    if fg:byte(i) ~= 0 then return 1 end
    if sh:byte(i) ~= 0 then return 2 end
    return 0
  end
  local function glyphMismatch(gid)
    local bad = 0
    local ox, oy = (gid % 16) * 16, math.floor(gid / 16) * 16
    for y = 0, 15 do
      for x = 0, 15 do
        local p = idx:byte((oy + y) * pw + ox + x + 1)
        local want = (p == 1 or p == 2) and p or 0
        if sheetValue(ox + x, oy + y) ~= want then bad = bad + 1 end
      end
    end
    return bad
  end
  eq(glyphMismatch(0xBB), 0, "latin_normal 'A' glyph is pixel-exact vs pret latin_normal.png")
  local total = 0
  for gid = 0, 511 do total = total + glyphMismatch(gid) end
  eq(total, 0, "all 512 latin_normal glyphs are pixel-exact vs pret latin_normal.png")
end

T.finish("emerald_text_test")
