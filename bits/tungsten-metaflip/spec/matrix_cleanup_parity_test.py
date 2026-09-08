#!/usr/bin/env python3
"""Native shared-matrix algebra vs independent column/row equation oracle."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/matmul/metaflip'))
from verify_cofactor_mergers import compress_shared, refactor_shared
from pair_cleanup_parity_test import check_runtime_wiring


def check(binary):
    check_runtime_wiring()
    gate = (ROOT / 'bits/tungsten-metaflip/lib/metaflip/fleet/pair_cleanup.w').read_text()
    assert 'use matrix_cleanup' in gate
    assert gate.index('cleaned = ffmc_reduce(') < gate.index('if cleaned < 1 || ffw_support_tensor_error_scratch(')
    run = subprocess.run([binary, '--parity'], check=True, text=True,
                         capture_output=True, timeout=60)
    cases, modes, ties, drops = 0, set(), 0, 0
    mode = None
    for line in run.stdout.splitlines():
        fields = line.split()
        if fields[0] == 'CASE':
            assert mode is None
            mode = int(fields[2])
            source, actual = [], []
        elif fields[0] in ('IN', 'OUT'):
            (source if fields[0] == 'IN' else actual).append(tuple(map(int, fields[1:])))
        elif fields[0] == 'END':
            if mode == 0:
                expected, _ = compress_shared(source, max_bits=63)
            else:
                expected, _ = refactor_shared(source, (mode - 1) // 2, max_bits=63,
                                             reverse_columns=bool((mode - 1) % 2))
            assert actual == expected, (cases, mode, source, actual, expected)
            assert len(actual) == int(fields[1]) <= len(source)
            assert all(0 < v < 1 << 63 for term in actual for v in term)
            if len(actual) == len(source) and sorted(actual) != sorted(source):
                ties += 1
            drops += len(actual) < len(source)
            modes.add(mode)
            cases += 1
            mode = None
    assert cases == 700 and len(modes) == 7 and mode is None
    assert ties and drops
    print(f'PASS native/offline matrix parity: {cases} cases, {ties} neutral changes, {drops} reductions')


if __name__ == '__main__':
    check(sys.argv[1])
