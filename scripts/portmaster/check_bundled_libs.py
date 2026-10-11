#!/usr/bin/env python3
"""Fail if a bundled aarch64 ELF in a PortMaster port tree needs a shared
library that is neither shipped in libs.aarch64/ nor guaranteed by the host.

Usage: check_bundled_libs.py PORT_DIR
PORT_DIR is the directory holding bin/ and libs.aarch64/.
"""
from pathlib import Path
import re
import struct
import sys

HOST_PROVIDED = re.compile(
    r"^(ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libdl\.so\.2"
    r"|libpthread\.so\.0|librt\.so\.1|libstdc\+\+\.so\.6|libgcc_s\.so\.1"
    r"|libSDL2-2\.0\.so\.0|libopenal\.so\.1|libfreetype\.so\.6|libz\.so\.1"
    r"|lib(GL|EGL|GLESv1_CM|GLESv2)\.so\.[0-9]+)$")

PT_LOAD, PT_DYNAMIC = 1, 2
DT_NULL, DT_NEEDED, DT_STRTAB, DT_SONAME, DT_RPATH, DT_RUNPATH = 0, 1, 5, 14, 15, 29
EM_AARCH64 = 183


class ElfError(Exception):
    pass


def read_dynamic(path):
    data = Path(path).read_bytes()
    if data[:4] != b"\x7fELF":
        return None
    if data[4] != 2 or data[5] != 1:
        raise ElfError("not a 64-bit little-endian ELF")
    machine = struct.unpack_from("<H", data, 18)[0]
    if machine != EM_AARCH64:
        raise ElfError(f"machine {machine} is not aarch64")
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", data, 54)
    loads, dynamic = [], None
    for i in range(phnum):
        p_type, _flags, p_offset, p_vaddr, _paddr, p_filesz, _memsz, _align = \
            struct.unpack_from("<IIQQQQQQ", data, phoff + i * phentsize)
        if p_type == PT_LOAD:
            loads.append((p_vaddr, p_offset, p_filesz))
        elif p_type == PT_DYNAMIC:
            dynamic = (p_offset, p_filesz)
    if dynamic is None:
        return {"needed": [], "soname": None, "paths": []}

    def to_offset(vaddr):
        for start, offset, size in loads:
            if start <= vaddr < start + size:
                return offset + vaddr - start
        raise ElfError(f"address {vaddr:#x} is outside every PT_LOAD segment")

    entries = []
    offset, size = dynamic
    for pos in range(offset, offset + size, 16):
        tag, value = struct.unpack_from("<qQ", data, pos)
        if tag == DT_NULL:
            break
        entries.append((tag, value))
    strtab = next((v for t, v in entries if t == DT_STRTAB), None)
    if strtab is None:
        raise ElfError("dynamic section has no DT_STRTAB")
    base = to_offset(strtab)

    def string(index):
        end = data.index(b"\0", base + index)
        return data[base + index:end].decode()

    return {"needed": [string(v) for t, v in entries if t == DT_NEEDED],
            "soname": next((string(v) for t, v in entries if t == DT_SONAME), None),
            "paths": [string(v) for t, v in entries if t in (DT_RPATH, DT_RUNPATH)]}


def check(port):
    port = Path(port)
    libs = port / "libs.aarch64"
    errors = []
    elves = {}
    for path in sorted(list((port / "bin").glob("*")) + list(libs.glob("*"))):
        if not path.is_file():
            continue
        try:
            info = read_dynamic(path)
        except (ElfError, struct.error, ValueError) as err:
            errors.append(f"{path.relative_to(port)}: {err}")
            continue
        if info is not None:
            elves[path] = info
    if not elves:
        errors.append(f"no ELF files under {port}/bin or {port}/libs.aarch64")
    bundled = {p.name for p in elves if p.parent == libs}
    for path, info in elves.items():
        rel = path.relative_to(port)
        if path.parent == libs and info["soname"] and info["soname"] != path.name:
            errors.append(f"{rel}: SONAME {info['soname']} does not match the file name")
        for runpath in info["paths"]:
            if not all(part.startswith("$ORIGIN") for part in runpath.split(":") if part):
                errors.append(f"{rel}: build-time RPATH/RUNPATH {runpath}")
        for needed in info["needed"]:
            if needed not in bundled and not HOST_PROVIDED.match(needed):
                errors.append(f"{rel}: needs {needed}, which is not in libs.aarch64/")
    return errors


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    errors = check(argv[1])
    for error in errors:
        print(f"FAIL {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"PASS bundled libs: every DT_NEEDED under {argv[1]} is shipped or host-provided")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
