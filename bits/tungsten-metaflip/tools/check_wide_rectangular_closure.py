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
    ((10, 12, 25), '12x10x25', 1836,
     '9f6e46e1cbbf99417ab2f1ae3c36a92260809ef313e6540eabcaa065baab7c58', True),
    ((16, 25, 28), '16x28x25', 6223,
     '049d2676a8f0e9c560026c5ad511faadc14debd415cc5d6d6c97e3407f3e3923', True),
    ((10, 12, 19), '12x10x19', 1421,
     'a184dc5aeb7a90d5e88af72a4ec4eb73f58888ea9ce0caa5159b533ed0724de5', True),
    ((16, 25, 27), '16x27x25', 6080,
     '7d6bdd7c300602617ad8f9c52b3638210391699394e69c55d7b86dc12bfd2ce3', True),
    ((16, 25, 31), '16x31x25', 6916,
     'a31cfc6638245c110fcba943c4ed948889915210be74ced9d2c8f12b057e4e41', True),
    ((16, 25, 29), '16x29x25', 6534,
     'bb01d2f6b1516808bc22a9edfd3ca2a0b36da9ea9c440a46846a07a22c0cad78', True),
    ((8, 19, 30), '8x19x30', 2723,
     '519e99587c73888bbc011a5a11c7342fcae631e79d591b077e52d3749772fc7a', True),
    ((15, 19, 28), '19x28x15', 4576,
     '20554ab7fe74e6a977ad7612274843926e79b18bbd2f3f168bf103b0cbc2ca86', True),
    ((14, 20, 28), '20x28x14', 4484,
     '10b966b8ceeb69bdf506007eb026df28df0aed4d6c118a5593e991a915ce8091', True),
    ((19, 20, 25), '20x19x25', 5403,
     'c11d3a775ed89031462c126f1707f63cd600c611d268878f165a838b9a8eb2a6', True),
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
        with_new[key] = min(with_new.get(key, rank), rank)
    improved = module.solver(with_new)
    gains = [{'shape': shape, 'before': original(shape), 'after': improved(shape)}
             for shape in itertools.combinations_with_replacement(range(2, 33), 3)
             if improved(shape) < original(shape)]
    if len(gains) != 48 or sum(row['before'] - row['after'] for row in gains) != 2062:
        raise ValueError('downstream impact changed')
    print(json.dumps({'field': 'GF(2)', 'record_claim': False,
                      'catalog_sha256': manifest['catalog_sha256'],
                      'candidate_sha256': {shape: digest for _, shape, _, digest, _ in CANDIDATES},
                      'gains': gains}, indent=2))


if __name__ == '__main__':
    main()
