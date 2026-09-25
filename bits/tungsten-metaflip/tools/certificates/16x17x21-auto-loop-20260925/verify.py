#!/usr/bin/env python3
"""Replay the retained GF(2) tensors and their exact projection lineage."""
import json
from pathlib import Path
import sys
import tempfile

if not __debug__:
    raise RuntimeError("certificate verification requires Python assertions")

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[1]
ROOT = HERE.parents[4]
sys.path.insert(0, str(TOOLS))
import search_wide_auto_loop as loop  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402
from search_wide_projection_walks import verify_file  # noqa: E402

report = json.loads((HERE / "manifest.json").read_text())
assert (report["schema"], report["field"], report["record_claim"]) == (1, "GF(2)", False)
source = Path(report["source"])
assert not source.is_absolute() and ".." not in source.parts
source_raw = loop.read_seed(ROOT / source)
parents = {}
for row in report["rows"]:
    raw = loop.read_seed(HERE / row["file"])
    assert loop.digest(raw) == row["sha256"]
    shape, terms = top.read_blob(raw)
    assert (list(shape), len(terms)) == (row["shape"], row["rank"])
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "tensor.mfw"
        path.write_bytes(raw)
        assert verify_file(path) == (shape, terms, row["sha256"])
    if row["parent"] is None:
        assert row["kind"] == "source" and raw == source_raw
    else:
        parent_shape, parent_terms = parents[row["parent"]]
        if row["kind"].startswith("projection"):
            details = row["details"]
            basis = two_pass(parent_terms, parent_shape, details["mode"])
            child_shape, projected = top.project(parent_shape, basis,
                                                 details["axis"], details["coordinate"])
            width = max(child_shape[0] * child_shape[1], child_shape[1] * child_shape[2],
                        child_shape[0] * child_shape[2])
            compressed, _ = top.compress_shared(projected, max_bits=width)
            assert top.blob(child_shape, compressed) == raw
        elif row["kind"] == "basis":
            assert top.blob(parent_shape,
                            two_pass(parent_terms, parent_shape, row["details"]["mode"])) == raw
        else:
            assert row["kind"] == "walk" and shape == parent_shape
            assert row["details"]["steps"] > 0
    parents[row["sha256"]] = shape, terms

assert len(parents) == 9
assert any(row["shape"] == [16, 17, 21] and row["rank"] == 3321
           for row in report["rows"])
print("PASS nine exact GF(2) tensors; projection/basis lineage and Ruby full-tensor checks")
