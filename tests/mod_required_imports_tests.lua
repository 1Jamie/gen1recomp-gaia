package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Manifest = require("src.mods.Manifest")
local RequiredImports = require("src.mods.RequiredImports")
local Loader = require("src.mods.Loader")
local S = require("tests.harness").suite("required mod imports")
local check, eq = S.check, S.eq

local DIGEST = "0123456789abcdef0123456789abcdef"
local function fakeHash(data)
  return data:sub(1, 4) == "\128\55\18\64" and DIGEST
    or "ffffffffffffffffffffffffffffffff"
end

local manifest = Manifest.validate({
  id = "stadium_fx", name = "Stadium FX", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "stadium2", name = "Stadium 2", file = "stadium2.z64",
      format = "n64", md5 = { DIGEST, DIGEST:upper() } },
  },
}, "mods/stadium_fx")

eq(#manifest.required_imports, 1, "required import parses")
eq(#manifest.required_imports[1].md5, 1, "accepted MD5 values normalize and dedupe")
eq(manifest.required_imports[1].md5[1], DIGEST, "MD5 is lowercase")

local optionalManifest = Manifest.validate({
  id = "optional_fx", name = "Optional FX", version = "1.0.0", entry = "main.lua",
  optional_imports = {
    { id = "bonus", name = "Bonus ROM", file = "bonus.z64",
      format = "n64", md5 = DIGEST },
  },
}, "mods/optional_fx")
eq(#optionalManifest.optional_imports, 1, "optional import parses")
eq(optionalManifest.optional_imports[1].required, false,
  "optional import is marked non-blocking")
local optionalRows, optionalMissing, missingOptional =
  RequiredImports.inspect(optionalManifest, love.filesystem, fakeHash)
eq(optionalMissing, 0, "missing optional import is not required")
eq(missingOptional, 1, "missing optional import is reported separately")
check(not optionalRows[1].required, "optional row is labeled optional")

check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  required_imports = { { id = "rom", file = "../outside.z64", md5 = DIGEST } },
}), "required import cannot escape baseroms")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  required_imports = { { id = "rom", file = "rom.z64", md5 = "short" } },
}), "malformed MD5 is refused")

local canonical = "\128\55\18\64ABCD"
local v64 = "\55\128\64\18BADC"
local n64 = "\64\18\55\128DCBA"
check(RequiredImports.importData(optionalManifest, "bonus", canonical,
  { hash = fakeHash }), "optional import uses the normal validation path")
eq(RequiredImports.normalizeN64(canonical), canonical, "z64 stays canonical")
eq(RequiredImports.normalizeN64(v64), canonical, "v64 pair swap canonicalizes")
eq(RequiredImports.normalizeN64(n64), canonical, "n64 word swap canonicalizes")
eq(RequiredImports.normalizeN64(string.rep("H", 512) .. v64), canonical,
  "recognized 512-byte copier header is stripped")
check(RequiredImports.normalizeN64(string.rep("H", 520)) == nil,
  "an arbitrary 512-byte prefix is not treated as a copier header")

local ok, digest = RequiredImports.importData(manifest, "stadium2", v64,
  { hash = fakeHash })
check(ok, "validated bytes import")
eq(digest, DIGEST, "import reports canonical digest")
eq(love.filesystem.read("mods/stadium_fx/baseroms/stadium2.z64"), canonical,
  "import writes canonical bytes inside the mod")
local rows, missing = RequiredImports.inspect(manifest, love.filesystem, fakeHash)
eq(missing, 0, "written import satisfies its declaration")
check(rows[1].present, "inspection reports ready")

