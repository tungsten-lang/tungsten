#!/usr/bin/env python3
"""Replay the rank-623 rectangular certificate's finite GF(2) closure effect."""
import argparse
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MANIFEST = HERE / 'certificates/structured-parent-portfolio-20260922/manifest.json'
CERT = HERE / 'certificates/wide-rectangular-walk-20260922/9x5x20-r623.mfw'
VERIFIER = HERE / 'verify_tensor.rb'
SOLVER = ROOT / 'benchmarks/matmul/metaflip/verify_recursive_portfolio.py'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('catalog', type=Path, help='catalog.json at the portfolio manifest revision')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    raw = args.catalog.read_bytes()
    if hashlib.sha256(raw).hexdigest() != manifest['catalog_sha256']:
        raise ValueError('catalog revision differs from the pinned portfolio')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(VERIFIER), '--shape', '9x5x20', str(CERT)], text=True))[0]
    if not checked['exact'] or checked['rank'] != 623 or checked['sha256'] != (
            '04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5'):
        raise ValueError('rank-623 tensor certificate failed verification')
    spec = importlib.util.spec_from_file_location('metaflip_recursive_portfolio', SOLVER)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    seeds = module.catalog_minima(json.loads(raw))
    for row in manifest['rows']:
        key = tuple(row['shape'])
        seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    original = module.solver(seeds)
    with_new = dict(seeds)
    with_new[(5, 9, 20)] = min(with_new[(5, 9, 20)], 623)
    improved = module.solver(with_new)
    gains = [{'shape': shape, 'before': original(shape), 'after': improved(shape)}
             for shape in itertools.combinations_with_replacement(range(2, 33), 3)
             if improved(shape) < original(shape)]
    if len(gains) != 8 or sum(row['before'] - row['after'] for row in gains) != 8:
        raise ValueError('downstream impact changed')
    print(json.dumps({'field': 'GF(2)', 'record_claim': False,
                      'catalog_sha256': manifest['catalog_sha256'],
                      'candidate_sha256': checked['sha256'], 'gains': gains}, indent=2))


if __name__ == '__main__':
    main()
