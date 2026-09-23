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
    ((13, 20, 28), '20x28x13', 4167,
     'dbbcfd9d67a9c7a51927f6b0e7cdf72f2df419fb136e2a9cde04743d6749e986', True),
    ((13, 19, 28), '19x28x13', 4068,
     '15e461d7172163885bc5a51485d6de238e42ca783f02adc786bb9c85947c53e5', True),
    ((15, 19, 27), '19x27x15', 4488,
     '6547c40d267aed101dae2f3a2d91e5d3ded8198e586a5a4ea1f46af701b41feb', True),
    ((8, 19, 29), '8x19x29', 2642,
     'cf97d17f4b857e83df6e97541938e545f4a3ad03ce981d828a189df90099c633', True),
    ((13, 20, 27), '20x27x13', 4092,
     '23a9d6e38925bfaecdccf3f3dc9f400dfd68b2f66f3fb4ab8e5aa1b032e4cc3d', True),
    ((19, 20, 25), '20x19x25', 5403,
     'c11d3a775ed89031462c126f1707f63cd600c611d268878f165a838b9a8eb2a6', True),
    ((13, 19, 27), '19x27x13', 3969,
     'ac2739d03b5231470050263c8677bfb25e283daebccdb5a6d9c7a180360d75d8', True),
    ((13, 20, 26), '20x26x13', 3991,
     'f115d6847bd5bd894ca59183e527a286e03f5ae4383f3dc38e24fca51ef56490', True),
    ((12, 20, 27), '20x27x12', 3699,
     '21e6b32af7808c961b33afa0357113cc019ef482e3caa8ca4d1710360ccece48', True),
    ((8, 19, 28), '8x19x28', 2554,
     'bb5dc75988081487d8818f0199bda6cd424022a0ce07eaad1278f93143704da5', True),
    ((13, 19, 26), '19x26x13', 3874,
     '36a042fbf9a75a2910694a46343a9ffa5b79af5aace59d9d9562365e065ca3f0', True),
    ((13, 20, 25), '20x25x13', 3890,
     '6a709719b5fe039baea4e1b97da45a2cd022c5d4a63345dec56da478dd6bcd59', True),
    ((11, 20, 27), '20x27x11', 3545,
     '86d8bac9048e7fd74c7a9dd9cf8dc029c555e32cba44622c7803ec3dcb96433c', True),
    ((7, 19, 28), '7x19x28', 2384,
     '91f691c6acbf09d16ecc819c77d1f7dce5fc8bd14cae307d17a14fbcde4d9e3a', True),
    ((8, 19, 27), '8x19x27', 2464,
     '0acee2a6eebe372fb9f395a6b7f91b88361dfc51efcce955b467ba8aaa2c9072', True),
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
    if len(gains) != 102 or sum(row['before'] - row['after'] for row in gains) != 4674:
        raise ValueError('downstream impact changed')
    print(json.dumps({'field': 'GF(2)', 'record_claim': False,
                      'catalog_sha256': manifest['catalog_sha256'],
                      'candidate_sha256': {shape: digest for _, shape, _, digest, _ in CANDIDATES},
                      'gains': gains}, indent=2))


if __name__ == '__main__':
    main()
