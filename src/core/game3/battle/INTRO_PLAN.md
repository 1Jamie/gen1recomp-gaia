# Battle intro + trainer presentation — implementation plan

Target: FRLG `BeginBattleIntro` presentation for the owned game3 battle engine, built the
same way move anims were (ROM/pret-derived assets → cache → host present state → runtime
sequencer). Reference tree: `/home/autumn/src/pokefirered` (`$POKEFIRERED`).

---

## 1. Scope

### Goals

1. **In-battle intro** for wild and single trainer battles:
   BG intro slide → sprite slide-in → party summary (trainer) → intro message →
   opponent send-out → player throw + send-out → healthbox slide-in → `command`.
2. **Trainer front pics** and **player back pics** resolved from the ROM (lazy decode with
   cache write-through, mirroring `Pokemon.frontPic`), plus a small `trainers.lua` data
   extract for trainer class / name / pic id.
3. **Soft field fade** into the battle scene (`src/ui/game3/fade.lua`), which already ticks
   and draws around `Battle.draw` for free.
4. **Party status summary** bar + balls during the trainer intro. Cheap: the balls are
   already in the extracted healthbox element sheet; only the 128×8 bar needs a new offset.
5. Fix the trainer intro string, which currently prints the **lead mon's** name instead of
   the trainer class + name.

### Non-goals (explicitly deferred)

- `battle_transition.c` mugshots / VS wipe / all 15 `BattleTransition_*` effects. The field
  side keeps a plain fade.
- Double battles, link/multi, Safari, Ghost, Old Man tutorial, Pokédude intro variants.
- Shiny sparkle anim (`TryShinyAnimation`), `Intro_WaitForShinyAnimAndHealthbox`.
- Real GBA scanline/window effects in the BG slide (`gScanlineEffectRegBuffers`, `WIN0V`).
  Approximated — see §7.
- Non-Poké Ball ball graphics (`ItemIdToBallId`); MVP always uses the Poké Ball sheet.
- Real cries (`Audio.playCry` is already a timing stub; the sequencer only waits on it).

---

## 2. Why a new sequencer, not `AnimSeq`

`anim_seq.lua` is the per-hit loop (`anim → wait VM → tweenHp → wait`) driven from
`Engine.resolveMove` output. The intro is a different shape: a fixed script of
presentation beats with no hit list, exactly like `exp_seq.lua` (award → bar → level →
learn) and `evo_seq.lua`. So: **new `intro_seq.lua`, same module contract**
(`reset` / `busy` / `begin(...) -> bool` / `update() -> done`).

Likewise the intro send-out is **not** an `AnimVm` script. In pret, `Special_BallThrow` /
`Special_BallThrowWithTrainer` are the *catch* throw (`AnimTask_ThrowBall`,
`AnimTask_IsBallBlockedByTrainerOrDodged`) — they are the wrong animation and they are also
tasks the VM currently stubs. The intro send-out is `DoPokeballSendOutAnimation` in
`src/pokeball.c`: pure C sprite callbacks with no battle-anim script at all. `pack.special`
has no send-out entry to wire up. **Therefore the send-out is implemented as host tweens in
`anim.lua` driven by `intro_seq.lua`**, using pret's exact frame counts (§5). This is the
same call the repo already made for `HorizontalLunge` (a `noGfx` template routed to a host
visual task).

---

## 3. Architecture

```
                      ROM (FireRed USA 1.0, sha1 41cb23d8…)
                                     │
  ┌──────────────────────────────────┴────────────────────────────────────┐
  │ src/import/gba/trainer_extract.lua              (NEW)                 │
  │   gTrainers / gTrainerClassNames  → data/generated/gba/trainers.lua   │
  │   gTrainerBackPicTable[0..1]      → …/trainers/back_<0|1>.rgba        │
  │ src/import/gba/battle_chrome_extract.lua        (EXTEND)              │
  │   gBattleInterface_PartySummaryBar_Gfx → …/pokemon/battle/            │
  │                                            party_summary_bar.rgba     │
  └──────────────────────────────────┬────────────────────────────────────┘
                                     │  CacheFs (firered/ prefix)
  ┌──────────────────────────────────┴────────────────────────────────────┐
  │ src/core/game3/trainer_pic.lua                  (NEW)                 │
  │   TrainerPic.front(picId)  – lazy ROM LZ decode + cache write-through  │
  │   TrainerPic.back(gender)  – 5-frame 64×320 strip                     │
  │ src/core/game3/scripting/trainers.lua           (REWRITE)             │
  │   Trainers.info(id) -> { class, className, name, picId, partySize }   │
  └──────────────────────────────────┬────────────────────────────────────┘
                                     │
  ┌──────────────────────────────────┴────────────────────────────────────┐
  │ src/core/game3/battle/anim.lua                  (EXTEND)  = the HOST  │
  │   Anim._stage : { slide, trainer[side], ball, healthbox[side],        │
  │                   partyBar[side] }                                    │
  │   Anim.stage() / Anim.introSlideDone() / Anim.tweenStage(...)         │
  │   Anim.present(side).visible / .darken   (mon hidden until release)   │
  │   Anim._introTweening feeds Anim.busy()                               │
  └──────────────────────────────────┬────────────────────────────────────┘
                                     │
  ┌──────────────────────────────────┴────────────────────────────────────┐
  │ src/core/game3/battle/intro_seq.lua             (NEW)  = SEQUENCER    │
  │   step table (wild | trainer), one beat per entry (§5)                │
  └──────────────────────────────────┬────────────────────────────────────┘
                                     │
  ┌──────────────────────────────────┴────────────────────────────────────┐
  │ src/core/game3/battle/init.lua   phase "intro" delegates to IntroSeq  │
  │ src/core/game3/battle/ui.lua     draws trainers / ball / gated boxes  │
  │ src/core/game3/battle/healthbox.lua  accepts visible + ox/oy          │
  └───────────────────────────────────────────────────────────────────────┘
```

