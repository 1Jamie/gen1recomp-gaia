#!/usr/bin/env python3
import argparse
import bisect
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

HELP = """Headless Game Boy Color boot-to-CONTINUE harness for Gen 2 battery saves.

Boots a Gold / Silver / Crystal ROM in mGBA (GB core, python bindings, no window),
mashes through the intro and title with START, selects CONTINUE, confirms the
PLAYER / BADGES / POKeDEX / TIME panel, waits for the overworld loop, then reads
live memory using label addresses from the ROM's pret .sym file.

Run it with the pygba-headless venv interpreter:

  ~/.local/share/pygba-headless/venv/bin/python gb_boot.py \\
      --rom ../pokecrystal/pokecrystal.gbc --sav my.sav --out /tmp/run1 \\
      [--sym ROM.sym] [--frames 6000] [--dump-json /tmp/run1.json]

Inputs are never modified: ROM and save are copied into --out (mGBA writes the
battery file next to the ROM copy). Outputs in --out:

  input.sav            pristine copy of --sav
  game.gbc/game.sav    working copies (game.sav is what mGBA flushed)
  after.sav            first 32 KiB of the emulated SRAM at the end of the run
  menu.png             title menu (CONTINUE / NEW GAME ...)
  continue_panel.png   PLAYER / BADGES / POKeDEX / TIME panel
  corrupted.png        only when the game printed 'The save file is corrupted'
  overworld.png        overworld after the map loop is running
  result.json          everything below (also written to --dump-json)

overworld_blank is set when the map loop runs but the screen is one tile or
one colour (a save whose map state the game cannot draw).

result.json keys: menu_has_continue, save_file_exists (wSaveFileExists after
the title menu came up), corrupted, panel_seen, overworld, static checksum
verdicts (primary_ok, backup_ok, check values), screens (every distinct text
screen seen, decoded from wTilemap), and memory: player name/id/money/badges,
party (species/level/hp/moves/pp/status/item/happiness), wCurBox, wBoxNames,
map group/number/x/y, current box count and species read from SRAM sBox, and
each archived box count sBox1..sBox14.

Verdict: exit status 0 when the overworld loaded, 1 when CONTINUE was missing,
the game reported corruption, or the overworld never came up, 2 on usage or
emulator errors.
"""

KEY = {"A": 0, "B": 1, "SELECT": 2, "START": 3, "RIGHT": 4, "LEFT": 5, "UP": 6, "DOWN": 7}

CHARS = {0x7F: " ", 0x9A: "(", 0x9B: ")", 0x9C: ":", 0x9D: ";", 0x9E: "[", 0x9F: "]",
         0xE0: "'", 0xE1: "PK", 0xE2: "MN", 0xE3: "-", 0xE6: "?", 0xE7: "!", 0xE8: ".",
         0xE9: "&", 0xEA: "e", 0xEF: "M", 0xF0: "Y", 0xF1: "x", 0xF3: "/", 0xF4: ",",
         0xF5: "F", 0xED: ">", 0xEE: "v", 0x54: "POKe", 0x4F: " ", 0x51: " ", 0x55: " ", 0x57: " "}
for _i in range(26):
    CHARS[0x80 + _i] = chr(65 + _i)
    CHARS[0xA0 + _i] = chr(97 + _i)
for _i in range(10):
    CHARS[0xF6 + _i] = chr(48 + _i)

SRAM_SIZE = 0x8000


def decode(data, stop=True):
    out = []
    for b in data:
        if b == 0x50 and stop:
            break
        out.append(CHARS.get(b, "."))
    return "".join(out)


def load_sym(path):
    sym = {}
    for line in Path(path).read_text(errors="replace").splitlines():
        parts = line.split(";")[0].split()
        if len(parts) != 2 or ":" not in parts[0]:
            continue
        bank, addr = parts[0].split(":")
        try:
            sym.setdefault(parts[1], (int(bank, 16), int(addr, 16)))
        except ValueError:
            pass
    return sym


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sram_off(sym, name):
    bank, addr = sym[name]
    return bank * 0x2000 + (addr - 0xA000)


