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
import screen_two_pass_basis_children as basis  # noqa: E402


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify(shape, terms, expected, directory):
    if list(shape) != expected["shape"] or len(terms) != expected["rank"]:
        raise ValueError("shape or rank mismatch")
    top.exact(shape, terms)
    raw = top.blob(shape, terms)
    if digest(raw) != expected["sha256"]:
        raise ValueError("scheme digest mismatch")
    path = directory / ("x".join(map(str, shape)) +
                        f"-r{len(terms)}-{expected['sha256'][:12]}.mfw")
    path.write_bytes(raw)
    checked = json.loads(subprocess.check_output(
        ["ruby", str(HERE / "verify_tensor.rb"), "--shape",
         "x".join(map(str, shape)), str(path)], text=True))[0]
    if (not checked["exact"] or checked["rank"] != expected["rank"] or
            checked["density"] != expected["density"] or
            checked["sha256"] != expected["sha256"]):
        raise ValueError("independent full-tensor check failed")
    return path


def load_cert(row, directory):
    raw = gzip.decompress(base64.b64decode(
        (CERT / row["file"]).read_bytes().replace(b"\n", b""),
        validate=True))
    if digest(raw) != row["sha256"]:
        raise ValueError("retained certificate digest mismatch")
    shape, terms = top.read_blob(raw)
    path = verify(shape, terms, row, directory)
    return shape, terms, path


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


