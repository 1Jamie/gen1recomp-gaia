import struct, sys

SIZES = [3884, 3968, 3968, 3968, 3848] + [3968] * 8 + [2000]


def csum(b, n):
    s = 0
    for i in range(0, n, 4):
        s += struct.unpack_from('<I', b, i)[0]
    s &= 0xFFFFFFFF
    return ((s >> 16) + (s & 0xFFFF)) & 0xFFFF


def slots(d):
    for base in (0, 0xE000):
        secs = {}
        for i in range(14):
            o = base + i * 0x1000
            sid = struct.unpack_from('<H', d, o + 0xFF4)[0]
            if struct.unpack_from('<I', d, o)[0] == 0xFFFFFFFF and sid > 13:
                continue
            secs[sid] = o
        if len(secs) == 14:
            yield base, secs


def fix(d, sec, o):
    struct.pack_into('<H', d, o + 0xFF6, csum(d[o:o + 0x1000], SIZES[sec]))


def xor_qty(d, base, table, K):
    for off, cnt in table:
        for i in range(cnt):
            p = base + off + i * 4 + 2
            q = struct.unpack_from('<H', d, p)[0]
            struct.pack_into('<H', d, p, q ^ (K & 0xFFFF))


def frlg(d, mode, K):
    for base, secs in slots(d):
        s0 = secs[0]
        s1 = secs[1]
        if mode == 'min':
            struct.pack_into('<I', d, s0 + 0xAF8, K)
            fix(d, 0, s0)
            continue
        assert struct.unpack_from('<I', d, s0 + 0xF20)[0] == 0
        assert struct.unpack_from('<I', d, s0 + 0xAF8)[0] == 0
        struct.pack_into('<I', d, s0 + 0xF20, K)
        struct.pack_into('<I', d, s0 + 0xAF8, K)
        fix(d, 0, s0)
        m = struct.unpack_from('<I', d, s1 + 0x290)[0]
        struct.pack_into('<I', d, s1 + 0x290, m ^ K)
        c = struct.unpack_from('<H', d, s1 + 0x294)[0]
        struct.pack_into('<H', d, s1 + 0x294, c ^ (K & 0xFFFF))
        xor_qty(d, s1, ((0x298, 30), (0x310, 42), (0x3B8, 30), (0x430, 13), (0x464, 58), (0x54C, 43)), K)
        fix(d, 1, s1)


def emerald(d, K):
    for base, secs in slots(d):
        s0 = secs[0]
        s1 = secs[1]
        assert struct.unpack_from('<I', d, s0 + 0xAC)[0] == 0
        struct.pack_into('<I', d, s0 + 0xAC, K)
        struct.pack_into('<I', d, s0 + 0x1F4, K)
        fix(d, 0, s0)
        m = struct.unpack_from('<I', d, s1 + 0x490)[0]
        struct.pack_into('<I', d, s1 + 0x490, m ^ K)
        c = struct.unpack_from('<H', d, s1 + 0x494)[0]
        struct.pack_into('<H', d, s1 + 0x494, c ^ (K & 0xFFFF))
        xor_qty(d, s1, ((0x498, 50), (0x560, 30), (0x5D8, 30), (0x650, 16), (0x690, 64), (0x790, 46)), K)
        fix(d, 1, s1)


if __name__ == '__main__':
    src, dst, mode = sys.argv[1:4]
    K = 0x5A3C9E71
    d = bytearray(open(src, 'rb').read())
    if mode in ('frlg_min', 'frlg_key'):
        frlg(d, mode.split('_')[1], K)
    elif mode == 'emerald_key':
        emerald(d, K)
    open(dst, 'wb').write(d)
