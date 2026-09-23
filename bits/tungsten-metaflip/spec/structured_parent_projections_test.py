#!/usr/bin/env python3
"""Focused exact replay of retained structured-parent coordinate projections."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / 'bits/tungsten-metaflip/tools/screen_structured_parent_projections.py'
MANIFEST = ROOT / 'bits/tungsten-metaflip/tools/certificates/structured-parent-projections-20260923/manifest.json'
SPEC = importlib.util.spec_from_file_location('structured_parent_projections', TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class StructuredParentProjectionsTest(unittest.TestCase):
    def test_fast_projection_matches_independent_grid(self):
        from verify_coordinate_projections import project_grid
        shape = (3, 4, 5)
        terms = [(0b101101101011, 0b10110010010101011111, 0b101001111011001),
                 (0b111111111111, 0b11111111111111111111, 0b111111111111111)]
        for dimension, extent in enumerate(shape):
            for coordinate in range(extent):
                with self.subTest(dimension=dimension, coordinate=coordinate):
                    target, projected = MODULE.project(shape, terms, dimension, coordinate)
                    keep = [list(range(n)) for n in shape]
                    keep[dimension].pop(coordinate)
                    self.assertEqual(target[dimension], extent - 1)
                    self.assertEqual(projected, project_grid(shape, terms, keep))

    def test_replay_all_retained_projections(self):
        data = json.loads(MANIFEST.read_text())
        self.assertEqual((data['schema'], data['field'], data['record_claim'],
                          data['source_parents'], data['projections'],
                          len(data['rows']), len(data['extensions'])),
                         (1, 'GF(2)', False, 81, 4279, 16, 1))
        self.assertEqual(len({tuple(row['shape']) for row in data['rows']}), 16)
        with tempfile.TemporaryDirectory(prefix='metaflip-structured-projection-') as tmp:
            sources, outputs = Path(tmp) / 'sources', Path(tmp) / 'outputs'
            MODULE.replay_sources(sources, (row['source_portfolio_shape'] for row in data['rows']))
            for row in data['rows']:
                with self.subTest(shape=row['shape']):
                    result = MODULE.materialize(row, sources, outputs)
                    self.assertEqual((result['rank'], result['sha256']),
                                     (row['rank'], row['sha256']))
            for row in data['extensions']:
                with self.subTest(extension=row['shape']):
                    result = MODULE.materialize_extension(row, outputs, outputs)
                    self.assertEqual((result['rank'], result['sha256']),
                                     (row['rank'], row['sha256']))


if __name__ == '__main__':
    unittest.main()
