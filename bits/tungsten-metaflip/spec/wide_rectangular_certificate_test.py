#!/usr/bin/env python3
"""Independently expand retained rectangular GF(2) tensor certificates."""
import base64
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
METAFLIP = ROOT / 'bits/tungsten-metaflip'
CERTS = METAFLIP / 'tools/certificates/wide-rectangular-walk-20260922'
PORTFOLIO = METAFLIP / 'tools/certificates/structured-parent-portfolio-20260922/manifest.json'
VERIFIER = ROOT / 'benchmarks/matmul/metaflip/verify_block_composition_records.py'


class WideRectangularCertificateTest(unittest.TestCase):
    def check_certificate(self, shape, rank, digest, portfolio_shape, parent_rank, catalog_bound,
                          compressed=False):
        name = 'x'.join(map(str, shape))
        suffix = '.mfw.gz.b64' if compressed else '.mfw'
        raw = (CERTS / f'{name}-r{rank}{suffix}').read_bytes()
        if compressed:
            raw = gzip.decompress(base64.b64decode(raw.replace(b'\n', b''), validate=True))
        self.assertEqual(hashlib.sha256(raw).hexdigest(), digest)
        lines = raw.decode('ascii').splitlines()
        self.assertEqual(lines.pop(0), f'MFW1 {" ".join(map(str, shape))} {rank}')
        self.assertEqual(len(lines), rank)
        manifest = json.loads(PORTFOLIO.read_text())
        parent = next(row for row in manifest['rows'] if row['shape'] == list(portfolio_shape))
        self.assertEqual((parent['rank'], parent['catalog_recursive_bound']), (parent_rank, catalog_bound))

        spec = importlib.util.spec_from_file_location('wide_rectangular_independent', VERIFIER)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        body = ''.join('R ' + ' '.join(str(int(mask, 16)) for mask in line.split()) + '\n'
                       for line in lines).encode('ascii')
        with tempfile.TemporaryDirectory(prefix='metaflip-wide-rect-cert-') as tmp:
            path = Path(tmp) / 'candidate.txt'
            path.write_bytes(body)
            record = module.Record(name, shape, rank,
                                   path.name, hashlib.sha256(body).hexdigest())
            result = module._verify_one((Path(tmp), record))
        self.assertEqual((result.exact_rank, result.terms, result.tensor_ones),
                         (rank, rank, shape[0] * shape[1] * shape[2]))

    def test_9x5x20_rank_623(self):
        self.check_certificate((9, 5, 20), 623,
                               '04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5',
                               (5, 9, 20), 624, 629)

    def test_12x10x20_rank_1448(self):
        self.check_certificate((12, 10, 20), 1448,
                               'ce1223857ec1c7bf2215b248a5cbeb42c4171df2c648ee7d752fd9f822741df8',
                               (10, 12, 20), 1464, 1500)

    def test_12x10x25_rank_1836(self):
        self.check_certificate((12, 10, 25), 1836,
                               '9f6e46e1cbbf99417ab2f1ae3c36a92260809ef313e6540eabcaa065baab7c58',
                               (10, 12, 25), 1836, 1860, compressed=True)

    def test_16x28x25_rank_6223(self):
        self.check_certificate((16, 28, 25), 6223,
                               '049d2676a8f0e9c560026c5ad511faadc14debd415cc5d6d6c97e3407f3e3923',
                               (16, 25, 28), 6225, 6229, compressed=True)

    def test_12x10x19_rank_1421(self):
        self.check_certificate((12, 10, 19), 1421,
                               'a184dc5aeb7a90d5e88af72a4ec4eb73f58888ea9ce0caa5159b533ed0724de5',
                               (10, 12, 20), 1464, 1500, compressed=True)

    def test_16x27x25_rank_6080(self):
        self.check_certificate((16, 27, 25), 6080,
                               '7d6bdd7c300602617ad8f9c52b3638210391699394e69c55d7b86dc12bfd2ce3',
                               (16, 25, 28), 6225, 6229, compressed=True)

    def test_16x31x25_rank_6916(self):
        self.check_certificate((16, 31, 25), 6916,
                               'a31cfc6638245c110fcba943c4ed948889915210be74ced9d2c8f12b057e4e41',
                               (16, 25, 32), 7055, 7080, compressed=True)

    def test_16x29x25_rank_6534(self):
        self.check_certificate((16, 29, 25), 6534,
                               'bb01d2f6b1516808bc22a9edfd3ca2a0b36da9ea9c440a46846a07a22c0cad78',
                               (16, 25, 32), 7055, 7080, compressed=True)

    def test_8x19x30_rank_2723(self):
        self.check_certificate((8, 19, 30), 2723,
                               '519e99587c73888bbc011a5a11c7342fcae631e79d591b077e52d3749772fc7a',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x28x15_rank_4576(self):
        self.check_certificate((19, 28, 15), 4576,
                               '20554ab7fe74e6a977ad7612274843926e79b18bbd2f3f168bf103b0cbc2ca86',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x28x14_rank_4484(self):
        self.check_certificate((20, 28, 14), 4484,
                               '10b966b8ceeb69bdf506007eb026df28df0aed4d6c118a5593e991a915ce8091',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x28x13_rank_4167(self):
        self.check_certificate((20, 28, 13), 4167,
                               'dbbcfd9d67a9c7a51927f6b0e7cdf72f2df419fb136e2a9cde04743d6749e986',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x19x25_rank_5403(self):
        self.check_certificate((20, 19, 25), 5403,
                               'c11d3a775ed89031462c126f1707f63cd600c611d268878f165a838b9a8eb2a6',
                               (20, 20, 25), 5566, 5570, compressed=True)


if __name__ == '__main__':
    unittest.main()
