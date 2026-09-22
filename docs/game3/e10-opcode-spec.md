# E10 opcode spec — engine-unwired opcodes vs pret

**Scope:** the engine opcodes that have no handler branch in `src/core/game3/scripting/ops_a.lua`
and therefore fall through to the generic skip path (`ops_a.lua:1956-1975`).

**Pret ground truth:** `pret/pokefirered` @ `c75f3523` ("Merge pull request #770 from Deokishisu/patch-8"),
canonical team clone `/Users/shanemcgovern/dev/pokefirered`. Every behavioural claim below cites
`pokefirered/…` file:line. Nothing here is a fix instruction — the Finisher/applier verifies each against the
cited pret body and engine seams before wiring (C1 lesson: report suggestions are evidence, not instructions).

**Engine snapshot:** `/Users/shanemcgovern/dev/gen1recomp` working tree at time of writing.

---

## 1. Recount — 26, not 63

The v3 review said "63 defined opcodes have no handler" (E10, marked `verified=true` at review time). That no
longer reproduces against this tree:

| Measure | Count |
|---|---|
| Opcodes declared in `opcodes.lua` `Opcodes.TABLE` | **213** |
| Pret `ScrCmd_*` functions in `pokefirered/src/scrcmd.c` | **213** (full parity) |
| Engine ops with an `op == "…"` branch in `ops_a.lua` | **189** |
| Engine ops with **no** branch (this spec) | **26** |

The review's named examples are all wired now, most with pret citations in the code:
`callstd_if`/`gotostd_if` (`ops_a.lua:371`), `applymovementat`/`waitmovementat`/`addobjectat`/`removeobjectat`
(`:1058`), `bufferitemnameplural` (`:804`), `setmonmove` (`:823`), `addpcitem`/`checkpcitem` (`:945`),
`setdooropen`/`setdoorclosed` (`:1085`), `vmessage` (`:913`), `vgoto`/`vcall`/`vgoto_if`/`vcall_if` (`:885`).
Only `createvobject`/`turnvobject` from that list remain unwired.
Also note: `goto_if_set` has a `return false` stub branch in `ops_a.lua` but is **not** an opcode in
`opcodes.lua` — it is a composite pret macro (event.inc), so that branch is dead code, not a coverage gap.

## 2. Classification summary

| Class | Count | Ops |
|---|---|---|
| A — pret FRLG no-op (engine skip is behaviour-equivalent; add explicit no-op branches) | 16 | `initclock`, `dotimebasedevents`, `adddecoration`, `removedecoration`, `checkdecor`, `checkdecorspace`, `drawbox`, `drawboxtext`, `showcontestpainting`, `setberrytree`, `startcontest`, `showcontestresults`, `contestlinktransfer`, `getpokenewsactive`, `addelevmenuitem`, `showelevmenu` |
| B — pret yields (ScriptContext_Stop) | 1 | `choosecontestmon` |
| C — real work, wiring needed | 9 | `setmysteryeventstatus`, `gotonative`, `gettime`, `setobjectsubpriority`, `resetobjectsubpriority`, `createvobject`, `turnvobject`, `loadhelp`, `unloadhelp` |

Pret-side grounding: **26/26 cited** (0 `[pret-unverified]` here). Engine-side readiness differs per op and is
called out in the table: **20 wired-ready** (16 explicit nops + `gettime` + the two subpriority ops +
`choosecontestmon`), **6 need an engine backend or seam decision** (`setmysteryeventstatus`, `gotonative`,
`createvobject`, `turnvobject`, `loadhelp`, `unloadhelp`).

**Operand-layout audit result:** 24/26 declared layouts match pret. Two are **wrong and already desync the
decoder** (not just unwired): `0xa8 setobjectsubpriority` and `0xa9 resetobjectsubpriority` — see §3.1.

---

## 3. Per-op spec

Layout column: `pret` byte sequence from `asm/macros/event.inc` (operands after the opcode byte; `map` expands
to 2 bytes per `asm/macros/map.inc:4-7`). Engine column: declared `op(name, size, args)` from `opcodes.lua`.

### 3.1 Real work — wiring needed

