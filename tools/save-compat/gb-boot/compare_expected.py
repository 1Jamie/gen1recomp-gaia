#!/usr/bin/env python3
import argparse
import glob
import json
import os
import sys

PARTY_KEYS = ("species", "item", "moves", "pp", "level", "status", "hp", "max_hp")


def check(label, want, got, problems):
    if want != got:
        problems.append("%s: expected %r, the game has %r" % (label, want, got))


def compare(expect, result):
    mem = result.get("memory") or {}
    problems = []
    check("player name", expect["player_name"], mem.get("player_name"), problems)
    check("player id", expect["player_id"], mem.get("player_id"), problems)
    check("money", expect["money"], mem.get("money"), problems)
    check("party count", expect["party_count"], mem.get("party_count"), problems)
    listed = [m["listed"] for m in expect["party"]]
    check("party species list", listed, (mem.get("party_species_list") or [])[: len(listed)], problems)
    for i, want in enumerate(expect["party"]):
        got = (mem.get("party") or [])[i] if i < len(mem.get("party") or []) else {}
        for key in PARTY_KEYS:
            if key == "hp" and want["listed"] == 0xFD:
                continue
            check("party %d %s" % (i + 1, key), want[key], got.get(key), problems)
    check("current box", expect["cur_box"], mem.get("cur_box"), problems)
    check("box names", expect["box_names"], mem.get("box_names"), problems)
    for key in ("map_group", "map_number", "x", "y"):
        check(key, expect[key], mem.get(key), problems)
    check("archived box counts", expect["sram_box_counts"], mem.get("sram_box_counts"), problems)
    check("active box (sBox after LoadBox) count", expect["sram_cur_box_count"], mem.get("sram_cur_box_count"), problems)
    return problems


def main():
    ap = argparse.ArgumentParser(description="Compare what the real game read out of an exported save with the expected values written next to the save by gen2_engine_fuzz_test.lua (SAVE_COMPAT_ENGINE_DUMP).")
    ap.add_argument("--saves", required=True, help="directory holding gen2.<version>.engineNNN.expect.json")
    ap.add_argument("--boots", required=True, help="gb_boot_batch.py output directory")
    a = ap.parse_args()
    bad = 0
    total = 0
    for path in sorted(glob.glob(os.path.join(a.saves, "*.expect.json"))):
        stem = os.path.basename(path)[: -len(".expect.json")]
        res = os.path.join(a.boots, stem, "result.json")
        if not os.path.exists(res):
            print("MISSING", stem)
            bad += 1
            continue
        total += 1
        problems = compare(json.load(open(path)), json.load(open(res)))
        if problems:
            bad += 1
            print("FAIL", stem)
            for line in problems[:8]:
                print("   ", line)
        else:
            print("ok  ", stem)
    print("%d of %d saves read back exactly as exported" % (total - bad, total))
    return 1 if bad else 0


sys.exit(main())
