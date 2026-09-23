#!/usr/bin/env python3
"""Focused exact replay of the top-two projection beam's retained tensors."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / 'bits/tungsten-metaflip/tools/screen_top_two_projection_children.py'
MANIFEST = ROOT / 'bits/tungsten-metaflip/tools/certificates/top-two-projection-children-20260923/manifest.json'
SPEC = importlib.util.spec_from_file_location('top_two_projection_children', TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TopTwoProjectionChildrenTest(unittest.TestCase):
    def test_replay_all_retained_tensors(self):
        data = json.loads(MANIFEST.read_text())
        self.assertEqual((data['schema'], data['field'], data['record_claim'],
                          data['first_projections'], data['first_shapes'],
                          data['per_shape'], data['rank_slack'],
                          data['selected_intermediates'], data['child_projections'],
                          len(data['rows']), len(data['extensions'])),
                         (1, 'GF(2)', False, 4279, 229, 2, 50, 211, 10521, 3, 1))
        with tempfile.TemporaryDirectory(prefix='metaflip-top-two-projection-test-') as tmp:
            sources, outputs = Path(tmp) / 'sources', Path(tmp) / 'outputs'
            MODULE.replay_sources(sources,
                                  (row['source_portfolio_shape'] for row in data['rows']))
            rows = []
            for row in data['rows']:
                with self.subTest(shape=row['shape']):
                    result = MODULE.materialize(row, sources, outputs)
                    self.assertEqual((result['rank'], result['sha256']),
                                     (row['rank'], row['sha256']))
                    rows.append(result)
            for row in data['extensions']:
                with self.subTest(extension=row['shape']):
                    result = MODULE.materialize_extension(row, rows, outputs)
                    self.assertEqual((result['rank'], result['sha256']),
                                     (row['rank'], row['sha256']))


if __name__ == '__main__':
    unittest.main()
