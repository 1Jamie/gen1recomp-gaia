-- Unit tests for Trainer ROM extraction (AI, 4-tier parties, Flat IV math, Zero EVs, Dialogs).

local Rom = require("src.import.gba.rom")
local Versions = require("src.import.gba.versions")
local TrainerExtract = require("src.import.gba.trainer_extract")
local Trainers = require("src.core.game3.scripting.trainers")

local checksPassed = 0
local function check(cond, msg)
  if not cond then
    error("[FAIL] " .. tostring(msg))
  end
  checksPassed = checksPassed + 1
  print("[ok] " .. tostring(msg))
end

-- Open real ROM if present, or create mock ROM
local romFile = "1636 - Pokemon Fire Red (U)(Squirrels).gba"
local f = io.open(romFile, "rb")
if not f then
  error("ROM file not found for trainer extract test: " .. romFile)
end
f:close()

local fakeImports = {
  info = function(self, id) return { size = 16777216, md5 = "fake" } end,
  read = function(self, id, off, len)
    local rf = io.open(romFile, "rb")
    rf:seek("set", off)
    local data = rf:read(len)
    rf:close()
    return data
  end
}

local rom = assert(Rom.open(fakeImports, "firered"))

print("[test] 1. Trainer Database Extraction & Census")
local pack = TrainerExtract.extract(rom)
check(pack ~= nil, "Trainer pack extracted successfully")
check(pack.trainerCount == 743, "743 trainers extracted (Versions.TRAINERS_COUNT)")
check(pack.classCount == 107, "107 trainer classes extracted (Versions.TRAINER_CLASS_COUNT)")
check(pack.classNames[0] == "PKMN TRAINER" or pack.classNames[0] == "POKéMON TRAINER" or pack.classNames[0] == "", "Class names parsed")

