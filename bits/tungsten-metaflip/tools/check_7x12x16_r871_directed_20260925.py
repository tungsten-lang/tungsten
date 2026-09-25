#!/usr/bin/env python3
"""Replay three exact GF(2) 7x12x16/r871 descendants and their closure."""
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
CERT = HERE / "certificates/7x12x16-r871-directed-20260925"
sys.path.insert(0, str(HERE))
import check_7x12x16_directed_20260925 as parent_check  # noqa: E402
import check_wide_rectangular_closure as old  # noqa: E402
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


def closure(catalog, manifest, parent_manifest):
    raw = catalog.read_bytes()
    target = manifest["closure"]
    if digest(raw) != target["catalog_sha256"]:
        raise ValueError("catalog revision mismatch")
    spec = importlib.util.spec_from_file_location(
        "metaflip_recursive_portfolio_r871",
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
    prior = dict(seeds)
    prior[(7, 13, 16)] = 962
    parent_key = tuple(sorted(parent_manifest["walks"][-1]["result"]["shape"]))
    prior[parent_key] = parent_manifest["walks"][-1]["result"]["rank"]
    parent = portfolio.solver(prior)
    updated = dict(prior)
    key = tuple(sorted(manifest["walks"][0]["result"]["shape"]))
    updated[key] = target["retained_rank"]
    after = portfolio.solver(updated)
    gains = [{"shape": shape, "before": before(shape), "after": after(shape)}
             for shape in itertools.combinations_with_replacement(range(2, 33), 3)
             if after(shape) < before(shape)]
    extra = [row for row in gains if
             after(tuple(row["shape"])) < parent(tuple(row["shape"]))]
    if (before(key) != target["baseline_rank"] or
            parent(key) != target["parent_rank"] or
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
            manifest["record_claim"] is not False or len(manifest["walks"]) != 3 or
            manifest["parent_certificate"] != "../7x12x16-directed-20260925/manifest.json"):
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
    with tempfile.TemporaryDirectory(prefix="metaflip-7x12x16-r871-") as tmp:
        directory = Path(tmp)
        shape, terms, _ = parent_check.load(parent_row, directory)
        results = []
        for index, walk in enumerate(manifest["walks"]):
            basis = two_pass(terms, shape, walk["basis_mode"])
            seed = top.blob(shape, basis)
            if (len(basis) != walk["seed_rank"] or
                    digest(seed) != walk["seed_sha256"]):
                raise ValueError("basis seed mismatch")
            top.exact(shape, basis)
            child_shape, child_terms, expected = load(walk["result"], directory)
            if child_shape != shape:
                raise ValueError("walk changed tensor shape")
            if args.replay_walk:
                seed_path = directory / f"seed-{index}.mfw"
                output_path = directory / f"walk-{index}.mfw"
                seed_path.write_bytes(seed)
                subprocess.run([str(args.replay_walk), "x".join(map(str, shape)),
                                str(seed_path), str(output_path), str(walk["steps"]),
                                str(walk["nonce"])],
                               check=True, capture_output=True, text=True)
                if output_path.read_bytes() != expected:
                    raise ValueError("native walk replay mismatch")
            results.append(dict(mode=walk["basis_mode"], rank=len(child_terms),
                                sha256=digest(expected)))
        gains = closure(args.catalog, manifest, parent_manifest) if args.catalog else None
        print(json.dumps({"field": "GF(2)", "record_claim": False,
                          "shape": list(shape), "rank": results[0]["rank"],
                          "results": results,
                          "walks_replayed": bool(args.replay_walk),
                          "closure_gains": gains}, indent=2))


if __name__ == "__main__":
    main()
