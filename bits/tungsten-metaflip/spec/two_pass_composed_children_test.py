#!/usr/bin/env python3
"""Replay exact two-pass composed children and optional native basis parity."""
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
import screen_two_pass_basis_children as two_pass
import screen_top_two_projection_children as top

MANIFEST = TOOLS / 'certificates/two-pass-composed-children-20260923/manifest.json'


def check(native=None):
    data = json.loads(MANIFEST.read_text())
    assert data['field'] == 'GF(2)' and data['record_claim'] is False
    assert data['parent_set'] == 'composed-chain'
    assert data['counts'] == dict(parents=6, modes=72, projections=5148)
    assert {(tuple(row['shape']), row['rank']) for row in data['rows']} == {
        ((16, 23, 31), 6380), ((16, 24, 31), 6484),
        ((16, 25, 31), 6888)}
    assert all(row['rank'] < min(row['local_baseline_rank'], row['public_rank'])
               for row in data['rows'])
    seeds = two_pass.baseline_seeds('composed-chain')
    before = top.solver(dict(seeds))
    for row in data['rows']:
        shape = tuple(row['shape'])
        seeds[shape] = min(seeds.get(shape, row['rank']), row['rank'])
    after = top.solver(seeds)
    gains = [before(shape) - after(shape)
             for shape in combinations_with_replacement(range(2, 33), 3)]
    assert sum(gain > 0 for gain in gains) == 43
    assert all(gain >= 0 for gain in gains)
    with tempfile.TemporaryDirectory(prefix='metaflip-two-pass-composed-test-') as temp:
        root = Path(temp)
        parents = two_pass.build_parents(root / 'parents', 'composed-chain')
        assert len(parents) == 6
        checked = [two_pass.materialize(row, parents, root / 'children')
                   for row in data['rows']]
        assert all(Path(row['output']).is_file() for row in checked)
        if native is not None:
            binary = str(Path(native).resolve())
            output = root / 'native.mfw'
            for row in data['rows']:
                sources = [parent for parent in parents
                           if parent['sha256'] == row['source_sha256']]
                assert len(sources) == 1
                run = subprocess.run([binary, '--basis-mode', sources[0]['output'],
                                      str(output), str(row['mode'])],
                                     check=True, capture_output=True, text=True)
                fields = run.stdout.split()
                assert fields[0] == 'BASIS_MODE'
                assert int(fields[1]) == row['source_rank']
                assert int(fields[2]) == row['basis_rank']
                assert int(fields[4]) == 0
                assert hashlib.sha256(output.read_bytes()).hexdigest() == row['basis_sha256']
                shape, basis = top.read_blob(output.read_bytes())
                assert list(shape) == row['source_shape'] and len(basis) == row['basis_rank']
    print(f"PASS composed two-pass children: {len(data['rows'])} exact tensors, "
          f"native={native is not None}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', type=Path)
    args = parser.parse_args()
    check(args.native)
