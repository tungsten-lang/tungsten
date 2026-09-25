#!/usr/bin/env python3
"""Replay parent projections and independently check retained GF(2) tensors."""
import base64
import gzip
import hashlib
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

if not __debug__:
    raise RuntimeError("tensor replay requires Python assertions")

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent.parent
sys.path.insert(0, str(TOOLS))
import screen_top_two_projection_children as tensor  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402
from search_wide_projection_walks import verify_file  # noqa: E402


def unpack(path):
    if path.name != path.name.split("/")[-1] or not path.name.endswith(".mfw.gz.b64"):
        raise ValueError("invalid witness name")
    return gzip.decompress(base64.b64decode(
        path.read_bytes().replace(b"\n", b""), validate=True))


def main():
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert manifest["schema"] == 1 and manifest["field"] == "GF(2)"
    assert manifest["record_claim"] is False
    parent_dir = HERE.parent / "impact-parents-20260925"
    parents = {row["file"]: row for row in
               json.loads((parent_dir / "manifest.json").read_text())["witnesses"]}
    with TemporaryDirectory(prefix="metaflip-impact-projection-") as temporary:
        for row in manifest["rows"]:
            parent = parents[row["parent"]]
            parent_raw = unpack(parent_dir / row["parent"])
            assert hashlib.sha256(parent_raw).hexdigest() == parent["sha256"]
            shape, terms = tensor.read_blob(parent_raw)
            assert list(shape) == parent["shape"] and len(terms) == parent["rank"]
            tensor.exact(shape, terms)
            mode = row["mode"]
            basis = terms if mode is None else two_pass(terms, shape, mode)
            tensor.exact(shape, basis)
            child, projected = tensor.project(shape, basis, row["axis"],
                                              row["coordinate"])
            width = max(child[0]*child[1], child[1]*child[2], child[0]*child[2])
            seed, _ = tensor.compress_shared(projected, max_bits=width)
            assert list(child) == row["shape"] and len(seed) == row["projection_rank"]
            tensor.exact(child, seed)
            assert hashlib.sha256(tensor.blob(child, seed)).hexdigest() == row["projection_sha256"]
            raw = unpack(HERE / row["file"])
            assert hashlib.sha256(raw).hexdigest() == row["sha256"]
            output = Path(temporary) / (row["file"][:-7])
            output.write_bytes(raw)
            checked_shape, checked_terms, checked_sha = verify_file(output)
            assert (list(checked_shape) == row["shape"] and
                    len(checked_terms) == row["rank"] and checked_sha == row["sha256"])
            assert row["rank"] < row["projection_rank"]
            print(f"PASS {row['file']} rank={row['rank']}")


if __name__ == "__main__":
    main()
