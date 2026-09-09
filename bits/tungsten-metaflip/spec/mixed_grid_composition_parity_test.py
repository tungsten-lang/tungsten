#!/usr/bin/env python3
"""Independent grid/group set packing and complete substitution/tensor checks."""
from collections import Counter
from functools import lru_cache
from itertools import combinations, product
from pathlib import Path
import argparse
import os
import random
import subprocess
import tempfile

from mixed_composition_parity_test import RUNTIME, load_bank, oriented, store
from mixed_group_composition_parity_test import context_prices as group_prices
from mixed_group_composition_parity_test import cost_at as group_cost, group_components
from packed_composition_parity_test import EDGES, bits, exact, naive, parse_terms

AXES = ((0, 1), (0, 2), (1, 2))
FIXED = (1, 0, 2)
# Unique coordinate of the first and second constrained factor.
OWNERS = ((0, 2), (1, 2), (1, 0))


def run(binary, *args, grids=True):
    env = dict(os.environ, METAFLIP_TEST_GRIDS='1' if grids else '0')
    p = subprocess.run([str(binary), *map(str, args)], env=env, capture_output=True, text=True, timeout=90)
    assert p.returncode == 0, (args, p.returncode, p.stdout, p.stderr)
    return p


def is_grid(terms, members, kind):
    a, b = AXES[kind-3]
    cells = {(terms[i][a], terms[i][b]) for i in members}
    return len(members) == 4 and len(cells) == 4 and all(len({v[j] for v in cells}) == 2 for j in (0, 1))


def components(terms, costs):
    # Broaden the existing group equality graph even when no pair saves.
    active_costs = list(costs[:10])
    for kind in range(3, 6):
        if 0 < costs[7+kind] < 4*costs[0]:
            for a in AXES[kind-3]:
                active_costs[1+a] = 1
    return group_components(terms, active_costs)


def optimal(terms, costs):
    @lru_cache(None)
    def search(left):
        if not left:
            return 0
        i, *tail = left
        best = costs[0]+search(tuple(tail))
        for size in range(2, 5):
            for rest in combinations(tail, size-1):
                members = (i, *rest)
                options = [group_cost(costs, a, size) for a in range(3)
                           if len({terms[j][a] for j in members}) == 1]
                if size == 4:
                    options += [costs[7+k] for k in range(3, 6) if is_grid(terms, members, k)]
                valid = [c for c in options if 0 < c < size*costs[0]]
                if valid:
                    best = min(best, min(valid)+search(tuple(j for j in tail if j not in rest)))
        return best
    return search(tuple(range(len(terms))))


def context_prices(scales, leaves):
    costs = group_prices(scales, leaves)
    for fixed in FIXED:
        shape = tuple(d*(1 if i == fixed else 2) for i, d in enumerate(scales))
        leaf = leaves.get(tuple(sorted(shape)))
        costs.append(-1 if leaf is None else len(leaf))
    return costs


def check_plan(terms, costs, line, budget, forced=False):
    values = list(map(int, line.split()))
    price, probes, fallback, count, pairs, groups, gfallback, gcount = values[:8]
    assert 0 <= probes <= budget and 0 <= pairs <= budget and 0 <= groups <= budget
    assert count == len(components(terms, costs)) and 0 <= fallback <= count
    assert gcount == len(group_components(terms, costs)) and 0 <= gfallback <= gcount
    flat = values[8:]
    assert len(flat) == 2*len(terms)
    plan = list(zip(flat[::2], flat[1::2]))
    buckets = {}
    for i, (head, kind) in enumerate(plan):
        assert 0 <= head <= i and -1 <= kind <= 5 and plan[head] == (head, kind)
        buckets.setdefault(head, []).append(i)
    actual = 0
    for head, members in buckets.items():
        kind = plan[head][1]
        if len(members) == 1:
            assert kind == -1
            cost = costs[0]
        elif kind < 3:
            assert 0 <= kind and 2 <= len(members) <= 4
            assert len({terms[i][kind] for i in members}) == 1
            cost = group_cost(costs, kind, len(members))
        else:
            assert is_grid(terms, members, kind)
            cost = costs[7+kind]
        assert cost > 0
        actual += cost
    assert price == actual
    if not fallback and not forced and len(terms) <= 12:
        assert price == optimal(terms, costs)
    return price, plan, fallback


