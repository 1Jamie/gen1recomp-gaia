#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
from pathlib import Path

DEV = Path(__file__).resolve().parents[4]

HELP = """Boot every Gen 2 .sav in a directory through gb_boot.py and tabulate the results.

Picks up files named like the save-compat dumps:

  g2.<version>.<case>.<kind>.sav     (dump_fixtures.lua: kind = src | r1 | fresh)
  gen2.<version>.<case>.sav

version gold   -> --gold-rom   (falls back to --silver-rom when no Gold ROM is built:
                                Gold and Silver share one SRAM layout)
version silver -> --silver-rom
version crystal-> --crystal-rom

Each save boots in its own process (gb_boot.py) into OUT/<file stem>/, so a
native crash only loses that case. Writes OUT/summary.md, OUT/summary.json and
OUT/summary.tsv with: case, kind, rom, static checksum verdict, CONTINUE in
menu, corrupted, continue panel, overworld, blank overworld, name, money,
party count, SRAM current-box count, bytes the game rewrote outside
scratch SRAM (sWindowStack/sScratch) and in which regions, screenshot path.

Example (pygba-headless venv interpreter):

  luajit tools/save-compat/dump_fixtures.lua /tmp/dump
  ~/.local/share/pygba-headless/venv/bin/python \\
      tools/save-compat/gb-boot/gb_boot_batch.py --in /tmp/dump --out /tmp/boots

Exit status is 0 when every save reached the overworld, 1 otherwise.
"""

NAME = re.compile(r"^(?:g2|gen2)\.(gold|silver|crystal)\.(.+?)(?:\.(src|r1|fresh))?\.sav$")


def pick_rom(version, a):
    if version == "crystal":
        return a.crystal_rom
    if version == "gold" and Path(a.gold_rom).is_file():
        return a.gold_rom
    return a.silver_rom


def one(job, a):
    path, version, case, kind = job
    rom = pick_rom(version, a)
    out = Path(a.out) / path.stem
    cmd = [sys.executable, str(Path(__file__).with_name("gb_boot.py")), "--rom", str(rom), "--sav", str(path),
           "--out", str(out), "--frames", str(a.frames), "--quiet"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=a.timeout)
        code, err = p.returncode, p.stderr[-2000:]
    except subprocess.TimeoutExpired:
        code, err = -9, "timeout"
    row = {"file": path.name, "version": version, "case": case, "kind": kind or "", "rom": Path(rom).name,
           "exit": code, "error": err.strip() if code not in (0, 1) else ""}
    rj = out / "result.json"
    if rj.is_file() and code in (0, 1):
        r = json.loads(rj.read_text())
        m = r.get("memory", {})
        shots = r.get("shots", {})
        row.update({
            "static": r["static"]["expected_load"],
            "continue": r["menu_has_continue"],
            "corrupted": r["corrupted"],
            "panel": r["panel_seen"],
            "overworld": r["overworld"],
            "blank": r.get("overworld_blank"),
            "name": m.get("player_name"),
            "money": m.get("money"),
            "party": m.get("party_count"),
            "box": m.get("sram_cur_box_count"),
            "rewrote": r.get("after_diff_bytes_excluding_scratch"),
            "rewrote_regions": ",".join(k for k in r.get("after_diff_regions", {}) if not k.startswith(("sWindowStack", "sScratch"))),
            "shot": shots.get("overworld") or shots.get("corrupted") or shots.get("menu") or next(iter(shots.values()), ""),
            "notes": "; ".join(n for n in r.get("notes", []) if not n.startswith("pressed A"))[:200],
        })
    return row


def main(argv=None):
    p = argparse.ArgumentParser(description=HELP, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--in", dest="inp", required=True, help="directory of .sav files")
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--gold-rom", default=str(DEV / "pokegold" / "pokegold.gbc"))
    p.add_argument("--silver-rom", default=str(DEV / "pokegold" / "pokesilver.gbc"))
    p.add_argument("--crystal-rom", default=str(DEV / "pokecrystal" / "pokecrystal.gbc"))
    p.add_argument("--only", help="regex filter on file names")
    p.add_argument("--frames", type=int, default=6000)
    p.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    p.add_argument("--timeout", type=int, default=300, help="seconds per save")
    a = p.parse_args(argv)
    jobs = []
    for f in sorted(Path(a.inp).iterdir()):
        mt = NAME.match(f.name)
        if mt and (not a.only or re.search(a.only, f.name)):
            jobs.append((f, mt.group(1), mt.group(2), mt.group(3)))
    if not jobs:
        p.error("no gen 2 saves matched in %s" % a.inp)
    for v in {j[1] for j in jobs}:
        rom = pick_rom(v, a)
        if not Path(rom).is_file():
            p.error("missing ROM for %s: %s" % (v, rom))
    Path(a.out).mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        rows = list(ex.map(lambda j: one(j, a), jobs))
    cols = ["version", "case", "kind", "rom", "static", "continue", "corrupted", "panel", "overworld", "blank",
            "name", "money", "party", "box", "rewrote", "rewrote_regions", "shot", "notes"]
    out = Path(a.out)
    (out / "summary.json").write_text(json.dumps(rows, indent=2) + "\n")
    with (out / "summary.tsv").open("w") as f:
        f.write("\t".join(cols) + "\n")
        for r in rows:
            f.write("\t".join(str(r.get(c, "")) for c in cols) + "\n")
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        if r.get("error"):
            lines.append("| %s | %s | %s | %s | ERROR exit %s: %s |" % (r["version"], r["case"], r["kind"], r["rom"],
                                                                       r["exit"], r["error"][:120].replace("\n", " ")))
        else:
            lines.append("| " + " | ".join(str(r.get(c, "")).replace("|", "/") for c in cols) + " |")
    ok = sum(1 for r in rows if r.get("overworld") and not r.get("corrupted"))
    lines.append("")
    lines.append("%d / %d reached the overworld" % (ok, len(rows)))
    (out / "summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if ok == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
