"""Build exact, diverse escape portfolios for metaflip searches.

The GPU relay's original portfolio consists solely of one generic factor split
per lane.  This tool builds a richer *rank-aware* bank from the exact identities
in :mod:`sym_escape`:

* ``split`` -- generic, symmetry-breaking or symmetry-neutral factor split;
* ``break`` -- a split targeted specifically at a fixed C3 cube;
* ``orbit-split`` and ``polarize`` -- C3-preserving identities; and
* normalized depth-two compositions of the above.

"Normalized" means that every intermediate identity is applied as a parity
toggle, zero factors are discarded, and complete resulting term sets are
canonicalized and deduplicated.  Thus commuting identities, collision-heavy
paths, and an identity followed by its inverse cannot occupy duplicate bank
slots under different labels.

The JSONL bank stores complete schemes because escape families have different
rank deltas.  It is intentionally independent of any particular CPU or Metal
walker's fixed-stride seed buffer.  ``materialize`` writes any slot as the bare
dump accepted by both FlipFleet's generated Tungsten walker and the GPU relay.

Examples:

  python3 escape_portfolio.py build seed.txt 5 bank.jsonl --count 48
  python3 escape_portfolio.py verify bank.jsonl
  python3 escape_portfolio.py materialize bank.jsonl 7 escaped.txt
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
import sys
from typing import Iterable, Optional, Sequence

from bench_decomp import verify as independent_verify
from sym_escape import (
    common_factors,
    density,
    fixed_terms,
    flip_pair_count,
    is_c3_closed,
    load_scheme,
    orbit_split_identity,
    parity_terms,
    polarization_identity,
    split_identity,
    toggle_identity,
    transpose,
)


Term = tuple[int, int, int]
SchemeKey = tuple[Term, ...]


# Keep both symmetry-preserving compositions and transitions from the quotient
# graph into the ordinary graph.  Generic split+split is the asymmetric control.
DEFAULT_RECIPES = (
    ("split",),
    ("break",),
    ("orbit-split",),
    ("polarize",),
    ("split", "split"),
    ("break", "split"),
    ("orbit-split", "orbit-split"),
    ("orbit-split", "polarize"),
    ("polarize", "orbit-split"),
    ("polarize", "polarize"),
    ("orbit-split", "break"),
    ("polarize", "break"),
)


@dataclass(frozen=True)
class EscapeMove:
    kind: str
    term: Term
    part: int
    axis: int | None = None

    def as_json(self) -> dict:
        return {
            "kind": self.kind,
            "term": list(self.term),
            "part": self.part,
            "axis": self.axis,
        }


@dataclass(frozen=True)
class PortfolioEntry:
    scheme: SchemeKey
    recipe: tuple[str, ...]
    moves: tuple[EscapeMove, ...]
    profile: dict
    # Optional in version-1 banks.  Older generated banks omit this field and
    # are still accepted; when they contain moves, verify_bank replays them.
    provenance: Optional[dict] = None


def canonical(scheme: Iterable[Term]) -> SchemeKey:
    return tuple(sorted(parity_terms(scheme)))


def scheme_digest(scheme: Iterable[Term]) -> str:
    payload = ";".join(f"{u},{v},{w}" for u, v, w in canonical(scheme))
    return hashlib.sha256(payload.encode("ascii")).hexdigest()


def validate_scheme_masks(scheme: Iterable[Term], n: int, label: str = "scheme") -> None:
    """Reject masks that an n-by-n tensor reconstruction would silently ignore."""
    if not isinstance(n, int) or n <= 0:
        raise ValueError("n must be positive")
    bound = 1 << (n * n)
    for index, term in enumerate(scheme):
        if not isinstance(term, (tuple, list)) or len(term) != 3:
            raise ValueError(f"{label} term {index} must contain three masks")
        for axis, mask in enumerate(term):
            if not isinstance(mask, int) or mask <= 0 or mask >= bound:
                raise ValueError(
                    f"{label} term {index} axis {axis} mask {mask!r} "
                    f"is outside [1,{bound})"
                )


def replay_moves(base: Iterable[Term], moves: Iterable[EscapeMove], n: int) -> SchemeKey:
    """Replay a deterministic escape path from its declared source scheme."""
    current = canonical(base)
    validate_scheme_masks(current, n, "provenance base")
    for index, move in enumerate(moves):
        validate_scheme_masks((move.term,), n, f"provenance move {index}")
        if not isinstance(move.part, int) or not 0 < move.part < 1 << (n * n):
            raise ValueError(f"provenance move {index} has an out-of-range part")
        current = canonical(apply_move(current, n, move))
        validate_scheme_masks(current, n, f"provenance move {index} result")
    return current


def _stable_order(items: Iterable, salt: str) -> list:
    """Deterministically shuffle without depending on Python's hash seed."""
    return sorted(
        items,
        key=lambda item: hashlib.blake2b(
            (salt + repr(item)).encode("utf-8"), digest_size=16
        ).digest(),
    )


