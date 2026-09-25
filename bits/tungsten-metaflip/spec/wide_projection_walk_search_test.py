#!/usr/bin/env python3
"""Focused replay of the exact multiword projection-walk scheduler."""
import base64
import gzip
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / "bits/tungsten-metaflip/tools/search_wide_projection_walks.py"
SOURCE = (ROOT / "bits/tungsten-metaflip/tools/certificates/"
          "wide-rectangular-walk-20260922/12x8x13-r786.mfw.gz.b64")
TIED_SOURCE = (ROOT / "bits/tungsten-metaflip/tools/certificates/"
               "wide-rectangular-walk-20260922/12x8x12-r705.mfw.gz.b64")
SPEC = importlib.util.spec_from_file_location("wide_projection_walk_search", TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WideProjectionWalkSearchTest(unittest.TestCase):
    def test_beam_spends_first_walks_on_distinct_shapes(self):
        rows = [{"shape": [8, 12, 12], "sha256": "a"},
                {"shape": [12, 8, 12], "sha256": "b"},
                {"shape": [7, 12, 12], "sha256": "c"}]
        self.assertEqual([row["sha256"] for row in MODULE.select(rows, 2)],
                         ["a", "c"])
        self.assertEqual([row["sha256"] for row in MODULE.select(rows, 3)],
                         ["a", "c", "b"])

    def test_known_rank_786_projection_is_selected(self):
        raw = gzip.decompress(base64.b64decode(SOURCE.read_bytes()))
        with tempfile.TemporaryDirectory(prefix="metaflip-wide-projection-") as tmp:
            path = Path(tmp) / "source.mfw"
            path.write_bytes(raw)
            shape, terms, sha = MODULE.verify_file(path)
        self.assertEqual((shape, len(terms), sha),
                         ((12, 8, 13), 786,
                          "e81e47cfe8f569567fb2d88472b1f28c0b859f9069180c0d45c9c323bd42d611"))
        rows = MODULE.proposals(shape, terms, {(8, 12, 12): 720})
        self.assertEqual(len(rows), 2)
        self.assertEqual((rows[0]["rank"], rows[0]["mode"], rows[0]["axis"],
                          rows[0]["coordinate"], rows[0]["sha256"]),
                         (722, 6, 2, 3,
                          "d7fc65e5f440a2051d8ec64591c3a14082cefbb431aabeb55048c41cc367a27b"))
        self.assertNotEqual(rows[0]["sha256"], rows[1]["sha256"])
        self.assertEqual(MODULE.select(rows, 1), rows[:1])

    def test_rank_ties_prefer_shared_factor_opportunity(self):
        raw = gzip.decompress(base64.b64decode(TIED_SOURCE.read_bytes()))
        shape, terms = MODULE.top.read_blob(raw)
        MODULE.top.exact(shape, terms)
        rows = MODULE.proposals(shape, terms, {(8, 11, 12): 676})
        self.assertEqual((rows[0]["rank"], rows[0]["coordinate"],
                          rows[0]["pair_counts"]), (673, 5, [0, 28, 20]))
        self.assertEqual((rows[1]["rank"], rows[1]["coordinate"],
                          rows[1]["pair_counts"]), (673, 8, [0, 27, 22]))

    def test_duplicate_basis_modes_do_not_repeat_projections(self):
        shape, terms = MODULE.top.read_blob(
            gzip.decompress(base64.b64decode(SOURCE.read_bytes())))
        with mock.patch.object(MODULE, "two_pass", return_value=terms), \
             mock.patch.object(MODULE.top, "project", wraps=MODULE.top.project) as project:
            rows = MODULE.proposals(shape, terms, {(8, 12, 12): 720})
        self.assertEqual(project.call_count, shape[2] + len(rows))

    def test_retained_projection_rejects_independent_mismatch(self):
        shape, terms = MODULE.top.read_blob(
            gzip.decompress(base64.b64decode(SOURCE.read_bytes())))
        with mock.patch.object(MODULE.neutral, "project_grid", return_value=[]):
            with self.assertRaisesRegex(ValueError, "independent projection mismatch"):
                MODULE.proposals(shape, terms, {(8, 12, 12): 720})


if __name__ == "__main__":
    unittest.main()
