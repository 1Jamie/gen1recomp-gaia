#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import sys

HELP = """Headless Game Boy boot-to-CONTINUE harness for Gen 1 battery saves.

Boots a Pokemon Red, Blue or Yellow ROM in mGBA (GB core, python bindings, no
window), mashes START and A through the title and CONTINUE screens, waits for
the overworld, screenshots the menu and the overworld, then reads live WRAM
using label addresses from the ROM's pret .sym file.

  ~/.local/share/pygba-headless/venv/bin/python gen1_boot.py \\
      --rom pokered.gbc --sym pokered.sym --sav my.sav --out /tmp/run1

Exit status 0 when the overworld loaded, 1 when it did not, 2 on usage errors.
Outputs in --out: menu.png, overworld.png, result.json.
"""

KEYS = {"A": 1, "B": 2, "SELECT": 4, "START": 8, "RIGHT": 16, "LEFT": 32, "UP": 64, "DOWN": 128}


def load_sym(path):
    syms = {}
    for line in open(path):
        m = re.match(r"([0-9a-f]{2}):([0-9a-f]{4}) (\S+)$", line.strip())
        if m:
            syms.setdefault(m.group(3), int(m.group(2), 16))
    return syms


def main():
    ap = argparse.ArgumentParser(description=HELP, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", required=True)
    ap.add_argument("--sym", required=True)
    ap.add_argument("--sav", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--title-frames", type=int, default=1500)
    ap.add_argument("--max-frames", type=int, default=3000)
    ap.add_argument("--settle", type=int, default=240)
    ap.add_argument("--patch", action="append", default=[], help="OFFSET=VALUE patched into the save before boot (checksum fixed)")
    ap.add_argument("--read", action="append", default=[], help="NAME=ADDR:LEN extra WRAM reads after load (hex ADDR)")
    args = ap.parse_args()

    import mgba.core
    import mgba.image
    import mgba.log

    mgba.log.silence()
    os.makedirs(args.out, exist_ok=True)
    work = os.path.join(args.out, "work")
    os.makedirs(work, exist_ok=True)
    rom = os.path.join(work, "game.gbc")
    sav = os.path.join(work, "game.sav")
    shutil.copy(args.rom, rom)
    data = bytearray(open(args.sav, "rb").read())
    for item in args.patch:
        off, val = item.split("=")
        data[int(off, 0)] = int(val, 0)
    if args.patch:
        data[0x3523] = (~sum(data[0x2598:0x3523])) & 0xFF
    open(sav, "wb").write(data)
    shutil.copy(args.sav, os.path.join(args.out, "input.sav"))
    args.sav = sav
    sym = load_sym(args.sym)

    core = mgba.core.load_path(rom)
    img = mgba.image.Image(*core.desired_video_dimensions())
    core.set_video_buffer(img)
    core.reset()
    core.autoload_save()

    def run(n, keys=0):
        core.set_keys(raw=keys)
        for _ in range(n):
            core.run_frame()
        core.set_keys(raw=0)

    def u8(addr):
        return core.memory.u8[addr]

    def block(label, n):
        base = sym[label]
        return [u8(base + i) for i in range(n)]

    def shot(name):
        img.to_pil().convert("RGB").save(os.path.join(args.out, name + ".png"))

    player_picture = sym["wSpritePlayerStateData1PictureID"]
    player_y = sym["wSpritePlayerStateData1YPixels"]

    image = open(args.sav, "rb").read()
    want_map, want_y, want_x = image[0x260A], image[0x260D], image[0x260E]

    def in_overworld():
        return (u8(sym["wCurMap"]) == want_map and u8(sym["wYCoord"]) == want_y and u8(sym["wXCoord"]) == want_x
                and u8(player_picture) == 1 and u8(player_y) == 60)

    run(args.title_frames)
    shot("title")
    loaded = False
    frames = 0
    pattern = ["START", "A", "A"]
    step = 0
    while frames < args.max_frames and not loaded:
        run(8, KEYS[pattern[step % 3]])
        run(52)
        step += 1
        frames += 60
        if step == 3:
            shot("menu")
        loaded = in_overworld()
    run(args.settle)
    shot("overworld")

    def bcd(bs):
        v = 0
        for b in bs:
            v = v * 100 + (b >> 4) * 10 + (b & 15)
        return v

    mem = {}
    if loaded:
        count = u8(sym["wPartyCount"])
        mem = {
            "wCurMap": u8(sym["wCurMap"]),
            "wYCoord": u8(sym["wYCoord"]),
            "wXCoord": u8(sym["wXCoord"]),
            "money": bcd(block("wPlayerMoney", 3)),
            "badges": u8(sym["wObtainedBadges"]),
            "options": u8(sym["wOptions"]),
            "playerId": u8(sym["wPlayerID"]) * 256 + u8(sym["wPlayerID"] + 1),
            "partyCount": count,
            "partySpecies": block("wPartySpecies", max(count, 0)),
            "partyLevels": [u8(sym["wPartyMon1Level"] + 44 * i) for i in range(count)],
            "partyHP": [u8(sym["wPartyMon1HP"] + 44 * i) * 256 + u8(sym["wPartyMon1HP"] + 44 * i + 1) for i in range(count)],
            "partyStatus": [u8(sym["wPartyMon1Status"] + 44 * i) for i in range(count)],
            "numBagItems": u8(sym["wNumBagItems"]),
            "bag": block("wBagItems", 2 * u8(sym["wNumBagItems"])),
            "lastBlackoutMap": u8(sym["wLastBlackoutMap"]),
            "statusFlags6": u8(sym["wStatusFlags6"]),
            "mapPalOffset": u8(sym["wMapPalOffset"]),
            "numSafariBalls": u8(sym["wNumSafariBalls"]),
            "safariSteps": u8(sym["wSafariSteps"]) * 256 + u8(sym["wSafariSteps"] + 1),
            "dayCareInUse": u8(sym["wDayCareInUse"]),
            "dayCareSpecies": u8(sym["wDayCareMonSpecies"]),
            "playTime": block("wPlayTimeHours", 5),
            "eventFlags": block("wEventFlags", 320),
            "toggleableObjectFlags": block("wToggleableObjectFlags", 32),
            "hiddenCoinFlags": block("wObtainedHiddenCoinsFlags", 2),
            "trashCans": [u8(sym["wFirstLockTrashCanIndex"]), u8(sym["wSecondLockTrashCanIndex"])],
            "fossil": [u8(sym["wFossilItem"]), u8(sym["wFossilMon"])],
            "beatGymFlags": u8(sym["wBeatGymFlags"]),
            "player": [u8(sym["wSpritePlayerStateData1PictureID"]), u8(sym["wSpritePlayerStateData1FacingDirection"])],
        }
    for item in args.read:
        name, spec = item.split("=")
        addr, length = spec.split(":")
        mem[name] = [u8(int(addr, 16) + i) for i in range(int(length))]
    result = {"loaded": loaded, "memory": mem}
    json.dump(result, open(os.path.join(args.out, "result.json"), "w"), indent=1)
    print(json.dumps(result))
    return 0 if loaded else 1


if __name__ == "__main__":
    sys.exit(main())
