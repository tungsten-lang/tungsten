from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from catalog_gf2_export import export


ROOT = Path(__file__).resolve().parent


class CatalogGF2ExportTest(unittest.TestCase):
    def test_strassen_roundtrip_and_w_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "strassen.json"
            rank = export(
                ROOT / "matmul_2x2_rank7_strassen_gf2.txt", output, 2, 2, 2
            )
            data = json.loads(output.read_text())
        self.assertEqual(rank, 7)
        self.assertEqual(data["n"], [2, 2, 2])
        self.assertEqual(data["m"], 7)
        self.assertIs(data["z2"], True)
        self.assertTrue(all(len(row) == 4 for row in data["u"]))
        self.assertTrue(all(len(row) == 4 for row in data["v"]))
        self.assertTrue(all(len(row) == 4 for row in data["w"]))

    def test_wrong_shape_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bad.json"
            with self.assertRaises(ValueError):
                export(
                    ROOT / "matmul_2x2_rank7_strassen_gf2.txt",
                    output,
                    2,
                    2,
                    1,
                )


if __name__ == "__main__":
    unittest.main()