| Op | Pret fn (file:line) | Pret behaviour | Layout pret vs engine | Engine state | Wiring requirement |
|---|---|---|---|---|---|
| `0x0e setmysteryeventstatus` | `src/scrcmd.c:269-273` | `SetMysteryEventScriptStatus(ScriptReadByte(ctx))` — stores the mystery-event script status byte | `B` (2 total) vs `2 {B}` ✅ | unwired | Needs a session save field + writer mirroring `SetMysteryEventScriptStatus`; check pret readers before choosing the field (grep `GetMysteryEventScriptStatus`). No engine field found → **[engine-unverified: seam choice]** |
| `0x24 gotonative` | `src/scrcmd.c:92-97` | `SetupNativeScript(ctx, func)`, returns TRUE: replaces the running script with the C function, resuming the script when it returns TRUE | `W` (5 total) vs `5 {W}` ✅ | unwired; overlaps Q10 (`Natives.callnative` has no `native:` registrations) | Requires a native-function registry + dispatch (Q10). Without it the op can only skip/halt. **[engine-unverified: dispatch design]** |
| `0x2e gettime` | `src/scrcmd.c:673-681` | FRLG: **writes 0 to VAR_0x8000/0x8001/0x8002** (RTC lines commented out) | `—` (1 total) vs `1 {}` ✅ | unwired | Set the three special vars to 0 (pret does not leave them stale). Trivial; wired-ready. |
| `0xa8 setobjectsubpriority` | `src/scrcmd.c:1122-1130` | `localId = VarGet(u16)`, `mapGroup = ScriptReadByte`, `mapNum = ScriptReadByte`, `priority = ScriptReadByte`; `SetObjectSubpriority(localId, mapNum, mapGroup, priority + 83)` | `H, map(2), B` = **5 operand bytes / 6 total** vs engine `5 {B,B,B,B}` = 4 operands ❌ **under-reads 1 byte** | unwired; engine declares wrong layout | Fix layout to `{H,B,B,B}` size 6, then map to the object's OAM subpriority (`oam.lua:292` `Oam.setSubpriority`-style path; `objects.lua` may need a setter). |
| `0xa9 resetobjectsubpriority` | `src/scrcmd.c:1133-1140` | `localId = VarGet(u16)`, group/num bytes; `ResetObjectSubpriority(localId, mapNum, mapGroup)` | `H, map(2)` = **4 operands / 5 total** vs engine `4 {B,B,B}` ❌ **under-reads 1 byte** | unwired; engine declares wrong layout | Fix layout to `{H,B,B}` size 5, then reset the object sprite's subpriority. |
| `0xaa createvobject` | `src/scrcmd.c:1171-1181` | `graphicsId(B)`, `virtualObjId(B)`, `x=VarGet(u16)`, `y=VarGet(u16)`, `elevation(B)`, `direction(B)`; `CreateVirtualObject(...)` — sprite-only NPCs beyond the object limit | `B,B,H,H,B,B` (8 total) vs `8 {B,B,H,H,B,B}` ✅ | unwired | No virtual-object backend found in `src/core/game3/` → needs a design addition (sprite registry keyed by `virtualObjId`, reused by `turnvobject`, cleaned on map unload). **[engine-unverified: backend missing]** |
| `0xab turnvobject` | `src/scrcmd.c:1184-1190` | `virtualObjId(B)`, `direction(B)`; `TurnVirtualObject(id, direction)` | `B,B` (3 total) vs `3 {B,B}` ✅ | unwired | Depends on the `createvobject` backend. |
| `0xc8 loadhelp` | `src/scrcmd.c:1274-1280` | Reads a word (`msg`), falls back to `ctx->data[0]` when NULL, `DrawHelpMessageWindowWithText(msg)` | `W` (5 total) vs `5 {W}` ✅ | unwired; engine has the L/R context Help (`help_system.lua:133 Help.show(game,context)`), not a text help window | Seam decision: does the engine's Help display script text, or should this be a no-op like `signmsg`? Pret behaviour is the cited text window; **[engine-unverified: seam choice]** |
| `0xc9 unloadhelp` | `src/scrcmd.c:1285-1289` | `DestroyHelpMessageWindow_()` | `—` (1 total) vs `1 {}` ✅ | unwired | Pair with `loadhelp`; if loadhelp maps to `Help.close()`, wire this to the same. |

### 3.2 Pret FRLG no-ops (engine skip is equivalent; make it explicit)

All of these are `return FALSE` in pret with the real implementation commented out (FRLG removed the feature).
Wiring = one explicit `return false` branch (no silent skip), so mods/scripts relying on the pret-contract see a
documented no-op. None consume their operands in pret beyond the script reader skipping them, which the
decoder already does via their declared sizes (all ✅ against event.inc).

| Op | Pret fn (file:line) | Pret body | Layout check |
|---|---|---|---|
| `0x2c initclock` | `scrcmd.c:658-664` | RTC lines commented; `return FALSE` | `H,H` (5) vs `5 {H,H}` ✅ |
| `0x2d dotimebasedevents` | `scrcmd.c:667-671` | commented; `return FALSE` | `1` ✅ |
| `0x4b adddecoration` | `scrcmd.c:526-532` | reads var, DecorationAdd commented | `H` (3) vs `3 {H}` ✅ |
| `0x4c removedecoration` | `scrcmd.c:534-540` | commented | `3 {H}` ✅ |
| `0x4d checkdecor` | `scrcmd.c:550-556` | commented | `3 {H}` ✅ |
| `0x4e checkdecorspace` | `scrcmd.c:542-548` | commented | `3 {H}` ✅ |
| `0x72 drawbox` | `scrcmd.c:1464-1472` | window draw commented | `B×4` (5) vs `5 {B,B,B,B}` ✅ |
| `0x74 drawboxtext` | `scrcmd.c:1505-1516` | commented | `5 {B,B,B,B}` ✅ |
| `0x77 showcontestpainting` | `scrcmd.c:1543-1552` | reads 1 byte, commented | `B` (2) vs `2 {B}` ✅ |
| `0x8a setberrytree` | `scrcmd.c:1989-1999` | commented | `B,B,B` (4) vs `4 {B,B,B}` ✅ |
| `0x8c startcontest` | `scrcmd.c:2018-2024` | commented | `1` ✅ |
| `0x8d showcontestresults` | `scrcmd.c:2026-2032` | commented | `1` ✅ |
| `0x8e contestlinktransfer` | `scrcmd.c:2034-2040` | commented | `1` ✅ |
| `0x96 getpokenewsactive` | `scrcmd.c:2002-2008` | commented | `H` (3) vs `3 {H}` ✅ |
| `0xb1 addelevmenuitem` | `scrcmd.c:2178-2187` | commented | `B,H,H,H` (8) vs `8 {B,H,H,H}` ✅ |
| `0xb2 showelevmenu` | `scrcmd.c:2189-2194` | commented | `1` ✅ |

### 3.3 Pret yields

| Op | Pret fn (file:line) | Pret behaviour | Layout | Engine state | Wiring requirement |
|---|---|---|---|---|---|
| `0x8b choosecontestmon` | `scrcmd.c:2010-2016` | `ChooseContestMon()` commented, but **`ScriptContext_Stop(); return TRUE;` are active** — the script halts awaiting context resume | `1` ✅ | unwired → engine continues instead of yielding | Wire as a yield (`vm` pause equivalent / `return true` in the dispatch contract), matching pret's stop. Contest UI itself is absent in FRLG. |