local target = Manifest.validate({
  id = "other_fx", name = "Other FX", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "same_rom", file = "source.z64", format = "n64", md5 = DIGEST },
  },
}, "mods/other_fx")
local copied = RequiredImports.reconcile({ manifest, target }, love.filesystem, fakeHash)
eq(#copied, 1, "matching installed import is reused")
eq(love.filesystem.read("mods/other_fx/baseroms/source.z64"), canonical,
  "reuse creates a private per-mod copy")
check(RequiredImports.remove(target, "same_rom"), "a required import can be removed")
eq(love.filesystem.read("mods/other_fx/baseroms/source.z64"), nil,
  "remove deletes this mod's private copy")
local copiedAfterRemove = RequiredImports.reconcile({ manifest, target },
  love.filesystem, fakeHash)
eq(#copiedAfterRemove, 0,
  "an explicit removal is not immediately undone by automatic reuse")
check(RequiredImports.importData(target, "same_rom", canonical, { hash = fakeHash }),
  "choosing the file again clears the removal decision")

local legacy = Manifest.validate({
  id = "legacy", name = "Legacy", version = "1.0.0", entry = "main.lua",
}, "mods/legacy")
local legacyTarget = Manifest.validate({
  id = "legacy_user", name = "Legacy User", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "rom", file = "legacy-source.z64", format = "n64", md5 = DIGEST },
  },
}, "mods/legacy_user")
love.filesystem.write("mods/legacy/baseroms/manually-imported.v64", v64)
local legacyCopied = RequiredImports.reconcile({ legacy, legacyTarget },
  love.filesystem, fakeHash)
eq(#legacyCopied, 1, "an undeclared legacy baserom can satisfy a new declaration")
eq(love.filesystem.read("mods/legacy_user/baseroms/legacy-source.z64"), canonical,
  "legacy reuse still stores canonical bytes")

local rejected, why = RequiredImports.importData(target, "same_rom", "wrong",
  { hash = fakeHash })
eq(rejected, nil, "mismatched selection is rejected")
check(tostring(why):find("Nintendo 64", 1, true) ~= nil,
  "normalization failure explains the selected format")

love.filesystem.write("mods/launcher_needs/manifest.json", ([[{
  "id":"launcher_needs","name":"Launcher Needs","version":"1.0.0",
  "entry":"main.lua","required_imports":[{"id":"source","name":"Source ROM",
  "file":"source.bin","md5":"%s"}]
}]]):format(DIGEST))
love.filesystem.write("mods/launcher_needs/main.lua", "return function(mod) end")
local launcherRows = require("src.mods.LauncherMods").list()
eq(#launcherRows, 1, "launcher keeps a mod with a missing required import visible")
eq(launcherRows[1].missingRequiredImports, 1,
  "launcher row carries the missing import count")
eq(launcherRows[1].status, "needs_import",
  "missing import changes Ready to Import required")
check(launcherRows[1].statusDetail:find("Source ROM", 1, true) ~= nil,
  "launcher warning names the missing file")

local function memfs(files)
  return {
    read = function(path) return files[path] end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
    end,
    getDirectoryItems = function(path)
      if path == "mods" then
        local out, seen = {}, {}
        for key in pairs(files) do
          local id = key:match("^mods/([^/]+)/manifest%.json$")
          if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
        table.sort(out)
        return out
      end
      return {}
    end,
    load = function(path)
      local source = files[path]
      if not source then return nil, "missing" end
      return load(source, path)
    end,
  }
end

local manifestJson = ([[{
  "id":"needs_rom","name":"Needs ROM","version":"1.0.0","entry":"main.lua",
  "required_imports":[{"id":"rom","name":"Source ROM","file":"source.bin",
  "md5":"%s"}]
}]]):format(DIGEST)
local loader = Loader.new({ fs = memfs({
  ["mods/needs_rom/manifest.json"] = manifestJson,
  ["mods/needs_rom/main.lua"] = "return function(mod) mod.exports.ran = true end",
}) })
check(loader:load({}) == false, "missing required import blocks the enabled mod")
local status = loader:status().available[1]
eq(status.state, "invalid", "blocked mod reports invalid")
check(status.error:find("Source ROM", 1, true) ~= nil,
  "loader failure names the required import")
check(not (loader.exports.needs_rom and loader.exports.needs_rom.ran),
  "blocked mod entry never executes")

local optionalJson = ([[{
  "id":"optional_rom","name":"Optional ROM","version":"1.0.0","entry":"main.lua",
  "optional_imports":[{"id":"rom","name":"Bonus ROM","file":"bonus.bin",
  "md5":"%s"}]
}]]):format(DIGEST)
local optionalLoader = Loader.new({ fs = memfs({
  ["mods/optional_rom/manifest.json"] = optionalJson,
  ["mods/optional_rom/main.lua"] = "return function(mod) mod.exports.ran = true end",
}) })
check(optionalLoader:load({}), "missing optional import does not block the mod")
check(optionalLoader.exports.optional_rom.ran,
  "mod entry executes without its optional import")

S.finish()
