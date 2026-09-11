#!/usr/bin/env python3
"""Focused exact-label, component, budget and full-construction adapter gates."""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import random
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'bits/tungsten-metaflip/tools'))
from wide_group_plans import factor_labels, components, plan_many, validate_partition
from mixed_grid_composition_parity_test import components as reference_components, optimal, expected
from mixed_composition_parity_test import load_bank, unit_leaves
from packed_composition_parity_test import exact, naive


def check(binary, bank_root, bank_id):
    rng = random.Random(202609112)
    cases = []
    for trial in range(96):
        palettes = [[(1 << (64+a*180+j*7)) | 1 for j in range(4)] for a in range(3)]
        terms = [tuple(rng.choice(p) for p in palettes) for _ in range(rng.randrange(1, 10))]
        costs = [rng.randrange(1, 24) for _ in range(4)] + [rng.choice([-1, rng.randrange(1, 80)]) for _ in range(9)]
        labels = factor_labels(terms)
        for a in range(3):
            for i in range(len(terms)):
                for j in range(len(terms)):
                    assert (labels[i][a] == labels[j][a]) == (terms[i][a] == terms[j][a])
        assert components(labels, costs) == [list(c) for c in reference_components(terms, costs)]
        cases.append((terms, costs))
    results = plan_many(binary, cases)
    for (terms, costs), result in zip(cases, results):
        assert result['complete_within_model'] and result['price'] == optimal(terms, costs)
    assert plan_many(binary, cases) == results
    # Native 512-term limit must not truncate a 600-term parent. These 150
    # disconnected grids admit exact component calls, even with >64-bit words.
    grid_costs = [7,14,14,14,-1,-1,-1,-1,-1,-1,26,-1,-1]
    grids = [(1 << (65+2*g+i), 1 << (400+2*g+j), 1 << (i*2+j))
             for g in range(150) for i in range(2) for j in range(2)]
    big = plan_many(binary, [(grids, grid_costs)])[0]
    assert big['complete_within_model'] and big['price'] == 150*26 and big['native_components'] == 150
    limited = plan_many(binary, [(grids, grid_costs)], budget=1)[0]
    assert not limited['complete_within_model'] and len(limited['wrapper_fallbacks']) == 149
    assert all(v <= 1 for v in limited['counters']) and validate_partition(grids, grid_costs, limited['plan']) == limited['price']
    # One oversized equality component takes an explicitly incomplete,
    # still legal pure-axis fallback rather than overflowing native arrays.
    connected = [(1 << 1023, i+1, (i+1)<<70) for i in range(600)]
    costs = [7,10,14,14,-1,-1,-1,-1,-1,-1,-1,-1,-1]
    fallback = plan_many(binary, [(connected, costs)])[0]
    assert fallback['price'] == 3000 and not fallback['complete_within_model']
    assert fallback['native_components'] == 0 and fallback['wrapper_fallbacks'][0]['reason'] == 'capacity'
    # All three elementary-grid orientations get complete tensor checks.
    leaves = unit_leaves(load_bank(Path(bank_root), bank_id))
    from mixed_grid_composition_parity_test import context_prices
    full = []
    for shape in ((2,1,33), (1,33,2), (33,2,1)):
        terms = naive(shape); scales = (2,2,2)
        full.append((shape, terms, scales, context_prices(scales, leaves)))
    answers = plan_many(binary, [(t,c) for _,t,_,c in full])
    for (shape, terms, scale, costs), result in zip(full, answers):
        target, output = expected(shape, terms, scale, leaves, result['plan'])
        assert len(output) <= result['price'];exact(target, output)
    # A proposal rebate must never become a claimed tensor rank. Here the
    # proxy selects a pair at 13, but its checked leaf and output have rank 14.
    source = naive((1,1,2)); actual = context_prices((2,2,2), leaves)
    proxy = list(actual); proxy[1] -= 1
    proposal = plan_many(binary, [(source, proxy)])[0]
    assert proposal['price'] == 13
    assert validate_partition(source, actual, proposal['plan']) == 14
    target, output = expected((1,1,2), source, (2,2,2), leaves, proposal['plan'])
    assert len(output) == 14; exact(target, output)
    # High-word distinction matters: truncating these first factors creates
    # a false group. The independent full-factor partition gate rejects it.
    malformed = [((1<<100)|1,1,1), ((1<<101)|1,2,2)]
    try:validate_partition(malformed, costs, [(0,0),(0,0)])
    except ValueError:pass
    else:raise AssertionError('false low-word equality admitted')
    for invalid in ([], [(0,1,1)], [(1<<1024,1,1)], [(True,1,1)], [(1,2)]):
        try:factor_labels(invalid)
        except ValueError:pass
        else:raise AssertionError('invalid factor accepted')
    # Native failures/corrupt completion reports must not silently become
    # feasible fallbacks, including a success exit without an output file.
    probe = ([(1<<99,1,1),(1<<99,2,2)], costs)
    valid = list(map(int, plan_many(binary, [probe])[0]['native_rows'][0]['line'].split()))
    failures = [(None, 0), ('', 0), ('malformed\n', 0), (None, 1)]
    for slot, value in ((0, valid[0]+1), (1,50001), (2,valid[3]+1), (3,valid[3]+1), (8,1)):
        bad = list(valid); bad[slot] = value
        failures.append((' '.join(map(str,bad))+'\n', 0))
    for body, code in failures:
        def fake_run(args, **kwargs):
            if body is not None:
                Path(args[-1]).write_text(body)
            return SimpleNamespace(returncode=code,stdout='',stderr='')
        with patch('wide_group_plans.subprocess.run', fake_run):
            try:plan_many(binary, [probe])
            except (ValueError, RuntimeError):pass
            else:raise AssertionError('native failure accepted')
    print(f'PASS wide group adapter: {len(cases)} exact random cases, deterministic replay, 600-term splitting/fallback, budget=1, 4 full tensors, proxy-rank rejection, corruption/width guards, {len(failures)} native failure guards')


if __name__ == '__main__':check(*sys.argv[1:])
