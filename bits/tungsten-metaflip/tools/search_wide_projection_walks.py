#!/usr/bin/env python3
"""Bounded exact GF(2) projection/basis/walk search for multiword rectangles.

This cold campaign is separate from the live fleet. Public ranks schedule
walks only; independent full-tensor checks gate every retained result.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import screen_neutral_basis_children as neutral  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify_file(path):
    raw = path.read_bytes()
    shape, terms = top.read_blob(raw)
    top.exact(shape, terms)
    checked = json.loads(subprocess.check_output(
        ["ruby", str(HERE / "verify_tensor.rb"), "--shape",
         "x".join(map(str, shape)), str(path)], text=True))[0]
    if (not checked["exact"] or checked["rank"] != len(terms) or
            checked["sha256"] != digest(raw)):
        raise ValueError(f"independent tensor check failed: {path}")
    return shape, terms, digest(raw)


def proposals(shape, terms, public, per_shape=2):
    """Retain distinct full representations, including rank ties."""
    best = {}
    for mode in (None, *range(6, 18)):
        basis = terms if mode is None else two_pass(terms, shape, mode)
        top.exact(shape, basis)
        for axis, extent in enumerate(shape):
            if extent <= 1:
                continue
            for coordinate in range(extent):
                child_shape, projected = top.project(shape, basis, axis, coordinate)
                key = tuple(sorted(child_shape))
                if key not in public:
                    continue
                keep = [list(range(value)) for value in shape]
                keep[axis].pop(coordinate)
                if projected != neutral.project_grid(shape, basis, keep):
                    raise ValueError("independent projection mismatch")
                width = max(child_shape[0] * child_shape[1],
                            child_shape[1] * child_shape[2],
                            child_shape[0] * child_shape[2])
                result, _ = top.compress_shared(projected, max_bits=width)
                raw = top.blob(child_shape, result)
                row = dict(shape=child_shape, rank=len(result), mode=mode,
                           axis=axis, coordinate=coordinate, sha256=digest(raw),
                           public_rank=public[key], terms=result, raw=raw)
                bucket = best.setdefault(key, [])
                if row["sha256"] not in {old["sha256"] for old in bucket}:
                    bucket.append(row)
                    bucket.sort(key=lambda entry: (entry["rank"], entry["sha256"]))
                    del bucket[per_shape:]
    return sorted((row for bucket in best.values() for row in bucket),
                  key=lambda row: (row["rank"] - row["public_rank"],
                                   row["rank"], tuple(sorted(row["shape"])),
                                   row["sha256"]))


def select(rows, beam):
    """Give distinct shapes first access to the bounded walk budget."""
    selected = []
    shapes = set()
    for row in rows:
        key = tuple(sorted(row["shape"]))
        if key not in shapes:
            selected.append(row)
            shapes.add(key)
        if len(selected) == beam:
            return selected
    for row in rows:
        if row not in selected:
            selected.append(row)
        if len(selected) == beam:
            break
    return selected


def public_comparison(path):
    return top.comparison(json.loads(path.read_text()))


def summary(row):
    return {key: row[key] for key in (
        "shape", "rank", "mode", "axis", "coordinate", "sha256", "public_rank")}


def run(args):
    source_shape, source_terms, source_hash = verify_file(args.seed)
    public = public_comparison(args.digest)
    if args.list_only:
        choices = select(proposals(source_shape, source_terms, public), args.beam)
        for row in choices:
            top.exact(row["shape"], row["terms"])
        print(json.dumps({"seed": source_hash, "selected": [summary(row) for row in choices]},
                         indent=2))
        return

    args.output_dir.mkdir(parents=True, exist_ok=False)
    manifest = {"schema": 1, "field": "GF(2)", "record_claim": False,
                "status": "running", "source": str(args.seed),
                "source_sha256": source_hash, "steps_per_walk": args.steps,
                "beam_per_parent": args.beam, "max_depth": args.depth,
                "public_digest_sha256": digest(args.digest.read_bytes()),
                "rows": []}

    def save():
        target = args.output_dir / "manifest.json"
        temporary = args.output_dir / "manifest.json.tmp"
        temporary.write_text(json.dumps(manifest, indent=2) + "\n")
        temporary.replace(target)

    save()
    frontier = [(source_shape, source_terms, source_hash)]
    visited = {source_hash}
    walk_number = 0
    for level in range(args.depth):
        next_frontier = []
        for parent_shape, parent_terms, parent_hash in frontier:
            for row in select(proposals(parent_shape, parent_terms, public), args.beam):
                if row["sha256"] in visited:
                    continue
                visited.add(row["sha256"])
                top.exact(row["shape"], row["terms"])
                name = f"d{level}-w{walk_number}"
                seed_path = args.output_dir / f"{name}-seed.mfw"
                output_path = args.output_dir / f"{name}-result.mfw"
                seed_path.write_bytes(row["raw"])
                nonce = args.nonce_base + walk_number
                if nonce > 2147483647:
                    raise ValueError("walk nonce exceeds native range")
                subprocess.run(
                    [str(args.walker), "x".join(map(str, row["shape"])),
                     str(seed_path), str(output_path), str(args.steps), str(nonce)],
                    check=True, capture_output=True, text=True)
                result_shape, result_terms, result_hash = verify_file(output_path)
                if result_shape != row["shape"]:
                    raise ValueError("walker changed the tensor shape")
                admitted = dict(depth=level + 1, parent_sha256=parent_hash,
                                proposal=summary(row), nonce=nonce,
                                result_rank=len(result_terms), result_sha256=result_hash,
                                numerical_below_public=(len(result_terms) < row["public_rank"]),
                                seed_file=seed_path.name, result_file=output_path.name)
                manifest["rows"].append(admitted)
                save()
                print(json.dumps(admitted), flush=True)
                if result_hash not in visited:
                    visited.add(result_hash)
                    next_frontier.append((result_shape, result_terms, result_hash))
                walk_number += 1
        frontier = next_frontier
        if not frontier:
            break
    manifest["status"] = "complete"
    save()
    print(json.dumps({"status": "complete", "walks": walk_number,
                      "numerical_below_public": sum(
                          row["numerical_below_public"] for row in manifest["rows"])}),
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=Path, required=True)
    parser.add_argument("--digest", type=Path, required=True,
                        help="dated rank table for scheduling only")
    parser.add_argument("--walker", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--depth", type=int, default=1)
    parser.add_argument("--beam", type=int, default=2)
    parser.add_argument("--steps", type=int, default=100000000)
    parser.add_argument("--nonce-base", type=int, default=19071)
    parser.add_argument("--list-only", action="store_true")
    args = parser.parse_args()
    if args.depth < 1 or args.beam < 1 or not 1 <= args.steps <= 1000000000:
        parser.error("depth, beam, and steps must be positive and bounded")
    if not 1 <= args.nonce_base <= 2147483647:
        parser.error("nonce base outside native range")
    if not args.list_only and (args.walker is None or args.output_dir is None):
        parser.error("--walker and --output-dir are required for walks")
    run(args)


if __name__ == "__main__":
    main()
