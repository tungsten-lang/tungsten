#!/usr/bin/env python3
"""Compare the packaged native reducer with the independent offline routine."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/matmul/metaflip'))
from pair_reduction_scan import has_merge, reduce_pairs


def check_runtime_wiring():
    """Keep the tested gate on real admission routes, outside worker loops."""
    runtime = ROOT / 'bits/tungsten-metaflip/lib/metaflip'
    fleet = (runtime / 'fleet.w').read_text()
    rect = (runtime / 'rect/campaign.w').read_text()
    assert 'use pair_cleanup' in (runtime / 'fleet/intake.w').read_text()
    assert 'use ../fleet/pair_cleanup' in rect
    for state in ('state', 'gpu_candidate', 'composed_candidate', 'late', 'late_composed'):
        assert f'ffpc_gate_square_best({state}, N,' in fleet, state
    for state in ('rect_candidate', 'late_rect'):
        assert f'ffpc_gate_rect_best({state}, ' in fleet, state
    for state in ('candidate', 'block_candidate', 'gpu_candidate', 'mitm_candidate'):
        assert f'ffpc_gate_rect_best({state}, n, m, p,' in rect, state
    assert fleet.index('cleaned_rank = ffpc_gate_square_best(state,') < fleet.index('descendant_identity = ffbi_best_id(state)')
    assert rect.index('gated_rank = ffpc_gate_rect_best(candidate,') < rect.index('candidate_rank = ffr_best_rank(candidate)')
    for name in ('scheme.w', 'rect.w'):
        assert 'pair_cleanup' not in (runtime / name).read_text()
    print('PASS cleanup wiring: CPU, GPU, late, rectangular and composition intake; no worker-loop import')


def check(binary):
    check_runtime_wiring()
    result = subprocess.run([binary, '--parity'], check=True, text=True,
                            capture_output=True, timeout=60)
    cases = 0
    source, actual, order = [], [], None
    orders = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if fields[0] == 'CASE':
            assert order is None, 'unfinished case'
            order = tuple(map(int, fields[2:]))
            orders.add(order)
            source, actual = [], []
        elif fields[0] in ('IN', 'OUT'):
            (source if fields[0] == 'IN' else actual).append(tuple(map(int, fields[1:])))
        elif fields[0] == 'END':
            expected, _ = reduce_pairs(source, order)
            assert sorted(actual) == expected, (cases, order, source, actual, expected)
            assert len(actual) == int(fields[1]) and not has_merge(actual)
            assert reduce_pairs(actual, order) == (sorted(actual), [])
            cases += 1
            order = None
    assert cases == 480 and len(orders) == 6 and order is None
    print(f'PASS native/offline pair-cleanup parity: {cases} cases, all six axis orders')


if __name__ == '__main__':
    check(sys.argv[1])