def checksum(data):
    return sum(data) & 0xFFFF


def static_checks(sym, raw):
    sram = raw[:SRAM_SIZE].ljust(SRAM_SIZE, b"\0")
    r = {"size": len(raw)}

    def u16(name):
        o = sram_off(sym, name)
        return sram[o] | (sram[o + 1] << 8)

    def wlen(a, b):
        return sym[b][1] - sym[a][1]

    r["check_value_1"] = sram[sram_off(sym, "sCheckValue1")]
    r["check_value_2"] = sram[sram_off(sym, "sCheckValue2")]
    r["backup_check_value_1"] = sram[sram_off(sym, "sBackupCheckValue1")]
    r["backup_check_value_2"] = sram[sram_off(sym, "sBackupCheckValue2")]
    a, b = sram_off(sym, "sGameData"), sram_off(sym, "sGameDataEnd")
    r["primary_sum"] = checksum(sram[a:b])
    r["primary_stored"] = u16("sChecksum")
    if "sBackupGameData" in sym:
        a, b = sram_off(sym, "sBackupGameData"), sram_off(sym, "sBackupGameDataEnd")
        r["backup_sum"] = checksum(sram[a:b])
    else:
        total = 0
        for s, w0, w1 in (("sBackupPokemonData", "wPokemonData", "wPokemonDataEnd"),
                          ("sBackupPlayerData3", "wPlayerData3", "wPlayerData3End"),
                          ("sBackupPlayerData1", "wPlayerData1", "wPlayerData1End"),
                          ("sBackupPlayerData2", "wPlayerData2", "wPlayerData2End"),
                          ("sBackupCurMapData", "wCurMapData", "wCurMapDataEnd")):
            o = sram_off(sym, s)
            total += checksum(sram[o:o + wlen(w0, w1)])
        r["backup_sum"] = total & 0xFFFF
    r["backup_stored"] = u16("sBackupChecksum")
    r["primary_ok"] = r["primary_sum"] == r["primary_stored"] and r["check_value_1"] == 99 and r["check_value_2"] == 127
    r["backup_ok"] = r["backup_sum"] == r["backup_stored"] and r["backup_check_value_1"] == 99 and r["backup_check_value_2"] == 127
    r["expected_load"] = "primary" if r["primary_ok"] else ("backup" if r["backup_ok"] else "corrupted")
    return r


class Runner:
    def __init__(self, rom, sav, sym, out):
        import mgba.core
        import mgba.image
        import mgba.log
        from mgba._pylib import ffi, lib
        self.lib = lib
        mgba.log.silence()
        self.ffi = ffi
        self.sym = sym
        self.out = out
        self.core = mgba.core.load_path(str(rom))
        if not self.core:
            raise RuntimeError("mGBA could not load the ROM")
        self.has_save = sav is not None
        if self.has_save and not self.core.autoload_save():
            raise RuntimeError("mGBA could not attach the save next to the ROM copy")
        w, h = self.core.desired_video_dimensions()
        self.fb = mgba.image.Image(w, h)
        self.core.set_video_buffer(self.fb)
        self.core.reset()
        self.frame = 0
        self.screens = []
        self.trace_every = 0

    def step(self, n=1, keys=()):
        for _ in range(n):
            self.core.set_keys(*(KEY[k] for k in keys))
            self.core.run_frame()
            self.frame += 1
            if self.trace_every and self.frame % self.trace_every == 0:
                self.shot("trace/f%06d.png" % self.frame)
        self.core.set_keys()

    def tap(self, key, hold=4, after=8):
        self.step(hold, (key,))
        self.step(after)

    def rd(self, name, off=0):
        bank, addr = self.sym[name]
        addr += off
        seg = bank if 0xD000 <= addr < 0xE000 else -1
        return self.core.memory.u8.raw_read(addr, seg)

    def rds(self, name, n, off=0):
        return bytes(self.rd(name, off + i) for i in range(n))

    def screen(self):
        raw = self.rds("wTilemap", 360)
        return [decode(raw[r * 20:(r + 1) * 20], stop=False) for r in range(18)]

    def screen_text(self):
        return "\n".join(self.screen())

    def log_screen(self, tag):
        lines = self.screen()
        text = "\n".join(lines)
        if not self.screens or self.screens[-1]["text"] != text:
            self.screens.append({"frame": self.frame, "tag": tag, "text": text})
        return text

    def shot(self, name):
        path = self.out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        self.fb.to_pil().convert("RGB").crop((0, 0, 160, 144)).save(path)
        return str(path)

    def sram(self):
        buf = self.ffi.new("void**")
        size = self.core._core.savedataClone(self.core._core, buf)
        if not size:
            return b""
        data = bytes(self.ffi.buffer(self.ffi.cast("uint8_t*", buf[0]), size))
        self.lib.free(buf[0])
        return data


