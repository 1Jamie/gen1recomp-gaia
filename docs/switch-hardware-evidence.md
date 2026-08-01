# Switch hardware evidence (Phase 0 + import + input)

**love-nx:** `11.5-nx1`  
**Console:** Switch OLED  
**Operator:** Andrew  
**Date:** 2026-08-01  

Do **not** commit ROM dumps or private dump hashes.

---

## Phase 0 — probe (T4) — pass

| Field | Value |
| ----- | ----- |
| Commit (import era) | `df7cea4` |
| `getOS()` / `love._os` | `NX` |
| Dimensions | 1280×720 |
| Save (probe) | `sdmc:/switch/gen1recomp/switch-probe` |
| Joy-Con | `joystickpressed` + `gamepadpressed` (Y→`#3`, X→`#4`) |

| Artifact | SHA-256 |
| -------- | ------- |
| `gen1recomp.nro` | `8290ac153d4c630e48c9b26ef9123f5204ed8ee0cef3042511707b5b645918f5` |

---

## T12 — Red import + Play — pass

Inbox MTP → “Procurar novamente” → Play; Joy-Con launcher/gameplay (not touch-only).

---

## T16 — Joy-Con launcher + gameplay — partial (naming fail)

| Field | Value |
| ----- | ----- |
| Commit tested | `7504753` |
| `game.love` SHA-256 | `bd3a35461bf453c1f0465a5a289421aef3b5c72d3bf1f8d76e86231256829e0e` |
| Touch required | **no** |

| Check | Result |
| ----- | ------ |
| Launcher (Joy-Con only, virtual cursor) | **pass** |
| Overworld walk / interact | **pass** |
| Naming — player | **fail** |
| Naming — rival | **fail** (same behavior) |

### Naming failure (root cause)

- love-nx fires **`gamepadpressed` + `joystickpressed` on the same physical press**.
- `NamingScreen` tested `wasPressed("b")` before `"a"` → if both true in one frame, always deletes.
- Y appeared to “work” because face `y`/`x` are absent from `DEFAULT_GAMEPAD_BINDINGS`, so only raw applied (no a+b collision).
- Observed: **Y places letter**; **X, A, and B erase**.

### UX note (SDL gamepad-only)

With LÖVE/SDL mapping only: physical **B** (south) → GB A (confirm); physical **A** (east) → GB B (erase). Explicit NX remap needed if physical A should confirm like retail Nintendo UX.

### Follow-up fix (software)

Skip raw face/menu when `joystick:isGamepad()`; align NX raw Y→a / X→b; prefer A over B in naming when both edges fire.

---

## T19 — save / suspend — partial

| Check | Result |
| ----- | ------ |
| Save in-game → full quit → title-override reopen → load save | **pass** |
| Suspend/resume ×10 | **not tested** |
| Full console reboot persistence | **not tested** |

T19 remains open until suspend×10 (and ideally reboot) are recorded.