print("[test] 2. The Flat IV Math Trap & Zero EVs")
-- Brock (id 414): rawIv = 0 -> iv = 0
local brock = pack.trainers[414]
check(brock ~= nil, "Leader Brock extracted (id 414)")
check(brock.name == "BROCK", "Brock name matches")
check(brock.partySize == 2, "Brock party size is 2")
check(#brock.party == 2, "Brock party mon count is 2")

local brockGeodude = brock.party[1]
check(brockGeodude.species == 74, "Brock mon 1 is Geodude (species 74)")
check(brockGeodude.level == 12, "Brock Geodude level is 12")
check(brockGeodude.rawIv == 0, "Brock Geodude rawIv is 0")
check(brockGeodude.iv == 0, "Flat IV math for rawIv=0 yields iv=0")
check(brockGeodude.ivs.hp == 0 and brockGeodude.ivs.atk == 0 and brockGeodude.ivs.spe == 0, "Uniform IVs across all stats")
check(brockGeodude.evs.hp == 0 and brockGeodude.evs.atk == 0 and brockGeodude.evs.spe == 0, "Explicit Zero EVs on trainer Pokémon")
check(#brockGeodude.moves == 2 and brockGeodude.moves[1] == 33 and brockGeodude.moves[2] == 111, "Brock Geodude custom moves (Tackle=33, Defense Curl=111)")

local brockOnix = brock.party[2]
check(brockOnix.species == 95, "Brock mon 2 is Onix (species 95)")
check(brockOnix.level == 14, "Brock Onix level is 14")
check(#brockOnix.moves == 3 and brockOnix.moves[1] == 33 and brockOnix.moves[2] == 20 and brockOnix.moves[3] == 317, "Brock Onix custom moves (Tackle=33, Bind=20, Rock Tomb=317)")

-- Giovanni 1 (id 348): rawIv = 250 -> iv = math.floor((250 * 31) / 255) = 30
local giovanni1 = pack.trainers[348]
check(giovanni1 ~= nil, "Giovanni 1 extracted (id 348)")
check(giovanni1.partySize == 3, "Giovanni 1 party size is 3")
local gioOnix = giovanni1.party[1]
check(gioOnix.rawIv == 250, "Giovanni Onix rawIv is 250")
check(gioOnix.iv == 30, "Flat IV math: (250 * 31) / 255 = 30 (not 250 overflow)")
check(gioOnix.ivs.hp == 30 and gioOnix.ivs.def == 30 and gioOnix.ivs.spa == 30, "Flat uniform IVs across all 6 stats = 30")
check(gioOnix.evs.hp == 0 and gioOnix.evs.atk == 0 and gioOnix.evs.spe == 0, "Zero EVs on Giovanni party")

print("[test] 3. 4-Tier Party Struct Formats")
-- Type 0: NoItemDefaultMoves (Giovanni 348)
check(giovanni1.partyFlags == 0, "Giovanni 1 uses partyFlags 0 (NoItemDefaultMoves)")
check(gioOnix.moves == nil, "NoItemDefaultMoves has nil custom moves (uses level-up moves)")

-- Type 1: NoItemCustomMoves (Misty 415)
local misty = pack.trainers[415]
check(misty ~= nil and misty.partyFlags == 1, "Misty uses partyFlags 1 (NoItemCustomMoves)")
check(#misty.party == 2, "Misty party size is 2")
local starmie = misty.party[2]
check(starmie.species == 121 and starmie.level == 21, "Misty mon 2 is Starmie Lv 21")
check(#starmie.moves == 4 and starmie.moves[1] == 129 and starmie.moves[4] == 352, "Starmie custom moves (Swift=129, Water Pulse=352)")

-- Type 3: ItemCustomMoves (Elite Four Lance 413)
local lance = pack.trainers[413]
check(lance ~= nil, "Elite Four Lance extracted (id 413)")
check(lance.partyFlags == 3, "Lance uses partyFlags 3 (ItemCustomMoves)")
check(#lance.party == 5, "Lance has 5 Pokémon")
local dragonite = lance.party[5]
check(dragonite.species == 149 and dragonite.level == 60, "Lance mon 5 is Dragonite Lv 60")
check(dragonite.heldItem == 142, "Lance Dragonite holds Sitrus Berry (item 142)")
check(#dragonite.moves == 4 and dragonite.moves[1] == 63 and dragonite.moves[3] == 200, "Dragonite custom moves (Hyper Beam=63, Outrage=200)")

print("[test] 4. AI Bitmask Decomposition")
check(brock.aiFlags == 7, "Brock aiFlags is 7")
check(brock.ai.checkBadMove == true, "Brock AI: checkBadMove is true")
check(brock.ai.checkViability == true, "Brock AI: checkViability is true")
check(brock.ai.tryToFaint == true, "Brock AI: tryToFaint is true")
check(brock.ai.setupFirstTurn == false, "Brock AI: setupFirstTurn is false")

-- Route trainer (Bug Catcher 102)
local bugCatcher = pack.trainers[102]
check(bugCatcher.aiFlags == 1, "Bug Catcher aiFlags is 1")
check(bugCatcher.ai.checkBadMove == true and bugCatcher.ai.checkViability == false, "Bug Catcher AI: checkBadMove only")

print("[test] 5. The Boss Text Disconnect & Dialogue Extraction")
local MapTree = require("src.import.gba.map_tree")
local MapCatalog = require("src.import.gba.map_catalog")
local ExtractScripts = require("src.import.gba.extract_scripts")

local version = (rom.sha1 and Versions.lookup(rom.sha1)) or select(2, next(Versions.BY_SHA1))
MapCatalog.rebuildIndex()
local census = assert(MapTree.walk(rom, version))
local order, byEngine = MapCatalog.allOrder(census, Versions.SEEDS)
MapCatalog.registerOrder(rom, version, order, byEngine)

local scriptBundle = ExtractScripts.extractFromRom(rom, version)
local dialogPack = TrainerExtract.extract(rom, { scripts = scriptBundle.scripts, text = scriptBundle.text })

-- Standard Route Trainer (Bug Catcher 102)
local bcDialog = dialogPack.trainers[102].dialogs
check(bcDialog.intro ~= nil and bcDialog.intro:find("Hey! You have POKéMON!"), "Standard trainer intro text extracted")
check(bcDialog.defeat ~= nil and bcDialog.defeat:find("CATERPIE can't hack it!"), "Standard trainer defeat text extracted")

-- Boss with trainerbattle 0x3 (Giovanni 348): intro text in preceding message box
local gioDialog = dialogPack.trainers[348].dialogs
check(gioDialog.intro ~= nil and gioDialog.intro:find("I am the leader, GIOVANNI!"), "Boss Text Disconnect: Giovanni 348 intro text extracted from preceding message")
check(gioDialog.defeat ~= nil and gioDialog.defeat:find("WHAT!\nThis can't be!"), "Giovanni 348 defeat text extracted")

-- Boss with trainerbattle 0x1 (Brock 414)
local brockDialog = dialogPack.trainers[414].dialogs
check(brockDialog.intro ~= nil and brockDialog.intro:find("I'm BROCK.\nI'm PEWTER's GYM LEADER"), "Brock intro speech extracted")
check(brockDialog.defeat ~= nil and brockDialog.defeat:find("BOULDERBADGE"), "Brock defeat badge speech extracted")

-- Early Rival (Trainer 326): trainerbattle 0x9
local rivalDialog = dialogPack.trainers[326].dialogs
check(rivalDialog.defeat ~= nil and rivalDialog.defeat:find("I picked the wrong POKéMON!"), "Early rival defeat text extracted")
check(rivalDialog.victory ~= nil and rivalDialog.victory:find("Am I great or what?"), "Early rival victory text extracted")

print("[test] 6. Runtime Trainers Module Interop")
-- Mock cache for Trainers module
local fakeCache = {
  exists = function(self, p) return true end,
  read = function(self, p)
    return TrainerExtract.pack_to_lua and TrainerExtract.pack_to_lua(dialogPack)
      or dofile("/home/autumn/.local/share/love/pokemon-love2d/firered/data/generated/gba/trainers.lua")
  end,
}
Trainers._pack = dialogPack

local foe = Trainers.foeFromId(414)
check(foe ~= nil, "Trainers.foeFromId resolves Brock (414)")
check(foe.trainerName == "BROCK", "foe trainerName is BROCK")
check(#foe.party == 2, "foe.party has 2 Pokémon")
check(foe.party[1].species == 74 and foe.party[1].level == 12, "foe mon 1 is Geodude Lv 12")
check(foe.party[2].species == 95 and foe.party[2].level == 14, "foe mon 2 is Onix Lv 14")
check(foe.party[1].evs.hp == 0 and foe.party[1].evs.atk == 0, "foe mon 1 has 0 EVs")
check(foe.party[1].iv == 0 and foe.party[1].ivs.hp == 0, "foe mon 1 has 0 IVs")
check(foe.aiFlags == 7, "foe aiFlags is 7")

local dialogs = Trainers.dialogs(414)
check(dialogs.intro ~= nil and dialogs.intro:find("PEWTER's GYM LEADER"), "Trainers.dialogs returns Brock intro")

print(string.format("\nAll %d trainer extraction and runtime tests passed successfully!", checksPassed))
