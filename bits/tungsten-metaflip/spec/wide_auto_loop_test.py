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
                                      output_dir=output, rounds=1,
                                      max_walks=1, steps=1,
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
                              report["record_claim"]), ("complete", 1, False))
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
