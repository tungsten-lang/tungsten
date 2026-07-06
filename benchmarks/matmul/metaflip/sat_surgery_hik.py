"""SAT surgery, k=5..8: local re-decomposition of k scheme terms by k-1 terms.

This extends the validated k<=4 tool (sat_surgery.py) to higher k. For a GF(2)
scheme and a k-subset K of its terms, form the partial tensor P = XOR of K's
rank-1 expansions, then ask z3 whether P has GF(2) tensor rank <= k-1. A hit
anywhere replaces K with k-1 terms and drops the whole scheme's rank by one
(no shared factors needed -> works where the flip graph is isolated, which
every known rank-47 <4,4,4> scheme is).

Differences vs the original k<=4 tool, all deliberate:

  * Subset selection generalized to any k via a BEAM SEARCH, ranked by two
    complementary heuristics that are merged/deduped per k:
      (a) smallest joint COORDINATE support (fewest distinct A/B/C coords the
          k terms touch; popcount of the partial tensor breaks ties), and
      (b) factor ADJACENCY (sum of pairwise Hamming distances of the u/v/w
          masks -> prefers subsets whose terms are structurally close).
    C(47,k) is astronomical, so this is a guided sample. Coverage (subsets
    tested vs the C(47,k) total) is reported per k -- no silent truncation.

  * The z3 encoding asks the true "rank <= k-1" question: R = k-1 term slots
    that MAY be zero (the original forbade zero terms). This is sound AND
    complete for tensor rank <= k-1, and is strictly MORE permissive than the
    original, so it can never miss a reduction the original would have found
    (and it additionally catches rank <= k-2 drops the original's nonzero
    constraint hid). Only the subset SAMPLE is incomplete, never the per-subset
    rank test.

  * Lex symmetry-breaking over the interchangeable term slots. Sound and
    complete; turns k=7 UNSAT proofs from ~60s (timeout) into ~1s.

Every SAT hit is spliced back into the full scheme and re-validated
(recon(new_scheme) == T AND rank == R0-1) before it is believed -- a "SAT"
that does not verify to a genuine lower-rank tensor is reported as a phantom
and the hunt continues.

Usage:
  python3 sat_surgery_hik.py --selftest
  python3 sat_surgery_hik.py <schemefile> <n> <m> <p>
        [--kmin 5 --kmax 8 --beam 600 --perk 250 --timeout 45 --no-symbreak]
  python3 sat_surgery_hik.py --hunt        # sweep the sparsest known 47s
"""
import argparse
import contextlib
import functools
import io
import itertools
import os
import sys
import time
from math import comb

import z3

from metaflip_proto2 import T, recon
from sat_surgery import expand, read_scheme
from sat_surgery import selftest as orig_selftest

SCHEME47 = "/Users/erik/tungsten/benchmarks/matmul/search/scheme47.txt"
RECORDS = "/Users/erik/tungsten/benchmarks/matmul/metaflip/records/444"
# sparsest-first (bits/term): AlphaTensor 9.57, cpu16 10.94, cpu10 13.87, cpu3 14.21
HUNT_SCHEMES = [
    f"{RECORDS}/at_f2.txt",
    f"{RECORDS}/cpu16_1.txt",
    f"{RECORDS}/cpu10_1.txt",
    f"{RECORDS}/cpu3_1.txt",
]


# --------------------------------------------------------------------------
# scheme + partial-tensor helpers
# --------------------------------------------------------------------------
def load_terms(path):
    """Read a scheme file, XOR-canonicalize duplicate terms, return sorted list."""
    S = set()
    for t in read_scheme(path):
        S.discard(t) if t in S else S.add(t)
    return sorted(S)


def coord_support(terms, sub):
    """Distinct A + B + C coordinates the k terms of `sub` collectively touch."""
    u = v = w = 0
    for i in sub:
        tu, tv, tw = terms[i]
        u |= tu
        v |= tv
        w |= tw
    return bin(u).count("1") + bin(v).count("1") + bin(w).count("1")


def factor_adjacency(terms, sub):
    """Sum of pairwise Hamming distances of the u/v/w masks (lower = closer)."""
    s = 0
    L = list(sub)
    for x in range(len(L)):
        ax = terms[L[x]]
        for y in range(x + 1, len(L)):
            ay = terms[L[y]]
            s += (bin(ax[0] ^ ay[0]).count("1")
                  + bin(ax[1] ^ ay[1]).count("1")
                  + bin(ax[2] ^ ay[2]).count("1"))
    return s


