import sys


def cs(d, a, n):
    return (~sum(d[a:a + n])) & 0xFF


def boxoff(i):
    return 0x4000 + i * 0x462 if i < 6 else 0x6000 + (i - 6) * 0x462


def check(d):
    res = {}
    res['main'] = (cs(d, 0x2598, 0x3523 - 0x2598), d[0x3523])
    res['bank2all'] = (cs(d, 0x4000, 0x5A4C - 0x4000), d[0x5A4C])
    res['bank3all'] = (cs(d, 0x6000, 0x7A4C - 0x6000), d[0x7A4C])
    for i in range(12):
        idx = (0x5A4D + i) if i < 6 else (0x7A4D + i - 6)
        res['box%d' % (i + 1)] = (cs(d, boxoff(i), 0x462), d[idx])
    return res


def fix_boxes(d):
    for i in range(12):
        idx = (0x5A4D + i) if i < 6 else (0x7A4D + i - 6)
        d[idx] = cs(d, boxoff(i), 0x462)
    d[0x5A4C] = cs(d, 0x4000, 0x5A4C - 0x4000)
    d[0x7A4C] = cs(d, 0x6000, 0x7A4C - 0x6000)


if __name__ == '__main__':
    mode = sys.argv[1]
    d = bytearray(open(sys.argv[2], 'rb').read())
    if mode == 'check':
        for k, (a, b) in check(d).items():
            print(k, hex(a), hex(b), 'OK' if a == b else 'BAD')
    elif mode == 'hpfix':
        cnt = 0
        for i in range(12):
            for s in range(20):
                p = boxoff(i) + 0x16 + s * 0x21
                if d[p] and d[p + 2] == 0xFF:
                    print('box', i + 1, 'slot', s + 1, 'species', d[p], 'hp', d[p + 1] << 8 | d[p + 2])
                    d[p + 2] = 0xFE
                    cnt += 1
        fix_boxes(d)
        open(sys.argv[3], 'wb').write(d)
        print('patched', cnt)
