return function(data, version)
  local names = { "SPRITE_CHRIS", "SPRITE_KRIS", "SPRITE_CHRIS_BIKE", "SPRITE_KRIS_BIKE", "SPRITE_SURF", "SPRITE_SURFING_PIKACHU" }
  local rows = {}
  data.sprites = {}
  for i, name in ipairs(names) do
    rows[i] = { type = 1, length = 12, palette = 0 }
    data.sprites[name] = { spriteType = "WALKING_SPRITE", paletteId = 0 }
  end
  data.constants = { spriteOrder = names, spriteContext = { version = 1, edition = version,
    capacity = version == "crystal" and 32 or 12, maxOutdoorSprites = version == "crystal" and 23 or 11,
    rows = rows, outdoorGroups = {} } }
  return data
end
