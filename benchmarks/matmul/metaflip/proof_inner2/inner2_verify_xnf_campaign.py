#!/usr/bin/env python3
"""Check coverage, hashes, and CakeML XLRUP proofs for an inner-2 campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

from inner2_stabilizer_orbits import CASES, enumerate_orbits, orbit_digest


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_coverage(data: dict[str, object]) -> list[dict[str, object]]:
    assert data["schema"] == "inner2-direct-rank-campaign-v1"
    assert data["field"] == "GF(2)"
    assert data["formula_format"] == "xnf"
    assert data["coverage_complete"] is True
    assert data["enumerate_only"] is False
    a, c = int(data["a"]), int(data["c"])
    if data.get("dual_inner2_quotient"):
        assert c == 2
    formulas = data["formulas"]
    assert isinstance(formulas, list)
    by_case: dict[str, list[dict[str, object]]] = {}
    for raw in formulas:
        assert isinstance(raw, dict)
        item = raw
        name = str(item["case"])
        by_case.setdefault(name, []).append(item)
    expected_names = {case[0] for case in CASES}
    assert set(by_case) == expected_names

    coverage = data["coverage"]
    assert isinstance(coverage, list)
    coverage_by_case = {str(item["case"]): item for item in coverage}
    assert set(coverage_by_case) == expected_names
    expected_total = (1 << (a * c)) - 1

    for name, a_rank, b_rank, pairing in CASES:
        orbits = enumerate_orbits(a, c, a_rank, b_rank, pairing)
        summary = coverage_by_case[name]
        assert int(summary["orbit_count"]) == len(orbits)
        assert int(summary["covered_nonzero_c"]) == expected_total
        assert summary["orbit_digest"] == orbit_digest(orbits)
        actual = sorted(by_case[name], key=lambda item: int(item["orbit_index"]))
        assert len(actual) == len(orbits)
        for index, (item, orbit) in enumerate(zip(actual, orbits)):
            assert int(item["a_rank"]) == a_rank
            assert int(item["b_rank"]) == b_rank
            shown_pairing = item["pairing"]
            assert shown_pairing == (pairing if pairing is not None else "na")
            assert int(item["orbit_index"]) == index
            assert int(item["fixed_c"]) == orbit.representative
            assert int(item["orbit_size"]) == orbit.size
    assert int(data["formula_count"]) == len(formulas)
    assert int(data["covered_fixed_c_values"]) == len(CASES) * expected_total
    guarded = bool(data.get("nonzero_c")) or bool(data.get("minimal_terms"))
    if guarded:
        assert int(data["prerequisite_checked_lower_bound"]) == int(data["terms"])
    return formulas


def verify_checked_prerequisite(
    data: dict[str, object], artifact_dir: Path,
) -> dict[str, object] | None:
    """Hash-audit the theorem needed by minimum-rank-only guards.

    A nonzero ``C_t`` and pair-distinctness are valid for a hypothetical
    decomposition with exactly ``terms`` summands, but not for a padded
    decomposition with fewer summands.  A complete UNSAT proof may therefore
    use those guards only when rank >= terms has already been checked.
    """
    guarded = bool(data.get("nonzero_c")) or bool(data.get("minimal_terms"))
    if not guarded:
        return None
    terms = int(data["terms"])
    if int(data["prerequisite_checked_lower_bound"]) != terms:
        raise ValueError("minimum-rank guards lack a matching checked lower bound")

    # Blaser's general matrix-multiplication bound for dimensions
    # <a,2,c> is
    #
    #   2a + ac + 2c - a - 2 - c + 1 = ac + a + c - 1.
    #
    # Unlike a computed certificate this prerequisite needs no external
    # artifact: the dimensions and arithmetic are part of the hash-pinned
    # campaign manifest.  In particular it certifies rank >= 19 for
    # <6,2,2>, allowing an exact-rank-19 nonzero-C campaign for <2,2,6>.
    a, c = int(data["a"]), int(data["c"])
    analytic_lower_bound = a * c + a + c - 1
    if analytic_lower_bound >= terms:
        return {
            "kind": "analytic-blaser",
            "campaign_tensor": data["tensor"],
            "dimensions": [a, 2, c],
            "formula": "ab+ac+bc-a-b-c+1",
            "verified_lower_bound_encoded": analytic_lower_bound,
            "required_lower_bound": terms,
        }

    key = (int(data["a"]), int(data["c"]), terms)
    if key != (5, 2, 17):
        raise ValueError(
            "no pinned checked-prerequisite audit is registered for "
            f"{data['tensor']} at rank {terms}"
        )

    # <5,2,2> is a cyclic factor permutation of <2,2,5>; tensor rank is
    # invariant under that permutation.  The audit pins both certificate
    # hashes and checks the encoded root lower bound before any guarded shard
    # is accepted.
    from n225_verify_wang import EXPECTED_ROOT_BOUND, audit_artifacts

    audit, _certificate, _archive = audit_artifacts(artifact_dir)
    assert int(audit["verified_lower_bound_encoded"]) == terms
    assert EXPECTED_ROOT_BOUND == terms
    return {
        **audit,
        "campaign_tensor": data["tensor"],
        "equivalence": "cyclic factor permutation <5,2,2> ~ <2,2,5>",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("proof_dir", type=Path)
    parser.add_argument("--checker", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=float)
    args = parser.parse_args()

    data = json.loads(args.manifest.read_text())
    formulas = verify_coverage(data)
    prerequisite = verify_checked_prerequisite(data, Path(__file__).resolve().parent)
    formula_dir = args.manifest.parent
    checked = []
    names: set[str] = set()
    for item in formulas:
        name = str(item["formula"])
        assert name not in names
        names.add(name)
        formula = formula_dir / name
        proof = args.proof_dir / (Path(name).stem + ".xlrup")
        assert formula.is_file(), formula
        assert proof.is_file(), proof
        assert sha256(formula) == item["formula_sha256"]
        assert formula.stat().st_size == int(item["formula_bytes"])
        result = subprocess.run(
            [str(args.checker), str(formula), str(proof)],
            capture_output=True,
            text=True,
            timeout=args.timeout,
        )
        transcript = result.stdout + result.stderr
        assert result.returncode == 0, (name, result.returncode, transcript[-2000:])
        assert transcript.splitlines().count("s VERIFIED UNSAT") == 1, (
            name,
            transcript[-2000:],
        )
        assert not re.search(r"warning|error|fail", transcript, re.IGNORECASE), (
            name,
            transcript[-2000:],
        )
        checked.append(
            {
                "formula": name,
                "formula_sha256": sha256(formula),
                "xlrup": proof.name,
                "xlrup_sha256": sha256(proof),
                "xlrup_bytes": proof.stat().st_size,
            }
        )
        print(f"VERIFIED {name}")

    result_manifest = {
        "schema": "inner2-direct-rank-checked-proofs-v1",
        "input_manifest": str(args.manifest.resolve()),
        "input_manifest_sha256": sha256(args.manifest),
        "checker": str(args.checker.resolve()),
        "checker_sha256": sha256(args.checker),
        "proof_count": len(checked),
        "claimed_lower_bound": data["claimed_lower_bound_if_all_unsat"],
        "checked_prerequisite": prerequisite,
        "proofs": checked,
    }
    if args.output is not None:
        args.output.write_text(json.dumps(result_manifest, indent=2) + "\n")
        print(f"manifest={args.output} sha256={sha256(args.output)}")
    print(
        f"VERIFIED COMPLETE tensor={data['tensor']} rank<={data['terms']} "
        f"proofs={len(checked)}"
    )


if __name__ == "__main__":
    main()
