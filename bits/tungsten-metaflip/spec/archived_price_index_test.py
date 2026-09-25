#!/usr/bin/env python3
"""Focused exact-replay and corrupt-witness gates for archived price metadata."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import check_archived_price_index as audit  # noqa: E402
import search_wide_auto_loop as loop  # noqa: E402


class ArchivedPriceIndexTest(unittest.TestCase):
    def test_exact_witness_required_even_with_matching_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            def fixture(raw, name):
                archive = root / f"{name}.tar.gz"
                with tarfile.open(archive, "w:gz") as bundle:
                    member = tarfile.TarInfo("witness.txt")
                    member.size = len(raw)
                    bundle.addfile(member, io.BytesIO(raw))
                index = root / f"{name}.json"
                index.write_text(json.dumps({
                    "schema": 1, "field": "GF(2)", "record_claim": False,
                    "sources": {"fixture": {"asset": archive.name,
                                            "sha256": audit.sha256_file(archive)}},
                    "bounds": [{"shape": [2, 2, 2],
                                "witness_shape": [2, 2, 2],
                                "rank": int(raw.splitlines()[0]),
                                "source": "fixture", "member": "witness.txt",
                                "sha256": hashlib.sha256(raw).hexdigest()}]}))
                return index

            valid = loop.STRASSEN.read_bytes()
            self.assertEqual(audit.check(fixture(valid, "valid"), root), 1)
            with self.assertRaises(AssertionError):
                audit.check(fixture(b"1\n1 1 1\n", "false"), root)


if __name__ == "__main__":
    unittest.main()