def _limit(items: Iterable, count: int, salt: str) -> list:
    unique = list(dict.fromkeys(items))
    return _stable_order(unique, salt)[:count]


def enumerate_moves(
    scheme: Iterable[Term], n: int, kind: str, limit: int = 64, salt: str = ""
) -> list[EscapeMove]:
    """Enumerate a broad deterministic sample of eligible exact moves."""
    scheme = set(scheme)
    validate_scheme_masks(scheme, n)
    if kind not in ("split", "break", "orbit-split", "polarize"):
        raise ValueError(f"unknown escape kind: {kind}")
    if not scheme or limit <= 0:
        return []

    moves: list[EscapeMove] = []
    if kind == "split":
        # Draw from the live factor population on the selected stored axis.
        # W is already in its stored representation, exactly as split_identity
        # expects, so no common-space transpose is needed here.
        factors = tuple(sorted({t[axis] for t in scheme}) for axis in range(3))
        for term in sorted(scheme):
            for axis in range(3):
                for part in factors[axis]:
                    if part and part != term[axis]:
                        moves.append(EscapeMove(kind, term, part, axis))
    elif kind == "break":
        # Break only true fixed cubes.  Parts are sampled in the common C3
        # factor space, then transposed back for the stored W axis.
        parts = common_factors(scheme, n)
        for term in fixed_terms(scheme, n):
            for axis in range(3):
                old_common = transpose(term[axis], n) if axis == 2 else term[axis]
                for part_common in parts:
                    if part_common and part_common != old_common:
                        part = transpose(part_common, n) if axis == 2 else part_common
                        moves.append(EscapeMove(kind, term, part, axis))
    else:
        if not is_c3_closed(scheme, n):
            return []
        parts = common_factors(scheme, n)
        for term in fixed_terms(scheme, n):
            x = term[0]
            for part in parts:
                if part and part != x:
                    moves.append(EscapeMove(kind, term, part, None))
    return _limit(moves, limit, f"{n}:{kind}:{salt}")


def apply_move(scheme: Iterable[Term], n: int, move: EscapeMove) -> set[Term]:
    scheme = set(scheme)
    validate_scheme_masks(scheme, n)
    validate_scheme_masks((move.term,), n, "move")
    if not isinstance(move.part, int) or not 0 < move.part < 1 << (n * n):
        raise ValueError("move part is outside the n-by-n mask space")
    if move.kind in ("split", "break"):
        if move.axis not in (0, 1, 2):
            raise ValueError("split and break moves require an axis")
        identity = split_identity(move.term, move.axis, move.part)
    elif move.kind == "orbit-split":
        identity = orbit_split_identity(move.term[0], move.part, n)
    elif move.kind == "polarize":
        identity = polarization_identity(move.term[0], move.part, n)
    else:
        raise ValueError(f"unknown escape kind: {move.kind}")
    output = toggle_identity(scheme, identity)
    validate_scheme_masks(output, n, "move result")
    return output


def profile_scheme(scheme: Iterable[Term], base: Iterable[Term], n: int) -> dict:
    """Return the structural bank profile relative to ``base``."""
    current = set(scheme)
    base = set(base)
    validate_scheme_masks(current, n)
    validate_scheme_masks(base, n, "base")
    return {
        "rank": len(current),
        "density": density(current),
        "c3": is_c3_closed(current, n),
        "fixed": len(fixed_terms(current, n)),
        "flip_pairs": flip_pair_count(current),
        "distance": len(current ^ base),
    }


