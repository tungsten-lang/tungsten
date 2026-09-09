#!/usr/bin/env python3
"""Independent matching oracle, leaf audit, linear maps and full GF(2) replay."""
from collections import Counter
from functools import lru_cache
from hashlib import sha256
from itertools import combinations_with_replacement, permutations, product
from pathlib import Path
import random
import subprocess
import sys
import tempfile

from packed_composition_parity_test import ROOT, EDGES, bits, exact, naive, orient, parse_terms
from group_composition_parity_test import narrow

RUNTIME = ROOT / 'bits/tungsten-metaflip/lib/metaflip'
SHAPES = list(combinations_with_replacement(range(2, 5), 3)) + [
    (a, b, c) for c in (6, 8) for a, b in combinations_with_replacement(range(2, 5), 2)]
RANKS = [7, 11, 14, 15, 20, 26, 23, 29, 38, 47,
         21, 30, 40, 44, 54, 73, 28, 40, 52, 58, 74, 94]


def run(binary, *args, **kwargs):
    return subprocess.run([binary, *map(str, args)], capture_output=True, text=True,
                          timeout=60, **kwargs)


def components(terms, costs):
    unseen = set(range(len(terms)))
    groups = []
    while unseen:
        group = {min(unseen)}
        frontier = set(group)
        unseen -= group
        while frontier:
            more = {j for j in unseen if any(
                terms[i][a] == terms[j][a] and costs[a+1] < 2*costs[0]
                for i in frontier for a in range(3))}
            unseen -= more
            group |= more
            frontier = more
        groups.append(sorted(group))
    return groups


def optimal(terms, costs):
    answer = 0
    for group in components(terms, costs):
        assert len(group) <= 16

        @lru_cache(None)
        def search(remaining):
            if not remaining:
                return 0
            first, *tail = remaining
            best = costs[0]+search(tuple(tail))
            for j in tail:
                choices = [costs[a+1] for a in range(3) if terms[first][a] == terms[j][a]]
                if choices:
                    best = min(best, min(choices)+search(tuple(k for k in tail if k != j)))
            return best
        answer += search(tuple(group))
    return answer


