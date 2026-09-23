#!/usr/bin/env python3
"""Replay neutral-basis children of the exact structured projection archive."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / 'bits/tungsten-metaflip/tools/screen_neutral_basis_children.py'
MANIFEST = ROOT / 'bits/tungsten-metaflip/tools/certificates/structured-neutral-children-20260923/manifest.json'
SPEC = importlib.util.spec_from_file_location('structured_neutral_children', TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class StructuredNeutralChildrenTest(unittest.TestCase):
    def test_replay_full_tensor_children(self):
        data = json.loads(MANIFEST.read_text())
        self.assertEqual((data['schema'], data['field'], data['record_claim'],
                          data['parent_set'], data['initial_parent_count'],
                          data['max_depth'], data['basis_variants'],
                          data['projections'], len(data['rows'])),
                         (1, 'GF(2)', False, 'structured-projections',
                          24, 3, 152, 7914, 2))
        self.assertEqual([row['rank'] for row in data['rows']], [2676, 2671])
        with tempfile.TemporaryDirectory(prefix='metaflip-structured-neutral-test-') as tmp:
            root = Path(tmp)
            parents = MODULE.build_structured_parents(root / 'parents')
            self.assertEqual(len(parents), 24)
            for row in data['rows']:
                with self.subTest(shape=row['shape']):
                    verified = MODULE.materialize(row, parents, root / 'outputs')
                    self.assertEqual((verified['rank'], verified['sha256']),
                                     (row['rank'], row['sha256']))
                    parents.append(verified)


if __name__ == '__main__':
    unittest.main()