def verify_descendants(shape, terms, rows, directory):
    by_kind = {row["construction"]: row for row in rows}
    left = top.orient(shape, terms, (8, 13, 16))
    strassen = HERE.parent / "lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"
    right = top.parse_terms(strassen.read_bytes(), 7)
    top.exact((2, 2, 2), right)
    product = top.kronecker((8, 13, 16), left, (2, 2, 2), right)
    verify((16, 26, 32), product, by_kind["strassen-product"], directory)

    for pair_row in rows:
        if not pair_row["construction"].startswith("certified-block-pair"):
            continue
        source = pair_row["right_shape"]
        seed = {"right_seed_shape": "x".join(map(str, source)),
                "right_seed_rank": pair_row["right_rank"],
                "right_seed_sha256": pair_row["right_sha256"],
                "right_compressed": True}
        right_shape, right_terms = blocks.load_seed(seed, None, "right_")
        target = tuple(pair_row["shape"])
        right_orientation = (target[0] - 8, 13, 16)
        right = blocks.orient(right_shape, right_terms, right_orientation)
        combined = (blocks.block((8, 13, 16), left, target, (0, 0, 0)) +
                    blocks.block(right_orientation, right, target, (8, 0, 0)))
        width = max(target[0] * target[1], target[1] * target[2],
                    target[0] * target[2])
        cleaned, history = blocks.compress_shared(combined, max_bits=width)
        if history:
            raise ValueError("unexpected block-pair cleanup")
        verify(target, cleaned, pair_row, directory)

    if "naive-append" in by_kind:
        target = (8, 13, 17)
        combined = (blocks.block((8, 13, 16), left, target, (0, 0, 0)) +
                    blocks.block((8, 13, 1), blocks.naive((8, 13, 1)),
                                 target, (0, 0, 16)))
        cleaned, history = blocks.compress_shared(combined, max_bits=221)
        if history:
            raise ValueError("unexpected append cleanup")
        verify(target, cleaned, by_kind["naive-append"], directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay-walk", type=Path,
                        help="compiled tools/wide_rect_walk.w binary")
    args = parser.parse_args()
    manifest = json.loads((CERT / "manifest.json").read_text())
    with tempfile.TemporaryDirectory(prefix="metaflip-top-two-directed-") as tmp:
        directory = Path(tmp)
        parent = replay_parent(manifest, directory)
        shape, terms, retained = load_cert(manifest["retained"], directory)

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

        verify_descendants(shape, terms, manifest["descendants"], directory)

        symmetric = manifest["symmetric_walk"]
        orientation = tuple(symmetric["input_shape"])
        sym_terms = top.orient(shape, terms, orientation)
        sym_raw = top.blob(orientation, sym_terms)
        if (len(sym_terms) != symmetric["input_rank"] or
                digest(sym_raw) != symmetric["input_sha256"]):
            raise ValueError("symmetric input mismatch")
        strong_shape, strong_terms, strong_path = load_cert(
            symmetric["retained"], directory)

        if args.replay_walk:
            sym_input = directory / "sym-input.mfw"
            sym_input.write_bytes(sym_raw)
            output = directory / "sym-walk.mfw"
            subprocess.run(
                [str(args.replay_walk), "16x13x8", str(sym_input), str(output),
                 str(symmetric["steps"]), str(symmetric["nonce"])],
                check=True, stdout=subprocess.PIPE, text=True)
            if output.read_bytes() != strong_path.read_bytes():
                raise ValueError("symmetric walk replay mismatch")

        verify_descendants(strong_shape, strong_terms,
                           manifest["stronger_descendants"], directory)

        basis_walk = manifest["basis_walk"]
        basis_input = basis.two_pass(
            strong_terms, strong_shape, basis_walk["mode"])
        basis_raw = top.blob(strong_shape, basis_input)
        if (list(strong_shape) != basis_walk["input_shape"] or
                len(basis_input) != basis_walk["input_rank"] or
                digest(basis_raw) != basis_walk["input_sha256"]):
            raise ValueError("basis input mismatch")
        middle_shape, middle_terms, middle_path = load_cert(
            basis_walk["retained"], directory)
        if args.replay_walk:
            source = directory / "basis-input.mfw"
            source.write_bytes(basis_raw)
            output = directory / "basis-walk.mfw"
            subprocess.run(
                [str(args.replay_walk), "16x13x8", str(source), str(output),
                 str(basis_walk["steps"]), str(basis_walk["nonce"])],
                check=True, stdout=subprocess.PIPE, text=True)
            if output.read_bytes() != middle_path.read_bytes():
                raise ValueError("basis walk replay mismatch")

        final_walk = manifest["final_walk"]
        final_orientation = tuple(final_walk["input_shape"])
        final_input = top.orient(middle_shape, middle_terms, final_orientation)
        final_raw = top.blob(final_orientation, final_input)
        if (len(final_input) != final_walk["input_rank"] or
                digest(final_raw) != final_walk["input_sha256"]):
            raise ValueError("final walk input mismatch")
        final_shape, final_terms, final_path = load_cert(
            final_walk["retained"], directory)
        if args.replay_walk:
            source = directory / "final-input.mfw"
            source.write_bytes(final_raw)
            output = directory / "final-walk.mfw"
            subprocess.run(
                [str(args.replay_walk), "8x16x13", str(source), str(output),
                 str(final_walk["steps"]), str(final_walk["nonce"])],
                check=True, stdout=subprocess.PIPE, text=True)
            raw_output = output.read_bytes()
            if digest(raw_output) != final_walk["raw_sha256"]:
                raise ValueError("final walk replay mismatch")
            raw_shape, raw_terms = top.read_blob(raw_output)
            refined = basis.two_pass(raw_terms, raw_shape,
                                     final_walk["basis_mode"])
            if top.blob(raw_shape, refined) != final_path.read_bytes():
                raise ValueError("final basis replay mismatch")
        verify_descendants(final_shape, final_terms,
                           manifest["final_descendants"], directory)

        projection = manifest["projection_directed"]
        if (list(final_shape) != projection["parent_shape"] or
                len(final_terms) != projection["parent_rank"] or
                digest(final_path.read_bytes()) != projection["parent_sha256"]):
            raise ValueError("projection parent mismatch")
        projected_shape, projected_raw = top.project(
            final_shape, final_terms, projection["deleted_axis"],
            projection["deleted_coordinate"])
        width = max(projected_shape[0] * projected_shape[1],
                    projected_shape[1] * projected_shape[2],
                    projected_shape[0] * projected_shape[2])
        projected_terms, cleanup = top.compress_shared(projected_raw,
                                                        max_bits=width)
        if (len(projected_raw) != projection["raw_rank"] or
                len(cleanup) != projection["cleanup_steps"]):
            raise ValueError("projection cleanup mismatch")
        projected_path = verify(projected_shape, projected_terms,
                                projection["projected"], directory)

        first = projection["first_walk"]
        first_shape, first_terms, first_path = load_cert(first["retained"],
                                                         directory)
        if args.replay_walk:
            output = directory / "projection-walk.mfw"
            subprocess.run(
                [str(args.replay_walk), "x".join(map(str, projected_shape)),
                 str(projected_path), str(output), str(first["steps"]),
                 str(first["nonce"])], check=True, stdout=subprocess.PIPE,
                text=True)
            if output.read_bytes() != first_path.read_bytes():
                raise ValueError("projection walk replay mismatch")

        second_shape = tuple(projection["second_orientation"])
        second_terms = top.orient(first_shape, first_terms, second_shape)
        second_raw = top.blob(second_shape, second_terms)
        if digest(second_raw) != projection["second_input_sha256"]:
            raise ValueError("second walk input mismatch")
        second = projection["second_walk"]
        second_final_shape, second_final_terms, second_path = load_cert(
            second["retained"], directory)
        if args.replay_walk:
            source = directory / "second-input.mfw"
            source.write_bytes(second_raw)
            output = directory / "second-walk.mfw"
            subprocess.run(
                [str(args.replay_walk), "x".join(map(str, second_shape)),
                 str(source), str(output), str(second["steps"]),
                 str(second["nonce"])], check=True, stdout=subprocess.PIPE,
                text=True)
            raw_output = output.read_bytes()
            if digest(raw_output) != second["raw_sha256"]:
                raise ValueError("second walk replay mismatch")
            raw_shape, raw_terms = top.read_blob(raw_output)
            refined = basis.two_pass(raw_terms, raw_shape,
                                     second["basis_mode"])
            if top.blob(raw_shape, refined) != second_path.read_bytes():
                raise ValueError("second basis replay mismatch")
        if tuple(second_final_shape) != second_shape:
            raise ValueError("second walk final shape mismatch")

        descendants = {row["construction"]: row for row in
                       manifest["projected_descendants"]}
        left = top.orient(second_final_shape, second_final_terms, (8, 13, 15))
        strassen = HERE.parent / "lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"
        right = top.parse_terms(strassen.read_bytes(), 7)
        top.exact((2, 2, 2), right)
        product = top.kronecker((8, 13, 15), left, (2, 2, 2), right)
        verify((16, 26, 30), product, descendants["strassen-product"],
               directory)

        parent_terms = top.orient(final_shape, final_terms, (8, 13, 16))
        target = (8, 13, 31)
        combined = (blocks.block((8, 13, 15), left, target, (0, 0, 0)) +
                    blocks.block((8, 13, 16), parent_terms, target,
                                 (0, 0, 15)))
        cleaned, history = blocks.compress_shared(combined, max_bits=403)
        if history:
            raise ValueError("unexpected projected block cleanup")
        verify(target, cleaned, descendants["block-with-parent"], directory)

        nested = manifest["nested_projection_directed"]
        if (list(second_final_shape) != nested["parent_shape"] or
                len(second_final_terms) != nested["parent_rank"] or
                digest(second_path.read_bytes()) != nested["parent_sha256"]):
            raise ValueError("nested projection parent mismatch")
        nested_shape, nested_raw = top.project(
            second_final_shape, second_final_terms, nested["deleted_axis"],
            nested["deleted_coordinate"])
        width = max(nested_shape[0] * nested_shape[1],
                    nested_shape[1] * nested_shape[2],
                    nested_shape[0] * nested_shape[2])
        nested_terms, nested_cleanup = top.compress_shared(nested_raw,
                                                              max_bits=width)
        if (len(nested_raw) != nested["raw_rank"] or
                len(nested_cleanup) != nested["cleanup_steps"]):
            raise ValueError("nested projection cleanup mismatch")
        nested_path = verify(nested_shape, nested_terms, nested["projected"],
                             directory)
        nested_walk = nested["walk"]
        nested_final_shape, nested_final_terms, nested_final_path = load_cert(
            nested_walk["retained"], directory)
        if args.replay_walk:
            output = directory / "nested-walk.mfw"
            subprocess.run(
                [str(args.replay_walk), "x".join(map(str, nested_shape)),
                 str(nested_path), str(output), str(nested_walk["steps"]),
                 str(nested_walk["nonce"])], check=True,
                stdout=subprocess.PIPE, text=True)
            raw_output = output.read_bytes()
            if digest(raw_output) != nested_walk["raw_sha256"]:
                raise ValueError("nested walk replay mismatch")
            raw_shape, raw_terms = top.read_blob(raw_output)
            refined = basis.two_pass(raw_terms, raw_shape,
                                     nested_walk["basis_mode"])
            if top.blob(raw_shape, refined) != nested_final_path.read_bytes():
                raise ValueError("nested basis replay mismatch")
        if tuple(nested_final_shape) != tuple(nested_shape):
            raise ValueError("nested final shape mismatch")
        left = top.orient(nested_final_shape, nested_final_terms, (8, 12, 15))
        product = top.kronecker((8, 12, 15), left, (2, 2, 2), right)
        verify((16, 24, 30), product, manifest["nested_descendants"][0],
               directory)
    print("PASS top-two directed ranks 1040..1037 and projections 989, 899")


if __name__ == "__main__":
    main()
