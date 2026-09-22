# RSE seams: FireRed → Ruby/Sapphire/Emerald

**Status:** design + documentation only. No `src/` edits in this pass (Finisher and
Refactor lanes are editing concurrently). Every "patch sketch" below is a proposal
for a later ticket, not applied code.

**Source review:** `/Users/shanemcgovern/Downloads/gen3-review-v3.html`
(sections I, J, route=architecture/migration cards, Handoff).

**Evidence rule:** claims below were re-checked against the working tree on
2026-09-22. Line numbers move; the file + symbol is the durable citation.

**pret grounding (standing rule, 2026-09-22).** Cross-game behaviour below is
grounded in pret; engine file:line is cited for *what this engine does today* and
pret file:line for *what the games do*. Verified this pass:

| Claim | pret citation | Status |
| --- | --- | --- |
| FireRed badge flags 0x820-0x827 | `pokefirered/include/constants/flags.h:1324` (`SYS_FLAGS 0x800`), `:1364-1371` (`FLAG_BADGE01_GET = SYS_FLAGS+0x20` … `08 = +0x27`) | VERIFIED — matches engine `trainer_card.lua:212` exactly |
| Ruby/Sapphire badge flags = base 0x807 | `pokeruby/include/constants/flags.h:779` (`SYSTEM_FLAGS 0x800`), `:789-796` (`+0x07` … `+0x0E`) | VERIFIED — differs from FireRed |
| Emerald badge flags = base 0x867 | `pokeemerald/include/constants/flags.h:1348` (`SYSTEM_FLAGS 0x860`), `:1359-1366` (`+0x7` … `+0xE`) | VERIFIED — differs from both |
| `SPECIES_EGG = 412`, `NUM_SPECIES = 412` in **all** Gen 3 games | `pokefirered/include/constants/species.h:421-423`; `pokeemerald/.../species.h:418-420`; `pokeruby/.../species.h:418,448` | VERIFIED — J7 re-graded, see §2.18 |
| FireRed has 20 heal locations | `pokefirered/src/data/heal_locations.json` (20 `"map"` rows) | VERIFIED — matches engine `heal_locations.lua` BY_ID (20) |
| RSE has 22 heal locations | `pokeemerald/src/data/heal_locations.json`, `pokeruby/src/data/heal_locations.json` (22 rows each) | VERIFIED — per-game table is required (J4) |
| RSE encounter music set differs from FRLG's 6 | `pokefirered/include/constants/songs.h` 6 `MUS_ENCOUNTER*`; `pokeemerald/.../songs.h` 17; `pokeruby/.../songs.h` 17 | VERIFIED — per-game mapping required (J5) |
| FRLG script macros 257 vs Emerald 271 | `pokefirered/asm/macros/event.inc` 257 `.macro`; `pokeemerald/asm/macros/event.inc` 271 | VERIFIED — opcode table deltas exist (§3.5) |
| RSE ships the same font pipeline assets | `graphics/fonts/latin_normal.png` and `latin_small.png` exist in both `pokefirered` and `pokeemerald` (HTTP 200 each, 2026-09-22); Emerald adds `latin_narrow/short/small_narrow` | VERIFIED — the provider seam is path/metrics, not a new renderer (§3.2) |
| 9 FireRed-only features (Fame Checker, Teachy TV, VS Seeker, Trainer Tower, Seagallop, Help, TM Case, Trainer Fan Club, Berry Pouch) | present in local clone `~/dev/pokefirered` @ `c75f35230`; each path 404 in `pokeemerald` **and** `pokeruby` (2026-09-22) | VERIFIED — capability gate, §3.4 |
| 4 RSE-only features (Contests, Secret Bases, Match Call, PokéNav) | 404 in `pokefirered`; `pokeemerald/src/{contest,secret_base,match_call,pokenav}.c` = 200 | VERIFIED — §3.4 |
| Shared, not FireRed-only: Easy Chat, Mystery Gift, Union Room, size records, Battle Tower | `src/{easy_chat,mystery_gift,union_room,pokemon_size_record,battle_tower}.c` exist in **both** repos | VERIFIED — re-graded into `Capabilities.CORE`, §3.4 |
| RSE `items.h` still defines `ITEM_FAME_CHECKER`/`ITEM_VS_SEEKER`/`ITEM_TEACHY_TV` | `pokeemerald/include/constants/items.h` contains all three (2026-09-22) | VERIFIED — item ids are NOT a usable gate; use the capability flag |

**UNVERIFIED in this doc (do not quote as fact):** the exact RSE encounter-music →
song-id mapping (needs `pokeemerald/src/battle_setup.c` + `songs.h`); the Hoenn
region-map page layout (needs `pokeemerald/src/region_map.c` + graphics); the
Ruby/Sapphire script-macro file path (`pokeruby/asm/macros/event.inc` is a 404 as of
2026-09-22, so the opcode source for RS must be located before T4.2); and all
`versions_rse.lua` ROM offsets (needs the actual carts). Each is labelled inline
where it appears.

| Related | File |
| --- | --- |
| House architecture | `docs/architecture.md` |
| Game3 feature docs | `docs/game3/*.md` |
| Test baseline | `docs/game3/test-baseline-v3.md` |
| Version registry | `src/core/GameVersion.lua:22-134` |

---

## 1. Verdict summary

1. **Nothing in sections I/J is already fixed except H1/H2** (link/gameStats save
   serialisation, actioned by the Finisher lane — see §2.11). All ten J findings
   were re-verified in the working tree this pass; J2 is still `"firered"`.
2. **Only three findings actually block RSE**: **J1** (save identity), **J8** (map-id
   namespace), **J10** (mod API dispatch). J7 was re-graded after pret grounding:
   `NUM_SPECIES`/`SPECIES_EGG = 412` is the *same* in FireRed, Emerald and Ruby
   (`pokefirered/.../species.h:421-423`; `pokeemerald/.../species.h:418-420`;
   `pokeruby/.../species.h:418,448`), so it is a low-risk data seam, not a blocker.
   The rest are either data seams (J3–J7, J9) or Gen3 structural debt (I1–I10) that
   makes the port harder but does not prevent it.
3. **The single highest-leverage change is a per-game profile table** read through
   one accessor module. Every J finding except J10 becomes a lookup against that
   profile; J10 becomes a dispatch key instead of `generation == 3`.
4. **The import pipeline is already per-version by construction**:
   `CacheFs.readActive` prefixes every read with `GameVersion.cachePrefix()`
   (`src/import/CacheFs.lua:354-365`), `bootGame` calls `GameVersion.set` +
   `CacheFs.mountVersion` (`main.lua:480-484`), and save files are per-version via
   `saveSuffix` (`src/core/GameVersion.lua:196-197`, `src/core/SaveData.lua:938`).
   Adding `ruby`/`sapphire`/`emerald` rows to `GameVersion.VERSIONS` is therefore
   the correct and cheapest entry point — **not** a new engine.
5. **Do not rename or restructure Gen3 core modules while the fix wave is running.**
   The ticket order in §4 puts all FireRed-identical seams (profile, map ids,
   options, save identity) before any behaviour-changing port work, and each ticket
   has a firered arm that returns today's values verbatim.

---

## 2. Finding dispositions

Legend — **Status**: `ACTIONED` (someone else already fixed it) ·
`CODE` (needs a code change; patch sketch given) · `DESIGN` (needs a design
decision; options + recommendation given).
**Lane**: own lane per the triage rule (Finisher = bugfix/feature/migration,
Refactor = route=refactor, Architect = architecture, QA = tests).

### 2.1 I1 — `gfx.lua` is the Gen 3 UI router misnamed as drawing primitives

**Current state (verified):** `src/core/game3/gfx.lua:1` still says "drawing
primitives"; `:5` requires `display`; `:6-9` require `chrome`, `window`,
`frlg_font`, `stack`; `Gfx.drawUi` (`:70-83` and lazy branches to `:179`) requires
**20 distinct `src.ui.game3.*` modules across 24 UI modules total** — worse than the
finding's 14. `gfx.lua` holds no graphics state; it reads `Stack`/`isOpen()` flags
and dispatches draw calls.

**Status: DESIGN** (Refactor lane). Not RSE-blocking, but every new screen must be
registered here and the screen set is FRLG-specific.

**Options:**
- **(a) Split into `gfx.lua` (primitives) + `ui_router.lua` (`drawUi`)** — keep
  `Gfx.drawUi` as a forwarding alias for one release so no call site changes.
- **(b) Leave as-is and fix the header comment** — zero risk, keeps the misleading
  name.
- **(c) Introduce a screen registry table** (`Screens.DRAW = { message = ..., ... }`)
  that `drawUi` iterates; RSE could override individual rows.

**Recommendation: (a) now, (c) only when a second screen consumer exists.** (a) is a
pure move + alias, testable headless; (c) adds a registry nothing needs yet. Do not
take this while the fix wave is editing `src/ui/game3/*`.

### 2.2 I2 — Core scripting depends on 16 UI screens

**Current state (verified):** `src/core/game3/scripting/adapters.lua` has 34 require
sites into **15 distinct** UI modules (`hall_of_fame:128`, `frlg_font:215`, `hud`
×5, `message` ×8, `choice` ×2, `mon_pic` ×2, `pc_menu:727`, `money_box:751`,
`shop_menu:770`, `fade`, `naming`, `party_menu:1099`, `elevator_window`,
`easy_chat:1174`, `region_map:1399`). The whole `scripting/` tree reaches **28**
distinct UI modules. `ops_a.lua:7` requires `natives.lua`, which lazily reaches UI
at `natives.lua:99/126/344/633/681`.

**Status: DESIGN** (Architect lane; this is the top porting cost, not a boot blocker).

**Options:**
- **(a) Screen port table**: `scripting/screens.lua` exposes `Screens.get("party_menu")`
  with a default table; RSE swaps rows. Mechanically large (34 call sites) but
  behaviour-preserving and testable.
- **(b) Do nothing now**; RSE reuses the FRLG screens as-is where semantics match
  (party menu, bag, PC are mechanically identical) and only diverges for FRLG-only
  screens (Fame Checker, Teachy TV, Trainer Tower records).
- **(c) Full decoupling** (VM emits UI intents; a presenter consumes them) — a
  rewrite, not a port.

**Recommendation: (b) for the first RSE milestone, (a) for the second.** The 28
screens split roughly into "identical GBA mechanics" (majority) and "FRLG-only"
handled by §3.4 capability flags. Reserve (a) for the modules the RSE port actually
diverges on, so the change is demand-driven.

### 2.3 I3 — `display ⇄ gfx`, plus `display → ui.help_system`

**Current state (verified):** `display.lua:257/273/371` require `gfx`;
`display.lua:258/269/355` require `ui/game3/help_system`; `gfx.lua:5` requires
`display`. All `display → gfx/help` requires are function-local
(`composeHardware`/`presentUi`), so this is a lazy cycle, not a load-order failure.

**Status: DESIGN** (Refactor lane). Not RSE-blocking.

**Patch sketch:** move the `help_system` draw call out of `display.lua` into
`gfx.drawUi` (which already owns UI draw order), leaving `display` a pure
BG/OAM compositor that takes a widget callback. `display` keeps only the
`gfx`-for-dimensions dependency, or receives dimensions as arguments.

**Recommendation: defer** until after the RSE profile lands. The help overlay is
gated by a capability flag anyway (§3.4); removing the require is then a small
follow-up with `tests/game3_help_test.lua` as the guard.

### 2.4 I4 — `hud ⇄ runtime`

**Current state (verified):** `src/ui/game3/hud.lua:279` (and `:351`) require
`src.core.game3.runtime`; `runtime.lua` requires `hud` at `:59`, `:230`, `:291`,
`:475`, `:483`, `:505`. All function-local.

**Status: DESIGN** (Refactor lane). Not RSE-blocking.

