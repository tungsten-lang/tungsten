#!/usr/bin/env python3
"""Independent subset packing, pair fallback, substitution and tensor gates."""
from collections import Counter
from functools import lru_cache
from itertools import combinations, product
from pathlib import Path
import random
import sys
import tempfile

from mixed_composition_parity_test import RUNTIME, load_bank, oriented, run, store
from packed_composition_parity_test import EDGES, bits, exact, naive, parse_terms


def cost_at(costs, axis, size):
    return costs[0] if size == 1 else costs[1+3*(size-2)+axis]


def group_components(terms, costs):
    active = [any(0 < cost_at(costs, a, k) < k*costs[0] for k in range(2, 5)) for a in range(3)]
    unseen = set(range(len(terms)))
    result = []
    while unseen:
        frontier = {min(unseen)}
        group = set(frontier)
        unseen -= group
        while frontier:
            more = {j for j in unseen if any(active[a] and terms[i][a] == terms[j][a]
                                             for i in frontier for a in range(3))}
            unseen -= more
            group |= more
            frontier = more
        result.append(tuple(sorted(group)))
    return result


def optimal(terms, costs):
    total = 0
    for component in group_components(terms, costs):
        assert len(component) <= 16

        @lru_cache(None)
        def search(remaining):
            if not remaining:
                return 0
            first, *tail = remaining
            best = costs[0]+search(tuple(tail))
            for axis in range(3):
                equal = [j for j in tail if terms[j][axis] == terms[first][axis]]
                for size in range(2, 5):
                    cost = cost_at(costs, axis, size)
                    if not 0 < cost < size*costs[0]:
                        continue
                    for others in combinations(equal, size-1):
                        best = min(best, cost+search(tuple(j for j in tail if j not in others)))
            return best
        total += search(component)
    return total


def check_plan(terms, costs, line, budget):
    price, probes, fallbacks, count, pair_states, *flat = map(int, line.split())
    plan = list(zip(flat[::2], flat[1::2]))
    assert len(flat) == 2*len(terms)
    assert 0 <= probes <= budget and 0 <= pair_states <= budget
    components = group_components(terms, costs)
    assert count == len(components) and 0 <= fallbacks <= count
    groups = {}
    for i, (head, axis) in enumerate(plan):
        assert 0 <= head <= i and -1 <= axis <= 2
        assert plan[head] == (head, axis)
        groups.setdefault(head, []).append(i)
    actual = 0
    for head, members in groups.items():
        axis = plan[head][1]
        assert 1 <= len(members) <= 4
        if len(members) == 1:
            assert axis == -1
        else:
            assert axis >= 0 and len({terms[i][axis] for i in members}) == 1
        cost = cost_at(costs, axis, len(members))
        assert cost > 0
        actual += cost
    assert actual == price
    if fallbacks == 0:
        assert price == optimal(terms, costs)
    if any(len(c) > 16 for c in components):
        assert fallbacks > 0
    return price, plan, fallbacks


def context_prices(scales, leaves):
    costs = [len(leaves[tuple(sorted(scales))])]
    for size in range(2, 5):
        for axis in range(3):
            shape = tuple(d*(size if i == (2, 0, 1)[axis] else 1) for i, d in enumerate(scales))
            leaf = leaves.get(tuple(sorted(shape)))
            costs.append(len(leaf) if leaf is not None else -1)
    return costs


