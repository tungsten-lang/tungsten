"""Mine small tensor-zero rank-one circuits for metaflip escape seeds.

Candidate rank-one terms come from local factor/XOR pools (the same restricted
family used by ``mitm_surgery.py``).  Expanding each term to a GF(2) tensor
signature makes small identities hashable:

* a three-term circuit satisfies sig(a) ^ sig(b) == sig(c);
* a four-term circuit is a collision between two disjoint pair sums; and
* a five-term circuit is a collision between a disjoint pair and triple.

Circuits are independently XOR-checked, optionally C3-symmetrized, toggled into
the input scheme, and ranked by resulting rank, connectivity, density, and
term-set distance.  This is an identity *discovery* tool, not a rank proof.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import os

from bench_decomp import parse_scheme, verify
from escape_portfolio import validate_scheme_masks
from mitm_surgery import candidate_terms, guided_subsets, tensor_xor
from sym_escape import (c3_image, density, fixed_terms, flip_pair_count,
                        is_c3_closed, parity_terms, toggle_identity)


MINED_KIND_ORDER = (
    "five-circuit", "multi-split", "split", "rectangle", "composite",
)


def canonical_identity(terms):
    return tuple(sorted(parity_terms(terms)))


def c3_symmetrize(identity, n):
    terms = []
    for term in identity:
        second = c3_image(term, n)
        terms.extend((term, second, c3_image(second, n)))
    return canonical_identity(terms)


def identity_kind(identity):
    if not identity:
        return "zero"
    unique = [len({term[axis] for term in identity}) for axis in range(3)]
    if len(identity) == 3 and sorted(unique) == [1, 1, 3]:
        return "split"
    if len(identity) == 4 and unique.count(1) >= 1:
        return "rectangle"
    if len(identity) == 5:
        return "multi-split" if 1 in unique else "five-circuit"
    return "composite"


def validate_tensor_masks(terms, ab, bb, cb, label="identity"):
    """Validate the three independently-sized factor mask spaces."""
    widths = (ab, bb, cb)
    if any(not isinstance(width, int) or width <= 0 for width in widths):
        raise ValueError("tensor factor widths must be positive")
    bounds = tuple(1 << width for width in widths)
    for index, term in enumerate(terms):
        if not isinstance(term, (tuple, list)) or len(term) != 3:
            raise ValueError(f"{label} term {index} must contain three masks")
        for axis, (mask, bound) in enumerate(zip(term, bounds)):
            if not isinstance(mask, int) or mask <= 0 or mask >= bound:
                raise ValueError(
                    f"{label} term {index} axis {axis} mask {mask!r} "
                    f"is outside [1,{bound})"
                )


def independent_zero_signature(terms, ab, bb, cb):
    """Direct sparse parity reconstruction, independent of sat_surgery.expand."""
    terms = tuple(terms)
    validate_tensor_masks(terms, ab, bb, cb)
    parity = set()
    for u, v, w in terms:
        for a in range(ab):
            if not u >> a & 1:
                continue
            for b in range(bb):
                if not v >> b & 1:
                    continue
                for c in range(cb):
                    if not w >> c & 1:
                        continue
                    coordinate = (a, b, c)
                    if coordinate in parity:
                        parity.remove(coordinate)
                    else:
                        parity.add(coordinate)
    return not parity


def _signatures(candidates, ab, bb, cb):
    validate_tensor_masks(candidates, ab, bb, cb, "candidate")
    return [tensor_xor((term,), ab, bb, cb) for term in candidates]


def mine_small_circuits(candidates, ab, bb, cb, limit=1000):
    """Return unique three- and four-term zero circuits."""
    signatures = _signatures(candidates, ab, bb, cb)
    by_signature = defaultdict(list)
    for index, signature in enumerate(signatures):
        by_signature[signature].append(index)

    circuits = set()
    pair_sums = defaultdict(list)
    for left in range(len(candidates)):
        for right in range(left + 1, len(candidates)):
            signature = signatures[left] ^ signatures[right]

            for third in by_signature.get(signature, ()):
                if third != left and third != right:
                    circuit = canonical_identity(
                        (candidates[left], candidates[right], candidates[third]))
                    if (len(circuit) == 3 and
                            independent_zero_signature(circuit, ab, bb, cb)):
                        circuits.add(circuit)

            for a, b in pair_sums.get(signature, ()):
                if len({left, right, a, b}) == 4:
                    circuit = canonical_identity(
                        (candidates[a], candidates[b],
                         candidates[left], candidates[right]))
                    if (len(circuit) == 4 and
                            independent_zero_signature(circuit, ab, bb, cb)):
                        circuits.add(circuit)
            bucket = pair_sums[signature]
            if len(bucket) < 8:
                bucket.append((left, right))
            if len(circuits) >= limit:
                return sorted(circuits)
    return sorted(circuits)


def mine_five_circuits(candidates, ab, bb, cb, limit=1000):
    """Return primitive five-term circuits by a pair/triple XOR join.

    Distinct rank-one signatures cannot form a zero subset of size one or two.
    Consequently a five-element zero set is automatically a matroid circuit:
    a proper three- or four-element zero subset would leave a zero pair or
    singleton as its complement.  Requiring disjoint joins is therefore the
    complete minimality check.
    """
    signatures = _signatures(candidates, ab, bb, cb)
    pair_sums = defaultdict(list)
    for left in range(len(candidates)):
        for right in range(left + 1, len(candidates)):
            signature = signatures[left] ^ signatures[right]
            bucket = pair_sums[signature]
            # Retain several representatives because an early pair may overlap
            # a matching triple while a later pair is disjoint.
            if len(bucket) < 16:
                bucket.append((left, right))

    circuits = set()
    for left in range(len(candidates)):
        for middle in range(left + 1, len(candidates)):
            partial = signatures[left] ^ signatures[middle]
            for right in range(middle + 1, len(candidates)):
                want = partial ^ signatures[right]
                for a, b in pair_sums.get(want, ()):
                    if len({left, middle, right, a, b}) != 5:
                        continue
                    circuit = canonical_identity((
                        candidates[left], candidates[middle], candidates[right],
                        candidates[a], candidates[b],
                    ))
                    if (len(circuit) == 5 and
                            independent_zero_signature(circuit, ab, bb, cb)):
                        circuits.add(circuit)
                        if len(circuits) >= limit:
                            return sorted(circuits)
    return sorted(circuits)


def mine_circuits(candidates, ab, bb, cb, limit=1000, max_terms=5,
                  five_pool=140):
    """Return small zero circuits, with an independent cap for each size."""
    circuits = mine_small_circuits(candidates, ab, bb, cb, limit)
    if max_terms >= 5:
        circuits.extend(mine_five_circuits(
            candidates[:five_pool], ab, bb, cb, limit))
    return sorted(set(circuits))


def scheme_distance(left, right):
    return len(set(left) ^ set(right))


def score_identity(scheme, identity, n):
    validate_scheme_masks(scheme, n, "input scheme")
    validate_scheme_masks(identity, n, "identity")
    if not independent_zero_signature(identity, n * n, n * n, n * n):
        raise ValueError("mined identity has a nonzero tensor signature")
    output = toggle_identity(scheme, identity)
    validate_scheme_masks(output, n, "identity output")
    return {
        "identity": canonical_identity(identity),
        "kind": identity_kind(identity),
        "identity_terms": len(identity),
        "rank": len(output),
        "density": density(output),
        "flip_pairs": flip_pair_count(output),
        "distance": scheme_distance(scheme, output),
        "c3": is_c3_closed(output, n),
        "fixed": len(fixed_terms(output, n)),
        "output": sorted(output),
    }


def select_diverse_rows(rows, count):
    """Round-robin identity families and maximize term-set separation."""
    pools = {
        kind: [row for row in rows if row["kind"] == kind]
        for kind in MINED_KIND_ORDER
    }
    selected = []
    while len(selected) < count:
        progressed = False
        selected_sets = [set(row["output"]) for row in selected]
        for kind in MINED_KIND_ORDER:
            pool = pools[kind]
            if not pool:
                continue

            def key(row):
                current = set(row["output"])
                novelty = (min(len(current ^ old) for old in selected_sets)
                           if selected_sets else row["distance"])
                return (
                    -novelty, row["rank"], -row["flip_pairs"],
                    row["density"], row["identity"],
                )

            chosen = min(pool, key=key)
            pool.remove(chosen)
            selected.append(chosen)
            selected_sets.append(set(chosen["output"]))
            progressed = True
            if len(selected) >= count:
                break
        if not progressed:
            break
    return selected


def mine_scheme(path, n, subset_count=8, pool=240, nearby=1,
                circuit_limit=1000, include_c3=True, max_terms=5,
                five_pool=140):
    scheme = sorted(set(parse_scheme(path)))
    validate_scheme_masks(scheme, n, "input scheme")
    if not verify(scheme, n, n, n):
        raise ValueError("input scheme is not exact")
    identities = set()
    for subset in guided_subsets(scheme, 5, subset_count):
        candidates = candidate_terms(
            scheme, subset, n * n, n * n, n * n, pool, nearby)
        for identity in mine_circuits(
                candidates, n * n, n * n, n * n, circuit_limit,
                max_terms, five_pool):
            identities.add(identity)
            if include_c3:
                sym = c3_symmetrize(identity, n)
                if (sym and independent_zero_signature(
                        sym, n * n, n * n, n * n)):
                    identities.add(sym)

    rows = [score_identity(set(scheme), identity, n) for identity in identities]
    rows.sort(key=lambda row: (
        row["rank"], -row["flip_pairs"], row["density"],
        -row["distance"], row["identity"],
    ))
    return rows


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scheme")
    parser.add_argument("n", type=int)
    parser.add_argument("--subsets", type=int, default=8)
    parser.add_argument("--pool", type=int, default=240)
    parser.add_argument("--nearby", type=int, default=1)
    parser.add_argument("--limit", type=int, default=1000)
    parser.add_argument("--max-terms", type=int, choices=(4, 5), default=5)
    parser.add_argument("--five-pool", type=int, default=140,
                        help="candidate cap for the cubic five-circuit join")
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--no-c3", action="store_true")
    parser.add_argument("--bank", help="write selected exact seeds as a JSONL escape bank")
    parser.add_argument("--bank-count", type=int, default=48)
    parser.add_argument("--max-rank-delta", type=int, default=7,
                        help="maximum temporary rank increase admitted to --bank")
    args = parser.parse_args(argv)
    rows = mine_scheme(args.scheme, args.n, args.subsets, args.pool,
                       args.nearby, args.limit, not args.no_c3,
                       args.max_terms, args.five_pool)
    counts = defaultdict(int)
    for row in rows:
        counts[row["kind"]] += 1
    print(f"identities={len(rows)} kinds={dict(sorted(counts.items()))}")
    for index, row in enumerate(rows[:args.top], 1):
        print(
            f"{index:3d} kind={row['kind']:<9} id_terms={row['identity_terms']:2d} "
            f"rank={row['rank']:3d} density={row['density']:4d} "
            f"pairs={row['flip_pairs']:3d} distance={row['distance']:2d} "
            f"c3={int(row['c3'])} fixed={row['fixed']}"
        )
    if args.bank:
        from escape_portfolio import (entries_from_schemes, verify_bank,
                                      write_bank)
        base = sorted(set(parse_scheme(args.scheme)))
        eligible = [row for row in rows
                    if row["rank"] <= len(base) + args.max_rank_delta]
        selected = select_diverse_rows(eligible, args.bank_count - 1)
        entries = entries_from_schemes(
            base, (row["output"] for row in selected), args.n, "mined")
        write_bank(args.bank, entries, args.n, os.path.basename(args.scheme))
        reports = verify_bank(args.bank)
        selected_counts = defaultdict(int)
        for row in selected:
            selected_counts[row["kind"]] += 1
        print(f"wrote {args.bank}: slots={len(reports)} "
              f"kinds={dict(sorted(selected_counts.items()))}")


if __name__ == "__main__":
    main()
