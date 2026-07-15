#!/usr/bin/env python3
"""Rebuild, replay, and manifest the six n324 quotient-rank proofs."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
CASES = (
    ("m12b1", (1, 2), 1, "natural"),
    ("m12b17", (1, 2), 17, "natural"),
    ("m14b1", (1, 4), 1, "natural"),
    ("m14b16", (1, 4), 16, "natural"),
    ("m18b1", (1, 8), 1, "canonical-first"),
    ("m18b17", (1, 8), 17, "canonical-first"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str]) -> str:
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("occurrence_table", type=Path)
    parser.add_argument("artifact_dir", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--solver", type=Path, required=True)
    parser.add_argument("--veripb", type=Path, required=True)
    parser.add_argument("--skip-rebuild", action="store_true")
    args = parser.parse_args()

    assert sha256(args.occurrence_table) == (
        "751c521c24e9f5e87085f4ed3e781edba71ae0c66a97cdbd0088a2e2d3b7f1f8"
    )
    assert args.solver.is_file() and args.veripb.is_file()

    orbit_output = run([sys.executable, str(ROOT / "n324_b_orbit_audit.py")])
    assert orbit_output.count("coverage=45 disjoint=PASS") == 3
    planted_output = run([
        sys.executable,
        str(ROOT / "n324_quotient_encoding_audit.py"),
        "--solver", str(args.solver),
    ])
    assert "QUOTIENT_ENCODING_AUDIT PASS cases=18" in planted_output

    records = []
    with tempfile.TemporaryDirectory(prefix="n324-qrank-rebuild-") as temporary:
        temporary = Path(temporary)
        for name, missing, fixed_b, order in CASES:
            formula = args.artifact_dir / f"{name}.opb"
            proof = args.artifact_dir / f"{name}.pbp"
            assert formula.is_file() and proof.is_file()
            with proof.open() as source:
                assert source.readline() == "pseudo-Boolean proof version 2.0\n"
                conclusions = 0
                for line in source:
                    lowered = line.lower()
                    assert not line.startswith("del id ")
                    assert not line.startswith("a ")
                    assert "assume" not in lowered and "assumption" not in lowered
                    conclusions += line.startswith("conclusion UNSAT")
                assert conclusions == 1

            if not args.skip_rebuild:
                base = temporary / f"{name}_base.opb"
                rebuilt = temporary / f"{name}.opb"
                run([
                    sys.executable,
                    str(ROOT / "n324_rankone_b_assignment_opb.py"),
                    str(args.occurrence_table), str(base),
                    "--missing", str(missing[0]), str(missing[1]),
                    "--fixed-b", str(fixed_b),
                ])
                run([
                    sys.executable,
                    str(ROOT / "n324_quotient_rank_opb.py"),
                    str(base), str(rebuilt),
                    "--missing", str(missing[0]), str(missing[1]),
                    "--term-order", order,
                ])
                assert sha256(rebuilt) == sha256(formula), name

            verification = run([
                str(args.veripb), "--force-checked-deletion", "--opb",
                str(formula), str(proof),
            ])
            assert verification.count("s VERIFIED UNSATISFIABLE") == 1
            lowered_verification = verification.lower()
            for diagnostic in (
                "warning", "error", "failure", "unjustified", "assumption",
            ):
                assert diagnostic not in lowered_verification, (name, diagnostic)
            header = formula.open().readline().rstrip()
            assert "#variable= 7529" in header
            assert "#constraint= 86487" in header
            records.append({
                "name": name,
                "missing_A": list(missing),
                "fixed_B": fixed_b,
                "term_order": order,
                "formula": formula.name,
                "formula_bytes": formula.stat().st_size,
                "formula_sha256": sha256(formula),
                "proof": proof.name,
                "proof_bytes": proof.stat().st_size,
                "proof_sha256": sha256(proof),
                "veripb": "VERIFIED UNSATISFIABLE; no warning or error",
            })
            print(
                f"{name} REBUILD={'SKIP' if args.skip_rebuild else 'PASS'} "
                f"VERIPB=PASS proof_bytes={proof.stat().st_size}"
            )

    manifest = {
        "schema": "n324-quotient-rank-proof-manifest-v1",
        "claim": (
            "The six rank-one-A/rank-one-B rank-19 residual shards are UNSAT; "
            "combined with the separately checked mode lemmas and symmetry "
            "cover, GF(2) rank(<3,2,4>) is 20."
        ),
        "occurrence_table_sha256": sha256(args.occurrence_table),
        "solver": {
            "path_name": args.solver.name,
            "sha256": sha256(args.solver),
            "expected": "RoundingSat 2 commit d4edbf7",
        },
        "veripb": {
            "path_name": args.veripb.name,
            "sha256": sha256(args.veripb),
            "version_output": run([str(args.veripb), "--version"]).strip(),
        },
        "audits": {
            "fixed_B_orbit_cover": "PASS: 3 missing-A cases, 2 B orbits each",
            "planted_rank_encoding": "PASS: ranks 0..7 SAT, rank 8 UNSAT, two orders",
            "proof_deletions": "all unchecked deletion commands removed",
            "veripb_checked_deletion_mode": "PASS without warnings",
        },
        "cases": records,
        "source_sha256": {
            path.name: sha256(path)
            for path in (
                ROOT / "n324_common.py",
                ROOT / "n324_rankone_b_assignment_opb.py",
                ROOT / "n324_quotient_rank.py",
                ROOT / "n324_quotient_rank_opb.py",
                ROOT / "n324_quotient_encoding_audit.py",
                ROOT / "n324_verify_quotient_proofs.py",
                ROOT / "n324_b_orbit_audit.py",
            )
        },
    }
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        f"QUOTIENT_PROOF_CAMPAIGN PASS cases={len(records)} "
        f"manifest_sha256={sha256(args.manifest)}"
    )


if __name__ == "__main__":
    main()
