#!/usr/bin/env python3
"""Replay projection provenance and independently check every retained tensor."""
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
    return gzip.decompress(base64.b64decode(
        path.read_bytes().replace(b"\n", b""), validate=True))


def main():
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert manifest["schema"] == 1 and manifest["field"] == "GF(2)"
    assert manifest["record_claim"] is False
    with TemporaryDirectory(prefix="metaflip-20x22x23-certificate-") as temporary:
        for row in manifest["rows"]:
            parent_raw = unpack(HERE / row["parent"])
            parent_shape, parent_terms = tensor.read_blob(parent_raw)
            tensor.exact(parent_shape, parent_terms)
            if row.get("operation") == "continuation":
                child, seed, seed_raw = parent_shape, parent_terms, parent_raw
            else:
                basis = two_pass(parent_terms, parent_shape, row["mode"])
                tensor.exact(parent_shape, basis)
                child, projected = tensor.project(parent_shape, basis,
                                                  row["axis"], row["coordinate"])
                width = max(child[0]*child[1], child[1]*child[2], child[0]*child[2])
                seed, _ = tensor.compress_shared(projected, max_bits=width)
                seed_raw = tensor.blob(child, seed)
            assert list(child) == row["shape"] and len(seed) == row["projection_rank"]
            assert hashlib.sha256(seed_raw).hexdigest() == row["projection_sha256"]
            tensor.exact(child, seed)
            raw = unpack(HERE / row["file"])
            assert hashlib.sha256(raw).hexdigest() == row["sha256"]
            if row["walks"]:
                assert row["rank"] < row["projection_rank"]
            else:
                assert raw == seed_raw
            path = Path(temporary) / row["file"][:-7]
            path.write_bytes(raw)
            checked_shape, checked_terms, checked_sha = verify_file(path)
            assert (list(checked_shape) == row["shape"] and
                    len(checked_terms) == row["rank"] and checked_sha == row["sha256"])
            print(f"PASS {row['file']} rank={row['rank']}")


if __name__ == "__main__":
    main()
