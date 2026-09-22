-- FireRed (Game 3) profile row. Every value below is a constant the engine
-- hardcodes today; the field's source is cited so a wiring ticket can move
-- the call site without re-deriving it.
--
-- Data only: no requires, no love, safe to load under luajit.
-- Design: docs/game3/rse-seams.md section 3.1.

return {
  id = "firered",
  label = "FireRed",
  generation = 3,
  engine = "game3",

  -- src/core/game3/map_ids.lua:5-29
  map = {
    prefixes = { "FR_", "SEVII_" }, -- MapIds.isGame3Map membership
    enginePrefix = "FR_",           -- map_catalog pret_to_engine synthesis
    legacyPrefixes = { "SEVII_" },  -- Game3.lua:384 "refuse Sevii leftovers"
    newGameStart = {
      map = "FR_PLAYERS_HOUSE_2F",
      x = 6,
      y = 6,
      facing = "down",
      healMap = "FR_PLAYERS_HOUSE_1F",
      healX = 8,
      healY = 5,
    },
  },

  -- FRLG repair rules that live in save_schema_firered.lua today; the module
  -- is created by the schema-split handoff (rse-seams T0.2).
  saveRules = "src.core.game3.profiles.firered_rules",

  -- src/core/game3/options.lua:5
  optionsBlock = "firered",

  -- src/ui/game3/frlg_font.lua:314-319 and :381-393 (CacheFs-relative paths;
  -- readActive applies the game's cachePrefix).
  font = {
    module = "src.ui.game3.frlg_font",
    widths = "data/generated/gba/chrome/fonts/latin_widths.lua",
    smallWidths = "data/generated/gba/chrome/fonts/latin_small_widths.lua",
  },

  -- pret: pokefirered/include/constants/species.h:421-423 SPECIES_EGG 412,
  -- NUM_SPECIES SPECIES_EGG; the same values in pokeemerald :418-420 and
  -- pokeruby :418,448. Engine side: versions.lua:88, pokemon.lua:510.
  species = { num = 412, egg = 412 },

  -- src/core/game3/pokedex_data.lua:111-153 and :283-286
  dexArea = {
    defaultKey = "kanto",
    mapGroups = "src.import.gba.map_groups_firered",
    dexMax = 151,
    stripPrefixes = { "FR_", "SEVII_" },
  },

  -- pret: pokefirered/include/constants/flags.h:1324 SYS_FLAGS 0x800,
  -- :1364-1371 FLAG_BADGE01_GET = SYS_FLAGS+0x20 … 08 = +0x27.
  -- Engine side: trainer_card.lua:212-213. RSE differs (pokeruby :779,789-796
  -- base 0x807; pokeemerald :1348,1359-1366 base 0x867).
  badges = {
    count = 8,
    flagBase = 0x820,
    names = {
      "BOULDER", "CASCADE", "THUNDER", "RAINBOW",
      "SOUL", "MARSH", "VOLCANO", "EARTH",
    },
  },

  -- src/core/game3/heal_locations.lua BY_ID table (20 entries)
  heal = { table = "firered" },

  -- src/core/game3/scripting/trainers.lua:11-13, :22-41, :327-364
  trainers = {
    rivalIds = { squirtle = 326, bulbasaur = 327, charmander = 328 },
    fallback = { class = 81, pic = 106, name = "TERRY" },
    music = {
      encounter = {
        -- pret TRAINER_ENCOUNTER_MUSIC_* codes -> songs 283/284/285
        girlCodes = { 1, 2, 9 },
        rocketCodes = { 3, 6, 7 },
        girl = 284, -- MUS_ENCOUNTER_GIRL
        rocket = 283, -- MUS_ENCOUNTER_ROCKET
        boy = 285, -- MUS_ENCOUNTER_BOY (default)
      },
      battle = {
        championClass = 90, champion = 299,
        gymClasses = { 84, 87 }, gym = 296,
        trainer = 297,
      },
      victory = {
        gymClasses = { 84, 90 }, gym = 312,
        trainer = 310,
      },
    },
  },

  -- src/ui/game3/region_map.lua:407-414
  regionMap = { switchFlag = "FLAG_SYS_SEVII_MAP_123" },

  -- Flags for the FRLG-only features that are ungated today
  -- (rse-seams sections 3.4 and 3.5).  The split is pret-grounded:
  -- pokefirered/src/{help_system,tm_case,fame_checker,teachy_tv,vs_seeker,
  -- trainer_tower,seagallop,trainer_fan_club}.c all exist; every one of those
  -- paths 404s in pokeemerald and pokeruby (verified 2026-09-22), except the
  -- shared primitives below which have RSE counterparts.
  capabilities = {
    -- shared GBA primitives (RSE implements these too)
    easyChat = true,
    braille = true,
    mysteryGift = true,
    unionRoom = true,
    daycare = true,
    pokecenter = true,
    marts = true,
    moveRelearner = true,
    eggs = true,
    berries = true,
    sizeRecord = true, -- pokeemerald/src/pokemon_size_record.c exists
    -- FireRed-only (no RSE counterpart in pret)
    helpSystem = true,
    tmCase = true,
    fameChecker = true,
    teachyTV = true,
    vsSeeker = true,
    trainerTower = true,
    seagallop = true,
    trainerFanClub = true,
    berryPouch = true,
    sevii = true,
  },

  -- src/core/game3/scripting/natives.lua:803-820
  nativeModules = {
    "natives_corner",
    "natives_cutscene",
    "natives_daycare",
    "natives_elevator",
    "natives_events",
    "natives_fame",
    "natives_fan_club",
    "natives_gift",
    "natives_link",
    "natives_listmenu",
    "natives_moveteach",
    "natives_queries",
    "natives_seagallop",
    "natives_size_record",
    "natives_tower",
    "natives_trade",
  },

  -- The aux extractors RomExtractorGen3:runAuxExtracts (:291-438) runs
  -- unconditionally today; an RSE row lists its own set.
  extractors = {
    "region_map_extract",
    "map_sections_extract",
    "multichoice_extract",
    "heal_locations_extract",
    "door_anim_extract",
    "slot_machine_extract",
    "trade_extract",
    "link_art_extract",
    "fame_checker_extract",
    "teachy_tv_extract",
    "mystery_gift_extract",
    "trainer_tower_extract",
    "tutor_extract",
    "museum_extract",
    "move_relearner_extract",
    "egg_extract",
    "battle_anim_extract",
    "battle_ai_extract",
  },
}
