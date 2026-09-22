#!/usr/bin/env python3
"""Replay retained rectangular certificates' finite GF(2) closure effect."""
import argparse
import base64
import gzip
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MANIFEST = HERE / 'certificates/structured-parent-portfolio-20260922/manifest.json'
CERTS = HERE / 'certificates/wide-rectangular-walk-20260922'
VERIFIER = HERE / 'verify_tensor.rb'
SOLVER = ROOT / 'benchmarks/matmul/metaflip/verify_recursive_portfolio.py'
CANDIDATES = (
    ((5, 9, 20), '9x5x20', 623,
     '04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5', False),
    ((10, 12, 20), '12x10x20', 1448,
     'ce1223857ec1c7bf2215b248a5cbeb42c4171df2c648ee7d752fd9f822741df8', False),
    ((16, 25, 28), '16x28x25', 6223,
     '049d2676a8f0e9c560026c5ad511faadc14debd415cc5d6d6c97e3407f3e3923', True),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('catalog', type=Path, help='catalog.json at the portfolio manifest revision')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    raw = args.catalog.read_bytes()
    if hashlib.sha256(raw).hexdigest() != manifest['catalog_sha256']:
        raise ValueError('catalog revision differs from the pinned portfolio')
    for _, shape, rank, digest, compressed in CANDIDATES:
        path = CERTS / f'{shape}-r{rank}.mfw'
        if compressed:
            encoded = path.with_name(path.name + '.gz.b64').read_bytes().replace(b'\n', b'')
            raw_cert = gzip.decompress(base64.b64decode(encoded, validate=True))
            with tempfile.TemporaryDirectory(prefix='metaflip-wide-rect-') as tmp:
                path = Path(tmp) / path.name
                path.write_bytes(raw_cert)
                checked = json.loads(subprocess.check_output(
                    ['ruby', str(VERIFIER), '--shape', shape, str(path)], text=True))[0]
        else:
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
    for key, _, rank, _, _ in CANDIDATES:
        with_new[key] = min(with_new[key], rank)
    improved = module.solver(with_new)
    gains = [{'shape': shape, 'before': original(shape), 'after': improved(shape)}
             for shape in itertools.combinations_with_replacement(range(2, 33), 3)
             if improved(shape) < original(shape)]
    if len(gains) != 14 or sum(row['before'] - row['after'] for row in gains) != 61:
        raise ValueError('downstream impact changed')
    print(json.dumps({'field': 'GF(2)', 'record_claim': False,
                      'catalog_sha256': manifest['catalog_sha256'],
                      'candidate_sha256': {shape: digest for _, shape, _, digest, _ in CANDIDATES},
                      'gains': gains}, indent=2))


if __name__ == '__main__':
    main()
