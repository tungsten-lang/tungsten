#!/usr/bin/env python3
"""Iterate necessary-B solve, exact Gaussian rejection, and checked PB cuts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str], output: Path | None = None) -> tuple[str, int, float]:
    started = time.perf_counter()
    if output is None:
        completed = subprocess.run(
            command,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        print(completed.stdout, end="")
        return completed.stdout, completed.returncode, time.perf_counter() - started
    with output.open("w") as sink:
        completed = subprocess.run(
            command,
            check=False,
            text=True,
            stdout=sink,
            stderr=subprocess.STDOUT,
        )
    # RoundingSat may use a nonzero result code for a time limit; the status
    # line, not the process code, is the loop's semantic result.
    return output.read_text(), completed.returncode, time.perf_counter() - started


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("occurrence_table", type=Path)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--fixed-b", type=int, required=True)
    parser.add_argument("--solver", type=Path, required=True)
    parser.add_argument("--max-iterations", type=int, default=20)
    parser.add_argument("--max-cuts-per-model", type=int, default=64)
    parser.add_argument(
        "--affine-samples", type=int, default=0,
        help="extra left-null affine witnesses sampled for each rejected model",
    )
    parser.add_argument(
        "--block-restarts", type=int, default=0,
        help="48x19 block-coset coordinate-descent restarts per target slice",
    )
    parser.add_argument("--time-limit", type=int, default=60)
    parser.add_argument(
        "--resume", action="store_true",
        help="continue an existing archive up to --max-iterations total models",
    )
    parser.add_argument(
        "--keep-instances", action="store_true",
        help="retain cumulative OPBs (base plus cuts); normally they are replayed",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    apply_script = root / "n324_apply_benders_cuts.py"
    verify_script = root / "n324_verify_b_assignment.py"
    cut_script = root / "n324_benders_cut.py"
    args.work_dir.mkdir(parents=True, exist_ok=True)
    missing_args = [str(value) for value in args.missing]

    existing = sorted(args.work_dir.glob("cuts[0-9][0-9][0-9].opb"))
    start = len(existing) if args.resume else 0
    if not args.resume:
        assert not existing, "work directory already contains cuts; pass --resume"
    for iteration in range(start, args.max_iterations):
        cuts = sorted(args.work_dir.glob("cuts[0-9][0-9][0-9].opb"))
        assert len(cuts) == iteration, (iteration, cuts)
        instance = args.work_dir / f"iter{iteration:03d}.opb"
        model = args.work_dir / f"iter{iteration:03d}.out"
        if cuts:
            run(
                [
                    "python3",
                    str(apply_script),
                    str(args.base),
                    str(instance),
                    *map(str, cuts),
                ]
            )
        else:
            instance = args.base

        solver_command = [
            str(args.solver),
            "--verbosity=0",
            "--print-sol=1",
            f"--time-limit={args.time_limit}",
            str(instance),
        ]
        output, returncode, elapsed = run(
            solver_command,
            model,
        )
        status_match = re.search(r"^s (\S+)", output, re.M)
        assert status_match, output[-1000:]
        status = status_match.group(1)
        metadata = {
            "schema": "n324-benders-solver-run-v1",
            "iteration": iteration,
            "solver": str(args.solver.resolve()),
            "solver_sha256": file_sha256(args.solver),
            "command": solver_command,
            "elapsed_seconds": elapsed,
            "returncode": returncode,
            "status": status,
            "base_sha256": file_sha256(args.base),
            "instance_sha256": file_sha256(instance),
        }
        (args.work_dir / f"iter{iteration:03d}.meta.json").write_text(
            json.dumps(metadata, indent=2) + "\n"
        )
        print(
            f"ITERATION {iteration} status={status} accumulated_cut_files={len(cuts)}",
            flush=True,
        )
        if status == "UNSATISFIABLE":
            print(f"CANDIDATE_UNSAT_INSTANCE {instance}")
            return
        if status != "SATISFIABLE":
            print(f"STOP status={status}")
            return

        run(
            [
                "python3",
                str(verify_script),
                str(args.occurrence_table),
                str(model),
                "--missing",
                *missing_args,
                "--fixed-b",
                str(args.fixed_b),
            ]
        )
        cut = args.work_dir / f"cuts{iteration:03d}.opb"
        witness = args.work_dir / f"cuts{iteration:03d}.json"
        run(
            [
                "python3",
                str(cut_script),
                str(model),
                str(cut),
                str(witness),
                "--missing",
                *missing_args,
                "--fixed-b",
                str(args.fixed_b),
                "--max-cuts",
                str(args.max_cuts_per_model),
                "--affine-samples",
                str(args.affine_samples),
                "--block-restarts",
                str(args.block_restarts),
            ]
        )
        if cuts and not args.keep_instances:
            # The manifest records the instance hash.  The instance itself is a
            # deterministic, large concatenation of the base and archived cuts.
            instance.unlink()
    print(f"STOP max_iterations={args.max_iterations}")


if __name__ == "__main__":
    main()
