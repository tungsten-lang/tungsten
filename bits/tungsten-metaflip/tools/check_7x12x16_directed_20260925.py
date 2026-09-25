#!/usr/bin/env python3
"""Replay the exact GF(2) 7x12x16/r872 projection and directed walks."""
import argparse
import base64
import gzip
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CERT = HERE / "certificates/7x12x16-directed-20260925"
sys.path.insert(0, str(HERE))
import check_7x13x16_directed_20260924 as parent_check  # noqa: E402
import check_wide_rectangular_closure as old  # noqa: E402
import screen_neutral_basis_children as neutral  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def load(row, directory):
    encoded = (CERT / row["file"]).read_bytes().replace(b"\n", b"")
    raw = gzip.decompress(base64.b64decode(encoded, validate=True))
    shape, terms = top.read_blob(raw)
    density = sum(factor.bit_count() for term in terms for factor in term)
    if (list(shape) != row["shape"] or len(terms) != row["rank"] or
            density != row["density"] or digest(raw) != row["sha256"]):
        raise ValueError("certificate metadata mismatch")
    top.exact(shape, terms)
    path = directory / row["file"].removesuffix(".gz.b64")
    path.write_bytes(raw)
    checked = json.loads(subprocess.check_output(
        ["ruby", str(HERE / "verify_tensor.rb"), "--shape",
         "x".join(map(str, shape)), str(path)], text=True))[0]
    if (not checked["exact"] or checked["rank"] != row["rank"] or
            checked["density"] != density or checked["sha256"] != digest(raw)):
        raise ValueError("independent tensor check failed")
    return shape, terms, raw


def replay(binary, directory, label, shape, seed, walk, expected):
    seed_path = directory / f"{label}-seed.mfw"
    result_path = directory / f"{label}-result.mfw"
    seed_path.write_bytes(seed)
    subprocess.run([str(binary), "x".join(map(str, shape)), str(seed_path),
                    str(result_path), str(walk["steps"]), str(walk["nonce"])],
                   check=True, capture_output=True, text=True)
    if result_path.read_bytes() != expected:
        raise ValueError(f"{label} native walk replay mismatch")