---

## 4. Counts for the lead

- Unwired opcodes (current tree): **26** (review's 63 is stale; all named examples except `createvobject`/`turnvobject` now have cited handlers).
- Pret-grounded: **26/26** — 0 `[pret-unverified]` on behaviour; all bodies in `src/scrcmd.c` + layouts in
  `asm/macros/event.inc`.
- Wired-ready (trivial, no backend needed): **20** — 16 explicit no-ops + `gettime` + `choosecontestmon` +
  `setobjectsubpriority`/`resetobjectsubpriority` (layout fix + existing OAM subpriority seam).
- Needs an engine backend or a seam decision: **6** — `setmysteryeventstatus`, `gotonative`,
  `createvobject`, `turnvobject`, `loadhelp`, `unloadhelp` (each marked `[engine-unverified]` above).
- Pre-existing decoder defects found while auditing: **2** (`0xa8`/`0xa9` under-read 1 byte — scripts
  containing them already desync all later rows, same class as E3).

---

## 5. Seam decisions (Architect, 2026-09-22)

Design + evidence only; no `src/` edits. Engine anchors are this tree, pret anchors
are the canonical clone `~/dev/pokefirered` @ `c75f35230` (plus pret/pokeemerald and
pret/pokeruby over raw.githubusercontent for the cross-game checks, all fetched
2026-09-22).

### 5.0 Cross-game table (why "FRLG-only" is the wrong axis here)

| Op | `pokefirered` macro + handler | `pokeemerald` macro + handler | Usage in FRLG `data/` + `src/` (0 = never emitted) | Verdict |
|---|---|---|---|---|
| `0x0e setmysteryeventstatus` | `asm/macros/event.inc:98` + `src/scrcmd.c:269` | macro present, `data/script_cmd_table.inc:32` → `ScrCmd_setmysteryeventstatus` | **0** | shared FRLG+E, **absent from R/S** |
| `0x24 gotonative` | `event.inc:268` + `src/scrcmd.c:92` | `event.inc` present, `data/script_cmd_table.inc:54` → handler | **0** | shared FRLG+E+R/S (R/S table `data/script_cmd_table.inc:39`) |
| `0xaa createvobject` | `event.inc:1346` + `src/scrcmd.c:1171` | `data/script_cmd_table.inc:188` → handler | **0** | shared FRLG+E, **absent from R/S** |
| `0xab turnvobject` | `event.inc:1357` + `src/scrcmd.c:1184` | `data/script_cmd_table.inc:189` → handler | **0** | shared FRLG+E, **absent from R/S** |
| `0xc8 loadhelp` | `event.inc:1551` + `src/scrcmd.c:1274` | `data/script_cmd_table.inc:218` → **`ScrCmd_nop1`** | **0** | **FRLG-only in effect** (Emerald no-ops it) |
| `0xc9 unloadhelp` | `event.inc:1557` + `src/scrcmd.c:1285` | `data/script_cmd_table.inc:219` → **`ScrCmd_nop1`** | **0** | **FRLG-only in effect** (Emerald no-ops it) |

**None of the six is FireRed-only by macro presence — but none is used by any script
in the FRLG ROM** (0 hits for each across `data/` and `src/`, excluding the command
table and handler). They are reachable only from external Mystery Event payloads
(e-Reader / Wonder Card), which are not in the ROM. That drives the priorities:
all six are **low/medium**, and only `setmysteryeventstatus` has a plausible runtime
source.

The Emerald `0xc8/0xc9 → ScrCmd_nop1` mapping is also a concrete input for the
opcode overlay design in `rse-seams.md` §3.5: an RSE overlay must re-declare both
slots as **size 1** (`nop1`), not the FRLG size-5/size-1 pair, or every later row in
an RSE script desyncs.

### 5.1 `0x0e setmysteryeventstatus` — **handoff, small: Mystery Event status slot**

- **Decision:** give the engine a real status slot mirroring pret's
  `sMysteryEventScriptContext.data[2]`, written by this opcode from the normal VM
  and read back by the Mystery Event runner. No UI, no capability gate.
- **pret:** writer `SetMysteryEventScriptStatus` `src/mystery_event_script.c:92-95`;
  reader `MEventScript_Run` `src/mystery_event_script.c:75-80` (status out-param at `:78`) / `RunMysteryEventScript` `:83-88`; failure path
  `SetIncompatible` sets `3` `src/mystery_event_script.c:46-50`; opcode handler
  `src/scrcmd.c:269-273`; consumers `src/mystery_gift_client.c:257,296`
  (`FUNC_RUN_MEVENT`); header `include/mystery_event_script.h:6-7`. Note pret has a
  **separate** ME-script command `MEScrCmd_setstatus` (`src/mystery_event_script.c:129`)
  in `gMysteryEventScriptCmdTable` — that is a different opcode space and is out of
  scope here.
- **Engine anchors:** opcode declared `src/core/game3/scripting/opcodes.lua:27`;
  dispatch skip path `src/core/game3/scripting/ops_a.lua:1977-1979`; storage candidates
  `src/core/game3/mystery_gift.lua` (no status field today) and
  `src/core/game3/scripting/natives_gift.lua:100-123`.
- **Wiring:** one `elseif op == "setmysteryeventstatus"` case in `dispatch` writing
  `ctx.mysteryEventStatus = row[1]` plus
  `require("src.core.game3.mystery_gift").setStatus(row[1])`; a `getStatus()` mirror.
- **Status value meanings (0/1/2/3):** `[pret-unverified]` — settling file
  `src/mystery_event_script.c` (the ME command handlers that *read* the slot).
- **Tests:** new `tests/engine/game3_mystery_event_status_test.lua` (VM row →
  write → readback; unknown id no-op); regression `tests/game3_gift_delivery_test.lua`,
  `tests/game3_gift_model_test.lua`, `tests/game3_gift_menu_test.lua`.
- **Effort:** small (~15 lines + test). **Owner: handoff** — `ops_a.lua` and
  `mystery_gift.lua` are Finisher-owned.

### 5.2 `0x24 gotonative` — **handoff, deferred: keep documented safe-skip, seam = symbol map**

- **Decision:** do **not** emulate pret's ROM function-pointer jump (impossible
  without executing ROM). Wire the op to a *symbol* resolver: `gotonative <word>`
  looks up `Natives.resolveNative(addr)` → `["native:" .. symbol]`; unmapped logs once
  and skips (the current behaviour, made explicit). Leave the registry empty until
  an extracted symbol table exists.
