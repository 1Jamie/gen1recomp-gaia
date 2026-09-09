-- Pokémon Storage System Chrome Extractor from pokefirered / FRLG assets.
-- Bakes/vendors PC storage UI textures into CacheFS (data/generated/gba/pokemon/storage/).

local Versions = require("src.import.gba.versions")

local StorageChromeExtract = {}

StorageChromeExtract.CACHE_SUB = "pokemon/storage"
StorageChromeExtract.FORMAT_VERSION = 1

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function ensure_dir(dir)
  pcall(function()
    local lfs = require("lfs")
    local current = ""
    for part in dir:gmatch("[^/]+") do
      current = current == "" and part or (current .. "/" .. part)
      lfs.mkdir(current)
    end
  end)
end

local function write_file(cache, path, data)
  if cache and cache.write then
    cache:write(path, data)
  end
  local dir = path:match("^(.*)/[^/]+$")
  if dir then
    ensure_dir(dir)
  end
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

function StorageChromeExtract.ready(cache, root)
  root = root or default_cache_root()
  local outDir = root .. "/" .. StorageChromeExtract.CACHE_SUB
  local manifestPath = outDir .. "/manifest.lua"
  if cache and cache.exists then
    return cache:exists(manifestPath)
  end
  local f = io.open(manifestPath, "rb")
  if f then f:close() return true end
  return false
end

function StorageChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  opts.cache = cache or opts.cache
  return StorageChromeExtract.extract(rom, opts)
end

function StorageChromeExtract.extract(romBytes, opts)
  opts = opts or {}
  local cache = opts.cache
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local outDir = cacheRoot .. "/" .. StorageChromeExtract.CACHE_SUB

  if not opts.force and StorageChromeExtract.ready(cache, cacheRoot) then
    return true
  end

  ensure_dir(outDir)

  local files = {
    "cursor.png",
    "cursor_shadow.png",
    "box_scroll_arrow.png",
    "menu.png",
    "scrolling_bg.png",
    "waveform.png",
    "interface_frame.png",
    "button_party.png",
    "button_close.png",
    "party_drawer_bg.png",
    "party_slot_filled.png",
    "party_slot_empty.png",
  }

  local manifest = {
    version = StorageChromeExtract.FORMAT_VERSION,
    textures = {},
  }

  for _, file in ipairs(files) do
    local srcPath = "src/import/gba/chrome/menus/storage/" .. file
    local data = read_file(srcPath) or read_file("data/generated/gba/pokemon/storage/" .. file)
    if data then
      local dstPath = outDir .. "/" .. file
      write_file(cache, dstPath, data)
      manifest.textures[file] = file
    end
  end

  local manifestSrc = string.format([[
return {
  version = %d,
  textures = {
    cursor = "cursor.png",
    cursor_shadow = "cursor_shadow.png",
    arrow = "box_scroll_arrow.png",
    menu = "menu.png",
    scrolling_bg = "scrolling_bg.png",
    waveform = "waveform.png",
    frame = "interface_frame.png",
    button_party = "button_party.png",
    button_close = "button_close.png",
    party_drawer_bg = "party_drawer_bg.png",
    party_slot_filled = "party_slot_filled.png",
    party_slot_empty = "party_slot_empty.png",
  }
}
]], StorageChromeExtract.FORMAT_VERSION)

  write_file(cache, outDir .. "/manifest.lua", manifestSrc)
  print("[game3/storage_chrome_extract] storage chrome ready (" .. outDir .. ")")
  return true
end

return StorageChromeExtract