def closure(catalog, manifest, parent_manifest):
    raw = catalog.read_bytes()
    target = manifest["closure"]
    if digest(raw) != target["catalog_sha256"]:
        raise ValueError("catalog revision mismatch")
    spec = importlib.util.spec_from_file_location(
        "metaflip_recursive_portfolio_r872",
        ROOT / "benchmarks/matmul/metaflip/verify_recursive_portfolio.py")
    portfolio = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = portfolio
    spec.loader.exec_module(portfolio)
    baseline = json.loads(old.MANIFEST.read_text())
    if baseline["catalog_sha256"] != target["catalog_sha256"]:
        raise ValueError("portfolio baseline catalog mismatch")
    seeds = portfolio.catalog_minima(json.loads(raw))
    for row in baseline["rows"]:
        key = tuple(row["shape"])
        seeds[key] = min(seeds.get(key, row["rank"]), row["rank"])
    for key, _, rank, _, _ in old.CANDIDATES:
        seeds[key] = min(seeds.get(key, rank), rank)
    before = portfolio.solver(dict(seeds))
    parent_seeds = dict(seeds)
    parent_key = tuple(sorted(parent_manifest["walks"][-1]["result"]["shape"]))
    parent_seeds[parent_key] = min(parent_seeds.get(parent_key, 962), 962)
    parent = portfolio.solver(parent_seeds)
    updated = dict(parent_seeds)
    key = tuple(sorted(manifest["walks"][-1]["result"]["shape"]))
    updated[key] = min(updated.get(key, target["retained_rank"]),
                       target["retained_rank"])
    after = portfolio.solver(updated)
    shapes = itertools.combinations_with_replacement(range(2, 33), 3)
    gains = [{"shape": shape, "before": before(shape), "after": after(shape)}
             for shape in shapes if after(shape) < before(shape)]
    extra = [row for row in gains if after(tuple(row["shape"])) <
             parent(tuple(row["shape"]))]
    if (before(key) != target["baseline_rank"] or
            after(key) != target["retained_rank"] or
            len(gains) != target["improved_shapes"] or
            sum(row["before"] - row["after"] for row in gains) !=
            target["saved_rank_units"] or
            len(extra) != target["incremental_shapes"] or
            sum(parent(tuple(row["shape"])) - row["after"] for row in extra) !=
            target["incremental_saved_rank_units"]):
        raise ValueError("finite closure impact mismatch")
    return gains


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay-walk", type=Path,
                        help="compiled tools/wide_rect_walk.w binary")
    parser.add_argument("--catalog", type=Path,
                        help="catalog.json with the pinned SHA-256 revision")
    args = parser.parse_args()
    manifest = json.loads((CERT / "manifest.json").read_text())
    if (manifest["schema"] != 1 or manifest["field"] != "GF(2)" or
            manifest["record_claim"] is not False or len(manifest["walks"]) != 2 or
            manifest["parent_certificate"] != "../7x13x16-directed-20260924/manifest.json"):
        raise ValueError("unexpected certificate manifest")
    parent_manifest = json.loads((CERT / manifest["parent_certificate"]).read_text())
    parent_row = parent_manifest["walks"][-1]["result"]
    if parent_row["sha256"] != manifest["parent_sha256"]:
        raise ValueError("parent digest mismatch")
    parent_cmd = [sys.executable, str(parent_check.__file__)]
    if args.replay_walk:
        parent_cmd.extend(("--replay-walk", str(args.replay_walk)))
    if args.catalog:
        parent_cmd.extend(("--catalog", str(args.catalog)))
    subprocess.run(parent_cmd, check=True, capture_output=True, text=True)
    with tempfile.TemporaryDirectory(prefix="metaflip-7x12x16-") as tmp:
        directory = Path(tmp)
        shape, terms, _ = parent_check.load(parent_row, directory)
        projection = manifest["projection"]
        basis = two_pass(terms, shape, projection["basis_mode"])
        top.exact(shape, basis)
        child_shape, raw_projected = top.project(
            shape, basis, projection["axis"], projection["coordinate"])
        keep = [list(range(extent)) for extent in shape]
        keep[projection["axis"]].pop(projection["coordinate"])
        if raw_projected != neutral.project_grid(shape, basis, keep):
            raise ValueError("independent projection mismatch")
        width = max(child_shape[0] * child_shape[1],
                    child_shape[1] * child_shape[2],
                    child_shape[0] * child_shape[2])
        seed_terms, _ = top.compress_shared(raw_projected, max_bits=width)
        seed = top.blob(child_shape, seed_terms)
        if (list(child_shape) != projection["shape"] or
                len(seed_terms) != projection["rank"] or
                digest(seed) != projection["sha256"]):
            raise ValueError("walk-one seed mismatch")
        top.exact(child_shape, seed_terms)
        first = manifest["walks"][0]
        shape, terms, first_result = load(first["result"], directory)
        if args.replay_walk:
            replay(args.replay_walk, directory, "first", child_shape, seed,
                   first, first_result)
        second = manifest["walks"][1]
        basis = two_pass(terms, shape, second["basis_mode"])
        basis_raw = top.blob(shape, basis)
        if (len(basis) != second["seed_rank"] or
                digest(basis_raw) != second["seed_sha256"]):
            raise ValueError("walk-two seed mismatch")
        top.exact(shape, basis)
        last_shape, last_terms, last_result = load(second["result"], directory)
        if args.replay_walk:
            replay(args.replay_walk, directory, "second", shape, basis_raw,
                   second, last_result)
        gains = closure(args.catalog, manifest, parent_manifest) if args.catalog else None
        print(json.dumps({"field": "GF(2)", "record_claim": False,
                          "shape": list(last_shape), "rank": len(last_terms),
                          "sha256": digest(last_result),
                          "walks_replayed": bool(args.replay_walk),
                          "closure_gains": gains}, indent=2))


if __name__ == "__main__":
    main()
