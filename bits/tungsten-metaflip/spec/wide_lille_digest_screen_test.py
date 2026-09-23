#!/usr/bin/env python3
"""Focused checks for public-rank screening of exact GF(2) witnesses."""
import importlib.util
from pathlib import Path
import sys
import unittest


TOOL = Path(__file__).resolve().parents[1] / 'tools/screen_wide_lille_digest.py'
sys.path.insert(0, str(TOOL.parent))
spec = importlib.util.spec_from_file_location('screen_wide_lille_digest', TOOL)
screen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screen)


class LilleDigestScreenTest(unittest.TestCase):
    def test_canonical_shapes_and_best_local_rank(self):
        entries = [{'format': [2, 3, 4], 'rank': 19},
                   {'format': [3, 4, 5], 'rank': 30}]
        candidates = [((4, 2, 3), '4x2x3', 21, '', False),
                      ((2, 3, 4), '2x3x4', 18, '', False),
                      ((5, 3, 4), '5x3x4', 33, '', False)]
        self.assertEqual(screen.compare(entries, candidates), [
            {'shape': [2, 3, 4], 'local_gf2_rank': 18, 'lille_rank': 19, 'gap': -1},
            {'shape': [3, 4, 5], 'local_gf2_rank': 33, 'lille_rank': 30, 'gap': 3}])

    def test_missing_public_shape_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'missing 1 archive shapes'):
            screen.compare([], [((2, 3, 4), '2x3x4', 18, '', False)])

    def test_conflicting_public_rank_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'conflicting Lille ranks'):
            screen.compare([{'format': [2, 3, 4], 'rank': 19},
                            {'format': [4, 2, 3], 'rank': 20}], [])


if __name__ == '__main__':
    unittest.main()
