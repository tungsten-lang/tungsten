#!/usr/bin/env python3
"""Compose Satsuma's lex-leader proof with Wassat's RUP steps and check it."""

import argparse
from pathlib import Path
import subprocess
import tempfile


def append_rup_steps(source, proof):
    count = 0
    empty = False
    for line in source:
        tokens = line.split()
        if not tokens or tokens[0] in {"d", "c"}:
            continue
        clause = [int(token) for token in tokens]
        if clause[-1] != 0 or 0 in clause[:-1] or empty:
            raise ValueError("invalid ASCII clause in Wassat's proof")
        clause.pop()
        terms = "".join(f"+1 {'~' if lit < 0 else ''}x{abs(lit)} " for lit in clause)
        proof.write(f"rup {terms}>= 1;\n")
        count += 1
        empty = not clause
    if not empty:
        raise ValueError("Wassat's proof lacks a final empty clause")
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="original DIMACS file")
    parser.add_argument("output", type=Path, help="destination for the verified VeriPB proof")
    parser.add_argument("--wassat", default=str(Path(__file__).resolve().parents[1] / "bin/wassat"))
    parser.add_argument("--satsuma", default="satsuma")
    parser.add_argument("--veripb", default="veripb")
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        parser.error("input and proof output must have distinct paths")
    with tempfile.TemporaryDirectory(dir=args.output.parent) as scratch:
        root = Path(scratch)
        reduced = root / "reduced.cnf"
        proof = root / "combined.pbp"
        suffix = root / "wassat.drat"
        subprocess.run([args.satsuma, "lex", args.input, "--veripb", "--out-file",
                        reduced, "--proof-file", proof], check=True)
        with (root / "solver.out").open("w") as log:
            result = subprocess.run([args.wassat, reduced, "--drat", suffix], stdout=log)
        if result.returncode != 20:
            raise SystemExit(f"Wassat returned {result.returncode}. No UNSAT proof was produced.")
        with suffix.open() as source, proof.open("a") as dest:
            dest.write("\n")
            steps = append_rup_steps(source, dest)
            dest.write("output NONE;\nconclusion UNSAT : -1;\nend pseudo-Boolean proof;\n")
        # RUP is monotone under retained clauses. If a future solver emits
        # stronger RAT steps, the checker rejects any unsupported inference.
        checked = subprocess.run([args.veripb, args.input, proof], capture_output=True, text=True)
        if checked.returncode or "s VERIFIED UNSATISFIABLE" not in checked.stdout.splitlines():
            raise SystemExit(f"VeriPB could not verify the proof.\n{checked.stdout}{checked.stderr}")
        proof.replace(args.output)
        print(f"VERIFIED UNSATISFIABLE, {steps} Wassat RUP steps, {args.output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
