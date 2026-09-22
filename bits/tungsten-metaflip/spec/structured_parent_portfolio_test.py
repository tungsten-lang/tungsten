#!/usr/bin/env python3
"""Replay the compact GF(2) portfolio with a separate tensor parity checker."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


BIT = Path(__file__).resolve().parents[1]
ROOT = BIT.parents[1]
TOOL = BIT / 'tools/replay_structured_parent_portfolio.rb'
MANIFEST = BIT / 'tools/certificates/structured-parent-portfolio-20260922/manifest.json'
VERIFIER = ROOT / 'benchmarks/matmul/metaflip/verify_block_composition_records.py'
spec = importlib.util.spec_from_file_location('independent_tensor_verifier', VERIFIER)
verifier = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = verifier
spec.loader.exec_module(verifier)


class StructuredParentPortfolioTest(unittest.TestCase):
    def test_rejects_mutated_tensor_hash(self):
        manifest = json.loads(MANIFEST.read_text())
        row = next(row for row in manifest['rows'] if row['shape'] == [5, 9, 20])
        row['result_sha256'] = '0' * 64
        with tempfile.TemporaryDirectory(prefix='metaflip-structured-tamper-') as tmp:
            changed = Path(tmp) / 'manifest.json'
            changed.write_text(json.dumps(manifest))
            replay = subprocess.run(['ruby', str(TOOL), '--manifest', str(changed),
                                     '--output', str(Path(tmp) / 'output'), '--only', '5x9x20'],
                                    capture_output=True, text=True)
            self.assertNotEqual(replay.returncode, 0)
            self.assertIn('result mismatch', replay.stderr)

    def test_all_exact_tensors(self):
        manifest = json.loads(MANIFEST.read_text())
        self.assertEqual((manifest['schema'], manifest['field'], len(manifest['rows'])), (1, 'GF(2)', 81))
        with tempfile.TemporaryDirectory(prefix='metaflip-structured-portfolio-') as tmp:
            output = Path(tmp) / 'output'
            replay = subprocess.run(['ruby', str(TOOL), '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(replay.returncode, 0, replay.stderr)
            certificates = Path(tmp) / 'certificates'
            certificates.mkdir()
            for row in manifest['rows']:
                shape = row['shape']
                recipe_path = output / 'x'.join(map(str, shape)) / ('x'.join(map(str, row['result_shape'])) + '.recipe.json')
                recipe = json.loads(recipe_path.read_text())
                result = recipe['result']
                original = recipe_path.parent / result['path']
                raw = original.read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), row['result_sha256'])
                lines = raw.decode('ascii').splitlines()
                self.assertEqual(int(lines.pop(0)), row['rank'])
                self.assertEqual(len(lines), row['rank'])
                body = ''.join(('R ' + line.removeprefix('R ') + '\n') for line in lines)
                name = 'x'.join(map(str, shape)) + '.txt'
                (certificates / name).write_text(body)
                record = verifier.Record(name.removesuffix('.txt'), tuple(row['result_shape']), row['rank'],
                                         name, hashlib.sha256(body.encode()).hexdigest())
                checked = verifier._verify_one((certificates, record))
                self.assertEqual(checked.tensor_ones, shape[0] * shape[1] * shape[2])
                self.assertLess(row['rank'], row['catalog_recursive_bound'])


if __name__ == '__main__':
    unittest.main()
