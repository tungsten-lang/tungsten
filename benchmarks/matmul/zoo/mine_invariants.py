"""Mine structural invariants from our record-rank scheme library.

For each scheme: GF(2) ranks of the three factor matrices (terms x n^2 —
full rank means no linear compression of that side exists), per-axis weight
histograms, block-structure respect (does every mask stay inside a
row/column partition?), and cross-scheme motif sharing (exact term reuse).
Output is ansatz material: patterns that hold across ALL schemes are
candidate constraints for a parametric construction.
"""
import glob
import itertools
import re
from collections import Counter


def read_scheme(path):
    terms = []
    us, vs, ws = {}, {}, {}
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("R "):
            terms.append(tuple(int(x) for x in ln.split()[1:]))
        elif ln.startswith(("us[", "vs[", "ws[")):
            m = re.match(r"(us|vs|ws)\[(\d+)\] = (\d+)", ln)
            {"us": us, "vs": vs, "ws": ws}[m.group(1)][int(m.group(2))] = int(m.group(3))
        elif len(ln.split()) == 3:
            terms.append(tuple(int(x) for x in ln.split()))
    if us:
        terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    return terms


def gf2_rank(rows):
    rows = [r for r in rows if r]
    rank = 0
    for bit in range(64):
        piv = None
        for i, r in enumerate(rows):
            if r >> bit & 1:
                piv = i
                break
        if piv is None:
            continue
        pr = rows.pop(piv)
        rows = [r ^ pr if r >> bit & 1 else r for r in rows]
        rank += 1
    return rank


def block_respect(masks, n, split):
    """Fraction of masks whose support stays inside one row-block x col-block
    cell of the (split, n-split) partition."""
    inside = 0
    for mk in masks:
        rows = set()
        cols = set()
        for b in range(n * n):
            if mk >> b & 1:
                rows.add(b // n)
                cols.add(b % n)
        rb = {0 if r < split else 1 for r in rows}
        cb = {0 if c < split else 1 for c in cols}
        if len(rb) == 1 and len(cb) == 1:
            inside += 1
    return inside / len(masks)


def analyze(path, n, tag):
    terms = read_scheme(path)
    R = len(terms)
    D = n * n
    out = [f"== {tag} (rank {R}, n={n})"]
    for axis, name in [(0, "U"), (1, "V"), (2, "W")]:
        col = [t[axis] for t in terms]
        rk = gf2_rank(list(col))
        wts = Counter(bin(x).count("1") for x in col)
        hist = " ".join(f"{w}:{c}" for w, c in sorted(wts.items()))
        dup = R - len(set(col))
        out.append(f"  {name}: gf2-rank {rk}/{min(R, D)}  dup-factors {dup}  weights {hist}")
    for split in range(1, n // 2 + 1):
        fr = sum(block_respect([t[a] for t in terms], n, split) for a in range(3)) / 3
        out.append(f"  block ({split},{n-split}) respect: {fr:.2%}")
    return out, set(terms)


def main():
    base = "/Users/erik/tungsten/benchmarks/matmul"
    schemes4 = [(f"{base}/search/scheme47.txt", "scheme47")] + [
        (f, f.split("/")[-1][:-4]) for f in sorted(glob.glob(f"{base}/metaflip/records/444/cpu*.txt"))]
    schemes5 = [(f"{base}/metaflip/matmul_5x5_rank93_gf2.txt", "ours93"),
                (f"{base}/search/seed_mp93.txt", "mp93")]

    termsets = {}
    for path, tag in schemes4:
        lines, ts = analyze(path, 4, tag)
        print("\n".join(lines))
        termsets[tag] = ts
    for path, tag in schemes5:
        lines, ts = analyze(path, 5, tag)
        print("\n".join(lines))
        termsets[tag] = ts

    print("\n== cross-scheme motif sharing (exact shared terms, 4x4 library)")
    tags4 = [t for _, t in schemes4]
    any_shared = False
    for a, b in itertools.combinations(tags4, 2):
        s = len(termsets[a] & termsets[b])
        if s:
            print(f"  {a} & {b}: {s} shared terms")
            any_shared = True
    if not any_shared:
        print("  none — all pairs fully disjoint")
    print("\n== shared single factors across 4x4 library (same mask reused in any scheme)")
    for axis, name in [(0, "U"), (1, "V"), (2, "W")]:
        pool = Counter()
        for tag in tags4:
            for t in termsets[tag]:
                pool[t[axis]] += 1
        reused = {m: c for m, c in pool.items() if c > 1}
        top = sorted(reused.items(), key=lambda x: -x[1])[:5]
        print(f"  {name}: {len(reused)} masks appear in >1 scheme; top {top}")


if __name__ == "__main__":
    main()