def has(text, *words):
    flat = text.replace("\n", "")
    return any(w in flat for w in words)


def read_memory(r, sram):
    s = r.sym
    m = {}
    m["player_name"] = decode(r.rds("wPlayerName", 11))
    m["player_name_raw"] = r.rds("wPlayerName", 11).hex()
    m["player_id"] = (r.rd("wPlayerID") << 8) | r.rd("wPlayerID", 1)
    mb = r.rds("wMoney", 3)
    m["money"] = (mb[0] << 16) | (mb[1] << 8) | mb[2]
    m["johto_badges"] = r.rd("wJohtoBadges")
    m["kanto_badges"] = r.rd("wKantoBadges")
    m["badges"] = bin(m["johto_badges"]).count("1") + bin(m["kanto_badges"]).count("1")
    if "wPlayerGender" in s:
        m["player_gender"] = r.rd("wPlayerGender")
    m["game_time"] = {"hours": (r.rd("wGameTimeHours") << 8) | r.rd("wGameTimeHours", 1),
                      "minutes": r.rd("wGameTimeMinutes")}
    count = r.rd("wPartyCount")
    m["party_count"] = count
    m["party_species_list"] = list(r.rds("wPartySpecies", 7))
    base = s["wPartyMon1"][1]
    size = s["wPartyMon2"][1] - base

    def off(label):
        return s["wPartyMon1" + label][1] - base

    mons = []
    for i in range(min(count, 6)):
        o = i * size
        b = lambda label, n=1: r.rds("wPartyMon1", n, o + off(label))
        mons.append({
            "slot": i + 1,
            "species": b("Species")[0],
            "item": b("Item")[0],
            "moves": list(b("Moves", 4)),
            "pp": list(b("PP", 4)),
            "happiness": b("Happiness")[0],
            "level": b("Level")[0],
            "status": b("Status")[0],
            "hp": int.from_bytes(b("HP", 2), "big"),
            "max_hp": int.from_bytes(b("MaxHP", 2), "big"),
            "raw": r.rds("wPartyMon1", size, o).hex(),
        })
    m["party"] = mons
    m["cur_box"] = r.rd("wCurBox")
    names = r.rds("wBoxNames", 14 * 9)
    m["box_names"] = [decode(names[i * 9:(i + 1) * 9]) for i in range(14)]
    m["map_group"] = r.rd("wMapGroup")
    m["map_number"] = r.rd("wMapNumber")
    m["x"] = r.rd("wXCoord")
    m["y"] = r.rd("wYCoord")
    m["map_status"] = r.rd("wMapStatus")
    if len(sram) >= SRAM_SIZE:
        o = sram_off(s, "sBoxCount")
        bc = sram[o]
        m["sram_cur_box_count"] = bc
        so = sram_off(s, "sBoxSpecies")
        m["sram_cur_box_species"] = list(sram[so:so + min(bc, 20)])
        m["sram_box_counts"] = [sram[sram_off(s, "sBox%d" % n)] for n in range(1, 15)]
    return m