# Backward-compatible local name for early users of this standalone module.
_entry_profile = profile_scheme


def entries_from_schemes(
    base: Iterable[Term],
    schemes: Iterable[Iterable[Term]],
    n: int,
    recipe_label: str = "mined",
) -> list[PortfolioEntry]:
    """Make a verified bank from arbitrary exact candidate schemes.

    This is the integration point for identity miners and local-surgery tools:
    callers need not manufacture escape-specific ``EscapeMove`` provenance.
    The exact, canonical base is always slot zero; candidates are independently
    tensor-verified, parity-normalized, and deduplicated by complete term set.
    """
    if not recipe_label:
        raise ValueError("recipe_label must be nonempty")
    base_key = canonical(base)
    validate_scheme_masks(base_key, n, "base")
    if not independent_verify(base_key, n, n, n):
        raise ValueError("base scheme is not an exact matrix-multiplication tensor")
    entries = [
        PortfolioEntry(base_key, (), (), profile_scheme(base_key, base_key, n))
    ]
    seen = {base_key}
    for candidate in schemes:
        key = canonical(candidate)
        validate_scheme_masks(key, n, "candidate scheme")
        if key in seen:
            continue
        if not independent_verify(key, n, n, n):
            raise ValueError("candidate scheme is not an exact matrix-multiplication tensor")
        seen.add(key)
        entries.append(
            PortfolioEntry(
                key, (recipe_label,), (), profile_scheme(key, base_key, n)
            )
        )
    return entries


def _recipe_candidates(
    base: set[Term], n: int, recipe: tuple[str, ...], per_step: int
) -> list[tuple[SchemeKey, tuple[EscapeMove, ...]]]:
    states: list[tuple[set[Term], tuple[EscapeMove, ...]]] = [(set(base), ())]
    for depth, kind in enumerate(recipe):
        next_by_scheme: dict[SchemeKey, tuple[EscapeMove, ...]] = {}
        for state_index, (scheme, path) in enumerate(states):
            moves = enumerate_moves(
                scheme,
                n,
                kind,
                per_step,
                salt=f"{'/'.join(recipe)}:{depth}:{state_index}",
            )
            for move in moves:
                output = apply_move(scheme, n, move)
                key = canonical(output)
                # Complete-term-set normalization is the canonical authority.
                # Keep the first deterministic path only as human provenance.
                next_by_scheme.setdefault(key, path + (move,))
        states = [(set(key), path) for key, path in next_by_scheme.items()]
        if not states:
            break
    base_key = canonical(base)
    return [(canonical(s), path) for s, path in states if canonical(s) != base_key]


def _pick_novel(
    candidates: list[tuple[SchemeKey, tuple[EscapeMove, ...]]],
    selected: Sequence[PortfolioEntry],
    base: set[Term],
    n: int,
) -> tuple[SchemeKey, tuple[EscapeMove, ...]]:
    """Pick farthest from prior slots, then prefer connectivity and sparsity."""
    selected_sets = [set(entry.scheme) for entry in selected]

    def key(candidate):
        scheme, _ = candidate
        current = set(scheme)
        if selected_sets:
            novelty = min(len(current ^ other) for other in selected_sets)
        else:
            novelty = len(current ^ base)
        return (
            -novelty,
            len(current),
            -flip_pair_count(current),
            density(current),
            scheme_digest(current),
        )

    return min(candidates, key=key)


