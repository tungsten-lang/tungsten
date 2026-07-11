"""Restricted meet-in-the-middle local tensor surgery over GF(2).

For a selected k-term piece of an exact matrix-multiplication scheme, search
for k-1 replacement rank-one terms.  Unlike the Brent-equation SAT tools, this
enumerates a deliberately finite factor family: selected factors, their
pairwise XOR closure, and optionally nearby factors from the full scheme.

The resulting search is incomplete, but every hit is exact and independently
reconstructed after splicing.  For k<=5 the replacement has at most four
terms, so tensor signatures turn the nonlinear-looking surgery into ordinary
XOR joins:

  r=2: signature lookup over pairs
  r=3: pair + singleton lookup
  r=4: pair-sum meet-in-the-middle

This is intended as a cheap support-family scout before launching a general
SAT solve, and as the reference algorithm for a future GPU pair-sum kernel.

Examples:

  python3 mitm_surgery.py --selftest
  python3 mitm_surgery.py scheme.txt 4 4 4 --k 5 --subsets 32 --pool 700
  python3 mitm_surgery.py scheme.txt 4 4 4 --subset 0,1,2,3,4
"""

from __future__ import annotations

import argparse
import itertools
import time

from bench_decomp import parse_scheme, verify
from metaflip_proto2 import T, recon
from sat_surgery import expand


def popcount(value):
    # macOS still ships Python 3.9, which predates int.bit_count().
    return bin(value).count("1")


def tensor_xor(terms, ab, bb, cb):
    value = 0
    for term in terms:
        value ^= expand(term, ab, bb, cb)
    return value


def terms_in_bounds(terms, ab, bb, cb):
    limits = (1 << ab, 1 << bb, 1 << cb)
    return all(all(isinstance(mask, int) and 0 < mask < limit
                   for mask, limit in zip(term, limits))
               for term in terms)


def xor_fingerprint(value, width=128):
    """Return a compact linear projection of a tensor bit vector.

    Pair-sum joins only need a hash key: candidate matches are checked against
    the complete tensor signatures before they are accepted.  Rotating each
    fixed-width chunk before XOR-folding keeps this map linear, so
    ``fp(a ^ b) == fp(a) ^ fp(b)``, while avoiding a full n^6-bit dictionary
    key for every candidate pair.
    """
    mask = (1 << width) - 1
    output = 0
    rotation = 0
    while value:
        chunk = value & mask
        if rotation:
            chunk = ((chunk << rotation) |
                     (chunk >> (width - rotation))) & mask
        output ^= chunk
        value >>= width
        rotation = (rotation + 29) % width
    return output


def _axis_pool(terms, subset, axis, nearby=0):
    """Selected factors plus pairwise XORs and optional global near neighbors."""
    selected = sorted({terms[index][axis] for index in subset})
    pool = set(selected)
    for left, right in itertools.combinations(selected, 2):
        merged = left ^ right
        if merged:
            pool.add(merged)
    if nearby:
        outside = sorted(
            {term[axis] for term in terms} - pool,
            key=lambda value: (
                min(popcount(value ^ base) for base in selected),
                popcount(value), value,
            ),
        )
        pool.update(outside[:nearby])
    return sorted(pool)


def candidate_terms(terms, subset, ab, bb, cb, limit=700, nearby=2):
    """Return a connectivity-biased finite rank-one candidate family."""
    pools = [_axis_pool(terms, subset, axis, nearby) for axis in range(3)]
    selected_axes = [{terms[index][axis] for index in subset} for axis in range(3)]

    def distance(term):
        return sum(min(popcount(term[axis] ^ base)
                       for base in selected_axes[axis]) for axis in range(3))

    candidates = list(itertools.product(*pools))
    candidates.sort(key=lambda term: (
        distance(term),
        sum(popcount(mask) for mask in term),
        term,
    ))
    # Ensure the selected terms survive any cap even if density sorting moves
    # them later; they are useful anchors in pair/triple joins.
    chosen = []
    seen = set()
    for term in [terms[index] for index in subset] + candidates:
        if term not in seen and all(term):
            seen.add(term)
            chosen.append(term)
        if len(chosen) >= limit:
            break
    return chosen


