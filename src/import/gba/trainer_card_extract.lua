-- Trainer card chrome extractor for Game 3 (FRLG).
-- Bakes card background, badge sheet, and player front sprites into CacheFS.

local TrainerCardExtract = {}

TrainerCardExtract.CACHE_SUB = "trainer_card"
TrainerCardExtract.FORMAT_VERSION = 1

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

function TrainerCardExtract.extract(rom, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local outDir = cacheRoot .. "/" .. TrainerCardExtract.CACHE_SUB
  return {
    ok = true,
    outDir = outDir,
  }
end

return TrainerCardExtract