Nothing new is required in `anim_vm.lua` / `anim_sprites.lua` / `anim_tasks.lua`. The intro
draws from `Anim._stage` in `ui.lua`, in the same z-order slot the mon sprites already use.

---

## 4. Verified ROM offsets (FireRed USA 1.0, file offsets)

All of these were confirmed against the local dump (sha1
`41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc`) — structural scan plus byte-exact comparison
against pret data where a reference file exists.

| pret symbol | file offset | layout | notes |
|---|---|---|---|
| `gTrainerFrontPicTable` | `0x23957C` | 148 × 8B `{u32 ptr, u16 size, u16 tag}` | `tag == index`; size `0x800` mostly, `0x1000` for a few (2-frame sheets — use frame 0 only) |
| `gTrainerFrontPicPaletteTable` | `0x239A1C` | 148 × 8B `{u32 ptr, u16 tag, u16 pad}` | LZ → 32B (16 colors) |
| `gTrainerBackPicTable` | `0x239FA4` | 6 × 8B | `[0]`=Red `0x2800`, `[1]`=Leaf `0x2800` → **5 frames** of 64×64 4bpp |
| `gTrainerBackPicPaletteTable` | `0x239FD4` | 6 × 8B | |
| `gTrainers` | `0x23EAC8` | stride `0x28` | `+1` trainerClass, `+3` trainerPic, `+4` trainerName[12], `+0x20` partySize (u32), `+0x24` party ptr |
| `gTrainerClassNames` | `0x23E558` | 107 × 13B | GBA charmap, `0xFF`-terminated; `0x53 0x54` = `{PKMN}` |
| `gBattleInterface_PartySummaryBar_Gfx` | `0xE7BB04` | LZ → 512B = 128×8 4bpp | byte-exact vs `graphics/battle_interface/party_summary_bar.png`; palette = `healthbox_pal` @ `0xD11B84` (already extracted) |

