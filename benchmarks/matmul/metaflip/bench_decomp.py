"""Benchmark a bilinear matrix-multiplication decomposition for ACTUAL performance,
not just rank. Rank alone is the wrong objective: a rank-r scheme over GF(2)
computes C = A·B with r "multiplications" (AND of two GF(2) linear forms) plus a
pile of ADDITIONS (XORs) to build those linear forms and to accumulate the output.
A low-rank-but-dense scheme can need far more total ops than naive.

Two performance axes, both reported:

  * Asymptotic exponent  omega = log_n(rank)   (square <n,n,n>). This is the prize
    for LARGE matrices via recursion: T(N) = rank * T(N/n)  ->  O(N^omega). Lower
    rank => lower exponent => asymptotically faster. Naive <5,5,5> has rank 125 =
    5^3 => omega 3.0; a rank-93 scheme => omega log_5(93) = 2.816.

  * Base-case op count (single <n,n,n> block, no recursion). Standard additive
    complexity of a bilinear scheme, no CSE:
        mults = rank
        adds  = (sum popcount(u_t) - rank)      # build left  forms L_t = u_t . A
              + (sum popcount(v_t) - rank)      # build right forms R_t = v_t . B
              + (sum popcount(w_t) - n*p)       # accumulate C from the products
        total_ops = mults + adds = total_bits - rank - n*p
    So total_ops = (density) - rank - (#outputs). Reducing rank by 1 only pays off
    if it adds <= 1 net bit; otherwise the "faster" (lower-rank) scheme is SLOWER
    as a base-case kernel. This is exactly the tension a rank-only search ignores.

Usage:
  python3 bench_decomp.py <scheme.txt> [<scheme2.txt> ...] [--n 5] [--verify] [--naive]
  python3 bench_decomp.py --watch <run_dir>        # live perf-curve of a search
"""
import glob
import math
import os
import sys
import time


# ---- scheme parsing (R u v w | us[i]= | bare 'rank\n u v w') ----------------
def parse_scheme(path):
    import re
    terms, us, vs, ws = [], {}, {}, {}
    with open(path) as f:
        lines = f.read().splitlines()
    bare = lines and lines[0].strip().isdigit() and not lines[0].startswith(("us", "R"))
    for idx, ln in enumerate(lines):
        ln = ln.strip()
        if ln.startswith("R "):
            a = ln.split()
            terms.append((int(a[1]), int(a[2]), int(a[3])))
        elif ln.startswith(("us[", "vs[", "ws[")):
            mo = re.match(r"(us|vs|ws)\[(\d+)\]\s*=\s*(\d+)", ln)
            if mo:
                {"us": us, "vs": vs, "ws": ws}[mo.group(1)][int(mo.group(2))] = int(mo.group(3))
        elif bare and idx >= 1:
            a = ln.split()
            if len(a) == 3:
                terms.append((int(a[0]), int(a[1]), int(a[2])))
    if us:
        terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    return terms


def naive_scheme(n, m, p):
    return [(1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k))
            for i in range(n) for j in range(m) for k in range(p)]


def verify(terms, n, m, p):
    """Tensor-check: reconstruct the matmul tensor over GF(2) and compare."""
    want = set((i * m + j, j * p + k, i * p + k)
               for i in range(n) for j in range(m) for k in range(p))
    acc = {}
    for u, v, w in terms:
        bu = [x for x in range(n * m) if (u >> x) & 1]
        bv = [x for x in range(m * p) if (v >> x) & 1]
        bw = [x for x in range(n * p) if (w >> x) & 1]
        for a in bu:
            for b in bv:
                for c in bw:
                    acc[(a, b, c)] = acc.get((a, b, c), 0) ^ 1
    got = set(k for k, x in acc.items() if x)
    return got == want


