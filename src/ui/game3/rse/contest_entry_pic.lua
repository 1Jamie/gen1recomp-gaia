local EntryPic = {}

-- pokeemerald/src/contest_util.c:2589
EntryPic.LEFT, EntryPic.TOP = 10, 3

EntryPic.active = false

local function MonPic() return require("src.ui.game3.mon_pic") end

-- pokeemerald/src/contest_util.c:2577
function EntryPic.show(m)
  if EntryPic.active then return end
  local Pokemon = require("src.core.game3.pokemon")
  local species = tonumber(m.species) or 0
  local pic = Pokemon.frontPic(Pokemon.picSpecies(species, m.personality), 0,
    Pokemon.isShiny({ personality = m.personality, otId = (tonumber(m.otId) or 0) % 65536,
      otSecretId = math.floor((tonumber(m.otId) or 0) / 65536) % 65536 }), m.personality)
  local mp = MonPic()
  mp.show(species, EntryPic.LEFT, EntryPic.TOP)
  if pic and pic.image then
    mp._img, mp._w, mp._h = pic.image, pic.w or 64, pic.h or 64
  end
  EntryPic.active = true
  EntryPic.species = species
end

-- pokeemerald/src/contest_util.c:2626
function EntryPic.hide()
  if not EntryPic.active then return end
  EntryPic.active = false
  MonPic().hide()
end

function EntryPic.reset()
  EntryPic.active = false
end

return EntryPic
