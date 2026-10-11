#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
local CartCache = require("tests.game3_cart_cache")
local CacheBlob = require("src.import.CacheBlob")
local version, root = CartCache.mountOrSkip("game3_deoxys_form_cache_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function cached(rel)
  local d = slurp(root .. "/pokemon/" .. rel)
  return d and CacheBlob.decode(root .. "/pokemon/" .. rel, d)
end

local function mask_mismatches(rgba, tiles, tileOff, w, h)
  local bad = 0
  local tw = w / 8
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local t = math.floor(y / 8) * tw + math.floor(x / 8)
      local byte = tiles:byte(tileOff + t * 32 + (y % 8) * 4 + math.floor((x % 8) / 2) + 1)
      local idx = (x % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      local a = rgba:byte((y * w + x) * 4 + 4)
      if (idx == 0) ~= (a == 0) then bad = bad + 1 end
    end
  end
  return bad
end

local PIC = 64 * 64 * 4
for _, kind in ipairs({ "front", "back", "front_shiny", "back_shiny" }) do
  local normal, handled = cached(kind .. "/410.rgba"), cached(kind .. "/410_handled.rgba")
  check(handled ~= nil and #handled == PIC, kind .. "/410_handled.rgba is a 64x64 pic")
  check(normal ~= nil and handled ~= nil and normal ~= handled, kind .. " form pic differs from Normal Forme")
end
local icon, iconHandled = cached("icons/410.rgba"), cached("icons/410_handled.rgba")
check(iconHandled ~= nil and #iconHandled == 32 * 64 * 4, "icons/410_handled.rgba is a 32x64 icon sheet")
check(icon ~= nil and iconHandled ~= nil and icon ~= iconHandled, "form icon differs from Normal Forme")

local pret = "../pokefirered/graphics/pokemon/deoxys/"
local form = version == "leafgreen" and "_def" or ""
local front, back = slurp(pret .. "front" .. form .. ".4bpp"), slurp(pret .. "back" .. form .. ".4bpp")
local formIcon = slurp(pret .. (version == "leafgreen" and "icon_defense" or "icon_attack") .. ".4bpp")
if not (front and back and formIcon) then
  print("[skip] pret pokefirered Deoxys graphics not built; pixel parity not checked")
else
  -- pokefirered/src/decompress.c:108
  check(mask_mismatches(cached("front/410_handled.rgba"), front, 2048, 64, 64) == 0,
    version .. " front pic is the second frame of gMonFrontPic_Deoxys")
  check(mask_mismatches(cached("back/410_handled.rgba"), back, 2048, 64, 64) == 0,
    version .. " back pic is the second frame of gMonBackPic_Deoxys")
  check(mask_mismatches(cached("front/410.rgba"), front, 0, 64, 64) == 0,
    "front/410.rgba stays Normal Forme")
  -- pokefirered/src/pokemon_icon.c:1112
  check(mask_mismatches(iconHandled, formIcon, 0, 32, 64) == 0, version .. " icon is the form icon")
end

local stats = cached("stats.lua")
local row = stats and stats:match("%[410%] = (%b{})")
local want = version == "leafgreen" and "atk = 70, def = 160" or "atk = 180, def = 20"
check(row ~= nil and row:find(want, 1, true) ~= nil, version .. " Deoxys base stats are sDeoxysBaseStats")

if failed > 0 then
  print(failed .. " check(s) failed")
  os.exit(1)
end
print("all checks passed (game3_deoxys_form_cache_test)")
