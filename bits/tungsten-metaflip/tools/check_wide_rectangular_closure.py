#!/usr/bin/env python3
"""Replay retained rectangular certificates' finite GF(2) closure effect."""
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
CERTS = HERE / 'certificates/wide-rectangular-walk-20260922'
VERIFIER = HERE / 'verify_tensor.rb'
SOLVER = ROOT / 'benchmarks/matmul/metaflip/verify_recursive_portfolio.py'
CANDIDATES = (
    ((5, 9, 20), '9x5x20', 623,
     '04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5'),
    ((10, 12, 20), '12x10x20', 1448,
     'ce1223857ec1c7bf2215b248a5cbeb42c4171df2c648ee7d752fd9f822741df8'),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('catalog', type=Path, help='catalog.json at the portfolio manifest revision')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    raw = args.catalog.read_bytes()
    if hashlib.sha256(raw).hexdigest() != manifest['catalog_sha256']:
        raise ValueError('catalog revision differs from the pinned portfolio')
    for _, shape, rank, digest in CANDIDATES:
        path = CERTS / f'{shape}-r{rank}.mfw'
        checked = json.loads(subprocess.check_output(
            ['ruby', str(VERIFIER), '--shape', shape, str(path)], text=True))[0]
        if not checked['exact'] or checked['rank'] != rank or checked['sha256'] != digest:
            raise ValueError(f'{shape} tensor certificate failed verification')
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
    for key, _, rank, _ in CANDIDATES:
        with_new[key] = min(with_new[key], rank)
    improved = module.solver(with_new)
    gains = [{'shape': shape, 'before': original(shape), 'after': improved(shape)}
             for shape in itertools.combinations_with_replacement(range(2, 33), 3)
             if improved(shape) < original(shape)]
    if len(gains) != 11 or sum(row['before'] - row['after'] for row in gains) != 56:
        raise ValueError('downstream impact changed')
    print(json.dumps({'field': 'GF(2)', 'record_claim': False,
                      'catalog_sha256': manifest['catalog_sha256'],
                      'candidate_sha256': {shape: digest for _, shape, _, digest in CANDIDATES},
                      'gains': gains}, indent=2))


if __name__ == '__main__':
    main()
