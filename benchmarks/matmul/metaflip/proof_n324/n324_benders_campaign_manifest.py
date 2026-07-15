#!/usr/bin/env python3
"""Bind six independently audited n324 Benders archives into one manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


EXPECTED = {
    ((1, 2), 1),
    ((1, 2), 17),
    ((1, 4), 1),
    ((1, 4), 16),
    ((1, 8), 1),
    ((1, 8), 17),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("archives", nargs=6, type=Path)
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    orbit_audit = root / "n324_b_orbit_audit.py"
    audit_run = subprocess.run(
        ["python3", str(orbit_audit)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    entries = []
    cases = set()
    occurrence_hashes = set()
    total_models = 0
    total_cuts = 0
    for path in args.archives:
        data = json.loads(path.read_text())
        assert data["schema"] == "n324-gaussian-benders-archive-v1"
        assert data["claim_scope"].endswith("not an UNSAT proof")
        case = (tuple(data["missing_A"]), data["fixed_B"])
        assert case not in cases
        cases.add(case)
        assert data["checked_instance"] is not None
        checked_path = Path(data["checked_instance"]["path"])
        assert sha256(checked_path) == data["checked_instance"]["sha256"]
        assert all(value == "PASS" for value in data["audit"].values())
        assert sum(item["checked_cuts"] for item in data["iterations"]) == data["checked_cuts"]
        assert len(data["iterations"]) == data["checked_models"]
        occurrence_hashes.add(data["occurrence_table"]["sha256"])
        total_models += data["checked_models"]
        total_cuts += data["checked_cuts"]
        entries.append(
            {
                "missing_A": data["missing_A"],
                "fixed_B": data["fixed_B"],
                "archive": str(path.resolve()),
                "archive_sha256": sha256(path),
                "models": data["checked_models"],
                "cuts": data["checked_cuts"],
                "base_sha256": data["base"]["sha256"],
                "checked_instance_sha256": data["checked_instance"]["sha256"],
            }
        )
    assert cases == EXPECTED
    assert len(occurrence_hashes) == 1
    entries.sort(key=lambda entry: (entry["missing_A"], entry["fixed_B"]))

    campaign = {
        "schema": "n324-gaussian-benders-campaign-v1",
        "claim_scope": "all six cases covered, but no shard is proved UNSAT",
        "symmetry_cases": entries,
        "symmetry_case_count": 6,
        "audited_models": total_models,
        "audited_cuts": total_cuts,
        "occurrence_table_sha256": next(iter(occurrence_hashes)),
        "orbit_coverage_audit": {
            "script": str(orbit_audit),
            "script_sha256": sha256(orbit_audit),
            "output": audit_run.stdout.splitlines(),
            "status": "PASS",
        },
        "required_next_step": (
            "proof-producing UNSAT plus independent PB proof replay for every "
            "checked instance; SAT or time limit leaves the global bound open"
        ),
    }
    args.output.write_text(json.dumps(campaign, indent=2) + "\n")
    print(
        f"CAMPAIGN PASS cases=6 models={total_models} cuts={total_cuts} "
        f"manifest={args.output} sha256={sha256(args.output)}"
    )


if __name__ == "__main__":
    main()