def run(a):
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    rom_copy = out / "game.gbc"
    sav_copy = out / "game.sav"
    shutil.copyfile(a.rom, rom_copy)
    if sav_copy.exists():
        sav_copy.unlink()
    raw = Path(a.sav).read_bytes()
    shutil.copyfile(a.sav, out / "input.sav")
    shutil.copyfile(a.sav, sav_copy)
    sym_path = Path(a.sym) if a.sym else Path(a.rom).with_suffix(".sym")
    sym = load_sym(sym_path)
    res = {"rom": str(Path(a.rom).resolve()), "rom_sha256": sha(a.rom), "sav": str(Path(a.sav).resolve()),
           "sav_sha256": sha(a.sav), "sav_size": len(raw), "sym": str(sym_path), "out": str(out.resolve()),
           "static": static_checks(sym, raw), "menu_has_continue": False, "menu_new_game_only": False,
           "corrupted": False, "panel_seen": False, "overworld": False, "shots": {}, "notes": []}
    r = Runner(rom_copy, sav_copy, sym, out)
    res["game_title"] = r.core.game_title
    r.trace_every = a.trace_every
    budget = a.frames

    menu = False
    while r.frame < budget:
        r.tap("START", hold=3, after=27)
        t = r.log_screen("title")
        if has(t, "CONTINUE", "NEW GAME"):
            r.step(30)
            t = r.log_screen("menu")
            menu = True
            break
    res["menu_frame"] = r.frame if menu else None
    if not menu:
        res["shots"]["timeout"] = r.shot("timeout.png")
        res["notes"].append("title menu never appeared")
        return finish(r, res, a)
    res["shots"]["menu"] = r.shot("menu.png")
    res["save_file_exists"] = r.rd("wSaveFileExists")
    res["menu_has_continue"] = "CONTINUE" in t
    res["menu_new_game_only"] = "CONTINUE" not in t and "NEW GAME" in t
    res["menu_text"] = t
    if not res["menu_has_continue"]:
        res["notes"].append("no CONTINUE entry: game considers the save absent (check values)")
        return finish(r, res, a)

    r.tap("A", hold=3, after=10)
    deadline = r.frame + 900
    while r.frame < deadline:
        r.step(5)
        t = r.log_screen("continue")
        if has(t, "corrupted"):
            r.step(60)
            r.log_screen("corrupted")
            res["corrupted"] = True
            res["shots"]["corrupted"] = r.shot("corrupted.png")
            res["notes"].append("game printed 'The save file is corrupted'")
            r.tap("A", hold=3, after=60)
            res["after_corrupt_screen"] = r.log_screen("after_corrupt")
            res["shots"]["after_corrupt"] = r.shot("after_corrupt.png")
            return finish(r, res, a)
        if has(t, "PLAYER") and has(t, "TIME"):
            r.step(40)
            r.log_screen("panel")
            res["panel_seen"] = True
            res["panel_frame"] = r.frame
            res["shots"]["continue_panel"] = r.shot("continue_panel.png")
            break
    if not res["panel_seen"]:
        res["shots"]["no_panel"] = r.shot("no_panel.png")
        res["notes"].append("continue panel never appeared")
        return finish(r, res, a)

    r.tap("A", hold=3, after=10)
    stable = 0
    last_a = r.frame
    while r.frame < budget:
        r.step(2)
        t = r.log_screen("to_overworld")
        if r.rd("wMapStatus") == 2 and not has(t, "PLAYER", "corrupted"):
            stable += 2
            if stable >= 60:
                break
        else:
            stable = 0
            if r.frame - last_a >= 60 and t.strip(" .\n"):
                r.tap("A", hold=3, after=5)
                last_a = r.frame
                res["notes"].append("pressed A at frame %d on screen: %s" % (r.frame, " | ".join(l.strip() for l in t.split("\n") if l.strip(" .")) ))
    if stable >= 60:
        r.step(90)
        r.log_screen("overworld")
        res["overworld"] = True
        res["overworld_frame"] = r.frame
        res["shots"]["overworld"] = r.shot("overworld.png")
        res["overworld_tilemap_distinct"] = len(set(r.rds("wTilemap", 360)))
        res["overworld_png_colors"] = len(r.fb.to_pil().convert("RGB").crop((0, 0, 160, 144)).getcolors(65536) or [])
        res["overworld_blank"] = res["overworld_tilemap_distinct"] <= 1 or res["overworld_png_colors"] <= 1
        if res["overworld_blank"]:
            res["notes"].append("overworld loop runs but the screen is a single tile/colour: map state in the save (wScreenSave, player object) is not drawable")
    else:
        res["shots"]["timeout"] = r.shot("timeout.png")
        res["notes"].append("overworld loop never reached")
    return finish(r, res, a)