def expected(shape, terms, scales, leaves, plan):
    target = tuple(a*b for a, b in zip(shape, scales))
    parity = Counter()
    for head, (owner, kind) in enumerate(plan):
        if head != owner:
            continue
        members = [i for i, pair in enumerate(plan) if pair[0] == head]
        expanded = -1 if kind < 0 else (2, 0, 1)[kind] if kind < 3 else None
        if kind >= 3:
            dims = tuple(d*(1 if i == FIXED[kind-3] else 2) for i, d in enumerate(scales))
            a, b = AXES[kind-3]
            av = [terms[head][a], next(terms[i][a] for i in members if terms[i][a] != terms[head][a])]
            bv = [terms[head][b], next(terms[i][b] for i in members if terms[i][b] != terms[head][b])]
            grid = {(av.index(terms[i][a]), bv.index(terms[i][b])): i for i in members}
        else:
            dims = tuple(d*(len(members) if i == expanded else 1) for i, d in enumerate(scales))
        maps = []
        for f, (r, c) in enumerate(EDGES):
            values = []
            for lr, lc in product(range(dims[r]), range(dims[c])):
                if kind >= 3:
                    coordinates = {r: lr//scales[r], c: lc//scales[c]}
                    u, v = OWNERS[kind-3]
                    member = grid[coordinates.get(u, 0), coordinates.get(v, 0)]
                else:
                    member = members[(lr//scales[r] if r == expanded else 0)+(lc//scales[c] if c == expanded else 0)]
                outer = terms[member][f]
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


def composition_case(binary, root, bank_id, leaves, shape, terms, scales, budget=50000, forced=None):
    key, terms = store(root, shape, terms)
    output = root/'grid-output.tensor'
    extra = [] if forced is None else [forced]
    run(binary, '--compose', root, key, bank_id, *scales, output, budget, *extra)
    costs = context_prices(scales, leaves)
    price, plan, fallback = check_plan(terms, costs, Path(str(output)+'.plan').read_text(), budget, forced is not None)
    target, want = expected(shape, terms, scales, leaves, plan)
    lines = output.read_text().splitlines()
    got = [tuple(int(v, 16) for v in line.split()) for line in lines[1:]]
    assert lines[0].split() == ['MFW1', *map(str, target), str(len(got))]
    assert got == want and len(got) <= price
    exact(target, got)
    return price, len(got), plan, fallback


def dense_naive(shape):
    # An invertible shear at one tensor-network node, with inverse transpose
    # on the other incident factor, preserves matrix multiplication exactly.
    node = 0 if shape[0] == 2 else 1
    incident = [f for f, edge in enumerate(EDGES) if node in edge]
    result = []
    for term in naive(shape):
        row = list(term)
        for f in incident:
            r,c = EDGES[f]; changed = row[f]
            for bit in bits(row[f]):
                coords = [bit//shape[c],bit%shape[c]]
                place = 0 if r == node else 1
                source = 1 if f == incident[0] else 0
                if coords[place] == source:
                    coords[place] = 1-source
                    changed ^= 1 << (coords[0]*shape[c]+coords[1])
            row[f] = changed
        result.append(tuple(row))
    exact(shape,result)
    return result


def check(binary, pair_binary, parent=None):
    run(binary, '--grid-bounds-test')
    rng = random.Random(20260911)
    cases = []
    for _ in range(180):
        terms = [tuple(rng.randrange(1, 5) for _ in range(3)) for _ in range(rng.randrange(1, 12))]
        costs = [rng.randrange(1, 40) for _ in range(4)]
        costs += [rng.choice([-1, rng.randrange(1, 129)]) for _ in range(9)]
        cases.append((terms, costs, 50000))
    for budget in (1, 7, 50000):
        for size in (4, 8, 16, 17, 512):
            terms = [(1+i//2, 1+i%2, 1+i//4) for i in range(size)]
            cases.append((terms, [7,14,14,14,-1,-1,-1,-1,-1,-1,26,26,26], budget))
    # Duplicate cells: choosing one representative per equality cell is not
    # a complete packing search. All alternatives must remain available.
    cells = [(1,1,1),(1,2,2),(2,1,3),(2,2,4)]
    cases += [(cells+cells, [7,14,14,14,-1,-1,-1,-1,-1,-1,26,-1,-1], 50000),
              (cells, [7,14,14,14,-1,-1,-1,-1,-1,-1,-1,-1,-1], 50000)]
    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-grids-') as directory:
        root = Path(directory)
        source, dest = root/'in', root/'out'
        source.write_text(''.join(' '.join(map(str, [len(t), *c, b, *(v for row in t for v in row)]))+'\n' for t,c,b in cases))
        run(binary, '--plans', source, dest)
        rows = dest.read_text().splitlines(); first = dest.read_bytes()
        assert len(rows) == len(cases)
        run(binary, '--plans', source, dest)
        assert dest.read_bytes() == first
        source.write_text(''.join(' '.join(map(str, [len(t), *c[:10], b, *(v for row in t for v in row)]))+'\n' for t,c,b in cases))
        run(binary, '--plans', source, dest, grids=False)
        old = dest.read_text().splitlines()
        for (terms,costs,budget),row,baseline in zip(cases,rows,old):
            price,plan,fallback = check_plan(terms,costs,row,budget)
            values = list(map(int,baseline.split()))
            assert price <= values[0]
            if budget == 1:
                assert price == values[0] and plan == list(zip(values[5::2],values[6::2]))
        bank_id = run(pair_binary,'--bank',root,RUNTIME).stdout.strip().splitlines()[-1]
        leaves = load_bank(root,bank_id)
        compositions = 0
        for scales in product(range(2,5),repeat=3):
            composition_case(binary,root,bank_id,leaves,(2,2,2),naive((2,2,2)),scales)
            compositions += 1
        for kind,shape in ((3,(2,1,2)),(4,(1,2,2)),(5,(2,2,1))):
            # Exercise dense linear factor maps, not only one-hot grids.
            terms = dense_naive(shape)
            for scales in ((2,2,2),(2,3,2),(3,2,2)):
                if context_prices(scales,leaves)[7+kind] > 0:
                    composition_case(binary,root,bank_id,leaves,shape,terms,scales,forced=kind)
                    compositions += 1
        # Full tensor with two disjoint grids. Pair-only prices cannot see
        # either saving at scale 222: 56 -> 52.
        price,rank,plan,_ = composition_case(binary,root,bank_id,leaves,(2,2,2),naive((2,2,2)),(2,2,2))
        assert price == rank == 52 and sum(i == h and k >= 3 for i,(h,k) in enumerate(plan)) == 2
        compositions += 1
        if parent:
            terms = parse_terms(parent.read_bytes(),104); exact((4,5,7),terms)
            for scales,bound in (((2,2,2),724),((2,3,3),1548),((3,3,2),1542)):
                price,rank,_,fallback = composition_case(binary,root,bank_id,leaves,(4,5,7),terms,scales)
                assert price == rank == bound and fallback == 0, (scales,price,rank,fallback)
                compositions += 1
    print(f'PASS mixed grids: {len(cases)} plans; {compositions} complete tensor replays; group-plan non-regression')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary',type=Path)
    parser.add_argument('pair_binary',type=Path)
    parser.add_argument('--parent',type=Path)
    args = parser.parse_args()
    check(args.binary.resolve(),args.pair_binary.resolve(),args.parent)
