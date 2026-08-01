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

# T16 — Joy-Con launcher + gameplay — pass (naming re-verify)

### Round 1 @ `7504753` — partial

| Check | Result |
| ----- | ------ |
| Launcher / overworld (Joy-Con only) | **pass** |
| Naming player/rival | **fail** (dual-path a+b; see below) |
| Touch required | **no** |
| `game.love` SHA-256 | `bd3a35461bf453c1f0465a5a289421aef3b5c72d3bf1f8d76e86231256829e0e` |

### Naming failure (root cause) — fixed in `efd81d8` + `2699c9a`

- love-nx fires **`gamepadpressed` + `joystickpressed` on the same physical press**.
- `NamingScreen` tested `wasPressed("b")` before `"a"` → if both true in one frame, always deletes.
- Dual-path fix: ignore raw when `isGamepad()` (`efd81d8`).
- SDL-only UX then had physical B confirm / A erase; NX face remap (`2699c9a`) restores Nintendo A=confirm / B=cancel.

### Round 2 @ `2699c9a` — pass (Nintendo UX)

| Field | Value |
| ----- | ----- |
| Commit tested | `2699c9a` |
| `game.love` SHA-256 | `a208b21e1f30b00e2e8c6fa6efe14f0e06d1db0ae1e50b810b16d9fb852926bc` |
| Touch required | **no** |

| Check | Result |
| ----- | ------ |
| Naming — player | **pass** — physical **A** confirms letter, **B** cancels/erases |
| Naming — rival | **pass** (same) |
| Launcher / overworld (prior round) | **pass** (unchanged mapping for d-pad/stick) |

T16 hardware gate: **closed**.

---

## T19 — save / suspend — pass

| Check | Result |
| ----- | ------ |
| Save in-game → full quit → title-override reopen → load save | **pass** (@ `7504753` / retained) |
| Suspend/resume ×10 (launcher / gameplay / mixed) | **pass** (operator 2026-08-01) |
| Full console reboot persistence | **pass** (operator 2026-08-01) |

T19 hardware gate: **closed**. No stuck input, duplicate audio, or crash reported.

---

## T24 — fused NRO alone + NRO-only update — **pass**

| Field | Value |
| ----- | ----- |
| First fused attempt | `6fb5602` (Blue Play failed — mount) |
| Fix commits | `b1ad7c7` (logs/generated overlay), `ac6dfe7` (Blue/Yellow mount) |
| Deploy | isolated folder, no adjacent `game.love` |
| Boot fused | **pass** |
| ROM import | **pass** |
| Play **Red** | **pass** |
| Play **Blue** (after `ac6dfe7`) | **pass** (operator 2026-08-01) |
| NRO-only replace | **pass** — saves retained; app still boots/plays |
| Touch required | no |

T24 hardware gate: **closed**.

---

## NXMOD-12 — VoxelMod OLED smoke (scaffold)

Operator fills results after software gates. **Do not commit** DramaticShape (or any) mod `.zip` bytes — transfer via MTP into `imports/mods/` only.

| Field | Value (operator) |
| ----- | ---------------- |
| Status | **pending** |
| gen1recomp commit | |
| love-nx tag | `11.5-nx1` (or pin used) |
| Console | Switch OLED |
| Mod id | |
| Mod version | |
| Zip source URL | https://github.com/DramaticShape/DramaticShapeVoxelMod/releases |
| Zip committed to git? | **no** (must remain no) |

### Checklist

| Step | Pass / fail / pending | Notes |
| ---- | --------------------- | ----- |
| MTP zip into save `imports/mods/` | pending | |
| MODS → Procurar novamente → mod listed | pending | |
| Enable mod + Play Red boots without crash | pending | |
| Overworld Select+A → visible colors/settings change | pending | |
| Overworld Select+B → visible tilt/perspective change | pending | |

### Evidence notes

```text
Operator:
Date:
Commit tested:
game.love / NRO SHA-256 (optional):
Pass / fail summary:
```
