#!/usr/bin/env python3
"""Replay the small rank-only price index against separately stored witnesses.

The index does not redistribute imported terms. It affects search scheduling,
never candidate admission or world-record claims.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

from search_wide_auto_loop import ARCHIVED_PRICE_INDEX, archived_price_minima
from screen_top_two_projection_children import exact, parse_terms

HERE = Path(__file__).resolve().parent
RUBY = HERE / "verify_tensor.rb"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check(index_path, archive_dir):
    archived_price_minima(index_path)
    index = json.loads(index_path.read_text())
    witnesses = 0
    for source_name, source in index["sources"].items():
        asset = archive_dir / source["asset"]
        if sha256_file(asset) != source["sha256"]:
            raise ValueError(f"archive digest mismatch: {asset}")
        with tarfile.open(asset, "r:gz") as archive:
            for row in index["bounds"]:
                if row["source"] != source_name:
                    continue
                member = archive.extractfile(row["member"])
                if member is None:
                    raise ValueError(f"missing archive member: {row['member']}")
                raw = member.read()
                if hashlib.sha256(raw).hexdigest() != row["sha256"]:
                    raise ValueError(f"witness digest mismatch: {row['member']}")
                shape = tuple(row["witness_shape"])
                terms = parse_terms(raw, row["rank"])
                exact(shape, terms)
                checked = json.loads(subprocess.check_output(
                    ["ruby", "-r", str(RUBY), "-r", "json", "-e",
                     "puts JSON.generate(MetaflipTensorVerifier.verify_text(STDIN.read, *ARGV.map(&:to_i)))",
                     *map(str, shape)], input=raw))
                if (checked["exact"] is not True or
                        checked["rank"] != row["rank"] or
                        checked["sha256"] != row["sha256"]):
                    raise ValueError(f"independent tensor mismatch: {row['member']}")
                witnesses += 1
    if witnesses != len(index["bounds"]):
        raise ValueError("unreplayed archived price row")
    return witnesses


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive_dir", type=Path)
    parser.add_argument("--index", type=Path, default=ARCHIVED_PRICE_INDEX)
    args = parser.parse_args()
    count = check(args.index, args.archive_dir)
    print(json.dumps({"field": "GF(2)", "exact_witnesses": count,
                      "record_claim": False}))
