#!/usr/bin/env python3
"""Run a hash-gated inner-2 XNF campaign serially and resumably.

This driver never turns a solver's UNSAT line into a theorem.  UNSAT attempts
remain explicitly unchecked until FRAT-XOR elaboration and CakeML replay via
``inner2_verify_xnf_campaign.py``.  SAT models, on the other hand, are decoded
and reconstructed immediately by the independent direct-rank auditor.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shlex
import subprocess
import time
from pathlib import Path

from inner2_direct_rank_audit import audit
from inner2_verify_xnf_campaign import verify_checked_prerequisite, verify_coverage


SCHEMA = "inner2-xnf-resume-v1"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def last_integer(transcript: str, label: str) -> int:
    matches = re.findall(
        rf"(?m)^c {re.escape(label)}\s+:\s+"
        r"([0-9]+(?:\.[0-9]+)?)([KMGT]?)\b",
        transcript,
    )
    if not matches:
        return 0
    value, suffix = matches[-1]
    scale = {"": 1, "K": 1_000, "M": 1_000_000, "G": 1_000_000_000,
             "T": 1_000_000_000_000}[suffix]
    return int(float(value) * scale)


def last_float(transcript: str, label: str) -> float:
    matches = re.findall(
        rf"(?m)^c {re.escape(label)}\s+:\s+([0-9]+(?:\.[0-9]+)?)",
        transcript,
    )
    return float(matches[-1]) if matches else 0.0


def solver_status(transcript: str) -> str:
    matches = re.findall(r"(?m)^s (SATISFIABLE|UNSATISFIABLE|INDETERMINATE)$", transcript)
    return matches[-1] if matches else "MISSING"


def load_state(path: Path, manifest: Path, manifest_hash: str) -> dict[str, object]:
    if not path.exists():
        return {
            "schema": SCHEMA,
            "manifest": str(manifest.resolve()),
            "manifest_sha256": manifest_hash,
            "attempts": {},
        }
    state = json.loads(path.read_text())
    if state.get("schema") != SCHEMA:
        raise ValueError(f"wrong state schema in {path}")
    if state.get("manifest_sha256") != manifest_hash:
        raise ValueError("resume state belongs to a different formula manifest")
    if not isinstance(state.get("attempts"), dict):
        raise ValueError("malformed attempts map")
    return state


def summarize(state: dict[str, object], formula_count: int) -> dict[str, object]:
    attempts = state["attempts"]
    assert isinstance(attempts, dict)
    latest = [rows[-1] for rows in attempts.values() if rows]
    counts: dict[str, int] = {}
    for row in latest:
        status = str(row["status"])
        counts[status] = counts.get(status, 0) + 1
    return {
        "formula_count": formula_count,
        "attempted_formulas": len(latest),
        "attempt_count": sum(len(rows) for rows in attempts.values()),
        "latest_status_counts": counts,
        "formal_lower_bound_ready": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--solver", default="cryptominisat5")
    parser.add_argument("--seconds", type=float, default=60.0)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--only", help="regular expression matched against formula names")
    parser.add_argument(
        "--priority", choices=("least-cpu", "smallest-orbit", "manifest"),
        default="least-cpu",
    )
    parser.add_argument(
        "--cms-arg", action="append", default=[],
        help="extra CryptoMiniSat argument; repeat and use --cms-arg=--flag=value",
    )
    parser.add_argument("--proof", action="store_true", help="retain FRAT-XOR output")
    parser.add_argument(
        "--retry-terminal", action="store_true",
        help="rerun formulas already SAT-audited or carrying an unchecked proof",
    )
    parser.add_argument(
        "--continue-after-sat", action="store_true",
        help="do not stop the campaign after an independently audited SAT model",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be positive")

    manifest = args.manifest.resolve()
    data = json.loads(manifest.read_text())
    formulas = verify_coverage(data)
    prerequisite = verify_checked_prerequisite(data, Path(__file__).resolve().parent)
    manifest_hash = sha256(manifest)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "logs").mkdir(exist_ok=True)
    if args.proof:
        (output / "frat").mkdir(exist_ok=True)
    state_path = output / "campaign_status.json"
    state = load_state(state_path, manifest, manifest_hash)
    state["checked_prerequisite"] = prerequisite
    attempts = state["attempts"]
    assert isinstance(attempts, dict)

    selected = []
    pattern = re.compile(args.only) if args.only else None
    for position, raw in enumerate(formulas):
        item = dict(raw)
        item["manifest_position"] = position
        name = str(item["formula"])
        if pattern is not None and pattern.search(name) is None:
            continue
        prior = attempts.get(name, [])
        latest = str(prior[-1]["status"]) if prior else ""
        terminal = latest in ("SAT_MODEL_VERIFIED", "UNSAT_PROOF_UNCHECKED")
        # A solver-only UNSAT should be rerun when proof logging is requested,
        # but repeated non-proof runs add no information.
        terminal = terminal or (latest == "UNSAT_UNCHECKED" and not args.proof)
        if not terminal or args.retry_terminal:
            selected.append(item)

    def consumed(item: dict[str, object]) -> float:
        rows = attempts.get(str(item["formula"]), [])
        return sum(float(row.get("cpu_seconds", 0.0)) for row in rows)

    if args.priority == "least-cpu":
        selected.sort(
            key=lambda item: (
                consumed(item), int(item["orbit_size"]), str(item["formula"])
            )
        )
    elif args.priority == "smallest-orbit":
        selected.sort(key=lambda item: (int(item["orbit_size"]), str(item["formula"])))
    else:
        selected.sort(key=lambda item: int(item["manifest_position"]))
    if args.limit is not None:
        selected = selected[: args.limit]

    formula_dir = manifest.parent
    for item in selected:
        name = str(item["formula"])
        formula = formula_dir / name
        if not formula.is_file():
            raise FileNotFoundError(formula)
        if formula.stat().st_size != int(item["formula_bytes"]):
            raise ValueError(f"formula size mismatch: {name}")
        formula_hash = sha256(formula)
        if formula_hash != item["formula_sha256"]:
            raise ValueError(f"formula hash mismatch: {name}")

        prior = attempts.setdefault(name, [])
        assert isinstance(prior, list)
        attempt_index = len(prior)
        seed = args.seed + attempt_index
        stem = Path(name).stem
        log = output / "logs" / f"{stem}.a{attempt_index:03d}.seed{seed}.log"
        proof = output / "frat" / f"{stem}.a{attempt_index:03d}.frat"
        command = [
            args.solver,
            "--verb", "1",
            "--threads", "1",
            "--maxtime", str(args.seconds),
            "--random", str(seed),
            *args.cms_arg,
            str(formula),
        ]
        if args.proof:
            command.append(str(proof))
        if args.dry_run:
            print(shlex.join(command))
            continue

        started = time.monotonic()
        completed = subprocess.run(command, capture_output=True, text=True)
        wall = time.monotonic() - started
        transcript = completed.stdout + completed.stderr
        log.write_text(transcript)
        raw_status = solver_status(transcript)
        status = raw_status
        model_audit: dict[str, object] | None = None
        error: str | None = None
        if raw_status == "SATISFIABLE":
            try:
                model_audit = audit(log, int(data["a"]), int(data["c"]), int(data["terms"]))
                assert model_audit["fixed_a_rank"] == int(item["a_rank"])
                assert model_audit["fixed_b_rank"] == int(item["b_rank"])
                assert model_audit["fixed_pairing"] == item["pairing"]
                if data.get("nonzero_c") or data.get("minimal_terms"):
                    assert model_audit["used_terms"] == int(data["terms"])
                status = "SAT_MODEL_VERIFIED"
            except Exception as exception:  # preserve the rejected transcript
                status = "SAT_MODEL_REJECTED"
                error = repr(exception)
        elif raw_status == "UNSATISFIABLE":
            status = "UNSAT_PROOF_UNCHECKED" if args.proof else "UNSAT_UNCHECKED"
        elif raw_status != "INDETERMINATE":
            status = "SOLVER_ERROR"
            error = f"missing solver status, return code {completed.returncode}"

        row: dict[str, object] = {
            "attempt": attempt_index,
            "seed": seed,
            "seconds_limit": args.seconds,
            "command": command,
            "returncode": completed.returncode,
            "status": status,
            "wall_seconds": round(wall, 6),
            "cpu_seconds": last_float(transcript, "all-threads sum CPU time"),
            "conflicts": last_integer(transcript, "conflicts"),
            "decisions": last_integer(transcript, "decisions"),
            "propagations": last_integer(transcript, "propagations"),
            "formula_sha256": formula_hash,
            "log": str(log),
        }
        if args.proof and proof.exists():
            row.update(
                {
                    "frat": str(proof),
                    "frat_bytes": proof.stat().st_size,
                    "frat_sha256": sha256(proof),
                }
            )
        if model_audit is not None:
            row["model_audit"] = model_audit
        if error is not None:
            row["error"] = error
        prior.append(row)
        state["summary"] = summarize(state, len(formulas))
        atomic_json(state_path, state)
        print(
            f"{status:22s} cpu={row['cpu_seconds']:7.2f} "
            f"conflicts={row['conflicts']:9d} {name}",
            flush=True,
        )
        if status == "SAT_MODEL_VERIFIED" and not args.continue_after_sat:
            break

    if args.dry_run:
        return
    state["summary"] = summarize(state, len(formulas))
    atomic_json(state_path, state)
    print(json.dumps(state["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
