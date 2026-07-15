#!/usr/bin/env python3
"""Generate an exhaustive fixed-term campaign for GF(2) ``<a,2,c>`` rank.

The five adjacent-factor normal forms cover every nonzero term.  Within each
normal form, ``inner2_stabilizer_orbits`` covers every nonzero third factor.
Consequently UNSAT for every formula in a complete manifest proves that no
decomposition with at most ``terms`` terms exists.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from inner2_direct_rank_opb import build as build_opb
from inner2_direct_rank_xnf import build as build_xnf
from inner2_stabilizer_orbits import CASES, enumerate_orbits, orbit_digest


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(
    output_dir: Path,
    a: int,
    c: int,
    terms: int,
    formula_format: str,
    selected_cases: set[str],
    orbit_index: int | None,
    enumerate_only: bool,
    quotient_rank: bool,
    lex_terms: bool = False,
    nonzero_c: bool = False,
    minimal_terms: bool = False,
    rref: bool = True,
    known_lower_bound: int | None = None,
    dual_inner2_quotient: bool = False,
    span_dependency_weight: int = 0,
) -> dict[str, object]:
    if lex_terms and formula_format != "xnf":
        raise ValueError("--lex-terms is implemented only for XNF campaigns")
    if (nonzero_c or minimal_terms) and known_lower_bound != terms:
        raise ValueError(
            "exact/minimal-term guards require --known-lower-bound equal to --terms"
        )
    if dual_inner2_quotient and (formula_format != "xnf" or c != 2):
        raise ValueError("--dual-inner2-quotient requires XNF with --c 2")
    quotient_rank = quotient_rank or formula_format == "opb"
    output_dir.mkdir(parents=True, exist_ok=True)
    width = (a * c + 3) // 4
    entries: list[dict[str, object]] = []
    coverage: list[dict[str, object]] = []

    for name, a_rank, b_rank, pairing in CASES:
        if name not in selected_cases:
            continue
        orbits = enumerate_orbits(a, c, a_rank, b_rank, pairing)
        coverage.append(
            {
                "case": name,
                "a_rank": a_rank,
                "b_rank": b_rank,
                "pairing": pairing if pairing is not None else "na",
                "orbit_count": len(orbits),
                "covered_nonzero_c": sum(orbit.size for orbit in orbits),
                "orbit_digest": orbit_digest(orbits),
            }
        )
        chosen = enumerate(orbits)
        if orbit_index is not None:
            assert 0 <= orbit_index < len(orbits), (name, orbit_index, len(orbits))
            chosen = ((orbit_index, orbits[orbit_index]),)
        for index, orbit in chosen:
            suffix = "xnf" if formula_format == "xnf" else "opb"
            filename = (
                f"n{a}2{c}_r{terms}_{name}_o{index:03d}_"
                f"c{orbit.representative:0{width}x}.{suffix}"
            )
            path = output_dir / filename
            item: dict[str, object] = {
                "case": name,
                "a_rank": a_rank,
                "b_rank": b_rank,
                "pairing": pairing if pairing is not None else "na",
                "orbit_index": index,
                "fixed_c": orbit.representative,
                "fixed_c_hex": f"{orbit.representative:0{width}x}",
                "orbit_size": orbit.size,
                "formula": filename,
            }
            if not enumerate_only:
                if formula_format == "xnf":
                    stats = build_xnf(
                        path,
                        a,
                        c,
                        terms,
                        a_rank,
                        b_rank,
                        pairing,
                        orbit.representative,
                        quotient_rank,
                        rref,
                        lex_terms,
                        nonzero_c,
                        minimal_terms,
                        dual_inner2_quotient,
                        span_dependency_weight,
                    )
                else:
                    stats = build_opb(
                        path,
                        a,
                        c,
                        terms,
                        a_rank,
                        b_rank,
                        pairing,
                        True,
                        True,
                        orbit.representative,
                    )
                item["formula_sha256"] = sha256(path)
                item["formula_bytes"] = path.stat().st_size
                item["variables"] = stats["variables"]
                item["constraints"] = stats["constraints"]
                if formula_format == "xnf":
                    item["clauses"] = stats["clauses"]
                    item["xors"] = stats["xors"]
            entries.append(item)

    all_names = {case[0] for case in CASES}
    complete = selected_cases == all_names and orbit_index is None
    manifest: dict[str, object] = {
        "schema": "inner2-direct-rank-campaign-v1",
        "field": "GF(2)",
        "tensor": f"<{a},2,{c}>",
        "a": a,
        "c": c,
        "terms": terms,
        "claimed_lower_bound_if_all_unsat": terms + 1,
        "formula_format": formula_format,
        "quotient_rank": quotient_rank,
        "lex_terms": lex_terms,
        "nonzero_c": nonzero_c,
        "minimal_terms": minimal_terms,
        "rref": rref,
        "dual_inner2_quotient": dual_inner2_quotient,
        "prerequisite_checked_lower_bound": known_lower_bound,
        "enumerate_only": enumerate_only,
        "coverage_complete": complete,
        "coverage": coverage,
        "formula_count": len(entries),
        "covered_fixed_c_values": sum(int(item["orbit_size"]) for item in entries),
        "expected_fixed_c_values_per_coarse_case": (1 << (a * c)) - 1,
        "formulas": entries,
    }
    if span_dependency_weight:
        manifest["span_dependency_weight"] = span_dependency_weight
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(
        json.dumps(
            {
                "manifest": str(manifest_path),
                "manifest_sha256": sha256(manifest_path),
                "coverage_complete": complete,
                "formula_count": len(entries),
                "enumerate_only": enumerate_only,
            },
            sort_keys=True,
        )
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--a", type=int, required=True)
    parser.add_argument("--c", type=int, required=True)
    parser.add_argument("--terms", type=int, required=True)
    parser.add_argument("--format", choices=("xnf", "opb"), default="xnf")
    parser.add_argument("--case", action="append", choices=tuple(case[0] for case in CASES))
    parser.add_argument("--orbit-index", type=int)
    parser.add_argument("--enumerate-only", action="store_true")
    parser.add_argument("--without-quotient-rank", action="store_true")
    parser.add_argument("--lex-terms", action="store_true")
    parser.add_argument("--no-rref", action="store_true")
    parser.add_argument(
        "--nonzero-c",
        action="store_true",
        help="exact-rank mode; requires an independently checked rank >= terms",
    )
    parser.add_argument(
        "--minimal-terms",
        action="store_true",
        help="minimum exact-rank mode; implies --nonzero-c",
    )
    parser.add_argument("--known-lower-bound", type=int)
    parser.add_argument(
        "--dual-inner2-quotient",
        action="store_true",
        help="also constrain the cyclic B*C inner-2 quotient; requires --c 2",
    )
    parser.add_argument(
        "--span-dependency-weight",
        type=int,
        default=0,
        help="exclude low-weight row dependencies in all three factor spans",
    )
    args = parser.parse_args()
    generate(
        args.output_dir,
        args.a,
        args.c,
        args.terms,
        args.format,
        set(args.case) if args.case else {case[0] for case in CASES},
        args.orbit_index,
        args.enumerate_only,
        not args.without_quotient_rank,
        args.lex_terms,
        args.nonzero_c,
        args.minimal_terms,
        not args.no_rref,
        args.known_lower_bound,
        args.dual_inner2_quotient,
        args.span_dependency_weight,
    )


if __name__ == "__main__":
    main()
