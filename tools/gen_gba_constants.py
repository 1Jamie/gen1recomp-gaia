#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT_ROOT = os.path.join(REPO, "src", "core", "game3", "constants")

GAMES = {
    "emerald": "pokeemerald",
    "firered": "pokefirered",
}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua_key(k):
    if isinstance(k, int):
        return "[%d]" % k
    if IDENT.match(k) and k not in LUA_RESERVED:
        return k
    return "[" + lua_str(k) + "]"


LUA_RESERVED = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}


def lua_value(v, indent, hexfmt=False):
    pad = "  " * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        if hexfmt and v >= 0:
            return "0x%X" % v
        return str(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        if not v:
            return "{}"
        if all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + ", ".join(lua_value(x, 0, hexfmt) for x in v) + " }"
        inner = ",\n".join(pad + "  " + lua_value(x, indent + 1, hexfmt) for x in v)
        return "{\n" + inner + ",\n" + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        keys = sorted(v.keys(), key=lambda k: (0, k, "") if isinstance(k, int) else (1, 0, k))
        if all(not isinstance(v[k], (dict, list)) for k in keys) and len(keys) <= 4 and indent > 1:
            return "{ " + ", ".join("%s = %s" % (lua_key(k), lua_value(v[k], 0, hexfmt)) for k in keys) + " }"
        lines = []
        for k in keys:
            lines.append("%s  %s = %s," % (pad, lua_key(k), lua_value(v[k], indent + 1, hexfmt)))
        return "{\n" + "\n".join(lines) + "\n" + pad + "}"
    raise TypeError(type(v))


def write_lua(game, kind, sources, data, hexfmt=False):
    d = os.path.join(OUT_ROOT, game)
    os.makedirs(d, exist_ok=True)
    src = ", ".join(sources)
    body = "-- tools/gen_gba_constants.py from %s\nreturn %s\n" % (src, lua_value(data, 0, hexfmt))
    path = os.path.join(d, kind + ".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
    return path


def strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", lambda m: " " * 0 + "\n" * m.group(0).count("\n"), text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


class CHeaders:
    def __init__(self, root):
        self.root = root
        self.defs = {}
        self.funcs = {}
        self.order = []
        self.origin = {}
        self.parsed = set()
        self.defined = {"ENGLISH"}
        self.cache = {}

    def parse(self, rel):
        if rel in self.parsed:
            return
        self.parsed.add(rel)
        path = os.path.join(self.root, rel)
        text = strip_c_comments(read(path))
        text = text.replace("\\\n", " ")
        lines = text.split("\n")
        stack = []
        active = True
        enum_buf = None
        for raw in lines:
            line = raw.strip()
            m = re.match(r"#\s*(ifdef|ifndef|if|elif|else|endif|define|include|undef)\b\s*(.*)$", line)
            if m:
                d, rest = m.group(1), m.group(2).strip()
                if d in ("ifdef", "ifndef"):
                    name = rest.split()[0]
                    cond = (name in self.defined or name in self.defs or name.startswith("GUARD_"))
                    if name.startswith("GUARD_"):
                        cond = d == "ifndef"
                    elif d == "ifndef":
                        cond = not cond
                    stack.append((active, cond, cond))
                    active = active and cond
                elif d == "if":
                    cond = bool(self.try_eval(rest))
                    stack.append((active, cond, cond))
                    active = active and cond
                elif d == "elif":
                    outer, _, taken = stack[-1]
                    cond = (not taken) and bool(self.try_eval(rest))
                    stack[-1] = (outer, cond, taken or cond)
                    active = outer and cond
                elif d == "else":
                    outer, _, taken = stack[-1]
                    stack[-1] = (outer, not taken, True)
                    active = outer and not taken
                elif d == "endif":
                    outer, _, _ = stack.pop()
                    active = outer
                elif not active:
                    continue
                elif d == "include":
                    im = re.match(r'"(constants/[^"]+)"', rest)
                    if im:
                        inc = os.path.join("include", im.group(1))
                        if os.path.exists(os.path.join(self.root, inc)):
                            self.parse(inc)
                elif d == "define":
                    fm = re.match(r"([A-Za-z_]\w*)\(([^)]*)\)\s*(.*)$", rest)
                    if fm:
                        self.funcs[fm.group(1)] = ([a.strip() for a in fm.group(2).split(",") if a.strip()], fm.group(3))
                        continue
                    dm = re.match(r"([A-Za-z_]\w*)\s*(.*)$", rest)
                    if dm:
                        self.set(dm.group(1), dm.group(2).strip(), rel)
                continue
            if not active:
                continue
            if enum_buf is None:
                if re.match(r"^(typedef\s+)?enum\b", line):
                    enum_buf = line
                    if "}" in line:
                        self.parse_enum(enum_buf, rel)
                        enum_buf = None
            else:
                enum_buf += " " + line
                if "}" in line:
                    self.parse_enum(enum_buf, rel)
                    enum_buf = None

    def parse_enum(self, text, rel):
        m = re.search(r"\{(.*)\}", text, flags=re.S)
        if not m:
            return
        body = m.group(1)
        parts = []
        depth = 0
        cur = ""
        for ch in body:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            if ch == "," and depth == 0:
                parts.append(cur)
                cur = ""
            else:
                cur += ch
        parts.append(cur)
        prev = None
        for p in parts:
            p = p.strip()
            if not p:
                continue
            if "=" in p:
                name, expr = p.split("=", 1)
                name = name.strip()
                expr = expr.strip()
            else:
                name = p
                expr = "0" if prev is None else "(%s) + 1" % prev
            self.set(name, expr, rel)
            prev = name

    def set(self, name, expr, rel):
        if name not in self.defs:
            self.order.append(name)
        self.defs[name] = expr
        self.origin[name] = rel
        self.cache.pop(name, None)

    def expand_funcs(self, expr, depth=0):
        if depth > 20:
            return expr
        changed = True
        while changed:
            changed = False
            for fname, (params, body) in self.funcs.items():
                m = re.search(r"\b%s\s*\(" % re.escape(fname), expr)
                if not m:
                    continue
                i = m.end()
                lvl = 1
                j = i
                while j < len(expr) and lvl:
                    if expr[j] == "(":
                        lvl += 1
                    elif expr[j] == ")":
                        lvl -= 1
                    j += 1
                args = []
                cur = ""
                lvl = 0
                for ch in expr[i:j - 1]:
                    if ch == "(":
                        lvl += 1
                    elif ch == ")":
                        lvl -= 1
                    if ch == "," and lvl == 0:
                        args.append(cur.strip())
                        cur = ""
                    else:
                        cur += ch
                if cur.strip() or args:
                    args.append(cur.strip())
                sub = body
                for pn, av in zip(params, args):
                    sub = re.sub(r"\b%s\b" % re.escape(pn), "(" + av + ")", sub)
                expr = expr[:m.start()] + "(" + sub + ")" + expr[j:]
                changed = True
        return expr

    def value(self, name, seen=None):
        if name in self.cache:
            return self.cache[name]
        if name not in self.defs:
            return None
        seen = seen or set()
        if name in seen:
            return None
        seen = seen | {name}
        v = self.eval(self.defs[name], seen)
        self.cache[name] = v
        return v

    def try_eval(self, expr):
        try:
            return self.eval(expr, set())
        except Exception:
            return None

    def eval(self, expr, seen):
        expr = self.expand_funcs(expr)
        expr = re.sub(r"\bdefined\s*\(\s*(\w+)\s*\)", lambda m: "1" if (m.group(1) in self.defs or m.group(1) in self.defined) else "0", expr)
        expr = re.sub(r"\((?:u8|u16|u32|s8|s16|s32|int|unsigned)\)", "", expr)
        expr = re.sub(r"\b(0x[0-9A-Fa-f]+|\d+)[uUlL]+\b", r"\1", expr)
        if '"' in expr or "'" in expr or "{" in expr:
            return None

        def rep(m):
            tok = m.group(0)
            if re.match(r"^(0x[0-9A-Fa-f]+|\d+)$", tok):
                return str(int(tok, 0))
            if tok in ("TRUE",) and tok not in self.defs:
                return "1"
            if tok in ("FALSE",) and tok not in self.defs:
                return "0"
            v = self.value(tok, seen)
            if v is None:
                raise ValueError(tok)
            return "(%d)" % v

        try:
            py = re.sub(r"\b[A-Za-z_]\w*\b|\b0x[0-9A-Fa-f]+\b|\b\d+\b", rep, expr)
        except ValueError:
            return None
        py = py.replace("&&", " and ").replace("||", " or ")
        py = re.sub(r"!(?!=)", " not ", py)
        py = py.replace("/", "//")
        if not py.strip():
            return None
        try:
            v = eval(py, {"__builtins__": {}}, {})
        except Exception:
            return None
        if isinstance(v, bool):
            v = int(v)
        if not isinstance(v, int):
            return None
        return v

    def collect(self, pattern, files=None, exclude=None):
        rx = re.compile(pattern)
        ex = re.compile(exclude) if exclude else None
        out = {}
        for n in self.order:
            if not rx.match(n):
                continue
            if ex and ex.match(n):
                continue
            if files is not None and self.origin.get(n) not in files:
                continue
            v = self.value(n)
            if v is not None:
                out[n] = v
        return out

    def ordered(self, names):
        idx = {n: i for i, n in enumerate(self.order)}
        return sorted(names, key=lambda n: idx.get(n, 1 << 30))


def reverse(table, order_fn, skip=None):
    rx = re.compile(skip) if skip else None
    out = {}
    for n in order_fn(list(table.keys())):
        if rx and rx.search(n):
            continue
        v = table[n]
        if v not in out:
            out[v] = n
    return out



def gen_specials(game, root):
    rel = "data/specials.inc"
    lines = read(os.path.join(root, rel)).split("\n")
    stack = []
    active = True
    in_macro = False
    by_id = {}
    by_name = {}
    dups = {}
    wait = {}
    n = 0
    defined = {"ALLOCATE_SPECIAL_TABLE": 1}
    for raw in lines:
        line = raw.split("@")[0].strip()
        if not line:
            continue
        if line.startswith(".macro"):
            in_macro = True
            continue
        if line.startswith(".endm"):
            in_macro = False
            continue
        if in_macro:
            continue
        m = re.match(r"\.(ifdef|ifndef|if|else|endif)\b\s*(.*)$", line)
        if m:
            d, rest = m.group(1), m.group(2).strip()
            if d == "ifdef":
                c = rest in defined
                stack.append((active, c))
                active = active and c
            elif d == "ifndef":
                c = rest not in defined
                stack.append((active, c))
                active = active and c
            elif d == "if":
                c = bool(defined.get(rest, 0)) if re.match(r"^\w+$", rest) else False
                stack.append((active, c))
                active = active and c
            elif d == "else":
                outer, c = stack[-1]
                stack[-1] = (outer, not c)
                active = outer and not c
            elif d == "endif":
                active = stack.pop()[0]
            continue
        if not active:
            continue
        m = re.match(r"def_special\s+(\w+)(?:\s*,\s*waitstate\s*=\s*(\w+))?", line)
        if m:
            name = m.group(1)
            by_id[n] = name
            if name in by_name:
                dups.setdefault(name, [by_name[name]]).append(n)
            by_name[name] = n
            if m.group(2) and m.group(2) not in ("0", "FALSE"):
                wait[n] = True
            n += 1
    data = {"count": n, "byId": by_id, "byName": by_name, "waitstate": wait}
    if dups:
        data["duplicates"] = dups
    return data, [os.path.basename(root) + "/" + rel]



def parse_macros(text):
    macros = {}
    order = []
    cur = None
    for raw in text.split("\n"):
        line = raw.split("@")[0].strip()
        m = re.match(r"\.macro\s+(\w+)\s*(.*)$", line)
        if m:
            params = []
            for p in m.group(2).split(","):
                p = p.strip()
                if not p:
                    continue
                params.append(re.split(r"[:=\s]", p)[0])
            cur = {"name": m.group(1), "params": params, "body": []}
            continue
        if line.startswith(".endm"):
            if cur is not None:
                if cur["name"] not in macros:
                    order.append(cur["name"])
                macros[cur["name"]] = cur
            cur = None
            continue
        if cur is not None and line:
            cur["body"].append(line)
    return macros, order


SIZE_KIND = {".byte": "byte", ".2byte": "half", ".4byte": "word"}
COND_OPEN = (".if", ".ifb", ".ifnb", ".ifdef", ".ifndef")


def parse_tree(body):
    def block(i, stop):
        nodes = []
        while i < len(body):
            line = body[i]
            tok = line.split()[0]
            if tok in stop:
                return nodes, i
            if tok in COND_OPEN:
                branches = []
                i += 1
                while True:
                    b, i = block(i, (".else", ".elseif", ".endif"))
                    branches.append(b)
                    t = body[i].split()[0]
                    i += 1
                    if t == ".endif":
                        break
                if len(branches) == 1:
                    branches.append([])
                nodes.append(("cond", branches))
                continue
            nodes.append(("line", line))
            i += 1
        return nodes, i

    return block(0, ())[0]


def expand_paths(macros, nodes, depth=0):
    paths = [[]]
    for node in nodes:
        if node[0] == "cond":
            alts = []
            for br in node[1]:
                alts.extend(expand_paths(macros, br, depth))
            paths = [p + q for p in paths for q in alts]
            continue
        line = node[1]
        tok = line.split()[0]
        if tok == ".error":
            return []
        if tok in SIZE_KIND:
            arg = line[len(tok):].strip()
            am = re.match(r"^\\(\w+)$", arg)
            item = ("emit", SIZE_KIND[tok], am.group(1) if am else arg)
            paths = [p + [item] for p in paths]
            continue
        if tok.startswith(".") or "=" in tok:
            continue
        if tok in macros and depth < 8:
            sub = expand_paths(macros, macros[tok]["tree"], depth + 1)
            paths = [p + [("call", tok)] + q + [("ret", tok)] for p in paths for q in sub]
    return paths


def opcode_of(item, const_id):
    if item[0] != "emit" or item[1] != "byte":
        return None
    v = item[2]
    if v.startswith("SCR_OP_"):
        return const_id.get(v)
    if re.match(r"^0x[0-9A-Fa-f]+$", v):
        return int(v, 16)
    return None


def gen_script_cmds(game, root):
    rel_t = "data/script_cmd_table.inc"
    rel_m = "asm/macros/event.inc"
    ttext = read(os.path.join(root, rel_t))
    handlers = {}
    consts = {}
    in_tab = False
    idx = 0
    for raw in ttext.split("\n"):
        line = raw.strip()
        if line.startswith("gScriptCmdTable::"):
            in_tab = True
            continue
        if line.startswith("gScriptCmdTableEnd::"):
            break
        m = re.match(r"script_cmd_table_entry\s+(\w+)\s+(\w+)", line)
        if m:
            consts[idx] = m.group(1)
            handlers[idx] = m.group(2)
            idx += 1
            continue
        if in_tab:
            m = re.match(r"\.4byte\s+(\w+)", line)
            if m:
                handlers[idx] = m.group(1)
                idx += 1
    count = idx
    const_id = {c: i for i, c in consts.items()}
    mtext = read(os.path.join(root, rel_m))
    macros, morder = parse_macros(mtext)
    mapinc = os.path.join(root, "asm/macros/map.inc")
    if os.path.exists(mapinc):
        mm, _ = parse_macros(read(mapinc))
        for k, v in mm.items():
            macros.setdefault(k, v)
    for mac in macros.values():
        mac["tree"] = parse_tree(mac["body"])
    cands = {}
    for name in morder:
        for path in expand_paths(macros, macros[name]["tree"]):
            first = next((it for it in path if it[0] == "emit"), None)
            if first is None:
                continue
            op = opcode_of(first, const_id)
            if op is None or path[0] != first and any(it[0] == "call" for it in path[:path.index(first)]):
                continue
            rest = path[path.index(first) + 1:]
            layout = []
            fresh = False
            for it in rest:
                if it[0] == "call":
                    fresh = True
                elif it[0] == "emit":
                    if fresh and opcode_of(it, const_id) is not None:
                        break
                    fresh = False
                    layout.append((it[1], it[2]))
            cands.setdefault(op, {}).setdefault(name, set()).add(tuple(layout))
    by_id = {}
    by_name = {}
    for op in range(count):
        h = handlers[op]
        c = consts.get(op)
        base = h[len("ScrCmd_"):] if h.startswith("ScrCmd_") else h
        pick = None
        lst = cands.get(op, {})
        norm = lambda s: s.lower().replace("_", "")
        names = [n for n in morder if n in lst]
        for name in names:
            if name == base:
                pick = name
                break
        if pick is None and c:
            for name in names:
                if norm(name) == norm(c[len("SCR_OP_"):]):
                    pick = name
                    break
        macro = None
        if pick is None and names:
            macro = names[0]
            pick = names[0]
        if pick is None:
            name = c[len("SCR_OP_"):].lower().replace("_", "") if c else base
            seq, variable = [], False
        else:
            name = pick
            if macro is not None:
                name = base if base != "nop1" else c[len("SCR_OP_"):].lower().replace("_", "")
            layouts = sorted(lst[pick], key=lambda l: (len(l), l))
            kinds = set(tuple(k for k, _ in l) for l in layouts)
            variable = len(kinds) > 1
            if variable:
                seq = []
                for col in zip(*layouts):
                    if len(set(k for k, _ in col)) != 1:
                        break
                    seq.append(col[-1])
            else:
                seq = list(layouts[-1])
        if h == "ScrCmd_nop1" and name != "nop1":
            seq, variable = [], False
            name = c[len("SCR_OP_"):].lower().replace("_", "") if c else name
            stub = True
        else:
            stub = False
        entry = {
            "name": name,
            "handler": h,
            "args": [{"kind": k, "name": a} for k, a in seq],
        }
        if c:
            entry["const"] = c
        if stub:
            entry["stub"] = True
        if macro is not None and macro != name:
            entry["macro"] = macro
        size = 1 + sum({"byte": 1, "half": 2, "word": 4}[k] for k, _ in seq)
        if variable:
            entry["variable"] = True
            entry["prefix"] = size
        else:
            entry["size"] = size
        by_id[op] = entry
        by_name.setdefault(name, op)
    data = {"count": count, "byId": by_id, "byName": by_name}
    base = os.path.basename(root)
    return data, [base + "/" + rel_t, base + "/" + rel_m]



def headers(root):
    h = CHeaders(root)
    for f in sorted(os.listdir(os.path.join(root, "include", "constants"))):
        if f.endswith(".h"):
            h.parse(os.path.join("include", "constants", f))
    for extra in ("include/battle_transition.h",):
        if os.path.exists(os.path.join(root, extra)):
            h.parse(extra)
    return h


def hdr_src(root, files):
    base = os.path.basename(root)
    return [base + "/" + f for f in files if os.path.exists(os.path.join(root, f))]


def simple(h, root, files, pattern, exclude=None, rev=None, revskip=None, hexfmt=False):
    files = [f for f in files if os.path.exists(os.path.join(root, f))]
    t = h.collect(pattern, set(files), exclude)
    data = {"byName": t}
    if rev:
        data["byId"] = {}
        for pfx in rev:
            sub = {k: v for k, v in t.items() if k.startswith(pfx)}
            data["byId"][pfx] = reverse(sub, h.ordered, revskip)
    return data, hdr_src(root, files)


def gen_flags(game, h, root):
    f = ["include/constants/flags.h"]
    t = h.collect(r"^(FLAG_|\w*FLAGS\w*|NUM_)", set(f))
    rev = reverse({k: v for k, v in t.items() if k.startswith("FLAG_")}, h.ordered, r"(_START|_END|_COUNT)$")
    return {"byName": t, "byId": {"FLAG_": rev}}, hdr_src(root, f)


def gen_vars(game, h, root):
    f = ["include/constants/vars.h"]
    t = h.collect(r"^(VAR_|\w*VARS\w*|NUM_)", set(f))
    rev = reverse({k: v for k, v in t.items() if k.startswith("VAR_")}, h.ordered, r"(_START|_END|_COUNT)$")
    return {"byName": t, "byId": {"VAR_": rev}}, hdr_src(root, f)


def gen_songs(game, h, root):
    f = ["include/constants/songs.h"]
    return simple(h, root, f, r"^(MUS_|SE_|PH_|START_MUS|END_MUS|END_SE|NUM_)", rev=["MUS_", "SE_", "PH_"], revskip=r"^(START|END|NUM)_")


def gen_movement(game, h, root):
    f = ["include/constants/event_object_movement.h"]
    return simple(h, root, f, r"^(MOVEMENT_ACTION_|MOVEMENT_TYPE_|NUM_MOVEMENT_TYPES)", rev=["MOVEMENT_ACTION_", "MOVEMENT_TYPE_"], revskip=r"(_COUNT|_NONE_END)$")


def gen_behaviors(game, h, root):
    f = ["include/constants/metatile_behaviors.h"]
    return simple(h, root, f, r"^(MB_|NUM_METATILE_BEHAVIORS)", rev=["MB_"])


def gen_field_effects(game, h, root):
    f = ["include/constants/field_effects.h"]
    return simple(h, root, f, r"^FLDEFF_", rev=["FLDEFF_"])


def gen_items(game, h, root):
    f = ["include/constants/items.h", "include/constants/item.h", "include/constants/global.h"]
    files = [x for x in f if os.path.exists(os.path.join(root, x))]
    t = h.collect(r"^(ITEM_|ITEMS_COUNT|FIRST_|LAST_|NUM_|MAX_BERRY|MAIL_|ITEM_TO_)", set(files[:1]))
    pockets = h.collect(r"^(POCKET_|\w+_POCKET$|POCKETS_COUNT|NUM_BAG_POCKETS)", set(files))
    rev = reverse({k: v for k, v in t.items() if k.startswith("ITEM_")}, h.ordered, r"(_START|_END|_COUNT)$")
    return {"byName": t, "byId": {"ITEM_": rev}, "pockets": pockets}, hdr_src(root, files)


def gen_species(game, h, root):
    f = ["include/constants/species.h"]
    t = h.collect(r"^(SPECIES_|NUM_SPECIES|NATIONAL_DEX_|HOENN_DEX_|KANTO_DEX_|NUM_)", set(f + ["include/constants/pokedex.h"]))
    rev = reverse({k: v for k, v in t.items() if k.startswith("SPECIES_")}, h.ordered, r"(_START|_END|_COUNT)$")
    return {"byName": t, "byId": {"SPECIES_": rev}}, hdr_src(root, f + ["include/constants/pokedex.h"])


def gen_trainer_classes(game, h, root):
    f = ["include/constants/trainers.h"]
    return simple(h, root, f, r"^(TRAINER_CLASS_|FACILITY_CLASS_|TRAINER_PIC_|TRAINER_BACK_PIC_|TRAINER_ENCOUNTER_MUSIC_|NUM_TRAINER_CLASSES|NUM_FACILITY_CLASSES|FACILITY_CLASSES_COUNT)", rev=["TRAINER_CLASS_", "FACILITY_CLASS_", "TRAINER_PIC_", "TRAINER_BACK_PIC_", "TRAINER_ENCOUNTER_MUSIC_"], revskip=r"(_COUNT)$")


def gen_trainers(game, h, root):
    f = ["include/constants/opponents.h"]
    return simple(h, root, f, r"^(TRAINER_|TRAINERS_COUNT|MAX_TRAINERS_COUNT)", rev=["TRAINER_"], revskip=r"(_COUNT)$")


def gen_battle_strings(game, h, root):
    f = ["include/constants/battle_string_ids.h"]
    return simple(h, root, f, r"^(STRINGID_|BATTLESTRINGS_|B_MSG_)", rev=["STRINGID_"])


def gen_easy_chat(game, h, root):
    f = ["include/constants/easy_chat.h"]
    return simple(h, root, f, r"^(EC_GROUP_|EC_NUM_GROUPS|EC_WORD_UNDEFINED|EC_EMPTY_WORD|EC_MASK_|EZCHAT_|EC_INDEX|EC_GROUP)", rev=["EC_GROUP_"], revskip=r"(_COUNT)$")


def gen_decorations(game, h, root):
    f = ["include/constants/decorations.h"]
    return simple(h, root, f, r"^(DECOR_|NUM_DECORATIONS|DECORCAT_|DECORSHAPE_|DECORPERM_|NUM_DECORATION_)", rev=["DECOR_", "DECORCAT_"], revskip=r"(_COUNT)$")


def gen_abilities(game, h, root):
    f = ["include/constants/abilities.h"]
    return simple(h, root, f, r"^(ABILITY_|ABILITIES_COUNT)", rev=["ABILITY_"])


def gen_moves(game, h, root):
    f = ["include/constants/moves.h"]
    return simple(h, root, f, r"^(MOVE_|MOVES_COUNT)", rev=["MOVE_"], revskip=r"(_COUNT)$")


def gen_weather(game, h, root):
    f = ["include/constants/weather.h", "include/constants/field_weather.h"]
    return simple(h, root, f, r"^(WEATHER_|COORD_EVENT_WEATHER_|NUM_WEATHER)", rev=["WEATHER_", "COORD_EVENT_WEATHER_"], revskip=r"(_COUNT)$")


def gen_battle(game, h, root):
    f = ["include/constants/battle.h", "include/battle_transition.h", "include/constants/battle_setup.h"]
    files = [x for x in f if os.path.exists(os.path.join(root, x))]
    t = h.collect(r"^(BATTLE_TYPE_|B_TRANSITION_|BATTLE_ENVIRONMENT_|BATTLE_TERRAIN_|B_OUTCOME_|B_SIDE_|B_POSITION_|B_FLANK_|B_WEATHER_|B_ACTION_|MAX_BATTLERS_COUNT|B_BUFF_|B_SIDE_STATUS_|STATUS1_|STATUS2_|STATUS3_|B_TXT_|BATTLE_FORMAT|TRAINER_BATTLE_)", set(files))
    rev = {}
    for pfx in ("B_TRANSITION_", "BATTLE_ENVIRONMENT_", "BATTLE_TERRAIN_", "B_OUTCOME_", "TRAINER_BATTLE_"):
        sub = {k: v for k, v in t.items() if k.startswith(pfx)}
        if sub:
            rev[pfx] = reverse(sub, h.ordered, r"(_COUNT)$")
    return {"byName": t, "byId": rev}, hdr_src(root, files)


def gen_event_objects(game, h, root):
    f = ["include/constants/event_objects.h"]
    return simple(h, root, f, r"^(OBJ_EVENT_GFX_|NUM_OBJ_EVENT_GFX|LOCALID_PLAYER|LOCALID_CAMERA)", rev=["OBJ_EVENT_GFX_"], revskip=r"^OBJ_EVENT_GFX_VAR_")


def gen_metatile_labels(game, h, root):
    f = ["include/constants/metatile_labels.h"]
    return simple(h, root, f, r"^METATILE_", hexfmt=True)


def gen_region_map_sections(game, h, root):
    f = ["include/constants/region_map_sections.h"]
    return simple(h, root, f, r"^(MAPSEC_|METLOC_|KANTO_MAPSEC_)", rev=["MAPSEC_"], revskip=r"(_COUNT|_START|_END)$")


def gen_heal_locations(game, h, root):
    f = ["include/constants/heal_locations.h"]
    return simple(h, root, f, r"^(HEAL_LOCATION_|NUM_HEAL_LOCATIONS)", rev=["HEAL_LOCATION_"])


def gen_map_groups(game, h, root):
    rel = "data/maps/map_groups.json"
    j = json.loads(read(os.path.join(root, rel)))
    by_name = {}
    groups = []
    for gi, gname in enumerate(j["group_order"]):
        maps = j[gname]
        groups.append({"name": gname, "count": len(maps)})
        for mi, mname in enumerate(maps):
            mj = json.loads(read(os.path.join(root, "data", "maps", mname, "map.json")))
            by_name[mj["id"]] = {"group": gi, "num": mi, "name": mname}
    data = {"groups": groups, "byName": by_name}
    return data, [os.path.basename(root) + "/" + rel]


HDR_KINDS = [
    ("flags", gen_flags, True),
    ("vars", gen_vars, True),
    ("songs", gen_songs, False),
    ("movement", gen_movement, False),
    ("metatile_behaviors", gen_behaviors, True),
    ("field_effects", gen_field_effects, False),
    ("items", gen_items, False),
    ("species", gen_species, False),
    ("trainer_classes", gen_trainer_classes, False),
    ("trainers", gen_trainers, False),
    ("battle_string_ids", gen_battle_strings, False),
    ("easy_chat", gen_easy_chat, False),
    ("decorations", gen_decorations, False),
    ("abilities", gen_abilities, False),
    ("moves", gen_moves, False),
    ("weather", gen_weather, False),
    ("battle", gen_battle, False),
    ("map_groups", gen_map_groups, False),
    ("event_objects", gen_event_objects, False),
    ("metatile_labels", gen_metatile_labels, True),
    ("region_map_sections", gen_region_map_sections, False),
    ("heal_locations", gen_heal_locations, False),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pret", default=os.path.dirname(REPO))
    ap.add_argument("--game", action="append")
    ap.add_argument("--kind", action="append")
    a = ap.parse_args()
    games = a.game or list(GAMES)
    for game in games:
        root = os.path.join(a.pret, GAMES[game])
        if not os.path.isdir(root):
            sys.exit("missing pret tree: " + root)
        want = set(a.kind) if a.kind else None
        if want is None or "specials" in want:
            d, s = gen_specials(game, root)
            print(write_lua(game, "specials", s, d))
        if want is None or "script_cmds" in want:
            d, s = gen_script_cmds(game, root)
            print(write_lua(game, "script_cmds", s, d))
        if want is not None and not (want & {k for k, _, _ in HDR_KINDS}):
            continue
        h = headers(root)
        for kind, fn, hexfmt in HDR_KINDS:
            if want is not None and kind not in want:
                continue
            d, s = fn(game, h, root)
            if d is None:
                continue
            print(write_lua(game, kind, s, d, hexfmt))


if __name__ == "__main__":
    main()