def check_plan(terms, costs, line, budget):
    price, states, fallbacks, count, *flat = map(int, line.split())
    plan = list(zip(flat[::2], flat[1::2]))
    assert len(flat) == 2*len(terms)
    assert 0 <= states <= budget
    groups = components(terms, costs)
    assert count == len(groups) and 0 <= fallbacks <= count
    actual = 0
    for i, (j, axis) in enumerate(plan):
        assert 0 <= j < len(terms) and -1 <= axis < 3
        assert plan[j] == (i, axis)
        if i == j:
            assert axis == -1
        else:
            assert axis >= 0 and terms[i][axis] == terms[j][axis]
            assert costs[axis+1] < 2*costs[0]
        if i <= j:
            actual += costs[axis+1]
    assert actual == price
    pure = [len(terms)*costs[0]]
    for axis in range(3):
        gain = max(0, 2*costs[0]-costs[axis+1])
        pure.append(len(terms)*costs[0]-gain*sum(v//2 for v in Counter(t[axis] for t in terms).values()))
    assert price <= min(pure)
    if fallbacks == 0:
        assert price == optimal(terms, costs)
    if any(len(g) > 16 for g in groups):
        assert fallbacks > 0
    return price, plan, fallbacks


def planner_tests(binary, root):
    rng = random.Random(20260909)
    cases = []
    for _ in range(300):
        n = rng.randrange(1, 17)
        terms = [tuple(rng.randrange(1, 9) for _ in range(3)) for _ in range(n)]
        costs = [rng.randrange(1, 65) for _ in range(4)]
        cases.append((terms, costs, 50000))
    for _ in range(60):
        terms = [tuple(rng.randrange(1, 6) for _ in range(3)) for _ in range(14)]
        cases.append((terms, [20, 21, 22, 23], 1))
    # Triangle, disconnected components, boundary-sized clique, oversized
    # connected graph, equal prices, and a full-rank input slab.
    for n in (1, 2, 3, 16, 17, 512):
        cases.append(([(1, 1, 1)]*n, [20, 21, 22, 23], 50000))
    cases.extend([
        ([(1, 2, 3), (1, 4, 5), (6, 4, 3)], [7, 10, 9, 8], 50000),
        ([(i//2+1, i+1, i+1) for i in range(32)], [14, 21, 26, 26], 50000),
        ([(1, 1, 1)]*16, [7, 14, 14, 14], 1),
    ])
    source, output = root/'plans.in', root/'plans.out'
    source.write_text(''.join(' '.join(map(str, [len(t), *c, b, *(v for row in t for v in row)]))+'\n'
                              for t, c, b in cases))
    run(binary, '--plans', source, output, check=True)
    rows = output.read_text().splitlines()
    assert len(rows) == len(cases)
    for (terms, costs, budget), line in zip(cases, rows):
        check_plan(terms, costs, line, budget)
    original = output.read_bytes()
    run(binary, '--plans', source, output, check=True)
    assert output.read_bytes() == original
    return len(cases)


def load_bank(root, identity):
    raw = (root/'composition/banks'/identity).read_bytes()
    assert sha256(raw).hexdigest() == identity
    fields = raw.decode().split()
    assert len(fields) == 23 and fields[0] == 'MFM_BANK1'
    assert raw == (' '.join(fields)+'\n').encode()
    result = {}
    for shape, rank, key in zip(SHAPES, RANKS, fields[1:]):
        actual, terms = narrow(root, key)
        assert actual == shape and len(terms) == rank
        result[shape] = terms
    return result


def oriented(leaves, shape):
    source = tuple(sorted(shape))
    perm = next(p for p in permutations(range(3)) if tuple(source[i] for i in p) == shape)
    return orient(source, leaves[source], perm)


def expected(shape, terms, scales, leaves, plan):
    target = tuple(x*y for x, y in zip(shape, scales))
    result = set()
    for i, (j, axis) in enumerate(plan):
        if j < i:
            continue
        expanded = -1 if i == j else (2, 0, 1)[axis]
        dims = tuple(s*(2 if k == expanded else 1) for k, s in enumerate(scales))
        maps = []
        for f, (r, c) in enumerate(EDGES):
            values = []
            for lr, lc in product(range(dims[r]), range(dims[c])):
                member = (lr//scales[r] if r == expanded else 0) + (lc//scales[c] if c == expanded else 0)
                parent = terms[(i, j)[member]][f]
                values.append(sum(1 << ((v//shape[c]*scales[r]+lr%scales[r])*target[c]
                                        +v%shape[c]*scales[c]+lc%scales[c]) for v in bits(parent)))
            maps.append(values)
        for term in oriented(leaves, dims):
            row = []
            for f, value in enumerate(term):
                mapped = 0
                for bit in bits(value):
                    mapped ^= maps[f][bit]
                row.append(mapped)
            if 0 not in row:
                row = tuple(row)
                if row in result:
                    result.remove(row)
                else:
                    result.add(row)
    return target, sorted(result)


def store(root, shape, terms):
    terms = sorted(terms)
    exact(shape, terms)
    data = (f'MFR1 {" ".join(map(str, shape))} {len(terms)}\n'
            +''.join(' '.join(map(str, row))+'\n' for row in terms)).encode()
    key = sha256(data).hexdigest()
    (root/'objects'/f'{key}.tensor').write_bytes(data)
    return key, terms


def composition_case(binary, root, identity, leaves, shape, terms, scales, budget=50000):
    key, terms = store(root, shape, terms)
    output = root/'output.tensor'
    p = run(binary, '--compose', root, key, identity, *scales, output, budget, check=True)
    dims = [scales, (scales[0], scales[1], 2*scales[2]),
            (2*scales[0], scales[1], scales[2]), (scales[0], 2*scales[1], scales[2])]
    costs = [len(leaves[tuple(sorted(d))]) for d in dims]
    price, plan, fallbacks = check_plan(terms, costs, Path(str(output)+'.plan').read_text(), budget)
    target, want = expected(shape, terms, scales, leaves, plan)
    lines = output.read_text().splitlines()
    header = lines.pop(0).split()
    got = [tuple(int(v, 16) for v in line.split()) for line in lines]
    assert header == ['MFW1', *map(str, target), str(len(want))]
    assert got == want and f'price={price} rank={len(got)} ' in p.stdout
    exact(target, got)
    return price, len(got), fallbacks


def check(binary):
    run(binary, '--bounds-test', check=True)
    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-') as directory:
        root = Path(directory)
        count = planner_tests(binary, root)
        first = run(binary, '--bank', root, RUNTIME, check=True)
        identity = first.stdout.strip().splitlines()[-1]
        leaves = load_bank(root, identity)
        again = run(binary, '--bank', root, RUNTIME, check=True)
        assert again.stdout.strip().splitlines()[-1] == identity
        seeds = RUNTIME/'seeds/gf2'
        parents = [((2, 3, 2), naive((2, 3, 2))),
                   ((2, 2, 2), naive((2, 2, 2))+[naive((2, 2, 2))[0]]*2),
                   ((2, 2, 2), naive((2, 2, 2))+[naive((2, 2, 2))[0]]*80)]
        for shape, rank, name in [
            ((2, 2, 2), 7, 'matmul_2x2_rank7_strassen_gf2.txt'),
            ((3, 3, 3), 23, 'matmul_3x3_rank23_d139_gf2.txt'),
            ((4, 4, 4), 47, 'matmul_4x4_rank47_d450_gf2.txt'),
            ((3, 5, 5), 58, 'matmul_3x5x5_rank58_d518_gf2.txt'),
        ]:
            parents.append((shape, parse_terms((seeds/name).read_bytes(), rank)))
        cases = 0
        for shape, terms in parents:
            for scales in product(range(2, 5), repeat=3):
                composition_case(binary, root, identity, leaves, shape, terms, scales)
                cases += 1
        for scales in ((2, 3, 4), (4, 4, 4), (3, 4, 2)):
            composition_case(binary, root, identity, leaves, (1, 63, 1), naive((1, 63, 1)), scales)
            cases += 1
        for scales in ((2, 3, 4), (4, 4, 4)):
            composition_case(binary, root, identity, leaves, *parents[0], scales, budget=1)
            cases += 1
        # Rehashing corrupt bytes is not a tensor certificate. Corrupt a
        # dependency and rewrite its manifest honestly; the loader must fail.
        manifest = (root/'composition/banks'/identity).read_text().split()
        raw = (root/'objects'/f'{manifest[1]}.tensor').read_text()
        rows = raw.splitlines()
        altered = [tuple(map(int, row.split())) for row in rows[1:]]
        i = next(i for i, row in enumerate(altered) if row[0] != 1)
        u, v, w = altered[i]
        altered[i] = (u ^ 1, v, w)
        # Preserve legal widths, nonzero factors and canonical ordering, so
        # this forgery can only be rejected by the complete tensor identity.
        assert all(0 < value < 16 for row in altered for value in row)
        invalid = (rows[0]+'\n'+''.join(' '.join(map(str, row))+'\n'
                                       for row in sorted(altered))).encode()
        bad_leaf = sha256(invalid).hexdigest()
        (root/'objects'/f'{bad_leaf}.tensor').write_bytes(invalid)
        manifest[1] = bad_leaf
        bad_body = (' '.join(manifest)+'\n').encode()
        bad_bank = sha256(bad_body).hexdigest()
        (root/'composition/banks'/bad_bank).write_bytes(bad_body)
        key, _ = store(root, *parents[0])
        out = root/'must-not-write.tensor'
        assert run(binary, '--compose', root, key, bad_bank, 2, 2, 2, out, 50000).returncode != 0
        assert not out.exists()
        (root/'composition/mixed-bank-latest').write_text(bad_bank+'\n')
        assert run(binary, '--bank', root, RUNTIME).returncode != 0
    print(f'PASS mixed composition: {count} matching cases; 22 exact leaves; '
          f'{cases} full tensor/term-set replays; corrupt dependencies rejected')


if __name__ == '__main__':
    check(sys.argv[1])
