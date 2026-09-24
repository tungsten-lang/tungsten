#!/usr/bin/env python3
"""Check the exact nested 8x12x15 directed chain and its Strassen product."""
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
ROOT = HERE.parents[2]
CERT = HERE / "certificates/nested-directed-20260924"
sys.path.insert(0, str(HERE))
import screen_neutral_basis_children as neutral  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def load_certificate(row, directory):
    encoded = (CERT / row["file"]).read_bytes().replace(b"\n", b"")
    raw = gzip.decompress(base64.b64decode(encoded, validate=True))
    shape, terms = top.read_blob(raw)
    if (list(shape) != row["shape"] or len(terms) != row["rank"] or
            digest(raw) != row["sha256"]):
        raise ValueError("retained certificate shape/rank/digest mismatch")
    top.exact(shape, terms)
    if "density" in row:
        density = sum(sum(factor.bit_count() for factor in term) for term in terms)
        if density != row["density"]:
            raise ValueError("retained certificate density mismatch")
    path = directory / ("x".join(map(str, shape)) + f"-r{len(terms)}.mfw")
    path.write_bytes(raw)
    checked = json.loads(subprocess.check_output(
        ["ruby", str(HERE / "verify_tensor.rb"), "--shape",
         "x".join(map(str, shape)), str(path)], text=True))[0]
    if (not checked["exact"] or checked["rank"] != row["rank"] or
            checked["sha256"] != row["sha256"] or
            ("density" in row and checked["density"] != row["density"])):
        raise ValueError("independent full-tensor verification failed")
    return shape, terms, raw, path


def project_stage(shape, terms, row):
    basis = terms if row["basis_mode"] is None else two_pass(
        terms, shape, row["basis_mode"])
    top.exact(shape, basis)
    axis, coordinate = row["project_axis"], row["deleted_coordinate"]
    child_shape, raw = top.project(shape, basis, axis, coordinate)
    keep = [list(range(extent)) for extent in shape]
    keep[axis].pop(coordinate)
    if raw != neutral.project_grid(shape, basis, keep):
        raise ValueError("independent coordinate projection mismatch")
    width = max(child_shape[0] * child_shape[1],
                child_shape[1] * child_shape[2],
                child_shape[0] * child_shape[2])
    cleaned, _ = top.compress_shared(raw, max_bits=width)
    seed_raw = top.blob(child_shape, cleaned)
    if (list(child_shape) != row["seed_shape"] or
            len(cleaned) != row["seed_rank"] or
            digest(seed_raw) != row["seed_sha256"]):
        raise ValueError("projected walk seed mismatch")
    top.exact(child_shape, cleaned)
    return child_shape, cleaned, seed_raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay-walk", type=Path,
                        help="compiled tools/wide_rect_walk.w binary")
    args = parser.parse_args()
    manifest = json.loads((CERT / "manifest.json").read_text())
    if manifest["schema"] != 1 or manifest["field"] != "GF(2)":
        raise ValueError("unexpected manifest format")
    with tempfile.TemporaryDirectory(prefix="metaflip-nested-directed-") as tmp:
        directory = Path(tmp)
        shape, terms, _, _ = load_certificate(manifest["source"], directory)
        rows = []
        for index, stage in enumerate(manifest["stages"]):
            seed_shape, _, seed_raw = project_stage(shape, terms, stage)
            shape, terms, retained_raw, _ = load_certificate(
                stage["retained"], directory)
            if args.replay_walk and stage["walk_steps"] is not None:
                walk_seed = directory / f"walk-seed-{index}.mfw"
                walk_output = directory / f"walk-output-{index}.mfw"
                walk_seed.write_bytes(seed_raw)
                subprocess.run(
                    [str(args.replay_walk), "x".join(map(str, seed_shape)),
                     str(walk_seed), str(walk_output),
                     str(stage["walk_steps"]), str(stage["walk_nonce"])],
                    check=True, capture_output=True, text=True)
                raw = walk_output.read_bytes()
                if digest(raw) != stage["walk_sha256"]:
                    raise ValueError(f"walk {index} replay mismatch")
                walk_shape, walk_terms = top.read_blob(raw)
                top.exact(walk_shape, walk_terms)
                post = stage["post_basis_mode"]
                result = walk_terms if post is None else two_pass(
                    walk_terms, walk_shape, post)
                if top.blob(walk_shape, result) != retained_raw:
                    raise ValueError(f"walk {index} retained refinement mismatch")
            elif stage["walk_steps"] is None and seed_raw != retained_raw:
                raise ValueError(f"projection {index} retained mismatch")
            rows.append({"shape": list(shape), "rank": len(terms),
                         "sha256": digest(retained_raw)})

        product = manifest["product"]
        left_shape = tuple(product["left_orientation"])
        left = top.orient(shape, terms, left_shape)
        top.exact(left_shape, left)
        seed = ROOT / product["right_seed"]
        if digest(seed.read_bytes()) != product["right_seed_sha256"]:
            raise ValueError("Strassen seed revision mismatch")
        right = top.parse_terms(seed.read_bytes(), 7)
        top.exact((2, 2, 2), right)
        target = tuple(2 * extent for extent in left_shape)
        result = top.kronecker(left_shape, left, (2, 2, 2), right)
        top.exact(target, result)
        _, _, retained, _ = load_certificate(product["retained"], directory)
        if top.blob(target, result) != retained:
            raise ValueError("Strassen product mismatch")

        print(json.dumps({"field": "GF(2)", "record_claim": False,
                          "walks_replayed": bool(args.replay_walk),
                          "stages": rows,
                          "product": {"shape": list(target), "rank": len(result),
                                      "sha256": digest(retained)}}, indent=2))


if __name__ == "__main__":
    main()
