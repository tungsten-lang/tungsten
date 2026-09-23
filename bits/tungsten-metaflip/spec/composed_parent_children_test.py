#!/usr/bin/env python3
"""Replay the composed-parent projection chain from pinned exact schemes."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / 'bits/tungsten-metaflip/tools/screen_composed_parent_children.py'
MANIFEST = ROOT / 'bits/tungsten-metaflip/tools/certificates/composed-parent-children-20260923/manifest.json'
SPEC = importlib.util.spec_from_file_location('composed_parent_children', TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ComposedParentChildrenTest(unittest.TestCase):
    def test_replay_full_chain(self):
        data = json.loads(MANIFEST.read_text())
        self.assertEqual((data['schema'], data['field'], data['record_claim'],
                          data['source_parent_count'], data['max_depth'],
                          data['projections'], len(data['rows'])),
                         (1, 'GF(2)', False, 4, 6, 441, 3))
        self.assertEqual([row['rank'] for row in data['rows']],
                         [6996, 6905, 6499])
        with tempfile.TemporaryDirectory(prefix='metaflip-composed-child-test-') as tmp:
            root = Path(tmp)
            parents = MODULE.build_parents(root / 'sources', root / 'parents')
            for row in data['rows']:
                with self.subTest(shape=row['shape']):
                    verified = MODULE.materialize_child(row, parents,
                                                        root / 'children')
                    self.assertEqual((verified['rank'], verified['sha256']),
                                     (row['rank'], row['sha256']))
                    parents.append(verified)


if __name__ == '__main__':
    unittest.main()
