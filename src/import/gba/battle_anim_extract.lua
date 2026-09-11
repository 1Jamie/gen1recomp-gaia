-- ROM-native GBA battle anim extraction.
-- Decodes bytecode scripts from gBattleAnims_Moves and subroutines.
-- createsprite: reads SpriteTemplate.tileTag from the embedded ROM pointer → true tag.
-- Sprite sheets: decompressed from gBattleAnimPicTable + gBattleAnimPaletteTable → PNG.
-- Writes: {cacheRoot}/pokemon/battle_anims/pack.lua  +  tags/*.png

local Versions  = require("src.import.gba.versions")
local Lz77      = require("src.import.gba.lz77")

local BattleAnimExtract = {}

BattleAnimExtract.FORMAT_VERSION = 3
BattleAnimExtract.CACHE_SUB      = "pokemon/battle_anims"

local V = Versions.BATTLE_ANIMS or {}

-- ── opcode sizes (total bytes incl. opcode byte) for fixed-width opcodes ──
-- Variable-width: 0x02 createsprite, 0x03 createvisualtask, 0x1F createsoundtask
local OP_FIXED = {
  [0x00]=3,[0x01]=3,                -- loadspritegfx / unloadspritegfx
  [0x04]=2,[0x05]=1,[0x06]=1,[0x07]=1,[0x08]=1, -- delay/waitforvisualfinish/nop/nop2/end
  [0x09]=3,                          -- playse
  [0x0A]=2,[0x0B]=2,                 -- monbg / clearmonbg
  [0x0C]=3,                          -- setalpha
  [0x0D]=1,                          -- blendoff
  [0x0E]=5,                          -- call
  [0x0F]=1,                          -- return
  [0x10]=4,                          -- setarg
  [0x11]=9,                          -- choosetwoturnanim
  [0x12]=6,                          -- jumpifmoveturn
  [0x13]=5,                          -- goto
  [0x14]=2,[0x15]=1,[0x16]=1,[0x17]=1,[0x18]=2, -- fadetobg/restorebg/waitbgfadeout/waitbgfadein/changebg
  [0x19]=4,                          -- playsewithpan
  [0x1A]=2,                          -- setpan
  [0x1B]=8,                          -- panse
  [0x1C]=6,                          -- loopsewithpan
  [0x1D]=5,                          -- waitplaysewithpan
  [0x1E]=3,                          -- setbldcnt
  [0x20]=1,                          -- waitsound
  [0x21]=8,                          -- jumpargeq
  [0x22]=2,[0x23]=2,                 -- monbg_static / clearmonbg_static
  [0x24]=5,                          -- jumpifcontest
  [0x25]=4,                          -- fadetobgfromset
  [0x26]=8,[0x27]=8,                 -- panse_adjustnone / panse_adjustall
  [0x28]=2,[0x29]=1,[0x2A]=2,        -- splitbgprio / splitbgprio_all / splitbgprio_foes
  [0x2B]=2,[0x2C]=2,                 -- invisible / visible
  [0x2D]=2,[0x2E]=2,[0x2F]=1,        -- teamattack_moveback / movefwd / stopsound
}

local SPRITES_START = V.sprites_start or 10000
local TAG_NAMES     = Versions.ANIM_TAG_NAMES or {}

local BATTLER_NAMES = { [0]="attacker", [1]="target", [2]="atk_partner", [3]="def_partner" }

-- Signed-extend 8-bit (for pan values stored as s8).
local function s8(v)
  if v >= 128 then return v - 256 end
  return v
end

-- Signed-extend 16-bit (for arg values stored as s16).
local function s16(v)
  if v >= 32768 then return v - 65536 end
  return v
end

--- Decode one battle anim bytecode script beginning at file offset `startOff`.
-- @param rom   Rom instance
-- @param startOff  0-based ROM file offset of first opcode byte
-- @param visited   table of offsets already decoded (avoid infinite loops across goto chains)
-- @param labels    table: ROM-offset-string → script IR list (filled in-place for call/goto targets)
-- @return list of IR op tables
local function decode_script(rom, startOff, visited, labels, tag_dims)
  if visited[startOff] then
    return labels[tostring(startOff)] or {}
  end
  visited[startOff] = true

  local ops = {}
  labels[tostring(startOff)] = ops

  local i = startOff
  local guard = 0
  while guard < 512 do
    guard = guard + 1
    if i >= rom.size then break end

    local op = rom:get(i)

    if op == 0x08 then  -- end
      ops[#ops + 1] = { op = "end" }
      break

    elseif op == 0x00 then  -- loadspritegfx
      local tag_id  = rom:u16(i + 1)
      local tag_idx = tag_id - SPRITES_START
      local name    = TAG_NAMES[tag_idx] or ("TAG_" .. tag_idx)
      ops[#ops + 1] = { op = "loadspritegfx", tag = name, tag_idx = tag_idx }
      i = i + 3

    elseif op == 0x01 then  -- unloadspritegfx
      local tag_id  = rom:u16(i + 1)
      local tag_idx = tag_id - SPRITES_START
      local name    = TAG_NAMES[tag_idx] or ("TAG_" .. tag_idx)
      ops[#ops + 1] = { op = "unloadspritegfx", tag = name }
      i = i + 3

    elseif op == 0x02 then  -- createsprite
      local tmpl_gba = rom:u32(i + 1)
      local tmpl_off = rom:ptrOffset(tmpl_gba)
      -- SpriteTemplate layout: tileTag(u16)+paletteTag(u16)+oam*(u32)+anims*(u32)+images*(u32)+affineAnims*(u32)+callback*(u32) = 24 bytes
      local tile_id   = tmpl_off and rom:u16(tmpl_off)     or 0
      local tile_idx  = tile_id - SPRITES_START
      local tag_name  = (tile_id >= SPRITES_START) and (TAG_NAMES[tile_idx] or ("TAG_" .. tile_idx)) or nil
      local noGfx     = (tile_id < SPRITES_START)  -- tileTag = 0 means TAG_NONE → no gfx

      -- OAM dimensions from SpriteTemplate.oam pointer
      local w, h = 32, 32
      if tmpl_off then
        local oam_gba = rom:u32(tmpl_off + 4)
        local oam_off = rom:ptrOffset(oam_gba)
        if oam_off then
          -- OAM struct: 4 bytes total. shape=bits[15:14] of u16[0], size=bits[15:14] of u16[1]
          local h0 = rom:u16(oam_off)
          local h1 = rom:u16(oam_off + 2)
          local shape = math.floor(h0 / 0x4000) % 4  -- bits [15:14]
          local size  = math.floor(h1 / 0x4000) % 4  -- bits [15:14]
          local DIMS = {  -- {w,h} indexed by [shape][size]
            [0]={{8,8},{16,16},{32,32},{64,64}},  -- square
            [1]={{16,8},{32,8},{32,16},{64,32}},  -- wide
            [2]={{8,16},{8,32},{16,32},{32,64}},  -- tall
          }
          local row = DIMS[shape]
          if row and row[size + 1] then
            w, h = row[size + 1][1], row[size + 1][2]
          end
        end
      end

      local cb_gba = tmpl_off and rom:u32(tmpl_off + 20) or 0
      local cb_name = Versions.ANIM_CALLBACK_NAMES and Versions.ANIM_CALLBACK_NAMES[cb_gba]

      if tag_name and tag_dims and not tag_dims[tag_name] then
        tag_dims[tag_name] = { w = w, h = h }
      end

      local battler_byte = rom:get(i + 5)
      local is_target    = (battler_byte >= 0x80)
      local subpri       = battler_byte % 0x80
      local argc         = rom:get(i + 6)
      local args = {}
      for ai = 0, argc - 1 do
        args[ai + 1] = s16(rom:u16(i + 7 + ai * 2))
      end

      local battler = is_target and "target" or "attacker"

      ops[#ops + 1] = {
        op           = "createsprite",
        tag          = tag_name,
        callback     = cb_name,
        noGfx        = noGfx or nil,
        w            = w,
        h            = h,
        animBattler  = battler,
        subpriority  = subpri,
        args         = args,
      }
      i = i + 7 + argc * 2

    elseif op == 0x03 then  -- createvisualtask
      local fn_gba = rom:u32(i + 1)
      local pri    = rom:get(i + 5)
      local argc   = rom:get(i + 6)
      local args   = {}
      for ai = 0, argc - 1 do
        args[ai + 1] = s16(rom:u16(i + 7 + ai * 2))
      end
      local task_name = Versions.ANIM_TASK_NAMES and Versions.ANIM_TASK_NAMES[fn_gba]
      ops[#ops + 1] = {
        op       = "createvisualtask",
        task     = task_name or string.format("0x%08X", fn_gba),
        priority = pri,
        args     = args,
      }
      i = i + 7 + argc * 2

    elseif op == 0x04 then  -- delay
      ops[#ops + 1] = { op = "delay", frames = rom:get(i + 1) }
      i = i + 2

    elseif op == 0x05 then  -- waitforvisualfinish
      ops[#ops + 1] = { op = "waitforvisualfinish" }
      i = i + 1

    elseif op == 0x09 then  -- playse
      local se = rom:u16(i + 1)
      ops[#ops + 1] = { op = "playse", se = se }
      i = i + 3

    elseif op == 0x0A then  -- monbg
      local b = rom:get(i + 1)
      ops[#ops + 1] = { op = "monbg", battler = BATTLER_NAMES[b] or "target" }
      i = i + 2

    elseif op == 0x0B then  -- clearmonbg
      local b = rom:get(i + 1)
      ops[#ops + 1] = { op = "clearmonbg", battler = BATTLER_NAMES[b] or "target" }
      i = i + 2

    elseif op == 0x0C then  -- setalpha
      local v  = rom:u16(i + 1)
      local eva = v % 256
      local evb = math.floor(v / 256) % 256
      ops[#ops + 1] = { op = "setalpha", eva = eva, evb = evb }
      i = i + 3

    elseif op == 0x0D then  -- blendoff
      ops[#ops + 1] = { op = "blendoff" }
      i = i + 1

    elseif op == 0x0E then  -- call
      local target_gba = rom:u32(i + 1)
      local target_off = rom:ptrOffset(target_gba)
      ops[#ops + 1] = { op = "call", label = tostring(target_off) }
      i = i + 5
      -- Eagerly decode target if not yet visited
      if target_off and not visited[target_off] then
        decode_script(rom, target_off, visited, labels, tag_dims)
      end

    elseif op == 0x0F then  -- return
      ops[#ops + 1] = { op = "return" }
      break

    elseif op == 0x10 then  -- setarg
      local argId = rom:get(i + 1)
      local val   = s16(rom:u16(i + 2))
      ops[#ops + 1] = { op = "setarg", argId = argId, value = val }
      i = i + 4

    elseif op == 0x13 then  -- goto
      local target_gba = rom:u32(i + 1)
      local target_off = rom:ptrOffset(target_gba)
      ops[#ops + 1] = { op = "goto", label = tostring(target_off) }
      -- Decode target then stop (tail-jump)
      if target_off and not visited[target_off] then
        decode_script(rom, target_off, visited, labels, tag_dims)
      end
      break

    elseif op == 0x19 then  -- playsewithpan
      local se  = rom:u16(i + 1)
      local pan = s8(rom:get(i + 3))
      ops[#ops + 1] = { op = "playsewithpan", se = se, pan = pan }
      i = i + 4

    elseif op == 0x1C then  -- loopsewithpan
      local se    = rom:u16(i + 1)
      local pan   = s8(rom:get(i + 3))
      local wait  = rom:get(i + 4)
      local times = rom:get(i + 5)
      ops[#ops + 1] = { op = "loopsewithpan", se = se, pan = pan, wait = wait, times = times }
      i = i + 6

    elseif op == 0x1D then  -- waitplaysewithpan
      local se   = rom:u16(i + 1)
      local pan  = s8(rom:get(i + 3))
      local wait = rom:get(i + 4)
      ops[#ops + 1] = { op = "waitplaysewithpan", se = se, pan = pan, wait = wait }
      i = i + 5

    elseif op == 0x1F then  -- createsoundtask (variable, like createvisualtask)
      local fn_gba = rom:u32(i + 1)
      local argc   = rom:get(i + 5)
      local args   = {}
      for ai = 0, argc - 1 do
        args[ai + 1] = s16(rom:u16(i + 6 + ai * 2))
      end
      ops[#ops + 1] = { op = "nop" }  -- treat as nop; sound handled by SE ops
      i = i + 6 + argc * 2

    elseif op == 0x2B then  -- invisible
      ops[#ops + 1] = { op = "invisible", battler = BATTLER_NAMES[rom:get(i+1)] or "attacker" }
      i = i + 2

    elseif op == 0x2C then  -- visible
      ops[#ops + 1] = { op = "visible", battler = BATTLER_NAMES[rom:get(i+1)] or "attacker" }
      i = i + 2

    else
      -- Fixed-size or unknown: step by known size, emit nop
      local sz = OP_FIXED[op] or 1
      if sz > 1 or (op >= 0x05 and op <= 0x2F) then
        ops[#ops + 1] = { op = "nop" }
      end
      i = i + sz
    end
  end

  -- Ensure scripts always terminate
  if #ops == 0 or (ops[#ops].op ~= "end" and ops[#ops].op ~= "return") then
    ops[#ops + 1] = { op = "end" }
  end
  return ops
end

-- ── Sprite sheet extraction ───────────────────────────────────────────────

--- Decode one GBA 4bpp tile (32 bytes) to 8×8 RGBA pixels into `out[1..64*4]`.
local function decode_4bpp_tile(rom_bytes, tile_off, pal, out, out_off)
  for byte_i = 0, 31 do
    local b    = rom_bytes[tile_off + byte_i + 1] or 0
    local lo   = b % 16
    local hi   = math.floor(b / 16) % 16
    local px   = out_off + byte_i * 8
    -- low nibble = left pixel (even x), high nibble = right pixel (odd x)
    local cl = pal[lo]
    local ch = pal[hi]
    out[px + 1] = cl[1]; out[px + 2] = cl[2]; out[px + 3] = cl[3]; out[px + 4] = cl[4]
    out[px + 5] = ch[1]; out[px + 6] = ch[2]; out[px + 7] = ch[3]; out[px + 8] = ch[4]
  end
end

--- Decode GBA RGB555 palette bytes (32 bytes = 16 colors) to RGBA table.
-- Color 0 is forced fully transparent (GBA OBJ convention).
local function decode_palette(pal_bytes)
  local pal = {}
  for ci = 0, 15 do
    local v = pal_bytes[ci * 2 + 1] + pal_bytes[ci * 2 + 2] * 256
    local r  = (v % 32) * 8
    local g  = math.floor(v / 32) % 32 * 8
    local b  = math.floor(v / 1024) % 32 * 8
    local a  = (ci == 0) and 0 or 255
    pal[ci]  = { r, g, b, a }
  end
  return pal
end

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

-- CRC-32 table for PNG chunk checksums
local crc_table = {}
for n = 0, 255 do
  local c = n
  for _ = 0, 7 do
    if band(c, 1) ~= 0 then
      c = bxor(0xEDB88320, rshift(c, 1))
    else
      c = rshift(c, 1)
    end
  end
  crc_table[n] = c
end

local function crc32(str)
  local c = 0xFFFFFFFF
  for i = 1, #str do
    local b = str:byte(i)
    c = bxor(crc_table[band(bxor(c, b), 0xFF)], rshift(c, 8))
  end
  return bxor(c, 0xFFFFFFFF)
end

local function adler32(str)
  local s1 = 1
  local s2 = 0
  for i = 1, #str do
    s1 = (s1 + str:byte(i)) % 65521
    s2 = (s2 + s1) % 65521
  end
  return s2 * 65536 + s1
end

local function u32be(n)
  n = band(n, 0xFFFFFFFF)
  return string.char(
    band(rshift(n, 24), 0xFF),
    band(rshift(n, 16), 0xFF),
    band(rshift(n, 8), 0xFF),
    band(n, 0xFF)
  )
end

local function u16le(n)
  return string.char(band(n, 0xFF), band(rshift(n, 8), 0xFF))
end

local function make_chunk(type_str, data)
  local crc = crc32(type_str .. data)
  return u32be(#data) .. type_str .. data .. u32be(crc)
end

--- Encode RGBA pixel array to PNG bytes (uses love.image if available, else pure Lua PNG writer).
local function encode_png(pixels, w, h)
  if love and love.image and love.graphics then
    local ok, id = pcall(love.image.newImageData, w, h)
    if ok and id then
      id:mapPixel(function(x, y)
        local base = (y * w + x) * 4 + 1
        return pixels[base] / 255, pixels[base + 1] / 255,
               pixels[base + 2] / 255, pixels[base + 3] / 255
      end)
      local ok2, fd = pcall(id.encode, id, "png")
      if ok2 and fd then return fd:getString() end
    end
  end

  -- Pure Lua PNG writer
  local raw_lines = {}
  for y = 0, h - 1 do
    local row = { string.char(0) } -- Filter type 0: None
    local start_idx = y * w * 4 + 1
    for x = 0, w - 1 do
      local idx = start_idx + x * 4
      row[#row + 1] = string.char(pixels[idx] or 0, pixels[idx+1] or 0, pixels[idx+2] or 0, pixels[idx+3] or 0)
    end
    raw_lines[#raw_lines + 1] = table.concat(row)
  end
  local raw_data = table.concat(raw_lines)

  -- Deflate uncompressed blocks (max 65535 per block)
  local zlib_blocks = { string.char(0x78, 0x01) } -- ZLIB header
  local pos = 1
  local total_len = #raw_data
  while pos <= total_len do
    local chunk_len = math.min(total_len - pos + 1, 65535)
    local is_final = (pos + chunk_len > total_len) and 1 or 0
    zlib_blocks[#zlib_blocks + 1] = string.char(is_final)
    zlib_blocks[#zlib_blocks + 1] = u16le(chunk_len)
    zlib_blocks[#zlib_blocks + 1] = u16le(bxor(chunk_len, 0xFFFF))
    zlib_blocks[#zlib_blocks + 1] = raw_data:sub(pos, pos + chunk_len - 1)
    pos = pos + chunk_len
  end
  zlib_blocks[#zlib_blocks + 1] = u32be(adler32(raw_data))
  local idat_data = table.concat(zlib_blocks)

  -- PNG Signature + IHDR + IDAT + IEND
  local sig = "\137PNG\r\n\026\n"
  local ihdr = u32be(w) .. u32be(h) .. string.char(8, 6, 0, 0, 0)
  return sig .. make_chunk("IHDR", ihdr) .. make_chunk("IDAT", idat_data) .. make_chunk("IEND", "")
end

--- Extract all sprite sheets referenced in `usedTags` from gBattleAnimPicTable.
-- @param rom        Rom instance
-- @param cache      cachefs with :write(rel, bytes)
-- @param root       cache root prefix (e.g. "data/generated/gba")
-- @param usedTags   table of tag_name → true (only extract what's actually used)
-- @param tag_dims   optional table of tag_name → { w=N, h=N } from SpriteTemplates
-- @return tags metadata table: { TAG_NAME = { file=..., w=N, h=N, frameW=..., frameH=... }, ... }
local function extract_tag_sheets(rom, cache, root, usedTags, tag_dims)
  local anim  = Versions.BATTLE_ANIMS
  local tags  = {}
  if not (anim and anim.pic_table) then return tags end

  local pic_base = anim.pic_table
  local pal_base = anim.pal_table

  for idx = 0, anim.tag_count - 1 do
    local name = TAG_NAMES[idx]
    if not name then goto continue_tag end
    if not usedTags[name] then goto continue_tag end

    -- Read pic pointer (8-byte stride: ptr at +0, size at +4)
    local pic_gba = rom:u32(pic_base + idx * 8)
    local pic_off = rom:ptrOffset(pic_gba)
    if not (pic_off and rom:get(pic_off) == 0x10) then goto continue_tag end

    -- Read pal pointer
    local pal_gba = rom:u32(pal_base + idx * 8)
    local pal_off = rom:ptrOffset(pal_gba)
    if not pal_off then goto continue_tag end

    -- Decompress tile data
    local ok_lz, tile_bytes, _ = pcall(Lz77.decompress, function(j) return rom:get(j) end, pic_off)
    if not ok_lz or not tile_bytes then goto continue_tag end

    -- Decode palette (32 bytes uncompressed, or LZ77 compressed)
    local pal_bytes
    if rom:get(pal_off) == 0x10 then
      local ok_p, pb = pcall(Lz77.decompress, function(j) return rom:get(j) end, pal_off)
      if ok_p and pb then pal_bytes = pb end
    else
      pal_bytes = {}
      for pi = 0, 31 do pal_bytes[pi + 1] = rom:get(pal_off + pi) end
    end
    if not pal_bytes then goto continue_tag end

    local pal = decode_palette(pal_bytes)

    -- tile_bytes: raw 4bpp tile data. Each tile = 32 bytes = 8×8 pixels.
    -- Tiles are arranged in columns determined by frame width.
    local total_bytes = #tile_bytes
    local tile_count  = math.floor(total_bytes / 32)
    if tile_count <= 0 then goto continue_tag end

    local frame_w = tag_dims and tag_dims[name] and tag_dims[name].w
    local frame_h = tag_dims and tag_dims[name] and tag_dims[name].h
    local best_w = frame_w and math.max(1, math.floor(frame_w / 8))
    if not best_w then
      local widths = {1, 2, 4, 8, 16}
      best_w = 4
      for _, w in ipairs(widths) do
        if w * w <= tile_count then best_w = w end
      end
    end

    local img_w = best_w * 8
    local img_h = math.ceil(tile_count / best_w) * 8
    if img_h == 0 then img_h = img_w end

    -- Decode all tiles to RGBA
    local pixels = {}
    for pi = 1, img_w * img_h * 4 do pixels[pi] = 0 end

    local tiles_wide = math.floor(img_w / 8)
    for ti = 0, tile_count - 1 do
      local tx = ti % tiles_wide
      local ty = math.floor(ti / tiles_wide)
      -- Each tile's 8 rows map to img_w-stride RGBA pixels
      for row = 0, 7 do
        local byte_base = ti * 32 + row * 4
        for col = 0, 3 do
          local b   = tile_bytes[byte_base + col + 1] or 0
          local lo  = b % 16
          local hi  = math.floor(b / 16) % 16
          local px  = ((ty * 8 + row) * img_w + tx * 8 + col * 2)
          local cl  = pal[lo]
          local ch  = pal[hi]
          local base = px * 4 + 1
          pixels[base]   = cl[1]; pixels[base+1] = cl[2]
          pixels[base+2] = cl[3]; pixels[base+3] = cl[4]
          base = base + 4
          pixels[base]   = ch[1]; pixels[base+1] = ch[2]
          pixels[base+2] = ch[3]; pixels[base+3] = ch[4]
        end
      end
    end

    local png = encode_png(pixels, img_w, img_h)
    if png and #png > 0 then
      local rel = root .. "/tags/" .. name .. ".png"
      if cache and cache.write then
        cache:write(rel, png)
      end
      tags[name] = {
        file   = "tags/" .. name .. ".png",
        w      = img_w,
        h      = img_h,
        frameW = frame_w or (best_w * 8),
        frameH = frame_h or (best_w * 8),
      }
    end

    ::continue_tag::
  end
  return tags
end

-- ── Lua serializer ────────────────────────────────────────────────────────

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil"     then return "nil" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number"  then return tostring(v) end
  if t == "string"  then return string.format("%q", v) end
  if t == "table" then
    local n, isArr, count = #v, true, 0
    for k in pairs(v) do
      count = count + 1
      if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then isArr = false end
    end
    if isArr and n > 0 then
      local parts = {"{"}
      for i = 1, n do
        parts[#parts+1] = "\n"..indent.."  "..serialize(v[i], indent.."  ")..(i < n and "," or "")
      end
      parts[#parts+1] = "\n"..indent.."}"
      return table.concat(parts)
    end
    local keys, parts = {}, {"{"}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta == tb then
        if ta == "number" then return a < b end
        return tostring(a) < tostring(b)
      end
      return ta < tb
    end)
    for _, k in ipairs(keys) do
      local key = (type(k)=="string" and k:match("^[%a_][%w_]*$")) and k or ("["..serialize(k).."]")
      parts[#parts+1] = "\n"..indent.."  "..key.." = "..serialize(v[k], indent.."  ")..(k ~= keys[#keys] and "," or "")
    end
    parts[#parts+1] = "\n"..indent.."}"
    return table.concat(parts)
  end
  return "nil"
end

-- ── Generic fallback script (used when no pack is available) ──────────────

local GENERIC = {
  { op = "loadspritegfx", tag = "IMPACT", tag_idx = 135 },
  { op = "monbg", battler = "target" },
  { op = "createsprite", tag = "IMPACT", noGfx = nil, w = 32, h = 32,
    animBattler = "attacker", subpriority = 2,
    args = { 0, 0, -1, 2 } },  -- args[3]=-1 → from HorizontalLunge noGfx template
  { op = "createsprite", tag = "IMPACT", w = 32, h = 32,
    animBattler = "attacker", subpriority = 2, args = { 0, 0, 1, 2 } },
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2,
    args = { 1, 3, 0, 6, 1 } },
  { op = "waitforvisualfinish" },
  { op = "clearmonbg", battler = "target" },
  { op = "blendoff" },
  { op = "end" },
}

-- ── Public API ────────────────────────────────────────────────────────────

function BattleAnimExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or "data/generated/gba") .. "/" .. BattleAnimExtract.CACHE_SUB
  local path = root .. "/pack.lua"
  if cache and cache.exists and cache:exists(path) then return true end
  if cache and cache.read  and cache:read(path)   then return true end
  return false
end

--- Main extraction entry point.
-- @param rom    Rom instance (required for ROM-native extraction)
-- @param cache  cache object with :write(rel, bytes) method
-- @param opts   { force=bool, cacheRoot=string, progressCb=function }
function BattleAnimExtract.run(rom, cache, opts)
  opts      = opts or {}
  local root = (opts.cacheRoot or "data/generated/gba") .. "/" .. BattleAnimExtract.CACHE_SUB

  -- Skip if already extracted and not forced
  if not opts.force and BattleAnimExtract.ready(cache, opts.cacheRoot or "data/generated/gba") then
    return {
      path        = root .. "/pack.lua",
      moveCount   = V.move_count or 355,
      tagCount    = 0,
      version     = BattleAnimExtract.FORMAT_VERSION,
      skipped     = true,
    }
  end

  local anim = Versions.BATTLE_ANIMS
  if not (rom and anim and anim.moves_table) then
    -- No ROM — write generic fallback
    local pack = {
      version  = BattleAnimExtract.FORMAT_VERSION,
      moves    = {},
      labels   = {},
      tags     = {},
    }
    for id = 0, (V.move_count or 355) - 1 do
      pack.moves[id] = GENERIC
    end
    local lua = "return " .. serialize(pack) .. "\n"
    if cache and cache.write then cache:write(root .. "/pack.lua", lua) end
    print("[battle_anim_extract] no ROM — wrote generic fallback")
    return { path = root .. "/pack.lua", moveCount = 0, tagCount = 0,
             version = BattleAnimExtract.FORMAT_VERSION }
  end

  -- ── Step 1: Decode all move scripts ──────────────────────────────────
  local visited  = {}
  local labels   = {}   -- offset-string → IR ops list
  local moves    = {}   -- [id] → IR ops list
  local usedTags = {}   -- tag_name → true
  local tagDims  = {}   -- tag_name → { w=N, h=N }

  local moves_table = anim.moves_table
  local move_count  = anim.move_count or 355

  print("[battle_anim_extract] decoding " .. move_count .. " move scripts from ROM...")
  for id = 0, move_count - 1 do
    local gba_ptr = rom:u32(moves_table + id * 4)
    local off     = rom:ptrOffset(gba_ptr)
    if off then
      local script = decode_script(rom, off, visited, labels, tagDims)
      moves[id] = script
      -- Collect used tags
      for _, op in ipairs(script) do
        if op.tag and op.tag ~= "" then
          usedTags[op.tag] = true
        end
      end
    else
      moves[id] = GENERIC
    end
  end

  -- Collect tags from all label scripts too
  for _, script in pairs(labels) do
    for _, op in ipairs(script) do
      if op.tag and op.tag ~= "" then usedTags[op.tag] = true end
    end
  end

  local tag_count = 0
  for _ in pairs(usedTags) do tag_count = tag_count + 1 end
  print(string.format("[battle_anim_extract] %d moves decoded, %d unique tags", move_count, tag_count))

  -- ── Step 2: Extract sprite sheets ───────────────────────────────────
  local tagMeta = {}
  if cache then
    print("[battle_anim_extract] extracting " .. tag_count .. " sprite sheets...")
    tagMeta = extract_tag_sheets(rom, {
      write = function(_, rel, bytes) return cache:write(rel, bytes) end,
    }, root, usedTags, tagDims)
    local extracted = 0
    for _ in pairs(tagMeta) do extracted = extracted + 1 end
    print(string.format("[battle_anim_extract] wrote %d tag PNGs", extracted))
  end

  -- ── Step 3: Serialize pack ──────────────────────────────────────────
  local pack = {
    version = BattleAnimExtract.FORMAT_VERSION,
    moves   = moves,
    labels  = labels,
    tags    = tagMeta,
  }

  local lua = "return " .. serialize(pack) .. "\n"
  if cache and cache.write then
    cache:write(root .. "/pack.lua", lua)
  elseif opts.outPath then
    local f = assert(io.open(opts.outPath, "wb"))
    f:write(lua)
    f:close()
  end

  return {
    path      = root .. "/pack.lua",
    moveCount = move_count,
    tagCount  = tag_count,
    version   = BattleAnimExtract.FORMAT_VERSION,
  }
end

return BattleAnimExtract
