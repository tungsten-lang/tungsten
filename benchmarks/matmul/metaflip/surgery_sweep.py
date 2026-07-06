"""Beam sweep for SAT-guided local rank surgery.

This is the scaled version of sat_surgery.py: scan a pool of record-rank
schemes, dedupe them, generate k-term local replacement candidates with a
beam over partial-tensor support, and ask whether k terms can be replaced by
k-1 terms. A SAT hit writes a reduced exact-valid scheme and exits.

Usage:
  python3 surgery_sweep.py <n> <m> <p> <glob-or-dir-or-file> [...]

Examples:
  python3 surgery_sweep.py 4 4 4 records/444 --budget-s 300 --kmax 6
  python3 surgery_sweep.py 5 5 5 'records/555_ties/*.txt' --budget-s 900
"""
from __future__ import annotations

import argparse
import glob
import os
import sys
import time

from metaflip_proto2 import T, recon
from sat_surgery import decode_model, expand, read_scheme, run_z3, smt_for


def pc(x):
    return bin(x).count("1")


def normalize_terms(terms):
    s = set()
    for t in terms:
        if not (t[0] and t[1] and t[2]):
            continue
        if t in s:
            s.remove(t)
        else:
            s.add(t)
    return tuple(sorted(s))


def scheme_bits(terms):
    return sum(pc(u) + pc(v) + pc(w) for u, v, w in terms)


def expand_inputs(inputs):
    paths = []
    for item in inputs:
        if os.path.isdir(item):
            paths.extend(glob.glob(os.path.join(item, "*.txt")))
            paths.extend(glob.glob(os.path.join(item, "*")))
        else:
            matches = glob.glob(item)
            paths.extend(matches if matches else [item])
    out = []
    seen = set()
    for path in sorted(paths):
        if path in seen or not os.path.isfile(path):
            continue
        seen.add(path)
        out.append(path)
    return out


def load_valid_schemes(paths, n, m, p, limit=None):
    target = T(n, m, p)
    seen = set()
    schemes = []
    for path in paths:
        try:
            terms = normalize_terms(read_scheme(path))
        except Exception as exc:
            print(f"skip {path}: parse failed: {exc}", flush=True)
            continue
        if not terms:
            continue
        if terms in seen:
            continue
        seen.add(terms)
        if recon(set(terms), n, m, p) != target:
            print(f"skip {path}: exact validation failed", flush=True)
            continue
        schemes.append((scheme_bits(terms), path, terms))
    schemes.sort(key=lambda x: (len(x[2]), x[0], x[1]))
    if limit is not None:
        schemes = schemes[:limit]
    return schemes


def factor_overlap_score(a, b):
    score = 0
    if a[0] == b[0]:
        score += 5
    if a[1] == b[1]:
        score += 5
    if a[2] == b[2]:
        score += 5
    # Partial mask intersections are weaker than exact shared factors but
    # still a useful local-cancellation signal.
    score += pc(a[0] & b[0]) + pc(a[1] & b[1]) + pc(a[2] & b[2])
    return score


def beam_candidates(terms, exp, kmax=6, beam=300, per_k=120, pair_seed=None):
    """Return [(support, subset)] ordered by increasing partial support.

    The beam state stores the XOR expansion for each subset, so extending a
    candidate is cheap. We seed it with both low-support pairs and high factor
    overlap pairs; that keeps the search from being only a duplicate of the
    one-shot sat_surgery.py heuristic.
    """
    nterms = len(terms)
    if pair_seed is None:
        pair_seed = max(beam * 4, per_k * 8)
    pairs = []
    for i in range(nterms):
        for j in range(i + 1, nterms):
            p = exp[i] ^ exp[j]
            support = pc(p)
            overlap = factor_overlap_score(terms[i], terms[j])
            pairs.append((support, -overlap, (i, j), p))
    pairs_by_support = sorted(pairs, key=lambda x: (x[0], x[1], x[2]))
    pairs_by_overlap = sorted(pairs, key=lambda x: (x[1], x[0], x[2]))

    state = {}
    for row in pairs_by_support[:pair_seed] + pairs_by_overlap[: max(per_k, beam)]:
        support, neg_overlap, subset, tensor = row
        old = state.get(subset)
        if old is None or support < old[0]:
            state[subset] = (support, tensor)

    candidates = []
    frontier = [(support, subset, tensor) for subset, (support, tensor) in state.items()]
    frontier.sort(key=lambda x: (x[0], x[1]))
    frontier = frontier[:beam]
    candidates.extend((support, subset) for support, subset, _ in frontier[:per_k])

    for k in range(3, kmax + 1):
        nxt = {}
        for _, subset, tensor in frontier:
            used = set(subset)
            start = subset[-1] + 1
            for j in range(start, nterms):
                if j in used:
                    continue
                sub2 = subset + (j,)
                p2 = tensor ^ exp[j]
                support = pc(p2)
                old = nxt.get(sub2)
                if old is None or support < old[0]:
                    nxt[sub2] = (support, p2)
        frontier = [(support, subset, tensor) for subset, (support, tensor) in nxt.items()]
        frontier.sort(key=lambda x: (x[0], x[1]))
        frontier = frontier[:beam]
        candidates.extend((support, subset) for support, subset, _ in frontier[:per_k])
        if not frontier:
            break

    seen = set()
    out = []
    for support, subset in candidates:
        if subset in seen:
            continue
        seen.add(subset)
        out.append((support, subset))
    return out


