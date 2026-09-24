#!/usr/bin/env python3
"""Verify the exact GF(2) 13x15x24/r2800 certificate and optional walk replay."""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import screen_top_two_projection_children as top
from screen_two_pass_basis_children import two_pass


HERE = Path(__file__).resolve().parent
CERT = HERE / "certificates/wide-rectangular-walk-20260922"
SOURCE = ("15x24x13-r2808.mfw.gz.b64", (15, 24, 13), 2808, 103677,
          "e0cae9b40c5485b447cea67b5edf71cf6b56a51f392e3f31be80ac9fa378e72d")
FINAL = ("15x24x13-r2800.mfw.gz.b64", (15, 24, 13), 2800, 97138,
         "d7e9b78873521d3d6b5309b95248560c41cc8edd45b08932adb6de048f96f02a")
FIRST_RAW = "1da41359b316949d4c0789afe85c9b8a071b1f96755d98cb6730f7ed00ee2919"
SECOND_INPUT = "521827486a91f959503fdbdde6d9faf20f90132d105e5496d4e605ce98403acf"
SECOND_RAW = "d02d3df7196a149ed43e17ce4f96bd792acf1cf5cec8c1670233064ff0d97480"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def load(row, directory):
    filename, shape, rank, density, expected_hash = row
    raw = gzip.decompress(base64.b64decode(
        (CERT / filename).read_bytes().replace(b"\n", b""), validate=True))
    if digest(raw) != expected_hash:
        raise ValueError("certificate digest mismatch")
    actual_shape, terms = top.read_blob(raw)
    if tuple(actual_shape) != shape or len(terms) != rank:
        raise ValueError("certificate shape/rank mismatch")
    top.exact(shape, terms)
    path = directory / filename.removesuffix(".gz.b64")
    path.write_bytes(raw)
    checked = json.loads(subprocess.check_output(
        ["ruby", str(HERE / "verify_tensor.rb"), "--shape",
         "x".join(map(str, shape)), str(path)], text=True))[0]
    if (not checked["exact"] or checked["rank"] != rank or
            checked["density"] != density or checked["sha256"] != expected_hash):
        raise ValueError("independent tensor check failed")
    return path, terms


def walk(binary, shape, source, output, nonce):
    subprocess.run([str(binary), "x".join(map(str, shape)), str(source),
                    str(output), "100000000", str(nonce)], check=True,
                   stdout=subprocess.PIPE, text=True)
    return output.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay-walk", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="metaflip-13x15x24-") as tmp:
        directory = Path(tmp)
        source, _ = load(SOURCE, directory)
        final, _ = load(FINAL, directory)
        if args.replay_walk:
            first = walk(args.replay_walk, SOURCE[1], source,
                         directory / "first.mfw", 2026092741)
            if digest(first) != FIRST_RAW:
                raise ValueError("first walk replay mismatch")
            shape, terms = top.read_blob(first)
            transformed = top.orient(shape, two_pass(terms, shape, 12),
                                     (24, 13, 15))
            second_input = top.blob((24, 13, 15), transformed)
            if digest(second_input) != SECOND_INPUT:
                raise ValueError("second walk input mismatch")
            seed = directory / "second-input.mfw"
            seed.write_bytes(second_input)
            second = walk(args.replay_walk, (24, 13, 15), seed,
                          directory / "second.mfw", 2026092769)
            if digest(second) != SECOND_RAW:
                raise ValueError("second walk replay mismatch")
            shape, terms = top.read_blob(second)
            retained = top.orient(shape, two_pass(terms, shape, 7), FINAL[1])
            if top.blob(FINAL[1], retained) != final.read_bytes():
                raise ValueError("final basis replay mismatch")
    print("PASS exact GF(2) 13x15x24/r2800 certificate")


if __name__ == "__main__":
    main()
