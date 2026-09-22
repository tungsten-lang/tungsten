#!/usr/bin/env python3
"""Independently expand retained rectangular GF(2) tensor certificates."""
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
    def check_certificate(self, shape, rank, digest, portfolio_shape, parent_rank, catalog_bound):
        name = 'x'.join(map(str, shape))
        raw = (CERTS / f'{name}-r{rank}.mfw').read_bytes()
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


if __name__ == '__main__':
    unittest.main()