def build_portfolio(
    scheme: Iterable[Term],
    n: int,
    count: int = 48,
    per_step: int = 16,
    recipes: Sequence[tuple[str, ...]] = DEFAULT_RECIPES,
    include_base: bool = True,
) -> list[PortfolioEntry]:
    """Return a balanced, novelty-biased exact escape portfolio."""
    if n <= 0:
        raise ValueError("n must be positive")
    if count <= 0:
        raise ValueError("count must be positive")
    base = set(parity_terms(scheme))
    validate_scheme_masks(base, n, "base scheme")
    if not independent_verify(base, n, n, n):
        raise ValueError("base scheme is not an exact matrix-multiplication tensor")

    pools: dict[tuple[str, ...], list[tuple[SchemeKey, tuple[EscapeMove, ...]]]] = {}
    seen = {canonical(base)}
    for recipe in recipes:
        pool = []
        for key, path in _recipe_candidates(base, n, tuple(recipe), per_step):
            if key not in seen:
                pool.append((key, path))
        # Do not mark globally seen until selection: if two recipes collide, the
        # round-robin chooser gives the earlier documented recipe precedence.
        pools[tuple(recipe)] = pool

    selected: list[PortfolioEntry] = []
    if include_base:
        base_key = canonical(base)
        selected.append(PortfolioEntry(base_key, (), (), profile_scheme(base_key, base, n)))

    while len(selected) < count:
        progressed = False
        for recipe in recipes:
            recipe = tuple(recipe)
            pool = [(key, path) for key, path in pools[recipe] if key not in seen]
            pools[recipe] = pool
            if not pool:
                continue
            key, path = _pick_novel(pool, selected, base, n)
            pools[recipe] = [(k, p) for k, p in pool if k != key]
            seen.add(key)
            profile = profile_scheme(key, base, n)
            # This reconstruction is intentionally independent of the escape
            # algebra.  Never serialize an identity implementation mistake.
            if not independent_verify(key, n, n, n):
                raise AssertionError(f"escape recipe {recipe} changed the tensor")
            selected.append(PortfolioEntry(key, recipe, path, profile))
            progressed = True
            if len(selected) >= count:
                break
        if not progressed:
            break
    return selected


def _move_from_json(data: dict) -> EscapeMove:
    try:
        return EscapeMove(
            data["kind"], tuple(data["term"]), data["part"], data.get("axis")
        )
    except (KeyError, TypeError) as error:
        raise ValueError("malformed escape move provenance") from error


def _default_provenance(entry: PortfolioEntry, base: SchemeKey) -> dict:
    base_sha256 = scheme_digest(base)
    result_sha256 = scheme_digest(entry.scheme)
    kinds = tuple(move.kind for move in entry.moves)
    if not entry.recipe and not entry.moves and entry.scheme == base:
        return {
            "mode": "base",
            "replayable": True,
            "base_sha256": base_sha256,
            "result_sha256": result_sha256,
        }
    if entry.moves:
        if kinds != entry.recipe:
            raise ValueError("nonempty moves must exactly match the recipe")
        return {
            "mode": "moves",
            "replayable": True,
            "base_sha256": base_sha256,
            "result_sha256": result_sha256,
        }
    # Mined schemes and native-walker outputs are materialized and independently
    # exact, but an empty move list must never be presented as a replay recipe.
    return {
        "mode": "materialized",
        "replayable": False,
        "base_sha256": base_sha256,
        "result_sha256": result_sha256,
    }


