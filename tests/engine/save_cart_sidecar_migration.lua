package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")
local G2 = require("tests.fixtures.save.gen2_build")
local K = require("tests.save_compat._codec")

local realFS = love.filesystem

local function fresh(version)
  local files = {}
  love.filesystem = {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
  SaveData.resetSlotState()
  GameVersion.set(version)
  return files
end

local function slotOf(version, slotId)
  return SaveSerializer.decode(SaveData.readSlotSource(version, slotId) or "")
end

local function exportOf(files, version, slotId)
  return files[("exports/%s/gen1recomp-%s-%s.sav"):format(version, version, tostring(slotId))]
end

SaveConvert.setGen2DataStub(K.gen2Data)

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local cart = G2.build({ version = version, player = "ASH" }) .. string.rep("\1", 18)
  local sidecar = ("saves/%s/%%s.cart"):format(version)

  local files = fresh(version)
  files["picked.sav"] = cart
  local ok, slotId = SaveFileIO.importToSlot("picked.sav", version)
  eq(ok, true, version .. " fresh: the cart imports -- " .. tostring(slotId))
  local path = sidecar:format(tostring(slotId))
  eq(files[path], nil, version .. " fresh: no sidecar is written")
  eq(slotOf(version, slotId).rawImport, cart, version .. " fresh: the slot embeds the cart image")
  local exOk, exWhy = SaveFileIO.exportActiveSlot(version)
  eq(exOk ~= false, true, version .. " fresh: the slot exports without a sidecar -- " .. tostring(exWhy))
  eq(exportOf(files, version, slotId), cart, version .. " fresh: the export is the imported cart byte for byte")

  files = fresh(version)
  files["picked.sav"] = cart
  ok, slotId = SaveFileIO.importToSlot("picked.sav", version)
  path = sidecar:format(tostring(slotId))
  local legacy = slotOf(version, slotId)
  legacy.rawImport = nil
  eq(SaveData.writeSlot(version, slotId, legacy), true, version .. " legacy: a slot written before the image was embedded")
  files[path] = cart
  exOk, exWhy = SaveFileIO.exportActiveSlot(version)
  eq(exOk ~= false, true, version .. " legacy: the export still works -- " .. tostring(exWhy))
  eq(exportOf(files, version, slotId), cart, version .. " legacy: and is built on the old sidecar image")
  eq(files[path], nil, version .. " legacy: the sidecar is deleted once folded in")
  eq(slotOf(version, slotId).rawImport, cart, version .. " legacy: the slot now embeds the image")

  files = fresh(version)
  files["picked.sav"] = cart
  ok, slotId = SaveFileIO.importToSlot("picked.sav", version)
  path = sidecar:format(tostring(slotId))
  local other = G2.build({ version = version, player = "RED" })
  files[path] = other
  exOk, exWhy = SaveFileIO.exportActiveSlot(version)
  eq(exOk ~= false, true, version .. " both: the export works -- " .. tostring(exWhy))
  eq(exportOf(files, version, slotId), cart, version .. " both: the in-slot image wins over the sidecar")
  eq(files[path], nil, version .. " both: the sidecar is deleted")
  eq(slotOf(version, slotId).rawImport, cart, version .. " both: the slot image is untouched")
end

do
  local B = require("tests.fixtures.save.bytes")
  local files = fresh("gold")
  local L = G2.layout("gold")
  local b = B.fromString(G2.build({ version = "gold" }))
  b[L.sGameData + 20] = (b[L.sGameData + 20] + 1) % 256
  files["picked.sav"] = B.pack(b)
  local ok, slotId, info = SaveFileIO.importToSlot("picked.sav", "gold")
  eq(ok, true, "a corrupt primary still imports -- " .. tostring(slotId))
  check(info and type(info.note) == "string" and info.note:find("backup", 1, true) ~= nil,
    "and the launcher gets a note about the backup copy")
  files["picked.sav"] = G2.build({ version = "gold" })
  ok, slotId, info = SaveFileIO.importToSlot("picked.sav", "gold")
  eq(info, nil, "a healthy cart gets no note")
end

do
  local files = fresh("gold")
  files["picked.sav"] = G2.build({ version = "gold", lowByteZero = true })
  local ok, slotId = SaveFileIO.importToSlot("picked.sav", "gold")
  eq(ok, true, "a zero low-byte checksum cart imports -- " .. tostring(slotId))
  local exported, path, note = SaveFileIO.exportActiveSlot("gold")
  eq(exported, true, "an unchanged zero low-byte checksum cart exports -- " .. tostring(path))
  check(type(note) == "string" and note:find("gen2.openhomeChecksum", 1, true),
    "the launcher receives the reader warning after successful export")
end
SaveConvert.setGen2DataStub(nil)

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end
local FR = unrle(require("tests.fixture_data.gen3_saves").images.fr_rich_game)
local EM = unrle(require("tests.fixture_data.gen3_saves_emerald").images.em_fresh)

for _, case in ipairs({ { "firered", FR }, { "emerald", EM } }) do
  local version, cart = case[1], case[2]
  local sidecar = ("saves/%s/%%s.cart"):format(version)

  local files = fresh(version)
  files["picked.sav"] = cart
  local ok, slotId = SaveFileIO.importToSlot("picked.sav", version)
  eq(ok, true, version .. " fresh: the cart imports -- " .. tostring(slotId))
  local path = sidecar:format(tostring(slotId))
  eq(files[path], nil, version .. " fresh: no sidecar is written")
  local slot = slotOf(version, slotId)
  check(type(slot.modData) == "table" and type(slot.modData.cartImage) == "string",
    version .. " fresh: the slot embeds the cart image")
  eq(SaveFileIO.migrateLegacyCart(version, slotId, slot), nil, version .. " fresh: nothing to migrate")

  local stamped = slot.modData.cartImage
  slot.modData.cartImage, slot.modData.cartKey, slot.modData.cartGame = nil, nil, nil
  eq(SaveData.writeSlot(version, slotId, slot), true, version .. " legacy: a slot written before the image was embedded")
  files[path] = cart
  slot = slotOf(version, slotId)
  eq(SaveFileIO.migrateLegacyCart(version, slotId, slot), "folded", version .. " legacy: the sidecar is folded in")
  eq(files[path], nil, version .. " legacy: and deleted")
  eq(slotOf(version, slotId).modData.cartImage, stamped, version .. " legacy: the slot holds the same image import embeds")

  files[path] = cart
  slot = slotOf(version, slotId)
  eq(SaveFileIO.migrateLegacyCart(version, slotId, slot), "dropped", version .. " both: the in-slot image wins")
  eq(files[path], nil, version .. " both: the sidecar is deleted")
  eq(slotOf(version, slotId).modData.cartImage, stamped, version .. " both: the slot image is untouched")

  slot = slotOf(version, slotId)
  slot.modData.cartImage = nil
  slot.trainerId = (slot.trainerId + 1) % 65536
  files[path] = cart
  eq(SaveFileIO.migrateLegacyCart(version, slotId, slot), "dropped", version .. " stranger: another player's sidecar is dropped")
  eq(files[path], nil, version .. " stranger: and deleted")
  check(slot.modData.cartImage == nil, version .. " stranger: and never folded in")
end

love.filesystem = realFS
GameVersion.set("red")
T.finish()
