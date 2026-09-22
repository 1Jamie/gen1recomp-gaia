# Gen 3 (FireRed) review v3 — owner-laned triage

Source: `~/Downloads/gen3-review-v3.html` (sections A–X, 210 findings cards + section N status register + Worst 25).
Working tree: `/Users/shanemcgovern/dev/gen1recomp` (no `.git` at time of writing).

## What this file is

One row per finding card: ID, title, route, confidence, v3 verified flag, source evidence, one-line fix, owner lane.
Re-verification was done against the live tree (not the review's snapshot) for every unverified high-confidence finding in
the Worst 25 plus every unverified high-confidence `route=bugfix` finding, and for the five carried `N-*` Worst-25 items.
Invalid (stale) findings are struck through with the reason in the Notes column.

> **Fix suggestions in this file are evidence to verify, not instructions to apply verbatim.** They are lifted from the
> report text or synthesised during triage; check each against pret and the live source before applying it.
> Confirmed case: **C1 (Knock Off)** — the review's suggestion (`persistItem(effBattler, 0)`, party write-through) is
> Gen 4+ semantics and wrong for FRLG. The shipped correct fix is battler-only clear + battle-scoped `knockedOffMons`
> bit + send-out mask (see the C1 row in §C).
>
> **Source-of-truth rule (user mandate):** FireRed/Gen 3 behaviour is defined by `pret/pokefirered` (RSE: `pret/pokeemerald`
> + `pret/pokeruby`). Behavioural claims not verifiable against pret are labelled **`[pret-unverified]`** with the file that
> would confirm them. See §Pret grounding for the citations used.

## Lane assignment (anti-conflict)

- **Finisher** — route `bugfix`/`feature`/`migration` (plus the two stray section cards whose route is missing but that duplicate bugfix items).
- **Refactor** — route `refactor` + dead-code/cleanup items in sections M/O/X.
- **Architect** — sections I/J and every `route=architecture` item; already separately tasked, listed here for reference.
- **QA** — test-gap items (M10; status-register F10 residual).

**File-ownership rule:** each source file is owned by exactly ONE lane. If a file carries both bugfix and refactor/QA findings,
**Finisher owns the file now**; the refactor/QA items on that file are deferred until the lead clears them (list at the end).

Sections I/J are Architect-owned **areas** (20 findings already separately tasked). Their cards keep their route-based lane
below so the Finisher/Refactor can act if the lead clears the overlap; each is tagged `Architect ref` in Notes.

## Counts

- Cards parsed: **210** (the task brief said 209; the HTML contains 210 `<article class="card">` elements). Section X's heading says (9) but holds 10 cards.
- Lane counts: Finisher **137** · Refactor **64** · Architect **8** · QA **1**
  - Finisher = 135 route-based (129 bugfix + 1 feature + 5 migration) + 2 unrouted duplicates (C10, F10).
  - Refactor = all 64 `route=refactor` cards (includes the M/O/X dead-code items).
  - Architect = 7 `route=architecture` cards + F9. Sections I/J hold 20 cards in total; the other 12 are refactor/migration/bugfix and are tagged `Architect ref` where they sit in a route lane.
  - QA = M10 (test gaps); status-register F10 residual is listed in the QA section.
- v3 flags: verified=true 34 / verified=false 176; high 112, medium 93, unset 5
- Unrouted cards (no `data-route`): C10, F9, F10, T8; no-confidence cards: C10, F9, F10, T4, T8
- Re-verified: **44** target findings (39 v3 cards + 5 carried `N-*` register items) — invalid/stale **10**, valid **34** (U10 partial, counted valid with correction).
- Wave 2 (74 remaining Finisher rows, worktree @ 1ace9283 + local edits): **VERIFIED 53 / CONFIRMED-BUG 14 / INVALID-stale 6 / DUP 1**; pret-struck fixes **4** (E6, F4, H7, J9). Full details in each row's `W2:` note.

## Pret grounding (USER mandate)

**Rule:** the authoritative source for FireRed/Gen 3 behaviour is `https://github.com/pret/pokefirered` (for RSE ground
claims in `pret/pokeemerald` + `pret/pokeruby`). Engine-side code claims are grounded in the live tree (`file:line`);
pret-semantics claims are cited below or labelled **`[pret-unverified]`** with the pret file that would confirm them.
Where pret and the review report disagree, pret wins (confirmed case: C1 Knock Off).

Local pret checkout used for these citations: canonical team clone **`/Users/shanemcgovern/dev/pokefirered` @ `c75f3523`**
("Merge pull request #770 from Deokishisu/patch-8"). Citation re-verification 2026-09-22: all 12 cited files are
byte-identical to the earlier temp copy and every cited line still matches — **no line drift** (see §Canonical path
re-verification below).

| Finding | Claim checked against pret | Pret citation | Status |
|---|---|---|---|
| C1 | Knock Off clears only the battler's item + sets `knockedOffMons`; party keeps it; send-out masks it | `pokefirered/src/battle_script_commands.c:2730-2752`, `:4489` | CITED |
| E1 | `givemon` = 0x79 + 14 operand bytes (15 total) | `pokefirered/asm/macros/event.inc` (givemon macro) | CITED |
| E2 | `comparestat` = .byte statId + .4byte value (6 bytes) | `pokefirered/asm/macros/event.inc` (comparestat macro) | CITED |
| E3 | `updatemoneybox` = 0x95 + x + y + disable (4 bytes) | `pokefirered/asm/macros/event.inc` (updatemoneybox macro) | CITED |
| E5 | `DaisyMassageServices` writes VAR_MASSAGE_COOLDOWN_STEP_COUNTER (0x4025) = 0 | `pokefirered/src/field_specials.c:2075-2078`, `include/constants/vars.h:75` | CITED |
| H3 | Total record = `GetGameStat(GAME_STAT_LINK_BATTLE_WINS/LOSSES/DRAWS)` | `pokefirered/src/battle_records.c:452-456`; `include/constants/game_stat.h:27-29` | CITED |
| H4 | stat ids: HOF=10, hatched eggs=13, link W/L/D=23/24/25 (18=USED_CUT) | `pokefirered/include/constants/game_stat.h:14,17,20,27-29` | CITED |
| P1 | Heal Bell / Aromatherapy clear NIGHTMARE on attacker + partner | `pokefirered/src/battle_script_commands.c:8015,:8031` (aroma `:8071,:8078`) | CITED |
| P3 | the ten effect ids exist in pret move effects (21/22 marked `// unused`) | `pokefirered/include/constants/battle_move_effects.h:16,18,19,25,26,59,60,65,67,68` | CITED |
| Q3 | `ForcePlayerOntoBike` sets the bike avatar flag + cycling music | `pokefirered/src/field_specials.c:97-103` | CITED |
| Q4 | `ForcePlayerToStartSurfing` sets `PLAYER_AVATAR_FLAG_SURFING` | `pokefirered/src/field_specials.c:1513-1517` | CITED |
| Q8 | `ShakeScreen` / `SampleResortGorgeousMonAndReward` do real work | `pokefirered/src/field_specials.c:461-469`, `:679-688` | CITED |
| Q10 | `gotonative` = 0x24 + .4byte func (replaces script with native fn) | `pokefirered/asm/macros/event.inc` (gotonative macro) | CITED |
| R2 | `ANIMCMD_LOOP` −3, `ANIMCMD_JUMP` −2, `ANIMCMD_END` −1 | `pokefirered/include/sprite.h:84-88` | CITED |
| U10 | the six moves' pret effects + numeric values | `pokefirered/src/data/battle_moves.h:185,510,562,588,1264,1381,1732`; `include/constants/battle_move_effects.h:15,22,23,50,52,54` | CITED |
| T6 | **guard layer settled**: pret guards party-full in the **script layer** — Four Island withdraw `data/maps/FourIsland_PokemonDayCare/scripts.inc:86-88`, Four Island egg `data/maps/FourIsland/scripts.inc:95-104`, Route 5 withdraw `data/scripts/day_care.inc:79-81`; `daycare.c` itself stays index-assign | `pokefirered/src/daycare.c:525,:1081`; `data/maps/FourIsland_PokemonDayCare/scripts.inc:86-88`; `data/maps/FourIsland/scripts.inc:95-104`; `data/scripts/day_care.inc:79-81`; `data/specials.inc:195,203,389` | **CITED / RESOLVED** — engine mirror is the special-handler seam (`natives_daycare.lua`); the egg handler already has the guard (`:290-303`), withdraw handlers do not. No PC spill. |
| E10 | unwired engine opcodes vs pret — **recount: 26, not 63**; per-op spec delivered | one pret `ScrCmd_*` per op in `pokefirered/src/scrcmd.c` (all 26 cited); layouts `asm/macros/event.inc` | **CITED** — full table in `docs/game3/e10-opcode-spec.md`; 16 are pret FRLG no-ops, 10 need wiring, 2 have wrong engine layouts (`0xa8`/`0xa9`). |

Engine-internal verdicts (no pret semantics asserted; grounded in live-tree file:line only): D4, E9, F2, G2, G3, G5, H1,
H2, K1, L6, M7, S1, S2, S6, U4, V2, V3, V5, V6, W5, W9, W10.

### Canonical path re-verification (2026-09-22)

Canonical clone `/Users/shanemcgovern/dev/pokefirered` @ `c75f3523` vs the earlier temp copy
(`/private/var/folders/…/opencode/pokefirered-master`): all 12 cited files are **byte-identical**
(`src/battle_script_commands.c`, `asm/macros/event.inc`, `src/field_specials.c`, `include/constants/vars.h`,
`src/battle_records.c`, `include/constants/game_stat.h`, `include/constants/battle_move_effects.h`, `include/sprite.h`,
`src/data/battle_moves.h`, `src/daycare.c`, `data/specials.inc`, `src/scrcmd.c`), and every cited line was re-read in
the canonical clone → **drift: NO**. All citations in this file now refer to `/Users/shanemcgovern/dev/pokefirered`
@ `c75f3523`.

## Worst 25 (global rank) — lane + re-check

| # | Finding | ID | Route | Lane | Re-check |
|---|---|---|---|---|---|
| 1 | SaveMenu shows "saved the game" even when the write failed | G1 | bugfix | Finisher | — |
| 2 | ~~`Storage.depositItem` destroys items when the PC stack is at 999~~ | N-A25 | bugfix | Finisher | **invalid (stale)** |
| 3 | KNOCK_OFF clears the battler item but never persists it — item reappears | C1 | bugfix | Finisher | — (DONE, see §C) |
| 4 | Thief/Trick persist the stolen item only when the target is the player | C2 | bugfix | Finisher | — |
| 5 | Thief/Trick duplicate items across switch-out | C3 | bugfix | Finisher | — |
| 6 | `Map.load` with a nil def keeps the previous map's collision grid | B1 | bugfix | Finisher | — |
| 7 | Unresolved region-map section silently becomes PALLET TOWN (88) | B6 | bugfix | Finisher | — |
| 8 | ~~`Player.reset` silently discards its `facing` argument~~ | A1 | bugfix | Finisher | **invalid (stale)** |
| 9 | ~~`Player.reset` leaves surfing/surfHopping/dismounting set~~ | N-A2 | bugfix | Finisher | **invalid (stale)** |
| 10 | `Hud.update` calls `Naming.update` with the wrong arg — error swallowed every frame | G4 | bugfix | Finisher | — |
| 11 | ~~`gameStats` is never serialized — jackpots, eggs, link W/L/D all reset~~ | H1 | migration | Finisher | **invalid (stale)** |
| 12 | ~~Link records + trainer-card counters live in unsaved session fields~~ | H2 | migration | Finisher | **invalid (stale)** |
| 13 | ~~Hall of Fame requires a module that does not exist — HOF save is dead~~ | N-A22 | bugfix | Finisher | **invalid (stale)** |
| 14 | ~~Hall of Fame fields written but never serialized~~ | N-A23 | migration | Finisher | **invalid (stale)** |
| 15 | Boot executes cache Lua via unsandboxed `loadstring` | L1 | bugfix | Finisher | — |
| 16 | File browser shells out with an unescaped `io.popen("ls …")` | L3 | bugfix | Finisher | — |
| 17 | OW sprite `.meta` dimensions trusted → multi-GB allocation | L4 | bugfix | Finisher | — |
| 18 | ~~`mids.idx` header dimensions trusted → huge allocation~~ | N-E3 | bugfix | Finisher | **invalid (stale)** |
| 19 | 63 defined script opcodes have no handler | E10 | bugfix | Finisher | — |
| 20 | ~~`givemon` opcode is 6 bytes short of pret → script stream desync~~ | E1 | bugfix | Finisher | **invalid (stale)** |
| 21 | Thick Fat halves SpAtk only — physical Fire/Ice unaffected | C4 | bugfix | Finisher | — |
| 22 | Liquid Ooze recoil missing for Dream Eater | C5 | bugfix | Finisher | — |
| 23 | AI Natural Cure switching only recognises sleep | C6 | bugfix | Finisher | — |
| 24 | Option block hardcoded to the `"firered"` key | J2 | bugfix | Finisher | — |
| 25 | Double OAM build + sort per presented frame (measured) | K1 | refactor | Refactor | verified · **DONE** (oam.lua buildOamBuffer reuses the buffer when set+keys unchanged) |

Prior-register IDs (N-*) are not cards in v3; they were re-checked against source anyway. N-A2/N-A22/N-A23/N-A25/N-E3 are all already fixed (see Notes).
Note: the Worst-25 table's IDs for rows 22–23 are off by one against §C — row 22 (`Liquid Ooze`) is card **C3**, row 23 (`Natural Cure`) is card **C5**. The lane/re-check columns below use the card IDs, so rows 22–23 are listed by the worst-table label.

## Re-verification results (required set)

Set = every unverified high-confidence finding in the Worst 25 + every unverified high-confidence `route=bugfix` card (38),
plus the five carried `N-*` Worst-25 items = 44. `A1` was also checked because it is Worst-25 #8 (v3 marked it verified=true).

### Invalid / stale (do not schedule)

| ID | Title | Why it is stale |
|---|---|---|
| E1 | ~~`givemon` opcode arg layout is 6 bytes short of pret → desync of every later row~~ | Already fixed: opcodes.lua:134 now `op("givemon", 15, { H, B, H, W, W, B })`, matching pret event.inc (2+1+2+4+4+1 operand bytes). |
| E2 | ~~`comparestat` decodes as B,H instead of B,W and has no handler~~ | Already fixed: opcodes.lua:223 `op("comparestat", 7, { B, W })` (pret: .byte statId + .4byte value) and handler at ops_a.lua:792-800. |
| H1 | ~~`gameStats` is never serialized~~ | Already serialized: save_schema_firered.lua:228 (toSaveTable) and :295 (fromSaveTable). |
| H2 | ~~Link-battle records and trainer-card counters live in unsaved session fields~~ | Already serialized: save_schema_firered.lua:231-232 and :297-298 carry linkBattleRecords + trainerCard. |
| N-A2 | ~~Player.reset leaves surfing/surfHopping/dismounting set~~ | Already fixed: player.lua:144-149 clears surfing/surfHopping/dismounting (and biking) in Player.reset. |
| N-A22 | ~~Hall of Fame requires a module that does not exist — HOF save is dead~~ | Module exists: src/ui/game3/hall_of_fame.lua with valid requires; adapters.lua:128-132 wires it. |
| N-A23 | ~~Hall of Fame fields written but never serialized~~ | Already serialized: schema :235-241 / :300-306 carry game_cleared, hasHallOfFameRecords, hallOfFameTeams, hofDebut*. |
| N-A25 | ~~Storage.depositItem destroys items when the PC stack is at 999~~ | Already fixed: storage.lua:437-449 refuses a deposit that would exceed MAX_ITEM_QTY (comment spells out the old loss). |
| N-E3 | ~~mids.idx header dimensions trusted → huge allocation~~ | Already fixed: native_pack.lua:106-125 validates magic, midCount/atlas dims and blob length before reading. |
| A1 | ~~`Player.reset` silently discards its `facing` argument~~ | DRIFT (not in required set): v3 says verified=true, but player.lua:111-115 now assigns Player.facing from the argument. Re-checked because it is Worst 25 #8. |

### Verified against live source

| ID | Title | Evidence (file:line) |
|---|---|---|
| D4 | Sprite/task animate+draw errors are swallowed without releasing the slot | anim_sprites.lua:230-231 and anim_tasks.lua:4863-4865 pcall + print only; no release/recycle on error. |
| E3 | `updatemoneybox` declares 2 byte args but pret consumes 3 | opcodes.lua:167 still `{ B, B }`; pret event.inc emits 0x95 + x + y + disable (4 bytes). Adjacent: 0x94 hidemoneybox declares size 1 while pret consumes 2 dummy bytes (opcodes.lua:166). |
| E5 | `DaisyMassageServices` writes VAR 0x4025 through a nil store, so the write is dropped | natives.lua:406 -> setSpecialVar (natives.lua:54-57) -> Flags.setVar(nil, ...) (flags.lua:361-371): non-special ids need a store; 0x4025 is not in 0x8000-0x8014 (ctx.lua:20-23) and ctx has no setVar method. Pret: `src/field_specials.c:2075-2078`, `include/constants/vars.h:75`. |
| E9 | `checkpartymove` / `incrementgamestat` are stubbed as no-ops | ops_a.lua:1954-1956 groups incrementgamestat/checkpartymove with the genuine erasebox no-op and returns false. |
| F2 | Dex `owned` and `caught` diverge — gifted/traded catches dropped | party.lua:275-279 and natives_trade.lua:360-364 set seen+owned only; schema :120 seeds no `caught`; dex.lua:225 / save_menu.lua:226 read `caught`. |
| G2 | `BagChrome.ready()` does a disk/cache read of `bg.rgba` every frame | bag_chrome.lua:133-137 re-reads bg.rgba on every ready() call; bag_menu.lua:893 calls it from draw(). |
| G3 | Female TM Case / Berry Pouch chrome re-read the background every frame | tm_case_chrome.lua:93-97 latches only on _bgMale; tm_case.lua:250 calls ready() every draw; female path sets _bgFemale (:107-110), so ready() re-reads forever. |
| G5 | Easy Chat plays no sound effects — wrong audio API name | easy_chat.lua:52-55 calls `Aud.playSE` (not `playSe`); audio.lua:574 defines only Audio.playSe. |
| H3 | Link record screen reads the wrong fields — TOTAL RECORD is always 0 | trainer_tower_records.lua:379-381 reads session.linkBattleWins/Losses/Draws; only writer is link/battle.lua:481-487 bumpGameStat into s.gameStats; link/init.lua:499 copies card/stats into link payload, never back to session. Pret: `src/battle_records.c:452-456`, `include/constants/game_stat.h:27-29`. |
| H4 | Sticker-man brag flags use the wrong game-stat ids | natives_events.lua:220-226 reads HOF from stat 13 and eggs from 18; step_events.lua:274-277 writes egg count to 13; stats 18 and 24 have no writers. Pret: `include/constants/game_stat.h:14,17,20,27-29` (13=HATCHED_EGGS, 18=USED_CUT, 24=LINK_BATTLE_LOSSES). |
| K1 | Double OAM build + sort per presented frame | display.lua:244 and :264 both call Oam.buildOamBuffer(), which scans+sorts the global pool (oam.lua:498-510); both planes run per presented frame (display.lua:303-318). DONE — src/core/game3/oam.lua buildOamBuffer reuses the cached buffer when the visible set and sort keys are unchanged (adjacent-pair check on the total comparator); the UI pass no longer re-sorts an unchanged buffer. game3_display_fit / stitchfield / elevation_oam_priority PASS. |
| L6 | `SaveFileIO` export/cart paths interpolate an unchecked slot id | SaveFileIO.lua:27-28 and :197 interpolate slotId unchecked; SaveData.slotNames (:929-932) does the same. Caveat: needs a crafted registry/options entry (local file), so defence-in-depth. |
| M7 | Extractor reads ROM fields then discards them | items_extract.lua:163-174 reads itemId/itemType/fieldUseFunc/battleUseFunc; emitted row :182-193 omits all four. |
| P1 | Heal Bell / Aromatherapy never clears the *user's* Nightmare volatile | healing.lua:138 clears user status without user.expNightmare = nil; partner path :144 does clear it; party loop :148-151 clears status/sleep only. Pret: `src/battle_script_commands.c:8015,:8031` (aroma `:8071,:8078`). |
| P3 | Effect ids 12/14/15/21/22/55/56/61/63/64 have no `STATUS_SETUP` entry and no handler | effect_ids.lua ids 12/14/15/21/22/55/56/61/63/64 absent from STATUS_SETUP (:273+) and STAT_CHANGES (:380+); effects/init.lua:129-130 returns false. Pret: `include/constants/battle_move_effects.h:16,18,19,25,26,59,60,65,67,68` (ids 21/22 marked `// unused`). |
| Q3 | `ForcePlayerOntoBike` writes the wrong state objects | natives_events.lua:131-142 writes session.player.ridingBike / rt.player.ridingBike; Runtime has no .player and nothing reads ridingBike; the live state is Player.biking (player.lua:58). Pret: `src/field_specials.c:97-103`. |
| Q4 | `ForcePlayerToStartSurfing` writes the wrong state objects and leaves bike/hop set | natives_events.lua:145-156 writes session.player.surfing / rt.player.surfing; live state is Player.surfing/surfHopping (player.lua:63-65), never set by the special. Pret: `src/field_specials.c:1513-1517`. |
| Q8 | Real specials registered as blanket no-ops | natives_events.lua:343/345/347/349/370 register ShakeScreen, InitRoamer, SampleResortGorgeousMonAndReward, DisableMsgBoxWalkaway, UpdateLoreleiDollCollection as noops. Pret: `src/field_specials.c:461-469`, `:679-688`. |
| Q10 | `gotonative` is defined but never dispatched, and the `native:` namespace has zero registrations | opcodes.lua:52 defines gotonative with no ops_a branch; natives.lua:885 looks up "native:"..id and only "special:" keys are ever registered (natives.lua:245+). Pret: `asm/macros/event.inc` gotonative macro (0x24 + .4byte func). |
| R1 | `map_tree_extract.simplify_events` reads coord fields that are never written | map_tree_extract.lua:100-101 reads c.trigger/c.index; extract_map_events.lua:146-149 emits var/value (no trigger/index). |
| R2 | `ow_extract.max_anim_frame` stops on `ANIMCMD_JUMP` (-2) while believing it is `END` | ow_extract.lua:104 breaks only on 0xFFFE (JUMP); trade_extract.lua:48 breaks on `v >= 0xFFFD` so END 0xFFFF / LOOP 0xFFFD are skipped. Pret: `include/sprite.h:84-88` (LOOP −3, JUMP −2, END −1). |
| S1 | Slot-machine coin mutations discard the coin API result, leaving bet/payout half-mutated | slot_machine.lua:661-703 pcall() results discarded while st.bet/st.payout/session coins mutate regardless. |
| S2 | Post-trade save path swallows failure and reports done | link/trade.lua:449-455 pcalls both saves, then calls scene().saveDone() unconditionally. |
| S6 | `Moves._runReloadHooks` discards every hook error, unlike `Pokemon._runReloadHooks` | moves.lua:207 `pcall(h.fn, Moves)` discards errors; pokemon.lua:205-208 captures ok/err and logs. |
| T6 | `Daycare.withdraw`/`giveEggFromDaycare` hardcode `party[PARTY_SIZE]` with no party-full guard | daycare.lua:277 and breeding.lua:437-438 index session.party[PARTY_SIZE] with no size check; contrast storage.lua:211-213 party_full guard. Pret RESOLVED: the guard lives in the script layer (`data/maps/FourIsland_PokemonDayCare/scripts.inc:86-88` withdraw, `data/maps/FourIsland/scripts.inc:95-104` egg, `data/scripts/day_care.inc:79-81` Route 5 withdraw), while `src/daycare.c:525,:1081` index-assigns unguarded. Engine's script-layer mirror is the special handlers: `natives_daycare.lua:290-303` already guards the egg; the two withdraw handlers do not. No PC spill. |
| U4 | Repel step counter written to the happiness-counter var slot | encounters.lua:48 declares VAR_REPEL_STEP_COUNT = 0x4021; step_events.lua:301-305 uses 0x4021; flags_table.lua:3210 has REPEL=0x4020 and :3111 HAPPINESS=0x4021. |
| U10 | Seven curated moves point at effect ids that are never registered | PARTIAL: all seven effectId strings are unregistered, but only six moves lack a numeric effect (TAIL_WHIP/LEER/HARDEN/SWORDS_DANCE/AGILITY/AMNESIA, moves.lua:67-75). GROWL also has `effect = EffectIds.ATTACK_DOWN` (18) and resolves via STATUS_SETUP. Fix the six. Pret: `src/data/battle_moves.h:185,510,562,588,1264,1381,1732`; values `include/constants/battle_move_effects.h:15,22,23,50,52,54`. |
| V2 | `session.monBoxId` / `session.monBoxPos` written but not saved | storage.lua:342-343 writes session.monBoxId/monBoxPos; natives.lua:79 reads them with 0+1 defaults; neither key exists in save_schema_firered.lua. |
| V3 | `session.id` / `session.playerId` read, never written | party.lua:250 and mail.lua:163 read session.id/playerId; grep shows zero writers and neither is in the schema. |
| V5 | `session.caughtMonsCount` read, never written | save_menu.lua:228 and trainer_card.lua:361 read caughtMonsCount as a fallback; zero writers in src/. |
| V6 | `dex.owned` vs `dex.caught` divergence | schema :120 seeds owned only; party.lua:277-279 sets owned only; save_menu.lua:54-58 counts dex.caught only; dex.lua:62 uses `caught or owned`. |
| W5 | Pokédex per-screen state is not reset on close/open | pokedex.lua:288-292 resets open/_onClose only; show() :203-207 resets modeCursor/modeScroll/listCursor/cursor/listScroll; dataPage/category state etc. survive. |
| W9 | Summary header has no-op ternaries for the x coordinate | summary_menu.lua:457 `isMovesPage and 8 or 8` and :463 `isMovesPage and 16 or 16` — both branches identical. |
| W10 | Pokédex scroll-arrow animation advances inside `draw` | pokedex_chrome.lua:752, :777, :800 each advance _animTimer inside the three draw functions. |

## Findings by section

### A Correctness: field / runtime (7)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| A1 | ~~`Player.reset` silently discards its `facing` argument~~ | bugfix | high | true | invalid (stale) | src/core/game3/player.lua:113 | `Player.facing = (DELTA[facing] and facing) or Player.facing or "down"` at the top of `reset`. | Finisher | DRIFT (not in required set): v3 says verified=true, but player.lua:111-115 now assigns Player.facing from the argument. Re-checked because it is Worst 25 #8. |
| A2 | Field teardown leaks fishing and warp-lock flags | bugfix | medium | false | VERIFIED | src/core/game3/field.lua:70, field.lua:994 | Clear those flags in `Field.stop()` and `Field.start`. | Finisher | W2: field.lua:70-76 clears only running/_session/locked/_waterfall/_tempFlagMap; _fishing cleared only at :994; unlock guards :188/:190; _flyLanding :1230-1233. |
| A3 | Warp busy/escalator flags have no production reset | bugfix | medium | true | VERIFIED | src/core/game3/warp.lua:711, player.lua:817 | Call `Warp.clear()` from `Field.stop()`/`Runtime.stop`/`Game3:reset`. | Finisher | W2: warp.lua sets _busy at :113/:168/:228, clears only inside callbacks :149/:206; Warp.clear (:741) has zero callers in src/. v3 line :711 drifted. |
| A4 | Door sheet Images/Quads have no release path | bugfix | medium | false | VERIFIED | src/core/game3/doors.lua:558, field_effects.lua:120,136 | Add `Doors.release()` and call it from reset. | Finisher | W2: doors.lua:558 newImage, :565 newQuad, :577 cached in Doors._sheets; no release function exists in the file. |
| A5 | `Doors.loadSheet` can raise on a malformed manifest row | bugfix | medium | false | VERIFIED | src/core/game3/doors.lua:537 | Validate the three fields before use; cache `false` on failure. | Finisher | W2: doors.lua:501-505 guards a missing info row; malformed fields raise at :537 (info.width*info.height) and :544 (newImageData outside pcall); caller loadSheet (:595) is not wrapped. |
| A6 | `PcAnim` blanks a metatile when `VAR_0x8004` is out of range | bugfix | medium | true | VERIFIED | src/core/game3/pc_anim.lua:66 | Range-check `var` before indexing; drop the `or 0`. | Finisher | W2: pc_anim.lua:64-66 `(ON[var] or ... or 0)` -> set_mid(0) blanks the metatile for an out-of-range VAR_0x8004. |
| A7 | `Player.startSurfing` can strand `surfHopping` if the forced step is refused | bugfix | medium | false | VERIFIED | src/core/game3/player.lua:588 | Revert `surfHopping` when `forceStep` returns false. | Finisher | W2: player.lua:595-610 startSurfing sets surfHopping=true then ignores forceStep's return; forceStep returns false at :531/:533 (moving/invalid dir). |

### B Correctness: maps / collision / data (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| B1 | `Map.load` skips `Collision.bindMap` when `def` is nil | bugfix | high | true | — | map.lua:288 | Return an error before mutating, or `Collision.clear()`. · bugfix · high | Finisher |  |
| B2 | Zero-dimension `midLayout` yields a truthy-but-empty grid, disabling the host fallback | bugfix | medium | false | VERIFIED | layout_native.lua:60, collision.lua:769-770 | Guard `n == 0`: return nil/fall through to the host grid instead of an empty truthy grid. | Finisher | W2: layout_native.lua:60-71 collArray returns a truthy empty {} when width*height==0; collision.lua:769-770 then bounds-fails every step. |
| B3 | Extract silently drops maps whose layout spec or tileset bundle is missing | bugfix | medium | true | VERIFIED | extract_island1.lua:320 | Report dropped maps (log + non-success status) instead of silently skipping the layout. | Finisher | W2: extract_island1.lua:319-321 still skips silently (no else/log) when layoutSpec/bundle missing. |
| B4 | `nativeReady` accepts the cache after checking only the first pairs entry | bugfix | medium | false | VERIFIED | extract_island1.lua:199 | Smoke-check every pairs entry (all `mids_over.idx` present) before `nativeReady` returns true. | Finisher | W2: extract_island1.lua:197-201 `return true -- smoke-check first pair` still inside the pairs loop. |
| B5 | Transient cache-read failures are cached as permanent negatives | bugfix | medium | false | VERIFIED | map_preview_screen.lua:157, region_map.lua:315, heal_locations.lua:108 | Don't cache negatives on transient failure (retry on next probe / clear on version mount). | Finisher | W2: map_preview_screen.lua:157 _manifestTried latch, :204 _images[artwork]=false, region_map.lua:315 `img or false` — transient failures cached for the session. |
| B6 | Unresolved region-map section silently becomes 88 = PALLET TOWN | bugfix | high | true | — | dataset.lua:208, map_sections_extract.lua:366 | Keep the unresolved flag and surface it; don't advertise the 88/PALLET TOWN fallback. | Finisher |  |
| B7 | START snap cycle advertises three targets but implements two | bugfix | medium | false | VERIFIED | region_map.lua:713-715 | Implement the third START snap target or drop it from the comment/cycle. | Finisher | W2: region_map.lua:713 comment lists three snap targets; :715 uses `% 2`. |
| B8 | Dungeon markers use a 32px origin while every sibling marker uses 28px | bugfix | medium | false | VERIFIED | region_map.lua:641-642 | Use the 28px MAP_OFFSET_X origin for dungeon markers. | Finisher | W2: region_map.lua:641 `32 + x*CELL` vs MAP_OFFSET_X=28 (:28, used at :164/:829/:889). |
| B9 | `Map.refreshWorld` cache is not invalidated on reload | refactor | medium | false | — | map.lua:131-133 | Set `_worldRoot` in Map.load and clear it in WorldAPI:invalidateMap. | Refactor | DONE — map.lua half only per carve condition: `src/core/game3/map.lua:287-291` clears `Map._worldRoot` inside `Map.load`. Proof: `/tmp/b9_repro.lua` FAILED pre-fix (2/2 checks: `_worldRoot` stayed `FR_TEST_A` and refreshWorld returned the cached table) → PASSES post-fix (3/3). Suites BEFORE+AFTER green: game3_map_onload, stitchmap_header, stitchmap_bike, stitchmap_heal, stitchfield_ground/onframe/whiteout, encounters_flash, stitchcoll_escape_warp, tests/engine/game3_map_def_less_bind. pret: `pokefirered/src/overworld.c:792` `LoadMapFromWarp → LoadCurrentMapData()` and `overworld.c:759` `LoadMapFromCameraTransition → LoadCurrentMapData() → InitMap()` (`:772`) — pret re-reads map data on every load path, no cross-load map cache. WorldAPI:invalidateMap half deliberately NOT done (B10 not-DONE, ambiguous basename). |
| B10 | `effectiveEncounters` swallows `ensureLoaded` failure and reports a zero-rate table | bugfix | medium | false | VERIFIED | WorldAPI.lua:387 | Propagate the `ensureLoaded` failure (nil/error) instead of reporting a zero-rate table. | Finisher | W2: world/game3/WorldAPI.lua:381-389 pcall(ensureLoaded) then reads E._tables — failures indistinguishable from zero-rate. |

### C Correctness: battle core (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| C1 | KNOCK_OFF clears the battler item but never persists the removal — **DONE** | bugfix | high | true | — | `effects/secondary.lua:462-479`, `state.lua:65-67`, `state.lua:426-455` | ~~Persist the knock-off (`persistItem(effBattler, 0)`) like the `:371-372` site.~~ **WRONG for FRLG (Gen 4+ semantics).** Correct shipped mechanism: clear only the live battler (`effBattler.item = 0`) + set the battle-scoped `knockedOffMons` bit (`State.markKnockedOff`), with the send-out mask re-clearing `b.item = 0` on every later entry — no party-mon write-through (pret `battle_script_commands.c:2730-2752` / `:4489`). | Finisher | **DONE** — Finisher fix log row `01a0c869-4b7b-7660-a1a0-4faf2be94d27` ("Fix Knock Off foeParty item wipe"). Tests: `tests/engine/game3_knock_off_item_test.lua` 14/14, `tests/engine/game3_knocked_off_flag_test.lua` 5/5, `tests/game3_battle_move_effects_test.lua` 126/0. Do not re-break with a party write-through. |
| C2 | Thief/Trick persist the stolen item only when the target is the player | bugfix | high | true | — | effects/secondary.lua:372, effects/special.lua:322 | Persist the stolen/swapped item for both sides; drop the player-only guard. | Finisher |  |
| C3 | Liquid Ooze recoil is applied for Absorb but not Dream Eater | bugfix | high | true | — | effects/hit.lua:373 | Apply Liquid Ooze recoil to DREAM_EATER as well (extend the drain check at hit.lua:373). | Finisher |  |
| C4 | Thick Fat halves SpAtk only, so physical Fire/Ice moves are unaffected | bugfix | high | true | — | damage.lua:234-236 | Halve physical Fire/Ice attack too (branch on move type before the move-type split). | Finisher |  |
| C5 | AI Natural Cure switching only recognises sleep | bugfix | high | true | — | ai_switch.lua:145-146 | Treat any status Natural Cure can clear as a switch cue, not just SLP. | Finisher |  |
| C6 | `mostSuitableMon` applies STAB from the switching-out battler's types | bugfix | medium | false | VERIFIED | engine.lua:1846 | Score STAB from the candidate mon's own types, not the switching-out battler's. | Finisher | W2: battle/engine.lua:1846 applies STAB from `active` (the switching-out battler) inside mostSuitableMon (:1764). |
| C7 | AI `get_protect_count` reads a field that is never written | bugfix | medium | false | VERIFIED | ai_cmds.lua:910, effects/volatiles.lua:26 | Read the real counter (`user.expProtectStreak`) in ai_cmds.lua. | Finisher | W2: ai_cmds.lua:910 reads b.protectUses; the live counter is expProtectStreak (effects/volatiles.lua:14-26). |
| C8 | Post-action `HeldItems.normal` pass is hardcoded to the player side | bugfix | medium | false | VERIFIED | engine.lua:1357 | Run the post-action HeldItems.normal pass for both sides. | Finisher | W2: battle/engine.lua:1357 post-action pass hardcoded to `st.player` (HeldItems.normal(ad, st.player, true)). |
| C9 | `sortedBattlers` re-rolls the speed-tie break on every call | bugfix | medium | false | VERIFIED | residuals.lua:57, engine.lua:2025 | Compute the speed-tie roll once per turn/sort and cache it for all callers. | Finisher | W2: residuals.lua:56-58 rolls adapter:roll(0,1) inside the sort comparator; sort re-runs from residuals/handlers/engine every turn. |
| C10 | `State.makeBattler` rebuilt per candidate in switch scoring | — | — | false | DUP | — | n/a — recorded as covered by C6; no standalone fix. | Finisher | duplicate; recorded for completeness W2: recorded-for-completeness duplicate of C6; no standalone work (same makeBattler-in-switch-scoring claim).|

### D Correctness: battle flow / animation (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| D1 | Per-sprite-per-frame option-table allocation in the anim draw path | refactor | high | false | — | anim_vm.lua:667, anim_pal.lua:321, g2_pret.lua:960 | Hoist the tint option tables (reuse one table; set fields per sprite). | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| D2 | `gSineTable` copies drift from the canonical `Trig.SINE` | refactor | high | true | — | anim_tasks.lua:10, g2_pret.lua:55, g3_pret.lua:8 | Use the canonical `Trig.SINE`; delete the anim_tasks/g2/g3 copies. | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| D3 | Single global busy flags for HP/EXP tweens can be cleared by the wrong tween | bugfix | medium | false | VERIFIED | — | Guard the busy flags with a tween id/owner instead of a single global boolean. | Finisher | W2: anim.lua:521/:561 set the shared flags, :529/:575 clear them unconditionally on tween completion, :246-247 reset; busy reads at :363/:370-371. |
| D4 | Sprite/task animate+draw errors are swallowed without releasing the slot | bugfix | high | false | verified | anim_sprites.lua:230-231, anim_tasks.lua:4863-4865 | On pcall failure, release the sprite/task slot (mirror the cb error path). | Finisher | anim_sprites.lua:230-231 and anim_tasks.lua:4863-4865 pcall + print only; no release/recycle on error. |
| D5 | Visual-task pool exhaustion silently drops effects and skips waits | bugfix | medium | false | VERIFIED | anim_tasks.lua:4837-4838, anim_vm.lua:1301-1305 | Grow/block the task pool on exhaustion instead of silently dropping the effect. | Finisher | W2: anim_tasks.lua:4837-4838 print+return nil; anim_vm.lua createvisualtask (:1006-1010) returns true regardless; waitforvisualfinish (:1323-1331) passes when visualCount()==0. |
| D6 | Catch breakout dereferences `ball.mon` with no nil guard | bugfix | medium | false | VERIFIED | catch_seq.lua:564, anim.lua:198 | Nil-guard `b.mon` before dereferencing in BallOpen.tick. | Finisher | W2: catch_seq.lua:564 dereferences b.mon with no nil guard while :720 `Anim.present(target)` can return nil. |
| D7 | EvoSeq visual mode can stall the post-win flow if the scene never calls `onDone` | bugfix | medium | false | VERIFIED | evo_seq.lua:118-119 | Add a failure/timeout path so a scene that never calls onDone cannot stall the award flow. | Finisher | W2: evo_seq.lua:118 sets _waiting, :149 early-returns while set; resets only at :13/:23/:41/:47 — no timeout path. |
| D8 | `AnimTasks.clear_task` leaves non-underscore task fields on recycled slots | refactor | medium | false | — | anim_tasks.lua:52-53, anim_sprites.lua:58 | Clear all task fields on recycle (mirror `anim_sprites.lua:58`). | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| D9 | `SwitchSeq` mutates the step's shared `sides` table when sorting | refactor | medium | false | — | switch_seq.lua:707 | Copy the `sides` list before sorting; don't mutate the authored `d.sides`. | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| D10 | BattleTransition canvases/quads survive `abort()` and are never released | bugfix | medium | false | VERIFIED | battle_transition.lua:1685-1691 | Release `_mosaicCanvas`/quads in `finish()`/`abort()`. | Finisher | W2: finish() (:1547-1554) and abort() (:1556-1561) release nothing; _mosaicCanvas only touched at :1685/:1690, never freed. |

### E Correctness: scripting (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| E1 | ~~`givemon` opcode arg layout is 6 bytes short of pret → desync of every later row~~ | bugfix | high | false | invalid (stale) | opcodes.lua:134, disasm.lua:94-108, extract_scripts.lua:198 | STALE — already fixed: opcodes.lua:134 is `op("givemon", 15, {H,B,H,W,W,B})` matching pret. No action. | Finisher | Already fixed: opcodes.lua:134 now `op("givemon", 15, { H, B, H, W, W, B })`, matching pret event.inc (2+1+2+4+4+1 operand bytes). |
| E2 | ~~`comparestat` decodes as B,H instead of B,W and has no handler~~ | bugfix | high | false | invalid (stale) | opcodes.lua:217, ops_a.lua | STALE — already fixed: opcodes.lua:223 is `op("comparestat", 7, {B,W})` and ops_a.lua:792 handles it. No action. | Finisher | Already fixed: opcodes.lua:223 `op("comparestat", 7, { B, W })` (pret: .byte statId + .4byte value) and handler at ops_a.lua:792-800. |
| E3 | `updatemoneybox` declares 2 byte args but pret consumes 3 | bugfix | high | false | verified | opcodes.lua:162 | Widen `updatemoneybox` to `{B,B,B}` (size 4): pret consumes x, y and the disable byte. | Finisher | opcodes.lua:167 still `{ B, B }`; pret event.inc emits 0x95 + x + y + disable (4 bytes). Adjacent: 0x94 hidemoneybox declares size 1 while pret consumes 2 dummy bytes (opcodes.lua:166). |
| E4 | `PlayCry` guards on `ctx:getVar`, a method `Ctx` never defines | bugfix | high | true | — | natives.lua:714-720, ctx.lua | Use `Flags.getVar(store, ctx, 0x8000)` instead of the nonexistent `ctx:getVar`. | Finisher |  |
| E5 | `DaisyMassageServices` writes VAR 0x4025 through a nil store, so the write is dropped | bugfix | high | false | verified | natives.lua:406 | Pass the live store (`Space.store`/`session.store`) when writing VAR 0x4025. | Finisher | natives.lua:406 -> setSpecialVar (natives.lua:54-57) -> Flags.setVar(nil, ...) (flags.lua:361-371): non-special ids need a store; 0x4025 is not in 0x8000-0x8014 (ctx.lua:20-23) and ctx has no setVar method. |
| E6 | `addmoney`/`removemoney`/`checkmoney` VarGet a raw word and ignore the disable byte | bugfix | medium | false | CONFIRMED-BUG | ops_a.lua:1424-1428 | ~~Read the disable byte (`row[2]`) and treat the amount as VarGet-capable.~~ **Pret-corrected: pret reads the amount RAW (scrcmd.c:1798) — do NOT make it VarGet-capable; the real gap is the unread disable byte: apply the money change only when row[2]==0.** | Finisher | W2 pret: scrcmd.c:1798-1807 reads amount as a RAW word plus an ignore byte (applies only when !ignore). Engine ops_a.lua:1717-1736 VarGets amounts >=0x4000 and never reads the disable byte (row[2]). |
| E7 | `random` reads its operand raw where pret uses VarGet | bugfix | medium | false | CONFIRMED-BUG | ops_a.lua:1610-1612 | VarGet the operand before using it as the modulus. | Finisher | W2 pret: scrcmd.c:455-461 ScrCmd_random does `VarGet(ScriptReadHalfword)`; engine ops_a.lua:1903-1908 reads row[1] raw with no VarGet (line drift from v3 :1610). |
| E8 | VarGet parity cluster: several handlers read raw operands where pret uses VarGet | bugfix | medium | false | CONFIRMED-BUG | ops_a.lua:746 | VarGet the operand reads in the listed handlers (buffernumberstring, warp coords, setmetatile, field effects, setweather). | Finisher | W2 pret: ScrCmd_warp VarGets x/y, ScrCmd_setweather/:setmetatile VarGet operands, ScrCmd_buffernumberstring VarGets — engine reads raw (ops_a.lua:1156/:1328/:1369/:1004) and flags.lua:350-358 Flags.getVar lacks pret's passthrough (event_data.c:235-241 returns idx when not a var). |
| E9 | `checkpartymove` / `incrementgamestat` are stubbed as no-ops | bugfix | high | false | verified | ops_a.lua:1660-1662 | Implement `checkpartymove` (VAR_RESULT + VAR_0x8004) and `incrementgamestat`. | Finisher | ops_a.lua:1954-1956 groups incrementgamestat/checkpartymove with the genuine erasebox no-op and returns false. |
| E10 | 26 (not 63) defined opcodes have no handler and fall through to the generic skip path — **SPEC DONE** | bugfix | high | true | — | opcodes.lua, ops_a.lua | Recount + per-op pret spec in `docs/game3/e10-opcode-spec.md`: 16 are pret FRLG no-ops (wire explicit `return false`), `choosecontestmon` yields, 9 need real wiring (`setmysteryeventstatus`, `gotonative`, `gettime`, `setobjectsubpriority`, `resetobjectsubpriority`, `createvobject`, `turnvobject`, `loadhelp`, `unloadhelp`); `0xa8`/`0xa9` declared layouts are wrong (under-read 1 byte). | Finisher | SPEC DONE 2026-09-22 — review's 63 no longer reproduces (all named examples except `createvobject`/`turnvobject` now have cited handlers); pret-side 26/26 grounded at c75f3523. |

### F Correctness: save / data (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| F1 | `PokedexData.getEntry` calls a method that does not exist | bugfix | high | true | — | pokedex_data.lua:187, pokemon.lua:287 | Call `Pokemon.national(sp)` (fallback to `sp`). | Finisher |  |
| F2 | Dex `owned` and `caught` diverge — gifted/traded catches dropped | bugfix | high | false | verified | party.lua:275-279, natives_trade.lua:360-364, save_schema_firered.lua:120 | Set `caught` wherever `owned` is set (gift/trade paths) or seed `caught` in the schema. | Finisher | party.lua:275-279 and natives_trade.lua:360-364 set seen+owned only; schema :120 seeds no `caught`; dex.lua:225 / save_menu.lua:226 read `caught`. |
| F3 | Save schema field asymmetry | refactor | high | false | — | save_schema_firered.lua:189-190 | Write/read the same keys symmetrically (engine/version/generation); drop dead legacy reads. | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| F4 | Daycare withdraw/egg writes party slot 6 with no party-full guard | bugfix | medium | false | CONFIRMED-BUG | daycare.lua:276-277, breeding.lua:437-438, natives_daycare.lua:179-190 | ~~Guard party-full (spill to PC) and append instead of index-assigning party[PARTY_SIZE].~~ **Pret-corrected: no PC spill and no append — pret index-assigns party[PARTY_SIZE-1]; add the party-full guard in natives_daycare.lua handlers (mirror :290-303); keep daycare.lua/breeding.lua as-is.** | Finisher | W2 pret: guard belongs to the script/handler layer — FourIsland_PokemonDayCare scripts.inc:86-88, FourIsland scripts.inc:95-104, day_care.inc:79-81; daycare.c:525/:1081 index-assign on purpose. Engine natives_daycare.lua:179-201 (withdraw) has no guard; the egg handler does (:290-303). **DONE** — shared `partyIsFull` at natives_daycare.lua:78 into both withdraw handlers (:199, :218) + the egg (:324); `daycare.lua`/`breeding.lua` untouched. Tests: game3_daycare_breeding/hatch/menu/model all rc=0 (model test 9 split guard vs `Daycare.take` write-through pin, new 9b Route 5 guard). |
| F5 | `sanitize_pockets` merges misplaced stacks past pocket capacity and the 999 cap | bugfix | medium | false | VERIFIED | bag.lua:97-106 | Clamp/refuse merges past pocket capacity and MAX_ITEM_QTY during sanitize. | Finisher | W2: bag.lua:97-107 merges/append misplaced stacks with no capacity or 999-cap check. |
| F6 | `Bag.add` new-slot branch reports unclamped quantity as placed | bugfix | medium | false | VERIFIED | bag.lua:299-304 | Return the clamped placed amount, not the requested qty. | Finisher | W2: bag.lua:300-305 stores Items.clampGame3(qty) then `return true, qty` (unclamped); existing-slot path correctly returns `placed`. |
| F7 | `Storage.deserialize` keeps the default starter Potion when `items` is absent | bugfix | medium | false | VERIFIED | storage.lua:553-564 | Start from an empty item list when `data.items == nil` (don't keep the seeded starter Potion). | Finisher | W2: storage.lua:553-564 keeps the seeded Potion (Storage.new :52-53, id 13) whenever data.items is nil. |
| F8 | RNG partial state does not round-trip | bugfix | medium | false | VERIFIED | rng.lua:132-137, save_schema_firered.lua:186 | Reject partial RNG state on restore (require every field) and validate it. | Finisher | W2: rng.lua:131-137 setState accepts any subset; :174-179 restoreFromSession returns true for any table (even {}); schema :186 stores it. |
| F9 | `PokedexData` a4rea/map-group source is FireRed-only | — | — | false | — | — | n/a — correctness-adjacent duplicate; see J6 (Architect). | Architect | correctness-adjacent duplicate of J6 |
| F10 | ~~`storage.depositItem` overflow (carried A25 / re-reported as G-series)~~ | — | — | false | INVALID (stale) | — | STALE — same defect as N-A25, already fixed in storage.lua:437-449. No action. | Finisher | duplicate of N-A25 (already fixed) W2: duplicate of N-A25, already fixed — storage.lua:441-444 refuses stack overflow with `pc_item_stack_full` (comment spells out the old loss).|

### G Correctness: UI menus (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| G1 | SaveMenu reports "saved the game" even when the save failed | bugfix | high | true | — | save_menu.lua:94-133 | Capture both pcall results; only enter the "saved" phase when the writes succeeded. | Finisher | **DONE (verified in tree)** — `do_save` now pcalls `persistSessionOnly` + `game.saveGame` and only sets `_phase = "saved"` on a truthy write; pinned by `tests/engine/game3_save_menu_failure_test.lua` (refused/throwing/absent `saveGame` → `save_failed`, confirmed write → `saved`), green in the 25-suite engine run. |
| G2 | `BagChrome.ready()` does a disk/cache read of `bg.rgba` every frame | bugfix | high | false | verified | bag_chrome.lua:136, bag_menu.lua:893 | Memoize the ready check (latch the result) instead of reading bg.rgba every frame. | Finisher | bag_chrome.lua:133-137 re-reads bg.rgba on every ready() call; bag_menu.lua:893 calls it from draw(). |
| G3 | Female TM Case / Berry Pouch chrome re-read the background every frame | bugfix | high | false | verified | tm_case_chrome.lua:2-3 | Latch `_bgFemale`/memoize ready so female saves stop re-reading the background. | Finisher | tm_case_chrome.lua:93-97 latches only on _bgMale; tm_case.lua:250 calls ready() every draw; female path sets _bgFemale (:107-110), so ready() re-reads forever. |
| G4 | `Hud.update` calls `Naming.update` with the wrong argument type, erroring every frame | bugfix | high | true | — | hud.lua:183, naming.lua:489 | Call `Naming.update(input, dt)` with the input object (or fix the arity contract). | Finisher |  |
| G5 | Easy Chat plays no sound effects — wrong audio API name | bugfix | high | false | verified | easy_chat.lua:53-54, audio.lua:574 | Use `Aud.playSe` (correct casing). | Finisher | easy_chat.lua:52-55 calls `Aud.playSE` (not `playSe`); audio.lua:574 defines only Audio.playSe. |
| G6 | `pc_menu` rebuilds its menu row tables (and `Strings`) every frame / input | refactor | high | false | — | pc_menu.lua:568 | Hoist menu row tables and `Strings()` out of draw/handleInput; rebuild on state change only. | Refactor | DONE — src/ui/game3/pc_menu.lua root rows cached via PcMenu._rootEntries() keyed on names + Strings.active(); both input and draw paths use it; pc/box suites PASS. |
| G7 | `shop_menu` rebuilds stock/sell rows and price/name strings every frame | refactor | high | false | — | shop_menu.lua:594 | Cache stock/sell rows; rebuild only when the shop/pocket state changes. | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| G8 | `commit_buy` Premier Ball bonus is uncapped/unchecked and its result ignored | bugfix | medium | false | VERIFIED | shop_menu.lua:262 | Capacity-check the Premier Ball add and log when it is not granted. | Finisher | W2: shop_menu.lua:264 Bag.add(bag, 12, 1) result discarded; the capacity check at :239 covers only the purchased balls. |
| G9 | `commit_sell` ignores `Bag.remove` failure and still pays out | bugfix | medium | false | VERIFIED | shop_menu.lua:281 | Check `Bag.remove`'s result and pay out only on success. | Finisher | W2: shop_menu.lua:281-282 Bag.remove result discarded, then money credited unconditionally. |
| G10 | ~~`Storage.depositItem` overflow, surfaced from the PC menu~~ | bugfix | medium | false | INVALID (stale) | storage.lua:440 | STALE — see N-A25; deposit overflow is refused now (storage.lua:437-449). No action. | Finisher | W2: same N-A25 defect, already fixed — storage.lua:441-444; pc_menu paths reach only the guarded code. |

### H Correctness: link / new feature subsystems (7)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| H1 | ~~`gameStats` is never serialized~~ | migration | high | false | invalid (stale) | save_schema_firered.lua:187-230, slot_machine.lua:635, link/battle.lua:487 | STALE — `gameStats` is serialized (schema :228/:295). No action. | Finisher | Already serialized: save_schema_firered.lua:228 (toSaveTable) and :295 (fromSaveTable). |
| H2 | ~~Link-battle records and trainer-card counters live in unsaved session fields~~ | migration | high | false | invalid (stale) | link/battle.lua:458 | STALE — `linkBattleRecords`/`trainerCard` are serialized (schema :231-232/:297-298). No action. | Finisher | Already serialized: save_schema_firered.lua:231-232 and :297-298 carry linkBattleRecords + trainerCard. |
| H3 | Link record screen reads the wrong fields — TOTAL RECORD is always 0 | bugfix | high | false | verified | trainer_tower_records.lua:379-381, link/battle.lua:481-487, trainer_card.lua:401-402 | Read `gameStats.linkBattleWins/Losses/Draws` (or `trainerCard.*`) in Records.totalText and trainer_card. | Finisher | trainer_tower_records.lua:379-381 reads session.linkBattleWins/Losses/Draws; only writer is link/battle.lua:481-487 bumpGameStat into s.gameStats; link/init.lua:499 copies card/stats into link payload, never back to session. |
| H4 | Sticker-man brag flags use the wrong game-stat ids | bugfix | high | false | verified | natives_events.lua:219-225, step_events.lua:275-277 | Align stat ids with pret (HOF 10, eggs 13, link wins 23) and with the step_events writer. | Finisher | natives_events.lua:220-226 reads HOF from stat 13 and eggs from 18; step_events.lua:274-277 writes egg count to 13; stats 18 and 24 have no writers. |
| H5 | Trainer Tower stashes a full deep copy of the party in the save and never clears it | bugfix | medium | false | CONFIRMED-BUG | trainer_tower.lua:535-536 | Clear `savedPlayerParty` after the tower run; don't persist the snapshot. | Finisher | W2 pret: Trainer Tower operates on the live party (trainer_tower.c:1033-1035) and stashes no copy in the save; load_save.c:167-170 is the ordinary party save, not a TT stash. Engine trainer_tower.lua:535-536 deep-copies into block+session, re-stores at :554-555, never clears (read at :808). **INVALID (fix-as-written) — lead-adjudicated:** (i) clearing on Load is pret-unfaithful — `src/load_save.c:170` LoadPlayerParty deliberately does NOT consume the save-block copy, so mid-flow durability is correct pret behaviour and `game3_tower_party_test` test 3's pin stands (the attempted clear was reverted; suite rc=0 ×2); (ii) the residual (a stale copy lingering after the challenge bracket) has no pret-faithful clear point — the engine has no run-end event after the final Load (`src/trainer_tower.c:1033-1035` runs on the live party, not a stash). Residual routed to the Architect as design seam item 8 (may resolve as 'no action'). No further Finisher code work on H5. |
| H6 | Mystery Gift accepts an unvalidated gift payload, allowing a species-0 party mon | bugfix | medium | false | CONFIRMED-BUG | mystery_gift.lua:410-422 | Validate gift species/level/egg payload before giveMon/giveEgg. | Finisher | W2 pret: mystery_gift.c:191-210 ValidateWonderCard checks exactly the five card fields the engine checks (identical); pret WonderCard carries NO species payload — the engine's gift.species path (mystery_gift.lua:856-865) validates nothing before Party.giveMon/giveEgg (species-0 injectable). |
| H7 | ~~Mystery Gift `recordTrainerId` shifts an existing trainer to the front, diverging from pret's LRU~~ | bugfix | medium | false | INVALID (stale) | mystery_gift.lua:730-740 | ~~Return false without reordering when the trainer id already exists (pret LRU).~~ **Pret-corrected: no change needed — pret reorders an existing trainer to the front too (mystery_gift.c:620-627); engine is already pret-correct.** | Finisher | W2 pret: mystery_gift.c:599-628 RecordTrainerId DOES shift an existing trainer back to the front before returning FALSE — engine (mystery_gift.lua:726-740) matches pret exactly. Review claim reversed. |

### I Architecture / coupling (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| I1 | `gfx.lua` is the Gen 3 UI router misnamed as drawing primitives | refactor | high | false | — | gfx.lua:1 | Split draw primitives from the UI router; move `drawUi` dispatch into a UI module. | Refactor | Architect ref — section area already separately tasked. DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| I2 | Core scripting depends on 16 UI screens | architecture | high | false | — | scripting/adapters.lua:128, ops_a.lua:7 | Replace scripting→UI requires with adapter seams/callbacks. | Architect | Architect ref — section area already separately tasked. |
| I3 | New cycle `display ⇄ gfx`, plus `display → ui.help_system` | refactor | high | false | — | gfx.lua:5 | Break display⇄gfx by moving the UI pass behind an injected renderer. | Refactor | Architect ref — section area already separately tasked. DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| I4 | `hud ⇄ runtime` cycle | refactor | high | false | — | hud.lua:279, runtime.lua:59 | Inject the HUD into runtime (or lazy-require at call sites) to break hud⇄runtime. | Refactor | Architect ref — section area already separately tasked. DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| I5 | The whole Gen 3 tree is one 102-module SCC | architecture | high | false | — | — | Carve field/battle/ui seams and enforce them with a load-order test (see docs/architecture.md). | Architect | Architect ref — section area already separately tasked. |
| I6 | Additional load-order cycles outside Gen 3 | refactor | high | false | — | Data.lua:262, CacheFs.lua:231, SaveData.lua:20 | Untangle the listed cycles (lazy requires at call sites, injected deps). | Refactor | Architect ref — section area already separately tasked. DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| I7 | `import/gba` metadata cycle `versions ⇄ map_catalog ⇄ map_tree ⇄ extract_map_events` | migration | high | false | VERIFIED | versions.lua:2387, map_catalog.lua:104, map_tree.lua:5 | Drop versions→map_catalog; pass catalog data in. | Finisher | Architect ref — section area already separately tasked. W2: versions.lua:2392 requires map_catalog while map_catalog.lua:4 requires versions (cycle); map_tree.lua:4-5; extract_map_events.lua:4 — all four edges present.|
| I8 | runtime → extractor → runtime, with a concrete instance | migration | high | false | VERIFIED | encounters.lua:659, pokemon.lua:3, extract_island1.lua:336 | Keep extractor requires out of runtime init paths (lazy/injected). | Finisher | Architect ref — section area already separately tasked. W2: pokemon.lua:3 -> extract_island1.lua:336 -> extract_scripts.lua:454 -> encounters.lua:73 (back to extract_island1) — cycle confirmed.|
| I9 | Extractor reaches into `src.world.gen2` runtime | migration | high | false | VERIFIED | native_pack.lua:392 | Move shared helpers out of `src.world.gen2` or inject them. | Finisher | Architect ref — section area already separately tasked. W2: native_pack.lua:407 requires src.world.gen2.Permissions (line drift from v3 :392).|
| I10 | Duplicated responsibility: three collision modules and two bg modules | architecture | high | false | — | core/game3/collision.lua:1, core/game3/scripting/collision.lua:1, src/world/Collision.lua:1 | Consolidate to one collision module and one bg module per layer. | Architect | Architect ref — section area already separately tasked. |

### J Portability (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| J1 | FireRed conflation at the save layer | architecture | high | false | — | save_schema_firered.lua:189-190, SaveData.lua:1132, Game3.lua:46 | Key save/Continue on the actual version, not the FireRed literal. | Architect | Architect ref — section area already separately tasked. DEFERRED — Architect-owned (J1) per the triage lane table; no edit made. |
| J2 | Option block hardcoded to `"firered"` | bugfix | high | true | — | options.lua:5 | Derive the options block from GameVersion instead of the `"firered"` literal. | Finisher | **DONE via RSE patch T1.1** — `Options.block(engine, blockId)` + `Options.blockId(session)` now read `Profile.of(session.version).optionsBlock` (`options.lua:5-11,43-73`); `Options.BLOCK` stays as the fallback id for compatibility. New `tests/engine/game3_options_block_test.lua` 15/15, full gate green. |
| J3 | Kanto badge ids and names welded into UI | refactor | medium | false | — | trainer_card.lua:212-213 | Source badge flags/names from the active version's badge table. | Refactor | Architect ref — section area already separately tasked. DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| J4 | Whiteout/heal destinations are an FRLG-only table | refactor | medium | false | — | — | Make heal/whiteout destinations data-driven per version. | Refactor | Architect ref — section area already separately tasked. DEFERRED — portability design item with no evidence path; heal destinations live in Finisher-owned heal_locations.lua (B5). |
| J5 | Trainer encounter music + rival fallbacks are FRLG class ids | refactor | medium | false | — | scripting/trainers.lua:332-333 | Version-scope trainer class ids/music; remove FRLG literal fallbacks. | Refactor | Architect ref — section area already separately tasked. DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| J6 | Pokédex area map defaults to Kanto and reads FireRed's map groups | architecture | high | false | — | pokedex_data.lua:111-114 | Load the area-map/region data for the active version's region. | Architect | Architect ref — section area already separately tasked. DEFERRED — Architect-owned (J6) per the triage lane table; no edit made. |
| J7 | Internal species/form shape pinned to FRLG's 412 | refactor | medium | false | — | pokemon.lua:510 | Derive NUM_SPECIES/egg id per version. | Refactor | Architect ref — section area already separately tasked. DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| J8 | "Game3 map" is defined as the `FR_`/`SEVII_` string namespace | architecture | high | false | — | map_ids.lua:5-15, Game3.lua:384 | Identify game3 maps by version metadata, not `FR_`/`SEVII_` prefixes. | Architect | Architect ref — section area already separately tasked. |
| J9 | ~~Region-map switch button hardwired to a Sevii flag~~ | bugfix | medium | false | INVALID (stale) | region_map.lua:410 | ~~Drive the switch button from version map config, not the Sevii flag.~~ **Pret-corrected: the Sevii-flag gate IS pret behaviour for FRLG (region_map.c:1027-1029); keep only as an RSE portability note, no FRLG change.** | Finisher | Architect ref — section area already separately tasked. W2 pret: region_map.c:1027-1029 clears MAPPERM_HAS_SWITCH_BUTTON when FLAG_SYS_SEVII_MAP_123 is unset — the engine's region_map.lua:410 gate is pret-faithful for FRLG. Portability-only (RSE), not a FireRed bug.|
| J10 | The mod API treats `generation == 3` as exactly one engine | architecture | high | false | — | src/mods/Loader.lua:1666-1679, src/mods/Schemas.lua:896-903 | Dispatch gen3 by engine id with per-engine facades. | Architect | Architect ref — section area already separately tasked. |

### K Performance (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| K1 | Double OAM build + sort per presented frame | refactor | high | false | verified | display.lua:244 | Build the OAM buffer once per presented frame (or only when the layer changes). | Refactor | display.lua:244 and :264 both call Oam.buildOamBuffer(), which scans+sorts the global pool (oam.lua:498-510); both planes run per presented frame (display.lua:303-318). DONE — src/core/game3/oam.lua buildOamBuffer reuses the cached buffer when the visible set and sort keys are unchanged (adjacent-pair check on the total comparator); the UI pass no longer re-sorts an unchanged buffer. game3_display_fit / stitchfield / elevation_oam_priority PASS. |
| K2 | Per-glyph opts table alloc in `FrlgFont.draw` | refactor | high | false | — | frlg_font.lua:825 | Hoist the small-opts tables to constants and reuse them. | Refactor | DONE — src/ui/game3/frlg_font.lua ADVANCE_SMALL/ADVANCE_NORMAL hoisted, all 3 per-glyph call sites use them; text/dex suites PASS. |
| K3 | `collectTileDraws` allocates one table per visible tile | refactor | high | false | — | field_view.lua:667 | Reuse a scratch pool for tile draws instead of one table per tile. | Refactor | DONE — src/core/game3/field_view.lua collectTileDraws reuses a scratch pool (tile_draw_pool) and per-slot lists instead of one table per visible tile; field suites PASS. |
| K4 | `Bg.flushPriority` list + comparator per call | refactor | high | false | — | — | Sort once per priority change / cache the list. | Refactor | DEFERRED — Bg.flushPriority lives in bg.lua (src/core/game3/bg.lua / battle/bg.lua), both Architect-owned via I10; no Refactor-owned bg file. |
| K5 | `daytimeFor` re-`pcall(require)`s Palettes once per actor per frame | refactor | high | false | — | field_view.lua:453 | Hoist the Palettes require out of the per-actor path. | Refactor | DONE — src/core/game3/field_view.lua palettes() resolves src.world.gen2.Palettes once (package.loaded first) instead of pcall(require) per actor; field suites PASS. |
| K6 | OAM comparator calls `oamTopLeft` per comparison | refactor | high | false | — | — | Precompute `oamTopLeft` keys before sorting. | Refactor | DONE — src/core/game3/oam.lua caches oamTopLeft as s._oamSortY during collection; comparators read the cached key; elevation_oam_priority PASS. |
| K7 | Tileset animation re-uploads the whole atlas and rebuilds ImageData per mid | bugfix | medium | false | VERIFIED | tileset_anim.lua:137 | Reuse the ImageData and update only changed tiles (or batch uploads). | Finisher | W2: tileset_anim.lua:137/:141 per-mid sub+newImageData(16,16), :163 replacePixels of the whole atlas (line drift ~+4). |
| K8 | `drawNativeTiles` rebuilds the whole sprite batch on every 16px camera step | refactor | medium | false | — | field_view.lua:785-788 | Cache the batch per block; diff-update instead of full clear/refill. | Refactor | DEFERRED — native-tile batch diff-update is a rendering design change; headless suites cannot verify visual output and in-game frame evidence is required (AGENTS.md headless-render caveat). |
| K9 | Fallback tile path issues unbatched draws + per-slot shader/closure | refactor | medium | false | — | field_view.lua:691-704 | Batch fallback draws / cache per-slot shader state. | Refactor | DONE (partial) — src/core/game3/field_view.lua drawTilesColored uses one hoisted palette-run closure instead of a per-slot closure; batching the fallback atlas blits deferred with K8 (same visual-verification caveat). |
| K10 | Per-frame scratch tables/closures in the scene paths | refactor | high | false | — | new_game_scene.lua:1555-1558 | Reuse scratch tables/closures at file scope. | Refactor | DONE — src/ui/game3/new_game_scene.lua INPUT_PROXY hoisted with proxyPressed/proxyInput upvalues, replacing two closures + a table per GBA step; new_game/intro suites PASS. |

### L Security (6)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| L1 | Boot executes cache Lua via unsandboxed `loadstring` | bugfix | high | true | — | src/core/Data.lua:267, dataset.lua:97, ow_sprites.lua:32 | Sandbox the cache load (empty env) like dataset.lua:97 instead of bare loadstring. | Finisher |  |
| L2 | Portable `SaveData` shells out with an unescaped slot-derived path | bugfix | high | true | — | — | Stop shelling out (use love.filesystem.createDirectory) or escape the path. | Finisher |  |
| L3 | Slot ids never validated, so the portable save root is escapable | bugfix | high | true | — | SaveData.lua:930, options.lua | Validate slot ids (`^slot%d+$` / a whitelist) before building any save path. | Finisher |  |
| L4 | OW sprite `.meta` dimensions trusted → multi-GB allocation | bugfix | high | true | — | ow_extract.lua:298-300, ow_sprites.lua:59-68 | Clamp width/height/frameCount to sane maxima and verify the blob length before newImageData. | Finisher |  |
| L5 | Cache-relative names joined without a traversal check | refactor | high | false | — | CacheFs.lua:249-250 | Reject `..` in CacheFs relative paths before joining. | Refactor | DONE — src/import/CacheFs.lua unsafe_rel() guard rejects `..` in write/openWrite/readAt/existsAt/remove/removeDir/removeTree; import/cache suites PASS. |
| L6 | `SaveFileIO` export/cart paths interpolate an unchecked slot id | bugfix | high | false | verified | SaveFileIO.lua:28 | Validate slotId (e.g. `^slot%d+$`) before interpolating it into paths. | Finisher | SaveFileIO.lua:27-28 and :197 interpolate slotId unchecked; SaveData.slotNames (:929-932) does the same. Caveat: needs a crafted registry/options entry (local file), so defence-in-depth. |

### M Standards / dead code / tests (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| M1 | Dead render function `drawWorldEntities` | refactor | high | true | — | field_view.lua:301 | Delete `drawWorldEntities`. | Refactor | DONE — deleted dead drawWorldEntities (was field_view.lua:298); field_view-dependent suites PASS (stitchcoll_fall_draw/shake, elevation_oam_priority). |
| M2 | Dead `isBuilding` helper duplicating `PaletteRules.isBuildingCategory` | refactor | high | false | — | collision.lua:960, palette_rules.lua:125 | Delete `isBuilding` (use `PaletteRules.isBuildingCategory`). | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| M3 | Dead `begin_win_award` contradicting its own comment | refactor | high | false | — | battle/init.lua:1316 | Delete `begin_win_award`. | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| M4 | Four copies of the pret sine table with disagreeing values | refactor | high | true | — | trig.lua:4, anim_tasks.lua:10, g2_pret.lua:55 | Keep one canonical `Trig.SINE`; delete the three private copies. | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| M5 | `isSeviiMap` aliases are dead and misleadingly named | refactor | high | false | — | runtime.lua:298, map_ids.lua:18 | Delete the `isSeviiMap` aliases. | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| M6 | Duplicated catch RNG helper, one copy dead | refactor | high | false | — | battle/items.lua:36, catching.lua:33 | Delete the dead `roll` copy in battle/items.lua. | Refactor | DONE — deleted dead roll (was src/core/game3/battle/items.lua:36); game3_battle_bag / game3_battle_items_abilities PASS. |
| M7 | Extractor reads ROM fields then discards them | bugfix | high | false | verified | items_extract.lua:163-174 | Emit the four read fields (or drop the reads) so ROM item metadata survives extraction. | Finisher | items_extract.lua:163-174 reads itemId/itemType/fieldUseFunc/battleUseFunc; emitted row :182-193 omits all four. |
| M8 | Shadowed/redefined locals in long functions | refactor | medium | false | — | pokemon_extract.lua:934, gfx.lua:177, pc_chrome.lua:221 | Rename/remove the shadowed locals. | Refactor | DONE (partial) — pc_chrome.lua redundant `local sp` redeclaration removed (game3_pc_anim_test / game3_stitchuif_boxsend_test PASS); pokemon_extract.lua:934 shadow not present at the cited line in the current tree (snapshot drift); gfx.lua:177 stays deferred (Finisher-owned). |
| M9 | Dead `_byPret` index in the map catalog | refactor | high | false | — | — | Delete `_byPret` (or actually use it for lookups). | Refactor | DEFERRED — _byPret lives in src/import/gba/map_catalog.lua, Finisher-owned (I7); no edit made. |
| M10 | Untested high-risk Gen 3 modules | refactor | medium | false | — | — | Add suites for the listed modules (QA). | QA | DEFERRED — QA lane (test gaps for m4a_seq/oam/player/etc.), not Refactor rule-change work. |

### O anim_port parity and duplication (9)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| O1 | `g4` sine/cos lost the mask + s16 wrap the other three copies keep | refactor | high | false | — | g4_pret.lua:73, g1_pret.lua:83, g4_pret.lua:64 | Add `band(floor(i),0xFF)` and `P.s16(...)`. · refactor · high | Refactor | DONE — g4_pret.lua:66-73 Sin/Cos now apply P.s16 like g1/g2/g3; tests/game3_anim_port_g4_test.lua PASS. |
| O2 | `ArcTan2` rounding drifts between ports | refactor | medium | false | — | g2_pret.lua:88, g3_pret.lua:76, g4_pret.lua:78 | Pick round-to-nearest and share one helper. · refactor · medium | Refactor | DONE — shared Trig.arcTan2 (src/core/game3/trig.lua:33-38, round-to-nearest); g2_pret.lua:86, g3_pret.lua:73, g4_pret.lua:76 delegate; all 4 anim_port suites PASS. |
| O3 | Base `ShakeTargetInPattern` and its pattern tables are shadowed dead code | refactor | high | false | — | anim_tasks.lua:1363, g2_fire.lua:535, anim_tasks.lua:1366 | Delete the shadowed base task and `SHAKE_PATTERN_0/1`. · refactor · high | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| O4 | Template `cb` metadata is never consumed in g1 and g3 | refactor | high | false | — | g1_templates.lua:245, g3_data.lua:415, g2_pret.lua:1184 | Drop the field or route it through `AnimCallbacks.get`. · refactor · high | Refactor | DONE — removed the never-read template `cb` field from src/core/game3/battle/anim_port/g1_templates.lua (332) and g3_data.lua (388); load-file deep-compare identical ignoring cb; 4 anim_port + coverage + parity suites PASS. (g2 already consumes cbName at g2_pret.lua:1184.) |
| O5 | `P.Cos2` is defined and never called | refactor | high | false | — | g3_pret.lua:71 | Delete or wire it. · refactor · high | Refactor | DONE — deleted g3_pret.lua:72 (QA precondition met: test no longer asserts it); pret defines Cos2 at pokefirered/src/trig.c:539-541 but pret itself has zero `Cos2(` callers; engine grep clean; g1/g2/g3/g4 + pret-parity suites PASS. |
| O6 | `g3_pic_size.lua` is an exact uncited duplicate of `g1_pic_sizes.lua` | refactor | high | true | — | g3_pret.lua:1344, g4_tasks.lua:51, g3_pic_size.lua | Delete `g3_pic_size.lua`, have `g3_pret` use `g1_pic_sizes`. · refactor · high | Refactor | DONE — deleted src/core/game3/battle/anim_port/g3_pic_size.lua; g3_pret.lua:1344 now requires g1_pic_sizes; game3_anim_port_g3_test PASS. |
| O7 | `g2_mon_sizes` is a third re-encoded copy of the same table, truncated at 412 | refactor | high | false | — | g2_mon_sizes.lua:3, g1_pic_sizes.lua:4 | Derive at load, or extend to 440. · refactor · high | Refactor | DONE — src/core/game3/battle/anim_port/g2_mon_sizes.lua rewritten as an exact derived view of g1_pic_sizes (413/413 entries value-identical before/after); game3_anim_port_g2_test PASS. |
| O8 | `DOOM_COORDS` has one more entry than the pret table it cites | refactor | medium | false | — | g3_e3b.lua:153 | Comment the OOB read or guard explicitly. · refactor · medium | Refactor | DONE — g3_e3b.lua:153 comment documents the explicit OOB guard for the 5th DOOM_COORDS entry; game3_anim_port_g3_test PASS. |
| O9 | Positive sine indices 256–319 are handled three different ways | refactor | medium | false | — | g1_pret.lua:78, g2_pret.lua:83, g4_pret.lua:68 | Centralise on the 320-entry `trig` table. · refactor · medium | Refactor | DONE — g4_pret.lua:72 P.gSine aligned to the canonical Trig.SINE u8-masked index (same as g1); game3_anim_port_g4_test PASS. The other copies are D2/M4 (deferred). |

### P battle effects completeness (5)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| P1 | Heal Bell / Aromatherapy never clears the *user's* Nightmare volatile | bugfix | high | false | verified | effects/healing.lua:138 | Clear `user.expNightmare` (and each party mon) in `healBell`. · bugfix · high | Finisher | healing.lua:138 clears user status without user.expNightmare = nil; partner path :144 does clear it; party loop :148-151 clears status/sleep only. |
| P2 | Rapid Spin frees Wrap, Leech Seed and Spikes in one use; pret frees exactly one | bugfix | medium | false | CONFIRMED-BUG | — | Make the branches mutually exclusive. · bugfix · medium | Finisher | W2 pret: Cmd_rapidspinfree (battle_script_commands.c:8435-8474) is ONE if/else-if chain — wrap, else leech seed, else spikes; one free per use. Engine secondary.lua:408-430 runs three independent ifs, so one use can strip wrap+leech+own Spikes. |
| P3 | Effect ids 12/14/15/21/22/55/56/61/63/64 have no `STATUS_SETUP` entry and no handler | bugfix | high | false | verified | effect_ids.lua, init.lua:130 | Add the rows or delete the ids. · bugfix · high | Finisher | effect_ids.lua ids 12/14/15/21/22/55/56/61/63/64 absent from STATUS_SETUP (:273+) and STAT_CHANGES (:380+); effects/init.lua:129-130 returns false. |
| P4 | Registered-effect handlers that no code can reach | refactor | high | false | — | stats.lua:106-112, setup.lua:282, adapter.lua:401 | Delete or wire them. · refactor · high | Refactor | DEFERRED — the unreachable handlers are the same defect as U10 (moves referencing unregistered effect ids on Finisher-owned moves.lua/effects/init.lua); deleting them would pre-empt the U10 wiring fix. |
| P5 | Thief/Trick guard is pret-correct only for regular trainer battles | bugfix | medium | false | CONFIRMED-BUG | effects/special.lua:311, effects/secondary.lua:359 | Gate on battle-type flags rather than side. · bugfix · medium | Finisher | W2 pret: battle_script_commands.c:2611-2630 blocks opponent-side steal ONLY in regular trainer battles (allows EReader/Battle Tower/Link/Secret Base, and skips Trainer Tower separately). Engine secondary.lua:366 blocks ALL enemy-side steals (`user.side ~= "player"`). |

### Q script natives and specials (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Q1 | Duplicate special id 0x136: `ShowIcefallCaveCrackedIceAttempt` collides with `ShakeScreen`; the later no-op wins | bugfix | high | true | — | stdscripts.lua:146, natives_events.lua:118, tests/game3_special_events_test.lua | Delete the bogus name. · bugfix · high | Finisher | **DONE** — alias deleted (stdscripts.lua:145-146) and its dead handler removed (natives_events.lua:117-131); 0x136 now resolves to `ShakeScreen`. `tests/game3_special_events_test.lua` all passed, `tests/game3_special_ids_test.lua`/`game3_special_handlers_test.lua` green. |
| Q2 | `SetIcefallCaveCrackedIceMetatiles` writes cracked ice as impassable | bugfix | high | true | — | natives_events.lua:112, tests/game3_special_events_test.lua | Pass `false`. · bugfix · high | Finisher | **DONE** — `false` passed (natives_events.lua:117); MapGridSetMetatileIdAt only swaps the id, collision follows the new metatile. `tests/game3_special_events_test.lua` all passed. |
| Q3 | `ForcePlayerOntoBike` writes the wrong state objects | bugfix | high | false | verified | natives_events.lua:131-142, player.lua:41-60 | Drive `src.core.game3.player` fields. · bugfix · high | Finisher | natives_events.lua:131-142 writes session.player.ridingBike / rt.player.ridingBike; Runtime has no .player and nothing reads ridingBike; the live state is Player.biking (player.lua:58). **DONE** — dead session/rt writes replaced; handler sets `Player.biking`/`Player.surfHopping` and refuses a surfing avatar (field_specials.c:97). `tests/game3_special_events_test.lua` all passed. |
| Q4 | `ForcePlayerToStartSurfing` writes the wrong state objects and leaves bike/hop set | bugfix | high | false | verified | natives_events.lua:145-156 | Mirror the bike fix. · bugfix · high | Finisher | natives_events.lua:145-156 writes session.player.surfing / rt.player.surfing; live state is Player.surfing/surfHopping (player.lua:63-65), never set by the special. **DONE** — handler sets `Player.surfing = true`, clears `Player.biking`/`Player.surfHopping` (forced transition skips the hop; field_specials.c:1513). `tests/game3_special_events_test.lua` all passed. |
| Q5 | `ShowFieldMessageStringVar4` calls an adapter method that does not exist | bugfix | high | true | — | natives_events.lua:191-196, adapters.lua | Call `openMessageStay`. · bugfix · high | Finisher | **DONE** — handler now mirrors pret `field_specials.c:120 ShowFieldMessage(gStringVar4)`: sets `ctx.messageOpen` and calls `openMessageStay(text, nil)` (`natives_events.lua:175-189`). This was the `game3_special_trade` root cause. `tests/game3_special_trade_test.lua` all passed, `game3_oneoff_specials_test` 32/0. |
| Q6 | `SetWalkingIntoSignVars` writes state nothing consumes | bugfix | medium | false | VERIFIED | natives_events.lua:199-211 | Wire the fields into the msgbox/walk layer. · bugfix · medium | Finisher | W2: natives_events.lua:190-203 writes six ctx/session fields; zero readers anywhere else in src/ (grep). |
| Q7 | Teleporter field animations are empty bodies | feature | high | false | VERIFIED | natives_cutscene.lua:34-36, special_field_anim.lua | Implement housing/cable metatile animation. · feature · high | Finisher | W2: natives_cutscene.lua:34-40 AnimateTeleporterHousing/AnimateTeleporterCable are `return false` empty bodies; special_field_anim.lua implements only escalators (header comment at :2 mentions teleporter, no code). |
| Q8 | Real specials registered as blanket no-ops | bugfix | high | false | verified | natives_events.lua:343 | Implement the quest-bearing ones. · bugfix · high | Finisher | natives_events.lua:343/345/347/349/370 register ShakeScreen, InitRoamer, SampleResortGorgeousMonAndReward, DisableMsgBoxWalkaway, UpdateLoreleiDollCollection as noops. |
| Q9 | `StartSpecialBattle` has no Battle Tower / Secret Base path | bugfix | medium | false | CONFIRMED-BUG | natives_tower.lua:583-603 | Add the foe/party builder for cases 0/1. · bugfix · medium | Finisher | W2 pret: battle_tower.c:895+ StartSpecialBattle serves all special-battle types. Engine natives_tower.lua:590-612: SECRET_BASE branch never sets foe -> falls through to auto-LOSS at :607-610; no Battle Tower path exists. **INVALID (no FRLG caller) — deferred to the RSE waves:** whole-repo grep shows the only FRLG invocation of `special StartSpecialBattle` is `data/maps/SevenIsland_House_Room2/scripts.inc:23` with `VAR_0x8004 = 2` (e-reader, already handled); cases 0/1 are the RS paths — case 0 needs `gSaveBlock2Ptr->battleTower` data the engine does not model (`capabilities.lua:51`), and pret's case 1 builds no foe either (the script stages the party), so implementing them would be inventing data. The auto-LOSS branch is the safe dead path. Evidence table: 'tail batch 3' in this file. |
| Q10 | `gotonative` is defined but never dispatched, and the `native:` namespace has zero registrations | bugfix | high | false | verified | opcodes.lua:49, ops_a.lua, natives.lua:883-891 | Route through `Natives.callnative` and register handlers. · bugfix · high | Finisher | opcodes.lua:52 defines gotonative with no ops_a branch; natives.lua:885 looks up "native:"..id and only "special:" keys are ever registered (natives.lua:245+). |

### R ROM extractor decoding (5)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| R1 | `map_tree_extract.simplify_events` reads coord fields that are never written | bugfix | high | false | verified | map_tree_extract.lua:100, extract_map_events.lua:148, field.lua | Emit `var`/`value` (or alias). · bugfix · high | Finisher | map_tree_extract.lua:100-101 reads c.trigger/c.index; extract_map_events.lua:146-149 emits var/value (no trigger/index). |
| R2 | `ow_extract.max_anim_frame` stops on `ANIMCMD_JUMP` (-2) while believing it is `END` | bugfix | high | false | verified | ow_extract.lua:103, trade_extract.lua:48, ow/manifest.lua | Break on `lo >= 0xFFFD`. · bugfix · high | Finisher | ow_extract.lua:104 breaks only on 0xFFFE (JUMP); trade_extract.lua:48 breaks on `v >= 0xFFFD` so END 0xFFFF / LOOP 0xFFFD are skipped. |
| R3 | `parse_objects` ignores `ObjectEventTemplate.kind`, so clones decode as ordinary NPCs | bugfix | medium | false | CONFIRMED-BUG | extract_map_events.lua:36-38 | Read `kind` and decode the clone union. · bugfix · medium | Finisher | W2 pret: ObjectEventTemplate layout (global.fieldmap.h:110-130) is localId, graphicsId, kind, x, y, then a normal/clone union. Engine extract_map_events.lua:30-66 never reads kind (byte 2) and always decodes the normal union — clone templates decode as ordinary NPCs. |
| R4 | `map_tree_extract.pack_tileset` silently emits no `tiles.4bpp` for uncompressed tilesets | bugfix | medium | false | VERIFIED | map_tree_extract.lua:120, map_tree/tilesets/ts_082d4c44/meta.json | Derive the length (`palsOff - tilesOff`) and dump the bytes. · bugfix · medium | Finisher | W2: map_tree_extract.lua:120-124 explicitly sets tilesBlob=nil for uncompressed tiles; :139 skips tiles.4bpp with meta tiles_bytes=0 and no error. |
| R5 | `battle_anim_extract` decodes opcode 0x24 without reading its branch pointer | bugfix | medium | false | VERIFIED | battle_anim_extract.lua:381-383 | Read the pointer, emit a label, eagerly decode the target. · bugfix · medium | Finisher | W2: battle_anim_extract.lua:381-384 emits jumpifcontest and does `i = i + 5` without capturing the 4-byte branch pointer. |

### S swallowed errors (11)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| S1 | Slot-machine coin mutations discard the coin API result, leaving bet/payout half-mutated | bugfix | high | false | verified | slot_machine.lua:661 | Check each result, mutate only on success, log failures. · bugfix · high | Finisher | slot_machine.lua:661-703 pcall() results discarded while st.bet/st.payout/session coins mutate regardless. |
| S2 | Post-trade save path swallows failure and reports done | bugfix | high | false | verified | link/trade.lua:450 | Capture both results, log, and propagate. · bugfix · high | Finisher | link/trade.lua:449-455 pcalls both saves, then calls scene().saveDone() unconditionally. |
| S3 | Generated-data Lua loaders drop `pcall(chunk)` errors and fall through to nil | bugfix | medium | false | VERIFIED | dataset.lua:99, pokemon.lua:84, items_data.lua:226 | Log once before falling back. · bugfix · medium | Finisher | W2: shop_chrome.lua:85-90 and sibling loaders do `if ok then return t end; return nil` — the pcall error is never logged. |
| S4 | Battle capture-event wrappers discard thrown errors and return empty success | bugfix | medium | false | VERIFIED | battle/init.lua:720, switch_seq.lua:172 | Log the error before returning. · bugfix · medium | Finisher | W2: battle/init.lua:720-722 and :1876-1878, switch_seq.lua:170-174 — pcall errors discarded, false/{} returned with no log. |
| S5 | Battle RNG/badge pcall failures become silent defaults | bugfix | medium | false | VERIFIED | battle/engine.lua:169, damage.lua:105, engine.lua:95 | Log once before falling back. · bugfix · medium | Finisher | W2: adapter.lua:157-161 and :291-295 fall back silently to math.random on rng pcall failure; engine.lua:167-171 returns false (no badge) on Flags.hasBadge pcall failure, no log. |
| S6 | `Moves._runReloadHooks` discards every hook error, unlike `Pokemon._runReloadHooks` | bugfix | high | false | verified | battle/moves.lua:207, pokemon.lua:205 | Mirror the Pokemon form. · bugfix · high | Finisher | moves.lua:207 `pcall(h.fn, Moves)` discards errors; pokemon.lua:205-208 captures ok/err and logs. |
| S7 | ~~Core `SaveData.save` failure returns bare `false` with the error dropped~~ | bugfix | medium | false | INVALID (stale) | Game3.lua:768 | Log the error before returning false. · bugfix · medium | Finisher | W2: SaveData.save now logs both write failures before returning false — SaveData.lua:2221-2225 and :2230-2234 call Logger.error("save failed: %s", err). Error is no longer dropped. |
| S8 | ~~`Game3:loadGameData` wraps moves/items/trainers loading in log-free pcalls and then exposes nil~~ | bugfix | medium | false | INVALID (stale) | Game3.lua:200 | Check each result and log at error level. · bugfix · medium | Finisher | W2: symbol `Game3.loadGameData` no longer exists anywhere in src/ (grep = 0 hits) — the cited wrapper is gone/renamed. |
| S9 | Hot-path update/draw pcalls swallow errors every frame with no log | bugfix | medium | false | VERIFIED | Game3.lua:556, gfx.lua:64, battle/ui.lua:208 | Log once per source, rate-limited. · bugfix · medium | Finisher | W2: hud.lua:183 pcall(top.mod.update, dt) discards ok/err every frame in the hot path. |
| S10 | Mod/host API query pcalls turn errors into empty results callers read as "none found" | bugfix | medium | false | VERIFIED | world/game3/WorldAPI.lua:178, battle/game3/BattleAPI.lua:71 | Warn the caught error before returning the fallback. · bugfix · medium | Finisher | W2: world/game3/WorldAPI.lua:176-181 pcall(FM.fromMenu) -> returns nil on error (callers read as none-found); :673 map-load pcall likewise. |
| S11 | `Pokemon.install` guards swallow install failure, later degrading names/types to defaults | bugfix | medium | false | VERIFIED | scripting/natives.lua:86, battle/state.lua:21, party.lua:188 | Log and avoid silent re-attempts. · bugfix · medium | Finisher | W2: pokemon.lua:128-146 install clears 18 data tables up front; callers `pcall(Pokemon.install, nil)` discard the error (party.lua:188, breeding.lua:64, battle/state.lua:22, natives_trade.lua:131, daycare_menu.lua:61). |

### T nil / bounds / state (8)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| T1 | `BoxStorageUI._prevPartySlot` is a module upvalue `show()` never resets | bugfix | medium | false | VERIFIED | box_storage_ui.lua:283 | Reset/clamp `_prevPartySlot` in `show()`. · bugfix · medium | Finisher | W2: box_storage_ui.lua writes _prevPartySlot at :265/:272/:277, reads :283; no reset assignment exists anywhere in the file (4 occurrences total). |
| T2 | `Storage.moveMon`'s party compaction iterates with `pairs`, not `ipairs` | bugfix | medium | false | VERIFIED | storage.lua:275 | Use `table.remove(session.party, srcIdx)` or an index loop. · bugfix · medium | Finisher | W2: storage.lua:281-286 party compaction iterates with `pairs` — order not guaranteed. |
| T3 | `Trade.tradeMons` writes back to a throw-away table when `session.party` is nil | bugfix | medium | false | VERIFIED | scripting/natives_trade.lua:334 | Assign `session.party = session.party or {}` first. · bugfix · medium | Finisher | W2: natives_trade.lua:334-352 `local party = session.party or {}` then party[slot]=offered — nil session.party writes to a throw-away table while dex still updates. |
| T4 | `Party.giveEgg` refuses a fresh session that `giveMon` would accept | bugfix | — | false | VERIFIED | party.lua:286, party.lua:183 | Drop the `not session.party` clause. · bugfix · low | Finisher | W2: giveEgg (party.lua:285-286) rejects a nil session.party while giveMon (:181-183) auto-creates it — asymmetric. |
| T5 | Evolution's Shedinja fallback can append to the host save's party | bugfix | medium | false | VERIFIED | evolution.lua:306 | Always append to `session.party`. · bugfix · medium | Finisher | W2: evolution.lua:306 uses session.party or session.save.party fallback; :336 `party[#party+1] = shedinja` bypasses giveMon/toPC. |
| T6 | `Daycare.withdraw`/`giveEggFromDaycare` hardcode `party[PARTY_SIZE]` with no party-full guard | bugfix | high | false | verified | daycare.lua:277, breeding.lua:436-438, storage.lua:211-213 | ~~Guard `#party >= PARTY_SIZE` (spill to PC as `Party.giveMon` does) and append rather than index-assign.~~ **Pret-resolved:** the party-full guard is script-layer in pret — Four Island withdraw `data/maps/FourIsland_PokemonDayCare/scripts.inc:86-88`, egg `data/maps/FourIsland/scripts.inc:95-104`, Route 5 withdraw `data/scripts/day_care.inc:79-81` — so the engine's equivalent seam is the special handler (`natives_daycare.lua`: egg guard already at `:290-303`; add the same to `TakePokemonFromDaycare`/`TakePokemonFromRoute5Daycare`). Keep `daycare.lua`/`breeding.lua` index-assign as-is. No PC spill. · bugfix · high | Finisher | Spec/citation: `CITED / RESOLVED` in §Pret grounding; `daycare.c:525/:1081` unguarded on purpose. **DONE** — shared `partyIsFull` guard added in `natives_daycare.lua:71-81` and mirrored into `TakePokemonFromDaycare` (`:196-203`, pret `FourIsland_PokemonDayCare/scripts.inc:86-88`), `TakePokemonFromRoute5Daycare` (`:215-222`, pret `day_care.inc:79-81`) and the egg special (`:307-314`, pret `FourIsland/scripts.inc:95-104`). `daycare.lua`/`breeding.lua` untouched. Tests: `game3_daycare_breeding/hatch/menu/model` all rc=0 (model test 9 split special-guard vs model write-through pin, + new 9b Route 5 guard). |
| T7 | `Storage.ensure` on the draw path returns nil for a nil session, then indexes it | bugfix | medium | false | VERIFIED | box_storage_ui.lua:699, storage.lua:66, box_storage_ui.lua:80 | Guard the result and compute box/hover on state change. · bugfix · medium | Finisher | W2: storage.lua:65-66 returns nil for a nil session; box_storage_ui.lua:79-81 then indexes storage.currentBox with no guard (update_box_to_send_mons at :68-70 does guard). |
| T8 | Party `pairs` rebuild in `Storage` drops array order guarantees | — | — | false | — | — | n/a — recorded as covered by T2; no standalone fix. | Refactor | duplicate; recorded for completeness DONE — duplicate of T2; no standalone fix (recorded for completeness). |

### U data-table integrity (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| U1 | `BY_NUM` declares a move with no `BY_ID` row (`KARATE_CHOP`) | bugfix | high | true | — | battle/moves.lua:112 | Add the BY_ID row. · bugfix · high | Finisher |  |
| U2 | `EVO_IDS` marks HM02/HM03 (items 340/341) as evolution stones | bugfix | high | true | — | items_data.lua:499 | Delete `[340]`/`[341]`. · bugfix · high | Finisher |  |
| U3 | `isEvolutionStone` range excludes SUN/MOON and includes unused ids | bugfix | high | true | — | items_data.lua:392 | `>= 93 and <= 98`. · bugfix · high | Finisher |  |
| U4 | Repel step counter written to the happiness-counter var slot | bugfix | high | false | verified | encounters.lua:48, flags_table.lua:3210 | Use `0x4020`. · bugfix · high | Finisher | encounters.lua:48 declares VAR_REPEL_STEP_COUNT = 0x4021; step_events.lua:301-305 uses 0x4021; flags_table.lua:3210 has REPEL=0x4020 and :3111 HAPPINESS=0x4021. |
| U5 | `Moves.get` silently substitutes a 40 BP Normal move for unknown ids | bugfix | medium | false | VERIFIED | battle/moves.lua:311 | Return nil/`{unknown=true}`. · bugfix · medium | Finisher | W2: moves.lua Moves.get falls back to `M("MOVE_"..num, 40, T.NORMAL, ...)` for unknown numeric ids (40 BP Normal). |
| U6 | gfx id 48 mapping/comment disagrees with pret | bugfix | medium | false | CONFIRMED-BUG | scripting/gfx_ids.lua:29 | Correct the mapping/comment. · bugfix · medium | Finisher | W2 pret: event_objects.h:54 OBJ_EVENT_GFX_WORKER_F=48, :61 OBJ_EVENT_GFX_SCIENTIST=55. Engine gfx_ids.lua:29 maps 48 to SPRITE_SCIENTIST with a misleading "OAK lab aide" comment. |
| U7 | `berryNumber` falls back to berry #1 for non-berry ids | bugfix | medium | false | VERIFIED | items_data.lua:424 | `return nil`. · bugfix · medium | Finisher | W2: items_data.lua:416-425 berryNumber range test then `return 1` — berryNumber(4)=1 for non-berries. |
| U8 | Curated move rows drop the pret `target` field | bugfix | medium | false | CONFIRMED-BUG | battle/moves.lua:12-29, ai_cmds.lua:280 | Capture `target` in `M()`. · bugfix · medium | Finisher | W2 pret: every battle_moves.h row sets .target (e.g. :590 GROWL MOVE_TARGET_BOTH). Engine curated rows built by M() (moves.lua:12+) never set target; only from_rom (:280) does; ai_cmds.lua:280 reads `target or 0` -> curated-only rows lose AI target flags. |
| U9 | `HM_MOVES` includes Whirlpool, not an FRLG HM | bugfix | medium | false | CONFIRMED-BUG | pokemon.lua:1055 | Remove `[250]`. · bugfix · medium | Finisher | W2 pret: FRLG HM list is HM01 CUT .. HM08 (items.h:411-418) — no Whirlpool HM. Engine pokemon.lua:1048-1058 HM_MOVES includes [250] WHIRLPOOL (comment admits Gen2 leftover); isHmMove (:1660-1661) makes it un-forgettable. |
| U10 | Seven curated moves point at effect ids that are never registered | bugfix | high | false | verified (partial) | battle/moves.lua:66-75, effects/init.lua | Add the pret numeric effect to the six curated rows (TAIL_WHIP/LEER=`DEFENSE_DOWN` 19, HARDEN=`DEFENSE_UP` 11, SWORDS_DANCE=`ATTACK_UP_2` 50, AGILITY=`SPEED_UP_2` 52, AMNESIA=`SPECIAL_DEFENSE_UP_2` 54; pret `src/data/battle_moves.h` rows cited in §Pret grounding). · bugfix · high | Finisher | PARTIAL: all seven effectId strings are unregistered, but only six moves lack a numeric effect (TAIL_WHIP/LEER/HARDEN/SWORDS_DANCE/AGILITY/AMNESIA, moves.lua:67-75). GROWL also has `effect = EffectIds.ATTACK_DOWN` (18) and resolves via STATUS_SETUP. Fix the six. |

### V persistence audit (10)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| V1 | Badge count is structurally zero | bugfix | high | true | — | save_menu.lua:30, boot.lua:181, battle_bridge.lua:71 | Count `FLAG_BADGE01..08_GET` via `Flags.getFlag`. · bugfix · high | Finisher |  |
| V2 | `session.monBoxId` / `session.monBoxPos` written but not saved | bugfix | high | false | verified | storage.lua:342-343, natives.lua:79 | Derive from the flag or serialize both. · bugfix · high | Finisher | storage.lua:342-343 writes session.monBoxId/monBoxPos; natives.lua:79 reads them with 0+1 defaults; neither key exists in save_schema_firered.lua. |
| V3 | `session.id` / `session.playerId` read, never written | bugfix | high | false | verified | party.lua:250, mail.lua:163 | Alias to `trainerId` at construction. · bugfix · high | Finisher | party.lua:250 and mail.lua:163 read session.id/playerId; grep shows zero writers and neither is in the schema. |
| V4 | `session.otSecretId` read, never written | bugfix | medium | false | VERIFIED | party.lua:252, save_schema_firered.lua:85-88 | Drop the alias and guarantee `secretId`. · bugfix · medium | Finisher | W2: session.otSecretId read at catching.lua:237 (`session.secretId or session.otSecretId`); zero writers in src/. |
| V5 | `session.caughtMonsCount` read, never written | bugfix | high | false | verified | save_menu.lua:195, trainer_card.lua:361 | Set it at save time or delete the fallback. · bugfix · high | Finisher | save_menu.lua:228 and trainer_card.lua:361 read caughtMonsCount as a fallback; zero writers in src/. |
| V6 | `dex.owned` vs `dex.caught` divergence | bugfix | high | false | verified | save_schema_firered.lua:120, party.lua:277-279, save_menu.lua:56 | Have `giveMon` call `Dex.setCaught` (or seed `caught`). · bugfix · high | Finisher | schema :120 seeds owned only; party.lua:277-279 sets owned only; save_menu.lua:54-58 counts dex.caught only; dex.lua:62 uses `caught or owned`. |
| V7 | Save-menu time reads non-persisted mirrors instead of `session.playtime` | bugfix | medium | false | VERIFIED | save_menu.lua:196-197, runtime.lua:124-129 | Read `session.playtime`. · bugfix · medium | Finisher | W2: save_menu.lua reads flat session.playTimeHours/Minutes (writers: runtime.lua:124/:134 ticker only); schema persists nested playtime/playTime (:212/:281) — loaded session shows 0:00 until the ticker runs. |
| V8 | `session.mapName` / `session.mapSec` / `session.regionMapSectionId` read, never written | refactor | medium | false | — | — | Remove or implement. · refactor · medium | Refactor | DEFERRED — the reads are on Finisher-owned UI/save files (save_menu.lua) with no evidence path; implement/remove would change save-menu fallbacks, not a behavior-preserving refactor. |
| V9 | `session.store` read as a store fallback, never written | refactor | medium | false | — | storage.lua:25, box_storage_ui.lua:63, pokemon_size_record.lua:73 | Drop the alternative or assign once. · refactor · medium | Refactor | DONE (partial) — dead `session.store` fallback dropped in pokemon_size_record.lua:73 (game3_size_record_test PASS); storage.lua / box_storage_ui.lua halves stay deferred (Finisher-owned). |
| V10 | Schema reads `save.pc` / `save.pcItems` / `save.pc_items` that `toSaveTable` never writes | refactor | medium | false | — | save_schema_firered.lua:266, storage.lua:582-627 | Keep for migration with a test, or drop. · refactor · medium | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |

### W UI round 2 (12)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| W1 | `Hud` ticks the top menu twice per frame | bugfix | high | true | — | hud.lua:182 | Delete the `:292-297` block. · bugfix · high | Finisher |  |
| W2 | `require()` on the draw path across chrome/render helpers | refactor | high | false | — | summary_menu.lua:738, trainer_card.lua:667 | Hoist to file scope. · refactor · high | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| W3 | `TrainerCard` rebuilds its text model every frame | refactor | high | false | — | trainer_card.lua:645 | Cache in `show`/`beginFlip`. · refactor · high | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| W4 | `pc_chrome` allocates new quads every frame | refactor | high | true | — | pc_chrome.lua:170 | Cache by frame/state as `blit_no_hp` already does. · refactor · high | Refactor | DONE — src/ui/game3/pc_chrome.lua waveform Quads cached per frame index (waveform_quad helper, cache reset in ensure()); game3_pc_anim_test / game3_stitchuif_* PASS. |
| W5 | Pokédex per-screen state is not reset on close/open | bugfix | high | false | verified | pokedex.lua:288 | Reset the full block in `show()`/`close()`. · bugfix · high | Finisher | pokedex.lua:288-292 resets open/_onClose only; show() :203-207 resets modeCursor/modeScroll/listCursor/cursor/listScroll; dataPage/category state etc. survive. |
| W6 | Map preview re-resolves its entry and rebuilds colours every frame | refactor | medium | false | — | map_preview_screen.lua:391 | Resolve once in `show()`. · refactor · medium | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| W7 | Help system allocates tables/closures every frame | refactor | medium | false | — | help_system.lua:192 | Hoist the list and reuse one shim. · refactor · medium | Refactor | DONE — src/ui/game3/help_system.lua: HELD_KEYS + one reused REPEAT_SHIM replace the per-frame table/closure in Help.update; game3_help_rom_test PASS. |
| W8 | Boot's `COPYRIGHT` phase and `a()` helper are dead | refactor | high | false | — | boot.lua:22 | Delete or wire. · refactor · high | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| W9 | Summary header has no-op ternaries for the x coordinate | bugfix | high | false | verified | summary_menu.lua:457 | Collapse or supply the intended value. · bugfix · high | Finisher | summary_menu.lua:457 `isMovesPage and 8 or 8` and :463 `isMovesPage and 16 or 16` — both branches identical. |
| W10 | Pokédex scroll-arrow animation advances inside `draw` | bugfix | high | false | verified | pokedex_chrome.lua:752 | Advance once per tick. · bugfix · high | Finisher | pokedex_chrome.lua:752, :777, :800 each advance _animTimer inside the three draw functions. |
| W11 | Quest Log re-sorts the playback frame and re-requires modules every draw | refactor | medium | false | — | quest_log.lua:66 | Sort a copy when the frame is produced; hoist requires. · refactor · medium | Refactor | DONE (partial) — src/ui/game3/quest_log.lua requires (ow_sprites, pokedex_chrome) cached behind accessors and the actor comparator hoisted to file scope; the per-draw sort stays because Playback:frame() returns a fresh interpolated copy each call (core change would be needed to sort at production). quest_log suites PASS. DONE (partial) — src/ui/game3/quest_log.lua requires (ow_sprites, pokedex_chrome) cached behind accessors and the actor comparator hoisted to file scope; the per-draw sort stays because Playback:frame() returns a fresh interpolated copy each call (core change would be needed to sort at production). quest_log suites PASS. DONE (partial) — src/ui/game3/quest_log.lua requires (ow_sprites, pokedex_chrome) cached behind accessors and the actor comparator hoisted to file scope; the per-draw sort stays because Playback:frame() returns a fresh interpolated copy each call (core change would be needed to sort at production). quest_log suites PASS. |
| W12 | Box storage chrome draws without guarding `Storage.ensure` throughout the draw path | refactor | medium | false | — | — | Resolve on state change and guard. · refactor · medium | Refactor | DEFERRED — the draw path is src/ui/game3/box_storage_ui.lua, Finisher-owned (T1/T7/V9). |

### X off-by-one and dead code (9)

| ID | Title | Route | Conf | v3 ver | Re-check | Evidence (file:line) | One-line fix | Lane | Notes |
|---|---|---|---|---|---|---|---|---|---|
| X1 | Fishing dot-game always rolls the first-round `+4`, never the `+1` branch | bugfix | medium | false | CONFIRMED-BUG | field.lua:1040, field_player_avatar.c:1741, field.lua:985 | Track `f.rounds` and use `+1` when `rounds > 0`. · bugfix · medium | Finisher | W2 pret: field_player_avatar.c:1740-1746 uses randVal+1 for every round and randVal+4 only on round 0. Engine field.lua:1041 always adds FISHING_FIRST_ROUND_DOTS and _fishing tracks no rounds field. |
| X2 | `battle/rules.lua` phase-classification subsystem is fully dead | refactor | high | false | — | damage.lua:315-322 | Delete the maps/wrappers or wire them. · refactor · high | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| X3 | `battle/adapter.lua` exposes seven never-called methods | refactor | high | false | — | — | Remove or route callers through them. · refactor · high | Refactor | DONE — deleted 11 provably-dead methods from src/core/game3/battle/adapter.lua (truncateEvents, types, battlers, aliveBattlers, battler, isDouble, alliesOf, isConfused, invokeEffect, fieldGet, fieldSet, weather); battle suites PASS. |
| X4 | `battle/engine.lua` turn/switch planning helpers are dead | refactor | medium | false | — | — | Confirm the live path, then delete or wire. · refactor · medium | Refactor | DEFERRED — src/core/game3/battle/engine.lua is Finisher-owned (C6/C8/C9/S5); no edit made. |
| X5 | `battle/ui.lua` has five unused helpers | refactor | medium | false | — | src/ui/game3/battle_chrome.lua | Trim or delete the module. · refactor · medium | Refactor | DONE — deleted 5 dead helpers from src/ui/game3/battle_chrome.lua (hasDoublesBoxes, ready, hasAssets, drawHpFill, drawExpFill); 5 chrome suites PASS. |
| X6 | `mystery_gift.lua` Gift-stat/card API is unwired | bugfix | medium | false | VERIFIED | — | Call them from the save/read path or drop. · bugfix · medium | Finisher | W2: card/stat APIs (disableCardSending, sourceByKey, disableStats, tryEnableStatsByFlagId, tryIncrementStat, trySaveStamp, isNewsSameAsSaved) are called only from tests/game3_gift_model_test.lua; production uses isSendingCardAllowed + natives_gift.lua:106-108 getCardStatForScript. |
| X7 | `scripting/flags.lua` flag helpers exist only for tests | refactor | medium | false | — | natives.lua:320 | Route production through them or delete. · refactor · medium | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |
| X8 | `pokemon.lua` party-scan Pokerus/dex helpers are dead | refactor | medium | false | — | — | Remove the two wrappers. · refactor · medium | Refactor | DEFERRED — src/core/game3/pokemon.lua is Finisher-owned (F1/J7/S3/S6/U9); no edit made. |
| X9 | `battle/commands.lua` menu/AI helper API is dead | refactor | high | false | — | — | Delete or wire into the turn loop. · refactor · high | Refactor | DONE (claim partly wrong) — 8 helpers have LIVE callers and were kept per the zero-caller protocol (src+tests grep): `menuFor` 2, `playerAction` 24, `selectionError` 10, `moveUsable` 3, `fightShortcut` 5, `switchError` 13, `enemyAction` 26, `tryFlee` 8 (+ `SAFARI_MENU` live via menuFor). Deleted the 4 zero-caller items: `Commands.defaultMenuIndex` (was :18), `Commands.battlerOf` export (was :27; local `battler_of` kept for in-file use), `Commands.setAiHook` + `Commands.aiHook` field + its unreachable branch (now documented at commands.lua:245-247), `Commands.enemyActions` (was :342). File 389→371 lines. Tests BEFORE+AFTER green (6 then 13 suites): game3_battle_safari, stitchbattle_safari_exit, battle_switch_and_faint, battle_ai, battle_event_seq, battle_status_timing, battle_move_effects, battle_baton_pass, battle_doubles_engine, battle_faint, battle_special_moves, battle_bag, battle_items_abilities. pret cites: `battle_controller_player.c:2099-2100` (cursor reset to 0 at controller entry — no defaultMenuIndex API exists), `battle_controller_opponent.c:113/:1339/:1350` (per-battler OpponentHandleChooseAction/ChooseMove dispatch — no batch-plural API, no mod-hook seam), `battle_anim_mons.c:831` `GetBattlerAtPosition` (positional lookup — mirrors the kept local `battler_of`), `battle_controller_safari.c:162-163` (safari action menu — live through menuFor). |
| X10 | Smaller zero-caller clusters not itemised above | refactor | medium | false | — | bg.lua, gfx.lua, oam.lua | Sweep in one dead-code commit. · refactor · medium | Refactor | DEFERRED — file(s) owned by another lane per the anti-conflict rule (see Deferred table below); no edit made. |

## File ownership (one lane per file)

Rule: any file touched by a Finisher finding is Finisher-owned now; refactor/QA items on that file wait for lead clearance.
Files marked *(ambiguous)* share a basename with another file in the tree — resolve by the finding's evidence path before editing.

| File | Lane | Findings | Candidates (when ambiguous) | Deferred items |
|---|---|---|---|---|
| `boot.lua (ambiguous)` | Finisher | F2, V1, W8 | `mobile/android/love/src/jni/love/src/modules/love/boot.lua`, `src/ui/game3/boot.lua` | refactor/QA deferred: W8 |
| `collision.lua (ambiguous)` | Finisher | B2, M2, X10 | `src/core/game3/collision.lua`, `src/core/game3/scripting/collision.lua` | refactor/QA deferred: M2, X10 |
| `docs/architecture.md` | Finisher | I8 |  |  |
| `encounters.lua (ambiguous)` | Finisher | I8, U4 | `src/core/game3/encounters.lua`, `tests/fixture_data/encounters.lua` |  |
| `field.lua (ambiguous)` | Finisher | A2, R1, S3, X1 | `src/core/game3/field.lua`, `tests/fixture_data/field.lua` |  |
| `field_player_avatar.c` | Finisher | X1 |  |  |
| `init.lua (ambiguous)` | Finisher | P3 | `data/scripts/init.lua`, `src/core/game3/battle/effects/init.lua`, `src/core/game3/battle/init.lua`, `src/core/game3/init.lua`, `src/core/game3/link/init.lua`, `src/import/gba/init.lua`, `tests/fixture_data/init.lua`, `tests/modkit/init.lua` |  |
| `map_tree/tilesets/ts_082d4c44/meta.json` | Finisher | R4 |  |  |
| `mystery_gift.lua (ambiguous)` | Finisher | H6, H7, S11 | `src/core/game3/mystery_gift.lua`, `src/ui/game3/mystery_gift.lua` |  |
| `ow/manifest.lua` | Finisher | R2 |  |  |
| `pokemon.lua (ambiguous)` | Finisher | F1, I8, J7, S3, S6, U9 | `src/core/game3/pokemon.lua`, `tests/fixture_data/pokemon.lua` | refactor/QA deferred: J7 |
| `slot_machine.lua (ambiguous)` | Finisher | H1, S1 | `src/core/game3/slot_machine.lua`, `src/ui/game3/slot_machine.lua` |  |
| `src/battle/game3/BattleAPI.lua` | Finisher | S10 |  |  |
| `src/core/Data.lua` | Finisher | I6, L1 |  | refactor/QA deferred: I6 |
| `src/core/Game3.lua` | Finisher | J1, J8, S7, S8, S9 |  | refactor/QA deferred: J1, J8 |
| `src/core/game3/audio.lua` | Finisher | G5 |  |  |
| `src/core/game3/bag.lua` | Finisher | F5, F6 |  |  |
| `src/core/game3/battle/ai_cmds.lua` | Finisher | C7, U8 |  |  |
| `src/core/game3/battle/ai_switch.lua` | Finisher | C5 |  |  |
| `src/core/game3/battle/anim.lua` | Finisher | D6 |  |  |
| `src/core/game3/battle/anim_sprites.lua` | Finisher | D4, D8 |  | refactor/QA deferred: D8 |
| `src/core/game3/battle/anim_tasks.lua` | Finisher | D2, D4, D5, D8, M4, O3 |  | refactor/QA deferred: D2, D8, M4, O3 |
| `src/core/game3/battle/anim_vm.lua` | Finisher | D1, D5 |  | refactor/QA deferred: D1 |
| `src/core/game3/battle/catch_seq.lua` | Finisher | D6 |  |  |
| `src/core/game3/battle/damage.lua` | Finisher | C4, S5, X2 |  | refactor/QA deferred: X2 |
| `src/core/game3/battle/effect_ids.lua` | Finisher | P3 |  |  |
| `src/core/game3/battle/effects/healing.lua` | Finisher | P1 |  |  |
| `src/core/game3/battle/effects/hit.lua` | Finisher | C3 |  |  |
| `src/core/game3/battle/effects/init.lua` | Finisher | U10 |  |  |
| `src/core/game3/battle/effects/secondary.lua` | Finisher | C1, C2, P5 |  |  |
| `src/core/game3/battle/effects/special.lua` | Finisher | C2, P5 |  |  |
| `src/core/game3/battle/effects/volatiles.lua` | Finisher | C7 |  |  |
| `src/core/game3/battle/engine.lua` | Finisher | C6, C8, C9, S5 |  |  |
| `src/core/game3/battle/evo_seq.lua` | Finisher | D7 |  |  |
| `src/core/game3/battle/held_items.lua` | Finisher | C1 |  |  |
| `src/core/game3/battle/init.lua` | Finisher | M3, S4 |  | refactor/QA deferred: M3 |
| `src/core/game3/battle/moves.lua` | Finisher | S6, U1, U10, U5, U8 |  |  |
| `src/core/game3/battle/residuals.lua` | Finisher | C9 |  |  |
| `src/core/game3/battle/state.lua` | Finisher | S11 |  |  |
| `src/core/game3/battle/switch_seq.lua` | Finisher | D9, S4 |  | refactor/QA deferred: D9 |
| `src/core/game3/battle/ui.lua` | Finisher | S9 |  |  |
| `src/core/game3/battle_bridge.lua` | Finisher | V1 |  |  |
| `src/core/game3/battle_transition.lua` | Finisher | D10 |  |  |
| `src/core/game3/breeding.lua` | Finisher | F4, S11, T6 |  |  |
| `src/core/game3/dataset.lua` | Finisher | B6, L1, S3 |  |  |
| `src/core/game3/daycare.lua` | Finisher | F4, S11, T6 |  |  |
| `src/core/game3/dex.lua` | Finisher | F2, I6, V6 |  | refactor/QA deferred: I6 |
| `src/core/game3/doors.lua` | Finisher | A4, A5 |  |  |
| `src/core/game3/evolution.lua` | Finisher | T5 |  |  |
| `src/core/game3/field.lua` | Finisher | A2 |  |  |
| `src/core/game3/field_effects.lua` | Finisher | A4 |  |  |
| `src/core/game3/gfx.lua` | Finisher | I1, I3, M8, S9, X10 |  | refactor/QA deferred: I1, I3, M8, X10 |
| `src/core/game3/heal_locations.lua` | Finisher | B5 |  |  |
| `src/core/game3/items_data.lua` | Finisher | S3, U2, U3, U7 |  |  |
| `src/core/game3/layout_native.lua` | Finisher | B2 |  |  |
| `src/core/game3/link/battle.lua` | Finisher | H1, H2, H3 |  |  |
| `src/core/game3/link/trade.lua` | Finisher | H1, S2 |  |  |
| `src/core/game3/mail.lua` | Finisher | V3 |  |  |
| `src/core/game3/map.lua` | Finisher | B1, B9 |  | B9 DONE (carved to Refactor) |
| `src/core/game3/options.lua` | Finisher | J2, L3 |  |  |
| `src/core/game3/ow_sprites.lua` | Finisher | L1, L4 |  |  |
| `src/core/game3/party.lua` | Finisher | F2, S11, T4, V3, V4, V6, X10 |  | refactor/QA deferred: X10 |
| `src/core/game3/pc_anim.lua` | Finisher | A6 |  |  |
| `src/core/game3/player.lua` | Finisher | A1, A3, A7, Q3 |  |  |
| `src/core/game3/pokedex_data.lua` | Finisher | F1, I6, J6, S3 |  | refactor/QA deferred: I6, J6 |
| `src/core/game3/rng.lua` | Finisher | F8 |  |  |
| `src/core/game3/runtime.lua` | Finisher | I4, M5, V7 |  | refactor/QA deferred: I4, M5 |
| `src/core/game3/save_schema_firered.lua` | Finisher | F2, F3, F8, H1, J1, V10, V4, V6 |  | refactor/QA deferred: F3, J1, V10 |
| `src/core/game3/scripting/adapters.lua` | Finisher | I2, Q5 |  | refactor/QA deferred: I2 |
| `src/core/game3/scripting/ctx.lua` | Finisher | E4 |  |  |
| `src/core/game3/scripting/disasm.lua` | Finisher | E1 |  |  |
| `src/core/game3/scripting/flags_table.lua` | Finisher | U4 |  |  |
| `src/core/game3/scripting/gfx_ids.lua` | Finisher | U6 |  |  |
| `src/core/game3/scripting/multichoice.lua` | Finisher | S3 |  |  |
| `src/core/game3/scripting/natives.lua` | Finisher | E4, E5, Q10, S11, V2, X7 |  | refactor/QA deferred: X7 |
| `src/core/game3/scripting/natives_cutscene.lua` | Finisher | Q7 |  |  |
| `src/core/game3/scripting/natives_daycare.lua` | Finisher | F4 |  |  |
| `src/core/game3/scripting/natives_events.lua` | Finisher | H4, Q1, Q2, Q3, Q4, Q5, Q6, Q8 |  |  |
| `src/core/game3/scripting/natives_tower.lua` | Finisher | Q9 |  |  |
| `src/core/game3/scripting/natives_trade.lua` | Finisher | F2, S11, T3 |  |  |
| `src/core/game3/scripting/opcodes.lua` | Finisher | E1, E10, E2, E3, Q10 |  |  |
| `src/core/game3/scripting/ops_a.lua` | Finisher | E10, E2, E6, E7, E8, E9, I2, Q10 |  | refactor/QA deferred: I2 |
| `src/core/game3/scripting/stdscripts.lua` | Finisher | Q1 |  |  |
| `src/core/game3/scripting/trainers.lua` | Finisher | J5, S3 |  | refactor/QA deferred: J5 |
| `src/core/game3/special_field_anim.lua` | Finisher | Q7 |  |  |
| `src/core/game3/step_events.lua` | Finisher | H1, H4 |  |  |
| `src/core/game3/tileset_anim.lua` | Finisher | K7 |  |  |
| `src/core/game3/trainer_tower.lua` | Finisher | H5, L1 |  |  |
| `src/core/game3/warp.lua` | Finisher | A3 |  |  |
| `src/core/SaveData.lua` | Finisher | I6, J1, L3 |  | refactor/QA deferred: I6, J1 |
| `src/import/gba/battle_anim_extract.lua` | Finisher | R5 |  |  |
| `src/import/gba/extract_island1.lua` | Finisher | B3, B4, I8 |  |  |
| `src/import/gba/extract_map_events.lua` | Finisher | R1, R3 |  |  |
| `src/import/gba/extract_scripts.lua` | Finisher | E1, I8 |  |  |
| `src/import/gba/items_extract.lua` | Finisher | M7 |  |  |
| `src/import/gba/map_catalog.lua` | Finisher | I7 |  |  |
| `src/import/gba/map_sections_extract.lua` | Finisher | B6 |  |  |
| `src/import/gba/map_tree.lua` | Finisher | I7 |  |  |
| `src/import/gba/map_tree_extract.lua` | Finisher | R1, R4 |  |  |
| `src/import/gba/native_pack.lua` | Finisher | I9 |  |  |
| `src/import/gba/ow_extract.lua` | Finisher | L4, R2 |  |  |
| `src/import/gba/trade_extract.lua` | Finisher | R2 |  |  |
| `src/import/gba/versions.lua` | Finisher | I7 |  |  |
| `src/import/SaveFileIO.lua` | Finisher | L6 |  |  |
| `src/ui/game3/bag_chrome.lua` | Finisher | G2 |  |  |
| `src/ui/game3/bag_menu.lua` | Finisher | G2 |  |  |
| `src/ui/game3/box_storage_ui.lua` | Finisher | T1, T7, V9 |  | refactor/QA deferred: V9 |
| `src/ui/game3/easy_chat.lua` | Finisher | G5 |  |  |
| `src/ui/game3/hud.lua` | Finisher | G4, I4, W1 |  | refactor/QA deferred: I4 |
| `src/ui/game3/map_preview_screen.lua` | Finisher | B5, W6 |  | refactor/QA deferred: W6 |
| `src/ui/game3/naming.lua` | Finisher | G4 |  |  |
| `src/ui/game3/naming_chrome.lua` | Finisher | S3 |  |  |
| `src/ui/game3/pokedex.lua` | Finisher | W5 |  |  |
| `src/ui/game3/pokedex_chrome.lua` | Finisher | W10 |  |  |
| `src/ui/game3/region_map.lua` | Finisher | B5, B7, B8, J9 |  |  |
| `src/ui/game3/save_menu.lua` | Finisher | G1, V1, V5, V6, V7 |  |  |
| `src/ui/game3/shop_chrome.lua` | Finisher | S3 |  |  |
| `src/ui/game3/shop_menu.lua` | Finisher | G7, G8, G9 |  | refactor/QA deferred: G7 |
| `src/ui/game3/summary_menu.lua` | Finisher | W2, W9 |  | refactor/QA deferred: W2 |
| `src/ui/game3/tm_case_chrome.lua` | Finisher | G3 |  |  |
| `src/ui/game3/trainer_card.lua` | Finisher | H3, J3, V5, W2, W3 |  | refactor/QA deferred: J3, W2, W3 |
| `src/ui/game3/trainer_tower_records.lua` | Finisher | H3 |  |  |
| `src/world/game3/WorldAPI.lua` | Finisher | S10 |  |  |
| `storage.lua (ambiguous)` | Finisher | F4, F7, G10, I6, T2, T6, T7, V10… | `src/core/game3/storage.lua`, `tests/modkit/cases/storage.lua` | refactor/QA deferred: I6, V10, V9 |
| `tests/game3_special_events_test.lua` | Finisher | Q1, Q2 |  |  |
| `WorldAPI.lua (ambiguous)` | Finisher | B10 | `src/world/WorldAPI.lua`, `src/world/game3/WorldAPI.lua`, `src/world/gen2/WorldAPI.lua` |  |
| `adapter.lua (ambiguous)` | Refactor | P4 | `src/core/game3/battle/adapter.lua`, `tests/drivers/gold/adapter.lua` |  |
| `bg.lua (ambiguous)` | Refactor | X10 | `src/core/game3/battle/bg.lua`, `src/core/game3/bg.lua` |  |
| `quest_log.lua (ambiguous)` | Refactor | W11 | `src/core/game3/quest_log.lua`, `src/ui/game3/quest_log.lua` |  |
| `src/core/game3/battle/commands.lua` | Refactor | X9 |  | carved from unassigned (no lane) — X9 DONE |
| `src/core/ChipAudio.lua` | Refactor | I6 |  |  |
| `src/core/DeltaSkin.lua` | Refactor | I6 |  |  |
| `src/core/game3/battle/anim_pal.lua` | Refactor | D1 |  |  |
| `src/core/game3/battle/anim_port/g1_pic_sizes.lua` | Refactor | O7 |  |  |
| `src/core/game3/battle/anim_port/g1_pret.lua` | Refactor | O1, O9 |  |  |
| `src/core/game3/battle/anim_port/g1_sprite.lua` | Refactor | O4 |  |  |
| `src/core/game3/battle/anim_port/g1_templates.lua` | Refactor | O4 |  |  |
| `src/core/game3/battle/anim_port/g2_fire.lua` | Refactor | O3 |  |  |
| `src/core/game3/battle/anim_port/g2_mon_sizes.lua` | Refactor | O7 |  | now a derived view of g1_pic_sizes (O7 DONE) |
| `src/core/game3/battle/anim_port/g2_pret.lua` | Refactor | D1, D2, M4, O2, O4, O9 |  |  |
| `src/core/game3/battle/anim_port/g3_data.lua` | Refactor | O4 |  |  |
| `src/core/game3/battle/anim_port/g3_e3b.lua` | Refactor | O8 |  |  |
| `src/core/game3/battle/anim_port/g3_pic_size.lua` | Refactor | O6 |  | FILE DELETED (O6 DONE — duplicate of g1_pic_sizes) |
| `src/core/game3/battle/anim_port/g3_pret.lua` | Refactor | D2, M4, O2, O5, O6 |  |  |
| `src/core/game3/battle/anim_port/g3_psychic.lua` | Refactor | O9 |  |  |
| `src/core/game3/battle/anim_port/g4_pret.lua` | Refactor | O1, O2, O9 |  |  |
| `src/core/game3/battle/anim_port/g4_tasks.lua` | Refactor | O6 |  |  |
| `src/core/game3/battle/catching.lua` | Refactor | M6 |  |  |
| `src/core/game3/battle/effects/setup.lua` | Refactor | P4 |  |  |
| `src/core/game3/battle/effects/stats.lua` | Refactor | P4 |  |  |
| `src/core/game3/battle/items.lua` | Refactor | M6 |  |  |
| `src/core/game3/display.lua` | Refactor | K1 |  |  |
| `src/core/game3/field_view.lua` | Refactor | K3, K5, K8, K9, M1 |  |  |
| `src/core/game3/map_ids.lua` | Refactor | J8, M5 |  |  |
| `src/core/game3/oam.lua` | Refactor | X10 |  |  |
| `src/core/game3/pokemon_size_record.lua` | Refactor | V9 |  |  |
| `src/core/game3/scripting/natives_queries.lua` | Refactor | I6 |  |  |
| `src/core/game3/trig.lua` | Refactor | D2, M4 |  | shared Trig.arcTan2 added (O2 DONE); D2/M4 copies still deferred |
| `src/core/Music.lua` | Refactor | I6 |  |  |
| `src/core/SessionLifecycle.lua` | Refactor | I6 |  |  |
| `src/core/TouchSkin.lua` | Refactor | I6 |  |  |
| `src/import/CacheFs.lua` | Refactor | I6, L5 |  |  |
| `src/import/gba/palette_rules.lua` | Refactor | M2 |  |  |
| `src/import/gba/pokemon_extract.lua` | Refactor | M8 |  |  |
| `src/inventory/Bag.lua` | Refactor | I6 |  |  |
| `src/ui/game3/battle_chrome.lua` | Refactor | X5 |  |  |
| `src/ui/game3/frlg_font.lua` | Refactor | K2 |  |  |
| `src/ui/game3/help_system.lua` | Refactor | W7 |  |  |
| `src/ui/game3/new_game_scene.lua` | Refactor | K10 |  |  |
| `src/ui/game3/pc_chrome.lua` | Refactor | M8, W4 |  |  |
| `src/ui/game3/pc_menu.lua` | Refactor | G6 |  |  |
| `src/core/game3/battle/bg.lua` | Architect | I10 |  |  |
| `src/core/game3/bg.lua` | Architect | I10 |  |  |
| `src/core/game3/collision.lua` | Architect | I10 |  |  |
| `src/core/game3/scripting/collision.lua` | Architect | I10 |  |  |
| `src/mods/Loader.lua` | Architect | J10 |  |  |
| `src/mods/Schemas.lua` | Architect | J10 |  |  |
| `src/world/Collision.lua` | Architect | I10 |  |  |

## Deferred until the lead clears them

Refactor/QA findings whose files are Finisher-owned (anti-conflict rule). Do not start these until the Finisher lands the bugfix on the same file.

| Finding | File(s) | Lane | Title |
|---|---|---|---|
| B9 | map.lua | Refactor | `Map.refreshWorld` cache is not invalidated on reload — **carved to Refactor, DONE** (see B9 row) |
| D1 | anim_pal.lua, anim_vm.lua, g2_pret.lua | Refactor | Per-sprite-per-frame option-table allocation in the anim draw path |
| D2 | anim_tasks.lua, g2_pret.lua, g3_pret.lua | Refactor | `gSineTable` copies drift from the canonical `Trig.SINE` |
| D8 | anim_sprites.lua, anim_tasks.lua | Refactor | `AnimTasks.clear_task` leaves non-underscore task fields on recycled slots |
| D9 | switch_seq.lua | Refactor | `SwitchSeq` mutates the step's shared `sides` table when sorting |
| F3 | save_schema_firered.lua | Refactor | Save schema field asymmetry |
| G7 | shop_menu.lua | Refactor | `shop_menu` rebuilds stock/sell rows and price/name strings every frame |
| I1 | gfx.lua | Refactor | `gfx.lua` is the Gen 3 UI router misnamed as drawing primitives |
| I2 | ops_a.lua, scripting/adapters.lua | Architect | Core scripting depends on 16 UI screens |
| I3 | gfx.lua | Refactor | New cycle `display ⇄ gfx`, plus `display → ui.help_system` |
| I4 | hud.lua, runtime.lua | Refactor | `hud ⇄ runtime` cycle |
| I6 | Bag.lua, CacheFs.lua, ChipAudio.lua | Refactor | Additional load-order cycles outside Gen 3 |
| I10 | core/game3/battle/bg.lua, core/game3/bg.lua, core/game3/collision.lua | Architect | Duplicated responsibility: three collision modules and two bg modules |
| J1 | Game3.lua, SaveData.lua, save_schema_firered.lua | Architect | FireRed conflation at the save layer |
| J3 | trainer_card.lua | Refactor | Kanto badge ids and names welded into UI |
| J5 | scripting/trainers.lua | Refactor | Trainer encounter music + rival fallbacks are FRLG class ids |
| J6 | pokedex_data.lua | Architect | Pokédex area map defaults to Kanto and reads FireRed's map groups |
| J7 | pokemon.lua | Refactor | Internal species/form shape pinned to FRLG's 412 |
| J8 | Game3.lua, map_ids.lua | Architect | "Game3 map" is defined as the `FR_`/`SEVII_` string namespace |
| M2 | collision.lua, palette_rules.lua | Refactor | Dead `isBuilding` helper duplicating `PaletteRules.isBuildingCategory` |
| M3 | battle/init.lua | Refactor | Dead `begin_win_award` contradicting its own comment |
| M4 | anim_tasks.lua, g2_pret.lua, g3_pret.lua | Refactor | Four copies of the pret sine table with disagreeing values |
| M5 | map_ids.lua, runtime.lua | Refactor | `isSeviiMap` aliases are dead and misleadingly named |
| M8 | gfx.lua, pc_chrome.lua, pokemon_extract.lua | Refactor | Shadowed/redefined locals in long functions |
| O3 | anim_tasks.lua, g2_fire.lua | Refactor | Base `ShakeTargetInPattern` and its pattern tables are shadowed dead code |
| V9 | box_storage_ui.lua, pokemon_size_record.lua, storage.lua | Refactor | `session.store` read as a store fallback, never written |
| V10 | save_schema_firered.lua, storage.lua | Refactor | Schema reads `save.pc` / `save.pcItems` / `save.pc_items` that `toSaveTable` never writes |
| W2 | summary_menu.lua, trainer_card.lua | Refactor | `require()` on the draw path across chrome/render helpers |
| W3 | trainer_card.lua | Refactor | `TrainerCard` rebuilds its text model every frame |
| W6 | map_preview_screen.lua | Refactor | Map preview re-resolves its entry and rebuilds colours every frame |
| W8 | boot.lua | Refactor | Boot's `COPYRIGHT` phase and `a()` helper are dead |
| X2 | damage.lua | Refactor | `battle/rules.lua` phase-classification subsystem is fully dead |
| X7 | natives.lua | Refactor | `scripting/flags.lua` flag helpers exist only for tests |
| X10 | bg.lua, collision.lua, gfx.lua | Refactor | Smaller zero-caller clusters not itemised above |

## QA lane (test gaps)

- **M10** — untested high-risk modules: `m4a_seq`, `m4a_worker`, `oam`, `palette`, `pal_fade`, `weather`, `options`, `save_mon`, `map_ids`, `trig` (grep for their requires in `tests/` = 0).
- **Status-register F10 residual** — collision/doors/warp now have suites; `player`, `audio`, `field_view` still have none.
- Recommended first suites: `oam` (K1/K6), `player` (A1/A2 class), `weather`/`options` (J2).

## Drift found by re-verification (v3 vs live tree)

These were reported as live in v3 but are already fixed in the working tree — do not schedule them:
`A1`, `E1`, `E2`, `H1`, `H2`, `N-A2`, `N-A22`, `N-A23`, `N-A25`, `N-E3`, `G10`.
Carried `A1` was marked verified=true in v3 and is Worst-25 #8; the current `Player.reset` assigns facing (player.lua:111-115).
`E3` also has an adjacent un-reported sibling: `hidemoneybox` (0x94, opcodes.lua:166) declares size 1 while pret consumes 2 dummy bytes.

## Sweep fixes (Finisher lane, task 01a0c86d)

| ID | Finding | Status | Fix / evidence | Test |
| --- | --- | --- | --- | --- |
| SWP-D1 | `game3_battle_safari`: foe never flees (3 checks) | **DONE** | `src/core/game3/battle/ai.lua:378-387` — when the ROM-extracted AI pack is absent (ROM-less CI), mirror `AI_Safari` (`data/battle_ai_scripts.s:3242`): roll `Rules.safari.fleeRate` → run, else watch. The pack path is unchanged when the pack exists. | `luajit tests/game3_battle_safari_test.lua` → 69 passed, 0 failed |
| SWP-D2 | `game3_save_trainer_card`: expects "saved" with no saveGame | **STALE TEST — left for lead** | Not a src defect: `tests/engine/game3_save_menu_failure_test.lua` (finding G1) deliberately pins "an absent saveGame does not report success". This suite calls `SaveMenu.show` with no game/saveGame and expects phase "saved" (`tests/game3_save_trainer_card_test.lua:109`). Fix belongs in the test stub (`saveGame = function() return true end`); tests/ is out of bounds for this task. | still 1 failed |
| SWP-D3 | `game3_link_session`: expects save TRUE with no saveGame | **STALE TEST — left for lead** | Same G1 contract: `tests/game3_link_session_test.lua:206` asserts `Field_AskSaveTheGame` result 1 while its Runtime stub's game has no `saveGame`. Needs the stub to provide `saveGame → true`. | still 1 failed |

## Finisher batch log — mega-task 01a0c866 (batch 1)

Worst-25-first, Finisher files only. pret = /Users/shanemcgovern/dev/pokefirered (c75f35230). Items 1-2 already recorded above (§C C1, §G G1).

| Worst-25 / ID | Verdict | Evidence (file:line) | pret citation | Test |
| --- | --- | --- | --- | --- |
| #4 C2 Thief/Trick persistent only player-side | **VERIFIED-CORRECT, no edit** | `effects/secondary.lua:379-382` persists attacker + victim; `effects/special.lua:325-328` persists both on Trick | `battle_script_commands.c:2610-2666` MOVE_EFFECT_STEAL_ITEM also writes BOTH sides via `REQUEST_HELDITEM_BATTLE`; the opponent guard reproduces `:2615-2622` (opponent steal only in EREADER/BATTLE_TOWER/LINK/SECRET_BASE) | `tests/game3_battle_move_effects_test.lua` 126/0 |
| #5 C3 Thief/Trick duplicate items on switch-out | **VERIFIED-CORRECT, no edit** | same both-side persist; no player-only guard remains in the persistence path | same as above (`:2658-2662` target write-through) | `tests/game3_battle_move_effects_test.lua` 126/0 |
| #21 C4 Thick Fat halves SpAtk only | **INVALID (report wrong for FRLG)** | `damage.lua:234-236` already matches pret | `pokemon.c:2480-2481`: `if (defender->ability == ABILITY_THICK_FAT && (type == TYPE_FIRE \|\| type == TYPE_ICE)) spAttack /= 2;` — spAttack only; Gen 3 categories are type-based, so no physical Fire/Ice exists | n/a |
| #22 C5 Liquid Ooze recoil for Dream Eater | **INVALID (report wrong for FRLG)** | `effects/hit.lua:372-380` Ooze branch on ABSORB only — matches pret | `data/battle_scripts_1.s:347` (Absorb path) has `jumpifability ... LIQUID_OOZE`; `:427-464` `BattleScript_EffectDreamEater` has NO Ooze check and `battle_script_commands.c:6643-6649` `Cmd_negativedamage` has none either | n/a |
| #10 G4 Hud→Naming wrong arg | **DONE (already fixed in tree)** | `naming.lua:489-512` split into `update(dt)` + `handleInput(input)`; `hud.lua:58-59` routes input, `:183` ticks `update(dt)` | n/a (engine contract test is the ground) | `tests/engine/game3_naming_update_contract_test.lua` green |
| #6 B1 Map.load nil def keeps old collision grid | **DONE (already fixed in tree)** | `map.lua:379-387`: `if def then Collision.bindMap(...) else Collision.clear() end` | n/a (engine test) | `tests/engine/game3_map_def_less_bind_test.lua` green |
| #16 "File browser unescaped `io.popen("ls …")`" (row mislabelled L3; §L L3 is actually the save-slot finding) | **DONE (already fixed in tree)** | `src/ui/kit/FileBrowser.lua:62` and `:111` both wrap the path in `shQuote` (`:11`); `grep -rn "io.popen" src/` shows no unquoted shell call | n/a | no dedicated test; code inspection |
| #24 J2 Option block hardcoded `"firered"` | **DEFERRED to RSE patch T1.1** (lead order: RSE patches after this batch) | `src/core/game3/options.lua:5` still `Options.BLOCK = "firered"` | per-request lead instruction | n/a |

## Finisher batch log — priority-ladder items 1-5 (task 01a0c866)

pret = /Users/shanemcgovern/dev/pokefirered @ c75f35230.

| # | Item | Status | Fix (file:line) | pret citation | Test |
| --- | --- | --- | --- | --- | --- |
| 1 | Opcode operand desync 0xa8/0xa9 | **DONE** | `src/core/game3/scripting/opcodes.lua:188` `{H,B,B,B}` size 6, `:191` `{H,B,B}` size 5 | `src/scrcmd.c:1122-1130` (`VarGet(ScriptReadHalfword)` + 3 bytes), `:1133-1140` (halfword + 2 bytes) | 9 suites: ops coins/scene/vars, givemon layout, script verbs, elevation_oam_priority, corner_slots, nurse_joy, braille — all rc=0 |
| 2 | T6 day-care party-full guard | **DONE** | `natives_daycare.lua:78` helper; `:199` TakePokemonFromDaycare, `:218` TakePokemonFromRoute5Daycare, `:324` egg (refactored onto the helper); `daycare.lua`/`breeding.lua` untouched | `FourIsland_PokemonDayCare/scripts.inc:86-88`, `FourIsland/scripts.inc:95-104`, `day_care.inc:79-81`, `src/daycare.c:525,:1081` | `game3_daycare_breeding/hatch/menu/model` rc=0; model test 9 re-split (special guard vs model write-through pin) + new 9b Route 5 guard |
| 3a | RSE patch T0.2 (version round-trip) | **DONE** | `save_schema_firered.lua:117,191,261`; `SaveData.lua:1128` gen3 via engine tag; `Game3.lua` `_hasContinueSave` + profile refusal list | per rse-seams §4 (no pret claim: engine identity plumbing) | new `tests/engine/game3_save_version_roundtrip_test.lua` 9/9; gamestats 10/10; save_pokeball 13/0; stitchsave all passed; full gate exit 0 |
| 3b | RSE patch T1.1 (`Options.block`, J2 folded) | **DONE** | `options.lua:5-11` BLOCK from profile, `:43-73` `Options.block(engine, blockId)` + `Options.blockId(session)` | profile-driven (fire red arm identical) | new `tests/engine/game3_options_block_test.lua` 15/15; full gate exit 0 |
| 3c | RSE patch T1.2 (map prefixes) | **DONE** | `map_ids.lua` `isGame3Map(mapId, gameId)` via `Profile.of(...).map.prefixes`; `map_catalog.lua` `pret_to_engine` uses `Profile.active().map.enginePrefix` | profile = FR_ / SEVII_ (unchanged) | map_onload, doors_table, doors_viewport, engine map_section_unresolved — all rc=0 |
| 4a | `game3_special_trade` (last D-list FAIL) | **DONE** | `natives_events.lua:175-189` `ShowFieldMessageStringVar4` sets `ctx.messageOpen` and calls `openMessageStay(text, nil)` — it previously called a non-existent `adapters.showMessage` (triage Q5) | `src/field_specials.c:120` `ShowFieldMessage(gStringVar4)`; box stays until the script closes it, same seam as the msgbox opcode (`ops_a.lua` msgbox branch) | `game3_special_trade` all passed; `game3_oneoff_specials` 32/0 |
| 4b | CableClub `ShowBattleRecords` VM release | **DONE** | `natives_tower.lua:567-584` — no screen module or no active runtime host ⇒ `yieldHost(... done() end)` so the waitstate completes; screen path unchanged | `data/scripts/cable_club.inc:566-575` (special + waitstate + releaseall), `data/specials.inc:207`, `src/battle_records.c:83` | `game3_tower_screen` 0 FAILs (hosted path still yields), tower state/party, special handlers/ids, link_session all rc=0; probes: unhosted ⇒ released, hosted ⇒ parks. Cache audit suite needs an objects pack absent from this machine — QA to re-run |
| 4c | `region_map`/`pokemon` extract markers on fresh imports | **DONE** | `RomExtractorGen3.lua:613-614` — parallel success path writes both markers (previously only the sequential fallback at :626/:637/:648) | importer contract (no pret claim) | `game3_import_hardening` all passed incl. new section 4 (parallel path writes both markers); `game3_region_map_assets` rc=0 |
| 5a | E10: 16 FRLG no-op ops wired | **DONE** | `ops_a.lua:17-36` `PRET_NO_OPS` table + `:2018` branch (checked after the host/mod command table) | each op cited in `docs/game3/e10-opcode-spec.md` §3.2 (all `src/scrcmd.c`) | probe (silent no-op, no "skip op" log) + 11 ops/script suites rc=0 |
| 5b | E10: `gettime` wired | **DONE** | `ops_a.lua:1977-1983` zeroes 0x8000/0x8001/0x8002 | `src/scrcmd.c:673-681` (RTC commented out; vars zeroed, never stale) | probe asserts all three zeroed from a non-zero seed |
| 5c | E10: `choosecontestmon` wired | **DONE** | `ops_a.lua:1984-1992` parks the script (mode=native, poll ⇒ false) | `src/scrcmd.c:2010-2016`: `ChooseContestMon()` commented out but `ScriptContext_Stop(); return TRUE;` live | probe asserts yield + stop + no resume; script suites rc=0 |
| 5d | E10: `setobjectsubpriority`/`resetobjectsubpriority` behaviour | **BLOCKED — needs a design call (ladder item 6's seam class); per lead: reclassified to the seam class — 2 reclassified, E10 wired = 18/20** | layout already fixed (row 1); behaviour wiring has no engine path: `Oam.setSubpriority` (`oam.lua:289`) has **zero callers**, no field object carries an OAM id (no `spriteId`/`oamId` anywhere in `src/core/game3/`), and `field_view.lua:555` recomputes `actorPriority` every frame so a store would be clobbered | `src/scrcmd.c:1122-1140` uses `SetObjectSubpriority`/`ResetObjectSubpriority` against the object-event sprite | n/a — propose treating with the 6 seam-decision ops |
| NEW-W3 | StartMenu POKéMON entry is not gated on `FLAG_SYS_POKEMON_GET` | **NEW FINDING (W3, unrouted)** — fix queued at tail position | `src/ui/game3/start_menu.lua:37` appends the POKéMON entry unconditionally; pret gates it: `if (FlagGet(FLAG_SYS_POKEMON_GET) == TRUE) AppendToStartMenuItems(STARTMENU_POKEMON)` — `pokefirered/src/start_menu.c:217-218`, flag id 0x828 (`include/constants/flags.h:1374` = SYS_FLAGS+0x28; engine `flags_table.lua:1324`) | gate entry `:37` the way the POKéDEX entry is gated at `:35`, then update `tests/game3_scenario_menu_test.lua` (its header documents the gap and pins the current 6-entry behaviour) | not yet run |

## Finisher batch log — tail batch 1 (item 6) DONE rows

| Row | Fix (file:line) | pret citation | Test |
| --- | --- | --- | --- |
| U9 | `pokemon.lua` HM table: `[250]` WHIRLPOOL removed from `HM_MOVES` | `include/constants/items.h:411-418` — FRLG HM01-08, no Whirlpool HM | `game3_national_dex_test`, `game3_growth_evolution_test` rc=0 |
| E7 | `ops_a.lua` `random` branch VarGets its operand via `var_get` | `src/scrcmd.c:455-461` `VarGet(ScriptReadHalfword(ctx))` | `game3_ops_vars_test`, `game3_ops_coins_test` rc=0 |
| E6 | `ops_a.lua` money ops: amount read RAW, change gated on the disable byte (the `>=0x4000` VarGet heuristic removed) | `src/scrcmd.c:1798-1830` + `asm/macros/event.inc:1166-1186` ("If 'disable' is set to anything but 0 then this command does nothing") | `game3_ops_coins_test`, `game3_battle_rewards_test` rc=0 |
| P2 | `secondary.lua` RAPIDSPIN is one if/else-if chain (wrap → leech seed → spikes) | `src/battle_script_commands.c:8435-8474` `Cmd_rapidspinfree` | `game3_battle_special_moves_test` rc=0 ×2 after re-pinning the one-per-use expectation (Knock Off precedent, chain order cited in the test), plus `game3_battle_move_effects_test`, `game3_partial_trap_safari_test` rc=0 |
| X1 | `field.lua` fishing tracks `rounds`; randVal+4 only on round 0 else randVal+1, capped 10 | `src/field_player_avatar.c:1740-1746` (Fishing4) + `:1761-1765` (Fishing5 `tRoundsPlayed++`) | `game3_field_items_test`, `game3_encounters_areas_test`, `engine/fishing_cast_timing_bug2064` rc=0 |
| F4 | delivered via the T6 guard (`natives_daycare.lua:78/:199/:218/:324`) — see the T6 row | FourIsland/day_care.inc cites in the T6 row | 4 daycare suites rc=0 |
| H5 | **ESCALATED** — clearing `modData.savedPlayerParty` inside `LoadPlayerParty` breaks `game3_tower_party_test` test 3; pret `src/load_save.c:170` copies save-block → live and does NOT consume the save-block copy, so a second Load still works. Edit reverted (`trainer_tower.lua` clean); the engine has no run-end event after the final Load to clear a lingering copy in. Needs a design call. | `src/load_save.c:160/:170`, `src/trainer_tower.c:1033-1035` | `game3_tower_party_test` rc=0 ×2 after revert |

## Finisher batch log — tail batch 2 (item 6)

| Row | Status | Fix / evidence (file:line) | pret citation | Test |
| --- | --- | --- | --- | --- |
| E8 | **DONE** | `ops_a.lua` — warp family VarGets x/y (warp branch), `setmetatile` VarGets all four operands, `dofieldeffect` VarGets the effect id, `setweather` VarGets the weather id; `flags.lua` `Flags.getVar` now passes a non-var id straight through (`id < 0x4000 → return id`) | `src/scrcmd.c:719-731` (warp x/y), `:2103-2108` (setmetatile all four), `:2042-2049` (dofieldeffect), `:685-691` (setweather), `src/event_data.c:235-241` VarGet passthrough (`GetVarPointer == NULL → return idx`) | 12/12: engine save_slots, save_file_io, save_confirm_layout + ops vars/coins/scene, stitchscript warp_gifts/seams, map_onload, special_events, field_forced_movement all rc=0 |
| L3 | **DONE** | `SaveData.lua:937-946` `valid_slot_id` (`^slot%d+$`) inside `slotNames` (single choke point; returns nil for anything else) + caller guards: `decodeSlot`, `saveNames` (falls back to legacy names), `slotDiskPath` (returns nil), `readSlotSourceIn`, `writeSlotIn` (`invalid slot id`), `deleteSlotIn` | row fix: validate slot ids before building any save path | probe: `slotDiskPath("firered", "../evil")` → nil (traversal blocked); engine save_slots/save_file_io/save_confirm_layout rc=0 |
| L1 | **DONE (already fixed in tree)** | the three cited sites are all sandboxed: `src/core/Data.lua:267` `load(bytes, ..., "t", {})`, `src/core/game3/dataset.lua:97` same, `src/core/game3/ow_sprites.lua:31` same | row cites dataset.lua:97 as the pattern | engine suites rc=0 in gate4/gate5 |
| L4 | **DONE (already fixed in tree)** | `src/core/game3/ow_sprites.lua:57-70` clamps width/height/frameCount (MAX 256/256/512) and verifies `#rgba == w*h*n*4` before any image allocation | — | covered by the OW/battle-anim suites (green in gate4) |
| B6 | **DONE (already fixed in tree)** | `src/core/game3/dataset.lua:189-199` only trusts a `secInfo.resolved` id — an unidentified map no longer advertises secId 88 PALLET TOWN | `src/region_map.c:3782` cited in `map_sections_extract.lua` (extract already returns `resolved = found ~= nil` at `:399`) | `tests/engine/game3_map_section_unresolved_test.lua` 8/8, `game3_map_onload_test` rc=0 |
| H5 | **INVALID (fix-as-written)** — adjudicated, see the H5 row | reverted; residual to Architect seam 8 | `src/load_save.c:170`, `src/trainer_tower.c:1033-1035` | `game3_tower_party_test` rc=0 ×2 |

## Finisher batch log — tail batch 3: the 7 W2 CONFIRMED-BUG rows

| Row | Status | Fix (file:line) | pret citation | Test |
| --- | --- | --- | --- | --- |
| E8 | **DONE** | `ops_a.lua` warp VarGets x/y (:1183-1188), `setmetatile` VarGets 4 (:1373-1376), `dofieldeffect` (:1377-1379), `setweather` (:1400-1401); `flags.lua:360` `Flags.getVar` passes ids < 0x4000 through (fixes `buffernumberstring` literals too) | `scrcmd.c:719-731`, `:2103-2108`, `:2042-2049`, `:685-691`; `event_data.c:235-241` (`GetVarPointer == NULL → return idx`) | 12/12 (ops vars/coins/scene, stitchscript warp_gifts/seams, map_onload, special_events, field_forced_movement + engine save suites) + gate5 **EXIT 0** |
| P5 | **DONE** | `secondary.lua` STEAL_ITEM gate + `special.lua` Trick gate now allow opponent steals only in Link/Battle Tower/e-Reader/Secret Base and never in Trainer Tower; new `st.battleTower`/`st.secretBase` flags (`init.lua:499-507`) set from `StartSpecialBattle` (`natives_tower.lua` runBattle opts) | `battle_script_commands.c:2610-2622` (STEAL_ITEM) and `:8799-8810` (Cmd_tryswapitems), `battle_tower.c:895-933` (case 0/1) | `game3_battle_move_effects_test` 126/0 (opponent steal still blocked in regular battles), doubles_engine, baton_pass, switch_and_faint, tower_party, link_battle all rc=0 |
| H6 | **DONE** | `mystery_gift.lua` `createEventMon` validates species via `Pokemon._names[species]` and clamps level 1-100 before `giveMon`/`giveEgg`; invalid payload returns nil (caller refuses) | `mystery_gift.c:191-210` validateCard covers only the five card fields — the species payload is engine-side and must self-validate | `game3_gift_delivery`, `game3_gift_menu`, `game3_gift_model` all rc=0 |
| Q9 | **INVALID (no FRLG caller) — deferred to RSE** | whole-repo grep: the ONLY FRLG invocation of `special StartSpecialBattle` is `data/maps/SevenIsland_House_Room2/scripts.inc:23` with `VAR_0x8004 = 2` (e-reader), which the engine already handles; cases 0/1 are the RS paths with no FRLG script. Building their foes needs `gSaveBlock2Ptr->battleTower` data the engine does not model (`capabilities.lua:51`: FRLG's tower is modeled as trainerTower; battleTower is RSE-future) and case 1 has no foe builder in pret either (the script stages the party) — implementing them = inventing data. The auto-LOSS branch is the safe dead path. | `battle_tower.c:895-933` (case 0 `FillBattleTowerTrainerParty`, case 1 stages nothing), `data/specials.inc:247` | n/a — no FRLG path can reach it (`game3_tower_party_test` e-reader case rc=0) |
| R3 | **DONE** | `extract_map_events.lua` `parse_objects` reads the `kind` byte (+2); clones (255) decode the clone union (`targetLocalId`/+8, `targetMapNum`/+12, `targetMapGroup`/+14) with sane STAY movement instead of garbage, and every object now carries `kind` + `cloneTarget` | `include/global.fieldmap.h:110-130` (template + union), `include/constants/event_objects.h:194-195` (NORMAL 0 / CLONE 255), usage `src/overworld.c:410`, `src/event_object_movement.c:1326` | `game3_hidden_items_test` rc=0 (parser suite touching this file), full gate below |
| U6 | **DONE** | `gfx_ids.lua:29` unmapped with an honest comment: pret gfx 48 = OBJ_EVENT_GFX_WORKER_F, engine has no worker sprite so `spriteFor` falls back; the old entry claimed SCIENTIST (which is gfx 55) | `include/constants/event_objects.h:54` (WORKER_F=48), `:61` (SCIENTIST=55) | object suites + gate below |
| U8 | **DONE** | `battle/moves.lua` `M()` captures `target` from extra (so curated rows keep pret's target; from_rom already did) + GROWL row gets `target = 8` | `src/data/battle_moves.h` `[MOVE_GROWL] .target = MOVE_TARGET_BOTH`, `include/battle.h:63` (`MOVE_TARGET_BOTH = 1 << 3`) | `game3_battle_doubles_engine_test`, `baton_pass`, `switch_and_faint`, `move_effects` all rc=0 |