def _verify_entry_provenance(
    entry: PortfolioEntry,
    base: SchemeKey,
    n: int,
    index: int,
    provenance: Optional[dict] = None,
) -> None:
    """Validate claimed replayability without rejecting legacy materialized rows."""
    provenance = entry.provenance if provenance is None else provenance
    if provenance is None:
        # Version-1 banks written before the provenance field are replayable
        # exactly when they actually carry moves.  Empty-move mined rows remain
        # valid materialized records under the independent tensor gate.
        if entry.moves:
            if entry.recipe and tuple(move.kind for move in entry.moves) != entry.recipe:
                raise ValueError(f"bank slot {index} recipe/move mismatch")
            if replay_moves(base, entry.moves, n) != entry.scheme:
                raise ValueError(f"bank slot {index} move provenance mismatch")
        elif index == 0 and entry.scheme != base:
            raise ValueError("bank base slot mismatch")
        return

    if not isinstance(provenance, dict):
        raise ValueError(f"bank slot {index} has malformed provenance")
    replayable = provenance.get("replayable")
    if not isinstance(replayable, bool):
        raise ValueError(f"bank slot {index} provenance must declare replayable")
    mode = provenance.get("mode")
    base_digest = scheme_digest(base)
    result_digest = scheme_digest(entry.scheme)
    if provenance.get("base_sha256") != base_digest:
        raise ValueError(f"bank slot {index} provenance base checksum mismatch")
    if provenance.get("result_sha256") != result_digest:
        raise ValueError(f"bank slot {index} provenance result checksum mismatch")

    if mode == "base":
        if not replayable or entry.moves or entry.scheme != base:
            raise ValueError(f"bank slot {index} has invalid base provenance")
        return
    if mode == "moves":
        if not replayable or not entry.moves:
            raise ValueError(f"bank slot {index} has invalid move provenance")
        if entry.recipe and tuple(move.kind for move in entry.moves) != entry.recipe:
            raise ValueError(f"bank slot {index} recipe/move mismatch")
        if replay_moves(base, entry.moves, n) != entry.scheme:
            raise ValueError(f"bank slot {index} move provenance mismatch")
        return
    if mode == "materialized":
        if replayable or entry.moves:
            raise ValueError(f"bank slot {index} materialized provenance is not replayable")
        return
    if mode != "staged" or replayable:
        raise ValueError(f"bank slot {index} has unsupported provenance mode {mode!r}")
    if entry.moves:
        raise ValueError(f"bank slot {index} staged provenance cannot claim global moves")

    stages = provenance.get("stages")
    if not isinstance(stages, list) or not stages:
        raise ValueError(f"bank slot {index} staged provenance has no stages")
    expected_input = base_digest
    for stage_index, stage in enumerate(stages):
        if not isinstance(stage, dict):
            raise ValueError(f"bank slot {index} provenance stage is malformed")
        if stage.get("input_sha256") != expected_input:
            raise ValueError(
                f"bank slot {index} provenance stage {stage_index} chain mismatch"
            )
        output_digest = stage.get("output_sha256")
        if not isinstance(output_digest, str):
            raise ValueError(
                f"bank slot {index} provenance stage {stage_index} has no output checksum"
            )
        stage_replayable = stage.get("replayable")
        if not isinstance(stage_replayable, bool):
            raise ValueError(
                f"bank slot {index} provenance stage {stage_index} must declare replayable"
            )
        if stage_replayable:
            if "move" not in stage or "input_terms" not in stage:
                raise ValueError(
                    f"bank slot {index} replayable stage {stage_index} lacks material"
                )
            stage_input = canonical(tuple(tuple(term) for term in stage["input_terms"]))
            validate_scheme_masks(stage_input, n, "provenance stage input")
            if scheme_digest(stage_input) != expected_input:
                raise ValueError(
                    f"bank slot {index} provenance stage {stage_index} input mismatch"
                )
            move = _move_from_json(stage["move"])
            if stage.get("kind") != move.kind:
                raise ValueError(
                    f"bank slot {index} provenance stage {stage_index} kind mismatch"
                )
            if scheme_digest(replay_moves(stage_input, (move,), n)) != output_digest:
                raise ValueError(
                    f"bank slot {index} provenance stage {stage_index} replay mismatch"
                )
        expected_input = output_digest
    if expected_input != result_digest:
        raise ValueError(f"bank slot {index} staged provenance result mismatch")


def write_bank(path: str, entries: Sequence[PortfolioEntry], n: int, source: str) -> None:
    if not entries:
        raise ValueError("cannot write an empty portfolio")
    base = canonical(entries[0].scheme)
    validate_scheme_masks(base, n, "bank base")
    header = {
        "format": "metaflip-escape-bank",
        "version": 1,
        "n": n,
        "count": len(entries),
        "source": source,
        "source_sha256": scheme_digest(base),
    }
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(json.dumps(header, sort_keys=True) + "\n")
        for index, entry in enumerate(entries):
            validate_scheme_masks(entry.scheme, n, f"bank slot {index}")
            provenance = (entry.provenance if entry.provenance is not None
                          else _default_provenance(entry, base))
            _verify_entry_provenance(entry, base, n, index, provenance)
            row = {
                "id": index,
                "recipe": list(entry.recipe),
                "moves": [move.as_json() for move in entry.moves],
                "profile": entry.profile,
                "provenance": provenance,
                "sha256": scheme_digest(entry.scheme),
                "terms": [list(term) for term in entry.scheme],
            }
            stream.write(json.dumps(row, separators=(",", ":"), sort_keys=True) + "\n")


