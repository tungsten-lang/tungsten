#!/usr/bin/env python3
"""Check compact portfolio prices against a pinned GF(2) catalog closure."""
import argparse
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MANIFEST = HERE / 'certificates/structured-parent-portfolio-20260922/manifest.json'
SOLVER = ROOT / 'benchmarks/matmul/metaflip/verify_recursive_portfolio.py'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('catalog', type=Path, help='docs/catalog.json from the manifest revision')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    raw = args.catalog.read_bytes()
    if hashlib.sha256(raw).hexdigest() != manifest['catalog_sha256']:
        raise ValueError('catalog digest does not match pinned revision')
    spec = importlib.util.spec_from_file_location('metaflip_recursive_portfolio', SOLVER)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    seeds = module.catalog_minima(json.loads(raw))
    rank = module.solver(seeds)
    for row in manifest['rows']:
        reference = rank(tuple(row['shape']))
        if reference != row['catalog_recursive_bound'] or row['rank'] >= reference:
            raise ValueError(f"comparison mismatch for {row['shape']}: {row['rank']} vs {reference}")
    earlier = [row for row in manifest['rows'] if max(row['scale']) <= 6]
    added = [row for row in manifest['rows'] if max(row['scale']) > 6]
    if len(earlier) != 71 or len(added) != 10:
        raise ValueError('portfolio generation split changed')
    base = dict(seeds)
    for row in earlier:
        key = tuple(row['shape'])
        base[key] = min(base.get(key, row['rank']), row['rank'])
    expanded = dict(base)
    for row in added:
        key = tuple(row['shape'])
        expanded[key] = min(expanded.get(key, row['rank']), row['rank'])
    before, after = module.solver(base), module.solver(expanded)
    gains = [(shape, before(shape) - after(shape))
             for shape in itertools.combinations_with_replacement(range(2, 33), 3)]
    improved = [(shape, gain) for shape, gain in gains if gain > 0]
    if len(improved) != 32 or sum(gain for _, gain in improved) != 788 or any(
            shape[0] == shape[1] == shape[2] for shape, _ in improved):
        raise ValueError('scale-7/8 composition impact changed')
    print(f"checked {len(manifest['rows'])} GF(2) comparisons against {manifest['catalog_revision']}; "
          'scale-7/8 improves 32 closure shapes, no squares')


if __name__ == '__main__':
    main()
