return {
  tasks = {
    {
      id = "ui_wild",
      run = "steps",
      weight = 0.02,
      steps = {
        { name = "encounters_extract", label = "Wild Encounters" },
      },
    },
    {
      id = "ui_places",
      run = "steps",
      weight = 0.02,
      steps = {
        { name = "src.import.gba.rse.map_sections_extract", label = "Map Sections" },
        { name = "heal_locations_extract", opts = { strict = true }, label = "Heal Locations" },
        { name = "multichoice_extract", label = "Dialog Menus" },
      },
    },
  },
  sequential = { "ui_wild", "ui_places" },
  dirs = { "/region_map", "/scripts", "/chrome/map_popup" },
}
