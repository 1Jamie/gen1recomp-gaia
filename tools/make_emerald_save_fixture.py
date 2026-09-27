#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
DEFAULT_ROM = REPO.parent / "pokeemerald" / "pokeemerald.gba"
DEFAULT_SAV = REPO / ".claude" / "skills" / "pygba-headless" / "assets" / "pokemon-emerald-all-shiny-fixed.sav"
ROM_SHA1 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7"

KEYS = {"A": 0, "B": 1, "select": 2, "start": 3, "right": 4, "left": 5, "up": 6, "down": 7, "R": 8, "L": 9}

# pokeemerald/pokeemerald.map
SYM = {
    "gMain": 0x030022C0,
    "gSaveBlock1Ptr": 0x03005D8C,
    "gSaveBlock2Ptr": 0x03005D90,
    "gPokemonStoragePtr": 0x03005D94,
    "gSaveCounter": 0x03006200,
    "gPlayerParty": 0x020244EC,
    "gPlayerPartyCount": 0x020244E9,
    "gTasks": 0x03005E00,
    "sGlobalScriptContext": 0x03000E40,
    "sStartMenuCursorPos": 0x0203760E,
    "sNumStartMenuActions": 0x0203760F,
    "sCurrentStartMenuActions": 0x02037610,
    "CB2_Overworld": 0x08085E5C,
    "CB2_MainMenu": 0x0802F6B0,
    "CB2_NamingScreen": 0x080E4F58,
    "BattleMainCB2": 0x08038420,
    "gBattleTypeFlags": 0x02022FEC,
    "Task_HandleTruckSequence": 0x080FB36C,
    "Task_DisplayMainMenu": 0x0802FBA4,
}
MENU_ACTION_SAVE = 5
SB1_SIZE, SB2_SIZE, STORAGE_SIZE = 0x3D88, 0xF2C, 0x83D0


def lua_consts(kind):
    text = (REPO / "src/core/game3/constants/emerald" / (kind + ".lua")).read_text()
    out = {}
    for name, val in re.findall(r"\b([A-Z][A-Z0-9_]+) = (-?0x[0-9A-Fa-f]+|-?\d+),", text):
        out.setdefault(name, int(val, 0))
    return out


class Emu:
    def __init__(self, rom, save_bytes=None, video=False):
        import mgba.log
        mgba.log.silence()
        import mgba.core
        from mgba._pylib import ffi
        self.ffi = ffi
        self.dir = Path(tempfile.mkdtemp())
        path = self.dir / "rom.gba"
        path.write_bytes(Path(rom).read_bytes())
        self.sav = self.dir / "rom.sav"
        self.sav.write_bytes(save_bytes if save_bytes is not None else b"\xff" * 0x20000)
        self.core = mgba.core.load_path(str(path))
        self.fb = None
        if video:
            import mgba.image
            self.fb = mgba.image.Image(*self.core.desired_video_dimensions())
            self.core.set_video_buffer(self.fb)
        self.core.autoload_save()
        self.core.reset()
        self.frame = 0

    def run(self, n=1, keys=()):
        for k in keys:
            self.core.add_keys(KEYS[k])
        for _ in range(n):
            self.core.run_frame()
            self.frame += 1
        for k in keys:
            self.core.clear_keys(KEYS[k])

    def press(self, key, hold=2, after=6):
        self.run(hold, (key,))
        self.run(after)

    def region(self, addr):
        mc = self.core.memory.u8._core
        size = self.ffi.new("size_t *")
        ptr = self.ffi.cast("uint8_t *", mc.getMemoryBlock(mc, addr >> 24, size))
        return self.ffi.buffer(ptr, size[0])

    def read(self, addr, n):
        buf = self.region(addr)
        a = addr & (len(buf) - 1)
        return bytes(buf[a:a + n])

    def write(self, addr, data):
        buf = self.region(addr)
        a = addr & (len(buf) - 1)
        buf[a:a + len(data)] = data

    def u8(self, a):
        return self.read(a, 1)[0]

    def u32(self, a):
        return int.from_bytes(self.read(a, 4), "little")

    def cb2(self):
        return self.u32(SYM["gMain"] + 4) & ~1

    def tasks(self):
        out = []
        for i in range(16):
            b = self.read(SYM["gTasks"] + i * 40, 40)
            if b[4]:
                out.append(int.from_bytes(b[0:4], "little") & ~1)
        return out

    def blocks(self):
        sb1 = self.read(self.u32(SYM["gSaveBlock1Ptr"]), SB1_SIZE)
        sb2 = self.read(self.u32(SYM["gSaveBlock2Ptr"]), SB2_SIZE)
        st = self.read(self.u32(SYM["gPokemonStoragePtr"]), STORAGE_SIZE)
        return sb1, sb2, st

    def flash(self):
        self.run(120)
        data = self.sav.read_bytes()
        if not 0x20000 <= len(data) <= 0x2003F:
            raise SystemExit("flash file is %d bytes" % len(data))
        return data

    def shot(self, path):
        self.fb.to_pil().convert("RGB").save(path)

    def wait_cb2(self, target, limit, tap=None, every=30):
        for i in range(limit):
            if self.cb2() == target:
                return True
            if tap and i % every == 0:
                self.press(tap, 2, 0)
            else:
                self.run(1)
        return self.cb2() == target


