-- Known clean US FireRed dumps → extract pointers (ROM file offsets).
-- Pointers are for FireRed USA 1.0 (SHA-1 41cb23d8…). Identity is SHA-1 only.

local Versions = {}

Versions.ROM_SIZE = 16777216
-- v53: outdoor LAB continuity — shared Y cuts, frlg bias, mid cohere, MRF.
-- v67: extract-first MapEvents + script BFS (cache is script/event source of truth)
-- v68: native FRLG mid atlas + pret map palettes (demake 2bpp still stored)
-- Text charmap $F0=':' fix lives in text_ir.lua; re-run script extract to refresh
-- cached strings (live cache was patched in-place for the yen→colon bug).
-- v72: naming keyboard 1:1 — cursor 2×2 frames, cropped KB, CLEAR row text
-- v75: restore title_screen.png composite + press_start / copyright aliases
-- v76: intro movie layout — copyright crop, GF sprite coords, scene1 frames
-- v77: GF presents center fix, scene3 gengar/bg pal, copyright x=0 crop
-- v78: scene2 PLTT slot shift, scene1 128px frames, scene3 grass 64×32
-- v79: title flames 10-frame sheet; title screen on Bg+Oam compositor
-- v80: trainer tables + battle intro back pics / party summary bar
-- v85: dual-layer native atlas (under/over) for pret BG2 sprite cover
-- v86: battle_transition ROM gfx → pokemon/battle_transition/
Versions.CACHE_VERSION = 86
Versions.NATIVE_VERSION = 5
Versions.OW_VERSION = 1
Versions.ANIM_VERSION = 1
-- Audio pack (M4A banks / DirectSound samples / cries).
Versions.AUDIO_VERSION = 5
-- FireRed USA 1.0 (BPRE) — located by structural scan (entry0 ms=me=0, SE_SELECT ms=me=2).
Versions.AUDIO = {
  song_table = 0x4A32CC,   -- gSongTable file offset
  song_count = 347,        -- ids 0 .. MUS_TEACHY_TV_MENU (346)
  cry_table = 0x48C914,    -- gCryTable (ToneData × 388)
  cry_count = 388,
}
-- game3 FieldView prefers pret 4bpp path when native cache is ready.
Versions.NATIVE_RENDER = true
Versions.OW_RENDER = true
Versions.TILESET_ANIM = true

--- GBA ROM pointer → file offset, or nil if not in ROM image.
function Versions.gbaToFile(addr)
  addr = tonumber(addr)
  if not addr or addr < 0x08000000 or addr >= 0x0A000000 then return nil end
  return addr - 0x08000000
end

-- FireRed USA 1.0 overworld object graphics (pret pokefirered.sym).
Versions.OW_GFX_POINTERS = 0x39FDB0       -- gObjectEventGraphicsInfoPointers
Versions.OW_SPRITE_PALETTES = 0x3A5158    -- sObjectEventSpritePalettes
Versions.NUM_OBJ_EVENT_GFX = 152
-- pret OBJ_EVENT_GFX_RED / OBJ_EVENT_GFX_GREEN (Leaf)
Versions.OW_PLAYER_MALE = 0
Versions.OW_PLAYER_MALE_BIKE = 1
Versions.OW_PLAYER_MALE_SURF = 2
Versions.OW_PLAYER_MALE_FIELD_MOVE = 3
Versions.OW_PLAYER_MALE_FISH = 4
Versions.OW_PLAYER_FEMALE = 7
Versions.OW_PLAYER_FEMALE_BIKE = 8
Versions.OW_PLAYER_FEMALE_SURF = 9
Versions.OW_PLAYER_FEMALE_FIELD_MOVE = 10
Versions.OW_PLAYER_FEMALE_FISH = 11
-- FireRed USA 1.0 font (menu cursor = SelectorArrow2 / charmap ▶ = 0xEF).
Versions.FONT_LATIN_NORMAL = 0x1FF300       -- sFontNormalLatinGlyphs
Versions.FONT_LATIN_WIDTHS = 0x207300       -- sFontNormalLatinGlyphWidths
Versions.FONT_GLYPH_BYTES = 64              -- 0x20 u16s per latin glyph
Versions.MENU_CURSOR_GLYPH = 0xEF           -- gText_SelectorArrow2

-- Pokémon species pack (names / icons / types / stats / abilities) — FireRed USA 1.0.
Versions.POKEMON_VERSION = 3
Versions.NUM_SPECIES = 412                -- SPECIES_NONE .. last (incl. egg/forms)
Versions.SPECIES_NAMES = 0x245EE0         -- gSpeciesNames
Versions.SPECIES_NAME_LENGTH = 11         -- 10 chars + 0xFF
Versions.SPECIES_INFO = 0x254784          -- gSpeciesInfo / BaseStats (28 bytes)
Versions.SPECIES_INFO_SIZE = 28
Versions.MON_ICON_TABLE = 0x3D37A0       -- gMonIconTable
Versions.MON_ICON_PAL_INDICES = 0x3D3E80  -- gMonIconPaletteIndices
Versions.MON_ICON_PALETTES = 0x3D3740     -- gMonIconPalettes (16 colors × N)
Versions.MON_ICON_PAL_COUNT = 6
Versions.MON_ICON_BYTES = 0x400           -- 32×64 4bpp (2 frames)
Versions.MON_ICON_W = 32
Versions.MON_ICON_H = 32                  -- first frame only
-- sSpeciesToNationalPokedexNum[NUM_SPECIES-1]; SpeciesToNational uses [species-1].
Versions.SPECIES_TO_NATIONAL = 0x251FEE
-- gAbilityNames[ABILITIES_COUNT][ABILITY_NAME_LENGTH+1] (FireRed USA 1.0 file off).
Versions.ABILITY_NAMES = 0x24FC40
Versions.ABILITY_NAME_LENGTH = 12
Versions.ABILITIES_COUNT = 78
Versions.ABILITY_DESCRIPTIONS = 0x24FB08   -- gAbilityDescriptionPointers (78 pointers)

-- Moves / learnsets / evolutions / TMHM / dex (FireRed USA 1.0 file offsets).
Versions.MOVE_NAMES = 0x247094            -- gMoveNames
Versions.MOVE_NAME_LENGTH = 12            -- +1 EOS → 13-byte stride
Versions.MOVE_DESCRIPTIONS = 0x4886E8     -- gMoveDescriptionPointers (354 pointers)
Versions.LEVEL_UP_LEARNSETS = 0x25D7B4    -- gLevelUpLearnsets pointer table
Versions.EVOLUTION_TABLE = 0x259754       -- gEvolutionTable
Versions.EVOS_PER_MON = 5
Versions.EVOLUTION_ENTRY_SIZE = 8         -- method,u16 param,u16 target,u16 pad
Versions.TMHM_LEARNSETS = 0x252BC8        -- sTMHMLearnsets (u32 lo + u32 hi)
Versions.TMHM_MOVES = 0x45A5A4            -- sTMHMMoves[58] u16
Versions.TMHM_COUNT = 58                  -- 50 TM + 8 HM
Versions.POKEDEX_ENTRIES = 0x44E850       -- gPokedexEntries (national index)
Versions.POKEDEX_ENTRY_SIZE = 36
Versions.NATIONAL_DEX_COUNT = 386         -- Deoxys; entries are 0..386 inclusive → 387
Versions.SPECIES_TO_KANTO = 0x251EE0      -- sSpeciesToKantoPokedexNum (411 u16s)
Versions.DEX_CATEGORIES = 0x452C4C        -- gDexCategories (9 categories)
Versions.POKEDEX_ORDERS = {
  alphabetical = 0x443FF2,
  weight = 0x4442F6,
  height = 0x4445FA,
  type = 0x4448FE,
}

