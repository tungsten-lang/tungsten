#!/usr/bin/env python3
"""Bounded exact projection/basis/walk/Strassen loop for GF(2) rectangles.

This is a cold campaign, not a live-fleet arm or a world-record oracle. Every
queued tensor is checked independently; price calculations never certify it.
Current checked-in witnesses and pinned archived bounds price the frontier.
"""
import argparse
import base64
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
import sys

if not __debug__:
    raise RuntimeError("wide auto loop requires Python assertions for tensor checks")

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_wide_rectangular_closure as old  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402
from search_wide_projection_walks import (  # noqa: E402
    proposals, select, shared_pair_counts, verify_file,
)
from verify_recursive_portfolio import catalog_minima, solver  # noqa: E402
from wide_pair_composition import compose_pairs  # noqa: E402

STRASSEN = HERE.parent / "lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"
CERTIFICATES = HERE / "certificates"
ARCHIVED_PRICE_INDEX = CERTIFICATES / "archived-exact-prices.json"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_seed(path):
    raw = path.read_bytes()
    if path.name.endswith(".mfw.gz.b64"):
        raw = gzip.decompress(base64.b64decode(raw.replace(b"\n", b""), validate=True))
    return raw


def external_minima(catalog):
    """Comparison bounds only; never use cross-field ranks as GF(2) witnesses."""
    bounds = {}
    for scheme in json.loads(catalog.read_bytes()).get("schemes", []):
        shape = tuple(sorted(scheme.get("format", [])))
        rank = scheme.get("external_best_rank")
        source = scheme.get("external_best_source")
        if (len(shape) != 3 or min(shape) < 2 or max(shape) > 32 or
                not isinstance(rank, int) or rank < 1 or
                not isinstance(source, str) or not source):
            continue
        candidate = (rank, source)
        if shape not in bounds or candidate < bounds[shape]:
            bounds[shape] = candidate
    return bounds


def archived_price_minima(path=ARCHIVED_PRICE_INDEX):
    """Load audited rank-only prices; tensor admission still needs full checks."""
    index = json.loads(path.read_text())
    if (index.get("schema") != 1 or index.get("field") != "GF(2)" or
            index.get("record_claim") is not False):
        raise ValueError("invalid archived price index")
    prices = {}
    for row in index["bounds"]:
        shape = tuple(row["shape"])
        if (len(shape) != 3 or tuple(sorted(shape)) != shape or
                tuple(sorted(row["witness_shape"])) != shape or
                min(shape) < 2 or max(shape) > 32 or row["rank"] < 1 or
                row["source"] not in index["sources"] or
                len(row["sha256"]) != 64 or
                row["member"].startswith("/") or ".." in Path(row["member"]).parts or
                shape in prices):
            raise ValueError("invalid archived price row")
        prices[shape] = row["rank"]
    return prices


def certificate_minima(seeds, root=CERTIFICATES):
    """Price from checked-in tensor witnesses, never from a claimed rank alone."""
    prices = dict(seeds)
    baseline = solver(dict(prices))
    files = sorted((*root.rglob("*.mfw"), *root.rglob("*.mfw.gz.b64")))
    for path in files:
        raw = read_seed(path)
        shape, terms = top.read_blob(raw)
        key = tuple(sorted(shape))
        if len(terms) >= min(prices.get(key, len(terms) + 1), baseline(key)):
            continue
        top.exact(shape, terms)
        prices[key] = min(prices.get(key, len(terms)), len(terms))
    return prices


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
    for key, rank in top.initial_seeds().items():
        seeds[key] = min(seeds.get(key, rank), rank)
    for key, rank in archived_price_minima().items():
        seeds[key] = min(seeds.get(key, rank), rank)
    return certificate_minima(seeds)


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


