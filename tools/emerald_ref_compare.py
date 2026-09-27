#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops

GBA_FPS = 262144 / 4389

LANDMARKS = [
    ("copyright_white", 14), ("copyright_fade_in", 20), ("copyright_hold_end", 155),
    ("copyright_fade_out", 162), ("scene1_fade_in", 212), ("gf_logo_blend_in", 345),
    ("gf_letters", 420), ("gf_logo_blend_out", 480), ("drop_ripple", 500), ("sparkles_pan", 800),
    ("flygon_silhouette", 1060), ("scene1_white", 1225), ("scene2_fade_in", 1250), ("scene2_mid", 1700),
    ("scene2_torchic_trip", 2000), ("scene2_white", 2200), ("scene3_pokeball", 2300),
    ("scene3_groudon_narrow", 2345), ("scene3_groudon", 2440), ("scene3_kyogre", 2560),
    ("scene3_kyogre_zoom", 2690), ("scene3_clouds", 2800), ("scene3_rayquaza", 3000),
    ("scene3_orb", 3140), ("title_logo", 3270), ("title_shine", 3300), ("title_banner", 3560),
    ("title_settle", 3700),
]


def load(path):
    return Image.open(path).convert("RGB")


def diff(a, b, bits5, tolerance=0):
    if bits5:
        a = a.point(lambda v: v >> 3)
        b = b.point(lambda v: v >> 3)
    d = ImageChops.difference(a, b)
    r, g, bl = d.split()
    m = ImageChops.lighter(ImageChops.lighter(r, g), bl).point(lambda v: 255 if v > tolerance else 0)
    return 100.0 * m.histogram()[255] / (a.width * a.height)


def big(a, b):
    return diff(a, b, False, 8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ours", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--offset", type=int, default=12)
    ap.add_argument("--window", type=int, default=3)
    ap.add_argument("--sweep", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()
    ours, ref = Path(a.ours), Path(a.ref)
    cache = {}

    def our(n):
        if n not in cache:
            p = ours / ("f%05d.png" % n)
            cache[n] = load(p) if p.exists() else None
        return cache[n]

    rows = []
    for name, r in LANDMARKS:
        rp = ref / ("frame-%06d.png" % r)
        if not rp.exists():
            continue
        rimg = load(rp)
        base = r - a.offset
        best = None
        for d in range(-a.window, a.window + 1):
            o = our(base + d)
            if o is None:
                continue
            pct = diff(rimg, o, True)
            if best is None or pct < best[1] or (pct == best[1] and abs(d) < abs(best[0])):
                best = (d, pct)
        at = our(base)
        exact = diff(rimg, at, True) if at is not None else None
        coarse = big(rimg, at) if at is not None else None
        rows.append({
            "landmark": name, "ref_frame": r, "ref_s": round(r / GBA_FPS, 4),
            "engine_tick": base, "engine_s": round(base / 60, 4),
            "diff_at_offset_pct": None if exact is None else round(exact, 3),
            "diff_over_one_step_pct": None if coarse is None else round(coarse, 3),
            "best_shift": None if best is None else best[0],
            "best_diff_pct": None if best is None else round(best[1], 3),
        })
        print("%-24s ref=%5d engine=%5d diff@0=%7s >1step=%7s best shift=%+d diff=%7s" % (
            name, r, base, "-" if exact is None else "%.3f%%" % exact,
            "-" if coarse is None else "%.3f%%" % coarse,
            0 if best is None else best[0], "-" if best is None else "%.3f%%" % best[1]))
    if a.sweep:
        worst = []
        for p in sorted(ours.glob("f?????.png")):
            n = int(p.stem[1:])
            rp = ref / ("frame-%06d.png" % (n + a.offset))
            if not rp.exists():
                continue
            ri, oi = load(rp), load(p)
            pct = diff(ri, oi, True)
            worst.append((big(ri, oi), pct, n))
        worst.sort(reverse=True)
        exact = sum(1 for w in worst if w[1] == 0)
        near = sum(1 for w in worst if w[0] == 0)
        print("sweep: %d frames, %d pixel-exact (5-bit), %d within one colour step, mean diff %.3f%%, mean >1step %.3f%%" % (
            len(worst), exact, near, sum(w[1] for w in worst) / max(1, len(worst)),
            sum(w[0] for w in worst) / max(1, len(worst))))
        for coarse, pct, n in worst[:25]:
            print("  worst engine=%5d ref=%5d >1step=%.3f%% diff=%.3f%%" % (n, n + a.offset, coarse, pct))
    if a.json:
        Path(a.json).write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    main()
