#!/usr/bin/env python3
"""Bounded exact projection/basis/walk/Strassen loop for GF(2) rectangles.

This is a cold campaign, not a live-fleet arm or a world-record oracle. Every
queued tensor is checked independently; price calculations never certify it.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_wide_rectangular_closure as old  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402
from search_wide_projection_walks import (  # noqa: E402
    proposals, select, shared_pair_counts, verify_file,
)
from verify_recursive_portfolio import catalog_minima, solver  # noqa: E402

STRASSEN = HERE.parent / "lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def initial_seeds(catalog):
    raw = catalog.read_bytes()
    baseline = json.loads(old.MANIFEST.read_text())
    if digest(raw) != baseline["catalog_sha256"]:
        raise ValueError("catalog revision differs from the pinned GF(2) portfolio")
    seeds = catalog_minima(json.loads(raw))
    for row in baseline["rows"]:
        key = tuple(row["shape"])
        seeds[key] = min(seeds.get(key, row["rank"]), row["rank"])
    for key, _, rank, _, _ in old.CANDIDATES:
        seeds[key] = min(seeds.get(key, rank), rank)
    return seeds


def basis_proposals(shape, terms, limit):
    result, seen = [], {digest(top.blob(shape, terms))}
    # Cover different axis orders before spending the beam on reverse-column
    # variants of the same order. On the r873 control this retains modes 6/12.
    for mode in (*range(6, 18, 2), *range(7, 18, 2)):
        basis = two_pass(terms, shape, mode)
        top.exact(shape, basis)
        raw = top.blob(shape, basis)
        key = digest(raw)
        if key not in seen:
            seen.add(key)
            result.append(dict(kind="basis", mode=mode, shape=list(shape),
                               rank=len(basis), raw=raw, sha256=key,
                               pair_counts=shared_pair_counts(basis)))
        if len(result) == limit:
            break
    return result


def run(args):
    if args.output_dir.exists():
        raise ValueError("output directory already exists")
    if not args.walker.is_file():
        raise ValueError("missing native walker")
    seeds = initial_seeds(args.catalog)
    right = top.parse_terms(STRASSEN.read_bytes(), 7)
    top.exact((2, 2, 2), right)
    args.output_dir.mkdir(parents=True)
    states_dir = args.output_dir / "states"
    states_dir.mkdir()
    manifest = dict(schema=1, field="GF(2)", record_claim=False,
                    status="running", source=str(args.seed),
                    catalog_sha256=digest(args.catalog.read_bytes()),
                    steps_per_walk=args.steps, rows=[])
    seen = set()

    def save():
        target = args.output_dir / "manifest.json"
        temporary = args.output_dir / "manifest.json.tmp"
        temporary.write_text(json.dumps(manifest, indent=2) + "\n")
        temporary.replace(target)

    def price():
        # The solver closes over its seed map; never mutate that map afterward.
        return solver(dict(seeds))

    def admit(raw, kind, parent=None, details=None):
        shape, terms = top.read_blob(raw)
        key = digest(top.blob(shape, sorted(terms)))
        if key in seen:
            return None
        top.exact(shape, terms)
        sha = digest(raw)
        path = states_dir / f"{sha}.mfw"
        path.write_bytes(raw)
        checked_shape, checked_terms, checked_sha = verify_file(path)
        if (checked_shape != shape or checked_terms != terms or checked_sha != sha):
            raise ValueError("independent admission mismatch")
        seen.add(key)
        canonical = tuple(sorted(shape))
        before = price()
        old_price = before(canonical)
        gains = []
        if len(terms) < old_price:
            seeds[canonical] = min(seeds.get(canonical, len(terms)), len(terms))
            after = price()
            gains = [dict(shape=s, before=before(s), after=after(s))
                     for s in itertools.combinations_with_replacement(range(2, 33), 3)
                     if after(s) < before(s)]
        row = dict(kind=kind, parent=parent, details=details or {},
                   shape=list(shape), rank=len(terms), sha256=sha,
                   path=str(path.relative_to(args.output_dir)),
                   old_price=old_price,
                   closure_improved=len(gains),
                   closure_saved=sum(g["before"] - g["after"] for g in gains))
        manifest["rows"].append(row)
        save()
        print(json.dumps(row), flush=True)
        return dict(shape=shape, terms=terms, raw=raw, sha256=sha,
                    price_improved=bool(gains))

    def compose(state):
        shape = state["shape"]
        target = tuple(2 * d for d in shape)
        rank = 7 * len(state["terms"])
        if (max(target) > 32 or rank > args.max_composed_rank or
                rank > price()(tuple(sorted(target)))):
            return None
        terms = top.kronecker(shape, state["terms"], (2, 2, 2), right)
        top.exact(target, terms)
        return admit(top.blob(target, terms), "strassen-product",
                     state["sha256"], dict(partner="2x2x2-r7"))

    save()
    source = admit(args.seed.read_bytes(), "source")
    if source is None:
        raise ValueError("duplicate source")
    frontier = [source]
    initial_product = compose(source)
    if (initial_product is not None and
            len(initial_product["terms"]) <= args.max_search_rank):
        frontier.append(initial_product)
    walks = 0
    for level in range(args.rounds):
        next_frontier, composed = [], []
        for state in frontier:
            if walks >= args.max_walks:
                break
            shape, terms = state["shape"], state["terms"]
            choices_prices = {}
            current_price = price()
            for axis, extent in enumerate(shape):
                if extent > 1:
                    child = list(shape)
                    child[axis] -= 1
                    key = tuple(sorted(child))
                    choices_prices[key] = current_price(key)
            rows = proposals(shape, terms, choices_prices)
            rows.sort(key=lambda r: (r["rank"] - current_price(tuple(sorted(r["shape"]))),
                                     r["rank"], r["sha256"]))
            choices = select(rows, args.projection_beam)
            choices.extend(basis_proposals(shape, terms, args.basis_beam))
            for choice in choices:
                if walks >= args.max_walks:
                    break
                seed = admit(choice["raw"], choice.get("kind", "projection-seed"),
                             state["sha256"], {k: choice[k] for k in
                             ("mode", "axis", "coordinate") if k in choice})
                if seed is None:
                    continue
                seed_product = compose(seed)
                if (seed_product is not None and
                        len(seed_product["terms"]) <= args.max_search_rank):
                    composed.append(seed_product)
                nonce = args.nonce_base + walks
                output = args.output_dir / f"walk-{walks}.mfw"
                subprocess.run([str(args.walker), "x".join(map(str, seed["shape"])),
                                str(states_dir / f'{seed["sha256"]}.mfw'),
                                str(output), str(args.steps), str(nonce)],
                               check=True, capture_output=True, text=True)
                walks += 1
                result = admit(output.read_bytes(), "walk", seed["sha256"],
                               dict(steps=args.steps, nonce=nonce))
                if result is not None:
                    next_frontier.append(result)
                    product = compose(result)
                    if (product is not None and
                            len(product["terms"]) <= args.max_search_rank):
                        composed.append(product)
        frontier = (next_frontier + composed)[:args.frontier_cap]
        if not frontier or walks >= args.max_walks:
            break
    manifest["status"] = "complete"
    manifest["walks"] = walks
    save()
    print(json.dumps(dict(status="complete", walks=walks,
                          exact_states=len(manifest["rows"]),
                          improved_states=sum(r["closure_improved"] > 0
                                              for r in manifest["rows"]))), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--walker", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--max-walks", type=int, default=6)
    parser.add_argument("--steps", type=int, default=100000000)
    parser.add_argument("--projection-beam", type=int, default=1)
    parser.add_argument("--basis-beam", type=int, default=2)
    parser.add_argument("--frontier-cap", type=int, default=4)
    parser.add_argument("--max-composed-rank", type=int, default=8000)
    parser.add_argument("--max-search-rank", type=int, default=3000,
                        help="queue composed tensors only up to this rank")
    parser.add_argument("--nonce-base", type=int, default=24001)
    args = parser.parse_args()
    if (not 1 <= args.rounds <= 20 or not 1 <= args.max_walks <= 10000 or
            not 1 <= args.steps <= 1000000000 or
            not 1 <= args.projection_beam <= 20 or
            not 1 <= args.basis_beam <= 12 or
            not 1 <= args.frontier_cap <= 100 or
            not 1 <= args.max_composed_rank <= 16384 or
            not 1 <= args.max_search_rank <= 16384 or
            not 1 <= args.nonce_base <= 2147483647 - args.max_walks):
        parser.error("invalid bounded search parameters")
    run(args)


if __name__ == "__main__":
    main()
