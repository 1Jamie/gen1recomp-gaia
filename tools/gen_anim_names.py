#!/usr/bin/env python3
"""Generate src/import/gba/anim_names_<game>.lua for an RSE-family pret build.

usage: tools/gen_anim_names.py --game emerald [--pret ../pokeemerald] [--ref ../pokefirered] [--check]
"""

import argparse
import hashlib
import importlib.util
import os
import re
import sys

ROM_LO = 0x08000000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES = {
    "emerald": {"repo": "pokeemerald", "elf": "pokeemerald.elf", "rom": "pokeemerald.gba"},
}
REF = {"repo": "pokefirered", "elf": "pokefirered.elf", "rom": "pokefirered.gba"}

FIXED = {
    0x00: 3, 0x01: 3, 0x04: 2, 0x05: 1, 0x06: 1, 0x07: 1, 0x08: 1, 0x09: 3,
    0x0A: 2, 0x0B: 2, 0x0C: 3, 0x0D: 1, 0x0E: 5, 0x0F: 1, 0x10: 4, 0x11: 9,
    0x12: 6, 0x13: 5, 0x14: 2, 0x15: 1, 0x16: 1, 0x17: 1, 0x18: 2, 0x19: 4,
    0x1A: 2, 0x1B: 7, 0x1C: 6, 0x1D: 5, 0x1E: 3, 0x20: 1, 0x21: 8, 0x22: 2,
    0x23: 2, 0x24: 5, 0x25: 4, 0x26: 7, 0x27: 7, 0x28: 2, 0x29: 1, 0x2A: 2,
    0x2B: 2, 0x2C: 2, 0x2D: 2, 0x2E: 2, 0x2F: 1,
}

TABLES = [
    ("moves", "gBattleAnims_Moves"),
    ("status", "gBattleAnims_StatusConditions"),
    ("general", "gBattleAnims_General"),
    ("special", "gBattleAnims_Special"),
]


