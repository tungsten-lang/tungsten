"""Offline wide-factor adapter for the existing bounded native MFM3 planner.

Labels encode exact equality, never truncated words or probabilistic hashes.
They are planner inputs, not tensors. Construction/admission must still use
the original full factors and independently verify the resulting tensor.
This does not change the production scheduler or add runtime dependencies.
"""
from collections import defaultdict
from pathlib import Path
import os
import subprocess
import tempfile

GRID_AXES = ((0, 1), (0, 2), (1, 2))


def factor_labels(terms):
    if not 1 <= len(terms) <= 16384:
        raise ValueError('parent rank must be in 1..16384')
    palettes = [dict() for _ in range(3)]
    result = []
    for term in terms:
        if len(term) != 3 or any(type(v) is not int or not 0 < v < 1 << 1024 for v in term):
            raise ValueError('expected three nonzero factors of at most 1024 bits')
        result.append(tuple(palettes[a].setdefault(v, len(palettes[a])+1) for a, v in enumerate(term)))
    return result


def validate_costs(costs):
    if len(costs) != 13 or any(type(c) is not int for c in costs):
        raise ValueError('expected thirteen integer leaf prices')
    if any(not 1 <= c <= 128 for c in costs[:4]) or any(c != -1 and not 1 <= c <= 128 for c in costs[4:]):
        raise ValueError('invalid native leaf price')


def group_cost(costs, axis, size):
    return costs[0] if size == 1 else costs[1+3*(size-2)+axis]


def components(labels, costs, grids=True):
    """All useful group/grid hyperedges lie in one equality component."""
    active = [any(0 < group_cost(costs, a, k) < k*costs[0] for k in range(2, 5)) for a in range(3)]
    if grids:
        for i, axes in enumerate(GRID_AXES):
            if 0 < costs[10+i] < 4*costs[0]:
                for a in axes:
                    active[a] = True
    leaders = list(range(len(labels)))

    def find(i):
        while leaders[i] != i:
            leaders[i] = leaders[leaders[i]]
            i = leaders[i]
        return i

    for a in range(3):
        if not active[a]:
            continue
        seen = {}
        for i, term in enumerate(labels):
            j = seen.setdefault(term[a], i)
            leaders[find(i)] = find(j)
    groups = defaultdict(list)
    for i in range(len(labels)):
        groups[find(i)].append(i)
    return sorted(groups.values(), key=lambda g: g[0])


def pure_fallback(terms, costs):
    """Legal best pure-axis 1..4-group DP, not a complete grid search."""
    best = (len(terms)*costs[0], [(i, -1) for i in range(len(terms))])
    for a in range(3):
        buckets = defaultdict(list)
        for i, term in enumerate(terms):
            buckets[term[a]].append(i)
        plan = [(i, -1) for i in range(len(terms))]
        total = 0
        for bucket in buckets.values():
            dp = [(0, 0)]
            for size in range(1, len(bucket)+1):
                choices = [(dp[size-k][0]+group_cost(costs, a, k), k)
                           for k in range(1, min(4, size)+1) if group_cost(costs, a, k) > 0]
                dp.append(min(choices))
            total += dp[-1][0]
            end = len(bucket)
            while end:
                k = dp[end][1]; members = bucket[end-k:end]
                for i in members:
                    plan[i] = (members[0], a if k > 1 else -1)
                end -= k
        best = min(best, (total, plan))
    return best


def validate_partition(terms, costs, plan):
    if len(plan) != len(terms):
        raise ValueError('partition length mismatch')
    groups = defaultdict(list)
    for i, (head, kind) in enumerate(plan):
        if not 0 <= head <= i or not -1 <= kind <= 5 or plan[head] != (head, kind):
            raise ValueError('invalid partition head')
        groups[head].append(i)
    total = 0
    for head, members in groups.items():
        kind = plan[head][1]; size = len(members)
        if size == 1:
            if kind != -1:
                raise ValueError('non-singleton label on singleton')
            cost = costs[0]
        elif 0 <= kind < 3:
            if not 2 <= size <= 4 or len({terms[i][kind] for i in members}) != 1:
                raise ValueError('false shared-factor group')
            cost = group_cost(costs, kind, size)
        elif 3 <= kind <= 5:
            a, b = GRID_AXES[kind-3]
            cells = {(terms[i][a], terms[i][b]) for i in members}
            if size != 4 or len(cells) != 4 or any(len({v[j] for v in cells}) != 2 for j in (0, 1)):
                raise ValueError('false elementary grid')
            cost = costs[7+kind]
        else:
            raise ValueError('invalid non-singleton kind')
        if cost <= 0:
            raise ValueError('unavailable leaf')
        total += cost
    return total