**Patch sketch:** invert the second edge — `runtime` should not require HUD; expose
the state HUD needs as a query table (`Runtime.hudState()`) that `hud` reads, and let
the field view call `Hud.refresh(...)` explicitly. Alternatively register HUD via
`ModRuntime`-style event hooks.

**Recommendation: defer.** Cosmetic for the port. HUD is FRLG-specific only in its
layout data, not its mechanics.

### 2.5 I5 — The whole Gen 3 tree is one 102-module SCC

**Current state (verified):** no committed SCC tool under `tools/` or `tests/`. The
only committed analysis is `graphify-out/GRAPH_REPORT.md:279-281` ("Import Cycles —
None detected"), whose AST cache omits the function-local `display → gfx` edge, so
it cannot refute a lazy-require SCC. Module counts: **310** Lua modules in the Gen3
tree (244 under `src/core/game3`, 66 under `src/ui/game3`). The specific number
"102" is **unverified**.

**Status: DESIGN** (Architect lane). Not RSE-blocking.

**Options:**
- **(a) Commit a tiny SCC checker** (`tools/scc.py`, ~80 lines: Tarjan over
  `require("…")` matches) and record the real number in this doc. Cheap, repeatable,
  prevents future drift.
- **(b) Treat the claim as advisory and proceed.**

**Recommendation: (a), but not as a gate.** A committed count turns a review opinion
into a regression signal; running it non-blocking in CI costs nothing. Do not spend
port effort reducing the SCC — the seams in §3 do that incidentally.

### 2.6 I6 — Additional load-order cycles outside Gen 3

**Current state (verified):** all five pairs still exist.
`Data.lua:262 → CacheFs.lua:231 → SaveData.lua:20 → Bag.lua:32 → Data.lua`
(the `SaveData → Bag` edge at `SaveData.lua:20` is the only **top-level** one);
`ChipAudio.lua:625 → SessionLifecycle.lua:77-78 → Music.lua:80 → ChipAudio`;
`DeltaSkin.lua:2 ↔ TouchSkin.lua:390`; `dex.lua:135 ↔ pokedex_data.lua:5`;
`natives_queries.lua:366 ↔ storage.lua:327`.

**Status: CODE** (Refactor lane) — one tiny, low-risk change; the rest are hazards
worth a comment, not a rewrite.

**Patch sketch:** make `SaveData.lua:20` lazy:
`local function bag() return require("src.modules.Bag") end` and replace
top-level uses. Leave the other four pairs: every edge there is function-local and
breaking them needs module surgery.

**Recommendation: take the `SaveData → Bag` de-eager-ing only.** It removes the one
edge that can actually bite on boot order. Guard with `./scripts/test.sh` (T1/T2)
plus `tests/engine/game3_*.lua`.

### 2.7 I7 — `import/gba` metadata cycle

**Current state (verified):** `versions.lua:2392` requires `map_catalog`;
`map_catalog.lua:4` requires `versions` (top-level) and `:104` requires `map_tree`;
`map_tree.lua:4` requires `versions`, `:5` requires `extract_map_events`;
`extract_map_events.lua:4` requires `versions`.

**Status: CODE** (Architect lane → lands inside migration ticket **T6.3**). It does
not block RSE (the extractor runs with the active game pinned), but the FRLG-named
tables are exactly the data a second game must replace.

**Patch sketch:** introduce a `Versions.game(id)` selector and split per-game tables
out of the monolith (`versions_firered.lua`, `versions_rse.lua`), keeping
`Versions` as a facade so the ~70 requiring files are untouched. Move the
`map_catalog` require inside the function that needs it (already function-local at
`:2387`; the cycle is entered through `map_catalog → versions` at module scope).

**Recommendation: fold into T6.3** rather than a standalone refactor — same files,
one review.

### 2.8 I8 — `runtime → extractor → runtime` (RSE-relevant)

**Current state (verified):** `encounters.lua:659` requires `pokemon` (inside
`mod_encounter`, function-local); **`pokemon.lua:3` requires
`src.import.gba.extract_island1` at module scope**; that module uses only
`Extract.CACHE_ROOT` (5 sites: `:38`, `:152`, `:239`, `:1251`, `:1454`);
`extract_island1.lua:336` requires `extract_scripts`; `extract_scripts.lua:454`
requires `src.core.game3.encounters` and calls `installEncounterTypes`.

**Status: CODE** (Architect lane → lands inside **T6.2/T6.3**). This is the one cycle
that makes "load the runtime" pull the whole ROM extractor, which is exactly the
thing a standalone RSE runtime must avoid.

**Patch sketch (exact):**
1. New `src/import/gba/cache_paths.lua` with zero requires:
   `return { CACHE_ROOT = "data/generated/gba", NATIVE_ROOT = "data/generated/gba/native" }`.
2. `extract_island1.lua` reads/writes `CachePaths.CACHE_ROOT` (keep
   `Extract.CACHE_ROOT` as a forwarding reference for external setters, or have
   `dataset.mountExtractRoots` set `CachePaths` and mirror onto `Extract`).
3. `pokemon.lua:3` replaces
   `local Extract = require("src.import.gba.extract_island1")` with
   `local CachePaths = require("src.import.gba.cache_paths")`, and the 5
   `Extract.CACHE_ROOT` reads become `CachePaths.CACHE_ROOT`.

**Non-regression argument:** the only value crossing the edge is a string path that
`Dataset.mountExtractRoots()` (`dataset.lua:275-283`) already sets from
`POKEPORT_GBA_CACHE` / `"data/generated/gba"`. Guard with
`tests/engine/game3_cache_module_sandbox_test.lua`, `tests/game3_cache.lua`, and a
new `tests/engine/game3_pokemon_no_extractor_require_test.lua` asserting
`package.loaded["src.import.gba.extract_island1"] == nil` after requiring
`src.core.game3.pokemon` with a stubbed cache.

### 2.9 I9 — Extractor reaches into `src.world.gen2` runtime

**Current state (verified):** `src/import/gba/native_pack.lua:407` requires
`src.world.gen2.Permissions` (for `isLedge`/`isWalkable`), `:412` requires
`src.core.game3.scripting.collision` (calls `seed("BLOCKED")`).

**Status: CODE** (Architect lane → **T6.3**). Not RSE-blocking; the Gen2 permission
table is being used as a generic movement oracle.

**Patch sketch:** pass a permissions table into the pack call
(`NativePack.pack(rom, game, permissions, collisionSeed)`) and have
`extract_island1` supply the Gen3 classifier directly. Delete the
`world.gen2` require. Behaviour identical for FireRed because the caller passes the
same table today.

### 2.10 I10 — Duplicated responsibility: three collision modules, two `bg` modules

**Current state (verified): the modules are different layers, not duplicates.**

| Module | Lines | Role | Used by |
| --- | --- | --- | --- |
| `src/core/game3/collision.lua` | 1291 | Gen3 runtime field grid, warps/doors/ledges/connections | `player.lua:5`, `field.lua:62`, `map.lua:379`, many tests |
| `src/core/game3/scripting/collision.lua` | 174 | Extract-time FRLG metatile-behaviour → Gen2 COLL classifier (`classify`/`seed`/`fromCell`) | `extract_island1.lua:9`, `native_pack.lua:412`, `core/game3/collision.lua:155` |
| `src/world/Collision.lua` | 98 | Gen1/2 host movement verdict + `movement.collision` hook | `src/world/*`, `script/Commands.lua:8` |
| `src/core/game3/bg.lua` | 293 | GBA BG0-BG3 layer state/priority/scroll/draw | `display.lua`, `Game3.lua:71`, title/intro |
| `src/core/game3/battle/bg.lua` | 273 | Battle terrain id → sheet selection | `battle/ui.lua:18`, `engine.lua:108`, `init.lua:507` |

**Status: DESIGN** (Refactor lane). Naming problem, not logic duplication.

**Recommendation: rename only, in a quiet window:**
`scripting/collision.lua` → `scripting/metatile_classify.lua` (12 call sites) and
`battle/bg.lua` → `battle/terrain_bg.lua`. Add a header comment to
`world/Collision.lua` stating it is the Gen1/2 verdict module. Zero behaviour change.

### 2.11 H1/H2 — `gameStats`, `linkBattleRecords`, `trainerCard` persistence

**Status: ACTIONED by the Finisher lane** (verified in the working tree after the
review was generated):

- `save_schema_firered.lua:228` writes `gameStats`, `:295` restores it.
- `:231` / `:297` write+restore `linkBattleRecords`; `:232` / `:298` the same for
  `trainerCard`.
- Hall-of-Fame block `:235-241` / `:300-306` also present.

Guards exist: `tests/engine/game3_gamestats_persistence_test.lua`,
`tests/engine/game3_link_records_persistence_test.lua`,
`tests/engine/game3_hall_of_fame_save_test.lua`. **No action; keep these keys in any
schema split (T0.2).**

### 2.12 J1 — FireRed conflation at the save layer

**Current state (verified):**
- `save_schema_firered.lua:115-116` stamps `engine = "game3"`,
  `version = opts.version or "firered"` in `newGame` — reads `opts`, never
  `session.version`.
- `:189-190` `toSaveTable` hardcodes `engine = "game3"`, `version = "firered"`
  unconditionally.
- `:258-311` `fromSaveTable` never copies `save.version` into the session, so any
  loaded save is re-stamped FireRed on the next write.
- `src/core/SaveData.lua:1132` detects Gen3 via `save.version == "firered"` in the
  slot-summary path (plus the other generational checks).
- `src/core/Game3.lua:46` gates Continue on `save.map:sub(1, 3) == "FR_"`;
  `:372` only checks `engine == "game3"`.

**Status: CODE — the #1 RSE blocker.**

**Patch sketch (three parts, same ticket):**

```lua
-- save_schema_firered.lua → save_schema_game3.lua (alias kept, 45 Lua require sites)
function Schema.newGame(opts)
  local profile = Profile.active()
  ...
  version = opts.version or profile.id,
function Schema.toSaveTable(session)
  local profile = Profile.of(session.version or Profile.active().id)
  ...
  version = profile.id,
function Schema.fromSaveTable(save)
  local profile = Profile.of(save.version)          -- unknown → active, warn once
  session.version = profile.id                        -- NEW: round-trip
```

```lua
-- SaveData.lua:1132 — do not key Gen3 off one game id
local gen3 = save.generation == 3
  or (vinfo and vinfo.generation == 3)
  or (save.engine == "game3") or false
```

```lua
-- Game3.lua:46 — the map namespace decides, not the prefix literal
return save.engine == "game3" and type(save.map) == "string"
  and MapIds.isGame3Map(save.map)
```

`Game3.lua:384` ("Refuse Sevii leftovers") becomes a profile call:
`Profile.of(session.version).map.legacyPrefixes` — for FireRed this stays
`{ "SEVII_" }`, so the refusal is unchanged.

**Non-regression argument:** every branch has an identical firered arm; the only
observable change for FireRed is that `session.version` now round-trips (it was
already `"firered"` in every existing save). Guard:
`tests/engine/game3_gamestats_persistence_test.lua`,
`tests/game3_save_pokeball_test.lua`, `tests/game3_stitchsave_schema_fields_test.lua`,
plus a new `tests/engine/game3_save_version_roundtrip_test.lua`.

### 2.13 J2 — Option block hardcoded to `"firered"`

**Current state (verified):** `options.lua:5` `Options.BLOCK = "firered"`; internal
users only (`:43` read, `:46` create, `:76` detect); no other `src/` file reads the
key directly. **RSE reads/overwrites FireRed's text speed, battle scene, frame and
void-fill in one store.**

**Status: CODE — small, self-contained.**

**Patch sketch:**

```lua
function Options.block(engine, blockId)
  blockId = blockId or Profile.optionsBlock()      -- Profile.active().optionsBlock
  local o = engine[blockId]
  ...
end
```

`Options.bind(session, engine)` resolves the block id from
`Profile.of(session.version)`; `Options.ensure(session)` uses
`Profile.active().optionsBlock`. FireRed resolves to `"firered"` — byte-identical.
**Add a one-time forward migration**: if a legacy engine-options file has
`firered` but the active game differs, leave it alone (RSE starts fresh); only the
firered row may read the legacy key. Guard: new
`tests/engine/game3_options_block_test.lua` (bind under `firered` ≠ bind under a
fixture `ruby` row), plus `./scripts/test.sh`.

### 2.14 J3 — Kanto badge ids and names welded into UI

**Current state (verified):** `src/ui/game3/trainer_card.lua:212-213`
`BADGE_FLAGS = { 0x820, … }` / `BADGE_NAMES = { "BOULDER", … }`; `:234-236` derives
the flag and formats `"FLAG_BADGE0%d_GET"`. `Flags.BADGES` already exists
(`src/core/game3/scripting/flags.lua:81-90`, extracted from `FlagsTable`) but the
trainer card ignores it.

**Status: CODE** (Finisher lane; Wave 2 ticket **T2.1**).

**pret grounding (2026-09-22):** badge flags are 8 per game but the base differs —
FireRed `0x820` (`pokefirered/include/constants/flags.h:1324,1364-1371`),
Ruby/Sapphire `0x807` (`pokeruby/include/constants/flags.h:779,789-796`), Emerald
`0x867` (`pokeemerald/include/constants/flags.h:1348,1359-1366`). Badge *names*
(STONE, KNUCKLE, …) are game string data, not pret constants, so they come from the
extracted pack; the profile carries the fallback.

**Patch sketch:** profile gains `badges = { count = 8, flagBase = 0x820, names = {…} }`;
`trainer_card.lua` reads `Profile.of(session.version).badges`, preferring
`Flags.BADGES[i]` (extracted) over the profile names when present. Hoenn's 8 badges
have different flags/names and the same count, so the loop shape is unchanged.
Guard: `tests/game3_trainer_card_layout_test.lua`,
`tests/game3_save_trainer_card_test.lua`, new
`tests/engine/game3_badge_provider_test.lua`.

### 2.15 J4 — Whiteout/heal destinations are an FRLG-only table

**Current state (verified):** `heal_locations.lua:8-10` `fr_center()` builds
`FR_<CITY>_POKEMON_CENTER_1F`; `:14-51` `BY_ID` has **20** entries, index 14 is
`SEVII_ONE_ISLAND_POKECENTER`; `:126-134` `get(id)` prefers the baked
`<cache>/region_map/heal_locations.lua` and falls back to `BY_ID`; there is no game
parameter. Callers: `field.lua:1381` / `:1445`, `bridge.lua:82`.

**Status: CODE** (Wave 2 ticket **T2.2**).

**pret grounding (2026-09-22):** FireRed has **20** heal locations
(`pokefirered/src/data/heal_locations.json`, 20 rows — matches the engine's 20-entry
BY_ID); Ruby/Sapphire and Emerald have **22**
(`pokeruby/src/data/heal_locations.json`, `pokeemerald/src/data/heal_locations.json`).
The index order differs, so a per-game table is required, not a rename.

**Patch sketch:** rename the constant table to `BY_ID_FIRERED` and add
`HealLocations.for(session)` returning the table named by
`Profile.of(session.version).heal.table` (or the baked cache table, which is
already per-game because `readActive` applies the prefix). `get(id, gameId)` becomes
`get(id, session)`. Callers pass the session, which they all have. Hoenn's
`HEAL_LOCATION_*` order differs from FRLG's, so the RSE table is mandatory — but the
cache loader already does the right thing once a `ruby/` prefix exists.
Guard: `tests/game3_stitchcoll_dynamic_warp_test.lua`, `tests/game3_field_safari_test.lua`,
new `tests/engine/game3_heal_provider_test.lua`.

### 2.16 J5 — Trainer encounter music + rival fallbacks are FRLG class ids

**Current state (verified):** `scripting/trainers.lua:11-13` rival constants
326/327/328; `:22-41` `FALLBACK_TRAINERS` hardcode `class=81`, `pic=106`,
`name="TERRY"`; `:328-341` `getEncounterMusic` maps FRLG
`TRAINER_ENCOUNTER_MUSIC_*` to FRLG songs 283/284/285; `:345-353` battle music
class ids 90/84/87; `:357-363` victory class 84/90. Per-trainer rows come from the
single cache `data/generated/gba/trainers.lua:57`.

**Status: CODE** (Wave 2 ticket **T2.3**). RSE classes/song ids differ, so this is a
real correctness seam, not just cosmetics.

**pret grounding (2026-09-22):** FireRed defines 6 `MUS_ENCOUNTER*` constants
(`pokefirered/include/constants/songs.h`); Emerald and Ruby/Sapphire define 17 each
(`pokeemerald/include/constants/songs.h`, `pokeruby/include/constants/songs.h`).
The engine's 3-way mapping (girl/rocket/boy) is an FRLG simplification. **The exact
RSE code→song map is UNVERIFIED** — it needs
`pokeemerald/src/battle_setup.c` (`PlayTrainerEncounterMusic`) plus `songs.h`; do
not invent it in T2.3.

**Patch sketch:** move the four literal tables (`RIVAL_IDS`, `FALLBACK_TRAINERS`,
`ENCOUNTER_MUSIC`, `BATTLE_MUSIC`, `VICTORY_MUSIC`) into the profile
(`trainers = { rivalIds = …, fallback = …, music = { encounter = …, battle = …, victory = … } }`).
`getEncounterMusic` becomes `Trainers.getEncounterMusic(id, session)`. Guard:
`tests/game3_special_handlers_test.lua` (PlayTrainerEncounterMusic),
`tests/game3_trainer_card_layout_test.lua`, plus a new
`tests/engine/game3_trainer_music_profile_test.lua`.

### 2.17 J6 — Pokédex area map defaults to Kanto and reads FireRed's map groups

**Current state (verified):** `pokedex_data.lua:113-115` `getAreaMapKey` falls back
to `"kanto"`; `:124` hardcodes
`load_lua("src/import/gba/map_groups_firered.lua")` (that is the only
`map_groups_*` file in the tree); `:153` strips `^FR_`/`^SEVII_`; `:283-286`
`numerical_kanto` / `Dex.KANTO_MAX or 151`. Area marker data itself comes from the
active cache (`<prefix>/pokemon/pokedex/area_markers.lua`), so only the join key and
the default are FRLG-pinned.

**Status: CODE** (Wave 2 ticket **T2.4**).

**Patch sketch:** profile gains
`dexArea = { defaultKey = "kanto", mapGroups = "src.import.gba.map_groups_firered", dexMax = 151, stripPrefixes = { "FR_", "SEVII_" } }`.
`getAreaMapKey` takes the profile (or session) and uses `dexArea.defaultKey`;
`:124` resolves `dexArea.mapGroups`; `:153` uses `dexArea.stripPrefixes`. Hoenn adds
`map_groups_rse.lua` and `dexArea = { defaultKey = "hoenn", dexMax = 202 }`.
Guard: `tests/game3_pokedex_area_test.lua`, `tests/game3_pokedex_area_chrome_test.lua`,
`tests/game3_national_dex_test.lua`.

### 2.18 J7 — Internal species/form shape pinned to FRLG's 412

**Current state (verified):** `pokemon.lua:510` `Pokemon.SPECIES_EGG = 412`, `:1246`
literal `mon.species == 412`; `battle/pic_coords.lua:417` `[412] = 20` (front) and
`:832` `[412] = 10` (back), both tables spanning 0-412; `pokemon_extract.lua:1112`
and `:1171` use `(Versions.NUM_SPECIES or 412)`; `versions.lua:88` flat
`NUM_SPECIES = 412`.

**pret re-grade (2026-09-22): the "412" is not a FireRed number.**
`pokefirered/include/constants/species.h:421-423`,
`pokeemerald/include/constants/species.h:418-420` and
`pokeruby/include/constants/species.h:418,448` all define `SPECIES_EGG 412` and
`NUM_SPECIES SPECIES_EGG`. Species ids 277-412 are the Hoenn set in every Gen 3
game. The review's impact claim ("wrong form/pic data for RSE") therefore does not
follow from the constant; the real per-game divergence is the **regional dex**
(Kanto 151 vs Hoenn 202) and any generated table that enumerates only one region.

**Status: CODE (low severity, downgraded from RSE blocker).**

**Patch sketch:**
- Profile gains `species = { num = 412, egg = 412 }` (already in
  `profiles/firered.lua`). Keep it as an assertion source, not a fork point.
- `pokemon.lua`: replace the two literals with
  `Pokemon.speciesEgg()` reading `Profile.of(session and session.version).species.egg`,
  keeping `Pokemon.SPECIES_EGG` as a deprecated field for the existing suites.
- `pokemon_extract.lua`: keep `or 412` but add a bounds assertion
  `species <= Profile.active().species.num` so a future cart with a different count
  fails loudly instead of silently.
- `pic_coords.lua` is generated data — do not hand-edit. Verify (T6.4) that the
  extracted RSE pic-size tables cover 0-412; the FRLG tables already span the same
  id range, but pic dimensions per species come from each game's ROM.
- The **Hoenn dex split** is `dexArea.dexMax = 202` (`pokeemerald` Hoenn dex runs
  1-202 per `HOENN_DEX_*` in the same file), handled in T2.4, not here.

Guard: `tests/game3_national_dex_test.lua`, `tests/game3_growth_evolution_test.lua`,
`tests/game3_battle_forms_intro_test.lua`.

### 2.19 J8 — "Game3 map" is defined as the `FR_`/`SEVII_` namespace

**Current state (verified):** `map_ids.lua:5-15` accepts only `FR_`/`SEVII_` plus an
optional `MapCatalog.isKnown` fallback; `Game3.lua:384` refuses any `SEVII_` save
map; `Game3.lua:46` requires `FR_`. Other prefix tests:
`heal_locations.lua:9`, `encounters.lua:282/286`, `doors.lua:149/182/188`,
`encounters_extract.lua:120/128/171`, `map_sections_extract.lua:307/338/339`,
`map_catalog.lua:25`, `src/mods/Gen3Compat.lua:91` (`MAP_PREFIX = "FR_"`).

**Status: CODE — an RSE blocker** (Wave 1 ticket **T1.2**).

**Patch sketch:**

```lua
-- src/core/game3/map_ids.lua
function MapIds.isGame3Map(mapId)
  if type(mapId) ~= "string" then return false end
  for _, prefix in ipairs(Profile.active().map.prefixes) do
    if mapId:sub(1, #prefix) == prefix then return true end
  end
  local ok, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if ok and MapCatalog and MapCatalog.isKnown then return MapCatalog.isKnown(mapId) end
  return false
end
```

`map_catalog.pret_to_engine` (`:13-26`) hardcodes `"FR_" .. s`; take the prefix from
`Profile.active().map.enginePrefix`. `doors.lua` uses the prefix to select door
sheets — route those through the profile too (FireRed unchanged). Design decision
recorded here: **keep engine map ids prefixed per game** (`FR_`, `RS_`, `E_`) rather
than renaming to a neutral `HOENN_` only — prefix tests stay cheap and save files
remain self-describing. Guard: `tests/game3_map_onload_test.lua`,
`tests/game3_doors_table_test.lua`, `tests/game3_doors_viewport_test.lua`,
`tests/engine/game3_map_section_unresolved_test.lua`.

### 2.20 J9 — Region-map switch button hardwired to a Sevii flag

**Current state (verified):** `src/ui/game3/region_map.lua:410`, inside
`permission()` (`:407-414`):
`if name == "switchButton" and not RegionMap.isFlagSet("FLAG_SYS_SEVII_MAP_123") then return false end`.

**Status: CODE** (Wave 3 ticket **T3.3**).

**Patch sketch:** profile gains `regionMap = { switchFlag = "FLAG_SYS_SEVII_MAP_123", pages = "data/generated/gba/region_map/…" }`.
`permission()` reads `Profile.of(session.version).regionMap.switchFlag`; `nil` means
"no switch button" (Hoenn has one paged map, so nil is correct there, not a
different flag). Guard: `tests/game3_region_map_assets_test.lua` + new
`tests/engine/game3_region_map_permission_test.lua`.

### 2.21 J10 — The mod API treats `generation == 3` as exactly one engine

**Current state (verified):** `src/mods/Loader.lua:1666-1668` selects
`src.battle.game3.BattleAPI` when `loader.generation == 3`; `:1678-1680` the same
for `src.world.game3.WorldAPI`; `:1878` routes to `Schemas.bindGen3`.
`src/mods/Schemas.lua:896-904` binds `gen3Pokemon → src.core.game3.pokemon`,
`gen3Moves → …battle.moves`, `gen3Items → …items_data`,
`gen3Encounters → …encounters`, `gen3Trainers → …scripting.trainers`
(`gen3Text`/`gen3Scripts` have no live module); content map `:646-662`, routing
`:670`.

**Status: ACTIONED (T7.1, 2026-09-22)** — see §3.7. RSE-blocking only for mods that
opt into Gen3 surfaces; no vanilla behaviour depends on it.

**Patch sketch:** dispatch on `(generation, versionId)`:
`LOADER_ENGINE["game3:" .. loader.version] or LOADER_ENGINE["game3"]` and a parallel
row in `Schemas`. The `gen3*` facade names stay stable (mods already depend on
them), so the change is a lookup-table widening, not an API break. Guard:
`tests/engine/game3_mod_names_survive_reload_test.lua`, `tests/run_modkit.lua`
(T4, 37 suites).

---

## 3. Cross-game seam design for Ruby/Sapphire/Emerald

### 3.0 Principle

One process runs one active game (as with Red/Blue/Gold). The port must therefore:

1. keep **identity** in `GameVersion` (sha1, cache prefix, save suffix, engine),
2. keep **behaviour that differs by game** in one profile table per game,
3. keep **engine code shared** and read the profile at the seams below,
4. make every seam's FireRed arm return today's constant, so the FireRed build is
   byte-for-byte equivalent until an RSE row is added.

**Do not** fork `src/core/game3` into `src/core/game3rse`. The shared surface is
~90% of the tree (battle core, scripting VM, bag/party/storage, menus, audio,
save shape); a fork doubles the fix wave.

### 3.1 The profile (replaces `save_schema_firered.lua` hardcoding)

**Options considered:**

| Option | Where the data lives | Pros | Cons |
| --- | --- | --- | --- |
| A. `GameVersion.VERSIONS[id].game3 = {…}` | `GameVersion.lua` | one source of truth; already zero-require | GameVersion must stay dependency-free (loads in `love.conf`); bloats the version table |
| B. `src/core/game3/profiles/<id>.lua` + `profile.lua` selector | new folder | Gen3-only deps allowed; one file per game = clean review surface; lazy require | two registries to keep in sync (id list) |
| C. Extend `src/import/gba/versions.lua` | versions monolith | already the ROM-offset home | 2434 lines flat FRLG data; 70 require sites; wrong layer (extract-time, not runtime) |

**Recommendation: B, with A only for the id/label/cachePrefix/saveSuffix identity
that already lives there.** The selector guards against drift by validating that the
profile's `id` matches the requested key and logs once on mismatch.

```
src/core/game3/profile.lua            -- selector + fail-closed resolution
src/core/game3/profiles/firered.lua   -- today's constants, verbatim
src/core/game3/profiles/ruby.lua      -- (later)
src/core/game3/profiles/sapphire.lua  -- (later)
src/core/game3/profiles/emerald.lua   -- (later)
```

```lua
-- src/core/game3/profile.lua
local GameVersion = require("src.core.GameVersion")
local Profile = {}
local FALLBACK, cache, warned = "firered", {}, {}
local function load(id)
  local ok, row = pcall(require, "src.core.game3.profiles." .. id)
  if ok and type(row) == "table" and row.id == id then return row end
  return nil
end
function Profile.of(id)                -- id = version id from GameVersion or save.version
  if type(id) ~= "string" then return Profile.active() end
  local row = cache[id] or load(id)
  if row then cache[id] = row; return row end
  if not warned[id] then                 -- fail closed, loudly, once
    warned[id] = true
    print("[game3/profile] no profile for '" .. id .. "'; using " .. FALLBACK)
  end
  return Profile.active()
end
function Profile.active()
  local id = GameVersion.generation() == 3 and GameVersion.get() or FALLBACK
  if cache[id] then return cache[id] end
  local row = load(id) or load(FALLBACK)
  if not row then error("game3 profile missing: " .. id .. " and " .. FALLBACK) end
  cache[id] = row
  return row
end
return Profile
```

**Implemented 2026-09-22 (T0.1), with one rename:** `Profile.for` is a Lua syntax
error (`for` is a keyword), so the accessor is **`Profile.of(id)`**. The shipped
module (`src/core/game3/profile.lua`) matches the sketch above and adds
`Profile.has(session, cap)`, `Profile.capabilitiesFor(session)`,
`Profile.isGame3Version(id)` and `Profile.reset()` (test hook).

**Profile row shape (firered values shown; each is today's constant):**

```lua
return {
  id = "firered",
  map = {
    prefixes = { "FR_", "SEVII_" },  -- is_game3_map membership
    enginePrefix = "FR_",            -- map_catalog synthesis
    legacyPrefixes = { "SEVII_" },   -- Game3:384 "refuse leftovers"
    newGameStart = { map = "FR_PLAYERS_HOUSE_2F", x = 6, y = 6, facing = "down",
                     healMap = "FR_PLAYERS_HOUSE_1F", healX = 8, healY = 5 },
  },
  saveRules = "src.core.game3.profiles.firered_rules", -- safari reset, metLocation 88, mail/questlog
  optionsBlock = "firered",
  font = { module = "src.ui.game3.frlg_font", widths = "chrome/fonts/latin_widths.lua" },
  species = { num = 412, egg = 412 },
  dexArea = { defaultKey = "kanto", mapGroups = "src.import.gba.map_groups_firered",
              dexMax = 151, stripPrefixes = { "FR_", "SEVII_" } },
  badges = { count = 8, flagBase = 0x820, names = { "BOULDER", … } },
  heal = { table = "firered" },       -- BY_ID_FIRERED / baked cache
  trainers = { rivalIds = { 326, 327, 328 }, fallback = {…},
               music = { encounter = {…}, battle = {…}, victory = {…} } },
  regionMap = { switchFlag = "FLAG_SYS_SEVII_MAP_123" },
  capabilities = { fameChecker = true, teachyTV = true, vsSeeker = true,
                   trainerTower = true, seagallop = true, unionRoom = true,
                   mysteryGift = true, helpSystem = true, easyChat = true,
                   braille = true, tmCase = true, berryPouch = false },
  nativeModules = { "natives_fame", "natives_tower", "natives_seagallop", … },
  extractors = { … },                 -- aux extract list, §3.6
}
```

**Save schema split (the J1 fix, and the answer to "replacing
`save_schema_firered.lua` hardcoding"):**

```
src/core/game3/save_schema_game3.lua        -- shared fields + hooks (profile-aware)
src/core/game3/profiles/firered_rules.lua   -- FRLG repair: safari flag/VAR, MAPSEC 88,
                                            --   new-game starter item, HoF block
src/core/game3/save_schema_firered.lua      -- thin alias: require(save_schema_game3)
```

The alias matters: **45 Lua files** require `save_schema_firered` (tests, drivers,
save editor). Renaming in one commit is a large, needless diff; alias now, rename in
a later sweep when the fix wave is done.

Profile-owned rules that today live in the schema:
- `reset_state_on_continue` (`save_schema_firered.lua:57-63`: `FLAG_SYS_SAFARI_MODE`
  0x800, `VAR_MAP_SCENE_FUCHSIA…` 0x406E, `session.safari = nil`) → `firered_rules`.
- `repair_own_mon` `metLocation = MAPSEC_PALLET_TOWN` (88) at `:78-89` →
  `firered_rules` (`metLocationDefault`).
- `newGame` starter Potion (`:160`, item 13), `easyChatProfile` defaults,
  `trainer_fan_club.reset`, `SizeRecord.initHeracrossSizeRecord` → profile hooks
  (`newGameExtras`) so RSE can omit FRLG-only records.

### 3.2 Font provider behind the `FrlgFont` seam

**Finding:** `src/ui/game3/frlg_font.lua` (927 lines) is required **directly** by 48
files (577 `FrlgFont.` references, 60 require lines). There is no provider today;
`src/render/Font.lua` is the Gen1/2 equivalent and is unrelated.

**Good news (verified):** the font pipeline is already **data-driven from the active
cache** — `ensure()` loads widths from `CacheFs.readActive("data/generated/gba/chrome/fonts/latin_widths.lua")`
(`frlg_font.lua:319-335`) and atlas pages via `loadImage(FG_PATHS)` (`:239-297`,
paths resolved through `CacheFs.readActive`, which applies the cache prefix). RSE
uses the same GBA `latin_normal` format, so **the pixel pipeline needs no change**;
only the width table and glyph-id bank can differ.

**Implemented (T5.1, new-file half, 2026-09-22):** `src/ui/game3/font.lua` is the
provider. It resolves `Profile.of(version).font.module` (FireRed's row names
`src.ui.game3.frlg_font`), caches resolved implementations, and forwards reads
**live** through a metatable, so `invalidate()`/`ensure()` state can never go stale
behind a snapshot. `frlg_font.lua` functions carry no `self`, so forwarding the raw
function is exact. Public seam:

```lua
Font.impl(versionId)   -- implementation for a game (nil = active)
Font.active()          -- the active game's implementation
Font.register(id, impl)  -- explicit implementation for a game (test/extracted-bank hook)
Font.unregister(id)
Font.reset()           -- drop resolutions; registrations survive
Font.CELL / Font.draw / Font.measure / ... -- forwarded live from the active impl
```

Because FireRed's row names the same module, `Font.CELL == FrlgFont.CELL`,
`Font.draw == FrlgFont.draw`, and `Font.impl("ruby")` falls back to FireRed until
`profiles/ruby.lua` exists. The 48 existing call sites stay on `frlg_font` until a
later mechanical sweep; **frlg_font.lua itself is Refactor-owned and was not
edited** — its own profile-driven width/atlas path is the deferred handoff
(`rse-seams` T5.1 second half).

**Options considered for the record:**

| Option | Change | Cost |
| --- | --- | --- |
| A. Provider module re-exporting the active impl | new `src/ui/game3/font.lua`; call sites migrate lazily | **chosen** — new seam, 0 forced edits |
| B. Make `frlg_font` itself profile-aware | edit one file; keep all 48 require sites | deferred handoff (Refactor-owned) |
| C. Rename/move to `game3_font.lua` and patch 60 requires | mechanical | largest diff, mid-wave conflict risk |

**RSE divergence risk to budget for:** the small-font glyph bank
(`latin_small_widths.lua`, `:381-394`) and the glyph-id table (`:110-135`) are
FRLG-specific. RSE's `latin_normal` shares the main bank; the small font and the
accented-glyph ids need an extracted table. That is extractor work (T6.4), not font
architecture.

### 3.3 Map-id and data tables per game behind a Dataset resolver

**Finding:** map identity is FRLG-string-based end to end (J8). The extractor
resolver (`dataset.lua`) consults `GameVersion.cachePrefix()` for paths (`:18-24`)
but otherwise hardcodes FRLG data: `Versions.MAPS` (`:119`), `Versions.PAIR_TILESET`
(`:121`), `FRLG_MAP_TO_FR` / `FRLG_MAP_TO_SEVII` reverse lookups (`:152-161`),
`FR_PALLET_TOWN`/`FR_ROUTE_1` fallback connections (`:243-268`), the explicit
`data/generated/gba/audio` root (`:367-368`).

**Design: one resolver, two layers.**

```
Layer 1 (identity):   src/core/game3/map_ids.lua   -- profile prefixes, NEW_GAME_START
Layer 2 (data):       src/core/game3/dataset.lua   -- profile-driven roots + map tables
```

Concretely, extend `Dataset` with three profile-driven functions rather than new
abstraction:

```lua
function Dataset.audioRoot()      -- Profile.active().audioRoot or Extract.CACHE_ROOT.."/audio"
function Dataset.mapGroups()      -- require(Profile.active().dexArea.mapGroups)
function Dataset.mapPrefixes()    -- Profile.active().map.prefixes
```

and replace the literals at `dataset.lua:152-161` (reverse map lookups) with a loop
over `Profile.active().map.reverseTables`, `:243-268` with a fallback table from the
same profile, `:367-368` with `Dataset.audioRoot()`.

**Map-id policy (decision requested, see §5):** keep per-game prefixed engine ids
(`FR_*`, `RS_*`, `E_*`) and add the prefix set to the profile. Alternative: single
neutral prefix per generation. **Recommendation: per-game prefixes** — save files
stay self-describing (`Game3._hasContinueSave` can tell Ruby's save from FireRed's
without version metadata), and `MapCatalog.pretToEngine` only needs a prefix
parameter.

**Data tables that must gain an RSE sibling** (each is a new file loaded by profile
name; no shared file is edited):

| FireRed file | RSE sibling | Consumer |
| --- | --- | --- |
| `map_groups_firered.lua` (690) | `map_groups_rse.lua` | `map_catalog.rebuildIndex` |
| `map_sections_extract.lua` (467, mapsec 88-196) | `map_sections_rse.lua` | region-map names, `dexArea` |
| `region_map_extract.lua` (675, Kanto + 4 Sevii) | `region_map_hoenn.lua` | region map |
| `region_map_sevii.lua` (52, orphaned) | delete or repurpose as Hoenn pages | — |
| `heal_locations` BY_ID (20) | `heal_locations_rse.lua` | whiteout |
| `marts.lua` loader | unchanged (generic) | marts |
| `versions.lua` offsets (2434) | `versions_rse.lua` | extractor |
| `map_catalog` | unchanged (prefix-parameterised) | all |

### 3.4 FRLG-only features behind capability flags

**Implemented (T3.1/T3.2 registry, 2026-09-22): `src/core/game3/capabilities.lua`**
is the flag registry: `Capabilities.NAMES` (every legal flag), the composed
`CORE`/`FRLG`/`RSE` sets, and `Capabilities.FEATURES` (feature id → capability +
owning modules + pret source). Gating call sites ask by **feature id**
(`Capabilities.gate(session, "fame_checker")`), an unknown id or flag warns once
and reads false rather than silently disabling a feature, and
`Capabilities.audit(row)` validates a profile row. `profiles/firered.lua` carries
the same flags (data-only) and its audit is pinned by
`tests/engine/game3_capabilities_test.lua` (258 checks).

**pret grounding (2026-09-22).** FireRed-only, present in the local clone
(`~/dev/pokefirered`, HEAD `c75f35230`) and 404 in pokeemerald **and** pokeruby:
`src/fame_checker.c`, `src/teachy_tv.c`, `src/vs_seeker.c`, `src/trainer_tower.c`,
`src/seagallop.c`, `src/help_system.c`, `src/tm_case.c`,
`src/trainer_fan_club.c`, `src/berry_pouch.c`. RSE-only, 200 in pokeemerald and
404 in pokefirered: `src/contest.c`, `src/secret_base.c`, `src/match_call.c`,
`src/pokenav.c`. `src/battle_tower.c` exists in both repos but FRLG's
player-facing tower is `trainer_tower.c`, so `battleTower` is classified RSE and
`trainerTower` FireRed. Note: RSE's `include/constants/items.h` still *defines*
`ITEM_FAME_CHECKER`/`ITEM_VS_SEEKER`/`ITEM_TEACHY_TV` as leftover constants — so
gating on item id presence is wrong; the capability flag is the gate.

**Handoff — the feature inventory, ungated today:** Fame Checker
(`core/game3/fame_checker.lua` 231, `ui/game3/fame_checker.lua` 862,
`import/gba/fame_checker_extract.lua` 218), Teachy TV (`core/game3/teachy_tv.lua`
757, `ui/game3/teachy_tv.lua` 1183, extractor 172), VS Seeker
(`core/game3/vs_seeker.lua` 635, `vs_seeker_data.lua` 245), Trainer Tower
(`core/game3/trainer_tower.lua` 832, `ui/.../trainer_tower_records.lua` 385,
`scripting/natives_tower.lua` 616, extractor 236), Seagallop
(`scripting/natives_seagallop.lua` 237, `seagallop_extract.lua` 220,
`region_map_sevii.lua` 52). Call sites: `item_use.lua:747-793`, `Game3.lua:356`,
`map.lua:417`, `step_events.lua:163-167`, `ops_a.lua:1448`, `bag_menu.lua:621`,
`natives.lua:809/816/868`, plus `RomExtractorGen3.lua:269-438`. The registry
being unwired means FireRed behaviour is unchanged; every call site below is a
Finisher/Refactor file and is parked as an exact patch in §4 (Wave 3).

**Design — three gates, one flag source:**

1. **Item gate.** `item_use.lua:747-793` dispatches FRLG-only items (VS Seeker,
   Teachy TV, Fame Checker). Gate with
   `Capabilities.gate(session, "vs_seeker")`; a disabled capability makes the
   item fall through to the generic "can't use here" path. RSE's item table simply
   never carries those item ids if the extractor omits them — belt and braces.
2. **Native gate.** `Natives.KNOWN_MODULES` (`natives.lua:803-820`) widens to
   `Profile.active().nativeModules` (default = today's 16-module list) and the
   merge loop skips a module whose feature capability is off
   (`Capabilities.nativeAllowed`). Unknown/absent handlers already safe-skip +
   log once (`natives.lua:883-891`), which is RSE-correct behaviour for a
   missing FRLG special. **Do not** delete FRLG natives from the shared table;
   filter at load. Exact patch: §4 Wave 3, T3.2.
3. **Extractor gate.** `RomExtractorGen3:runAuxExtracts` (`:291-438`) calls each
   `*_extract.run` unconditionally; make the list profile-driven
   (`Profile.of(id).extractors`, the field `profiles/firered.lua` already carries)
   so an RSE import never attempts FRLG-only packs. Exact patch: §4 Wave 3, T3.4.

**Capability sets — implemented in `src/core/game3/capabilities.lua`:**

```lua
Capabilities.CORE = { easyChat, braille, mysteryGift, unionRoom, daycare,
                      pokecenter, marts, moveRelearner, eggs, berries,
                      sizeRecord }
Capabilities.FRLG  = CORE + { helpSystem, tmCase, fameChecker, teachyTV,
                             vsSeeker, trainerTower, seagallop,
                             trainerFanClub, berryPouch, sevii }
Capabilities.RSE   = CORE + { battleTower, contests, secretBase,
                             matchCall, pokeNav }
```

Classification is pret-grounded (§3.4 header): `helpSystem`, `tmCase`,
`berryPouch`, `fameChecker`, `teachyTV`, `vsSeeker`, `trainerTower`, `seagallop`
and `trainerFanClub` are FireRed-only source files; `contests`, `secretBase`,
`matchCall` and `pokeNav` are Emerald-only; `easyChat`, `mysteryGift`,
`unionRoom`, `sizeRecord` and `battleTower` have sources in **both** repos and
are therefore shared, not FireRed-only.

RSE gains its own natives modules (`natives_contests.lua`, `natives_secret_base.lua`,
`natives_match_call.lua`) registered through the existing `MODULE_DIR`/`HANDLERS`
merge (`natives.lua:832-865`), which is already a registry — only the module **list**
needs to be per-profile.

### 3.5 Script opcodes and natives: shared core, game-specific registrations

**Finding (verified):** opcode decoding is one flat table
(`opcodes.lua:12-232`, 213 entries, bytes 0x00-0xD4, `MAX = 0xD4` at `:234`), and
execution is a ~1700-line `if op == "…"` chain in `ops_a.lua:294-1981` — there is
**no opcode handler registry**. Natives have a real registry:
`Natives.ALLOW["special:"..id]` inline (`natives.lua:245-798`, 53 handlers) plus
module merge (`natives.lua:800-865`, 152 handler keys from 16 modules, ~205 total),
with names in `stdscripts.lua:16-198` (180 names) and engine extensions at
`0xF001-0xF003`.

**pret grounding (2026-09-22):** FireRed's macro set is 257 `.macro` definitions
(`pokefirered/asm/macros/event.inc`) and Emerald's is 271
(`pokeemerald/asm/macros/event.inc`), so the decoded table genuinely differs between
games — a shared base with per-game overlays is required, not optional. The
Ruby/Sapphire macro source is **UNVERIFIED**: `pokeruby/asm/macros/event.inc`
returned 404 on 2026-09-22 and must be located before T4.2 covers RS.

**Split rule:**

- **Shared (never forked):** byte decoding, the VM (`vm.lua`), `ops_a` generic
  handlers (text, flags, vars, warps, movement, battles, money, items, party,
  `gend`), the natives registry/merge, `stdscripts` text, the four engine-extension
  specials.
- **Per-game registration 1 — native ids:** `stdscripts.Std.SPECIAL` is FRLG's
  `data/specials.inc` order. Make it `Std.SPECIALS[gameId]` with
  `Std.SPECIAL` kept as the firered alias (all 180 uses keep working), and resolve
  through `Std.specials()` at the 5 call sites that index by name. RSE's
  `specials.inc` order differs, so this is required, not optional.
- **Per-game registration 2 — native modules:** profile `nativeModules` (§3.4).
- **Per-game registration 3 — opcode table:** keep `Opcodes.TABLE` as the firered
  base; add `Opcodes.forGame(gameId)` that layers `profile.opcodeOverrides`
  (add/replace/remove entries by hex byte) and recomputes `MAX`. RSE adds contest
  opcodes and drops FRLG-only ones. The VM reads `Opcodes.forGame(...)` once per
  script load, not per row. **Unknown opcodes fall through to the existing generic
  skip path**, which is why a missing override degrades rather than crashes.
- **`callnative`/`native:` namespace:** currently zero registrations
  (`natives.lua:883-891` always misses). Keep it that way; register RSE specials in
  the `special:` namespace where the pret scripts expect them, except where RSE
  genuinely uses `callnative` (RSE macros do), in which case add
  `natives_native_rse.lua` with the same merge shape. Design note for the lead:
  **do not** invent an engine-specific `native:` namespace expansion while porting.

**FRLG-flavoured opcodes already present** that RSE never uses (safe to leave in the
shared table, filtered only if they misbehave): `loadhelp`/`unloadhelp` (:218-219),
`setworldmapflag` (:227), `warpspinenter` (:228), `bufferitemnameplural` (:231),
`trywondercardscript` (:226), `showcontestpainting` (:135, actually an RSE verb),
`bufferdecorationname`/`pokemartdecoration*` (:147/153-154).

### 3.6 Extraction and cache contract seams

- **`GameVersion.VERSIONS`** gains `ruby`/`sapphire`/`emerald` rows (sha1s, `cachePrefix = "ruby/"`,
  `saveSuffix = "_ruby"`, `generation = 3`, `engine = "game3"`, `cartShape = "gba"`).
  Note `src/core/game3/party.lua:165-169` already stubs `GameVersion.current == "leafgreen"`;
  LeafGreen should be added as a row in the same wave or the stub removed.
- **`CacheContract`**: add `VERSION_REQUIRED_FILES_OVERRIDE.ruby` (etc.) next to
  `:162` `firered`; `GameVersion.generation(version) == 3` already gates the Gen3
  semantic modules (`CacheContract.lua:525`).
- **`RomExtractorGen3.lua`** is FRLG-hardcoded at `:39/43/51` (accepts only
  `firered`/`leafgreen`), `:164/193` (`version = "firered"`), `:246/343/511-512`
  (`Rom.open(imports, "firered")`, `RevisionView.forImports(..., "firered", ...)`),
  and the aux list at `:401-438`. Parameterise by the active `GameVersion` row +
  profile `extractors`; this is the largest RSE ticket.
- **`Versions` monolith** — **T6.3a skeleton created (2026-09-22):**
  `src/import/gba/versions_game.lua` is the `Versions.game(id)` resolver. The
  `firered`/`leafgreen` rows name the existing monolith; an RSE row is registered
  when `versions_rse.lua` lands; unknown ids warn once and fail closed to FireRed —
  the same contract as `src/core/game3/profile.lua`. `register(id, path)` is the
  port/test seam, `reset()` drops resolutions. **Unwired**: the handoff aliases
  `Versions.game = require("src.import.gba.versions_game").game` and routes
  extractor reads through it.
- **`src/core/game3/cache_paths.lua`** — same ticket, same status: the shared
  `CACHE_ROOT`/`NATIVE_ROOT` module that replaces `extract_island1.lua:19-21` as
  the owner of the root, so `pokemon.lua` can drop its extractor require (I8) and
  `Dataset.mountExtractRoots` sets one root for both. `setRoot(root)` derives
  `NATIVE_ROOT`; `reset()` restores the packaged defaults (which the test pins
  against the extractor's current literals).

### 3.7 Mod API seam — IMPLEMENTED (T7.1, 2026-09-22)

`Loader.lua:1666-1680/1878` and `Schemas.lua:896-904` dispatched on
`generation == 3`. That is now a composite `(engine, versionId)` dispatch with a
graceful fallback to the generation's default row, so FireRed is byte-identical and
an RSE row is added without forking a shared table:

- `Loader.version` — the GameVersion id at construction (`opts.version` is the test
  seam), validated against the loader's generation by the existing
  `Loader:_targetVersion()`.
- `Loader.apiModule(kind, generation, version)` — `GEN3_API[version]` row, else
  `GEN3_API_DEFAULT` (the FireRed-backed modules). gen2/gen1 arms unchanged.
- `Schemas.GEN3_ROUTING[version]` and `Schemas.GEN3_LIVE_MODULES[version]` — sparse
  per-game overlays merged over `Schemas.GEN3` / `LIVE_MODULES` at read time
  (`Schemas.routing(generation, version)`, `Schemas.liveModuleFor(key, version)`).
  Overlays are cached per row and never written back, so the default view cannot be
  mutated by a game row.
- `Schemas.bindGen3(data, version)` records the game on the bound Data table (weak
  keys); `Schemas.boundVersion(data)` reads it back. `targetFor`/`gatedFor` take the
  optional version and default to `Schemas.GEN3`.
- The `gen3*` binding names are untouched: `ROOT_KEYS`/`LIVE_MODULES` are the
  fallback behind every overlay.

**Follow-up (not done):** `src/mods/DatasetViews.lua:305/323/351` still calls
`bindGen3(data)` / `targetFor(..., generation)` without `view.version`. It is
behaviour-identical today (no overlays exist); thread `view.version` when the first
RSE row lands. The file has no lane owner in the triage table, so this was left
untouched.

---

## 4. Migration tickets (ordered; FireRed must never regress)

**Rules for every ticket:** small, single-purpose; `./scripts/test.sh` green before
and after; every FireRed-visible value comes from the `profiles/firered.lua` row
rather than a new literal; visual changes need an in-game check (headless suites
render nothing). Run the per-suite commands from the engine root.

**Baseline status (updated 2026-09-22, lead-confirmed): the two known failures are
GREEN.** Re-verified in the working tree this pass:

```sh
luajit tests/engine/mew_dock_private_artifact_gate.lua   # 3/3 checks passed (git fixed)
luajit tests/game3_battle_move_effects_test.lua          # 126 passed, 0 failed (Knock Off fixed)
```

Full engine tier after T0.1: `luajit tests/run_engine.lua` → **617/617 suites
passed, exit 0** (was 616; the new profile suite is the 617th).

**Lane rule active (lead-approved 2026-09-22):** the Architect lane may implement a
ticket immediately when it **only creates new files** (profile rows, providers,
tests) or edits files the triage table gives Architect (`src/mods/Loader.lua`,
`src/mods/Schemas.lua`, the collision/bg modules). Any file owned by Finisher or
Refactor (including `save_schema_firered.lua`, `map_ids.lua`, `options.lua`,
`pokemon.lua`, `natives.lua`) is **handoff-only**: the patch below is exact and
ready to apply, but another lane applies it.

### Wave 0 — identity groundwork (no behaviour change)

Status: **T0.1 DONE** · **T0.2 HANDOFF-READY** · **T0.3 SUPERSEDED**.

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T0.1 ✅ | Profile selector + FireRed row + suite — **DONE 2026-09-22** | created `src/core/game3/profile.lua`, `src/core/game3/profiles/firered.lua`, `tests/engine/game3_profile_test.lua` | `luajit tests/engine/game3_profile_test.lua` → 80/80; `luajit tests/run_engine.lua` → 617/617 |
| T0.2 | Schema round-trips `session.version`; `SaveData`/`Game3` detection via engine+`MapIds` (J1, part 1) — **handoff patch below** | `save_schema_firered.lua`, `src/core/SaveData.lua`, `src/core/Game3.lua` (all Finisher-owned) | `tests/engine/game3_gamestats_persistence_test.lua`, `tests/game3_save_pokeball_test.lua`, `tests/game3_stitchsave_schema_fields_test.lua`, new `tests/engine/game3_save_version_roundtrip_test.lua` |
| T0.3 ❌ | Save-shape guard test — **superseded**: `tests/game3_stitchsave_schema_fields_test.lua` already round-trips the schema (secretId/safari/mail/options). Fold the new `version`/`engine` assertions into the T0.2 patch instead of a second suite. | — | existing suite above |

#### T0.2 handoff patch (exact)

Apply in one commit; all three files are Finisher-owned.

```lua
-- 1. src/core/game3/save_schema_firered.lua  (add near the top, after MapIds)
local Profile = require("src.core.game3.profile")

-- newGame: keep the caller's game, else the active one
    version = opts.version or Profile.active().id,

-- toSaveTable: write the session's game, not a literal
    version = session.version or Profile.active().id,

-- fromSaveTable: round-trip it; unknown ids fail closed in Profile.of
    version = save.version or Profile.active().id,      -- new session field
```

```lua
-- 2. src/core/SaveData.lua:1132 (slot summary must not key Gen3 off one game)
  local gen3 = save.generation == 3
    or (vinfo and vinfo.generation == 3)
    or (save.engine == "game3") or false
```

```lua
-- 3. src/core/Game3.lua:46 (_hasContinueSave: namespace decides, not a literal)
  return save.engine == "game3" and type(save.map) == "string"
    and MapIds.isGame3Map(save.map, save.version)
-- 3b. src/core/Game3.lua:384 (refusal list moves to the profile)
    local legacy = Profile.of(session.version).map.legacyPrefixes or {}
    for _, prefix in ipairs(legacy) do
      if session.map:sub(1, #prefix) == prefix then ... end
    end
```

Non-regression: every branch has an identical firered arm, and existing saves
already carry `version = "firered"`; the only behaviour change is that the field now
survives a load. `MapIds.isGame3Map("SEVII_…")` is true today, so the 3b refusal
list (not the namespace test) must stay the Sevii gate — keep both statements in
that order.

### Wave 1 — identity seams (FireRed-identical)

Status: **HANDOFF-READY** (all files Finisher/Refactor-owned).

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T1.1 | `Options.BLOCK` from profile (J2) — **handoff patch below** | `src/core/game3/options.lua` (Finisher), `profiles/firered.lua` (done) | new `tests/engine/game3_options_block_test.lua` + `./scripts/test.sh` |
| T1.2 | Profile map prefixes; `MapIds.isGame3Map`, `Game3` gate, `map_catalog` prefix (J8) — **handoff patch below** | `map_ids.lua` (Refactor), `Game3.lua`/`map_catalog.lua`/`doors.lua`/`encounters.lua`/`heal_locations.lua` (Finisher) | `tests/game3_map_onload_test.lua`, `tests/game3_doors_table_test.lua`, `tests/game3_doors_viewport_test.lua`, `tests/engine/game3_map_section_unresolved_test.lua` |
| T1.3 | `Dataset.audioRoot/mapGroups/mapPrefixes`; remove FRLG literals from hydration (J6/J8 infra) | `dataset.lua` (Finisher), `scripting/space.lua` (Finisher) | `tests/engine/game3_cache_module_sandbox_test.lua`, `tests/game3_cache.lua`, `tests/game3_encounters_lookup_test.lua` |
| T1.4 | Species/Egg from profile as an **assertion, not a fork** (J7 re-graded: 412 is shared by FR/E/R/S per pret) — low priority | `pokemon.lua` (Finisher), `pokemon_extract.lua` (Refactor) | `tests/game3_national_dex_test.lua`, `tests/game3_growth_evolution_test.lua`, `tests/game3_battle_forms_intro_test.lua` |

#### T1.1 handoff patch (exact)

```lua
-- src/core/game3/options.lua
local Profile = require("src.core.game3.profile")

-- keep the field for compatibility, but no call site may read it directly
Options.BLOCK = Profile.FALLBACK_ID

function Options.block(engine, blockId)
  if type(engine) ~= "table" then return fill_defaults({}) end
  blockId = blockId or Profile.active().optionsBlock
  local o = engine[blockId]
  ...
end

function Options.ensure(session)
  ...
  local blockId = (type(session.version) == "string"
    and Profile.of(session.version).optionsBlock)
    or Profile.active().optionsBlock
  if type(o[blockId]) == "table" then
    session.engineOptions = o
    o = Options.block(o, blockId)
    session.options = o
  end
  ...
end
```

`Options.bind(session, engine)` passes `Profile.of(session.version).optionsBlock`
once the T0.2 patch gives the session its `version`. FireRed resolves to `"firered"`
in every path, so an existing engine-options file reads/writes identically.

#### T1.2 handoff patch (exact)

```lua
-- src/core/game3/map_ids.lua
local Profile = require("src.core.game3.profile")

-- gameId is a version id (save.version) or nil for the active game
function MapIds.isGame3Map(mapId, gameId)
  if type(mapId) ~= "string" then return false end
  for _, prefix in ipairs(Profile.of(gameId).map.prefixes) do
    if mapId:sub(1, #prefix) == prefix then return true end
  end
  local ok, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if ok and MapCatalog and MapCatalog.isKnown then
    return MapCatalog.isKnown(mapId)
  end
  return false
end
```

```lua
-- src/import/gba/map_catalog.lua pret_to_engine: take the prefix from the profile
local Profile = require("src.core.game3.profile")
...
  return Profile.active().map.enginePrefix .. s
```

```lua
-- src/core/Game3.lua:384 — refusal list from the profile (see T0.2 patch 3b)
```

FireRed prefixes are `{"FR_", "SEVII_"}` and `"FR_"`, so every membership test and
every synthesized id is unchanged. `doors.lua`/`encounters.lua`/`heal_locations.lua`
prefix literals are pure namespace checks; convert them to `MapIds.isGame3Map` one
file at a time with the listed suites as the guard (each file is a separate commit
so a failure points at one seam).

### Wave 2 — content-data seams (one provider per finding)

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T2.1 | Badge provider (J3) | `src/ui/game3/trainer_card.lua:212-236`, `profiles/firered.lua` | `tests/game3_trainer_card_layout_test.lua`, `tests/game3_save_trainer_card_test.lua` |
| T2.2 | Heal-location provider (J4) | `heal_locations.lua`, callers `field.lua:1381/1399/1445`, `bridge.lua:82` | `tests/game3_stitchcoll_dynamic_warp_test.lua`, `tests/game3_field_safari_test.lua` |
| T2.3 | Trainer rival/music/fallback tables (J5) | `scripting/trainers.lua:11-13/22-41/328-363`, `profiles/firered.lua` | `tests/game3_special_handlers_test.lua`, new `tests/engine/game3_trainer_music_profile_test.lua` |
| T2.4 | Dex-area provider (J6) | `pokedex_data.lua:111-153/283-286`, `profiles/firered.lua` | `tests/game3_pokedex_area_test.lua`, `tests/game3_pokedex_area_chrome_test.lua`, `tests/game3_national_dex_test.lua` |
| T2.5 | Region-map switch capability (J9) | `src/ui/game3/region_map.lua:407-414` | `tests/game3_region_map_assets_test.lua`, new `tests/engine/game3_region_map_permission_test.lua` |

### Wave 3 — capability flags

Status: **T3.1a registry DONE · T3.1b/T3.2/T3.4 HANDOFF-READY (patches below) ·
T3.3 folded into T3.1b/T3.4**.

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T3.1a ✅ | Capability registry: `NAMES`, `CORE`/`FRLG`/`RSE` sets, `FEATURES` (feature → capability → modules → pret source), `gate`/`has`/`enabled`/`audit`/`nativeAllowed` | created `src/core/game3/capabilities.lua`; `profiles/firered.lua` regrouped to the pret-verified split (+`berryPouch`) | new `tests/engine/game3_capabilities_test.lua` → 265/265; `luajit tests/run_engine.lua` → 624/624; `luajit tests/run_modkit.lua` → 37/37; lint gate exit 0 |
| T3.1b | Gate the three FRLG-only item dispatches + the VS Seeker step/map call sites — **handoff patch below** | `src/core/game3/item_use.lua` (unowned), `Game3.lua`/`map.lua`/`step_events.lua` (Finisher) | `tests/game3_vs_seeker_test.lua`, `tests/game3_teachy_*_test.lua`, `tests/game3_fame_*_test.lua`, `tests/game3_item_use_and_parcel_test.lua` |
| T3.2 | Filter the natives module list by capability — **handoff patch below** | `src/core/game3/scripting/natives.lua` (Finisher) | `tests/game3_special_handlers_test.lua`, `tests/game3_special_ids_test.lua`, `tests/engine/game3_script_verbs_subset_test.lua` |
| T3.3 | Trainer Tower + Seagallop gating | folded into T3.1b (they only reach the engine through natives) and T3.4 | tower suites + `tests/game3_seagallop_test.lua` |
| T3.4 | Extractor aux list from the profile `extractors` field — **handoff patch below** | `src/import/RomExtractorGen3.lua:291-438` (unowned) | `./scripts/test.sh` + the ROM import gate in §4/T6.2 step 4 |

#### T3.1b handoff patch (exact)

```lua
-- src/core/game3/item_use.lua (top of file)
local Capabilities = require("src.core.game3.capabilities")

-- ~:747 VS Seeker branch -- capability first, before any module require
  if use == "vs_seeker" or id == ItemsData.ITEM_VS_SEEKER or id == "VS_SEEKER"
      or ItemsData.toNumericId(id) == ItemsData.ITEM_VS_SEEKER then
    if not Capabilities.gate(session, "vs_seeker") then
      return false, "vs_seeker", nil
    end
    local VsSeeker = require("src.core.game3.vs_seeker")
    ...

-- ~:778 Teachy TV branch (before require("src.core.game3.teachy_tv"))
    if not Capabilities.gate(session, "teachy_tv") then
      return false, "teachy_tv", nil
    end

-- ~:786 Fame Checker branch (before require("src.ui.game3.fame_checker"))
    if not Capabilities.gate(session, "fame_checker") then
      return false, "fame_checker", nil
    end
```

The deny returns **no message text**: the bag/field caller already owns the
"cannot use here" wording, and inventing one would be new behaviour. FireRed
reads every gate as `true`, so the branches are unchanged today.

Optional (same files, one line each, only if the Finisher wants the zero-cost
path): gate `Game3.lua:356` (`kind == "vs_seeker"` result),
`map.lua:417` (`vs_seeker.mapReset`) and `step_events.lua:163-167`
(`vs_seeker.onStep`) with `Capabilities.gate(session, "vs_seeker")`. They are
correctness-neutral today (the modules stay in the tree), so this is a
performance nicety, not a requirement.

#### T3.2 handoff patch (exact)

```lua
-- src/core/game3/scripting/natives.lua (top of file)
local Capabilities = require("src.core.game3.capabilities")
local Profile = require("src.core.game3.profile")

-- ~:803 keep KNOWN_MODULES as the fallback; let the profile widen it
local function moduleNames()
  local names = Profile.active().nativeModules
  return type(names) == "table" and names or KNOWN_MODULES
end

-- ~:857 merge loop -- skip a module whose feature capability is off
for _, base in ipairs(Natives.MODULE_NAMES) do
  if Capabilities.nativeAllowed(nil, base) then   -- nil session = active game
    local ok, mod = pcall(require, MODULE_PACKAGE .. base)
    if ok and type(mod) == "table" then
      Natives.MODULES[base] = mod
      for id, handler in pairs(mod.HANDLERS or {}) do
        Natives.ALLOW["special:" .. id] = handler
      end
    end
  end
end
```

`nativeAllowed` maps `natives_fame`/`natives_tower`/`natives_fan_club`/
`natives_seagallop` to their features (built from `Capabilities.FEATURES`) and
treats every other module as shared, so FireRed merges exactly the same 16
modules it merges today. Unknown ids in `Natives.ALLOW` already safe-skip +
log once, which is the correct RSE behaviour for an FRLG special.

#### T3.4 handoff patch (exact)

`profiles/firered.lua` already carries `extractors = { … }` (the 18 modules
`RomExtractorGen3:runAuxExtracts` runs unconditionally at `:291-438`). Make the
list profile-driven:

```lua
-- src/import/RomExtractorGen3.lua:runAuxExtracts
local Profile = require("src.core.game3.profile")
local wanted = Profile.of(GameVersion.get()).extractors   -- {"region_map_extract", ...}
-- local each module's `need*` flag with:
--   local needed = wanted[base] and not Module.ready(cache, GBA_ROOT)
```

An RSE row then lists only its own extractors, so an RSE import never attempts
fame/teachy/tower/seagallop packs. Verification is the ROM import gate from §4
(T6.2 step 4) plus `./scripts/test.sh`; the headless suites self-skip.

### Wave 4 — script layer

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T4.1 | `Std.SPECIALS[gameId]` + `Std.specials()`; keep `Std.SPECIAL` alias | `scripting/stdscripts.lua:16-212`, call sites indexing by name | `tests/game3_special_ids_test.lua`, `tests/game3_special_handlers_test.lua`, `tests/engine/game3_givemon_opcode_layout_test.lua` |
| T4.2 | `Opcodes.forGame(gameId)` overlay + recomputed `MAX`; VM reads once per script | `scripting/opcodes.lua`, `scripting/vm.lua`, `ops_a.lua` | `tests/engine/game3_givemon_opcode_layout_test.lua`, new `tests/engine/game3_opcode_overlay_test.lua` |

### Wave 5 — font provider

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T5.1a ✅ | Provider module + registration seam — **DONE 2026-09-22** | created `src/ui/game3/font.lua` | new `tests/engine/game3_font_provider_test.lua` → 34/34; `luajit tests/run_engine.lua` |
| T5.1b | Handoff: `frlg_font.lua` reads its width-table/small-font paths from `Profile.of(version).font` (Refactor-owned file) | `frlg_font.lua:319-394` | existing font suites + one in-game visual check |

### Wave 6 — import/extraction (the RSE data arrivals)

Status: **T6.1 HANDOFF · T6.2 HANDOFF-READY (patch below) · T6.3a DONE · T6.3b HANDOFF**.

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T6.1 | Add `ruby`/`sapphire`/`emerald` (+`leafgreen`) `GameVersion` rows + `CacheContract` overrides | `src/core/GameVersion.lua`, `CacheContract.lua:23/162` | `./scripts/test.sh`; `tests/engine/` version/manifest suites |
| T6.2 | `RomExtractorGen3` version plumbing (12 literal sites) — **handoff patch below** | `src/import/RomExtractorGen3.lua` + `CacheContract.lua` (Finisher-free files, but the ticket needs Finisher-owned `versions.lua`; see verdict) | importer suites (self-skip without ROM); import smoke test with the manifest-pinned ROM |
| T6.3a ✅ | `cache_paths.lua` + `Versions.game(id)` facade skeleton — **DONE 2026-09-22** | created `src/core/game3/cache_paths.lua`, `src/import/gba/versions_game.lua` | new `tests/engine/game3_cache_paths_test.lua` → 15/15; new `tests/engine/game3_versions_game_test.lua` → 21/21 |
| T6.3b | Wiring: `Versions.game` alias, `extract_island1` reads/writes `CachePaths`, `pokemon.lua` drops its extractor require (I8) | `versions.lua`, `extract_island1.lua`, `pokemon.lua`, `native_pack.lua` (all Finisher-owned) | new `tests/engine/game3_pokemon_no_extractor_require_test.lua` + engine tier |
| T6.4 | RSE data siblings: `versions_rse`, `map_groups_rse`, `map_sections_rse`, `region_map_hoenn`, `heal_locations_rse` | new data modules only | ROM-gated suites self-skip; `tests/game3_map_preview_extract_test.lua`, `tests/game3_region_map_assets_test.lua` |
| T6.5 | RSE runtime boot smoke: profile rows for RSE + `NEW_GAME_START` Littleroot | `profiles/ruby.lua` etc. | new `tests/engine/game3_rse_profile_test.lua` (fixture-driven, no ROM) |

#### T6.2 ownership verdict (2026-09-22)

The triage file-ownership table gives **`src/import/gba/versions.lua` to Finisher**
(row I7), and `map_catalog.lua` / `map_tree.lua` / `extract_island1.lua` likewise.
`src/import/RomExtractorGen3.lua` and `src/import/CacheContract.lua` have **no owner
row** (no findings point at them), but the ticket is not atomic without
`versions.lua`, so per the lead's rule the whole ticket is **handoff-only**. Effort:
**medium** (12 mechanical sites + 1 structural step), and the ROM-only paths cannot
be fully verified in a ROM-less checkout — but a FireRed import IS possible on this
machine (QA's sweep used `/Users/shanemcgovern/Downloads/1636 - Pokemon Fire Red
(U)(Squirrels).gba`, SHA-1 `41cb23d8…` = the manifest pin), so step 4 below is the
real gate.

#### T6.2 handoff patch (exact)

**Step 1 — GameVersion rows first (T6.1).** Without a `ruby`/`sapphire`/`emerald`
row, `GameVersion.get()` cannot return those ids and every step below stays FireRed.

**Step 2 — version plumbing in `src/import/RomExtractorGen3.lua` (12 sites,
behaviour-identical for FireRed):**

```lua
-- add near the top
local GameVersion = require("src.core.GameVersion")
local CachePaths = require("src.core.game3.cache_paths")

-- LeafGreen is FireRed's data; everything else canonicalises to itself.
local function canonicalImportId(id)
  return id == "leafgreen" and "firered" or id
end

-- at each public entry point (the two Rom.open sites and writeRequiredMarkers):
local version = GameVersion.get()
```

| line | today | replace with |
| --- | --- | --- |
| `:1` header | "FireRed Gen 3 extractor" | "Gen 3 extractor (game id from GameVersion)" |
| `:12` | `local GBA_ROOT = "data/generated/gba"` | `local GBA_ROOT = CachePaths.CACHE_ROOT` (or read at call time) |
| `:39`, `:51` | `id ~= "firered" and id ~= "leafgreen"` | `canonicalImportId(id) ~= canonicalImportId(version)` |
| `:43` | `id = "firered"` | `id = canonicalImportId(version)` |
| `:154` comment | `...OVERRIDE.firered needs` | `...OVERRIDE[version] needs` |
| `:164`, `:193` | `version = "firered"` | `version = version` (the extractor's local) |
| `:246` | `Rom.open(imports, "firered")` | `Rom.open(imports, version)` |
| `:343` | `Rom.open(self:sharedImports(sha1), "firered")` | `Rom.open(self:sharedImports(sha1), version)` |
| `:511` | `imports:info("firered")` | `imports:info(version)` |
| `:512` | `RevisionView.forImports(imports, "firered", info)` | `RevisionView.forImports(imports, version, info)` |

`makeImports(romData, sha1)` gains a `version` parameter for its two guards.

**Step 3 — `CacheContract` rows (shape exact, contents are T6.4 data):**

- `CacheContract.lua:23` cache tags: add `ruby = "rom-cache-v1-ruby:"` etc. beside
  `firered = "rom-cache-v15-firered:"` (one tag per version; the RSE tag version
  number is UNVERIFIED until an RSE import exists).
- `CacheContract.lua:162` `VERSION_REQUIRED_FILES_OVERRIDE.firered = {…}`: add
  sibling rows keyed by the new GameVersion ids, mirroring the row's shape
  (`dir`, `semantic`, `files` lists). The exact RSE file list is **UNVERIFIED** —
  it is produced by the first successful RSE import (T6.4) and must not be guessed.
- `CacheContract.requiredFilesFor(version)` is already version-keyed, so no code
  change is needed beyond the rows.

**Step 4 — verification gate (do not land steps 2–3 without it):**

```sh
POKEPORT_IDENTITY=pokeport-test-caches POKEPORT_VERSION=firered \
POKEPORT_IMPORT_ONLY=1 \
POKEPORT_IMPORT_ROM="/Users/shanemcgovern/Downloads/1636 - Pokemon Fire Red (U)(Squirrels).gba" \
love .
# then re-run: ./scripts/test.sh and the sweeps; the resulting cache file
# inventory must be byte-identical to the pre-change import.
```

The aux-extractor gating list (`RomExtractorGen3:291-438`, 18 extractors) is a
separate ticket — **T3.4** — not part of this plumbing patch; keep its behaviour
untouched here.

### Wave 7 — mod API

Status: **T7.1 DONE** (2026-09-22).

| ID | Ticket | Files touched | Tests |
| --- | --- | --- | --- |
| T7.1 ✅ | `(engine, versionId)` dispatch for BattleAPI/WorldAPI/bindings; keep `gen3*` names | `src/mods/Loader.lua` (`version`, `apiModule`, 3 call sites, devShim), `src/mods/Schemas.lua` (`GEN3_ROUTING`, `GEN3_LIVE_MODULES`, `routing`/`targetFor`/`gatedFor`/`bindGen3`/`liveModuleFor`/`boundVersion`) | new `tests/engine/game3_version_dispatch_test.lua` → 36/36; `tests/engine/gate_gen3_mod_api.lua`, `gate_gen2_mod_api.lua`, `gen2_rom_text_registry_test.lua`, `gen2_content_registries.lua`, `gen3_shim_engine_require.lua`, `game3_mod_names_survive_reload_test.lua` → PASS; `luajit tests/run_modkit.lua` → 37/37; `luajit tests/run_engine.lua` → 619/619 |

### Wave 8 — deferred debt (Refactor/Architect lanes; not RSE-blocking)

Ordered by value once the fix wave is clear: **I6** (de-eager `SaveData → Bag`),
**I8** (already folded into T6.3), **I10** (module renames), **I1** (split
`gfx.lua`), **I3/I4** (remove lazy cycles), **I2** (screen ports, demand-driven
only), **I5** (commit an SCC checker, non-blocking).

---

## 5. Decisions (lead-approved 2026-09-22; user may still override)

1. **Profile home — APPROVED as recommended (option B):
   `src/core/game3/profiles/<id>.lua` + `profile.lua` selector.** Implemented in T0.1.
2. **Map-id policy — APPROVED as recommended: per-game prefixes
   (`FR_`/`SEVII_`, later `RS_`/`E_`).** Wiring is the T1.2 handoff.
3. **RSE scope for milestone 1 — APPROVED: Ruby + Sapphire + Emerald as one
   milestone**, one profile row each sharing `versions_rse.lua`; Emerald deltas
   (Match Call, Battle Frontier, gym order) are data, not engine.
4. **Lane ownership of Waves 1–2 — RESOLVED (split rule):** the Architect lane may
   implement tickets that only create new files, or edit Architect-owned files
   (`src/mods/Loader.lua`, `src/mods/Schemas.lua`, the collision/bg modules). Any
   Finisher/Refactor-owned file is handoff-only with an exact patch in §4.
5. **`leafgreen` version row — APPROVED: add it** in Wave 6 (T6.1), sharing
   FireRed's `versions` data; the `party.lua:165-169` stub then becomes live.

## 6. Wave status log

| Date | Ticket | Files | Command | Result |
| --- | --- | --- | --- | --- |
| 2026-09-22 | T0.1 | created `src/core/game3/profile.lua`, `src/core/game3/profiles/firered.lua`, `tests/engine/game3_profile_test.lua` | `luajit tests/engine/game3_profile_test.lua` | 80/80 checks passed, exit 0 |
| 2026-09-22 | T0.1 regression | — | `luajit tests/run_engine.lua` | 617/617 suites passed, exit 0 |
| 2026-09-22 | baseline re-verify | — | `luajit tests/engine/mew_dock_private_artifact_gate.lua`; `luajit tests/game3_battle_move_effects_test.lua` | 3/3 passed; 126 passed 0 failed |
| 2026-09-22 | pret grounding pass | doc + profile row comments only | `curl` to raw.githubusercontent.com (citations in the header table) | 8 claims VERIFIED; 4 marked UNVERIFIED |
| 2026-09-22 | full gate note | — | `./scripts/test.sh` | T1/T2 red for ~2 min on `luajit_source_limits_test` (two teammate-edited files mid-write); re-ran it alone → 889/889 PASS. Not an A-lane change. |
| 2026-09-22 | T7.1 | edited `src/mods/Loader.lua`, `src/mods/Schemas.lua`; created `tests/engine/game3_version_dispatch_test.lua` | `luajit tests/engine/game3_version_dispatch_test.lua`; `luajit tests/run_modkit.lua`; `luajit tests/run_engine.lua` | 36/36; 37/37; 619/619 — all exit 0 |
| 2026-09-22 | T5.1a | created `src/ui/game3/font.lua`, `tests/engine/game3_font_provider_test.lua` | `luajit tests/engine/game3_font_provider_test.lua` | 34/34 exit 0 |
| 2026-09-22 | T6.3a | created `src/core/game3/cache_paths.lua`, `src/import/gba/versions_game.lua`, `tests/engine/game3_cache_paths_test.lua`, `tests/engine/game3_versions_game_test.lua` | `luajit tests/engine/game3_cache_paths_test.lua`; `luajit tests/engine/game3_versions_game_test.lua`; `luajit tests/run_engine.lua` | 15/15; 21/21; 623/623 — all exit 0 |
| 2026-09-22 | T6.2 ownership check | doc only | — | `versions.lua` = Finisher (I7) → T6.2 handoff-ready; exact patch set in §4 |
| 2026-09-22 | T3.1b | edited `src/core/game3/item_use.lua` (vs_seeker/teachy_tv/fame_checker capability gates before the module requires) | `game3_vs_seeker`, `game3_teachy_model/screen`, `game3_fame_model/screen`, `game3_item_use_and_parcel` | all rc=0 |
| 2026-09-22 | T3.2 | edited `src/core/game3/scripting/natives.lua` (`moduleNames()` from `Profile.active().nativeModules`, merge loop gated by `Capabilities.nativeAllowed(nil, base)`) | `game3_special_handlers`, `game3_special_ids`, engine `game3_script_verbs_subset` | all rc=0; full gate WAVE2_GATE1_EXIT=0 |
| 2026-09-22 | T3.4 | edited `src/import/RomExtractorGen3.lua` `runAuxExtracts` (profile `extractors` list gates all 18 `need*` checks; empty list = today's behaviour) | importer suites self-skip; behaviour-identical for FireRed proven by the T6.2 import gate below | covered by gate + import evidence |
| 2026-09-22 | T6.2 | edited `src/import/RomExtractorGen3.lua` (12 sites: header, `GBA_ROOT = CachePaths.CACHE_ROOT`, `canonicalImportId`+`importVersion(sha1)` guards in `makeImports`, meta/intro `version`, 2× `Rom.open`, `info`/`forImports`) | two fresh ROM imports (manifest-pinned FireRed, exit 0 each): file set identical 7269/7269; differing-path set 920 in pre-vs-post AND 920 in a same-code A/A rerun with **zero symmetric difference** ⇒ patch is output-neutral; **byte-identical clause: MET** (2026-09-22 follow-up, ticket `01a0c8f7` — was UNREACHABLE) — the 920-path run-to-run drift was `pairs()`-order JSON key serialization in three writers (917 `map_tree/*.json` + `census`/`meta`/`maps`/`connections.lua`), **not** the quantizer: fixed by `src/import/canonical_json.lua` (sorted-key encoder) wired into `map_tree_extract.write_json` + `RomExtractorGen3.writeJson`, sorted keys in `extract_island1`'s inline `write_json`, sorted direction keys in both `connections.lua` builders; two fresh imports byte-diff to **0 differing files (7269/7269 identical)** | gate evidence above; `importVersion` = `GameVersion.forSha1(sha1) or "firered"` (spec said `GameVersion.get()`, which returns the default gen1 id pre-detection in this flow — sha1 is authoritative); determinism proof: scratch identity `finisher-determinism`, cache wiped between runs, T6.2 gate form re-passed (`import_id:"firered"`, md5 `41cb23d8…`, `region_map/extract_status.json` present) |
| 2026-09-22 | T6.3b | edited `versions.lua` (`Versions.game` alias), `extract_island1.lua` (CACHE_ROOT/NATIVE_ROOT forward to `CachePaths` via metatable), `pokemon.lua` (line-3 extractor require → `CachePaths`, 5 root reads), `native_pack.lua` (root default from `CachePaths`); created `tests/engine/game3_pokemon_no_extractor_require_test.lua` | new test 7/7; `game3_cache_module_sandbox`, `game3_cache`, `game3_cache_paths`, `game3_versions_game` all rc=0 |
| 2026-09-22 | T3.1a | created `src/core/game3/capabilities.lua`, `tests/engine/game3_capabilities_test.lua`; edited `src/core/game3/profiles/firered.lua` (regrouped capability flags + `berryPouch`) | `luajit tests/engine/game3_capabilities_test.lua`; `luajit tests/run_engine.lua`; `luajit tests/run_modkit.lua`; `scripts/lint.sh --gate src` | 265/265; 624/624; 37/37; lint exit 0 |
| 2026-09-22 | T3.1b/T3.2/T3.4 | doc only | — | exact gate patches parked in §4 Wave 3 (item gate, natives filter, extractor list) |
| — | T0.2 | pending handoff | — | — |
| — | T1.1 | pending handoff | — | — |
| — | T1.2 | pending handoff | — | — |

## 7. Open verification (not done in this pass)

- I5's "102-module SCC" is unverified (see §2.5); needs `tools/scc.py`.
- All ROM-import-dependent RSE paths are untestable in this checkout (no ROM/cache);
  Waves 6 tests must be written to self-skip, as the existing `*_rom_test.lua`
  suites do.
- Visual/font parity (§3.2) cannot be proven headlessly (docs/architecture.md
  verification section); budget one in-game check per visual ticket.