def partial_tensor(exp, sub):
    P = 0
    for i in sub:
        P ^= exp[i]
    return P


# --------------------------------------------------------------------------
# guided candidate generation: two beams (coord-support, factor-adjacency)
# --------------------------------------------------------------------------
def _beam(terms, kmax, beam, score):
    """Beam search over increasing-size subsets, ranked by `score` (lower first).

    Returns {k: [(score, subset), ...]} for k in 2..kmax. Extension is
    unconstrained (any not-yet-included term) with frozen-subset dedup, so it
    is a proper beam, not a canonical-order greedy chain.
    """
    R0 = len(terms)
    levels = {2: sorted(((score(sub), sub)
                         for sub in itertools.combinations(range(R0), 2)),
                        key=lambda x: x[0])[:beam]}
    for k in range(3, kmax + 1):
        seen, ch = set(), []
        for _, sub in levels[k - 1]:
            for l in range(R0):
                if l in sub:
                    continue
                ns = tuple(sorted(sub + (l,)))
                if ns in seen:
                    continue
                seen.add(ns)
                ch.append((score(ns), ns))
        ch.sort(key=lambda x: x[0])
        levels[k] = ch[:beam]
    return levels


def gen_candidates(terms, exp, kmin, kmax, beam, perk):
    """Merge the two beams' top-`perk` per k into a deduped candidate list."""
    Lc = _beam(terms, kmax, beam,
               lambda sub: (coord_support(terms, sub),
                            bin(partial_tensor(exp, sub)).count("1")))
    La = _beam(terms, kmax, beam,
               lambda sub: (factor_adjacency(terms, sub),
                            coord_support(terms, sub)))
    out = {}
    for k in range(kmin, kmax + 1):
        seen, merged = set(), []
        for src in (Lc[k][:perk], La[k][:perk]):
            for _, sub in src:
                if sub in seen:
                    continue
                seen.add(sub)
                merged.append(sub)
        out[k] = merged
    return out


# --------------------------------------------------------------------------
# z3 solve: does partial tensor P have GF(2) tensor rank <= R ?
# --------------------------------------------------------------------------
def _lex_le(A, B):
    """A <=_lex B for equal-length bool lists (first element most significant)."""
    bvA = z3.Concat([z3.If(x, z3.BitVecVal(1, 1), z3.BitVecVal(0, 1)) for x in A])
    bvB = z3.Concat([z3.If(x, z3.BitVecVal(1, 1), z3.BitVecVal(0, 1)) for x in B])
    return z3.ULE(bvA, bvB)


def solve_partial(P, R, AB, BB, CB, timeout_ms, symbreak=True, want_model=False):
    """Return ('sat'|'unsat'|'timeout', model_or_None).

    Brent equations over the full AB*BB*CB cube: for each cell,
    XOR_t (u_t[a] & v_t[b] & w_t[c]) == P[cell]. R term slots, each allowed to
    be zero -> this is exactly the decision 'tensor rank of P <= R over GF(2)'.
    Lex symmetry-breaking orders the interchangeable slots.
    """
    s = z3.Solver()
    s.set("timeout", int(timeout_ms))
    U = [[z3.Bool(f"u{t}_{a}") for a in range(AB)] for t in range(R)]
    V = [[z3.Bool(f"v{t}_{b}") for b in range(BB)] for t in range(R)]
    W = [[z3.Bool(f"w{t}_{c}") for c in range(CB)] for t in range(R)]
    for a in range(AB):
        for b in range(BB):
            base = (a * BB + b) * CB
            for c in range(CB):
                tl = [z3.And(U[t][a], V[t][b], W[t][c]) for t in range(R)]
                s.add(functools.reduce(z3.Xor, tl) == bool((P >> (base + c)) & 1))
    if symbreak and R >= 2:
        for t in range(R - 1):
            s.add(_lex_le(U[t] + V[t] + W[t], U[t + 1] + V[t + 1] + W[t + 1]))
    r = s.check()
    if r == z3.sat:
        if not want_model:
            return "sat", None
        mdl = s.model()
        new = []
        for t in range(R):
            u = sum(1 << a for a in range(AB) if z3.is_true(mdl.eval(U[t][a], model_completion=True)))
            v = sum(1 << b for b in range(BB) if z3.is_true(mdl.eval(V[t][b], model_completion=True)))
            w = sum(1 << c for c in range(CB) if z3.is_true(mdl.eval(W[t][c], model_completion=True)))
            new.append((u, v, w))
        return "sat", new
    if r == z3.unsat:
        return "unsat", None
    return "timeout", None  # z3 'unknown' == hit the timeout


