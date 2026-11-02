#!/usr/bin/env python3
"""Check the CLI aggregate cap while the final solver resumes its scout."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    # Block every assignment. The bounded searches must remain UNKNOWN;
    # this exercises continuation without relying on a stored SAT witness.
    nv = 8
    cnf = f"p cnf {nv} {1 << nv}\n" + "".join(
        " ".join(str(v if mask & (1 << (v - 1)) else -v)
                 for v in range(1, nv + 1)) + " 0\n"
        for mask in range(1 << nv)
    )
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("WASSAT_", "STUDY_"))}
    env.update(WASSAT_BACKDOOR_TABLES="0", WASSAT_PROFILE="1",
               WASSAT_ARMS="1", WASSAT_PRE_ARMS="0", WASSAT_SLS_FLIPS="0",
               WASSAT_RAW_AT="0", WASSAT_PROBE_CONFLICTS="2", WASSAT_OTFS="0",
               TUNGSTEN_ALLOC_PROFILE="0")
    with tempfile.TemporaryDirectory(prefix="wassat-budget-") as temp:
        path = Path(temp) / "cube.cnf"
        path.write_text(cnf)
        for budget in (1, 2, 10):
            result = subprocess.run(
                [str(args.binary.resolve()), str(path), "--fast",
                 "--conflicts", str(budget)], env=env, text=True,
                capture_output=True, timeout=30,
            )
            assert result.returncode == 0, result.stderr
            assert "s UNKNOWN" in result.stdout, result.stdout
            count = re.search(r"^c conflicts: (\d+)", result.stdout, re.M)
            assert count and int(count[1]) == budget, result.stdout
            scout = re.search(r"cli.scout.search conflicts=(\d+)", result.stderr)
            assert scout and int(scout[1]) == min(budget, 2), result.stderr
    print("PASS: aggregate budgets 1, 2, and 10, including scout continuation")


if __name__ == "__main__":
    main()