def expected(shape, terms, scales, leaves, plan):
    target = tuple(a*b for a, b in zip(shape, scales))
    parity = Counter()
    for head, (owner, axis) in enumerate(plan):
        if owner != head:
            continue
        members = [i for i, pair in enumerate(plan) if pair[0] == head]
        expanded = -1 if len(members) == 1 else (2, 0, 1)[axis]
        dims = tuple(d*(len(members) if i == expanded else 1) for i, d in enumerate(scales))
        maps = []
        for f, (r, c) in enumerate(EDGES):
            values = []
            for lr, lc in product(range(dims[r]), range(dims[c])):
                member = (lr//scales[r] if r == expanded else 0)+(lc//scales[c] if c == expanded else 0)
                outer = terms[members[member]][f]
                values.append(sum(1 << ((bit//shape[c]*scales[r]+lr%scales[r])*target[c]
                                       +bit%shape[c]*scales[c]+lc%scales[c]) for bit in bits(outer)))
            maps.append(values)
        for leaf in oriented(leaves, dims):
            row = []
            for f, word in enumerate(leaf):
                value = 0
                for bit in bits(word):
                    value ^= maps[f][bit]
                row.append(value)
            if all(row):
                parity[tuple(row)] += 1
    return target, sorted(t for t, n in parity.items() if n % 2)


def composition_case(binary, root, bank_id, leaves, shape, terms, scales, budget=50000, forced_axis=None):
    key, terms = store(root, shape, terms)
    output = root/'group-output.tensor'
    extra = [] if forced_axis is None else [forced_axis]
    run(binary, '--compose', root, key, bank_id, *scales, output, budget, *extra, check=True)
    costs = context_prices(scales, leaves)
    price, plan, fallback = check_plan(terms, costs, Path(str(output)+'.plan').read_text(), budget)
    if forced_axis is not None:
        assert plan == [(0, forced_axis)]*4
    target, want = expected(shape, terms, scales, leaves, plan)
    lines = output.read_text().splitlines()
    got = [tuple(int(v, 16) for v in line.split()) for line in lines[1:]]
    assert lines[0].split() == ['MFW1', *map(str, target), str(len(got))]
    assert got == want and len(got) <= price
    exact(target, got)
    return price, len(got), fallback


def check(binary, pair_binary):
    run(binary, '--bounds-test', check=True)
    rng = random.Random(20260910)
    cases = []
    for _ in range(240):
        terms = [tuple(rng.randrange(1, 8) for _ in range(3)) for _ in range(rng.randrange(1, 13))]
        costs = [rng.randrange(1, 65) for _ in range(4)]
        costs += [rng.choice([-1, rng.randrange(1, 129)]) for _ in range(6)]
        cases.append((terms, costs, 50000))
    for budget in (1, 7, 50000):
        for n in (3, 4, 16, 17, 512):
            cases.append(([(1, 1, 1)]*n, [7, 11, 11, 11, 15, 16, -1, 18, 20, -1], budget))
    cases.extend([
        ([(1, 2, 3)]*3, [7, 14, 14, 14, 18, -1, -1, -1, -1, -1], 50000),
        ([(1, 2, 3)]*4, [7, 14, 14, 14, -1, -1, -1, 20, -1, -1], 50000),
        ([(2**62+i, 2**61+i//3, 2**60+i) for i in range(96)], [20, 38, 38, 38, 54, 54, 54, 74, 74, 74], 50000),
        ([(1, 2, 3), (2, 2, 3), (1, 4, 3), (1, 4, 5), (6, 4, 5)], [20, 25, 29, 35, 42, 45, 43, 59, 65, 55], 50000),
    ])
    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-groups-') as directory:
        root = Path(directory)
        source, dest = root/'in', root/'out'
        source.write_text(''.join(' '.join(map(str, [len(t), *c, b, *(v for row in t for v in row)]))+'\n' for t, c, b in cases))
        run(binary, '--plans', source, dest, check=True)
        rows = dest.read_text().splitlines()
        assert len(rows) == len(cases)
        first = dest.read_bytes()
        run(binary, '--plans', source, dest, check=True)
        assert dest.read_bytes() == first
        source.write_text(''.join(' '.join(map(str, [len(t), *c[:4], b, *(v for row in t for v in row)]))+'\n' for t, c, b in cases))
        run(pair_binary, '--plans', source, dest, check=True)
        paired = dest.read_text().splitlines()
        fallbacks = 0
        for (terms, costs, budget), row, baseline in zip(cases, rows, paired):
            price, plan, fallback = check_plan(terms, costs, row, budget)
            old_price, _, _, _, *old_flat = map(int, baseline.split())
            assert price <= old_price
            if fallback == len(group_components(terms, costs)):
                assert price == old_price
                assert plan == [(min(i, j), a) for i, (j, a) in enumerate(zip(old_flat[::2], old_flat[1::2]))]
            fallbacks += fallback
        bank_id = run(pair_binary, '--bank', root, RUNTIME, check=True).stdout.strip().splitlines()[-1]
        leaves = load_bank(root, bank_id)
        compositions = 0
        for scales in product(range(2, 5), repeat=3):
            composition_case(binary, root, bank_id, leaves, (2, 2, 3), naive((2, 2, 3)), scales)
            compositions += 1
        for shape in ((3, 2, 2), (2, 3, 2), (2, 2, 4), (4, 2, 2), (2, 4, 2), (3, 3, 3)):
            for budget in (1, 50000):
                composition_case(binary, root, bank_id, leaves, shape, naive(shape), (2, 3, 4), budget)
                compositions += 1
        seed = RUNTIME/'seeds/gf2/matmul_3x3_rank23_d139_gf2.txt'
        terms = parse_terms(seed.read_bytes(), 23)
        for scales in ((2, 3, 4), (3, 2, 4), (4, 3, 2)):
            composition_case(binary, root, bank_id, leaves, (3, 3, 3), terms, scales)
            compositions += 1
        for axis, shape, scales in ((0, (1,1,4), (3,4,2)), (1, (4,1,1), (2,3,4)), (2, (1,4,1), (3,2,4))):
            composition_case(binary, root, bank_id, leaves, shape, naive(shape), scales, forced_axis=axis)
            compositions += 1
    print(f'PASS mixed groups: {len(cases)} plans, {fallbacks} explicit fallbacks, {compositions} full tensor replays; pair non-regression')


if __name__ == '__main__':
    check(sys.argv[1], sys.argv[2])
