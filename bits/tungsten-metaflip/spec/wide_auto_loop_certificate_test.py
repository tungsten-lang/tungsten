#!/usr/bin/env python3
"""Focused exact replay for retained wide-loop composition certificates."""
import base64
import gzip
import json
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import search_wide_auto_loop as loop  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from verify_retained_wide_auto_loop import verify_bundle  # noqa: E402
from wide_pair_composition import compose_pairs  # noqa: E402


class WideAutoLoopCertificateTest(unittest.TestCase):
    def test_strassen_and_shared_pair_lineage(self):
        shape = (2, 2, 2)
        terms = [(1 << (i * 2 + j), 1 << (j * 2 + k), 1 << (i * 2 + k))
                 for i in range(2) for j in range(2) for k in range(2)]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bundle = root / "bundle"
            bundle.mkdir()

            def add(kind, shape, terms, parent=None, details=None):
                raw = top.blob(shape, terms)
                sha = loop.digest(raw)
                name = f"{sha}.mfw.gz.b64"
                (bundle / name).write_bytes(base64.b64encode(
                    gzip.compress(raw, mtime=0)) + b"\n")
                return dict(kind=kind, shape=list(shape), rank=len(terms),
                            sha256=sha, file=name, parent=parent,
                            details=details or {})

            source = add("source", shape, terms)
            (root / "seed.mfw").write_bytes(top.blob(shape, terms))
            projected_shape, projected_terms = top.project(shape, terms, 0, 1)
            width = max(projected_shape[0] * projected_shape[1],
                        projected_shape[1] * projected_shape[2],
                        projected_shape[0] * projected_shape[2])
            projected_terms, _ = top.compress_shared(projected_terms, max_bits=width)
            projection = add("projection-improvement", projected_shape, projected_terms,
                             source["sha256"], {"mode": None, "axis": 0, "coordinate": 1})
            strassen = top.parse_terms(loop.STRASSEN.read_bytes(), 7)
            product = top.kronecker(shape, terms, shape, strassen)
            child = add("strassen-product", (4, 4, 4), product,
                        source["sha256"], {"partner": "2x2x2-r7"})
            target, paired, pairs, raw_rank = compose_pairs(
                shape, terms, 0, max_rank=100)
            width = max(target[0] * target[1], target[1] * target[2],
                        target[0] * target[2])
            paired, _ = top.compress_shared(paired, max_bits=width)
            pair = add("shared-pair-product", target, paired,
                       source["sha256"], {"axis": 0, "pairs": pairs,
                                             "raw_rank": raw_rank})
            report = dict(schema=1, field="GF(2)", record_claim=False,
                          source="seed.mfw", rows=[source, projection, child, pair])
            (bundle / "manifest.json").write_text(json.dumps(report))
            result = verify_bundle(bundle, root=root)
            self.assertEqual(result["tensors"], 4)
            report["rows"][-1]["details"]["pairs"] += 1
            (bundle / "manifest.json").write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, "shared-pair lineage mismatch"):
                verify_bundle(bundle, root=root)
            report["rows"][-1]["details"]["pairs"] -= 1
            report["rows"][1]["details"]["axis"] = 1
            (bundle / "manifest.json").write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, "projection lineage mismatch"):
                verify_bundle(bundle, root=root)


if __name__ == "__main__":
    unittest.main()