def plan_many(binary, cases, *, budget=50000, timeout=60):
    """Plan (full_terms, thirteen_prices) cases with bounded component calls.

    Each of MFM3's three native search counters sums to at most `budget` per
    parent/context. Oversized or unallocated components get explicit feasible
    fallbacks; they are never classified as complete searches. Input batches
    stay below the native harness's 1 MiB parser limit.
    """
    if type(budget) is not int or not 1 <= budget <= 1000000:
        raise ValueError('invalid search budget')
    binary = str(Path(binary).resolve())
    results, jobs = [], []
    for terms, costs in cases:
        validate_costs(costs); labels = factor_labels(terms)
        groups = components(labels, costs)
        eligible = [g for g in groups if 1 < len(g) <= 512]
        allocation = budget//len(eligible) if eligible else 0
        remaining = budget
        result = dict(price=0, plan=[(i, -1) for i in range(len(terms))], components=len(groups),
                      native_components=0, counters=[0, 0, 0], native_fallbacks=0,
                      wrapper_fallbacks=[], native_rows=[])
        results.append(result)
        for members in groups:
            subset = [terms[i] for i in members]
            if len(members) == 1:
                result['price'] += costs[0]
                continue
            allowed = min(remaining, max(1, allocation)) if len(members) <= 512 else 0
            if not allowed:
                price, plan = pure_fallback(subset, costs)
                result['price'] += price
                for i, (head, kind) in enumerate(plan):
                    result['plan'][members[i]] = (members[head], kind)
                result['wrapper_fallbacks'].append(dict(members=members, reason='capacity' if len(members)>512 else 'budget'))
                continue
            remaining -= allowed
            encoded = [labels[i] for i in members]
            line = ' '.join(map(str, [len(members), *costs, allowed, *(v for t in encoded for v in t)]))+'\n'
            jobs.append((len(results)-1, members, allowed, line))
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-plan-') as directory:
        root = Path(directory)
        start = 0
        while start < len(jobs):
            end, size = start, 0
            while end < len(jobs) and size+len(jobs[end][3]) < 900000:
                size += len(jobs[end][3]); end += 1
            if end == start:
                raise ValueError('native row exceeds input bound')
            source, output = root/'input', root/'output'
            source.write_text(''.join(job[3] for job in jobs[start:end]))
            output.unlink(missing_ok=True)
            p = subprocess.run([binary, '--plans', str(source), str(output)],
                               env=dict(os.environ, METAFLIP_TEST_GRIDS='1'), capture_output=True,
                               text=True, timeout=timeout)
            if p.returncode:
                raise RuntimeError(f'native planner failed: {p.returncode}: {p.stdout} {p.stderr}')
            if not output.is_file():
                raise ValueError('native planner did not write its result')
            lines = output.read_text().splitlines()
            if len(lines) != end-start:
                raise ValueError('native row count mismatch')
            for (case, members, allowed, _), line in zip(jobs[start:end], lines):
                values = list(map(int, line.split()))
                if len(values) != 8+2*len(members):
                    raise ValueError('malformed native plan')
                price, gp, gf, gc, pp, hp, hf, hc = values[:8]
                plan = list(zip(values[8::2], values[9::2]))
                terms, costs = cases[case]; subset = [terms[i] for i in members]
                if price != validate_partition(subset, costs, plan) or any(not 0 <= v <= allowed for v in (gp, pp, hp)):
                    raise ValueError('native price or budget mismatch')
                if gc != len(components(subset, costs)) or hc != len(components(subset, costs, grids=False)) or not 0 <= gf <= gc or not 0 <= hf <= hc:
                    raise ValueError('native completion metadata mismatch')
                result = results[case]; result['price'] += price; result['native_components'] += 1
                result['native_fallbacks'] += gf
                result['counters'] = [a+b for a, b in zip(result['counters'], (gp, pp, hp))]
                result['native_rows'].append(dict(members=members, budget=allowed, line=line))
                for i, (head, kind) in enumerate(plan):
                    result['plan'][members[i]] = (members[head], kind)
            start = end
    for (terms, costs), result in zip(cases, results):
        if result['price'] != validate_partition(terms, costs, result['plan']) or any(v > budget for v in result['counters']):
            raise ValueError('assembled price or budget mismatch')
        result['complete_within_model'] = not result['wrapper_fallbacks'] and not result['native_fallbacks']
    return results
