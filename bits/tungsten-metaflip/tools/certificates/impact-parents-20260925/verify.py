#!/usr/bin/env python3
"""Independently replay the retained GF(2) impact-parent witnesses."""
import base64
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

if not __debug__:
    raise RuntimeError("tensor replay requires Python assertions")

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent.parent
sys.path.insert(0, str(TOOLS))
import screen_top_two_projection_children as tensor  # noqa: E402


def main():
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert manifest["schema"] == 1 and manifest["field"] == "GF(2)"
    assert manifest["record_claim"] is False
    with TemporaryDirectory(prefix="metaflip-impact-check-") as temporary:
        for row in manifest["witnesses"]:
            path = HERE / row["file"]
            assert path.parent == HERE and path.name.endswith(".mfw.gz.b64")
            raw = gzip.decompress(base64.b64decode(
                path.read_bytes().replace(b"\n", b""), validate=True))
            assert hashlib.sha256(raw).hexdigest() == row["sha256"]
            shape, terms = tensor.read_blob(raw)
            assert list(shape) == row["shape"] and len(terms) == row["rank"]
            tensor.exact(shape, terms)
            decoded = Path(temporary) / (path.name[:-7])
            decoded.write_bytes(raw)
            checked = json.loads(subprocess.check_output(
                ["ruby", str(TOOLS / "verify_tensor.rb"), "--shape",
                 "x".join(map(str, shape)), str(decoded)], text=True))[0]
            assert checked["exact"] and checked["rank"] == len(terms)
            assert checked["sha256"] == row["sha256"]
            print(f"PASS {path.name} rank={len(terms)}")


if __name__ == "__main__":
    main()
