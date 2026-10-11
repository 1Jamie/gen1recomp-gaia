#!/usr/bin/env python3
"""Exercise check_bundled_libs.py on synthetic aarch64 ELF port trees."""
from pathlib import Path
import struct
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_bundled_libs  # noqa: E402


def elf(needed, soname=None, runpath=None):
    names = list(needed) + ([soname] if soname else []) + ([runpath] if runpath else [])
    strtab = b"\0"
    index = {}
    for name in names:
        index[name] = len(strtab)
        strtab += name.encode() + b"\0"
    dyn = [(1, index[n]) for n in needed]
    if soname:
        dyn.append((14, index[soname]))
    if runpath:
        dyn.append((29, index[runpath]))
    header_size, ph_size = 64, 56
    str_off = header_size + 2 * ph_size
    dyn_off = str_off + len(strtab)
    dyn.append((5, str_off))
    dyn.append((0, 0))
    dynamic = b"".join(struct.pack("<qQ", t, v) for t, v in dyn)
    total = dyn_off + len(dynamic)
    ident = b"\x7fELF" + bytes([2, 1, 1]) + b"\0" * 9
    header = ident + struct.pack("<HHIQQQIHHHHHH", 3, 183, 1, 0, header_size, 0, 0,
                                 header_size, ph_size, 2, 64, 0, 0)
    load = struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, total, total, 0x1000)
    pdyn = struct.pack("<IIQQQQQQ", 2, 6, dyn_off, dyn_off, dyn_off, len(dynamic), len(dynamic), 8)
    return header + load + pdyn + strtab + dynamic


def tree(root, libs):
    (root / "bin").mkdir(parents=True)
    (root / "libs.aarch64").mkdir()
    (root / "bin/love.aarch64").write_bytes(
        elf(["liblove-11.5.so", "libluajit-5.1.so.2", "libc.so.6"]))
    for name, data in libs.items():
        (root / "libs.aarch64" / name).write_bytes(data)


LOVE_NEEDS = ["libSDL2-2.0.so.0", "libfreetype.so.6", "libluajit-5.1.so.2",
              "libopenal.so.1", "libz.so.1", "libmodplug.so.1", "libvorbisfile.so.3",
              "libtheoradec.so.1", "libogg.so.0", "libmpg123.so.0", "libstdc++.so.6",
              "libm.so.6", "libc.so.6", "ld-linux-aarch64.so.1", "libgcc_s.so.1"]
FULL = {
    "liblove-11.5.so": elf(LOVE_NEEDS, "liblove-11.5.so"),
    "libluajit-5.1.so.2": elf(["libm.so.6", "libdl.so.2", "libc.so.6"], "libluajit-5.1.so.2"),
    "libmodplug.so.1": elf(["libstdc++.so.6", "libc.so.6"], "libmodplug.so.1"),
    "libogg.so.0": elf(["libc.so.6"], "libogg.so.0"),
    "libvorbis.so.0": elf(["libogg.so.0", "libc.so.6"], "libvorbis.so.0"),
    "libvorbisfile.so.3": elf(["libvorbis.so.0", "libogg.so.0"], "libvorbisfile.so.3"),
    "libtheoradec.so.1": elf(["libc.so.6"], "libtheoradec.so.1"),
    "libmpg123.so.0": elf(["libm.so.6", "libc.so.6"], "libmpg123.so.0"),
}

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)

    tree(tmp / "full", FULL)
    errors = check_bundled_libs.check(tmp / "full")
    assert errors == [], errors

    missing = {k: v for k, v in FULL.items()
               if k not in ("libtheoradec.so.1", "libvorbis.so.0")}
    tree(tmp / "missing", missing)
    errors = check_bundled_libs.check(tmp / "missing")
    assert any("liblove-11.5.so: needs libtheoradec.so.1" in e for e in errors), errors
    assert any("libvorbisfile.so.3: needs libvorbis.so.0" in e for e in errors), errors

    renamed = dict(FULL, **{"libogg.so.0": elf(["libc.so.6"], "libogg.so.1")})
    tree(tmp / "soname", renamed)
    errors = check_bundled_libs.check(tmp / "soname")
    assert any("SONAME libogg.so.1" in e for e in errors), errors

    leaked = dict(FULL, **{"libogg.so.0": elf(["libc.so.6"], "libogg.so.0", "/tmp/prefix/lib")})
    tree(tmp / "runpath", leaked)
    errors = check_bundled_libs.check(tmp / "runpath")
    assert any("RUNPATH /tmp/prefix/lib" in e for e in errors), errors

    origin = dict(FULL, **{"libogg.so.0": elf(["libc.so.6"], "libogg.so.0", "$ORIGIN")})
    tree(tmp / "origin", origin)
    assert check_bundled_libs.check(tmp / "origin") == []

    x86 = bytearray(FULL["libogg.so.0"])
    x86[18:20] = struct.pack("<H", 62)
    tree(tmp / "arch", dict(FULL, **{"libogg.so.0": bytes(x86)}))
    errors = check_bundled_libs.check(tmp / "arch")
    assert any("not aarch64" in e for e in errors), errors

print("PASS bundled libs check: full tree, missing codecs, SONAME, RUNPATH, arch")