# --------------------------------------------------------------------------
# splice a hit back into the full scheme and re-validate
# --------------------------------------------------------------------------
def verify_reduction(terms, sub, new_terms, n, m, p):
    """Return (reduced_set, note). reduced_set is None on any failure."""
    AB, BB, CB = n * m, m * p, n * p
    P = partial_tensor([expand(t, AB, BB, CB) for t in terms], sub)
    chk = 0
    for t in new_terms:
        chk ^= expand(t, AB, BB, CB)
    if chk != P:
        return None, "decode-xor-mismatch"
    subset = set(sub)
    reduced = [t for i, t in enumerate(terms) if i not in subset] + list(new_terms)
    Sr = set()
    for t in reduced:
        if not (t[0] and t[1] and t[2]):
            continue  # a zero term contributes nothing
        Sr.discard(t) if t in Sr else Sr.add(t)
    if recon(Sr, n, m, p) != T(n, m, p):
        return None, "recon-mismatch"
    return Sr, f"rank={len(Sr)}"


# --------------------------------------------------------------------------
# driver
# --------------------------------------------------------------------------
def surgery(path, n, m, p, kmin=5, kmax=8, beam=600, perk=250,
            timeout_s=45, symbreak=True, log=print):
    AB, BB, CB = n * m, m * p, n * p
    terms = load_terms(path)
    assert recon(set(terms), n, m, p) == T(n, m, p), "input scheme invalid"
    R0 = len(terms)
    exp = [expand(t, AB, BB, CB) for t in terms]
    log(f"{os.path.basename(path)}: rank {R0}  k={kmin}..{kmax}  beam={beam} "
        f"perk={perk} timeout={timeout_s}s symbreak={symbreak}", flush=True)

    t_gen = time.time()
    cands = gen_candidates(terms, exp, kmin, kmax, beam, perk)
    log(f"  candidate generation: {time.time() - t_gen:.1f}s", flush=True)

    hit = None
    for k in range(kmin, kmax + 1):
        subs = cands[k]
        total = comb(R0, k)
        frac = len(subs) / total
        log(f"== k={k}: testing {len(subs)} guided subsets of C({R0},{k})="
            f"{total:,}  (coverage {frac:.2e}) ==", flush=True)
        cu = cs = ct = cz = 0
        t_k = time.time()
        for idx, sub in enumerate(subs):
            P = partial_tensor(exp, sub)
            if P == 0:
                cz += 1  # k terms already XOR to zero -> potential k-drop; verify
                Sr, note = verify_reduction(terms, sub, [], n, m, p)
                if Sr is not None and len(Sr) < R0:
                    log(f"  *** k={k} subset#{idx} {sub} XORs to ZERO -> "
                        f"VERIFIED {note} < {R0}", flush=True)
                    return _save_hit(path, k, sub, Sr, log)
                continue
            verdict, model = solve_partial(P, k - 1, AB, BB, CB,
                                           timeout_s * 1000, symbreak, want_model=True)
            if verdict == "sat":
                cs += 1
                Sr, note = verify_reduction(terms, sub, model, n, m, p)
                if Sr is not None and len(Sr) < R0:
                    log(f"  *** k={k} subset#{idx} {sub} SAT -> VERIFIED {note} < {R0}",
                        flush=True)
                    return _save_hit(path, k, sub, Sr, log)
                log(f"  !! k={k} subset#{idx} {sub} SAT but verify FAILED "
                    f"({note}) -- phantom, continuing", flush=True)
            elif verdict == "unsat":
                cu += 1
            else:
                ct += 1
            if (idx + 1) % 50 == 0:
                log(f"    ...{idx + 1}/{len(subs)}  unsat={cu} sat={cs} "
                    f"timeout={ct} ({time.time() - t_k:.0f}s)", flush=True)
        log(f"  k={k} DONE: unsat={cu} sat={cs} timeout={ct} zero={cz}  "
            f"({time.time() - t_k:.0f}s)  [timeouts are NOT proofs]", flush=True)
    log("  no verified rank reduction found", flush=True)
    return hit