def to_main_menu(e, limit=2000):
    return e.wait_cb2(SYM["CB2_MainMenu"], limit, tap="A", every=40)


def continue_game(e):
    if not to_main_menu(e):
        raise SystemExit("main menu not reached")
    e.run(90)
    if not e.wait_cb2(SYM["CB2_Overworld"], 1500, tap="A", every=40):
        raise SystemExit("overworld not reached after CONTINUE")
    e.run(240)


def new_game(e):
    for _ in range(9000):
        cb = e.cb2()
        if cb == SYM["CB2_NamingScreen"]:
            e.run(60)
            e.press("A", 2, 30)
            e.press("start", 2, 30)
            e.press("A", 2, 60)
            continue
        if cb == SYM["CB2_Overworld"]:
            break
        if e.frame % 30 == 0:
            e.press("A", 2, 0)
        else:
            e.run(1)
    if e.cb2() != SYM["CB2_Overworld"]:
        raise SystemExit("new game never reached the truck")
    for _ in range(6000):
        if SYM["Task_HandleTruckSequence"] not in e.tasks():
            break
        e.run(1)
    e.run(600)


def settle(e, limit=3000):
    quiet = 0
    for _ in range(limit):
        if e.u8(SYM["sGlobalScriptContext"] + 1) == 0 and e.cb2() == SYM["CB2_Overworld"]:
            quiet += 1
            if quiet >= 60:
                return True
            e.run(1)
        else:
            quiet = 0
            e.press("B", 2, 10)
    return False


def save_game(e):
    before = e.u32(SYM["gSaveCounter"])
    n = 0
    for _ in range(5):
        settle(e)
        e.press("start", 2, 40)
        n = e.u8(SYM["sNumStartMenuActions"])
        if n:
            break
        e.press("B", 2, 30)
    acts = list(e.read(SYM["sCurrentStartMenuActions"], n))
    if MENU_ACTION_SAVE not in acts:
        raise SystemExit("no SAVE in the start menu: %r" % acts)
    cur = e.u8(SYM["sStartMenuCursorPos"])
    for _ in range((acts.index(MENU_ACTION_SAVE) - cur) % n):
        e.press("down", 2, 8)
    e.press("A", 2, 10)
    snap = None
    for i in range(3000):
        if e.u32(SYM["gSaveCounter"]) != before:
            snap = e.blocks()
            break
        if i % 25 == 0:
            e.press("A", 2, 0)
        else:
            e.run(1)
    if snap is None:
        raise SystemExit("the save never completed")
    e.run(90)
    for _ in range(4):
        e.press("B", 2, 20)
    e.run(120)
    return snap


def walk_into_battle(e, steps=3000, seed=7):
    import random
    rng = random.Random(seed)
    d = "left"
    for i in range(steps):
        if rng.random() < 0.3:
            d = rng.choice(["left", "right", "up", "down"])
        e.run(16, (d,))
        if e.cb2() != SYM["CB2_Overworld"]:
            return e.wait_cb2(SYM["BattleMainCB2"], 1200)
        if i % 10 == 0:
            e.press("B", 2, 4)
    return False


def finish_battle(e):
    trainer = e.u32(SYM["gBattleTypeFlags"]) & 8
    for _ in range(200):
        if e.cb2() == SYM["CB2_Overworld"]:
            break
        if trainer:
            e.press("A", 2, 20)
        else:
            e.run(60)
            e.press("right", 2, 6)
            e.press("down", 2, 6)
            e.press("A", 2, 30)
            e.press("B", 2, 20)
    if not e.wait_cb2(SYM["CB2_Overworld"], 4000, tap="B", every=30):
        raise SystemExit("still in battle")
    e.run(300)


