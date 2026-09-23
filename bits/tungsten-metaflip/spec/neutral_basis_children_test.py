#!/usr/bin/env python3
"""Replay the neutral-basis child tensors from pinned source constructions."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / 'bits/tungsten-metaflip/tools/screen_neutral_basis_children.py'
MANIFEST = ROOT / 'bits/tungsten-metaflip/tools/certificates/neutral-basis-children-20260923/manifest.json'
SPEC = importlib.util.spec_from_file_location('neutral_basis_children', TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NeutralBasisChildrenTest(unittest.TestCase):
    def test_replay_full_chain(self):
        data = json.loads(MANIFEST.read_text())
        self.assertEqual((data['schema'], data['field'], data['record_claim'],
                          data['initial_parent_count'], data['max_depth'],
                          data['basis_variants'], data['projections'],
                          len(data['rows'])),
                         (1, 'GF(2)', False, 3, 3, 36, 2574, 3))
        self.assertEqual([row['rank'] for row in data['rows']],
                         [6487, 6903, 6381])
        with tempfile.TemporaryDirectory(prefix='metaflip-neutral-basis-test-') as tmp:
            root = Path(tmp)
            parents = MODULE.build_parents(root / 'parents')
            for row in data['rows']:
                with self.subTest(shape=row['shape']):
                    verified = MODULE.materialize(row, parents, root / 'outputs')
                    self.assertEqual((verified['rank'], verified['sha256']),
                                     (row['rank'], row['sha256']))
                    parents.append(verified)
            corrupted = dict(data['rows'][0], basis_sha256='0' * 64)
            with self.assertRaisesRegex(ValueError, 'neutral basis mismatch'):
                MODULE.materialize(corrupted, parents, root / 'rejected')


if __name__ == '__main__':
    unittest.main()
