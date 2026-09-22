#!/usr/bin/env python3
"""Check compact portfolio prices against a pinned GF(2) catalog closure."""
import argparse
import hashlib
import importlib.util
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
    rank = module.solver(module.catalog_minima(json.loads(raw)))
    for row in manifest['rows']:
        reference = rank(tuple(row['shape']))
        if reference != row['catalog_recursive_bound'] or row['rank'] >= reference:
            raise ValueError(f"comparison mismatch for {row['shape']}: {row['rank']} vs {reference}")
    print(f"checked {len(manifest['rows'])} GF(2) comparisons against {manifest['catalog_revision']}")


if __name__ == '__main__':
    main()
