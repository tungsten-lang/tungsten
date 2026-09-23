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

    def test_19x28x13_rank_4068(self):
        self.check_certificate((19, 28, 13), 4068,
                               '15e461d7172163885bc5a51485d6de238e42ca783f02adc786bb9c85947c53e5',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_19x27x15_rank_4488(self):
        self.check_certificate((19, 27, 15), 4488,
                               '6547c40d267aed101dae2f3a2d91e5d3ded8198e586a5a4ea1f46af701b41feb',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_8x19x29_rank_2642(self):
        self.check_certificate((8, 19, 29), 2642,
                               'cf97d17f4b857e83df6e97541938e545f4a3ad03ce981d828a189df90099c633',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_20x27x13_rank_4092(self):
        self.check_certificate((20, 27, 13), 4092,
                               '23a9d6e38925bfaecdccf3f3dc9f400dfd68b2f66f3fb4ab8e5aa1b032e4cc3d',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x19x25_rank_5403(self):
        self.check_certificate((20, 19, 25), 5403,
                               'c11d3a775ed89031462c126f1707f63cd600c611d268878f165a838b9a8eb2a6',
                               (20, 20, 25), 5566, 5570, compressed=True)

    def test_19x27x13_rank_3969(self):
        self.check_certificate((19, 27, 13), 3969,
                               'ac2739d03b5231470050263c8677bfb25e283daebccdb5a6d9c7a180360d75d8',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x26x13_rank_3991(self):
        self.check_certificate((20, 26, 13), 3991,
                               'f115d6847bd5bd894ca59183e527a286e03f5ae4383f3dc38e24fca51ef56490',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x27x12_rank_3699(self):
        self.check_certificate((20, 27, 12), 3699,
                               '21e6b32af7808c961b33afa0357113cc019ef482e3caa8ca4d1710360ccece48',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_8x19x28_rank_2554(self):
        self.check_certificate((8, 19, 28), 2554,
                               'bb5dc75988081487d8818f0199bda6cd424022a0ce07eaad1278f93143704da5',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x26x13_rank_3874(self):
        self.check_certificate((19, 26, 13), 3874,
                               '36a042fbf9a75a2910694a46343a9ffa5b79af5aace59d9d9562365e065ca3f0',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x25x13_rank_3890(self):
        self.check_certificate((20, 25, 13), 3890,
                               '6a709719b5fe039baea4e1b97da45a2cd022c5d4a63345dec56da478dd6bcd59',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x27x11_rank_3545(self):
        self.check_certificate((20, 27, 11), 3545,
                               '86d8bac9048e7fd74c7a9dd9cf8dc029c555e32cba44622c7803ec3dcb96433c',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_7x19x28_rank_2384(self):
        self.check_certificate((7, 19, 28), 2384,
                               '91f691c6acbf09d16ecc819c77d1f7dce5fc8bd14cae307d17a14fbcde4d9e3a',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_8x19x27_rank_2464(self):
        self.check_certificate((8, 19, 27), 2464,
                               '0acee2a6eebe372fb9f395a6b7f91b88361dfc51efcce955b467ba8aaa2c9072',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x25x13_rank_3766(self):
        self.check_certificate((19, 25, 13), 3766,
                               '79e591467c80ba62f290c8613da4320706707a5847da568737e177de3a47b5de',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_8x19x26_rank_2366(self):
        self.check_certificate((8, 19, 26), 2366,
                               'bbade19dd1133fe2bca1ec529ce7787ab59b1f6d76360786c48aa0b81581e5d3',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_7x19x27_rank_2298(self):
        self.check_certificate((7, 19, 27), 2298,
                               '0cc954e1b7f0e5455cf29df9e20b45ab12505a3ca0dd1c3b976f5591882d18e7',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x26x12_rank_3493(self):
        self.check_certificate((19, 26, 12), 3493,
                               '748e38f85e567644c495f46706ba4aeb2fdc9d1d25f46fb997557e1eb8d7103a',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_7x18x28_rank_2287(self):
        self.check_certificate((7, 18, 28), 2287,
                               '72d219a018cb0713080e7e384b1f7ca2215043537c93dccb81f5a154c21b1ebb',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_next_rectangular_projection_chain(self):
        # All ten witnesses descend from the exact 8x20x30 portfolio tensor;
        # a full GF(2) expansion, not the projection recipe, is the authority.
        rows = (
            ((8, 19, 25), 2267, 'bbc407c145ef69bbe150bf85c6e6c445b182bc9907a5457af92043c200a264c1'),
            ((7, 19, 26), 2209, 'f8528ab7ca06290912260b0a0b8001efb944fa9bd0525b8f9df3f9e157560ef4'),
            ((8, 19, 24), 2143, 'a96c3f75af3dc89f47a6b2d99697b4f79b41175ba40b027781e3984e440985b4'),
            ((7, 19, 25), 2122, '408505b79f9a5dac4cfc2c05cf81491a92cf840246a6c5e81d1f5198445ce43a'),
            ((7, 19, 24), 2010, '22daa861e41e1065711bc1f131d5bc1d9985be81a0d53fe0f577378239091eda'),
            ((8, 19, 23), 2104, '866292f6dad1c40934cc25170e5761d1c6f286376ce774b9e4b9358ec36f0790'),
            ((8, 18, 24), 2073, '1eff548ddb9085fb6f7deb1919120311b4b84938540d36c687827a2bd7b4029a'),
            ((8, 19, 22), 2034, '95e4cefd3c35ac44e7b11a115e5202e455aca43da75c9e5b0517cbb9b19b044c'),
            ((8, 17, 24), 1973, '3001999ab7d04bcb8d001441fbc117da06b1d1f4866ba7cff843f070ea0fbe97'),
            ((8, 17, 23), 1934, '7af84cea7140e0dd32a4db9aac7c8b0f1badf13a03aa9a6cfe0a3c6bc61ad045'),
        )
        for shape, rank, digest in rows:
            with self.subTest(shape=shape):
                self.check_certificate(shape, rank, digest, (8, 20, 30),
                                       2803, 2820, compressed=True)


if __name__ == '__main__':
    unittest.main()