def round_walk_limit(walks, max_walks, level, rounds):
    remaining = max_walks - walks
    remaining_rounds = rounds - level
    return walks + (remaining if remaining_rounds == 1 else
                    max(1, remaining // remaining_rounds))


def ordered_choices(projected, basis, price):
    # Prefer two distinct improving child shapes to a weaker parent-basis tie.
    # Otherwise keep both arms in the first two slots: an earlier two-walk
    # round spent both walks on basis variants and missed projection entirely.
    def gap(row):
        return row["rank"] - price(tuple(sorted(row["shape"])))

    if (len(projected) >= 2 and
            tuple(sorted(projected[0]["shape"])) !=
            tuple(sorted(projected[1]["shape"])) and
            gap(projected[0]) < 0 and gap(projected[1]) < 0 and
            (not basis or gap(projected[1]) < gap(basis[0]))):
        return projected[:2] + basis + projected[2:]
    if projected and basis and gap(basis[0]) < gap(projected[0]):
        return basis[:1] + projected[:1] + basis[1:] + projected[1:]
    return projected[:1] + basis[:2] + projected[1:] + basis[2:]


def composed_direct_choice(state):
    """Walk a newly composed parent once before its projection neighborhoods."""
    if state["kind"] not in ("strassen-product", "shared-pair-product"):
        return None
    return dict(kind="composed-direct", shape=state["shape"],
                rank=len(state["terms"]), raw=state["raw"],
                sha256=state["sha256"])


def projection_admission_kind(rank, round_price, live_price):
    """Keep new gains and tied representations, not superseded projections."""
    if rank >= round_price or rank > live_price:
        return None
    return "projection-improvement" if rank < live_price else "projection-tie"


def frontier_priority(state, current_price):
    return (len(state["terms"]) - current_price(tuple(sorted(state["shape"]))),
            len(state["terms"]), state["sha256"])


def select_frontier(walked, composed, cap, current_price):
    """Keep one composed continuation when the bounded beam has room for both."""
    priority = lambda state: frontier_priority(state, current_price)
    ordered_composed = sorted({s["sha256"]: s for s in composed}.values(),
                              key=priority)
    composed_ids = {s["sha256"] for s in ordered_composed}
    walked = list({s["sha256"]: s for s in walked
                   if s["sha256"] not in composed_ids}.values())
    if cap == 1 or not ordered_composed:
        return sorted([*walked, *composed], key=priority)[:cap]
    retained = ordered_composed[:1]
    retained.extend(sorted([*walked, *ordered_composed[1:]],
                           key=priority)[:cap - 1])
    return retained


def run(args):
    if args.output_dir.exists():
        raise ValueError("output directory already exists")
    if not args.walker.is_file():
        raise ValueError("missing native walker")
    source_raw = read_seed(args.seed)
    source_shape, source_terms = top.read_blob(source_raw)
    top.exact(source_shape, source_terms)
    seeds = initial_seeds(args.catalog)
    external = external_minima(args.catalog)
    right = top.parse_terms(STRASSEN.read_bytes(), 7)
    top.exact((2, 2, 2), right)
    args.output_dir.mkdir(parents=True)
    states_dir = args.output_dir / "states"
    states_dir.mkdir()
    manifest = dict(schema=1, field="GF(2)", record_claim=False,
                    status="running", source=str(args.seed),
                    catalog_sha256=digest(args.catalog.read_bytes()),
                    archived_price_index_sha256=digest(ARCHIVED_PRICE_INDEX.read_bytes()),
                    steps_per_walk=args.steps, rows=[])
    seen = set()
    states_by_sha = {}

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
        comparison = external.get(canonical)
        row["external_best_rank"] = comparison[0] if comparison else None
        row["external_best_source"] = comparison[1] if comparison else None
        row["external_gap"] = len(terms) - comparison[0] if comparison else None
        manifest["rows"].append(row)
        save()
        print(json.dumps(row), flush=True)
        state = dict(kind=kind, shape=shape, terms=terms, raw=raw, sha256=sha,
                     price_improved=bool(gains))
        states_by_sha[sha] = state
        return state

    def compose(state):
        shape = state["shape"]
        outputs = []
        target = tuple(2 * d for d in shape)
        rank = 7 * len(state["terms"])
        current_price = price()
        if (max(target) <= 32 and rank <= args.max_composed_rank and
                rank <= current_price(tuple(sorted(target)))):
            terms = top.kronecker(shape, state["terms"], (2, 2, 2), right)
            top.exact(target, terms)
            result = admit(top.blob(target, terms), "strassen-product",
                           state["sha256"], dict(partner="2x2x2-r7"))
            if result is not None:
                outputs.append(result)
        for axis, pairs in enumerate(shared_pair_counts(state["terms"])):
            if not pairs:
                continue
            scale = tuple(1 if i == (2, 0, 1)[axis] else 3 for i in range(3))
            target = tuple(d * k for d, k in zip(shape, scale))
            predicted = 9 * len(state["terms"]) - 3 * pairs
            if max(target) > 32 or predicted > args.max_composed_rank:
                continue
            built = compose_pairs(shape, state["terms"], axis,
                                  max_rank=args.max_composed_rank)
            if built is None:
                continue
            target, terms, actual_pairs, raw_rank = built
            if actual_pairs != pairs or raw_rank != predicted:
                raise ValueError("pair composition prediction mismatch")
            width = max(target[0] * target[1], target[1] * target[2],
                        target[0] * target[2])
            terms, _ = top.compress_shared(terms, max_bits=width)
            top.exact(target, terms)
            if len(terms) > current_price(tuple(sorted(target))):
                continue
            result = admit(top.blob(target, terms), "shared-pair-product",
                           state["sha256"], dict(axis=axis, pairs=pairs,
                                                 leaf="2x3x3-r15",
                                                 raw_rank=raw_rank))
            if result is not None:
                outputs.append(result)
        return outputs

    save()
    source = admit(source_raw, "source")
    if source is None:
        raise ValueError("duplicate source")
    frontier = [source]
    frontier.extend(product for product in compose(source)
                    if len(product["terms"]) <= args.max_search_rank)
    walks = 0
    direct_walked = set()
    for level in range(args.rounds):
        # Reserve walk slots for descendants. Without this, a wide first
        # frontier consumes max_walks and --rounds never feeds anything back.
        level_limit = round_walk_limit(walks, args.max_walks, level, args.rounds)
        next_frontier = []
        composed = [state for state in frontier if state["kind"] in
                    ("strassen-product", "shared-pair-product")]
        current_price = price()
        frontier.sort(key=lambda state: (
            0 if (level == 0 and state["kind"] == "source") or
            (level > 0 and state["kind"] in
             ("strassen-product", "shared-pair-product")) else 1,
            frontier_priority(state, current_price)))
        prepared = []
        direct_reserved = False
        for state in frontier:
            shape, terms = state["shape"], state["terms"]
            choices_prices = {}
            for axis, extent in enumerate(shape):
                if extent > 1:
                    child = list(shape)
                    child[axis] -= 1
                    key = tuple(sorted(child))
                    choices_prices[key] = current_price(key)
            rows = proposals(shape, terms, choices_prices)
            rows.sort(key=lambda r: (r["rank"] - current_price(tuple(sorted(r["shape"]))),
                                     r["rank"], r["sha256"]))
            # Exact projections do not need a walk slot to enter the archive.
            # Use the round-start price so tied representations from the same
            # improved shape remain available as different neighborhoods.
            for row in rows:
                canonical = tuple(sorted(row["shape"]))
                kind = projection_admission_kind(row["rank"],
                                                 current_price(canonical),
                                                 price()(canonical))
                if kind is None:
                    continue
                child = admit(row["raw"], kind,
                              state["sha256"], {k: row[k] for k in
                              ("mode", "axis", "coordinate")})
                if child is not None:
                    next_frontier.append(child)
                    composed.extend(product for product in compose(child)
                                    if len(product["terms"]) <= args.max_search_rank)
            projected = select(rows, args.projection_beam)
            basis = basis_proposals(shape, terms, args.basis_beam)
            choices = ordered_choices(projected, basis, current_price)
            # A direct walk helped several exact block-composition parents,
            # whereas matched direct walks on projection-rich source tensors
            # tied. Reserve at most one composed parent per round so it cannot
            # consume the whole beam or displace the source's first choice.
            if not direct_reserved and state["sha256"] not in direct_walked:
                direct = composed_direct_choice(state)
                if direct is not None:
                    choices.insert(0, direct)
                    direct_reserved = True
            prepared.append((state, choices))
        # Round-robin the frontier; otherwise the first descendant can use
        # every reserved walk while equally promising siblings are ignored.
        for turn in range(max((len(choices) for _, choices in prepared), default=0)):
            for state, choices in prepared:
                if walks >= level_limit:
                    break
                if turn >= len(choices):
                    continue
                choice = choices[turn]
                seed = admit(choice["raw"], choice.get("kind", "projection-seed"),
                             state["sha256"], {k: choice[k] for k in
                             ("mode", "axis", "coordinate") if k in choice})
                if seed is None:
                    seed = states_by_sha.get(choice["sha256"])
                if seed is None:
                    continue
                if choice.get("kind") == "composed-direct":
                    direct_walked.add(seed["sha256"])
                composed.extend(product for product in compose(seed)
                                if len(product["terms"]) <= args.max_search_rank)
                nonce = args.nonce_base + walks
                output = args.output_dir / f"walk-{walks}.mfw"
                subprocess.run([str(args.walker), "x".join(map(str, seed["shape"])),
                                str(states_dir / f'{seed["sha256"]}.mfw'),
                                str(output), str(args.steps), str(nonce)],
                               check=True, capture_output=True, text=True)
                walks += 1
                result = admit(output.read_bytes(), "walk", seed["sha256"],
                               dict(steps=args.steps, nonce=nonce))
                # A walk may return its exact seed. The basis variant is
                # still a distinct neighborhood worth feeding to the next
                # round, rather than silently collapsing the feedback loop.
                next_frontier.append(result if result is not None else seed)
                if result is not None:
                    composed.extend(product for product in compose(result)
                                    if len(product["terms"]) <= args.max_search_rank)
            if walks >= level_limit:
                break
        frontier = select_frontier(next_frontier, composed,
                                   args.frontier_cap, price())
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
