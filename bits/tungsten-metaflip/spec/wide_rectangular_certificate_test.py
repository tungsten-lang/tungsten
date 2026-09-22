#!/usr/bin/env python3
"""Independently expand the retained rectangular GF(2) tensor certificate."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
METAFLIP = ROOT / 'bits/tungsten-metaflip'
CERT = METAFLIP / 'tools/certificates/wide-rectangular-walk-20260922/9x5x20-r623.mfw'
PORTFOLIO = METAFLIP / 'tools/certificates/structured-parent-portfolio-20260922/manifest.json'
VERIFIER = ROOT / 'benchmarks/matmul/metaflip/verify_block_composition_records.py'
SHA256 = '04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5'


class WideRectangularCertificateTest(unittest.TestCase):
    def test_9x5x20_rank_623(self):
        raw = CERT.read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), SHA256)
        lines = raw.decode('ascii').splitlines()
        self.assertEqual(lines.pop(0), 'MFW1 9 5 20 623')
        self.assertEqual(len(lines), 623)
        manifest = json.loads(PORTFOLIO.read_text())
        parent = next(row for row in manifest['rows'] if row['shape'] == [5, 9, 20])
        self.assertEqual((parent['rank'], parent['catalog_recursive_bound']), (624, 629))

        spec = importlib.util.spec_from_file_location('wide_rectangular_independent', VERIFIER)
        module = importlib.util.module_from_spec(spec)
        import sys
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        body = ''.join('R ' + ' '.join(str(int(mask, 16)) for mask in line.split()) + '\n'
                       for line in lines).encode('ascii')
        with tempfile.TemporaryDirectory(prefix='metaflip-wide-rect-cert-') as tmp:
            path = Path(tmp) / 'candidate.txt'
            path.write_bytes(body)
            record = module.Record('9x5x20', (9, 5, 20), 623,
                                   path.name, hashlib.sha256(body).hexdigest())
            result = module._verify_one((Path(tmp), record))
        self.assertEqual((result.exact_rank, result.terms, result.tensor_ones), (623, 623, 900))


if __name__ == '__main__':
    unittest.main()
