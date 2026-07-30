#!/usr/bin/env python3
"""Strict, dependency-free checker for Wassat competition smoke output."""

from __future__ import annotations

import argparse
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"output check failed: {message}")


def parse_cnf(path: Path) -> tuple[int, list[list[int]]]:
    try:
        text = path.read_text(encoding="ascii")
    except (OSError, UnicodeDecodeError) as error:
        fail(f"cannot read ASCII DIMACS {path}: {error}")

    header: tuple[int, int] | None = None
    tokens: list[int] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("c"):
            continue
        if line.startswith("p"):
            fields = line.split()
            if header is not None or len(fields) != 4 or fields[:2] != ["p", "cnf"]:
                fail("malformed or duplicate DIMACS header")
            try:
                header = (int(fields[2]), int(fields[3]))
            except ValueError:
                fail("non-integer DIMACS header")
            continue
        if header is None:
            fail("clause appears before DIMACS header")
        try:
            tokens.extend(int(token) for token in line.split())
        except ValueError:
            fail("non-integer DIMACS clause token")

    if header is None:
        fail("missing DIMACS header")
    nvars, declared_clauses = header
    clauses: list[list[int]] = []
    clause: list[int] = []
    for literal in tokens:
        if literal == 0:
            clauses.append(clause)
            clause = []
        else:
            if abs(literal) > nvars:
                fail(f"DIMACS literal {literal} exceeds variable count {nvars}")
            clause.append(literal)
    if clause:
        fail("unterminated DIMACS clause")
    if len(clauses) != declared_clauses:
        fail(
            f"DIMACS declares {declared_clauses} clauses but contains {len(clauses)}"
        )
    return nvars, clauses


def check_output(
    cnf_path: Path, output_path: Path, expected: str, actual_exit: int
) -> None:
    expected_exit = {"SAT": 10, "UNSAT": 20}[expected]
    if actual_exit != expected_exit:
        fail(f"{expected} must exit {expected_exit}, got {actual_exit}")

    try:
        text = output_path.read_text(encoding="ascii")
    except (OSError, UnicodeDecodeError) as error:
        fail(f"stdout is not readable ASCII: {error}")

    statuses: list[str] = []
    value_lines: list[str] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        if line.rstrip() == "c" or line.startswith("c "):
            continue
        if line in ("s SATISFIABLE", "s UNSATISFIABLE", "s UNKNOWN"):
            statuses.append(line)
            continue
        if line.startswith("v "):
            if len(line) > 4096:
                fail(f"value line is {len(line)} characters, limit is 4096")
            value_lines.append(line)
            continue
        fail(f"non-competition stdout line: {line!r}")

    wanted_status = "s SATISFIABLE" if expected == "SAT" else "s UNSATISFIABLE"
    if statuses != [wanted_status]:
        fail(f"expected exactly [{wanted_status!r}], got {statuses!r}")

    if expected == "UNSAT":
        if value_lines:
            fail("UNSAT output must not contain value lines")
        return

    if not value_lines:
        fail("SAT output has no value lines")

    nvars, clauses = parse_cnf(cnf_path)
    assignment: dict[int, bool] = {}
    saw_terminator = False
    for line_index, line in enumerate(value_lines):
        fields = line.split()[1:]
        if not fields:
            fail("empty value line")
        for token_index, token in enumerate(fields):
            try:
                literal = int(token)
            except ValueError:
                fail(f"non-integer model token {token!r}")
            if literal == 0:
                if line_index != len(value_lines) - 1 or token_index != len(fields) - 1:
                    fail("model terminator must be the final token of the final value line")
                saw_terminator = True
                continue
            if saw_terminator:
                fail("model literal appears after terminator")
            variable = abs(literal)
            if variable < 1 or variable > nvars:
                fail(f"model literal {literal} exceeds variable count {nvars}")
            value = literal > 0
            if variable in assignment and assignment[variable] != value:
                fail(f"model assigns variable {variable} both polarities")
            assignment[variable] = value

    if not saw_terminator:
        fail("final value line is not terminated by zero")

    for index, clause in enumerate(clauses, start=1):
        if not any(
            abs(literal) in assignment
            and assignment[abs(literal)] == (literal > 0)
            for literal in clause
        ):
            fail(f"reported model does not satisfy clause {index}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("cnf", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("expected", choices=("SAT", "UNSAT"))
    parser.add_argument("exit_code", type=int)
    args = parser.parse_args()
    check_output(args.cnf, args.output, args.expected, args.exit_code)


if __name__ == "__main__":
    main()

