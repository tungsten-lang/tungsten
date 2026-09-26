#!/usr/bin/env python3
"""Independently replay a compact wide-auto-loop certificate directory."""
import argparse
import json
from pathlib import Path
import tempfile

if not __debug__:
    raise RuntimeError("wide tensor verification requires Python assertions")

import search_wide_auto_loop as loop
import screen_top_two_projection_children as top
from screen_two_pass_basis_children import two_pass
from search_wide_projection_walks import verify_file
from wide_pair_composition import compose_pairs

ROOT = Path(__file__).resolve().parents[3]


def check(condition, message):
    if not condition:
        raise ValueError(message)


def verified_raw(path, row):
    raw = loop.read_seed(path)
    shape, terms = top.read_blob(raw)
    check(loop.digest(raw) == row["sha256"], "tensor hash mismatch")
    check(list(shape) == row["shape"] and len(terms) == row["rank"],
          "tensor metadata mismatch")
    with tempfile.TemporaryDirectory() as temp:
        witness = Path(temp) / "tensor.mfw"
        witness.write_bytes(raw)
        check(verify_file(witness) == (shape, terms, row["sha256"]),
              "independent full-tensor replay mismatch")
    return raw, shape, terms


def verify_bundle(bundle, root=ROOT):
    report = json.loads((bundle / "manifest.json").read_text())
    check((report.get("schema"), report.get("field"), report.get("record_claim")) ==
          (1, "GF(2)", False), "unsupported certificate manifest")
    source = Path(report["source"])
    check(not source.is_absolute() and ".." not in source.parts,
          "unsafe source path")
    source_raw = loop.read_seed(root / source)
    strassen = top.parse_terms(loop.STRASSEN.read_bytes(), 7)
    checked = {}
    for row in report["rows"]:
        file = Path(row["file"])
        check(file.name == row["file"] and file.suffixes[-3:] ==
              [".mfw", ".gz", ".b64"], "unsafe tensor filename")
        raw, shape, terms = verified_raw(bundle / file, row)
        sha, parent_sha, kind = row["sha256"], row["parent"], row["kind"]
        check(sha not in checked, "duplicate tensor identity")
        if parent_sha is None:
            check(kind == "source" and raw == source_raw, "source mismatch")
        else:
            check(parent_sha in checked, "parent missing or out of order")
            parent_shape, parent_terms = checked[parent_sha]
            details = row["details"]
            if kind == "basis":
                expected = two_pass(parent_terms, parent_shape, details["mode"])
                check(shape == parent_shape and top.blob(shape, expected) == raw,
                      "basis lineage mismatch")
            elif kind.startswith("projection"):
                mode = details["mode"]
                basis = (parent_terms if mode is None else
                         two_pass(parent_terms, parent_shape, mode))
                child_shape, projected = top.project(parent_shape, basis,
                                                     details["axis"], details["coordinate"])
                width = max(child_shape[0] * child_shape[1],
                            child_shape[1] * child_shape[2],
                            child_shape[0] * child_shape[2])
                cleaned, _ = top.compress_shared(projected, max_bits=width)
                check(shape == child_shape and top.blob(shape, cleaned) == raw,
                      "projection lineage mismatch")
            elif kind == "walk":
                check(shape == parent_shape and len(terms) <= len(parent_terms) and
                      details["steps"] > 0, "walk metadata mismatch")
            elif kind == "strassen-product":
                target = tuple(2 * d for d in parent_shape)
                product = top.kronecker(parent_shape, parent_terms,
                                        (2, 2, 2), strassen)
                check(shape == target and top.blob(target, product) == raw,
                      "Strassen lineage mismatch")
            elif kind == "shared-pair-product":
                built = compose_pairs(parent_shape, parent_terms, details["axis"],
                                      max_rank=16384)
                check(built is not None, "missing pair composition")
                target, product, pairs, raw_rank = built
                width = max(target[0] * target[1], target[1] * target[2],
                            target[0] * target[2])
                cleaned, _ = top.compress_shared(product, max_bits=width)
                check(shape == target and top.blob(target, cleaned) == raw and
                      pairs == details["pairs"] and raw_rank == details["raw_rank"],
                      "shared-pair lineage mismatch")
            else:
                raise ValueError(f"unknown lineage kind: {kind}")
        checked[sha] = shape, terms
    check(bool(checked), "empty certificate")
    best = {}
    for shape, terms in checked.values():
        key = "x".join(map(str, shape))
        best[key] = min(best.get(key, len(terms)), len(terms))
    return {"tensors": len(checked), "best": best}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify_bundle(args.bundle), sort_keys=True))


if __name__ == "__main__":
    main()