def load_syms_module():
    path = os.path.join(ROOT, "tools", "gen_gba_syms.py")
    spec = importlib.util.spec_from_file_location("gen_gba_syms", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Build:
    def __init__(self, pret, info, symmod):
        self.pret = pret
        with open(os.path.join(pret, info["rom"]), "rb") as f:
            self.b = f.read()
        rows = symmod.read_symbols(os.path.join(pret, info["elf"]))
        symmod.fill_spans(rows)
        self.funcs = {}
        self.func_at = {}
        self.data_at = {}
        self.data = {}
        func_offs, data_offs = {}, {}
        for r in rows:
            if r["type"] == "FUNC":
                self.funcs.setdefault(r["name"], []).append(r)
                func_offs.setdefault(r["name"], set()).add(r["off"])
                self.func_at.setdefault(r["off"], []).append(r)
            else:
                self.data.setdefault(r["name"], []).append(r)
                data_offs.setdefault(r["name"], set()).add(r["off"])
                self.data_at.setdefault(r["off"], []).append(r)
        self.func_collide = {n for n, s in func_offs.items() if len(s) > 1}
        self.data_collide = {n for n, s in data_offs.items() if len(s) > 1}

    def u8(self, o):
        return self.b[o]

    def u16(self, o):
        return self.b[o] | (self.b[o + 1] << 8)

    def u32(self, o):
        return self.u16(o) | (self.u16(o + 2) << 16)

    def off(self, ptr):
        o = ptr - ROM_LO
        return o if 0 <= o < len(self.b) else None

    def sym_off(self, name):
        rs = self.data[name]
        assert len({r["off"] for r in rs}) == 1, name
        return rs[0]["off"]

    def func_row(self, ptr):
        o = self.off(ptr & ~1)
        if o is None:
            return None
        rows = [r for r in self.func_at.get(o, []) if r["size"] > 0] or self.func_at.get(o, [])
        return rows[0] if rows else None

    def data_row(self, ptr):
        o = self.off(ptr)
        if o is None:
            return None
        rows = self.data_at.get(o, [])
        named = [r for r in rows if r["type"] == "OBJECT"] or rows
        return named[0] if named else None

    def func_key(self, r):
        return ("%s:%s" % (r["obj"], r["name"])) if r["name"] in self.func_collide else r["name"]

    def data_key(self, r):
        return ("%s:%s" % (r["obj"], r["name"])) if r["name"] in self.data_collide else r["name"]

    def func_hash(self, r):
        o, n = r["off"], r["size"]
        code = bytearray(self.b[o:o + n])
        mask = [False] * n
        i = 0
        while i + 1 < n:
            if mask[i]:
                i += 2
                continue
            hw = code[i] | (code[i + 1] << 8)
            if (hw & 0xF800) == 0xF000 and i + 3 < n:
                nx = code[i + 2] | (code[i + 3] << 8)
                if (nx & 0xF800) in (0xF800, 0xE800):
                    for k in range(4):
                        mask[i + k] = True
                    i += 4
                    continue
            if (hw & 0xF800) == 0x4800:
                tgt = ((o + i + 4) & ~3) + (hw & 0xFF) * 4 - o
                if 0 <= tgt and tgt + 4 <= n:
                    for k in range(4):
                        mask[tgt + k] = True
            i += 2
        out = bytes(0 if mask[k] else code[k] for k in range(n))
        return hashlib.sha1(out).hexdigest()


def op_len(bd, o):
    op = bd.u8(o)
    if op in (0x02, 0x03):
        return 7 + bd.u8(o + 6) * 2
    if op == 0x1F:
        return 6 + bd.u8(o + 5) * 2
    if op not in FIXED:
        raise ValueError("bad anim opcode 0x%02X at 0x%X" % (op, o))
    return FIXED[op]


def table_labels(pret):
    tables, cur = {}, None
    with open(os.path.join(pret, "data", "battle_anim_scripts.s")) as f:
        for raw in f:
            s = raw.split("@", 1)[0].strip()
            comment = raw.split("@", 1)[1].strip() if "@" in raw else ""
            m = re.match(r"^(\w+)::?$", s)
            if m:
                cur = m.group(1) if m.group(1).startswith("gBattleAnims_") else None
                if cur:
                    tables[cur] = []
                continue
            if cur and s.startswith(".4byte"):
                tables[cur].append((s.split(None, 1)[1].strip(), comment))
    return tables


def walk(bd, roots, errors):
    templates, tasks, seen = {}, {}, set()
    work = list(roots)
    while work:
        o = work.pop()
        if o in seen:
            continue
        seen.add(o)
        pos = o
        for _ in range(8192):
            op = bd.u8(pos)
            if op == 0x02:
                templates.setdefault(bd.u32(pos + 1), pos)
            elif op in (0x03, 0x1F):
                tasks.setdefault(bd.u32(pos + 1), pos)
            elif op in (0x0E, 0x13, 0x24):
                t = bd.off(bd.u32(pos + 1))
                if t is None:
                    errors.append("bad branch at 0x%X" % pos)
                else:
                    work.append(t)
            elif op == 0x21:
                work.append(bd.off(bd.u32(pos + 4)))
            elif op == 0x12:
                work.append(bd.off(bd.u32(pos + 2)))
            elif op == 0x11:
                work.append(bd.off(bd.u32(pos + 1)))
                work.append(bd.off(bd.u32(pos + 5)))
            if op in (0x08, 0x0F, 0x13):
                break
            pos += op_len(bd, pos)
        else:
            errors.append("script at 0x%X did not terminate" % o)
    return templates, tasks


def short_cb(n):
    return n[4:] if re.match(r"^Anim[A-Z]", n) else n


def short_task(n):
    return n[len("AnimTask_"):] if n.startswith("AnimTask_") else n


def tag_names(pret):
    out = {}
    with open(os.path.join(pret, "include", "constants", "battle_anim.h")) as f:
        for l in f:
            m = re.match(r"#define\s+ANIM_TAG_(\w+)\s+\(ANIM_SPRITES_START\s*\+\s*(\d+)\)", l)
            if m:
                out[int(m.group(2))] = m.group(1)
    return out


def lua_str(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def lua_key(k):
    return k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[%s]" % lua_str(k)


def render_map(name, d, indent="  "):
    rows = ["%s%s = {" % (indent, name)]
    for k in sorted(d):
        rows.append("%s  %s = %s," % (indent, lua_key(k), lua_str(d[k])))
    rows.append("%s}," % indent)
    return rows


def render_list(name, lst, indent="  "):
    rows = ["%s%s = {" % (indent, name)]
    for v in lst:
        rows.append("%s  %s," % (indent, lua_str(v)))
    rows.append("%s}," % indent)
    return rows


def render_indexed(name, d, indent="  "):
    rows = ["%s%s = {" % (indent, name)]
    for k in sorted(d):
        rows.append("%s  [%d] = %s," % (indent, k, lua_str(d[k])))
    rows.append("%s}," % indent)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default="emerald", choices=sorted(GAMES))
    ap.add_argument("--pret")
    ap.add_argument("--ref")
    ap.add_argument("--out")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    info = GAMES[args.game]
    pret = args.pret or os.path.join(os.path.dirname(ROOT), info["repo"])
    refp = args.ref or os.path.join(os.path.dirname(ROOT), REF["repo"])
    out = args.out or os.path.join(ROOT, "src", "import", "gba", "anim_names_%s.lua" % args.game)

    symmod = load_syms_module()
    em = Build(pret, info, symmod)
    fr = Build(refp, REF, symmod)
    errors = []

    tables = table_labels(pret)
    roots, names = [], {}
    for key, tname in TABLES:
        base = em.sym_off(tname)
        lst = []
        for i, (lab, comment) in enumerate(tables[tname]):
            if lab == "Move_COUNT":
                continue
            ptr = em.u32(base + i * 4)
            o = em.off(ptr)
            if o is None:
                errors.append("%s[%d] bad pointer" % (tname, i))
                continue
            roots.append(o)
            if key != "moves":
                m = re.match(r"B_ANIM_(\w+)", comment)
                if not m:
                    errors.append("%s[%d] has no B_ANIM_ comment" % (tname, i))
                lst.append(m.group(1) if m else lab)
        names[key] = lst

    tmpl_ptrs, task_ptrs = walk(em, roots, errors)

    fr_tmpl_names = set(fr.data)
    fr_func_names = set(fr.funcs)
    em_func_names = set(em.funcs)

    fr_by_hash = {}
    for name, rs in fr.funcs.items():
        if name in em_func_names:
            continue
        for r in rs:
            if r["size"] > 0:
                fr_by_hash.setdefault(fr.func_hash(r), set()).add(name)

    renamed_cb, renamed_task, renamed_tmpl = {}, {}, {}
    only_cb, only_task, only_tmpl = set(), set(), set()

    def canon_func(r, renamed, only):
        name = r["name"]
        if name in fr_func_names:
            return name
        cands = fr_by_hash.get(em.func_hash(r), set())
        if len(cands) == 1:
            frn = next(iter(cands))
            renamed[name] = frn
            return frn
        if len(cands) > 1:
            errors.append("ambiguous hash match for %s: %s" % (name, ", ".join(sorted(cands))))
        only.add(name)
        return name

    tasks = {}
    for ptr in sorted(task_ptrs):
        r = em.func_row(ptr)
        if not r:
            errors.append("task pointer 0x%08X at script 0x%X has no ELF function" % (ptr, task_ptrs[ptr]))
            continue
        tasks[em.func_key(r)] = short_task(canon_func(r, renamed_task, only_task))

    callbacks, templates = {}, {}
    fr_tmpl_rows = {}
    for name, rs in fr.data.items():
        if name in em.data or not name.endswith("Template"):
            continue
        for r in rs:
            fr_tmpl_rows[name] = r

    def tmpl_shape(bd, off, cbname):
        return (bd.u16(off), bd.u16(off + 2), bytes(bd.b[bd.off(bd.u32(off + 4)):bd.off(bd.u32(off + 4)) + 6])
                if bd.off(bd.u32(off + 4)) is not None else b"", cbname)

    fr_shapes = {}
    for name, r in fr_tmpl_rows.items():
        o = r["off"]
        if o + 24 > len(fr.b):
            continue
        cbr = fr.func_row(fr.u32(o + 20))
        if not cbr:
            continue
        fr_shapes.setdefault(tmpl_shape(fr, o, cbr["name"]), set()).add(name)

    for ptr in sorted(tmpl_ptrs):
        r = em.data_row(ptr)
        if not r:
            errors.append("template pointer 0x%08X at script 0x%X has no ELF symbol" % (ptr, tmpl_ptrs[ptr]))
            continue
        o = r["off"]
        cbptr = em.u32(o + 20)
        cbr = em.func_row(cbptr)
        if not cbr:
            errors.append("template %s callback 0x%08X has no ELF function" % (r["name"], cbptr))
            continue
        cbcanon = canon_func(cbr, renamed_cb, only_cb)
        callbacks[em.func_key(cbr)] = short_cb(cbcanon)
        tname = r["name"]
        if tname in fr_tmpl_names:
            canon = tname
        else:
            cands = fr_shapes.get(tmpl_shape(em, o, cbcanon), set())
            if len(cands) == 1:
                canon = next(iter(cands))
                renamed_tmpl[tname] = canon
            else:
                canon = tname
                only_tmpl.add(tname)
        templates[em.data_key(r)] = canon

    tags = tag_names(pret)
    if sorted(tags) != list(range(len(tags))):
        errors.append("ANIM_TAG_ indices are not contiguous")

    print("%s: %d script roots, %d templates, %d callbacks, %d tasks" % (
        args.game, len(roots), len(templates), len(callbacks), len(tasks)))
    print("renamed: callbacks=%d tasks=%d templates=%d" % (len(renamed_cb), len(renamed_task), len(renamed_tmpl)))
    for k in sorted(renamed_cb):
        print("  cb   %s -> %s" % (k, renamed_cb[k]))
    for k in sorted(renamed_task):
        print("  task %s -> %s" % (k, renamed_task[k]))
    for k in sorted(renamed_tmpl):
        print("  tmpl %s -> %s" % (k, renamed_tmpl[k]))
    print("%s-only: callbacks=%s" % (args.game, ", ".join(sorted(only_cb)) or "-"))
    print("%s-only: tasks=%s" % (args.game, ", ".join(sorted(only_task)) or "-"))
    print("%s-only: templates=%s" % (args.game, ", ".join(sorted(only_tmpl)) or "-"))
    if errors:
        print("ERRORS (%d):" % len(errors))
        for e in errors[:80]:
            print("  " + e)
        sys.exit(1)

    lines = [
        "-- tools/gen_anim_names.py from %s, %s/data/battle_anim_scripts.s, %s/include/constants/battle_anim.h"
        % (info["elf"], info["repo"], info["repo"]),
        "return {",
        "  game = %s," % lua_str(args.game),
    ]
    lines += render_map("templates", templates)
    lines += render_map("callbacks", callbacks)
    lines += render_map("tasks", tasks)
    lines += ["  renamed = {"]
    lines += render_map("callbacks", renamed_cb, "    ")
    lines += render_map("tasks", renamed_task, "    ")
    lines += render_map("templates", renamed_tmpl, "    ")
    lines += ["  },", "  gameOnly = {"]
    lines += render_list("callbacks", sorted(only_cb), "    ")
    lines += render_list("tasks", sorted(only_task), "    ")
    lines += render_list("templates", sorted(only_tmpl), "    ")
    lines += ["  },"]
    lines += render_indexed("tagNames", tags)
    lines += render_indexed("statusNames", dict(enumerate(names["status"])))
    lines += render_indexed("generalNames", dict(enumerate(names["general"])))
    lines += render_indexed("specialNames", dict(enumerate(names["special"])))
    lines += ["  moveCount = %d," % len([l for l, _ in tables["gBattleAnims_Moves"] if l != "Move_COUNT"])]
    lines += ["}", ""]
    text = "\n".join(lines)

    if args.check:
        cur = open(out).read() if os.path.exists(out) else ""
        if cur != text:
            print("STALE %s" % out)
            sys.exit(1)
        print("OK %s" % out)
        return
    with open(out, "w") as f:
        f.write(text)
    print("wrote %s" % out)


if __name__ == "__main__":
    main()