def find_xor_decomposition(target, candidates, ab, bb, cb, rank):
    """Find `rank` distinct candidate signatures XORing to target, or None."""
    signatures = [expand(term, ab, bb, cb) for term in candidates]
    fingerprints = [xor_fingerprint(signature) for signature in signatures]
    target_fingerprint = xor_fingerprint(target)
    by_signature = {}
    for index, signature in enumerate(signatures):
        by_signature.setdefault(signature, []).append(index)

    if rank == 1:
        indices = by_signature.get(target)
        return [candidates[indices[0]]] if indices else None

    if rank == 2:
        for left, signature in enumerate(signatures):
            for right in by_signature.get(target ^ signature, ()):
                if right != left:
                    return [candidates[left], candidates[right]]
        return None

    if rank == 3:
        for left in range(len(candidates)):
            for right in range(left + 1, len(candidates)):
                want = target ^ signatures[left] ^ signatures[right]
                for third in by_signature.get(want, ()):
                    if third != left and third != right:
                        return [candidates[left], candidates[right], candidates[third]]
        return None

    if rank == 4:
        # Store compact linear fingerprints rather than full n^6-bit pair
        # sums.  At 6x6/pool=700 this cuts peak RSS from roughly 0.95 GiB to a
        # small fraction of that.  Full signatures reject fingerprint
        # collisions, so compression cannot create a false hit.
        #
        # Keep a few representatives per key: an exact complement may share an
        # endpoint with the first pair but be disjoint from a later one.
        pair_sums = {}
        for left in range(len(candidates)):
            for right in range(left + 1, len(candidates)):
                signature = signatures[left] ^ signatures[right]
                fingerprint = fingerprints[left] ^ fingerprints[right]
                complement = target_fingerprint ^ fingerprint
                for a, b in pair_sums.get(complement, ()):
                    if (len({left, right, a, b}) == 4 and
                            signatures[a] ^ signatures[b] ^ signature == target):
                        return [candidates[a], candidates[b],
                                candidates[left], candidates[right]]
                bucket = pair_sums.setdefault(fingerprint, [])
                if len(bucket) < 16:
                    bucket.append((left, right))
        return None

    raise ValueError("meet-in-the-middle reference supports replacement rank <= 4")


def verify_replacement(original, subset, replacement, n, m, p):
    """Splice and fully verify a candidate; return canonical terms or None."""
    ab, bb, cb = n * m, m * p, n * p
    target = tensor_xor((original[index] for index in subset), ab, bb, cb)
    if tensor_xor(replacement, ab, bb, cb) != target:
        return None
    removed = set(subset)
    parity = set()
    for term in [term for index, term in enumerate(original) if index not in removed] + list(replacement):
        if not all(term):
            continue
        parity.discard(term) if term in parity else parity.add(term)
    if len(parity) >= len(original):
        return None
    if recon(parity, n, m, p) != T(n, m, p):
        return None
    return sorted(parity)


def subset_score(terms, subset):
    unions = [0, 0, 0]
    for index in subset:
        for axis in range(3):
            unions[axis] |= terms[index][axis]
    support = sum(popcount(mask) for mask in unions)
    adjacency = 0
    for left, right in itertools.combinations(subset, 2):
        adjacency += sum(popcount(terms[left][axis] ^ terms[right][axis])
                         for axis in range(3))
    return support, adjacency, subset


def guided_subsets(terms, k, count):
    """Small deterministic beam of close k-subsets without enumerating C(r,k)."""
    width = max(count * 4, 64)
    level = sorted(itertools.combinations(range(len(terms)), 2),
                   key=lambda sub: subset_score(terms, sub))[:width]
    for size in range(3, k + 1):
        expanded = set()
        for subset in level:
            for index in range(len(terms)):
                if index not in subset:
                    expanded.add(tuple(sorted(subset + (index,))))
        level = sorted(expanded, key=lambda sub: subset_score(terms, sub))[:width]
    return level[:count]