-- Items table (FireRed USA 1.0). 375 entries × 44 bytes stride.
Versions.ITEMS = 0x3DB028
Versions.ITEMS_COUNT = 375
Versions.ITEM_STRIDE = 44

-- gBattleMoves (FireRed USA 1.0). Rows are 12 bytes (9-byte BattleMove + pad).
Versions.BATTLE_MOVES_VERSION = 1
Versions.BATTLE_MOVES = 0x250C04
Versions.BATTLE_MOVE_SIZE = 12
Versions.MOVES_COUNT = 355 -- MOVE_NONE .. last Gen3 move id inclusive span

-- Battle anim IR pack (transpile from pret scripts + tag sheets).
Versions.BATTLE_ANIMS_VERSION = 2

-- Wild encounters (FireRed USA 1.0): gWildMonHeaders[] — 20-byte entries,
-- terminated by mapGroup/mapNum = 0xFF. Verified via Route 1 land fingerprint.
Versions.WILD_MON_HEADERS = 0x3C9CB8
Versions.WILD_MON_HEADER_SIZE = 20
Versions.LAND_WILD_COUNT = 12
Versions.WATER_WILD_COUNT = 5
Versions.ROCK_WILD_COUNT = 5
Versions.FISH_WILD_COUNT = 10

-- Field-effect graphics & palettes (FireRed USA 1.0)
Versions.FIELD_EFFECT_TALL_GRASS = 0x39A008      -- gFieldEffectObjectPic_TallGrass
Versions.FIELD_EFFECT_PAL_GENERAL_1 = 0x398FC8 -- gFieldEffectObjectPalette1
Versions.FIELD_EFFECT_PAL_GENERAL_0 = 0x398FA8 -- gFieldEffectObjectPalette0
Versions.FIELD_EFFECT_PAL_PLAYER = 0x35B968    -- gObjectEventPal_Player (surf blob, etc.)

Versions.FIELD_EFFECTS = {
  tall_grass   = { pic = 0x39A008, pal = 0x398FC8, w = 16, h = 16, frames = 5 },
  cut_grass    = { pic = 0x398648, pal = 0x398FC8, w = 8,  h = 8,  frames = 1 },
  rock_smash   = { pic = 0x398928, pal = 0x398FA8, w = 16, h = 16, frames = 4 },
  surf_blob    = { pic = 0x396B08, pal = 0x35B968, w = 32, h = 32, frames = 6 },
  fly_bird     = { pic = 0x398048, pal = 0x398FA8, w = 32, h = 32, frames = 4 },
  ripple       = { pic = 0x398BA8, pal = 0x398FA8, w = 16, h = 16, frames = 8 },
  emoticons    = { pic = 0x3C6AC8, pal = 0x35B968, w = 16, h = 16, frames = 15 },
}

-- Battle interface chrome (FireRed USA 1.0 file offsets; LZ unless noted).
-- Healthbox pals are uncompressed INCBIN_U16 (pret graphics.c); matched to healthbox.pal.
-- Terrain grass: sBattleTerrainPalette/Tiles/Tilemap_Grass (battle_bg.c).
Versions.BATTLE_UI = {
  textbox_gfx = 0xD00000,           -- gBattleInterface_Textbox_Gfx LZ → 8192
  textbox_pal = 0xD004D8,           -- LZ → 64 (2×16 colors)
  textbox_tilemap = 0xD0051C,       -- LZ → 4096 (32×64 tiles)
  healthbox_elements = 0xD11BC4,    -- uncompressed 320×24 4bpp
  healthbox_player = 0xD1F340,      -- gHealthboxSinglesPlayerGfx LZ → 4096
  healthbox_enemy = 0xD1F604,       -- gHealthboxSinglesOpponentGfx LZ → 2048
  healthbox_pal = 0xD11B84,         -- uncompressed 32 (gBattleInterface_Healthbox_Pal)
  healthbar_pal = 0xD11BA4,         -- uncompressed 32 (gBattleInterface_Healthbar_Pal)
  terrain_grass = {
    pal = 0x248400,                 -- LZ → 96 (3 banks)
    tiles = 0x24844C,               -- LZ → 3136
    tilemap = 0x2489A8,             -- LZ → 4096 (32×32)
  },
  -- Indoor / lab (MAP_TYPE_INDOOR → BATTLE_TERRAIN_BUILDING)
  terrain_building = {
    pal = 0x24DDF0,                 -- LZ → 96
    tiles = 0x24DE34,               -- LZ → 2464
    tilemap = 0x24E16C,             -- LZ → 4096
  },
  party_summary_bar = 0xE7BB04,   -- gBattleInterface_PartySummaryBar_Gfx LZ → 512
}

