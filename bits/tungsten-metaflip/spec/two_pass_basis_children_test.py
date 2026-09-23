#!/usr/bin/env python3
"""Replay retained two-pass GF(2) children and optional native parity."""
import argparse
import hashlib
from itertools import combinations_with_replacement
import json
from pathlib import Path
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import screen_neutral_basis_children as neutral
import screen_two_pass_basis_children as two_pass
import screen_top_two_projection_children as top

MANIFEST = TOOLS / 'certificates/two-pass-basis-children-20260923/manifest.json'
DESCENDANTS = TOOLS / 'certificates/two-pass-basis-descendants-20260923/manifest.json'


def check(native=None):
    data = json.loads(MANIFEST.read_text())
    descendants = json.loads(DESCENDANTS.read_text())
    assert data['field'] == 'GF(2)' and data['record_claim'] is False
    assert data['counts'] == dict(parents=24, modes=288, projections=14928)
    assert len(data['rows']) == 15
    assert descendants['counts'] == dict(parents=15, modes=180, projections=9708)
    assert len(descendants['rows']) == 3
    with tempfile.TemporaryDirectory(prefix='metaflip-two-pass-test-') as temp:
        root = Path(temp)
        parents = neutral.build_structured_parents(root / 'parents')
        assert len(parents) == data['counts']['parents']
        output_dir = root / 'children'
        checked = [two_pass.materialize(row, parents, output_dir)
                   for row in data['rows']]
        assert len({tuple(row['shape']) for row in checked}) == len(checked)
        assert all(Path(row['output']).is_file() for row in checked)
        assert {(tuple(row['shape']), row['rank']) for row in checked} >= {
            ((8, 22, 25), 2675), ((10, 20, 22), 2663),
            ((8, 23, 25), 2746), ((10, 20, 23), 2737)}
        second = [two_pass.materialize(row, checked, root / 'descendants')
                  for row in descendants['rows']]
        assert {(tuple(row['shape']), row['rank']) for row in second} == {
            ((14, 16, 27), 3562), ((15, 16, 27), 3753),
            ((15, 19, 20), 3393)}
        seeds = two_pass.baseline_seeds()
        before = top.solver(dict(seeds))
        for row in data['rows']:
            shape = tuple(row['shape'])
            seeds[shape] = min(seeds.get(shape, row['rank']), row['rank'])
        after = top.solver(seeds)
        gains = [(shape, before(shape) - after(shape))
                 for shape in combinations_with_replacement(range(2, 33), 3)]
        assert len([gain for _, gain in gains if gain > 0]) == 94
        assert all(gain >= 0 for _, gain in gains)
        for row in descendants['rows']:
            shape = tuple(row['shape'])
            seeds[shape] = min(seeds.get(shape, row['rank']), row['rank'])
        after_second = top.solver(seeds)
        second_gains = [(shape, after(shape) - after_second(shape))
                        for shape in combinations_with_replacement(range(2, 33), 3)]
        assert len([gain for _, gain in second_gains if gain > 0]) == 14
        assert all(gain >= 0 for _, gain in second_gains)
        if native is not None:
            binary = str(Path(native).resolve())
            native_out = root / 'native.mfw'
            for family, sources in ((data, parents), (descendants, checked)):
                for row in family['rows']:
                    matches = [parent for parent in sources
                               if parent['sha256'] == row['source_sha256']]
                    assert len(matches) == 1
                    run = subprocess.run([binary, '--basis-mode', matches[0]['output'],
                                          str(native_out), str(row['mode'])],
                                         check=True, capture_output=True, text=True)
                    fields = run.stdout.split()
                    assert fields[0] == 'BASIS_MODE' and int(fields[1]) == row['source_rank']
                    assert int(fields[4]) == 0
                    assert hashlib.sha256(native_out.read_bytes()).hexdigest() == row['basis_sha256']
                    shape, basis = top.read_blob(native_out.read_bytes())
                    assert list(shape) == row['source_shape']
                    assert len(basis) == row.get('basis_rank', row['rank'])
    print(f"PASS two-pass children: {len(data['rows']) + len(descendants['rows'])} exact "
          f"tensors, 94 closure prices, native={native is not None}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', type=Path)
    args = parser.parse_args()
    check(args.native)