def search_scheme(path, n, m, p, k=5, subset_count=32, pool=700,
                  nearby=2, explicit_subset=None, log=print):
    raw_terms = parse_scheme(path)
    terms = sorted(set(raw_terms))
    ab, bb, cb = n * m, m * p, n * p
    if len(terms) != len(raw_terms) or not terms_in_bounds(terms, ab, bb, cb):
        raise ValueError("input scheme has duplicate, zero, or out-of-range factors")
    if not verify(terms, n, m, p):
        raise ValueError("input scheme is not exact")
    subsets = [tuple(explicit_subset)] if explicit_subset is not None else guided_subsets(
        terms, k, subset_count)
    started = time.monotonic()
    for ordinal, subset in enumerate(subsets, 1):
        candidates = candidate_terms(terms, subset, ab, bb, cb, pool, nearby)
        target = tensor_xor((terms[index] for index in subset), ab, bb, cb)
        replacement = find_xor_decomposition(target, candidates, ab, bb, cb, k - 1)
        if replacement:
            reduced = verify_replacement(terms, subset, replacement, n, m, p)
            if reduced is not None:
                log(f"MITM HIT subset={subset} pool={len(candidates)} "
                    f"rank {len(terms)} -> {len(reduced)}")
                return reduced
        log(f"subset {ordinal}/{len(subsets)} {subset} pool={len(candidates)} miss")
    log(f"MITM MISS tested={len(subsets)} elapsed={time.monotonic() - started:.3f}s")
    return None


def selftest():
    # A deterministic planted 5->4 problem.  The selected factors' XOR closure
    # contains the four generators, while the fifth selected term is their XOR
    # tensor sum expressed as two split terms plus a cancellation pair.
    ab = bb = cb = 4
    replacement = [
        (1, 1, 1), (2, 2, 2), (4, 4, 4), (8, 8, 8),
    ]
    target = tensor_xor(replacement, ab, bb, cb)
    candidates = list(replacement) + [
        (3, 1, 1), (1, 3, 1), (1, 1, 3), (5, 5, 5),
    ]
    found = find_xor_decomposition(target, candidates, ab, bb, cb, 4)
    assert found is not None
    assert tensor_xor(found, ab, bb, cb) == target

    # Exercise the r=3 join independently.
    target3 = tensor_xor(replacement[:3], ab, bb, cb)
    found3 = find_xor_decomposition(target3, candidates, ab, bb, cb, 3)
    assert found3 is not None
    assert tensor_xor(found3, ab, bb, cb) == target3
    print("mitm surgery selftest ok")


def emit_bare(terms, path):
    with open(path, "w") as stream:
        stream.write(f"{len(terms)}\n")
        for u, v, w in terms:
            stream.write(f"{u} {v} {w}\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scheme", nargs="?")
    parser.add_argument("n", nargs="?", type=int)
    parser.add_argument("m", nargs="?", type=int)
    parser.add_argument("p", nargs="?", type=int)
    parser.add_argument("--k", type=int, default=5)
    parser.add_argument("--subsets", type=int, default=32)
    parser.add_argument("--pool", type=int, default=700)
    parser.add_argument("--nearby", type=int, default=2)
    parser.add_argument("--subset", help="comma-separated explicit term indices")
    parser.add_argument("--out")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        selftest()
        return
    if not args.scheme or None in (args.n, args.m, args.p):
        parser.error("scheme and n m p are required")
    if not 2 <= args.k <= 5:
        parser.error("--k must be 2..5")
    explicit = None
    if args.subset:
        explicit = tuple(int(value) for value in args.subset.split(","))
        if len(explicit) != args.k:
            parser.error("--subset length must equal --k")
    hit = search_scheme(args.scheme, args.n, args.m, args.p, args.k,
                        args.subsets, args.pool, args.nearby, explicit)
    if hit is not None and args.out:
        emit_bare(hit, args.out)


if __name__ == "__main__":
    main()
