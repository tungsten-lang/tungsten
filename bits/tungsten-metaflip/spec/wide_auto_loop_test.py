#!/usr/bin/env python3
"""Focused exact-gate and basis-diversity checks for the cold loop."""
import argparse
import base64
from contextlib import redirect_stdout
import gzip
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import screen_top_two_projection_children as top  # noqa: E402
import search_wide_auto_loop as loop  # noqa: E402

CERT = TOOLS / "certificates/7x12x16-directed-20260925/7x16x12-r873.mfw.gz.b64"


class WideAutoLoopTest(unittest.TestCase):
    def source(self):
        return gzip.decompress(base64.b64decode(CERT.read_bytes()))

    def test_basis_beam_covers_distinct_axis_orders(self):
        shape, terms = top.read_blob(self.source())
        rows = loop.basis_proposals(shape, terms, 2)
        self.assertEqual([row["mode"] for row in rows], [6, 12])
        self.assertEqual([row["rank"] for row in rows], [873, 873])

    def test_round_budget_keeps_descendant_slots_and_both_basis_orders(self):
        self.assertEqual(loop.round_walk_limit(0, 6, 0, 2), 3)
        self.assertEqual(loop.round_walk_limit(3, 6, 1, 2), 6)
        projected = [dict(shape=(7, 16, 11), rank=835, mode="p0"),
                     dict(shape=(7, 16, 11), rank=836, mode="p1")]
        basis = [dict(shape=(7, 16, 12), rank=871, mode=mode)
                 for mode in ("b6", "b12", "b7", "b13")]
        prices = {(7, 11, 16): 822, (7, 12, 16): 871}
        order = loop.ordered_choices(projected, basis,
                                     lambda shape: prices[shape])
        self.assertEqual([row["mode"] for row in order],
                         ["b6", "b12", "p0", "b7", "b13", "p1"])
        prices[(7, 11, 16)] = 835
        order = loop.ordered_choices(projected, basis,
                                     lambda shape: prices[shape])
        self.assertEqual([row["mode"] for row in order][:3],
                         ["p0", "b6", "b12"])
        states = [dict(shape=(7, 16, 11), terms=[0] * 833, sha256="projected"),
                  dict(shape=(7, 16, 12), terms=[0] * 871, sha256="basis")]
        prices[(7, 11, 16)] = 822
        states.sort(key=lambda state: loop.frontier_priority(
            state, lambda shape: prices[shape]))
        self.assertEqual([state["sha256"] for state in states],
                         ["basis", "projected"])

    def test_projection_walk_composition_handoff(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "seed.mfw"
            source.write_bytes(self.source())
            catalog = root / "catalog.json"
            catalog.write_text("{}")
            walker = root / "copy-walker"
            walker.write_text("#!/usr/bin/env python3\nimport shutil, sys\n"
                              "shutil.copyfile(sys.argv[2], sys.argv[3])\n")
            walker.chmod(0o755)
            output = root / "output"
            args = argparse.Namespace(seed=source, catalog=catalog,
                                      walker=walker,
                                      output_dir=output, rounds=2,
                                      max_walks=2, steps=1,
                                      projection_beam=1, basis_beam=2,
                                      frontier_cap=4,
                                      max_composed_rank=8000,
                                      max_search_rank=3000,
                                      nonce_base=24001)
            with patch.object(loop, "initial_seeds", return_value={
                    (7, 12, 16): 876, (14, 24, 32): 6132}):
                with redirect_stdout(io.StringIO()):
                    loop.run(args)
            report = json.loads((output / "manifest.json").read_text())
            self.assertEqual((report["status"], report["walks"],
                              report["record_claim"]), ("complete", 2, False))
            kinds = {row["kind"] for row in report["rows"]}
            self.assertTrue({"source", "projection-seed", "strassen-product"} <= kinds)
            source_row = next(row for row in report["rows"] if row["kind"] == "source")
            self.assertEqual((source_row["old_price"], source_row["rank"]),
                             (876, 873))
            for row in report["rows"]:
                path = output / row["path"]
                shape, terms = top.read_blob(path.read_bytes())
                self.assertEqual((list(shape), len(terms)),
                                 (row["shape"], row["rank"]))
                top.exact(shape, terms)


if __name__ == "__main__":
    unittest.main()