def u16(b, o):
    return int.from_bytes(b[o:o + 2], "little")


def u32(b, o):
    return int.from_bytes(b[o:o + 4], "little")


def s16(b, o):
    v = u16(b, o)
    return v - 65536 if v >= 32768 else v


def s8(b, o):
    return b[o] - 256 if b[o] >= 128 else b[o]


# pokeemerald/src/pokemon.c:2863
ORDER = [
    (0, 1, 2, 3), (0, 1, 3, 2), (0, 2, 1, 3), (0, 3, 1, 2), (0, 2, 3, 1), (0, 3, 2, 1),
    (1, 0, 2, 3), (1, 0, 3, 2), (2, 0, 1, 3), (3, 0, 1, 2), (2, 0, 3, 1), (3, 0, 2, 1),
    (1, 2, 0, 3), (1, 3, 0, 2), (2, 1, 0, 3), (3, 1, 0, 2), (2, 3, 0, 1), (3, 2, 0, 1),
    (1, 2, 3, 0), (1, 3, 2, 0), (2, 1, 3, 0), (3, 1, 2, 0), (2, 3, 1, 0), (3, 2, 1, 0),
]


def box_mon(raw):
    if not any(raw):
        return None
    pid, otid = u32(raw, 0), u32(raw, 4)
    key = pid ^ otid
    sec = b"".join((u32(raw, 32 + i * 4) ^ key).to_bytes(4, "little") for i in range(12))
    g = ORDER[pid % 24][0] * 12
    a = ORDER[pid % 24][1] * 12
    m = ORDER[pid % 24][3] * 12
    return {
        "pid": pid, "otid": otid, "species": u16(sec, g), "heldItem": u16(sec, g + 2), "exp": u32(sec, g + 4),
        "moves": [u16(sec, a + i * 2) for i in range(4)], "ivWord": u32(sec, m + 4), "ribbons": u32(sec, m + 8),
        "nickRaw": raw[8:18].hex(), "otRaw": raw[20:27].hex(), "flags": raw[19],
    }


def items(b, off, count, key):
    out = []
    for i in range(count):
        iid, q = u16(b, off + i * 4), u16(b, off + i * 4 + 2)
        if key is not None:
            q ^= key & 0xFFFF
        if iid:
            out.append([iid, q])
    return out


