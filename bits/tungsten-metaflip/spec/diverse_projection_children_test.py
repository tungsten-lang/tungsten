#!/usr/bin/env python3
"""Focused screen and exact replay of near-best projection descendants."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / 'bits/tungsten-metaflip/tools/screen_diverse_projection_children.py'
MANIFEST = ROOT / 'bits/tungsten-metaflip/tools/certificates/diverse-projection-children-20260923/manifest.json'
SPEC = importlib.util.spec_from_file_location('diverse_projection_children', TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DiverseProjectionChildrenTest(unittest.TestCase):
    def test_two_step_screen_and_exact_replay(self):
        pinned = json.loads(MANIFEST.read_text())
        self.assertEqual((pinned['schema'], pinned['field'], pinned['record_claim'],
                          pinned['first_rank_slack'], pinned['intermediate_count'],
                          pinned['child_projections'], len(pinned['rows'])),
                         (1, 'GF(2)', False, 25, 207, 11266, 2))
        digest = {'entries': [dict(format=row['shape'], rank=row['public_rank'])
                              for row in pinned['rows']]}
        with tempfile.TemporaryDirectory(prefix='metaflip-diverse-projection-test-') as tmp:
            sources, outputs = Path(tmp) / 'sources', Path(tmp) / 'outputs'
            MODULE.replay_sources(sources,
                                  (entry['shape'] for entry in MODULE.relevant_sources()))
            screened = MODULE.screen(digest, sources)
            self.assertEqual((screened['intermediate_count'], screened['child_projections']),
                             (207, 11266))
            self.assertEqual(screened['rows'], pinned['rows'])
            for row in pinned['rows']:
                with self.subTest(shape=row['shape']):
                    result = MODULE.materialize(row, sources, outputs)
                    self.assertEqual((result['rank'], result['sha256']),
                                     (row['rank'], row['sha256']))


if __name__ == '__main__':
    unittest.main()
