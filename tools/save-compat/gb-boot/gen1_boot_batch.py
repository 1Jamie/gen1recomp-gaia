#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser(description="Boot every save in a manifest.json through gen1_boot.py and compare WRAM with the expectation.")
    ap.add_argument("--dir", required=True)
    ap.add_argument("--rom-red", required=True)
    ap.add_argument("--rom-blue", required=True)
    ap.add_argument("--rom-yellow", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    roms = {"red": args.rom_red, "blue": args.rom_blue, "yellow": args.rom_yellow}
    manifest = json.load(open(os.path.join(args.dir, "manifest.json")))
    failures = 0
    for entry in manifest:
        rom = roms[entry["version"]]
        sym = os.path.splitext(rom)[0] + ".sym"
        out = os.path.join(args.out, entry["file"].replace(".sav", ""))
        proc = subprocess.run(
            [sys.executable, os.path.join(HERE, "gen1_boot.py"), "--rom", rom, "--sym", sym,
             "--sav", os.path.join(args.dir, entry["file"]), "--out", out],
            capture_output=True, text=True)
        try:
            result = json.loads(proc.stdout.strip().splitlines()[-1])
        except Exception:
            result = {"loaded": False, "memory": {}}
        mem = result["memory"]
        bad = []
        if not result["loaded"]:
            bad.append("did not reach the overworld")
        for key, want in entry["expect"].items():
            if want is None:
                continue
            got = mem.get(key)
            if got != want:
                bad.append("%s want %s got %s" % (key, want, got))
        for key, floor in (entry.get("atLeast") or {}).items():
            got = mem.get(key)
            if got is None or got < floor:
                bad.append("%s want at least %s got %s" % (key, floor, got))
        status = "ok  " if not bad else "FAIL"
        print("%s %s %s" % (status, entry["file"], "; ".join(bad)))
        failures += 1 if bad else 0
    print("%d/%d saves booted and matched" % (len(manifest) - failures, len(manifest)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
