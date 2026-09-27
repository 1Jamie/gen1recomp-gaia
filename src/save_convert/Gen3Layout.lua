local L = require("src.save_convert.gen3_layouts.frlg")

local FAMILIES = { frlg = "src.save_convert.gen3_layouts.frlg", emerald = "src.save_convert.gen3_layouts.emerald" }

function L.family(name)
  local path = FAMILIES[name]
  if not path then error("gen3 save layout: no family " .. tostring(name), 2) end
  return require(path)
end

function L.familyOf(version)
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.layout and GameVersion.layout(version) == "rse" then return version end
  return "frlg"
end

function L.forVersion(version)
  return L.family(L.familyOf(version))
end

return L
