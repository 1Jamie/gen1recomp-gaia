#!/usr/bin/env python3
import json
import os
import sys


def pkhex(path):
    rows = {}
    with open(path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        for line in f:
            cols = line.rstrip("\n").split("\t")
            cols += [""] * (len(header) - len(cols))
            r = dict(zip(header, cols))
            name = os.path.basename(r["file"])
            if r["type"] == "NOT RECOGNIZED":
                rows[name] = {"type": "NOT RECOGNIZED", "exception": r["exception"]}
                continue
            anomalies = r["monAnomalies"]
            rows[name] = {
                "type": r["type"],
                "version": r["version"],
                "checksumsValid": r["PKHeXchk"],
                "party": int(r["party"] or 0),
                "boxed": int(r["boxed"] or 0),
                "monAnomalies": "none" if anomalies == "none" else anomalies.split(" mons;")[0],
                "exception": r["exception"],
                "unchangedWrite": r["unchangedWriteDiff"],
                "reopen": r["pkforgeReopen"],
                "slotsAfterReopen": r["pkforgeSlotDiff"],
                "g3Corrupting": r["pkforgeG3Corrupting"].split(" ")[0],
                "g3Foreign": r["pkforgeG3Foreign"].split(" ")[0],
            }
    return rows


def openhome(path):
    rows = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            if "fatal" in r:
                rows[r["file"]] = {"fatal": r["fatal"]}
                continue
            rows[r["file"]] = {
                "detected": r.get("detected"),
                "usedClass": r.get("usedClass"),
                "forced": r.get("forced"),
                "buildError": r.get("buildError"),
                "invalid": r.get("invalid"),
                "boxCount": r.get("boxCount"),
                "boxCounts": r.get("boxCounts"),
                "loaded": r.get("loaded"),
                "party": r.get("party", r.get("partyLua")),
                "writeNoEditDiffBytes": (r.get("writeNoEdit") or {}).get("diffBytes"),
                "reloadNoEdit": r.get("reloadNoEdit"),
                "reloadTouch": r.get("reloadTouch"),
                "touchFieldDiffs": len(r.get("touchFieldDiffs") or []),
                "slotErrors": len(r.get("slotErrors") or []),
            }
    return rows


def load(kind, path):
    return pkhex(path) if kind == "pkhex" else openhome(path)


def main():
    cmd, kind, actual_path, expected_path = sys.argv[1:5]
    ignore = tuple(sys.argv[5:])
    actual = load(kind, actual_path)
    if cmd == "bless":
        os.makedirs(os.path.dirname(expected_path), exist_ok=True)
        with open(expected_path, "w", encoding="utf-8") as f:
            json.dump({k: actual[k] for k in sorted(actual)}, f, indent=1, sort_keys=True)
            f.write("\n")
        print("   blessed %d files into %s" % (len(actual), expected_path))
        return 0
    if not os.path.exists(expected_path):
        print("   no expected file at %s (run scripts/save-compat.sh --bless)" % expected_path)
        return 1
    with open(expected_path, encoding="utf-8") as f:
        expected = json.load(f)
    bad = 0
    for name in sorted(set(actual) | set(expected)):
        if name in actual and name not in expected:
            print("   NEW      %s" % name)
            bad += 1
        elif name in expected and name not in actual:
            if name.startswith(ignore):
                continue
            print("   MISSING  %s" % name)
            bad += 1
        elif actual[name] != expected[name]:
            keys = sorted(k for k in set(actual[name]) | set(expected[name]) if actual[name].get(k) != expected[name].get(k))
            for k in keys:
                print("   CHANGED  %s %s: expected %r got %r" % (name, k, expected[name].get(k), actual[name].get(k)))
            bad += 1
    if bad:
        print("   %d file(s) differ from %s" % (bad, expected_path))
        return 1
    print("   all %d files match %s" % (len(actual), expected_path))
    return 0


sys.exit(main())