def write_reduced(path, terms):
    with open(path, "w") as f:
        f.write(str(len(terms)) + "\n")
        for u, v, w in sorted(terms):
            f.write(f"{u} {v} {w}\n")


def try_candidate(path, terms, exp, subset, n, m, p, timeout_s, out_dir):
    ab, bb, cb = n * m, m * p, n * p
    partial = 0
    for idx in subset:
        partial ^= exp[idx]
    if partial == 0:
        return "zero", None, None
    out = run_z3(smt_for(partial, len(subset) - 1, ab, bb, cb), timeout_s)
    if "unsat" in out:
        return "unsat", None, None
    if not out.startswith("sat"):
        return "timeout", None, None

    new_terms = decode_model(out, len(subset) - 1, ab, bb, cb)
    check = 0
    for term in new_terms:
        check ^= expand(term, ab, bb, cb)
    if check != partial:
        return "decode-mismatch", None, None

    reduced = [t for i, t in enumerate(terms) if i not in set(subset)] + new_terms
    reduced = normalize_terms(reduced)
    ok = recon(set(reduced), n, m, p) == T(n, m, p)
    if not ok or len(reduced) >= len(terms):
        return "bad-model", None, None

    os.makedirs(out_dir, exist_ok=True)
    base = os.path.basename(path).replace(".txt", "")
    out_path = os.path.join(out_dir, f"{base}.rank{len(reduced)}.reduced.txt")
    write_reduced(out_path, reduced)
    return "sat", out_path, len(reduced)


def sweep(args):
    paths = expand_inputs(args.inputs)
    schemes = load_valid_schemes(paths, args.n, args.m, args.p, args.limit_schemes)
    print(f"loaded {len(schemes)} unique exact-valid schemes from {len(paths)} paths", flush=True)
    if not schemes:
        return 2

    start_time = time.time()
    tried = 0
    by_verdict = {}
    for si, (bits, path, terms) in enumerate(schemes, 1):
        if time.time() - start_time >= args.budget_s:
            break
        ab, bb, cb = args.n * args.m, args.m * args.p, args.n * args.p
        exp = [expand(t, ab, bb, cb) for t in terms]
        cands = beam_candidates(
            terms,
            exp,
            kmax=args.kmax,
            beam=args.beam,
            per_k=args.per_k,
            pair_seed=args.pair_seed,
        )
        if args.dry_run:
            print(f"[{si}/{len(schemes)}] {path}: rank={len(terms)} bits={bits} candidates={len(cands)}")
            for support, subset in cands[: args.per_scheme]:
                print(f"  k={len(subset)} support={support} subset={subset}")
            continue

        print(f"[{si}/{len(schemes)}] {path}: rank={len(terms)} bits={bits} candidates={len(cands)}", flush=True)
        for support, subset in cands[: args.per_scheme]:
            elapsed = time.time() - start_time
            if elapsed >= args.budget_s:
                print("global budget exhausted", flush=True)
                print(f"tried={tried} verdicts={by_verdict}", flush=True)
                return 1
            verdict, out_path, new_rank = try_candidate(
                path, terms, exp, subset, args.n, args.m, args.p, args.z3_timeout_s, args.out_dir
            )
            tried += 1
            by_verdict[verdict] = by_verdict.get(verdict, 0) + 1
            print(
                f"  try={tried} k={len(subset)} support={support} -> {verdict}",
                flush=True,
            )
            if verdict == "sat":
                print(f"*** REDUCED {len(terms)} -> {new_rank}: {out_path}", flush=True)
                return 0
    print(f"no reduction found; tried={tried} verdicts={by_verdict}", flush=True)
    return 0 if args.dry_run else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("n", type=int)
    parser.add_argument("m", type=int)
    parser.add_argument("p", type=int)
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--budget-s", type=int, default=300)
    parser.add_argument("--z3-timeout-s", type=int, default=10)
    parser.add_argument("--kmax", type=int, default=6)
    parser.add_argument("--beam", type=int, default=300)
    parser.add_argument("--per-k", type=int, default=120)
    parser.add_argument("--pair-seed", type=int, default=None)
    parser.add_argument("--per-scheme", type=int, default=240)
    parser.add_argument("--limit-schemes", type=int, default=None)
    parser.add_argument("--out-dir", default="benchmarks/matmul/metaflip/surgery_hits")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.kmax < 2:
        parser.error("--kmax must be at least 2")
    return sweep(args)


if __name__ == "__main__":
    sys.exit(main())