def read_bank(path: str) -> tuple[dict, list[PortfolioEntry]]:
    with open(path, encoding="utf-8") as stream:
        rows = [json.loads(line) for line in stream if line.strip()]
    if not rows or rows[0].get("format") != "metaflip-escape-bank":
        raise ValueError("not a metaflip escape bank")
    header = rows[0]
    if header.get("version") != 1:
        raise ValueError(f"unsupported bank version: {header.get('version')}")
    n = header.get("n")
    if not isinstance(n, int) or n <= 0:
        raise ValueError("bank header has invalid n")
    entries = []
    for index, row in enumerate(rows[1:]):
        if row.get("id") != index:
            raise ValueError(f"bank slot id {row.get('id')} is not contiguous")
        moves = tuple(_move_from_json(move) for move in row.get("moves", ()))
        scheme = canonical(tuple(tuple(term) for term in row["terms"]))
        validate_scheme_masks(scheme, n, f"bank slot {index}")
        if scheme_digest(scheme) != row["sha256"]:
            raise ValueError(f"bank slot {row.get('id')} checksum mismatch")
        entries.append(PortfolioEntry(
            scheme, tuple(row.get("recipe", ())), moves, row["profile"],
            row.get("provenance"),
        ))
    if len(entries) != header.get("count"):
        raise ValueError("bank entry count does not match its header")
    if not entries:
        raise ValueError("bank contains no slots")
    if header.get("source_sha256") != scheme_digest(entries[0].scheme):
        raise ValueError("bank source checksum does not match slot zero")
    return header, entries


def verify_bank(path: str) -> list[dict]:
    header, entries = read_bank(path)
    n = int(header["n"])
    reports = []
    for index, entry in enumerate(entries):
        validate_scheme_masks(entry.scheme, n, f"bank slot {index}")
        exact = independent_verify(entry.scheme, n, n, n)
        actual = profile_scheme(entry.scheme, entries[0].scheme, n)
        if actual != entry.profile:
            raise ValueError(f"bank slot {index} profile mismatch")
        if not exact:
            raise ValueError(f"bank slot {index} is not tensor-exact")
        _verify_entry_provenance(entry, entries[0].scheme, n, index)
        reports.append({"id": index, "recipe": entry.recipe, **actual, "exact": exact})
    return reports


def emit_bare(scheme: Iterable[Term], path: str) -> None:
    terms = canonical(scheme)
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(f"{len(terms)}\n")
        for u, v, w in terms:
            stream.write(f"{u} {v} {w}\n")


def _summary(reports: Sequence[dict]) -> str:
    families: dict[str, int] = {}
    ranks: dict[int, int] = {}
    for report in reports:
        name = "+".join(report["recipe"]) or "base"
        families[name] = families.get(name, 0) + 1
        ranks[report["rank"]] = ranks.get(report["rank"], 0) + 1
    return "families=" + repr(families) + " ranks=" + repr(ranks)


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build", help="build and independently verify a mixed bank")
    build.add_argument("scheme")
    build.add_argument("n", type=int)
    build.add_argument("bank")
    build.add_argument("--count", type=int, default=48)
    build.add_argument("--per-step", type=int, default=16)
    verify = sub.add_parser("verify", help="tensor-verify every bank slot")
    verify.add_argument("bank")
    materialize = sub.add_parser("materialize", help="write one slot as a bare seed")
    materialize.add_argument("bank")
    materialize.add_argument("slot", type=int)
    materialize.add_argument("output")
    args = parser.parse_args(argv)

    if args.command == "build":
        base = load_scheme(args.scheme, args.n)
        entries = build_portfolio(base, args.n, args.count, args.per_step)
        write_bank(args.bank, entries, args.n, os.path.basename(args.scheme))
        reports = verify_bank(args.bank)
        print(f"wrote {args.bank}: {len(reports)} exact slots; {_summary(reports)}")
    elif args.command == "verify":
        reports = verify_bank(args.bank)
        print(f"verified {args.bank}: {len(reports)} exact slots; {_summary(reports)}")
    else:
        header, entries = read_bank(args.bank)
        if not 0 <= args.slot < len(entries):
            parser.error(f"slot must be in [0,{len(entries)})")
        emit_bare(entries[args.slot].scheme, args.output)
        report = entries[args.slot].profile
        print(
            f"wrote slot={args.slot} n={header['n']} recipe={entries[args.slot].recipe} "
            f"rank={report['rank']} density={report['density']} c3={report['c3']} "
            f"fixed={report['fixed']} to {args.output}"
        )


if __name__ == "__main__":
    main()
