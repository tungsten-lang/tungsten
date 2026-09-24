#!/usr/bin/env python3
"""Independently replay the exact top-two directed child and its compositions."""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
CERT = HERE / "certificates/top-two-directed-20260924"
sys.path.insert(0, str(HERE))
import screen_certified_block_extensions as blocks  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify(shape, terms, expected, directory):
    if list(shape) != expected["shape"] or len(terms) != expected["rank"]:
        raise ValueError("shape or rank mismatch")
    top.exact(shape, terms)
    raw = top.blob(shape, terms)
    if digest(raw) != expected["sha256"]:
        raise ValueError("scheme digest mismatch")
    path = directory / ("x".join(map(str, shape)) + ".mfw")
    path.write_bytes(raw)
    checked = json.loads(subprocess.check_output(
        ["ruby", str(HERE / "verify_tensor.rb"), "--shape",
         "x".join(map(str, shape)), str(path)], text=True))[0]
    if (not checked["exact"] or checked["rank"] != expected["rank"] or
            checked["density"] != expected["density"] or
            checked["sha256"] != expected["sha256"]):
        raise ValueError("independent full-tensor check failed")
    return path


def replay_parent(manifest, directory):
    parent_manifest = json.loads((CERT / manifest["parent_manifest"]).read_text())
    matches = [row for row in parent_manifest["rows"]
               if row["shape"] == sorted(manifest["parent_shape"]) and
               row["sha256"] == manifest["parent_sha256"]]
    if len(matches) != 1:
        raise ValueError("missing or ambiguous certified parent")
    row = matches[0]
    sources = directory / "sources"
    top.replay_sources(sources, [row["source_portfolio_shape"]])
    parent = top.materialize(row, sources, directory / "parent")
    raw = Path(parent["output"]).read_bytes()
    shape, terms = top.read_blob(raw)
    if (list(shape) != manifest["parent_shape"] or
            len(terms) != manifest["parent_rank"] or
            digest(raw) != manifest["parent_sha256"]):
        raise ValueError("parent replay mismatch")
    return Path(parent["output"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay-walk", type=Path,
                        help="compiled tools/wide_rect_walk.w binary")
    args = parser.parse_args()
    manifest = json.loads((CERT / "manifest.json").read_text())
    with tempfile.TemporaryDirectory(prefix="metaflip-top-two-directed-") as tmp:
        directory = Path(tmp)
        parent = replay_parent(manifest, directory)
        raw = gzip.decompress(base64.b64decode(
            (CERT / manifest["retained"]["file"]).read_bytes().replace(b"\n", b""),
            validate=True))
        shape, terms = top.read_blob(raw)
        if digest(raw) != manifest["retained"]["sha256"]:
            raise ValueError("retained certificate digest mismatch")
        retained = verify(shape, terms, manifest["retained"], directory)

        if args.replay_walk:
            source = parent
            for index, walk in enumerate(manifest["walks"]):
                output = directory / f"walk-{index}.mfw"
                subprocess.run(
                    [str(args.replay_walk), "8x16x13", str(source), str(output),
                     str(manifest["walk_steps_each"]), str(walk["nonce"])],
                    check=True, stdout=subprocess.PIPE, text=True)
                if digest(output.read_bytes()) != walk["sha256"]:
                    raise ValueError(f"walk {index} replay mismatch")
                source = output
            if source.read_bytes() != retained.read_bytes():
                raise ValueError("final walk bytes differ from retained certificate")

        left = top.orient(shape, terms, (8, 13, 16))
        strassen = HERE.parent / "lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"
        right = top.parse_terms(strassen.read_bytes(), 7)
        top.exact((2, 2, 2), right)
        product = top.kronecker((8, 13, 16), left, (2, 2, 2), right)
        product_row = next(row for row in manifest["descendants"]
                           if row["construction"] == "strassen-product")
        verify((16, 26, 32), product, product_row, directory)

        pair_row = next(row for row in manifest["descendants"]
                        if row["construction"] == "certified-block-pair")
        seed = {"right_seed_shape": "13x16x24",
                "right_seed_rank": pair_row["right_rank"],
                "right_seed_sha256": pair_row["right_sha256"],
                "right_compressed": True}
        right_shape, right_terms = blocks.load_seed(seed, None, "right_")
        right = blocks.orient(right_shape, right_terms, (24, 13, 16))
        target = (32, 13, 16)
        combined = (blocks.block((8, 13, 16), left, target, (0, 0, 0)) +
                    blocks.block((24, 13, 16), right, target, (8, 0, 0)))
        cleaned, history = blocks.compress_shared(combined, max_bits=512)
        if history:
            raise ValueError("unexpected block-pair cleanup")
        verify(target, cleaned, pair_row, directory)
    print("PASS top-two directed rank 1040 and exact descendants 7280, 3882")


if __name__ == "__main__":
    main()
