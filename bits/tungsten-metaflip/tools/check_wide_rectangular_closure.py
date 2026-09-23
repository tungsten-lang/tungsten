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
    ((8, 20, 29), '8x20x29', 2724,
     'b1f26cb283b84ba01d699007abe162318569afa6e9c3fdcdb02fbf44577e0a16', True),
    ((7, 20, 30), '7x20x30', 2622,
     '2321df5be27cdd71032b79a94adbf7a6b7e08d9e6e99128dab599de57963b223', True),
    ((7, 19, 30), '7x19x30', 2538,
     '005b9d101f493eb6cd6386479099ad10c106940d682ab7c2e7d6302ff5a59d13', True),
    ((7, 18, 30), '7x30x18', 2374,
     '0645becb3abaf003bbe7fe60d3b139ff0079f7345e4367ce41accd8ac364dd76', True),
    ((8, 18, 29), '8x29x18', 2498,
     'deb90236cda251a21c9576d17eebb647755f3dac5490529f2cd9899c288f9d89', True),
    ((7, 18, 29), '7x29x18', 2341,
     'd6245d9592b31e6e5b97e159306fe65d2e9c5638e52f21d66c3c8ff6ca17e42f', True),
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
    ((13, 19, 25), '19x25x13', 3766,
     '79e591467c80ba62f290c8613da4320706707a5847da568737e177de3a47b5de', True),
    ((8, 19, 26), '8x19x26', 2366,
     'bbade19dd1133fe2bca1ec529ce7787ab59b1f6d76360786c48aa0b81581e5d3', True),
    ((7, 19, 27), '7x19x27', 2298,
     '0cc954e1b7f0e5455cf29df9e20b45ab12505a3ca0dd1c3b976f5591882d18e7', True),
    ((12, 19, 26), '19x26x12', 3493,
     '748e38f85e567644c495f46706ba4aeb2fdc9d1d25f46fb997557e1eb8d7103a', True),
    ((7, 18, 28), '7x18x28', 2287,
     '72d219a018cb0713080e7e384b1f7ca2215043537c93dccb81f5a154c21b1ebb', True),
    ((8, 19, 25), '8x19x25', 2267,
     'bbc407c145ef69bbe150bf85c6e6c445b182bc9907a5457af92043c200a264c1', True),
    ((7, 19, 26), '7x19x26', 2209,
     'f8528ab7ca06290912260b0a0b8001efb944fa9bd0525b8f9df3f9e157560ef4', True),
    ((8, 19, 24), '8x19x24', 2140,
     'de9376f13a929162887d33fa4167b4ed8322c325c43d31816057ccf18792d758', True),
    ((7, 19, 25), '7x19x25', 2122,
     '408505b79f9a5dac4cfc2c05cf81491a92cf840246a6c5e81d1f5198445ce43a', True),
    ((7, 19, 24), '7x19x24', 2010,
     '22daa861e41e1065711bc1f131d5bc1d9985be81a0d53fe0f577378239091eda', True),
    ((8, 19, 23), '8x19x23', 2099,
     'f3f4942a48d9e9a56e1f7ebdef06a13a7f4d9bf963ccd4c2e3d6bbf48985f45c', True),
    ((7, 19, 23), '7x19x23', 1980,
     'd0cbe7d7c8257d13a22168325c18631180da81deddebefc2922dad926d5dcf41', True),
    ((8, 18, 24), '8x18x24', 2059,
     'df40e51fc739f0414f5d5596be3c934cb51d18da3dad3ee4065166c5b394e91b', True),
    ((8, 19, 22), '8x19x22', 2034,
     '95e4cefd3c35ac44e7b11a115e5202e455aca43da75c9e5b0517cbb9b19b044c', True),
    ((8, 17, 24), '8x17x24', 1965,
     '77e095bb121886e989ad3ebab9815069d27bf41cfd39f165cb64d51ca3827951', True),
    ((8, 17, 23), '8x17x23', 1923,
     '0f01b41327bcb556369308e3fea771e9b707cb689c8dfa4cea8f43a82c79a47f', True),
    ((7, 18, 24), '7x18x24', 1942,
     'e8c708c655e01a70f46f3058efe869d50583b5b29e3b9c20e90176278197ae4a', True),
    ((8, 18, 23), '8x18x23', 2016,
     '1d001c874df14a88f01e0ced8afdb2c1b20690bf2826810a6ed22d1b89c2cbae', True),
    ((7, 18, 23), '7x18x23', 1904,
     '8e8418b34ed6c26ad022e36850db8f9daefd376c3fd9056cb720ac0c3cccac55', True),
    ((7, 17, 24), '7x17x24', 1853,
     '75cbce4619a7db9e522f4878058cb972aca26ebf231d26366f4a8444a8e16ea4', True),
    ((8, 17, 22), '8x17x22', 1876,
     '95f4fd9516a94f5fa0e55bbf5a57969f2f8ac7ab945089061b575ca8efce6fff', True),
    ((8, 16, 23), '8x16x23', 1792,
     '54ef1bd730637c116c34b789b0bf0d370c2d4f94d1e99ab27a60c20c1e14f471', True),
    ((7, 16, 24), '7x16x24', 1730,
     'daac3903c14908ee957e64db32457f69445e70c842aaf3027bc7f6bf64e1d917', True),
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
    if len(gains) != 180 or sum(row['before'] - row['after'] for row in gains) != 7163:
        raise ValueError(f'downstream impact changed: {len(gains)} shapes, '
                         f'{sum(row["before"] - row["after"] for row in gains)} terms')
    print(json.dumps({'field': 'GF(2)', 'record_claim': False,
                      'catalog_sha256': manifest['catalog_sha256'],
                      'candidate_sha256': {shape: digest for _, shape, _, digest, _ in CANDIDATES},
                      'gains': gains}, indent=2))


if __name__ == '__main__':
    main()