def finish(r, res, a):
    sram = r.sram()
    res["sram_clone_size"] = len(sram)
    res["frames"] = r.frame
    res["memory"] = read_memory(r, sram)
    (r.out / "after.sav").write_bytes(sram[:SRAM_SIZE])
    if len(sram) > SRAM_SIZE:
        (r.out / "after_full.sav").write_bytes(sram)
    inp = Path(r.out / "input.sav").read_bytes()[:SRAM_SIZE]
    diff = [i for i in range(min(len(inp), len(sram), SRAM_SIZE)) if inp[i] != sram[i]]
    res["after_diff_bytes"] = len(diff)
    res["after_diff_banks"] = sorted({i // 0x2000 for i in diff})
    labels = sorted((v[0] * 0x2000 + v[1] - 0xA000, k) for k, v in r.sym.items()
                    if k.startswith("s") and "." not in k and 0xA000 <= v[1] < 0xC000 and v[0] < 4)
    regions = {}
    for i in diff:
        j = max(0, bisect.bisect_right([x[0] for x in labels], i) - 1)
        regions.setdefault(labels[j][1], []).append(i)
    res["after_diff_regions"] = {k: {"bytes": len(v), "first": hex(v[0]), "last": hex(v[-1])} for k, v in regions.items()}
    res["after_diff_bytes_excluding_scratch"] = sum(len(v) for k, v in regions.items() if not k.startswith(("sWindowStack", "sScratch")))
    res["after_static"] = static_checks(r.sym, sram)
    res["screens"] = r.screens
    res["ok"] = bool(res["overworld"] and not res["corrupted"])
    text = json.dumps(res, indent=2)
    (r.out / "result.json").write_text(text + "\n")
    if a.dump_json:
        Path(a.dump_json).parent.mkdir(parents=True, exist_ok=True)
        Path(a.dump_json).write_text(text + "\n")
    if not a.quiet:
        print(text)
    return res


def main(argv=None):
    p = argparse.ArgumentParser(description=HELP, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--rom", required=True, help="Gold, Silver or Crystal .gbc (pret build)")
    p.add_argument("--sav", required=True, help="battery save (32768 bytes, or 32816 with an RTC footer)")
    p.add_argument("--out", required=True, help="output directory (created; existing files overwritten)")
    p.add_argument("--sym", help="pret .sym for the ROM (default: ROM path with .sym)")
    p.add_argument("--frames", type=int, default=6000, help="emulated frame budget (default 6000)")
    p.add_argument("--dump-json", help="also write the result JSON here")
    p.add_argument("--trace-every", type=int, default=0, help="also save every Nth frame to OUT/trace/ (debugging)")
    p.add_argument("--quiet", action="store_true", help="do not print the JSON to stdout")
    a = p.parse_args(argv)
    for f in (a.rom, a.sav):
        if not Path(f).is_file():
            p.error("missing file: %s" % f)
    try:
        res = run(a)
    except (RuntimeError, KeyError, OSError) as e:
        print("error: %r" % (e,), file=sys.stderr)
        return 2
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