-- Battle field→battle transitions (FireRed USA 1.0; uncompressed INCBINs in
-- battle_transition.c). Fingerprinted vs pret graphics/battle_transitions/*.
Versions.BATTLE_TRANSITION = {
  big_pokeball_gfx = 0x3F87A0,       -- 32×88 4bpp (44 tiles)
  sliding_pokeball_bin = 0x3F8D20,   -- 64 B paint tile
  sliding_pokeball_gfx = 0x3F8D60,   -- 32×32 4bpp
  mugshot_banner_gfx = 0x3F8F60,     -- 120×8 4bpp
  -- unused_brendan / unused_lass at 0x3F9140 / 0x3F9940 (not extracted)
  grid_square_gfx = 0x3FA140,        -- 8×120 4bpp (15 shrink frames)
  sliding_pokeball_pal = 0x3FA638,   -- 16 colors (shared big/trail)
  mugshot_pals = {
    lorelei = 0x3FA660,
    bruno = 0x3FA680,
    agatha = 0x3FA6A0,
    lance = 0x3FA6C0,
    blue = 0x3FA6E0,
    red = 0x3FA700,    -- player male strip colors
    green = 0x3FA720,  -- player female strip colors
  },
  big_pokeball_tilemap = 0x3FA784,   -- 20×30 u16
  vsbar_tilemap = 0x3FAC34,          -- 20×32 u16
}

Versions.MON_BACK_PIC_TABLE = 0x23654C -- gMonBackPicTable

-- Trainer graphics / tables (FireRed USA 1.0 file offsets).
Versions.TRAINER_FRONT_PIC_TABLE = 0x23957C
Versions.TRAINER_FRONT_PIC_PAL_TABLE = 0x239A1C
Versions.TRAINER_BACK_PIC_TABLE = 0x239FA4
Versions.TRAINER_BACK_PIC_PAL_TABLE = 0x239FD4
Versions.TRAINERS_TABLE = 0x23EAC8
Versions.TRAINER_STRIDE = 0x28
Versions.TRAINER_CLASS_NAMES = 0x23E558
Versions.TRAINER_CLASS_NAME_STRIDE = 13
Versions.TRAINER_CLASS_COUNT = 107
Versions.TRAINER_PIC_COUNT = 148
Versions.TRAINERS_COUNT = 743 -- pret NUM_TRAINERS

-- Party menu chrome (LZ-compressed; FireRed USA 1.0).
Versions.PARTY_MENU_BG_GFX = 0xE82700       -- gPartyMenuBg_Gfx
Versions.PARTY_MENU_BG_PAL = 0xE829C8       -- gPartyMenuBg_Pal
Versions.PARTY_MENU_BG_TILEMAP = 0xE82AB0   -- gPartyMenuBg_Tilemap
Versions.PARTY_MENU_BALL_GFX = 0xE82BE8     -- gPartyMenuPokeball_Gfx
Versions.PARTY_MENU_BALL_PAL = 0xE82E7C     -- gPartyMenuPokeball_Pal

-- Pokémon Summary Screen (LZ-compressed & raw; FireRed USA 1.0).
Versions.SUMMARY_BG_GFX = 0xE9A460               -- gSummaryScreen_Gfx (LZ 4bpp, 16384 bytes)
Versions.SUMMARY_BG_PAL = 0xE9B310               -- gSummaryScreen_Pal (7 banks, 224 bytes)
Versions.SUMMARY_EXP_BAR_GFX = 0xE9B3F0          -- gSummaryExpBar_Gfx (LZ 4bpp, 384 bytes)
Versions.SUMMARY_HP_BAR_GFX = 0xE9B4B8           -- gSummaryHpBar_Gfx (LZ 4bpp, 384 bytes)
Versions.SUMMARY_HP_EXP_PAL = 0xE9B578           -- gSummaryBar_Pal (32 bytes)
Versions.SUMMARY_PAGE_INFO_TILEMAP = 0xE9B598    -- gSummaryPage_Info_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_SKILLS_TILEMAP = 0xE9B750  -- gSummaryPage_Skills_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_MOVES_TILEMAP = 0xE9B950   -- gSummaryPage_Moves_Tilemap (LZ 32x32, 2048 bytes)
Versions.SUMMARY_PAGE_MOVES_INFO_TILEMAP = 0xE9BA9C -- gSummaryPage_MovesInfo_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_EGG_TILEMAP = 0xE9BBCC     -- gSummaryPage_Egg_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_STATUS_ICONS_GFX = 0xE82EA0     -- gStatusGfx_Icons (LZ 4bpp, 1024 bytes)
Versions.SUMMARY_STATUS_ICONS_PAL = 0xE9BF28     -- gSummaryStatus_Pal (32 bytes)
Versions.SUMMARY_CURSOR_LEFT_GFX = 0x463740      -- sMoveSelectionCursor_Left_Gfx (288 bytes)
Versions.SUMMARY_CURSOR_RIGHT_GFX = 0x46386C     -- sMoveSelectionCursor_Right_Gfx (288 bytes)
Versions.SUMMARY_CURSOR_PAL = 0x463720           -- sMoveSelectionCursor_Pal (32 bytes)
Versions.SUMMARY_SHINY_STAR_GFX = 0x463B64       -- sShinyStar_Gfx (64 bytes)
Versions.SUMMARY_SHINY_STAR_PAL = 0x463B44       -- sShinyStar_Pal (32 bytes)
Versions.SUMMARY_POKERUS_GFX = 0x463B20          -- sPokerus_Gfx (64 bytes)
Versions.SUMMARY_POKERUS_PAL = 0x463B00          -- sPokerus_Pal (32 bytes)
Versions.SUMMARY_HP_BAR_YELLOW_PAL = 0x463AAC    -- sHpBar_Yellow_Pal (32 bytes)
Versions.SUMMARY_HP_BAR_RED_PAL = 0x463ACC       -- sHpBar_Red_Pal (32 bytes)

-- Bag / item-menu chrome + item icons (LZ; FireRed USA 1.0).
Versions.BAG_BG_GFX = 0xE830CC                  -- gBagBg_Gfx
Versions.BAG_BG_TILEMAP = 0xE832C0              -- gBagBg_Tilemap
Versions.BAG_BG_ITEM_PC_TILEMAP = 0xE83444      -- gBagBg_ItemPC_Tilemap
Versions.BAG_BG_PAL = 0xE835B4                  -- gBagBgPalette (3 banks)
Versions.BAG_BG_PAL_FEMALE = 0xE83604           -- gBagBgPalette_FemaleOverride
Versions.BAG_MALE_GFX = 0xE8362C                -- gBagMale_Gfx (64×256)
Versions.BAG_FEMALE_GFX = 0xE83DBC              -- gBagFemale_Gfx
Versions.BAG_SPRITE_PAL = 0xE84560              -- gBag_Pal
Versions.BAG_SWAP_GFX = 0xE84588                -- gSwapLine_Gfx
Versions.BAG_SWAP_PAL = 0xE845C8                -- gSwapLine_Pal

-- Trainer Card (LZ-compressed & raw; FireRed USA 1.0).
Versions.TRAINER_CARD_BG_TILES = 0xE86240       -- sTrainerCard_BgTiles (LZ 4bpp, 7456 bytes)
Versions.TRAINER_CARD_BG_MALE_MAP = 0xE86BE8    -- sTrainerCard_BgTilemap (LZ 32x20, 2048 bytes)
Versions.TRAINER_CARD_BG_FEMALE_MAP = 0xE86D6C  -- sTrainerCard_BgFemaleTilemap (LZ 32x20, 2048 bytes)
Versions.TRAINER_CARD_BG_PAL = 0xE86F98         -- sTrainerCard_BgPal (4 banks, 128 bytes)
Versions.TRAINER_CARD_BADGES_TILES = 0x3A5348   -- sTrainerCard_BadgesTiles (32 tiles 4bpp, 1024 bytes)
Versions.SHOP_BG_GFX = 0xE85DC8                 -- gBuyMenuFrame_Gfx
Versions.SHOP_BG_TILEMAP = 0xE85EFC             -- gBuyMenuFrame_Tilemap
Versions.SHOP_BG_TM_TILEMAP = 0xE86038          -- gBuyMenuFrame_TmHmTilemap
Versions.SHOP_BG_PAL = 0xE86170                 -- gBuyMenuFrame_Pal
Versions.ITEM_ICON_TABLE = 0x3D4294             -- sItemIconTable[ITEMS_COUNT+1]
Versions.ITEMS_COUNT = 375                      -- pret ITEMS_COUNT (table rows = +1)

-- Door animation graphics (sDoorGraphics[] from field_door.c; FireRed USA 1.0 file offsets).
-- Table layout: 12 bytes/entry: u32(metatileId|isLarge<<16) | ptr_tiles | ptr_pal
-- Verified by matching known metatile-ID sequence from DOOR_ENTRIES (0x03D/0x062/0x15B...).
Versions.DOOR_GRAPHICS_TABLE = 0x35B5D8         -- sDoorGraphics[32]
Versions.DOOR_GRAPHICS_COUNT = 32               -- entries in the table

-- Title screen + Oak speech graphics (FireRed USA 1.0 file offsets).
-- Verified by matching pret .gbapal bytes + LZ sizes in local dump.
Versions.INTRO = {
  -- Oak speech pics: 64×96 8bpp; ROM stores 32-color pal, indices use bank bits.
  leaf_pal = 0x460ED4,
  leaf_tiles = 0x460F14, -- LZ → 0x1800
  red_pal = 0x4615FC,
  red_tiles = 0x46163C, -- LZ → 0x1800
  oak_pal = 0x461CD4,
  oak_tiles = 0x461D14, -- LZ → 0x1800
  rival_pal = 0x4623AC,
  rival_tiles = 0x4623EC, -- LZ → 0x1800
  platform_pal = 0x4629D0, -- 16 colors
  platform_tiles = 0x462A10, -- LZ → 0x600 (3×32×32)
  -- Title screen
  logo_pal = 0xEAB6C4, -- 256 colors
  logo_tiles = 0xEAB8C4, -- LZ → 0x4000 (8bpp)
  logo_map = 0xEAD390, -- LZ → 0x500 (32×20)
  box_pal = 0xEAD5E8, -- 16 colors
  box_tiles = 0xEAD608, -- LZ → 0x10E0 (135 tiles 4bpp)
  box_map = 0xEADEE4, -- LZ → 0x500
  copyright_pal = 0xEAE094, -- 16 colors (bg + press-start)
  copyright_tiles = 0xEAE0B4, -- LZ → 0x800
  copyright_map = 0xEAE374, -- LZ → 0x500
  -- Oak speech scene BG (verified vs pret oak_speech_bg.* LZ)
  oak_speech_bg_pal = 0x460568, -- first 16 of shared guide pal
  oak_speech_bg_tiles = 0x460CA4, -- LZ → 0x140 (10 tiles)
  oak_speech_bg_map = 0x460CE8, -- LZ → 0x500
  -- Controls guide + Pikachu intro BG (pret bg_tiles + pikachu_intro/tilemap)
  -- Shared pal is 64 colors (4 banks) packed before tiles LZ.
  guide_bg_pal = 0x460568, -- 64 colors
  guide_bg_tiles = 0x4605E8, -- LZ → 0x1400 (160 tiles)
  pikachu_intro_map = 0x460BA8, -- LZ → 0x438 (30×18)
  controls_page2_map = 0x460D94, -- 5×16 u16 uncompressed
  controls_page3_map = 0x460E34, -- 5×16 u16 uncompressed
  stdpal_2 = 0x471E2C, -- GetTextWindowPalette(2); TopBar / chrome rows
  -- Pikachu intro sprites (pret pikachu_intro/{body,ears,eyes})
  pikachu_pal = 0x4629F0, -- 16 colors
  pikachu_body = 0x462B74, -- LZ → 0x400 (32×64, 2 frames)
  pikachu_ears = 0x462D34, -- LZ → 0x200 (32×32)
  pikachu_eyes = 0x462E18, -- LZ → 0x80 (16×8)
  -- Nidoran♀ front (species 29) + poke ball for release anim
  -- gMonFrontPicTable @ 0x2350AC; gMonPaletteTable @ 0x23730C (FR USA 1.0)
  mon_front_pic_table = 0x2350AC,
  mon_palette_table = 0x23730C,
  nidoran_f_tiles = 0xD42FB8, -- LZ → 0x800 (64×64); was wrongly 0x4096CC (Bulbasaur)
  nidoran_f_pal = 0xD4321C, -- LZ → 0x20
  ball_poke_tiles = 0xD01724, -- LZ → 0x180 (16×48)
  ball_poke_pal = 0xD017E0, -- LZ → 0x20
}

-- Intro cutscene sequence assets (pokefirered/src/intro.c rodata offsets).
Versions.INTRO_MOVIE = {
  copyright_pal = 0x402260,
  copyright_tiles = 0x402280, -- LZ → 1248 bytes
  copyright_map = 0x4024E4,   -- LZ → 2048 bytes (32×32)

  gf_bg_pal = 0x402630,
  gf_bg_tiles = 0x402650,     -- LZ → 96 bytes
  gf_bg_map = 0x402668,       -- LZ → 1280 bytes (32×20)
  gf_logo_pal = 0x40270C,
  gf_text_tiles = 0x40272C,   -- LZ → 1152 bytes
  gf_logo_tiles = 0x4028F8,   -- LZ → 1024 bytes
  star_pal = 0x402A44,
  star_tiles = 0x402A64,      -- LZ → 128 bytes
  sparkles_pal = 0x402ABC,
  sparkles_small_tiles = 0x402ADC, -- LZ → 128 bytes
  sparkles_big_tiles = 0x402B2C,   -- LZ → 2048 bytes
  presents_tiles = 0x402CD4,       -- LZ → 256 bytes

  scene1_grass_pal = 0x402D34,
  scene1_grass_tiles = 0x402D54,   -- LZ → 12704 bytes
  scene1_grass_map = 0x403FE8,     -- LZ → 4096 bytes (64×32)
  scene1_bg_pal = 0x4048CC,
  scene1_bg_tiles = 0x4048EC,      -- LZ → 4352 bytes
  scene1_bg_map = 0x404F7C,        -- LZ → 4096 bytes (64×32)

  scene2_bg_pal = 0x4053B4,        -- 96 bytes (3 banks)
  scene2_bg_tiles = 0x405414,      -- LZ → 2176 bytes
  scene2_bg_map = 0x405890,        -- LZ → 4096 bytes (64×32)
  scene2_plants_pal = 0x405B08,
  scene2_plants_tiles = 0x405B28,  -- LZ → 544 bytes
  scene2_plants_map = 0x405CDC,    -- LZ → 1280 bytes (32×20)
  gengar_pal = 0x405DA4,
  scene2_gengar_close_tiles = 0x405DC4, -- LZ → 3648 bytes
  scene2_gengar_close_map = 0x40644C,   -- LZ → 2048 bytes (32×32)
  scene2_nidorino_close_pal = 0x406634,
  scene2_nidorino_close_tiles = 0x406654, -- LZ → 5440 bytes
  scene2_nidorino_close_map = 0x4071D0,   -- LZ → 2048 bytes (32×32)

  scene3_bg_pal = 0x407430,        -- 64 bytes (2 banks)
  scene3_bg_tiles = 0x407470,      -- LZ → 2784 bytes
  scene3_bg_map = 0x407A50,        -- LZ → 1280 bytes (32×20)
  scene3_gengar_anim_tiles = 0x407B9C, -- LZ → 11136 bytes
  scene3_gengar_anim_map = 0x408D98,   -- LZ → 4096 bytes (64×32)
  scene2_gengar_tiles = 0x40926C,      -- LZ → 2048 bytes (64×64)
  nidorino_pal = 0x4096AC,
  scene2_nidorino_tiles = 0x4096CC,    -- LZ → 2048 bytes (64×64)
  scene3_grass_pal = 0x409A1C,
  scene3_grass_tiles = 0x409A3C,       -- LZ → 2048 bytes (64×64)
  scene3_gengar_static_tiles = 0x409D20, -- LZ → 6144 bytes
  scene3_nidorino_tiles = 0x40A3E4,    -- LZ → 10240 bytes
  scene3_swipe_pal = 0x40B834,
  scene3_recoil_dust_pal = 0x40B854,
  scene3_swipe_tiles = 0x40B874,       -- LZ → 2560 bytes
  scene3_recoil_dust_tiles = 0x40BAE0, -- LZ → 512 bytes
}

-- Title screen particle effects (pokefirered/src/title_screen.c).
Versions.TITLE_EFFECTS = {
  border_bg_tiles = 0x3BF58C,      -- LZ → 128 bytes
  border_bg_map = 0x3BF5A8,        -- LZ → 1280 bytes
  slash_tiles = 0x3BF64C,          -- LZ → 2048 bytes
  flames_pal = 0x3BF77C,           -- 32 bytes
  flames_tiles = 0x3BF79C,         -- LZ → 1280 bytes
  blank_flames_tiles = 0x3BFA14,   -- LZ → 1280 bytes
}


-- Naming screen chrome (FireRed USA 1.0). Verified by matching pret LZ/4bpp.
Versions.NAMING = {
  keyboard_pal = 0xE97FE4, -- 16 colors
  rival_pal = 0xE98004, -- 16 colors
  menu_pal = 0xE98024, -- 6×16 banks (menu / page labels / buttons / cursor)
  menu_gfx = 0xE980E4, -- LZ → 0x600
  background_map = 0xE982BC, -- LZ → 0x500
  keyboard_upper_map = 0xE98398, -- LZ → 0x500
  keyboard_lower_map = 0xE98458, -- LZ → 0x500
  keyboard_symbols_map = 0xE98518, -- LZ → 0x500
  -- Uncompressed 4bpp sprite sheets (sequential in ROM)
  page_swap_frame = 0xE985D8, -- 0x280
  back_button = 0xE98858, -- 0x1E0
  ok_button = 0xE98A38, -- 0x1E0
  page_swap_upper = 0xE98C18, -- 0x60
  page_swap_lower = 0xE98CB8, -- 0x60
  page_swap_others = 0xE98D58, -- 0x60
  cursor = 0xE98DF8, -- 0x80
  cursor_squished = 0xE98E98, -- 0x80
  cursor_filled = 0xE98F38, -- 0x80
  page_swap_button = 0xE98FD8, -- 0x100
  input_arrow = 0xE990D8, -- 0x20
  underscore = 0xE990F8, -- 0x20
  rival_gfx = 0x38A428, -- uncompressed 0x900 (naming-screen rival bust)
}

-- General primary tileset anim frames (TilesetAnim_General).
Versions.TILESET_ANIM_GENERAL = {
  flower = { base = 0x3A73E0, stride = 0x80, count = 5, bytes = 0x80 },
  water = { base = 0x3A7674, stride = 0x600, count = 8, bytes = 0x600 },
  sand = { base = 0x3AA674, stride = 0x240, count = 8, bytes = 0x240 },
}

-- Extract tileset pair → engine tileset id (palette bank key).
Versions.PAIR_TILESET = {
  sevii_outdoor = "SEVII_OUTDOOR",
  network = "SEVII_NETWORK",
  house = "SEVII_HOUSE",
  harbor = "SEVII_HARBOR",
  pallet_outdoor = "FR_PALLET_OUTDOOR",
  player_house = "FR_PLAYER_HOUSE",
  oak_lab = "FR_OAK_LAB",
  pewter_outdoor = "FR_PEWTER_OUTDOOR",
  pewter_gym = "FR_PEWTER_GYM",
  viridian_outdoor = "FR_VIRIDIAN_OUTDOOR",
}

-- Individual tileset blobs (FireRed USA 1.0), verified by matching pret bins in ROM.
Versions.TILESETS = {
  general = {
    compressed = true,
    secondary = false,
    tiles = 0x0EA1D68,
    palettes = 0x0EA1B68,
    metatiles = 0x29F6C8,
    attributes = 0x2A1EC8,
    metatile_bytes = 10240, -- 640 mids
    attr_bytes = 2560,
    palette_count = 16,
  },
  building = {
    compressed = true,
    secondary = false,
    tiles = 0x0275294,
    palettes = 0x0277694,
    metatiles = 0x02AD7B4,
    attributes = 0x02AFFB4,
    metatile_bytes = 10240, -- 640 mids
    attr_bytes = 2560,
    palette_count = 16,
  },
  sevii_islands_123 = {
    compressed = true,
    secondary = true,
    tiles = 0x0298B70,
    palettes = 0x0299AA4,
    metatiles = 0x2CD1CC,
    attributes = 0x2CE39C,
    metatile_bytes = 4560, -- 285 mids
    attr_bytes = 1140,
    palette_count = 16,
  },
  pokemon_center = {
    compressed = true,
    secondary = true,
    tiles = 0x0277C5C,
    palettes = 0x0278CC4,
    metatiles = 0x02B3A60,
    attributes = 0x02B4A50,
    metatile_bytes = 4080, -- 255 mids
    attr_bytes = 1020,
    palette_count = 16,
  },
  generic_building_2 = {
    compressed = true,
    secondary = true,
    tiles = 0x028E5A4,
    palettes = 0x028EC70,
    metatiles = 0x02BEF14,
    attributes = 0x02BFA94,
    metatile_bytes = 2944, -- 184 mids
    attr_bytes = 736,
    palette_count = 16,
  },
  island_harbor = {
    compressed = true,
    secondary = true,
    tiles = 0x029D0E4,
    palettes = 0x029D894,
    metatiles = 0x02D1D30,
    attributes = 0x02D2220,
    metatile_bytes = 1264, -- 79 mids
    attr_bytes = 316,
    palette_count = 16,
  },
  -- Pallet Town / Route 1 secondary (petaltown / pallet_town).
  -- Sizes must match pret bins in ROM (attrs sit immediately after metatiles).
  -- Oversized metatile_bytes previously skipped real attrs → outdoor doors
  -- seeded as solid BUILDING (0x07) instead of MB_WARP_DOOR.
  pallet_town = {
    compressed = true,
    secondary = true,
    tiles = 0x026D37C,
    palettes = 0x026D7C0,
    metatiles = 0x02A28C8,
    attributes = 0x02A2E58,
    metatile_bytes = 1424, -- 89 mids
    attr_bytes = 356,
    palette_count = 16,
  },
  pewter_city = {
    compressed = true,
    secondary = true,
    tiles = 0x026E1C0,
    palettes = 0x026EAB8,
    metatiles = 0x02A3728,
    attributes = 0x02A3C18,
    metatile_bytes = 1264, -- 79 mids
    attr_bytes = 316,
    palette_count = 16,
  },
  -- Viridian City / Route 2 secondary (matched pret bins in FR 1.0 ROM).
  viridian_city = {
    compressed = true,
    secondary = true,
    tiles = 0x026D9C0,
    palettes = 0x026DFC0,
    metatiles = 0x02A2FBC,
    attributes = 0x02A35AC,
    metatile_bytes = 1520, -- 95 mids
    attr_bytes = 380,
    palette_count = 16,
  },
  pewter_gym = {
    compressed = true,
    secondary = true,
    tiles = 0x02831BC,
    palettes = 0x02839B0,
    metatiles = 0x02AAA14,
    attributes = 0x02AB064,
    metatile_bytes = 1616, -- 101 mids
    attr_bytes = 404,
    palette_count = 16,
  },
  -- Player house interior secondary.
  pretty_petals_flower_shop = {
    compressed = true,
    secondary = true,
    tiles = 0x0EA99F4,
    palettes = 0x0EA97F4,
    metatiles = 0x02B4E4C,
    attributes = 0x02B4FCC,
    metatile_bytes = 384, -- 24 mids (ROM matches pret generic_building_1)
    attr_bytes = 96,
    palette_count = 16,
  },
  -- Oak lab secondary.
  lab = {
    compressed = true,
    secondary = true,
    tiles = 0x02806EC,
    palettes = 0x0280D00,
    metatiles = 0x02B68A0,
    attributes = 0x02B7390,
    metatile_bytes = 2800, -- 175 mids
    attr_bytes = 700,
    palette_count = 16,
  },
}

-- Primary+secondary pairs used by Island 1 maps.
Versions.TILESET_PAIRS = {
  sevii_outdoor = { primary = "general", secondary = "sevii_islands_123" },
  network = { primary = "building", secondary = "pokemon_center" },
  house = { primary = "building", secondary = "generic_building_2" },
  harbor = { primary = "general", secondary = "island_harbor" },
  pallet_outdoor = { primary = "general", secondary = "pallet_town" },
  player_house = { primary = "building", secondary = "pretty_petals_flower_shop" },
  oak_lab = { primary = "building", secondary = "lab" },
  pewter_outdoor = { primary = "general", secondary = "pewter_city" },
  pewter_gym = { primary = "building", secondary = "pewter_gym" },
  viridian_outdoor = { primary = "general", secondary = "viridian_city" },
}

-- Layout geometry + which tileset pair each map uses.
Versions.MAPS = {
  SEVII_ONE_ISLAND = {
    layout = "OneIsland",
    width = 24, height = 20,
    kind = "town",
    environment = "TOWN",
    pair = "sevii_outdoor",
  },
  SEVII_ONE_ISLAND_KINDLE_ROAD = {
    layout = "OneIsland_KindleRoad",
    width = 24, height = 140,
    kind = "route",
    environment = "ROUTE",
    pair = "sevii_outdoor",
  },
  SEVII_ONE_ISLAND_TREASURE_BEACH = {
    layout = "OneIsland_TreasureBeach",
    width = 24, height = 40,
    kind = "route",
    environment = "ROUTE",
    pair = "sevii_outdoor",
  },
  -- FRLG Network Center (heal + Network Machine). Not a stock Gen1/2 Poké Center.
  SEVII_ONE_ISLAND_POKECENTER = {
    layout = "OneIsland_PokemonCenter_1F",
    width = 19, height = 11,
    kind = "indoor",
    environment = "INDOOR",
    pair = "network",
  },
  SEVII_ONE_ISLAND_POKECENTER_2F = {
    layout = "OneIsland_PokemonCenter_2F",
    width = 15, height = 10,
    kind = "indoor",
    environment = "INDOOR",
    pair = "network",
  },
  SEVII_ONE_ISLAND_HARBOR = {
    layout = "Island_Harbor",
    width = 17, height = 13,
    kind = "indoor",
    environment = "INDOOR",
    pair = "harbor",
  },
  SEVII_ONE_ISLAND_HOUSE1 = {
    layout = "House3",
    width = 11, height = 9,
    kind = "indoor",
    environment = "INDOOR",
    pair = "house",
  },
  SEVII_ONE_ISLAND_HOUSE2 = {
    layout = "House3",
    width = 11, height = 9,
    kind = "indoor",
    environment = "INDOOR",
    pair = "house",
  },
  FR_PALLET_TOWN = {
    layout = "PalletTown",
    width = 24, height = 20,
    kind = "town",
    environment = "TOWN",
    pair = "pallet_outdoor",
  },
  FR_ROUTE_1 = {
    layout = "Route1",
    width = 24, height = 40,
    kind = "route",
    environment = "ROUTE",
    pair = "pallet_outdoor",
  },
  FR_VIRIDIAN_CITY = {
    layout = "ViridianCity",
    width = 48, height = 40,
    kind = "town",
    environment = "TOWN",
    pair = "viridian_outdoor",
  },
  FR_ROUTE_2 = {
    layout = "Route2",
    width = 24, height = 80,
    kind = "route",
    environment = "ROUTE",
    pair = "viridian_outdoor",
  },
  -- pret: 2F bedroom is 12×9; 1F living room is 13×10 (names are easy to swap).
  FR_PLAYERS_HOUSE_2F = {
    layout = "PlayersHouse_2F",
    width = 12, height = 9,
    kind = "indoor",
    environment = "INDOOR",
    pair = "player_house",
  },
  FR_PLAYERS_HOUSE_1F = {
    layout = "PlayersHouse_1F",
    width = 13, height = 10,
    kind = "indoor",
    environment = "INDOOR",
    pair = "player_house",
  },
  FR_RIVALS_HOUSE = {
    layout = "RivalsHouse",
    width = 13, height = 10,
    kind = "indoor",
    environment = "INDOOR",
    pair = "house",
  },
  FR_OAKS_LAB = {
    layout = "OaksLab",
    width = 13, height = 14,
    kind = "indoor",
    environment = "INDOOR",
    pair = "oak_lab",
  },
  FR_PEWTER_CITY = {
    layout = "PewterCity",
    width = 48, height = 40,
    kind = "town",
    environment = "TOWN",
    pair = "pewter_outdoor",
  },
  FR_PEWTER_CITY_GYM = {
    layout = "PewterCity_Gym",
    width = 13, height = 16,
    kind = "indoor",
    environment = "INDOOR",
    pair = "pewter_gym",
  },
}

-- FireRed USA 1.0 gMapGroups (array of MapGroup* → MapHeader*).
-- Verified: group[3][0] = PalletTown MapHeader @ 0x350618.
Versions.G_MAP_GROUPS = 0x3526A8
Versions.NUM_MAP_GROUPS = 43 -- pret map_groups.json group_order length

-- FireRed USA 1.0 MapHeader file offsets (verified against local dump).
-- Legacy hand list — prefer MapTree.walk(gMapGroups) for new extract.
-- Shared layouts (House3 / Harbor / PC 2F) disambiguated by header proximity
-- to One Island Network Center (0x351B6C).
Versions.MAP_HEADERS = {
  SEVII_ONE_ISLAND = 0x350768,
  SEVII_ONE_ISLAND_KINDLE_ROAD = 0x350B04,
  SEVII_ONE_ISLAND_TREASURE_BEACH = 0x350B20,
  SEVII_ONE_ISLAND_POKECENTER = 0x351B6C,
  SEVII_ONE_ISLAND_POKECENTER_2F = 0x351B18,
  SEVII_ONE_ISLAND_HARBOR = 0x351B50,
  SEVII_ONE_ISLAND_HOUSE1 = 0x351BA4,
  SEVII_ONE_ISLAND_HOUSE2 = 0x351BC0,
  FR_PALLET_TOWN = 0x350618,
  FR_VIRIDIAN_CITY = 0x350634,
  FR_ROUTE_1 = 0x35082C,
  FR_ROUTE_2 = 0x350848,
  -- MapHeaders: 0x350D50 = 1F (Mom + 4 warps); 0x350D6C = 2F (bedroom signs + 1 warp).
  FR_PLAYERS_HOUSE_1F = 0x350D50,
  FR_PLAYERS_HOUSE_2F = 0x350D6C,
  FR_RIVALS_HOUSE = 0x350D88,
  FR_OAKS_LAB = 0x350DA4,
  FR_PEWTER_CITY = 0x350650,
  FR_PEWTER_CITY_GYM = 0x350EA0,
}

-- FireRed USA 1.0 map.bin offsets (matched against pret layout bins).
local FIRERED_10_LAYOUTS = {
  OneIsland = { offset = 0x321354, width = 24, height = 20 },
  OneIsland_KindleRoad = { offset = 0x324330, width = 24, height = 140 },
  OneIsland_TreasureBeach = { offset = 0x325D94, width = 24, height = 40 },
  OneIsland_PokemonCenter_1F = { offset = 0x33A7CC, width = 19, height = 11 },
  -- Shared Pokémon Center 2F bin (several maps); first hit is fine — identical data.
  OneIsland_PokemonCenter_2F = { offset = 0x2D59B4, width = 15, height = 10 },
  Island_Harbor = { offset = 0x343DFC, width = 17, height = 13 },
  House3 = { offset = 0x2D5BF0, width = 11, height = 9 },
  PalletTown = { offset = 0x2DD100, width = 24, height = 20 },
  Route1 = { offset = 0x2E4E4C, width = 24, height = 40 },
  ViridianCity = { offset = 0x2DD4E4, width = 48, height = 40 },
  Route2 = { offset = 0x2E55F0, width = 24, height = 80 },
  -- Verified vs pret map.bin + local FR ROM: 0x2D50FC = 1F (13×10), 0x2D5224 = 2F (12×9).
  PlayersHouse_1F = { offset = 0x2D50FC, width = 13, height = 10 },
  PlayersHouse_2F = { offset = 0x2D5224, width = 12, height = 9 },
  RivalsHouse = { offset = 0x2D5320, width = 13, height = 10 },
  OaksLab = { offset = 0x2D54FC, width = 13, height = 14 },
  PewterCity = { offset = 0x2DE408, width = 48, height = 40 },
  PewterCity_Gym = { offset = 0x2D718C, width = 13, height = 16 },
}

-- Cell-space warps (pret map.json). Engine warps are cells (Gen2 setMap x/y).
Versions.WARPS = {
  SEVII_ONE_ISLAND = {
    { x = 14, y = 5, destMap = "SEVII_ONE_ISLAND_POKECENTER", destWarp = 1 },
    { x = 19, y = 9, destMap = "SEVII_ONE_ISLAND_HOUSE1", destWarp = 1 },
    { x = 8, y = 11, destMap = "SEVII_ONE_ISLAND_HOUSE2", destWarp = 1 },
    { x = 12, y = 18, destMap = "SEVII_ONE_ISLAND_HARBOR", destWarp = 1 },
  },
  SEVII_ONE_ISLAND_POKECENTER = {
    { x = 9, y = 9, destMap = "SEVII_ONE_ISLAND", destWarp = 1 },
    { x = 1, y = 5, destMap = "SEVII_ONE_ISLAND_POKECENTER_2F", destWarp = 1 },
  },
  SEVII_ONE_ISLAND_POKECENTER_2F = {
    { x = 1, y = 6, destMap = "SEVII_ONE_ISLAND_POKECENTER", destWarp = 2 },
  },
  SEVII_ONE_ISLAND_HARBOR = {
    { x = 8, y = 2, destMap = "SEVII_ONE_ISLAND", destWarp = 4 },
  },
  SEVII_ONE_ISLAND_HOUSE1 = {
    { x = 4, y = 7, destMap = "SEVII_ONE_ISLAND", destWarp = 2 },
  },
  SEVII_ONE_ISLAND_HOUSE2 = {
    { x = 4, y = 7, destMap = "SEVII_ONE_ISLAND", destWarp = 3 },
  },
  -- destWarp is 1-based index into the destination map's warp list (pret dest_warp_id + 1).
  FR_PALLET_TOWN = {
    { x = 6, y = 7, destMap = "FR_PLAYERS_HOUSE_1F", destWarp = 2 },
    { x = 15, y = 7, destMap = "FR_RIVALS_HOUSE", destWarp = 1 },
    { x = 16, y = 13, destMap = "FR_OAKS_LAB", destWarp = 1 },
  },
  FR_ROUTE_1 = {
  },
  FR_PLAYERS_HOUSE_1F = {
    { x = 5, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 1 },
    { x = 4, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 1 },
    { x = 10, y = 2, destMap = "FR_PLAYERS_HOUSE_2F", destWarp = 1 },
    { x = 3, y = 9, destMap = "FR_PALLET_TOWN", destWarp = 1 },
  },
  FR_PLAYERS_HOUSE_2F = {
    { x = 10, y = 2, destMap = "FR_PLAYERS_HOUSE_1F", destWarp = 3 },
  },
  FR_RIVALS_HOUSE = {
    { x = 4, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 2 },
    { x = 5, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 2 },
    { x = 3, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 2 },
  },
  FR_OAKS_LAB = {
    { x = 6, y = 12, destMap = "FR_PALLET_TOWN", destWarp = 3 },
    { x = 7, y = 12, destMap = "FR_PALLET_TOWN", destWarp = 3 },
    { x = 5, y = 12, destMap = "FR_PALLET_TOWN", destWarp = 3 },
  },
  -- Pewter outdoor warps (pret map.json; only Gym wired until other interiors extract).
  FR_PEWTER_CITY = {
    { x = 17, y = 6, destMap = "FR_PEWTER_CITY", destWarp = 1 }, -- museum stub
    { x = 25, y = 4, destMap = "FR_PEWTER_CITY", destWarp = 1 },
    { x = 15, y = 16, destMap = "FR_PEWTER_CITY_GYM", destWarp = 1 },
  },
  FR_PEWTER_CITY_GYM = {
    { x = 5, y = 14, destMap = "FR_PEWTER_CITY", destWarp = 3 },
    { x = 6, y = 14, destMap = "FR_PEWTER_CITY", destWarp = 3 },
    { x = 7, y = 14, destMap = "FR_PEWTER_CITY", destWarp = 3 },
  },
}

-- FireRed USA 1.0 — verified against local dump + pret bins.
local FIRERED_10 = {
  id = "firered_1_0",
  game = "firered",
  tilesets = Versions.TILESETS,
  layouts = FIRERED_10_LAYOUTS,
  map_headers = Versions.MAP_HEADERS,
  g_map_groups = Versions.G_MAP_GROUPS,
  num_map_groups = Versions.NUM_MAP_GROUPS,
  ow_gfx_pointers = Versions.OW_GFX_POINTERS,
  ow_sprite_palettes = Versions.OW_SPRITE_PALETTES,
  num_obj_event_gfx = Versions.NUM_OBJ_EVENT_GFX,
}

-- SHA-1 (lowercase) → version table. Engine identity is SHA-1 only.
Versions.BY_SHA1 = {
  ["41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"] = FIRERED_10,
}
-- Legacy MD5 keys retained only for error messages / migration hints.
Versions.BY_MD5 = {
  ["e26ee0d44e809351c8ce2d73c7400cdd"] = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc",
}

-- FRLG (mapGroup, mapNum) → Sevii host map ids (Island 1).
Versions.FRLG_MAP_TO_SEVII = {
  ["3:12"] = "SEVII_ONE_ISLAND",
  ["3:45"] = "SEVII_ONE_ISLAND_KINDLE_ROAD",
  ["3:46"] = "SEVII_ONE_ISLAND_TREASURE_BEACH",
  ["32:0"] = "SEVII_ONE_ISLAND_POKECENTER",
  ["32:1"] = "SEVII_ONE_ISLAND_POKECENTER_2F",
  ["32:2"] = "SEVII_ONE_ISLAND_HOUSE1",
  ["32:3"] = "SEVII_ONE_ISLAND_HOUSE2",
  ["32:4"] = "SEVII_ONE_ISLAND_HARBOR",
}

-- Standalone Fire Red map ids (engine Game3).
Versions.FRLG_MAP_TO_FR = {
  ["3:0"] = "FR_PALLET_TOWN",
  ["3:1"] = "FR_VIRIDIAN_CITY",
  ["3:2"] = "FR_PEWTER_CITY",
  ["3:19"] = "FR_ROUTE_1",
  ["3:20"] = "FR_ROUTE_2",
  ["4:0"] = "FR_PLAYERS_HOUSE_1F",
  ["4:1"] = "FR_PLAYERS_HOUSE_2F",
  ["4:2"] = "FR_RIVALS_HOUSE",
  ["4:3"] = "FR_OAKS_LAB",
  ["6:2"] = "FR_PEWTER_CITY_GYM",
}

-- pret map_groups.json name → existing engine id (keep save / session stable).
Versions.PRET_TO_FR = {
  PalletTown = "FR_PALLET_TOWN",
  ViridianCity = "FR_VIRIDIAN_CITY",
  PewterCity = "FR_PEWTER_CITY",
  Route1 = "FR_ROUTE_1",
  Route2 = "FR_ROUTE_2",
  PalletTown_PlayersHouse_1F = "FR_PLAYERS_HOUSE_1F",
  PalletTown_PlayersHouse_2F = "FR_PLAYERS_HOUSE_2F",
  PalletTown_RivalsHouse = "FR_RIVALS_HOUSE",
  PalletTown_ProfessorOaksLab = "FR_OAKS_LAB",
  PewterCity_Gym = "FR_PEWTER_CITY_GYM",
  OneIsland = "SEVII_ONE_ISLAND",
  OneIsland_KindleRoad = "SEVII_ONE_ISLAND_KINDLE_ROAD",
  OneIsland_TreasureBeach = "SEVII_ONE_ISLAND_TREASURE_BEACH",
  OneIsland_PokemonCenter_1F = "SEVII_ONE_ISLAND_POKECENTER",
  OneIsland_PokemonCenter_2F = "SEVII_ONE_ISLAND_POKECENTER_2F",
  OneIsland_Harbor = "SEVII_ONE_ISLAND_HARBOR",
  OneIsland_House1 = "SEVII_ONE_ISLAND_HOUSE1",
  OneIsland_House2 = "SEVII_ONE_ISLAND_HOUSE2",
}

function Versions.seviiMapFor(group, num)
  return Versions.FRLG_MAP_TO_SEVII[string.format("%d:%d", tonumber(group) or 0, tonumber(num) or 0)]
end

function Versions.frMapFor(group, num)
  local MapCatalog = require("src.import.gba.map_catalog")
  return MapCatalog.mapIdFor(group, num)
    or Versions.FRLG_MAP_TO_FR[string.format("%d:%d", tonumber(group) or 0, tonumber(num) or 0)]
    or Versions.FRLG_MAP_TO_SEVII[string.format("%d:%d", tonumber(group) or 0, tonumber(num) or 0)]
end

function Versions.mapIdFor(group, num)
  return Versions.frMapFor(group, num)
end

function Versions.normalizeSha1(sha1)
  if type(sha1) ~= "string" then return nil end
  return sha1:lower():gsub("%s+", "")
end

--- Canonical FireRed identity SHA-1 (maps legacy MD5 → SHA-1).
function Versions.identitySha1(hash)
  local key = Versions.normalizeSha1(hash)
  if not key or key == "" then return nil end
  if Versions.BY_MD5[key] and type(Versions.BY_MD5[key]) == "string" then
    return Versions.BY_MD5[key]
  end
  return key
end

-- Deprecated alias
Versions.normalizeMd5 = Versions.normalizeSha1

function Versions.lookup(sha1)
  local key = Versions.identitySha1(sha1)
  if not key or key == "" then return nil, "missing sha1" end
  local ver = Versions.BY_SHA1[key]
  if not ver then
    return nil, "unsupported or unknown FireRed dump SHA-1"
  end
  return ver
end

function Versions.lookupSha1(sha1)
  return Versions.lookup(sha1)
end

return Versions
