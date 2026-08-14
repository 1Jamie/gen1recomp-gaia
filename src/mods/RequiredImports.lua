-- Engine-owned import handling for files declared by a mod's required or
-- optional import arrays. Mods never receive host paths or broader
-- filesystem access: accepted bytes are copied into their own
-- mods/<id>/baseroms/ tree, where the existing mod:read sandbox can see them.

local CacheFs = require("src.import.CacheFs")

local RequiredImports = {}

local function allSpecs(manifest)
  local out = {}
  for _, spec in ipairs((manifest and manifest.required_imports) or {}) do
    out[#out + 1] = spec
  end
  for _, spec in ipairs((manifest and manifest.optional_imports) or {}) do
    out[#out + 1] = spec
  end
  return out
end

local function isRequired(spec)
  return spec.required ~= false
end

RequiredImports.specs = allSpecs

local N64_MAGIC = {
  ["\128\55\18\64"] = "z64", -- big endian / canonical
  ["\55\128\64\18"] = "v64", -- byte-swapped
  ["\64\18\55\128"] = "n64", -- little endian words
}

local function n64KindAt(data, offset)
  return N64_MAGIC[data:sub(offset, offset + 3)]
end

-- Return canonical big-endian N64 bytes.  A 512-byte copier header is
-- recognized only when valid N64 magic follows it, so arbitrary data is never
-- shortened just because its size happens to line up.
function RequiredImports.normalizeN64(data)
  if type(data) ~= "string" then return nil, "selected file could not be read" end
  local offset, kind = 1, n64KindAt(data, 1)
  if not kind then
    kind = n64KindAt(data, 513)
    if kind then offset = 513 end
  end
  if not kind then return nil, "not a recognized Nintendo 64 ROM" end
  data = data:sub(offset)
  if kind == "z64" then return data end

  if kind == "v64" then
    if #data % 2 ~= 0 then return nil, "byte-swapped N64 ROM has an odd size" end
    return (data:gsub("(.)(.)", "%2%1"))
  else
    if #data % 4 ~= 0 then return nil, "little-endian N64 ROM size is not word aligned" end
    return (data:gsub("(.)(.)(.)(.)", "%4%3%2%1"))
  end
end

function RequiredImports.normalize(spec, data)
  if spec and spec.format == "n64" then
    return RequiredImports.normalizeN64(data)
  end
  if type(data) ~= "string" then return nil, "selected file could not be read" end
  return data
end

local function hexDigest(data, hashFn)
  if hashFn then return hashFn(data):lower() end
  if not (love and love.data and love.data.hash and love.data.encode) then
    return nil, "MD5 support is unavailable in this build"
  end
  local digest = love.data.hash("md5", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest):lower()
end

local function accepts(spec, digest)
  for _, wanted in ipairs((spec and spec.md5) or {}) do
    if wanted == digest then return true end
  end
  return false
end

function RequiredImports.path(manifest, spec)
  return manifest.path .. "/baseroms/" .. spec.file
end

local function removedMarker(manifest, spec)
  return manifest.path .. "/baseroms/." .. spec.id .. ".removed"
end

-- Validate bytes against a declaration.  The returned data is canonicalized
-- (notably for N64 byte order/header variants) and is what must be stored.
function RequiredImports.validateData(spec, data, hashFn)
  local normalized, normalizeErr = RequiredImports.normalize(spec, data)
  if not normalized then return nil, normalizeErr end
  local digest, hashErr = hexDigest(normalized, hashFn)
  if not digest then return nil, hashErr end
  if not accepts(spec, digest) then
    return nil, ("MD5 mismatch (got %s)"):format(digest)
  end
  return normalized, digest
end

function RequiredImports.validateStoredData(spec, data, hashFn)
  local normalized, detail = RequiredImports.validateData(spec, data, hashFn)
  if not normalized then return nil, detail end
  if normalized ~= data then
    return nil, "stored N64 ROM is not canonical; choose the source file again"
  end
  return normalized, detail
end

function RequiredImports.inspect(manifest, fs, hashFn)
  fs = fs or (love and love.filesystem)
  local rows, missing, missingOptional = {}, 0, 0
  for _, spec in ipairs(allSpecs(manifest)) do
    local path = RequiredImports.path(manifest, spec)
    local suppressed = fs and fs.getInfo
      and fs.getInfo(removedMarker(manifest, spec), "file") ~= nil
    local data = fs and fs.read and fs.read(path) or nil
    local normalized, detail
    if data then
      normalized, detail = RequiredImports.validateStoredData(spec, data, hashFn)
    end
    local row = { id = spec.id, name = spec.name, file = spec.file,
      format = spec.format, path = path, present = normalized ~= nil,
      digest = normalized and detail or nil,
      error = data and not normalized and detail or nil,
      suppressed = suppressed, required = isRequired(spec), spec = spec }
    if not row.present then
      if row.required then missing = missing + 1
      else missingOptional = missingOptional + 1 end
    end
    rows[#rows + 1] = row
  end
  return rows, missing, missingOptional
end

function RequiredImports.importData(manifest, importId, data, opts)
  opts = opts or {}
  local spec
  for _, candidate in ipairs(allSpecs(manifest)) do
    if candidate.id == importId then spec = candidate break end
  end
  if not spec then return nil, "unknown required import: " .. tostring(importId) end
  local normalized, digest = RequiredImports.validateData(spec, data, opts.hash)
  if not normalized then return nil, digest end
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = ""
  local ok, err = CacheFs.write(RequiredImports.path(manifest, spec), normalized)
  if ok then CacheFs.remove(removedMarker(manifest, spec)) end
  CacheFs.prefix = savedPrefix
  if not ok then return nil, "could not copy import: " .. tostring(err) end
  return true, digest
end

function RequiredImports.remove(manifest, importId)
  for _, spec in ipairs(allSpecs(manifest)) do
    if spec.id == importId then
      local savedPrefix = CacheFs.prefix
      CacheFs.prefix = ""
      CacheFs.remove(RequiredImports.path(manifest, spec))
      local marked, markErr = CacheFs.write(removedMarker(manifest, spec), "removed\n")
      CacheFs.prefix = savedPrefix
      if not marked then return nil, "could not remember removal: " .. tostring(markErr) end
      return true
    end
  end
  return nil, "unknown required import: " .. tostring(importId)
end

-- Fill missing imports from another installed mod when its accepted canonical
-- MD5 overlaps.  The source remains inside the engine-owned mods tree, and a
-- fresh validation is performed before every copy.
function RequiredImports.reconcile(manifests, fs, hashFn)
  fs = fs or (love and love.filesystem)
  if not (fs and fs.read) then return {}, {} end
  local available, state, declaredPaths = {}, {}, {}
  for _, manifest in ipairs(manifests or {}) do
    local rows, missing, missingOptional = {}, 0, 0
    for _, spec in ipairs(allSpecs(manifest)) do
      local path = RequiredImports.path(manifest, spec)
      declaredPaths[path] = true
      local data = fs.read(path)
      local suppressed = fs.getInfo
        and fs.getInfo(removedMarker(manifest, spec), "file") ~= nil
      local normalized, detail
      if data then
        normalized, detail = RequiredImports.validateStoredData(spec, data, hashFn)
        if normalized then available[detail] = normalized end
      end
      local row = { id = spec.id, name = spec.name, file = spec.file,
        format = spec.format, path = path, present = normalized ~= nil,
        digest = normalized and detail or nil,
        error = data and not normalized and detail or nil,
        suppressed = suppressed, required = isRequired(spec), spec = spec }
      if not row.present then
        if row.required then missing = missing + 1
        else missingOptional = missingOptional + 1 end
      end
      rows[#rows + 1] = row
    end
    state[manifest.id] = { rows = rows, missing = missing,
      missingOptional = missingOptional }
  end


  -- Compatibility with mods that already maintained their own baseroms
  -- folder before this manifest field existed: index every other file in an
  -- installed mod's folder by both raw and (when recognizable) canonical N64
  -- MD5. Nothing outside the engine-owned mods tree is searched.
  if fs.getDirectoryItems and fs.getInfo then
    for _, manifest in ipairs(manifests or {}) do
      local dir = manifest.path .. "/baseroms"
      if fs.getInfo(dir, "directory") then
        for _, name in ipairs(fs.getDirectoryItems(dir) or {}) do
          local path = dir .. "/" .. name
          if name:sub(1, 1) ~= "." and not declaredPaths[path]
              and fs.getInfo(path, "file") then
            local data = fs.read(path)
            if data then
              local rawDigest = hexDigest(data, hashFn)
              if rawDigest then available[rawDigest] = data end
              local canonical = RequiredImports.normalizeN64(data)
              if canonical then
                local canonicalDigest = hexDigest(canonical, hashFn)
                if canonicalDigest then available[canonicalDigest] = canonical end
              end
            end
          end
        end
      end
    end
  end

  local copied = {}
  for _, manifest in ipairs(manifests or {}) do
    local entry = state[manifest.id]
    for _, row in ipairs(entry.rows) do
      if not row.present and not row.suppressed then
        for _, digest in ipairs(row.spec.md5) do
          local data = available[digest]
          if data then
            local ok = RequiredImports.importData(manifest, row.id, data,
              { hash = hashFn })
            if ok then
              copied[#copied + 1] = { mod = manifest.id, import = row.id,
                digest = digest }
              row.present, row.digest, row.error = true, digest, nil
              if row.required then entry.missing = entry.missing - 1
              else entry.missingOptional = entry.missingOptional - 1 end
            end
            break
          end
        end
      end
    end
  end
  return copied, state
end

return RequiredImports