Spot checks that passed: trainer `326/327/328` (Oak's Lab rival) → class `81`, pic `106`,
name `"TERRY"`, partySize `1`; class `81` = `"RIVAL"`, `86` = `"COOLTRAINER"`, `88` =
`"GENTLEMAN"`; pic `106` LZ-decodes to exactly 2048 tile bytes + 32 palette bytes.

Two things that **need no extract at all**:

- **Party summary balls** — `sPartySummaryBallSpriteSheets` is
  `gBattleInterface_Gfx + B_INTERFACE_GFX_BALL_PARTY_SUMMARY` where the constant is `66`
  (`src/battle_interface.c:46`). That is tile 66 of the already-extracted
  `pokemon/battle/elements.rgba` (320×24), and `BattleChrome`'s existing
  `elements_tile_quad(ti)` indexes it directly. Four tiles: 66..69.
- **The Poké Ball sprite** — `graphics/interface/ball/poke.png` is 16×48 (3 frames of
  16×16) and is already extracted as `ball_poke.png` from
  `Versions.OAK_SPEECH.ball_poke_tiles = 0xD01724` / `ball_poke_pal = 0xD017E0`, loaded by
  `src/ui/game3/boot.lua` as `assets.ballPoke` and already drawn frame-by-frame in
  `src/ui/game3/oak_scene.lua`. Reuse that loader; do not add a new one.

### Trainer pic placement (no coords table needed)

`OpponentHandleDrawTrainerPic` computes `y = (8 - gTrainerFrontPicCoords[id].size) * 4 + 40`
and every front-pic entry has `size == 8`, so the opponent trainer sprite **center is always
(176, 40)**. Same for `PlayerHandleDrawTrainerPic`:
`(8 - gTrainerBackPicCoords[id].size) * 4 + 80` with `size == 8` for Red/Leaf → **player back
center (80, 80)** (note: `80`, not the mon's `72`). So `gTrainerFrontPicCoords` /
`gTrainerBackPicCoords` do not need extracting. Sprites are 64×64, so top-left = center − 32.

---

## 5. Sequencer step tables

Frame counts are pret's, at 60 Hz. `f` = frames.

### Shared beat vocabulary (`intro_seq.lua` step kinds)

| kind | data | effect |
|---|---|---|
| `fade` | `mode, speed` | `Fade.begin`; wait on `Fade.isActive()` |
| `bgslide` | `frames` | tween `stage.slide` 0→1; unlock sprite motion partway (`gIntroSlideFlags`) |
| `slidein` | `who, from, to, frames` | tween `stage.trainer[side].ox` or `Anim.present(side).ox` |
| `undarken` | `side, frames` | tween `Anim.present(side).darken` 10/16 → 0 |
| `partybar` | `side, dir` | tween `stage.partyBar[side].ox`, set `.balls` from party |
| `msg` | `text` | `pushMsg`; the `Ui.pump()` gate in `Battle.update` blocks until drained |
| `trainerexit` | `side, dx, frames` | linear translate the trainer sprite off-screen; hide its party bar |
| `throwpose` | `frames[]` | drive `stage.trainer.player.frame` through the back-pic anim |
| `ballarc` | `from, to, frames, arcH` | tween `stage.ball.{x,y}`; parabolic `y` |
| `ballwait` | `frames` | plain delay (opponent ball hangs before opening) |
| `release` | `side` | ball frame 1, `present.visible = true`, `oy` 16→0 over 14f, cry |
| `cry` | `side` | `Audio.playCry`; wait `Audio.isCryFinished()` |
| `healthbox` | `side` | tween `stage.healthbox[side].ox` ±115 → 0 over 23f, `visible = true` |
| `wait` | `frames` | delay |

### Wild

| # | step | pret source | frames |
|---|---|---|---|
| 1 | `fade` FROM_BLACK | (repo-side; not pret) | 16 |
| 2 | `bgslide` | `BattleIntroSlide1/2/3` by terrain | 24 (unlock sprites at 8) |
| 3 | `slidein` enemy mon `ox −240 → 0` @ +2/f, `darken = 10/16` | `OpponentHandleLoadMonSprite` sets `x2 = -DISPLAY_WIDTH`; `SpriteCB_MoveWildMonToRight` does `x2 += 2`; `SpriteCB_EnemyMon` does `BeginNormalPaletteFade(…, 10, 10, RGB(8,8,8))` | 120 |
| 4 | `cry` enemy (pan 25) | `PlayCry_Normal` at `x2 == 0` | — |
| 5 | `undarken` enemy | `BeginNormalPaletteFade(…, 10, 0, …)` in `SpriteCB_WildMonShowHealthbox` | 10 |
| 6 | `healthbox` enemy | `StartHealthboxSlideIn` | 23 |
| 7 | `msg` `Wild {MON} appeared!` | `STRINGID_INTROMSG` → `sText_WildPkmnAppeared` | — |
| 8 | `msg` `Go! {MON}!` | `STRINGID_INTROSENDOUT` → `sText_GoPkmn` | — |
| 9 | player throw block (§5.1) | `PlayerHandleIntroTrainerBallThrow` | ~120 |
| 10 | `healthbox` player | `Intro_TryShinyAnimShowHealthbox` | 23 |

Note the ordering: in pret the wild mon's healthbox appears **before** the "appeared!"
message, because the sprite callback chain and `gBattleMainFunc` advance in parallel. The
sequencer is serial, so slotting the healthbox at step 6 reproduces the visible result.

### Trainer

| # | step | pret source | frames |
|---|---|---|---|
| 1 | `fade` FROM_BLACK | — | 16 |
| 2 | `bgslide` | `BattleIntroPrepareBackgroundSlide` | 24 |
| 3 | `slidein` **both**: enemy trainer `ox −240 → 0` @ +2/f, player back `ox +240 → 0` @ −2/f | `SpriteCB_TrainerSlideIn`, both `DrawTrainerPic` handlers | 120 |
| 4 | `partybar` enemy `(104, 40)`, `ox −100 → 0` @ +5/f, and player `(136, 96)`, `ox +100 → 0` @ −5/f | `CreatePartyStatusSummarySprites` (`battle_interface.c:1080`) | 20 |
| 5 | `msg` `{CLASS} {NAME}\nwould like to battle!` | `sText_Trainer1WantsToBattle` | — |
| 6 | `msg` `{CLASS} {NAME} sent\nout {MON}!` | `sText_Trainer1SentOutPkmn` | — |
| 7 | `trainerexit` enemy `176 → 280`, hide enemy party bar | `OpponentHandleIntroTrainerBallThrow` (`data[0]=35`, `data[2]=280`) + `Task_HidePartyStatusSummary` | 35 |
| 8 | `ballwait` then `release` enemy | `SpriteCB_OpponentMonSendOut` waits `data[0] > 15`; ball spawns at `(enemy cx, enemy cy + 24)` | 16 + 14 |
| 9 | `cry` enemy, `healthbox` enemy | `Intro_TryShinyAnimShowHealthbox` | 23 |
| 10 | `msg` `Go! {MON}!` | `sText_GoPkmn` | — |
| 11 | player throw block (§5.1), hide player party bar | `PlayerHandleIntroTrainerBallThrow` | ~120 |
| 12 | `healthbox` player | | 23 |

### 5.1 Player throw block (shared by wild and trainer)

From `PlayerHandleIntroTrainerBallThrow` + `Task_StartSendOutAnim` +
`SpriteCB_PlayerMonSendOut_1/2` + `SpriteCB_ReleaseMonFromBall` + `HandleBallAnimEnd`:

1. `throwpose` — player back pic anim 1, verified byte-exact against
   `src/data/trainer_graphics/back_pic_anims.h` (`sAnimCmd_Red_1` / `sAnimCmd_Leaf_1`, and
   the same bytes read back from the ROM anim table at `0x239EBC`):
   frame 1 (20f) → 2 (6f) → 3 (6f) → 4 (24f) → 0 (1f) = **57f total**.
   Concurrently `trainerexit` player `80 → −40` over **50f** (`data[0]=50`, `data[2]=-40`).
2. After **31f** (`Task_StartSendOutAnim` gate `data[1] < 31`), the ball spawns at
   **(48, 70)** and arcs to `(player cx, player cy_pic_offset + 24)` over **25f** with arc
   height **−30** (`SpriteCB_PlayerMonSendOut_1`: `data[0]=25`, `data[5]=-30`).
3. `release`: ball anim frame 1, ball-open particles, mon `visible = true`, mon `oy` 16 → 0
   over ~**14f** (`data[1] = 0x1000`, `−288`/f, `y2 = data[1] >> 8`), affine
   `BATTLER_AFFINE_EMERGE` scale-up, cry (pan −25).

For MVP the "affine emerge" can be a `Task.tween` on a new `present.scale` (0.2 → 1.0 over
14f) rather than a real affine matrix; the `oy` rise is already 1:1.

### 5.2 Exact strings (fixing the current bug)

`Battle.start` currently pushes `State.displayName(st.enemy) .. " wants\nto battle!"` — the
**mon** name, and Gen-1 wording. FRLG (`src/battle_message.c`):

| case | pret string |
|---|---|
| wild intro | `Wild {B_OPPONENT_MON1_NAME} appeared!` |
| trainer intro | `{B_TRAINER1_CLASS} {B_TRAINER1_NAME}\nwould like to battle!` |
| trainer send-out | `{B_TRAINER1_CLASS} {B_TRAINER1_NAME} sent\nout {B_OPPONENT_MON1_NAME}!` |
| player send-out | `Go! {B_PLAYER_MON1_NAME}!` |

`{B_TRAINER1_CLASS}` = `gTrainerClassNames[gTrainers[id].trainerClass]`,
`{B_TRAINER1_NAME}` = `gTrainers[id].trainerName`. When `trainerId` is absent, fall back to
`"{PKMN} TRAINER"` (class 0) and no name, collapsing the double space.

Rival trainers (class `81` = `RIVAL`) carry the placeholder name `"TERRY"` in the struct; the
real name lives in the save. If the session has a rival name, prefer it — otherwise the
struct name is the correct display fallback.

---

## 6. Ordered work slices

Each slice is independently landable and leaves the game runnable.

### Slice 1 — trainer data (no visuals)

- `src/import/gba/versions.lua`: add
  ```lua
  Versions.TRAINER_FRONT_PIC_TABLE     = 0x23957C
  Versions.TRAINER_FRONT_PIC_PAL_TABLE = 0x239A1C
  Versions.TRAINER_BACK_PIC_TABLE      = 0x239FA4
  Versions.TRAINER_BACK_PIC_PAL_TABLE  = 0x239FD4
  Versions.TRAINERS_TABLE              = 0x23EAC8
  Versions.TRAINER_STRIDE              = 0x28
  Versions.TRAINER_CLASS_NAMES         = 0x23E558
  Versions.TRAINER_CLASS_NAME_STRIDE   = 13
  Versions.TRAINER_CLASS_COUNT         = 107
  Versions.TRAINER_PIC_COUNT           = 148
  Versions.TRAINERS_COUNT              = 743  -- pret NUM_TRAINERS
  ```
  and bump the format-version comment block at the top like the other entries.
- **New** `src/import/gba/trainer_extract.lua`, modelled on
  `battle_moves_extract.lua` / `battle_chrome_extract.lua`
  (`FORMAT_VERSION`, `CACHE_SUB = "trainers"`, `run(rom, cache, opts)`, `ready(cache, root)`):
  - decode names via `TextIR.CHARMAP` exactly as `pokemon_extract.lua`'s `decode_name` does
    (it already handles the `0xBB`/`0xD5` letter ranges and `0xFF` EOS);
  - write `data/generated/gba/trainers.lua` → `{ classNames = {...}, trainers = { [id] = { class, pic, name, partySize } } }`;
  - write `data/generated/gba/trainers/manifest.lua`.
- Wire into `PokemonExtract.run` next to the existing sub-extracts
  (`src/import/gba/pokemon_extract.lua:567-591` — same `progress("trainers", 0, 1)` shape),
  and return it in the detail table so `RomExtractorGen3:runPokemonExtract` reports it.
- Add `--trainers` to `src/import/gba/cli_extract.lua` following the `--battle-anims` branch.
- **Rewrite** `src/core/game3/scripting/trainers.lua`: keep `Trainers.foeFromId` (the
  hardcoded Oak's Lab parties stay as the party source until a `gTrainers` party extract
  lands) and add `Trainers.info(id)` reading the generated pack, with the current
  hardcoded table as the fallback when the cache is missing.
- Thread `trainerId` through: `ops_a.lua:718-751` already has it →
  `adapters.lua:980` `startTrainerBattle(foe, done, battleOpts)` → `battle_bridge.lua:181`
  `Battle.start{...}`. Add `trainerId = opts.trainerId` and let `Battle.start` resolve
  class/name/pic through `Trainers.info`. Store on `st` as
  `st.trainerId / st.trainerClassName / st.trainerName / st.trainerPicId`.
- **Fix the strings now** (§5.2), still pushed synchronously. This alone is a visible win
  and keeps the diff reviewable.

### Slice 2 — trainer pics

- **New** `src/core/game3/trainer_pic.lua`. Copy the shape of
  `src/core/game3/pokemon.lua:761-880`:
  - `decode_pic_rgba(index, picTable, palTable, cacheRel, frames)` — the mon version is
    hardcoded to 8×8 tiles; generalise to `frames` so the back pic decodes as a 64×320
    vertical strip (5 × 64×64);
  - `TrainerPic.front(picId)` → `{ image, w = 64, h = 64 }`, cache
    `data/generated/gba/trainers/front/<picId>.rgba`;
  - `TrainerPic.back(gender)` → `{ image, w = 64, h = 320, frames = 5 }`, cache
    `data/generated/gba/trainers/back/<gender>.rgba`;
  - reuse `Versions.gbaToFile` and `src/import/gba/lz77.lua` as the mon path does;
  - for `0x1000`-sized front entries take the first 2048 bytes only.
- The 2 player back sheets are needed in **every** battle, so also bake them eagerly in
  `trainer_extract.run` (2 × 5 × 16 KB = 160 KB) so a shipped cache never needs the ROM.
  Front pics stay lazy, matching the existing mon-pic tradeoff.
- `src/import/CacheContract.lua`: add to `VERSION_REQUIRED_FILES_OVERRIDE.firered`
  (after the existing `pokemon/party/slot_main.rgba` line):
  ```
  "data/generated/gba/trainers.lua",
  "data/generated/gba/trainers/back_0.rgba",
  "data/generated/gba/trainers/back_1.rgba",
  ```
  Adding required files invalidates existing caches by design, so bump
  `CacheContract.VERSION_FORMAT.firered` from `"rom-cache-v1-firered:"` to
  `"rom-cache-v2-firered:"` in the same commit.

### Slice 3 — host stage state (`anim.lua`)

- Add `Anim._stage` and `Anim.resetStage()` (called from `Anim.reset`):
  ```lua
  Anim._stage = {
    slide = 0, slideDone = false,
    trainer = { player = { visible=false, ox=0, oy=0, frame=0, gender=0 },
                enemy  = { visible=false, ox=0, oy=0, picId=nil } },
    ball    = { visible=false, x=0, y=0, frame=0, side=nil },
    healthbox = { player = { visible=false, ox=0 }, enemy = { visible=false, ox=0 } },
    partyBar  = { player = { visible=false, ox=0, balls={} },
                  enemy  = { visible=false, ox=0, balls={} } },
  }
  ```
- `Anim.stage()`, `Anim.introSlideDone()`.
- `Anim.tweenStage(frames, onStep, onComplete)` — thin wrapper over `Task.tween` that
  raises/lowers a new `Anim._introTweening` counter.
- Add `Anim._introTweening > 0` to `Anim.busy()`, next to `_hpTweening` / `_expTweening`.
  Keep the existing comment's warning in mind: this must gate *in-flight tweens only*, not
  "the sequencer has steps left", or `Battle.update` soft-locks.
- Extend `default_present(side)` with `darken = 0` and `scale = 1`; both must be honoured in
  `ui.lua`'s `draw_mon_sprite`.
- Headless: `Anim.reset({ headless = true })` must leave `slideDone = true` and everything
  `visible = true` so `runToEnd` never sees a hidden battler.

### Slice 4 — sequencer (`intro_seq.lua`)

- **New** `src/core/game3/battle/intro_seq.lua`, structurally a sibling of `exp_seq.lua`:
  `IntroSeq.reset()`, `IntroSeq.busy()`, `IntroSeq.begin(st, opts) -> bool`,
  `IntroSeq.update() -> done`, module-local `_steps/_i/_waiting/advance()/finish()`.
- `begin` builds the step list from `st.wild` (§5) and returns `false` when
  `opts.headless` — the caller then pushes the strings directly.
- `update` follows `ExpSeq.update`'s orphan-wait guard: if `_waiting` and
  `not Anim.busy()`, `advance()`.
- `opts`: `{ pushMsg, headless, playerGender, trainerClassName, trainerName, trainerPicId, playerParty, foeParty }`.

### Slice 5 — engine phase (`init.lua`)

- `require` `IntroSeq`; add `IntroSeq.reset()` to `finish()` and `Battle.runToEnd()`
  alongside the other `*.reset()` calls.
- In `Battle.start`, replace the `if not opts.headless then … Ui.push(…) end` block
  (`init.lua:175-183`) with `IntroSeq.begin(st, {...})`. Keep the headless branch pushing
  the four strings in the same order so text-log assertions stay stable.
- Replace the `Battle._phase == "intro"` branch (`init.lua:469-477`). It currently sits
  *after* the shared `if Anim.busy() then return end; if not Ui.pump() then return end`
  gate, which is exactly the gate the sequencer wants, so the body becomes:
  ```lua
  if Battle._phase == "intro" then
    if not IntroSeq.update() then return end
    Battle._phase = "command"
    if Battle._auto then
      begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
    else
      Ui.openMenu()
    end
    return
  end
  ```
- Accept and store the new `opts` (`trainerId`, `trainerClass`, `trainerName`,
  `trainerPicId`, `playerGender`) on `st`.

### Slice 6 — drawing (`ui.lua`, `healthbox.lua`)

- `ui.lua` `draw_mon_sprite`: honour `pres.darken` (lerp toward `RGB(8,8,8)` = `(8/255)`)
  and `pres.scale` (scale about the sprite centre). `pres.visible == false` is already
  respected at line 271.
- New locals in `ui.lua`:
  - `draw_trainer_sprite(side)` — `TrainerPic.front(stage.trainer.enemy.picId)` at centre
    `(176 + ox, 40)`; `TrainerPic.back(gender)` quad-clipped to frame `stage.trainer.player.frame`
    at centre `(80 + ox, 80)`.
  - `draw_intro_ball()` — `assets.ballPoke` quad `(0, frame*16, 16, 16)` at
    `(stage.ball.x − 8, stage.ball.y − 8)`. Pull the image through
    `src/ui/game3/boot.lua`'s `ballPoke` rather than adding a second loader.
  - `draw_party_bar(side)` — `party_summary_bar.rgba` (128×8) at `(x + ox, y)` plus up to 6
    balls from `BattleChrome` element tile 66 at `(x + 8*i, y − 4)`.
- Insert into `Ui.draw` between the terrain and the mon sprites, matching pret subpriority:
  BG → enemy trainer → enemy mon → particles → player mon → player trainer → ball →
  healthboxes → party bars → panel.
- `Healthbox.draw(side, battler)` gains an `opts` or reads `Anim.stage().healthbox[side]`:
  skip entirely when `visible == false`, and offset both the box and its text/bars by `ox`.
  Today `Ui.draw` calls it unconditionally at lines 398-399.
- `BattleChrome.drawTerrain` / `BattleBg.draw` take an optional `x` offset so `bgslide` can
  scroll the terrain (pret scrolls `gBattle_BG1_X += 6`/frame).

### Slice 7 — party summary asset

- `src/import/gba/versions.lua`: `Versions.BATTLE_CHROME.party_summary_bar = 0xE7BB04`.
- `battle_chrome_extract.lua`: LZ → 512 B, decode as 16 tiles → 128×8, palette
  `healthbox_pal`, write `pokemon/battle/party_summary_bar.rgba`; add
  `partySummaryBar = { file = ..., w = 128, h = 8 }` plus
  `partyBarPlayer = { x = 136, y = 96 }`, `partyBarOpponent = { x = 104, y = 40 }`
  to the generated `manifest.lua`. Bump `BattleChromeExtract.FORMAT_VERSION` 3 → 4.
- `battle_chrome.lua`: load it in `install`, expose `BattleChrome.drawPartyBar(x, y)` and
  `BattleChrome.drawPartyBall(x, y, kind)` (element tiles 66..69).

### Slice 8 — field fade + docs

- `BattleBridge.start` (`battle_bridge.lua:149`): before `Battle.start`, run
  `Fade.begin(Fade.MODE.TO_BLACK, 1, cb)` and start the battle in the callback. `Runtime`
  already ticks `Fade` (`runtime.lua:149`) and `Gfx.drawUi` already draws it after
  `Battle.draw` (`display.lua:132-141`, `gfx.lua:121-124`), so the FROM_BLACK half needs
  nothing beyond being step 1 of the sequencer.
- Update `src/core/game3/battle/PARITY.md`:
  - Layers table: new row **Battle intro / send-out** — *Owned MVP: BG slide approximation,
    trainer slide-in, party summary, ROM trainer pics, pret-timed ball send-out. Deferred:
    battle_transition mugshot/VS, shiny anim, doubles.*
  - "Battle anim architecture" list: add
    `**Intro sequencer** intro_seq.lua: bgslide → slide-in → party summary → msgs →
    send-out → healthbox (pret BeginBattleIntro + DoPokeballSendOutAnimation)`.
  - "Pret 1:1 (later pass)": add battle transitions, shiny anim, real affine emerge,
    scanline BG slide.
  - Note that the send-out is deliberately **not** an `AnimVm` script, with the reason.

---

## 7. Risks and accepted MVP shortcuts

| # | risk / shortcut | mitigation |
|---|---|---|
| 1 | **BG intro slide is not reproducible.** `BattleIntroSlide1/2/3` drive `WIN0V`, `BLDCNT`, and per-scanline `gScanlineEffectRegBuffers` — no equivalent in the LÖVE compositor. | Approximate: horizontal terrain scroll (pret's `gBattle_BG1_X += 6`) plus a vertical wipe. What actually matters for parity is the *gate*: sprites must not move until the slide releases them, which `stage.slideDone` reproduces exactly. Flag it in `PARITY.md`. |
| 2 | **Total intro is long** (~7 s for a trainer battle at pret timings). | Keep the frame counts (they are the real game), but let `A`/`B` skip the remaining tweens by fast-forwarding the sequencer — the same affordance `Message` already gives. |
| 3 | **Lazy ROM decode needs the `.gba` in cwd.** `Pokemon.load_rom_bytes` scans three hardcoded filenames. A shipped cache with no ROM gets no trainer front pic. | Eager-bake the 2 player back sheets (always needed). For fronts, `TrainerPic.front` returning `nil` must degrade to *no trainer sprite* (skip straight to the send-out), never a placeholder rectangle — the "don't invent FX" rule. A follow-up slice can bake all 148 (≈2.4 MB). |
| 4 | **`Anim.busy()` soft-lock.** The comment at `anim.lua:99-101` documents that folding "sequencer has work left" into `busy()` deadlocks `Battle.update`. | `_introTweening` must be incremented only for in-flight `Task.tween`s and decremented in their `onComplete`. Cover with a test that drives 2000 frames and asserts the phase reaches `command`. |
| 5 | **Affine emerge** (`BATTLER_AFFINE_EMERGE`) is a real OAM matrix anim. | `present.scale` linear 0.2 → 1.0 over 14f. Visually close; note in `PARITY.md`. |
| 6 | **Trainer party for the summary bar** is unknown — `scripting/trainers.lua` only hardcodes three Oak's Lab parties and `st.foeParty` holds one mon. | `gTrainers[id].partySize` (offset `+0x20`) is in the extract, so the bar can show the right *count* of full balls without a party extract. Fall back to 1 ball. |
| 7 | **Cries are stubs.** `Audio.playCry` just sets a 64-frame timer. | Fine — the sequencer only needs the timing. |
| 8 | **`{PKMN}` in class names** is the 2-byte `0x53 0x54` charmap pair. | Decode to the literal `"POKéMON"` that `FrlgFont` can render, as the rest of the repo's strings do. |
| 9 | **Rival name.** Class 81 trainers carry the placeholder `"TERRY"`. | Prefer a session rival name when present; the struct name is the correct fallback. |
| 10 | **Cache invalidation.** New `CacheContract` required files reject every existing FireRed cache. | Intended; bump `VERSION_FORMAT.firered` in the same commit so the launcher explains the re-import instead of reporting a corrupt cache. |

---

## 8. Test plan

### Automated (`luajit tests/<name>.lua`, the CI convention)

**New `tests/game3_battle_intro_test.lua`**, following the plain
`check(cond, msg)`-and-`print("[test] N. …")` style of `tests/game3_intro_test.lua`:

1. **Offsets** — assert every `Versions.TRAINER_*` constant equals the value in §4. Cheap
   regression guard; `tests/game3_intro_test.lua` already does exactly this for
   `Versions.INTRO_MOVIE`.
2. **Step table shape** — `IntroSeq.begin` on a synthetic wild `st` produces steps in the
   §5 order; same for a trainer `st`, asserting the trainer path has `partybar` and
   `trainerexit` and the wild path does not.
3. **Strings** — a trainer battle with `trainerClassName = "RIVAL"`, `trainerName = "TERRY"`
   yields `"RIVAL TERRY\nwould like to battle!"` and
   `"RIVAL TERRY sent\nout SQUIRTLE!"`; a wild battle yields
   `"Wild PIDGEY appeared!"`. This is the bug-fix regression test.
4. **Headless skip** — `Battle.start{ headless = true }` leaves `IntroSeq.busy() == false`
   and `Ui.log()` contains the intro strings in order; `Battle.runToEnd()` still terminates
   within the existing 800-iteration guard.
5. **No soft-lock** — non-headless start, then drive `Battle.update(1/60)` up to 2000 times
   with a stub input; assert `Battle._phase == "command"` and
   `Anim.stage().healthbox.player.visible == true`.
6. **Visibility gating** — immediately after a non-headless `Battle.start`,
   `Anim.present("player").visible == false` and
   `Anim.stage().healthbox.enemy.visible == false`.

Also re-run the neighbours that touch the same modules: `tests/game3_summary_test.lua`
(shares `Pokemon` pic decode) and the `parity_battle_intro_chrome.lua` /
`parity_battle_intro_cry.lua` suites (Gen-2 paths — they must stay green, i.e. untouched).

### Manual

1. `luajit src/import/gba/cli_extract.lua --trainers` → verify
   `data/generated/gba/trainers.lua` has 743 rows, `classNames[81] == "RIVAL"`,
   `trainers[326] == { class = 81, pic = 106, name = "TERRY", partySize = 1 }`.
2. `luajit src/import/gba/cli_extract.lua --pokemon` → confirm
   `pokemon/battle/party_summary_bar.rgba` is 128×8×4 = 4096 bytes.
3. In-game **wild**: walk into Route 1 grass. Expect fade → BG slide → darkened Pidgey
   sliding in from the left → cry → un-darken → enemy healthbox → "Wild PIDGEY appeared!"
   → "Go! …!" → back-pic throw pose + slide-off-left → ball arc → mon rises → player
   healthbox → FIGHT menu.
4. In-game **trainer**: Oak's Lab rival battle. Expect both trainer sprites sliding in from
   opposite edges, both party bars, "RIVAL TERRY would like to battle!", trainer exiting
   right, opponent ball opening, then the player throw. Confirm the message says the
   trainer's class and name, **not** "SQUIRTLE".
5. **Degraded path** — rename the `.gba` out of cwd with a warm cache and start a trainer
   battle: no trainer sprite, no crash, intro still reaches `command`.
6. **Battle end** — win, lose, and run to confirm `finish()` clears the stage and the field
   redraws with no leftover trainer sprite or ball.

---

## 9. File-by-file summary

| file | action |
|---|---|
| `src/import/gba/versions.lua` | + `TRAINER_*` offsets, + `BATTLE_CHROME.party_summary_bar` |
| `src/import/gba/trainer_extract.lua` | **new** — trainers.lua + eager player back sheets |
| `src/import/gba/pokemon_extract.lua` | wire `TrainerExtract.run` into the sub-extract chain |
| `src/import/gba/battle_chrome_extract.lua` | + party summary bar; `FORMAT_VERSION` 3 → 4 |
| `src/import/gba/cli_extract.lua` | + `--trainers` |
| `src/import/CacheContract.lua` | + 3 firered required files; `VERSION_FORMAT.firered` v1 → v2 |
| `src/core/game3/trainer_pic.lua` | **new** — lazy front / eager back pic decode |
| `src/core/game3/scripting/trainers.lua` | + `Trainers.info(id)` from the generated pack |
| `src/core/game3/battle/anim.lua` | + `_stage`, `stage()`, `tweenStage`, `_introTweening`, `present.darken/.scale` |
| `src/core/game3/battle/intro_seq.lua` | **new** — the sequencer |
| `src/core/game3/battle/init.lua` | `Battle.start` builds the intro; `"intro"` phase delegates; resets |
| `src/core/game3/battle/ui.lua` | + trainer / ball / party-bar draws; gate healthboxes; honour darken/scale |
| `src/core/game3/battle/healthbox.lua` | + visibility and `ox` offset |
| `src/core/game3/battle/bg.lua` | + slide `x` offset passthrough |
| `src/ui/game3/battle_chrome.lua` | + `drawPartyBar` / `drawPartyBall` |
| `src/core/game3/battle_bridge.lua` | + `trainerId` passthrough, TO_BLACK fade before start |
| `src/core/game3/scripting/adapters.lua` | + `trainerId` in `startTrainerBattle` opts |
| `src/core/game3/battle/PARITY.md` | intro row + architecture bullet + deferred list |
| `tests/game3_battle_intro_test.lua` | **new** |