def bitlist(b, off, n):
    return [i for i in range(n * 8) if b[off + i // 8] >> (i % 8) & 1]


def time_of(b, o):
    return [s16(b, o), s8(b, o + 2), s8(b, o + 3), s8(b, o + 4)]


def oracle(sb1, sb2, st):
    key = u32(sb2, 0xAC)
    party = []
    for i in range(min(sb1[0x234], 6)):
        o = 0x238 + i * 100
        mon = box_mon(sb1[o:o + 80])
        mon.update({"level": sb1[o + 84], "hp": u16(sb1, o + 86), "maxHp": u16(sb1, o + 88), "mail": sb1[o + 85]})
        party.append(mon)
    boxes = 0
    firstbox = None
    for i in range(14 * 30):
        raw = st[4 + i * 80:4 + i * 80 + 80]
        if any(raw) and raw[19] & 2:
            boxes += 1
            if firstbox is None:
                firstbox = dict(box_mon(raw), slot=i)
    trees = {}
    for i in range(128):
        t = sb1[0x169C + i * 8:0x169C + i * 8 + 8]
        if any(t):
            trees[i] = [t[0], t[1] & 0x7F, u16(t, 2), t[4]]
    blocks = [list(sb1[0x848 + i * 8:0x848 + i * 8 + 7]) for i in range(40) if any(sb1[0x848 + i * 8:0x848 + i * 8 + 8])]
    stats = {}
    for i in range(64):
        v = u32(sb1, 0x159C + i * 4) ^ key
        if v:
            stats[i] = v
    rv = {}
    for i in range(256):
        v = u16(sb1, 0x139C + i * 2)
        if v:
            rv[0x4000 + i] = v
    dc = 0x3030
    return {
        "nameRaw": sb2[0:8].hex(), "gender": sb2[8], "tid": u16(sb2, 10), "sid": u16(sb2, 12),
        "playTime": [u16(sb2, 14), sb2[16], sb2[17]], "key": key, "warpFlags": sb2[9],
        "options": u16(sb2, 0x14), "buttonMode": sb2[0x13], "nationalMagic": sb2[0x1A],
        "money": u32(sb1, 0x490) ^ key, "coins": (u16(sb1, 0x494) ^ key) & 0xFFFF, "berryPowder": u32(sb2, 0x1F4) ^ key,
        "registeredItem": u16(sb1, 0x496),
        "pos": [s16(sb1, 0), s16(sb1, 2)], "location": [s8(sb1, 4), s8(sb1, 5), s8(sb1, 6), s16(sb1, 8), s16(sb1, 10)],
        "heal": [s8(sb1, 0x1C), s8(sb1, 0x1D), s8(sb1, 0x1E), s16(sb1, 0x20), s16(sb1, 0x22)],
        "weather": sb1[0x2E], "weatherCycleStage": sb1[0x2F],
        "party": party, "boxCount": boxes, "firstBoxMon": firstbox, "currentBox": st[0],
        "pockets": {
            "ITEMS": items(sb1, 0x560, 30, key), "KEY_ITEMS": items(sb1, 0x5D8, 30, key),
            "POKE_BALLS": items(sb1, 0x650, 16, key), "TM_CASE": items(sb1, 0x690, 64, key),
            "BERRY_POUCH": items(sb1, 0x790, 46, key),
        },
        "pcItems": items(sb1, 0x498, 50, None),
        "flags": bitlist(sb1, 0x1270, 300), "vars": rv, "gameStats": stats,
        "dexOwned": bitlist(sb2, 0x28, 52), "dexSeen": bitlist(sb2, 0x5C, 52),
        "daycare": {"offspringPersonality": u32(sb1, dc + 0x118), "stepCounter": sb1[dc + 0x11C],
                    "species": [(box_mon(sb1[dc + i * 0x8C:dc + i * 0x8C + 80]) or {}).get("species", 0) for i in range(2)],
                    "steps": [u32(sb1, dc + i * 0x8C + 0x88) for i in range(2)]},
        "berryTrees": trees, "pokeblocks": blocks,
        "localTimeOffset": time_of(sb2, 0x98), "lastBerryTreeUpdate": time_of(sb2, 0xA0),
        "roamer": {"species": u16(sb1, 0x31DC + 8), "level": sb1[0x31DC + 12], "active": sb1[0x31DC + 19],
                   "personality": u32(sb1, 0x31DC + 4), "ivs": u32(sb1, 0x31DC)},
        "mailItems": [u16(sb1, 0x2BE0 + i * 36 + 0x20) for i in range(16)],
        "trainerRematchStepCounter": u16(sb1, 0x9C8),
        "rematches": {i: sb1[0x9CA + i] for i in range(100) if sb1[0x9CA + i]},
        "secretBaseId": sb1[0x1A9C], "giftRibbons": list(sb1[0x31A8:0x31A8 + 11]),
        "decorInventory": list(sb1[0x2734:0x2734 + 150]), "playerRoomDecorations": list(sb1[0x271C:0x271C + 12]),
        "outbreakSpecies": u16(sb1, 0x2B90), "dewfordWords": [u16(sb1, 0x2E68 + i * 8 + 4) for i in range(5)],
        "linkRecord0": sb1[0x3150:0x3150 + 16].hex(), "contestWinnerSpecies": [u16(sb1, 0x2E90 + i * 32 + 8) for i in range(13)],
        "battlePoints": u16(sb2, 0x64C + 0x86C),
    }


def rle(data):
    out, i, n = [], 0, len(data)
    while i < n:
        b = data[i]
        if b in (0, 0xFF):
            j = i
            while j < n and data[j] == b:
                j += 1
            if j - i >= 6:
                out.append(("Z" if b == 0 else "F") + "%x" % (j - i))
                i = j
                continue
        j = i
        while j < n:
            if data[j] in (0, 0xFF):
                k = j
                while k < n and data[k] == data[j]:
                    k += 1
                if k - j >= 6:
                    break
                j = k
            else:
                j += 1
        out.append(data[i:j].hex())
        i = j
    return " ".join(out)


def lua(v, ind=""):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        if all(isinstance(x, (int, bool)) or x is None for x in v):
            return "{ " + ", ".join(lua(x) for x in v) + " }"
        inner = ind + "  "
        return "{\n" + "".join(inner + lua(x, inner) + ",\n" for x in v) + ind + "}"
    if isinstance(v, dict):
        inner = ind + "  "
        parts = []
        for k in sorted(v, key=lambda x: (isinstance(x, str), x)):
            key = ("[%d]" % k) if isinstance(k, int) else (k if re.match(r"^[A-Za-z_]\w*$", k) else "[%s]" % json.dumps(k))
            parts.append(inner + key + " = " + lua(v[k], inner) + ",\n")
        return "{\n" + "".join(parts) + ind + "}"
    raise TypeError(type(v))


def doctor(e, C, donor):
    sb1a, sb2a = e.u32(SYM["gSaveBlock1Ptr"]), e.u32(SYM["gSaveBlock2Ptr"])
    sb1, sb2, _ = e.blocks()
    key = u32(sb2, 0xAC)

    # pokeemerald/src/load_save.c:286
    def rekey32(block, base, off):
        e.write(base + off, (u32(block, off) ^ key).to_bytes(4, "little"))

    rekey32(sb1, sb1a, 0x490)
    e.write(sb1a + 0x494, ((u16(sb1, 0x494) ^ key) & 0xFFFF).to_bytes(2, "little"))
    for i in range(64):
        rekey32(sb1, sb1a, 0x159C + i * 4)
    rekey32(sb2, sb2a, 0x1F4)
    for off, cnt in ((0x560, 30), (0x5D8, 30), (0x650, 16), (0x690, 64), (0x790, 46)):
        for i in range(cnt):
            o = off + i * 4 + 2
            e.write(sb1a + o, ((u16(sb1, o) ^ key) & 0xFFFF).to_bytes(2, "little"))
    e.write(sb2a + 0xAC, b"\0\0\0\0")
    e.write(SYM["gPlayerParty"], donor)
    e.write(SYM["gPlayerPartyCount"], bytes([1]))
    potion = C["items"]["ITEM_POTION"]
    for i in range(50):
        e.write(sb1a + 0x498 + i * 4, potion.to_bytes(2, "little") + (i + 1).to_bytes(2, "little"))
    dc = 0x3030
    e.write(sb1a + dc, donor[:80])
    e.write(sb1a + dc + 0x88, (4321).to_bytes(4, "little"))
    e.write(sb1a + dc + 0x118, (0xDEADBEEF).to_bytes(4, "little"))
    e.write(sb1a + dc + 0x11C, bytes([77]))
    e.write(sb1a + 0x169C + 7 * 8, bytes([5, 3, 0x2C, 0x01, 4, 0x12, 0, 0]))
    e.write(sb1a + 0x848, bytes([1, 20, 0, 5, 0, 0, 10, 0]))
    flags = sb1[0x1270 + 0x950 // 8] | (1 << (0x950 % 8))
    e.write(sb1a + 0x1270 + 0x950 // 8, bytes([flags]))
    e.write(sb1a + 0x139C + 0xFF * 2, (1234).to_bytes(2, "little"))
    e.write(sb1a + 0x9C8, (123).to_bytes(2, "little"))
    e.write(sb1a + 0x9CA + 3, bytes([2]))
    e.write(sb1a + 0x31A8, bytes([1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 5]))
    e.write(sb2a + 0x98, (-2 & 0xFFFF).to_bytes(2, "little") + bytes([5, 30, 7]))
    mail = 0x2BE0 + 6 * 36
    e.write(sb1a + mail, b"".join(w.to_bytes(2, "little") for w in (0x0A0B, 0x0402, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF)))
    e.write(sb1a + mail + 0x12, bytes([0xCC, 0xC3, 0xD0, 0xBB, 0xC6, 0x00, 0xFF, 0xFF]))
    e.write(sb1a + mail + 0x1A, (0x12345678).to_bytes(4, "little") + (25).to_bytes(2, "little") + (121).to_bytes(2, "little"))
    e.write(sb1a + 0x3150, bytes([0xCC, 0xC3, 0xD0, 0xBB, 0xC6, 0xFF, 0, 0]) + (4242).to_bytes(2, "little")
            + (3).to_bytes(2, "little") + (1).to_bytes(2, "little") + (0).to_bytes(2, "little"))
    e.write(sb1a + 0x31DC, (0x3FFFFFFF).to_bytes(4, "little") + (0xCAFEBABE).to_bytes(4, "little")
            + (C["species"]["SPECIES_LATIOS"]).to_bytes(2, "little") + (100).to_bytes(2, "little")
            + bytes([40, 0, 1, 2, 3, 4, 5, 1]))


def capture(rom, bundled):
    C = {"items": lua_consts("items"), "flags": lua_consts("flags"), "species": lua_consts("species")}
    out = {"images": {}, "oracle": {}, "meta": {}}
    bundled_bytes = Path(bundled).read_bytes()

    e = Emu(rom, bundled_bytes)
    continue_game(e)
    shiny = e.blocks()
    donor = e.read(SYM["gPlayerParty"], 100)
    out["oracle"]["em_shiny"] = oracle(*shiny)
    out["meta"]["em_shiny"] = {"sha1": hashlib.sha1(bundled_bytes).hexdigest(), "size": len(bundled_bytes),
                               "ramAfterContinue": True, "olderSlotOf": "em_battle"}

    e = Emu(rom, bundled_bytes)
    continue_game(e)
    if not walk_into_battle(e):
        raise SystemExit("no wild battle on the bundled save's route")
    finish_battle(e)
    snap = save_game(e)
    out["images"]["em_battle"] = e.flash()
    out["oracle"]["em_battle"] = oracle(*snap)

    e = Emu(rom, None)
    new_game(e)
    snap = save_game(e)
    fresh = e.flash()
    out["images"]["em_fresh"] = fresh
    out["oracle"]["em_fresh"] = oracle(*snap)

    e = Emu(rom, fresh[:0x20000])
    continue_game(e)
    doctor(e, C, donor)
    snap = save_game(e)
    out["images"]["em_doctored"] = e.flash()
    out["oracle"]["em_doctored"] = oracle(*snap)

    for name, img in out["images"].items():
        out["meta"][name] = {"sha1": hashlib.sha1(img).hexdigest(), "size": len(img), "ramAfterContinue": False}
    return out


def write_fixture(data, path):
    lines = ["-- tools/make_emerald_save_fixture.py (PyGBA, pokeemerald.gba sha1 " + ROM_SHA1 + ")", "return {", "  images = {"]
    for name in sorted(data["images"]):
        lines.append("    %s = %s," % (name, json.dumps(rle(data["images"][name]))))
    lines.append("  },")
    lines.append("  meta = " + lua(data["meta"], "  ") + ",")
    lines.append("  oracle = " + lua(data["oracle"], "  ") + ",")
    lines.append("}")
    Path(path).write_text("\n".join(lines) + "\n")


def continue_check(rom, sav, shot):
    C = lua_consts("flags")
    e = Emu(rom, Path(sav).read_bytes(), video=True)
    if not to_main_menu(e):
        raise SystemExit("main menu not reached")
    e.run(150)
    if shot:
        e.shot(shot)
    sb1, sb2, _ = e.blocks()
    badges = [i + 1 for i in range(8) if (lambda f: sb1[0x1270 + f // 8] >> (f % 8) & 1)(C["FLAG_BADGE0%d_GET" % (i + 1)])]
    info = {"name": sb2[0:8].hex(), "playTime": [u16(sb2, 14), sb2[16], sb2[17]], "badges": badges,
            "dexOwned": len(bitlist(sb2, 0x28, 52)), "tid": u16(sb2, 10)}
    continue_game_from_menu(e)
    sb1, sb2, _ = e.blocks()
    info["overworld"] = {"location": [s8(sb1, 4), s8(sb1, 5)], "pos": [s16(sb1, 0), s16(sb1, 2)], "party": sb1[0x234]}
    if shot:
        e.shot(shot.replace(".png", "_field.png"))
    print(json.dumps(info))


def continue_game_from_menu(e):
    if not e.wait_cb2(SYM["CB2_Overworld"], 1500, tap="A", every=40):
        raise SystemExit("overworld not reached after CONTINUE")
    e.run(240)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["fixtures", "continue"])
    p.add_argument("sav", nargs="?")
    p.add_argument("--rom", default=str(DEFAULT_ROM))
    p.add_argument("--bundled", default=str(DEFAULT_SAV))
    p.add_argument("--out", default=str(REPO / "tests/fixture_data/gen3_saves_emerald.lua"))
    p.add_argument("--shot")
    a = p.parse_args()
    if hashlib.sha1(Path(a.rom).read_bytes()).hexdigest() != ROM_SHA1:
        raise SystemExit("not the byte-exact pokeemerald.gba")
    if a.mode == "fixtures":
        write_fixture(capture(a.rom, a.bundled), a.out)
        print("wrote", a.out)
    else:
        continue_check(a.rom, a.sav, a.shot)


if __name__ == "__main__":
    main()