# ---- the performance model --------------------------------------------------
def cost(terms, n, m, p):
    r = len(terms)
    bu = sum(bin(u).count("1") for u, v, w in terms)
    bv = sum(bin(v).count("1") for u, v, w in terms)
    bw = sum(bin(w).count("1") for u, v, w in terms)
    bits = bu + bv + bw
    outputs = n * p
    mults = r
    adds = (bu - r) + (bv - r) + (bw - outputs)
    total = mults + adds
    # asymptotic exponent for a SQUARE format only (recursion is well-defined there)
    omega = math.log(r) / math.log(n) if (n == m == p and r > 1) else float("nan")
    return dict(rank=r, bits=bits, mults=mults, adds=adds, ops=total, omega=omega)


def bench_file(path, n, m, p, do_verify):
    terms = parse_scheme(path)
    if not terms:
        return None
    c = cost(terms, n, m, p)
    c["name"] = os.path.basename(path)
    if do_verify:
        c["valid"] = verify(terms, n, m, p)
    return c


def print_table(rows):
    rows = [r for r in rows if r]
    # rank the "actual most performant" by base-case op count (ascending)
    rows.sort(key=lambda r: r["ops"])
    hdr = f"{'scheme':<40} {'rank':>5} {'bits':>6} {'mults':>6} {'adds':>7} {'OPS':>7} {'omega':>7}"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        om = f"{r['omega']:.3f}" if r["omega"] == r["omega"] else "  -  "
        v = "" if "valid" not in r else ("  [valid]" if r["valid"] else "  [INVALID!]")
        print(f"{r['name']:<40} {r['rank']:>5} {r['bits']:>6} {r['mults']:>6} "
              f"{r['adds']:>7} {r['ops']:>7} {om:>7}{v}")
    print()
    print("OPS = base-case GF(2) op count (mults+adds, no CSE) = bits - rank - outputs; lower is faster")
    print("omega = log_n(rank) = asymptotic exponent for recursion on large matrices; lower is faster")


# ---- live watcher: perf-curve of a running search ---------------------------
def watch(run_dir, n, m, p):
    """Watch a run dir; on each new fleet-best rank, benchmark it and append to
    perf_curve.csv, so you can see whether descending rank tracks ops up or down."""
    canonical = os.path.join(run_dir, "current_best.txt")
    curve = os.path.join(run_dir, "perf_curve.csv")
    if not os.path.exists(curve):
        with open(curve, "w") as f:
            f.write("time,rank,bits,mults,adds,ops,omega\n")
    seen = None
    print(f"watching {canonical} -> {curve}", flush=True)
    while True:
        try:
            terms = parse_scheme(canonical)
        except Exception:
            terms = None
        if terms and len(terms) != seen:
            seen = len(terms)
            c = cost(terms, n, m, p)
            line = (f"{time.strftime('%H:%M:%S')},{c['rank']},{c['bits']},{c['mults']},"
                    f"{c['adds']},{c['ops']},{c['omega']:.4f}")
            with open(curve, "a") as f:
                f.write(line + "\n")
            print(f"NEW BEST rank={c['rank']} bits={c['bits']} ops={c['ops']} "
                  f"omega={c['omega']:.3f}", flush=True)
        time.sleep(3)


def main():
    args = sys.argv[1:]
    n = m = p = 5
    if "--n" in args:
        i = args.index("--n"); n = m = p = int(args[i + 1]); del args[i:i + 2]
    do_verify = "--verify" in args
    args = [a for a in args if a != "--verify"]
    if "--watch" in args:
        i = args.index("--watch")
        watch(args[i + 1], n, m, p)
        return
    add_naive = "--naive" in args
    files = [a for a in args if not a.startswith("--")]
    rows = []
    if add_naive:
        c = cost(naive_scheme(n, m, p), n, m, p)
        c["name"] = f"naive <{n},{m},{p}>"
        if do_verify:
            c["valid"] = True
        rows.append(c)
    for f in files:
        rows.append(bench_file(f, n, m, p, do_verify))
    print_table(rows)


if __name__ == "__main__":
    main()