- **pret:** handler `src/scrcmd.c:92-97` (`SetupNativeScript(ctx, ScriptReadWord(ctx))`);
  `SetupNativeScript` `src/script.c:70`, decl `include/script.h:28` — the word is a
  `bool8 (*)(void)` **native C function pointer**, resumed by the script context.
- **Engine anchors:** `opcodes.lua:52` (declared, size 5 `{W}`); **no dispatch case**
  (`ops_a.lua:1977-1979` skips it); disassembly special-cases it
  `src/core/game3/scripting/disasm.lua:128`; the `native:` namespace has **zero**
  registrations — `Natives.callnative` `natives.lua:883-891` always misses (review Q10).
- **Wiring:** (1) `resolveNative` seam added to the natives registry, (2) one
  `elseif op == "gotonative"` case, (3) later, the extractor emits
  `addr → symbol` from the ROM (T6.x, needs `versions` offsets).
- **Tests:** new `tests/engine/game3_gotonative_test.lua` (unmapped → skip + one log;
  registered symbol → handler invoked, returns TRUE = yield); regression
  `tests/game3_special_ids_test.lua`, `tests/game3_script_verbs_subset_test.lua`.
- **Effort:** seam small, symbol extraction medium (importer + ROM-gated).
  **Owner: handoff** (`ops_a.lua`, `natives.lua` Finisher) + **extractor ticket**.
  Priority **low**: 0 in-ROM users; `[pret-unverified]` whether any e-Reader payload
  emits it (settling file: `src/mystery_event_script.c` payload format + RSE needs
  the pokeemerald clone).

### 5.3 `0xaa createvobject` — **handoff, medium: virtual-object registry**

- **Decision:** add a **virtual-object registry** (id → graphicsId, x, y, elevation,
  direction) owned by a new module, rendered through the existing OW-sprite path with
  no collision, no interaction and no script callback; cleaned up on map unload.
  `turnvobject` (§5.4) mutates the same row.
- **pret:** opcode handler `src/scrcmd.c:1171-1181`; backend
  `CreateVirtualObject` `src/event_object_movement.c:1719` (builds a real sprite with
  `SpriteCB_VirtualObject`, stores `sprite->sVirtualObjId` / `sVirtualObjElev`);
  lookup `GetVirtualObjectSpriteId` `src/event_object_movement.c:9236`; teardown
  `DestroyVirtualObjects` `src/event_object_movement.c:9225`; decl
  `include/event_object_movement.h:96`. In pret these are **sprites, not object
  events** — they never collide or talk.
- **Engine anchors:** `opcodes.lua:192` (declared, `8 {B,B,H,H,B,B}` — layout matches
  pret ✅); no backend exists — `grep -i virtual src/core/game3/objects.lua` → 0 hits;
  draw/collision owners are `src/core/game3/objects.lua` (Finisher) and
  `src/core/game3/ow_sprites.lua` (Finisher, L1/L4), with `field_view.lua`
  (Refactor) in the draw path.
- **Wiring:** new `src/core/game3/virtual_objects.lua`
  (`spawn(vObjId, graphicsId, x, y, elevation, direction)`, `turn(id, direction)`,
  `clear()`, `list()`), consumed by the object draw pass; two `dispatch` cases in
  `ops_a.lua`. Map-unload reset hooks alongside the existing object teardown in
  `objects.lua`.
- **Engine ownership rule:** `x`/`y` are `VarGet` halves in pret
  (`src/scrcmd.c:1174-1175`), so the handler must resolve vars like the existing
  `var_get` helper (`ops_a.lua:46-52`) — do **not** read the raw halves.
- **Tests:** new `tests/engine/game3_virtual_objects_test.lua` (spawn keys the id,
  turn mutates direction, duplicate id replaces, clear empties, unknown id no-ops,
  vars resolved); regression `tests/game3_objects_perm_reset_test.lua`,
  `tests/game3_npc_player_collision_test.lua` (must stay collision-free), plus an
  in-game visual check (headless tests render nothing).
- **Effort:** medium (registry + draw hookup). **Owner: split** — new registry file is
  **A-lane-buildable**; `objects.lua`/`ow_sprites.lua`/`ops_a.lua` wiring is
  **handoff** (all Finisher). Priority low (0 in-ROM users).

### 5.4 `0xab turnvobject` — **paired with §5.3, handoff**

- **Decision:** implement as `VirtualObjects.turn(id, direction)`; a missing id is a
  logged no-op (pret: `GetVirtualObjectSpriteId` returns `MAX_SPRITES` and
  `TurnVirtualObject` does nothing — `src/event_object_movement.c:9248-9257`).
- **Engine anchors:** `opcodes.lua:193`; no dispatch case (`ops_a.lua:1977-1979`).
- **Wiring:** one `elseif` calling the §5.3 registry.
- **Tests:** covered by `tests/engine/game3_virtual_objects_test.lua`; add the
  missing-id no-op row there.