def _save_hit(path, k, sub, Sr, log):
    outp = f"{path}.reduced_k{k}.txt"
    with open(outp, "w") as f:
        for u, v, w in sorted(Sr):
            f.write(f"R {u} {v} {w}\n")
    log(f"  *** saved rank-{len(Sr)} scheme to {outp}", flush=True)
    return (k, sub, outp, len(Sr))


# --------------------------------------------------------------------------
# validation gate
# --------------------------------------------------------------------------
def selftest(log=print):
    ok = True

    log("[1] original sat_surgery.py --selftest (split a term, re-merge)...")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r1 = orig_selftest()
    log(f"    -> {'PASS' if r1 else 'FAIL'}")
    ok &= r1

    log("[2] plant a k=5 merge -> the k=5 path must return SAT at rank 4...")
    naive = [(1 << (i * 4 + j), 1 << (j * 4 + k), 1 << (i * 4 + k))
             for (i, j, k) in [(0, 0, 0), (1, 1, 1), (2, 2, 2), (3, 3, 3)]]
    u, v, w = naive[0]
    five = [(u, v, w ^ 2), (u, v, 2)] + naive[1:]  # split term 0's w = w1 ^ w2
    assert len(set(five)) == 5 and all(a and b and c for a, b, c in five)
    P = 0
    for t in five:
        P ^= expand(t, 16, 16, 16)
    verdict, model = solve_partial(P, 4, 16, 16, 16, 30000, True, want_model=True)
    chk = 0
    for t in (model or []):
        chk ^= expand(t, 16, 16, 16)
    r2 = verdict == "sat" and chk == P
    log(f"    -> {verdict}, decode_xor==P: {chk == P}  {'PASS' if r2 else 'FAIL'}")
    ok &= r2

    log("[3] reproduce known negative: k=2,3,4 UNSAT on scheme47.txt...")
    terms = load_terms(SCHEME47)
    exp = [expand(t, 16, 16, 16) for t in terms]
    r3 = True
    for k in (2, 3, 4):
        subs = gen_candidates(terms, exp, k, k, 200, 30)[k]
        vs = {"sat": 0, "unsat": 0, "timeout": 0}
        for sub in subs:
            P = partial_tensor(exp, sub)
            if P == 0:
                continue
            verdict, _ = solve_partial(P, k - 1, 16, 16, 16, 30000, True)
            vs[verdict] += 1
        allunsat = vs["sat"] == 0 and vs["timeout"] == 0
        log(f"    k={k}: {len(subs)} subsets -> unsat={vs['unsat']} "
            f"sat={vs['sat']} timeout={vs['timeout']}  {'ok' if allunsat else 'REGRESSION'}")
        r3 &= allunsat
    log(f"    -> {'PASS' if r3 else 'FAIL'}")
    ok &= r3

    log(f"SELFTEST {'PASS' if ok else 'FAIL'}")
    return ok


# --------------------------------------------------------------------------
# cli
# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scheme", nargs="?")
    ap.add_argument("n", nargs="?", type=int)
    ap.add_argument("m", nargs="?", type=int)
    ap.add_argument("p", nargs="?", type=int)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--hunt", action="store_true")
    ap.add_argument("--kmin", type=int, default=5)
    ap.add_argument("--kmax", type=int, default=8)
    ap.add_argument("--beam", type=int, default=600)
    ap.add_argument("--perk", type=int, default=250)
    ap.add_argument("--timeout", type=int, default=45)
    ap.add_argument("--no-symbreak", action="store_true")
    a = ap.parse_args()

    if a.selftest:
        sys.exit(0 if selftest() else 1)

    if a.hunt:
        overall = None
        for sch in HUNT_SCHEMES:
            if not os.path.exists(sch):
                print(f"skip missing {sch}", flush=True)
                continue
            print("\n" + "=" * 70, flush=True)
            h = surgery(sch, 4, 4, 4, a.kmin, a.kmax, a.beam, a.perk,
                        a.timeout, not a.no_symbreak)
            if h:
                overall = (sch, h)
                print(f"\n*** RANK REDUCTION on {sch}: {h}", flush=True)
                break
        print(f"\nHUNT RESULT: {overall or 'no reduction (bounded coverage)'}", flush=True)
        sys.exit(0)

    surgery(a.scheme, a.n, a.m, a.p, a.kmin, a.kmax, a.beam, a.perk,
            a.timeout, not a.no_symbreak)


if __name__ == "__main__":
    main()
