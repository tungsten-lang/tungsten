#!/usr/bin/env python3
"""Focused certificate-only block-extension screening and replay checks."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / 'bits/tungsten-metaflip/tools/screen_certified_block_extensions.py'
SPEC = importlib.util.spec_from_file_location('certified_block_extensions', PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CertifiedBlockExtensionsTest(unittest.TestCase):
    def test_screen_only_certified_append_and_double(self):
        candidates = (((2, 2, 2), '2x2x2', 7, 'unused', False),)
        entries = [dict(format=[2, 2, 2], rank=8),
                   dict(format=[2, 2, 3], rank=12),
                   dict(format=[2, 2, 4], rank=15)]
        rows = MODULE.screen(entries, candidates, max_dim=4)
        self.assertEqual([(row['shape'], row['rank'], row['operation']) for row in rows],
                         [([2, 2, 3], 11, 'append'), ([2, 2, 4], 14, 'double')])
        with self.assertRaisesRegex(ValueError, 'conflicting public rank'):
            MODULE.screen(entries + [dict(format=[2, 3, 2], rank=13)], candidates)
        with self.assertRaisesRegex(ValueError, 'missing'):
            MODULE.screen(entries[1:], candidates)

    def test_materialize_exact_13x16x25(self):
        row = dict(shape=[13, 16, 25], rank=3050, public_rank=3102, gap=52,
                   operation='append', orientation=[13, 16, 24], axis=2,
                   seed_shape='13x16x24', seed_rank=2842,
                   seed_sha256='cad0bbc3685789992aed5d490035e698e6e5c1e5dc272f05dd86742b01364014',
                   compressed=True)
        with tempfile.TemporaryDirectory(prefix='metaflip-certified-block-') as tmp:
            result = MODULE.materialize(row, Path(tmp))
            self.assertEqual((result['rank'], result['gap'], result['sha256']),
                             (3050, 52, '46abb4fb714eb0d56f38f5ce0f87c8e15e5e1d834405b8ef42ff0c3b693133f2'))

    def test_screen_two_distinct_certified_blocks(self):
        candidates = (((2, 2, 2), '2x2x2', 7, 'unused', False),
                      ((2, 2, 3), '2x2x3', 11, 'unused', False))
        entries = [dict(format=list(shape), rank=rank) for shape, rank in
                   (((2, 2, 2), 8), ((2, 2, 3), 12), ((2, 2, 5), 20))]
        rows = MODULE.screen(entries, candidates, max_dim=5)
        self.assertEqual([(row['shape'], row['rank'], row['operation']) for row in rows],
                         [([2, 2, 5], 18, 'pair')])

    def test_materialize_exact_doubled_orientation(self):
        row = dict(shape=[11, 24, 32], rank=4866, public_rank=4909, gap=43,
                   operation='double', orientation=[11, 16, 24], axis=1,
                   seed_shape='11x16x24', seed_rank=2433,
                   seed_sha256='81169d6204bab77f43369bd309114dcbff710cebe53275b7d2ef9c1cfc603400',
                   compressed=True)
        with tempfile.TemporaryDirectory(prefix='metaflip-certified-block-') as tmp:
            result = MODULE.materialize(row, Path(tmp))
            self.assertEqual((result['rank'], result['gap'], result['sha256']),
                             (4866, 43, 'f20c71567e7286c9ce3f543cb3dadf4e7846e5ad1df3042d2c7e5255a132d01c'))

    def test_replay_all_retained_extensions(self):
        manifest = ROOT / 'bits/tungsten-metaflip/tools/certificates/certified-block-extensions-20260923/manifest.json'
        data = json.loads(manifest.read_text())
        self.assertEqual((data['schema'], data['field'], data['record_claim'], len(data['rows'])),
                         (1, 'GF(2)', False, 14))
        with tempfile.TemporaryDirectory(prefix='metaflip-certified-block-') as tmp:
            for row in data['rows']:
                with self.subTest(shape=row['shape']):
                    result = MODULE.materialize(row, Path(tmp))
                    self.assertEqual((result['rank'], result['sha256']),
                                     (row['rank'], row['sha256']))

    def test_replay_portfolio_extensions(self):
        manifest = ROOT / 'bits/tungsten-metaflip/tools/certificates/certified-portfolio-extensions-20260923/manifest.json'
        data = json.loads(manifest.read_text())
        self.assertEqual((data['schema'], data['field'], data['record_claim'], len(data['rows'])),
                         (1, 'GF(2)', False, 5))
        selected = sorted({'x'.join(map(str, row[prefix + 'portfolio_shape']))
                           for row in data['rows'] for prefix in ('', 'right_')
                           if row.get(prefix + 'seed_source') == 'portfolio'})
        with tempfile.TemporaryDirectory(prefix='metaflip-portfolio-block-') as tmp:
            sources = Path(tmp) / 'sources'
            command = ['ruby', str(ROOT / 'bits/tungsten-metaflip/tools/replay_structured_parent_portfolio.rb'),
                       '--output', str(sources)]
            for shape in selected:
                command.extend(('--only', shape))
            subprocess.run(command, check=True, capture_output=True, text=True)
            outputs = Path(tmp) / 'outputs'
            outputs.mkdir()
            for row in data['rows']:
                with self.subTest(shape=row['shape']):
                    result = MODULE.materialize(row, outputs, sources)
                    self.assertEqual((result['rank'], result['sha256']),
                                     (row['rank'], row['sha256']))


if __name__ == '__main__':
    unittest.main()