- **Effort:** trivial (subset of §5.3). **Owner: handoff** (same wiring files).

### 5.5 `0xc8 loadhelp` — **handoff, small: dedicated help *message window*, not the L/R Help system**

- **Decision:** implement a **help message window** backend (a `Window` template +
  `Window.print` at pret's fixed position, opened/closed by the opcodes). This is
  **not** `src/ui/game3/help_system.lua` (the L/R context browser) and is **not**
  capability-gated by `helpSystem` — that flag maps to `pokefirered/src/help_system.c`,
  whereas pret's window lives in `src/new_menu_helpers.c` and is also used by the
  start menu (`src/start_menu.c:332,440`), so the primitive is shared UI plumbing.
- **pret:** handler `src/scrcmd.c:1274-1280` (`msg = ScriptReadWord(ctx)`; if NULL
  falls back to `(const u8 *)ctx->data[0]`); backend `DrawHelpMessageWindowWithText`
  `src/new_menu_helpers.c:701-705` (`LoadHelpMessageWindowGfx` →
  `PrintTextOnHelpMessageWindow(text, 2)`); window id from
  `GetStartMenuWindowId()` `src/new_menu_helpers.c:677`. **Emerald maps this slot to
  `ScrCmd_nop1`** (`data/script_cmd_table.inc:218`), so R/S+Emerald scripts never ask
  for it.
- **Engine anchors:** `opcodes.lua:222` (size 5 `{W}` ✅); skip path
  `ops_a.lua:1977-1979`; text resolution already exists — `resolve_text(vm, ptr)`
  `ops_a.lua:36-45` maps a pointer through `Opcodes.key` → `vm:getText(key)`, and the
  NULL/0 fallback in pret maps onto `resolve_text`'s own `ptr == nil/0 → ctx.data[0]`
  handling; window primitives `src/ui/game3/window.lua:62 Window.template`,
  `:86 stdFrame`, `:114 Window.print`; the existing Help browser is a *different*
  API (`help_system.lua:133 Help.show`, `:101 Help.close`).
- **Wiring:** one `elseif op == "loadhelp"` case: `local ir = resolve_text(vm, row[1])`,
  then `HelpWindow.show(TextIR.toPlain(ir, { stringVars = ... }))`. Do **not**
  emulate pret's NULL-cast fallback beyond `resolve_text`'s existing behaviour — it is
  dead/unsafe in pret (0 users).
- **Tests:** new `tests/engine/game3_help_window_opcode_test.lua` (row → window open
  with the resolved string, `resolve_text` fallback for ptr 0, overlay id); regression
  `tests/game3_help_test.lua` (L/R Help browser unchanged) and
  `tests/game3_flags_extract_preserve_test.lua`. Visual check in-game (headless draws
  nothing).
- **Effort:** small (new file ~60 lines + one dispatch case). **Owner: split** —
  new `src/ui/game3/help_window.lua` is **A-lane-buildable**; the `ops_a.lua` case is
  **handoff** (Finisher). Priority low.

### 5.6 `0xc9 unloadhelp` — **paired with §5.5, handoff**

- **Decision:** `HelpWindow.close()`; safe to call when nothing is open (pret
  `DestroyHelpMessageWindow_(2)` — `src/new_menu_helpers.c:707-710`).
- **Engine anchors:** `opcodes.lua:223` (size 1 ✅); no dispatch case.
- **Wiring:** one `elseif` calling the §5.5 backend.
- **Tests:** covered by `tests/engine/game3_help_window_opcode_test.lua` (close with
  no window = no-op).
- **Effort:** trivial (subset of §5.5). **Owner: handoff** (`ops_a.lua`).

### 5.7 Summary for the ticket queue

| Op | Backend decision | Effort | Owner | Priority |
|---|---|---|---|---|
| `setmysteryeventstatus` | Mystery Event status slot on the gift context | small | **handoff** (ops_a + mystery_gift) | medium (external payloads can reach it) |
| `gotonative` | symbol map + documented skip; no ROM-pointer dispatch | small seam / medium extraction | **handoff + extractor ticket** | low (0 in-ROM users) |
| `createvobject` | virtual-object registry (new file) + draw hookup | medium | **A-lane file, handoff wiring** | low (0 in-ROM users) |
| `turnvobject` | same registry, `turn()` | trivial | **handoff** | low |
| `loadhelp` | dedicated help *message window* (new file), `resolve_text` for the word | small | **A-lane file, handoff wiring** | low (Emerald no-ops; 0 users) |
| `unloadhelp` | same window, `close()` | trivial | **handoff** | low |

Open `[pret-unverified]` items: (a) the meaning of the Mystery Event status values,
settling file `src/mystery_event_script.c`; (b) whether any external e-Reader /
Wonder Card payload emits `gotonative`/`loadhelp`, settling file: `src/mystery_event_script.c`
  `MEventScript_InitContext` (`:52-62`, `:70-73`) and the payload entry points; (c) Ruby/Sapphire emitting `gotonative` (its table lists the slot at
`pokeruby data/script_cmd_table.inc:39` but `event.inc` has no macro) — settling file:
a `pret/pokeruby` clone; (d) all RSE `versions_rse.lua` offsets — settling file: the
RSE carts.

### 5.8 `0xa8 setobjectsubpriority` / `0xa9 resetobjectsubpriority` — **handoff, medium: object → draw-order seam**

> **ADDENDUM:** E10 spec wired-ready corrected 20 → 18; set/resetobjectsubpriority
> reclassified to seam class per lead after Finisher call-back 5d.

- **Decision:** freeze the object's **draw-order pair** on the object record and
  stop the per-frame elevation recompute for that object — mirroring pret's
  `fixedPriority` flag. Store `{ fixedPriority = true, subpriority = <byte + 83>, fixedClass = <captured> }`
  on the EventObject; reset drops all three so elevation-driven priority resumes.
  **Do not wire `Oam.setSubpriority`** — that module is compositor/UI only (see the
  anchor list), so the field's ordering seam is `field_view`'s split + sort, not the
  OAM pool.
- **pret:** handler `src/scrcmd.c:1122-1130`
  (`SetObjectSubpriority(localId, mapNum, mapGroup, priority + 83)` — keep the
  `+ 83`), reset handler `src/scrcmd.c:1133-1140`;
  setters `SetObjectSubpriority` `src/event_object_movement.c:2089-2101`
  (`objectEvent->fixedPriority = TRUE; sprite->subpriority = subpriority;`,
  guarded by `TryGetObjectEventIdByLocalIdAndMap`, FALSE = found) and
  `ResetObjectSubpriority` `src/event_object_movement.c:2104-2116`
  (`fixedPriority = FALSE; triggerGroundEffectsOnMove = TRUE` — it does **not**
  restore an old value, it re-enables the dynamic path);
  the two freeze points that make it stick:
  `UpdateObjectEventElevationAndPriority` `src/event_object_movement.c:8379-8387`
  and `ObjectEventUpdateSubpriority` `src/event_object_movement.c:8424-8429` both
  `return` when `fixedPriority`; the dynamic writer they gate is
  `SetObjectSubpriorityByElevation` `src/event_object_movement.c:8414-8422`.
  Other `fixedPriority` writers for context: `src/field_player_avatar.c:2050,2101,2133`,
  `src/event_object_movement.c:4483,7193,7200`.
- **Usage:** **0** scripts in the FRLG ROM emit either op (only the command table,
  `data/script_cmd_table.inc:172-173`) — same low-priority class as §5.1–5.6.
- **Engine anchors:** layout already corrected to pret (Finisher's live bug fix) —
  `src/core/game3/scripting/opcodes.lua:188` `op("setobjectsubpriority", 6, {H,B,B,B})`
  and `:191` `op("resetobjectsubpriority", 5, {H,B,B})`, both citing `scrcmd.c:1122/1133`;
  **no dispatch case** (`src/core/game3/scripting/ops_a.lua:1977-1979` skip path).
  Object store: `Objects._byId = {} -- [localId] = EventObject`
  `src/core/game3/objects.lua:27`, spawn at `:120-145`.
  Per-frame recompute: `ELEVATION_TO_PRIORITY` `src/core/game3/field_view.lua:389-397`,
  `actorPriority()` `:396-417`, **`a.priority = actorPriority(a)` `:554`**,
  over/under split `:555-562` (`< 2` → over), `sortActors` `:563-570`
  (`sortY`, then insertion index), actor draw `drawSingleActor` `:418-452`
  (sprite renderer / `ow_sprites`, **no `oam.lua`**).
  `Oam.setSubpriority` `src/core/game3/oam.lua:289-294` has **zero callers**;
  `oam.lua` is required only by compositor/UI paths
  (`intro_movie.lua:4`, `title_screen.lua:3`, `display.lua:129/227/256`,
  `party_menu.lua:10`, `evolution_scene.lua:15`, `new_game_scene.lua:4`,
  `egg_hatch.lua:8`, `src/core/game3/init.lua:28`) — the overworld never loads it.
- **Wiring (three files, all handoff):**
  1. `src/core/game3/objects.lua` (**Finisher**): add
     `Objects.setFixedPriority(localId, mapId, subpriority)` — resolve the object in
     `Objects._byId`, ignore + `a.log` when `mapId` does not match the object's map
     (engine equivalent of pret's `TryGetObjectEventIdByLocalIdAndMap` guard), else
     set `obj.fixedPriority, obj.subpriority, obj.fixedClass = true, subpriority, nil`;
     and `Objects.resetFixedPriority(localId, mapId)` clearing all three.
  2. `src/core/game3/scripting/ops_a.lua` (**Finisher**): two `elseif` cases —
     `setobjectsubpriority` reads `row[1..4]` (H localId, B group, B num, B priority),
     resolves the halfword through the existing `var_get` (`ops_a.lua:70-76`) as pret
     does with `VarGet`, builds the engine map id from group/num the way
     `showobjectat` already does, and calls the setter with **`row[4] + 83`**;
     `resetobjectsubpriority` does the same for the reset.
  3. `src/core/game3/field_view.lua` (**Refactor**): honour the freeze —
     ```lua
     -- :554
     local obj = a.obj
     if obj and obj.fixedPriority then
       if obj.fixedClass == nil then obj.fixedClass = a.priority or actorPriority(a) end
       a.priority = obj.fixedClass            -- frozen: stop elevation updates
       a.subpriority = obj.subpriority        -- sort key, replaces sortY for this actor
     else
       a.priority = actorPriority(a)
       a.subpriority = nil
     end
     ```
     and in `sortActors` (`:563-570`) order by `(a.subpriority or a.sortY or a.y)`
     so a frozen actor lands where the script put it rather than where its Y says.
  4. **Explicit non-wiring:** `Oam.setSubpriority` stays caller-less; wiring it would
     reach a module the field never loads (verified above). If an actor path ever
     moves onto the OAM pool, that is a separate ticket.
- **Tests:** new `tests/engine/game3_object_subpriority_test.lua` — set writes
  `priority + 83`, wrong map id is a logged no-op, reset clears all three fields,
  `fixedClass` captures only on first frame, and a two-actor fixture proves the frozen
  actor wins the sort while an elevation-driven neighbour still follows
  `ELEVATION_TO_PRIORITY`. Regression:
  `tests/game3_elevation_oam_priority_test.lua`, `tests/game3_collision_npc_dir_test.lua`,
  `tests/game3_npc_player_collision_test.lua` (must stay green — priority changes can
  reshuffle draw order), plus an in-game layering check (headless draws nothing).
- **Effort:** medium (3 files, one per-frame path). **Owner: all three files are
  handoff** (objects/ops_a Finisher, field_view Refactor) — **no A-lane file here**.
- **[pret-unverified]:** whether any e-Reader/Mystery Event payload emits these two
  ops — settling file `src/mystery_event_script.c` payload handling; and whether the
  engine's map id is derivable from (group, num) without the ROM's map group table —
  settling file `src/import/gba/map_catalog.lua`.

### 5.9 H5 residual — Trainer Tower stash copy after the challenge bracket

- **(a) Memory-only or persisted? — PERSISTED (one of the two copies).**
  `Tower.savePlayerParty` writes **both** `session.modData.savedPlayerParty`
  (`trainer_tower.lua:535`, where `save_block()` is `session.modData`,
  `trainer_tower.lua:519-523`) and `session.savedPlayerParty` (`:536`).
  The schema passes `modData` straight through to the file:
  `save_schema_firered.lua:245` `modData = session.modData` (restore `:311`,
  new game `:175`), and **`savedPlayerParty` is not itself a schema key**, so:
  `modData.savedPlayerParty` → **in the save file**; `session.savedPlayerParty` →
  **memory only, dropped on load**. The load path prefers the memory copy
  (`trainer_tower.lua:544`), so across save+reload only the `modData` copy survives.
- **(b) Does pret clear it anywhere? — NO clear point exists.**
  pret's stash target is the save block's own party array:
  `SavePlayerParty` `src/load_save.c:157-166` copies live → `gSaveBlock1Ptr->playerParty`;
  `LoadPlayerParty` `src/load_save.c:167-176` copies back. Nothing ever zeroes that
  area — it is only **overwritten** by the next `SavePlayerParty()`, whose callers are
  `src/load_save.c:198` (inside `SaveSerializedGame`), `src/battle_setup.c:417`,
  `src/teachy_tv.c:1178`, `src/union_room.c:1814,1906,1914,1923`, and the scripts
  `data/maps/SevenIsland_House_Room1/scripts.inc:87,98`,
  `data/maps/SevenIsland_House_Room2/scripts.inc`, `data/scripts/cable_club.inc:288`.
  `src/trainer_tower.c` never stashes or clears a party (0 hits for
  `SavePlayerParty`/`LoadPlayerParty`; `src/trainer_tower.c:1033-1035` reads the live
  `gPlayerParty`), confirming the lead's note. The reads are the specials wired in
  `src/core/game3/scripting/natives_tower.lua:505-515` ← script specials
  `data/specials.inc:50-51`, called by the Seven Island reception scripts
  (`data/maps/SevenIsland_House_Room1/scripts.inc:45,95,111`,
  `Room2/scripts.inc:32`).
- **(c) Verdict: NO ACTION — document only.** Two grounds:
  1. **There is nothing pret-faithful to clear.** pret's copy lives in
     `gSaveBlock1Ptr->playerParty`, which is refreshed on every save by
     `SaveSerializedGame` (`src/load_save.c:196-201`) and never freed — so any
     clear-on-Load (or clear-on-Run-end) the engine invents is engine behaviour with
     no pret counterpart. The Finisher's revert was correct: keep
     `LoadPlayerParty` without a consume (`tests/game3_tower_party_test:3` pins it).
  2. **The lingering copy is not read outside the tower path** — consumers are only
     `natives_tower.lua:505-515`, `Tower.savedPlayerParty` `trainer_tower.lua:559-562`
     and `Tower.copyHeldItems` `:806-820`, all of which the reception script also gates.
     The stale-restore window is therefore the same script window pret has.
- **Trade-off recorded for the lead (open, low stakes):** the engine's `modData` copy
  is *extra* durability — it survives a mid-challenge save+reload where pret's save
  block would already have been overwritten by `SaveSerializedGame`. Dropping it would
  save 6 deep-copied mon records per save but would also let a mid-challenge save
  strand the player on the reduced party (a state pret itself can reach). **Recommendation:
  keep it, no code change**; revisit only if save size becomes a concern, and then by
  moving the copy under a save-time scrub of `modData` keys, not by clearing mid-run.
  **Owner: none (no ticket).** Tests that already pin the current behaviour:
  `tests/game3_tower_party_test:3,172,425-426`,
  `tests/drivers/game3_tower_run.lua:289`.

### 5.10 X6 — `mystery_gift` Gift-stat/card API unwired → **verdict (a) NO ACTION**

**Where this lands:** appended here (append-only) rather than edited into the triage
row, so row X6 keeps its original text and this reasoning sits with the other seam
decisions. **Effort: zero. No schema row, no Finisher handoff.**

- **The seven APIs** (all defined, **zero production callers**; only
  `tests/game3_gift_model_test.lua` exercises them — triage X6 verified this pass):

  | Engine API | Engine line | pret authority | pret's only callers |
  |---|---|---|---|
  | `disableCardSending` | `mystery_gift.lua:561` | `DisableWonderCardSending` `include/mystery_gift.h:66`, body `src/mystery_gift.c:235` | `src/mystery_gift_server.c:269` — **wireless** MG server |
  | `sourceByKey` | `:1361` | link-data idents (`MG_LINKID_*`) | link protocol only |
  | `disableStats` | `:696` | `MysteryGift_DisableStats` `mystery_gift.h:94`, body `src/mystery_gift.c:543` | `src/union_room.c:1781`, `:1874` — **wireless Union Room** |
  | `tryEnableStatsByFlagId` | `:701` | `MysteryGift_TryEnableStatsByFlagId` `mystery_gift.h:95`, body `src/mystery_gift.c:548` | `src/union_room.c:1777` — **wireless Union Room** (pair exchange) |
  | `tryIncrementStat` | `:751` | `MysteryGift_TryIncrementStat` `mystery_gift.h:92`, body `src/mystery_gift.c:561` | `src/cable_club.c:792,795` (battles won/lost), `src/trade_scene.c:2609` (trades) — gated by the flag below |
  | `trySaveStamp` | `:639` | `MysteryGift_TrySaveStamp` `mystery_gift.h:67`, body `src/mystery_gift.c:307` | `src/mystery_gift_client.c:228` — **wireless** MG client |
  | `isNewsSameAsSaved` | `:539` | `IsWonderNewsSameAsSaved` `src/mystery_gift.c:140` | `src/mystery_gift_client.c:211` — **wireless** MG client |

- **The gate that decides everything:** `MysteryGift_TryIncrementStat` runs only
  `if (sStatsEnabled)` (`src/mystery_gift.c:561-564`), and `sStatsEnabled` is
  `static EWRAM_DATA bool32` — **RAM-only, never persisted** (`src/mystery_gift.c:53`).
  Its **only** writer in the whole tree is `TryEnableStatsByFlagId`, whose **only**
  caller is `src/union_room.c:1777`, i.e. the wireless Union Room's two-player
  trainer-card exchange (and the paired `DisableStats` at `:1781`, `:1874`).
  With no Wireless Adapter, `sStatsEnabled` is FALSE forever, so pret's cable-club
  and trade increments are **no-ops for every player who cannot reach the Union
  Room** — which is every player in this engine.
- **No FRLG script reads the surface either:** `ValidateSavedWonderCard`,
  `GetMysteryGiftCardStat` and `WonderNews_GetRewardInfo` appear in
  `data/specials.inc:395/401/404` as `def_special` registrations **only** —
  `grep '^\s*special X' data/` returns **0 call sites** for all three. So the read
  special the engine *does* wire (`src/core/game3/scripting/natives_gift.lua:107`
  → `getCardStatForScript`, `mystery_gift.lua:677`) is itself unreachable from FRLG
  game data; pret's body also `AGB_ASSERT_EX(0, ...)` on a card-type mismatch
  (`src/mystery_gift.c:541`), confirming it is a guarded/unused path.
- **Persistence: already handled, no schema impact.** pret keeps the record at
  `gSaveBlock1Ptr->mysteryGift.*` (`src/mystery_gift.c:467,473,500,520`), engine
  parity at `struct WonderCardMetadata` (`include/global.h:671`) →
  `mystery_gift.lua:278-290`. The engine stores it at
  `session.modData[MysteryGift.SAVE_KEY]` (`mystery_gift.lua:311,319,322`) and the
  schema passes `modData` straight through (`save_schema_firered.lua:253`,
  restore `:323`), so **the record persists with no new save-schema row** — the
  "save/read path" the triage hint suggests calling from is already this passthrough.
- **Why not (b) WIRE IT:** the only non-wireless writers are
  `cable_club.c:792,795` + `trade_scene.c:2609`, and they still sit behind
  `sStatsEnabled`, which only the Union Room sets. Calling `tryIncrementStat` from
  `src/link/battle.lua` / `src/link/trade.lua` today would be a permanent no-op,
  and to make it *do* anything I would also have to invent the Union Room
  enable/disarm sequence — inventing a caller, which the pret mandate forbids.
- **Why not (c) DEFER-TO-RSE:** the flow is not RS/e-reader specific — it is
  **wireless-adapter** specific and exists identically in Emerald
  (`union_room`/`mystery_gift_client` are shared Gen 3), so "RSE" is not the right
  drawer; the correct label is "adapter-only, unreachable".
- **Degradation (what happens today):** the seven functions are inert; the record
  keeps `cardMetadata = { battlesWon = 0, battlesLost = 0, numTrades = 0, ... }`
  (`mystery_gift.lua:279-286`), and the Mystery Gift menu renders those zeros
  (`src/ui/game3/mystery_gift.lua:668-670`). That matches pret for a machine with no
  wireless link: nothing can increment a counter whose enable flag only the Union
  Room can set. No nil derefs, no stale data, no save growth.
- **Coverage:** `tests/game3_gift_model_test.lua:155-169+` already pins
  `trySaveStamp` accept/refuse, `tryIncrementStat` dedup-by-trainer, and
  `tryEnableStatsByFlagId` gating; `tests/game3_gift_delivery_test.lua`,
  `game3_gift_menu_test.lua` cover the wired paths. No new tests needed for NO
  ACTION.
- **Reopen condition (design sketched, not needed now):** if an engine Union
  Room/adapter simulation ever lands, wire in one ticket — `tryEnableStatsByFlagId`
  at the room's pair exchange (mirroring `src/union_room.c:1777`),
  `disableStats` at activity start (`:1874`) and on 3+ players (`:1781`), then the
  increments at `src/link/battle.lua` (won/lost) and `src/link/trade.lua`
  (trades), matching `cable_club.c:792,795` and `trade_scene.c:2609`. Files:
  `union_room.lua`, `link/battle.lua`, `link/trade.lua` (Finisher) + a state flag
  in `mystery_gift.lua`. Effort: small. Blocked on that adapter simulation.
- **[pret-unverified]:** the exact enable/disable ordering inside
  `src/union_room.c` (whether `Task_StartActivity`'s `DisableStats` at `:1874`
  precedes or follows a re-enable for that activity) — settling file
  `src/union_room.c` state machine; immaterial to this verdict because both paths
  are wireless-only.
