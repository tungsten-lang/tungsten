#!/usr/bin/env python3
"""Verify two exact tensors and their independently replayable lineage."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

if not __debug__:
    raise RuntimeError("certificate verification requires Python assertions")

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
import screen_top_two_projection_children as top  # noqa: E402
import search_wide_auto_loop as loop  # noqa: E402
from search_wide_projection_walks import verify_file  # noqa: E402
from verify_coordinate_projections import project_grid  # noqa: E402


def full_check(raw, expected, path):
    path.write_bytes(raw)
    shape, terms, sha = verify_file(path)
    assert list(shape) == expected["shape"]
    assert len(terms) == expected["rank"]
    assert sha == expected["sha256"]
    return shape, terms


def project(shape, terms, row):
    axis = row["projection"]["axis"]
    coordinate = row["projection"]["coordinate"]
    child, projected = top.project(shape, terms, axis, coordinate)
    keep = [list(range(size)) for size in shape]
    keep[axis].pop(coordinate)
    assert projected == project_grid(shape, terms, keep)
    width = max(child[0] * child[1], child[1] * child[2], child[0] * child[2])
    reduced, _ = top.compress_shared(projected, max_bits=width)
    top.exact(child, reduced)
    raw = top.blob(child, reduced)
    assert len(reduced) == row["projection"]["rank"]
    assert loop.digest(raw) == row["projection"]["sha256"]
    return child, raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--walker", type=Path)
    args = parser.parse_args()
    report = json.loads((HERE / "manifest.json").read_text())
    assert (report["schema"], report["field"], report["record_claim"]) == (1, "GF(2)", False)
    assert len(report["rows"]) == 2
    source = loop.read_seed(HERE / report["source"])
    assert loop.digest(source) == report["source_sha256"]
    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        parent_shape, parent_terms = top.read_blob(source)
        top.exact(parent_shape, parent_terms)
        assert (parent_shape, len(parent_terms)) == ((19, 21, 25), 5682)
        for index, row in enumerate(report["rows"]):
            child_shape, projected = project(parent_shape, parent_terms, row)
            seed = temp / f"seed-{index}.mfw"
            seed.write_bytes(projected)
            if args.walker:
                assert args.walker.is_file()
                for stage, walk in enumerate(row["walks"]):
                    output = temp / f"walk-{index}-{stage}.mfw"
                    subprocess.run([str(args.walker), "x".join(map(str, child_shape)),
                                    str(seed), str(output), str(walk["steps"]),
                                    str(walk["nonce"])], check=True)
                    seed = output
            raw = loop.read_seed(HERE / row["file"])
            if args.walker:
                assert seed.read_bytes() == raw
            parent_shape, parent_terms = full_check(raw, row, temp / f"checked-{index}.mfw")
    print("PASS two exact GF(2) tensors; projection lineage, rank and SHA-256; Ruby full-tensor checks" +
          ("; deterministic walks" if args.walker else ""))


if __name__ == "__main__":
    main()
