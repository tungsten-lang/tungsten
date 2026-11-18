#!/usr/bin/env python3
"""Strict, dependency-free checker for Wassat competition smoke output."""

from __future__ import annotations

import argparse
from collections.abc import Iterator
from pathlib import Path
from typing import TextIO


def fail(message: str) -> None:
    raise SystemExit(f"output check failed: {message}")


def dimacs_tokens(stream: TextIO) -> Iterator[str]:
    """Skip comment lines and stream even a CNF stored on one long line."""
    start_of_line = True
    comment = False
    pending = ""
    while chunk := stream.readline(65536):
        end_of_line = chunk.endswith("\n")
        if start_of_line:
            chunk = chunk.lstrip()
            if not chunk:
                continue
            comment = chunk.startswith("c")
            start_of_line = False
        if not comment:
            data = pending + chunk
            fields = data.split()
            pending = fields.pop() if data and not data[-1].isspace() else ""
            yield from fields
        if end_of_line:
            comment = False
            start_of_line = True
    if pending:
        yield pending


def dimacs_header(stream: TextIO) -> tuple[int, int]:
    for line in stream:
        line = line.strip()
        if not line or line.startswith("c"):
            continue
        fields = line.split()
        if len(fields) != 4 or fields[:2] != ["p", "cnf"]:
            fail("expected DIMACS header before clauses")
        try:
            nvars, nclauses = int(fields[2]), int(fields[3])
        except ValueError:
            fail("non-integer DIMACS header")
        if nvars < 0 or nclauses < 0:
            fail("negative DIMACS header count")
        return nvars, nclauses
    fail("missing DIMACS header")


def dimacs_literals(stream: TextIO, nvars: int, declared: int) -> Iterator[int]:
    count = 0
    pending = False
    for token in dimacs_tokens(stream):
        try:
            literal = int(token)
        except ValueError:
            fail("non-integer DIMACS clause token or duplicate header")
        if abs(literal) > nvars:
            fail(f"DIMACS literal {literal} exceeds variable count {nvars}")
        pending = literal != 0
        if not pending:
            count += 1
        yield literal
    if pending:
        fail("unterminated DIMACS clause")
    if count != declared:
        fail(f"DIMACS declares {declared} clauses but contains {count}")


def parse_cnf(path: Path) -> tuple[int, list[list[int]]]:
    """Materialize clauses for callers that explicitly request them."""
    try:
        with path.open(encoding="ascii") as stream:
            nvars, declared = dimacs_header(stream)
            clauses: list[list[int]] = []
            clause: list[int] = []
            for literal in dimacs_literals(stream, nvars, declared):
                if literal:
                    clause.append(literal)
                else:
                    clauses.append(clause)
                    clause = []
            return nvars, clauses
    except (OSError, UnicodeDecodeError) as error:
        fail(f"cannot read ASCII DIMACS {path}: {error}")


# Allocate one byte per variable in populated pages. Partial models can use
# high-numbered variables without allocating storage for the entire header.
PAGE_SIZE = 4096
UNASSIGNED = bytes(PAGE_SIZE)


def read_output(path: Path, expected: str) -> tuple[dict[int, bytearray], int]:
    pages: dict[int, bytearray] = {}
    highest = 0
    saw_status = False
    terminated = False
    wanted = "s SATISFIABLE" if expected == "SAT" else "s UNSATISFIABLE"
    try:
        with path.open(encoding="ascii") as stream:
            for raw_line in stream:
                line = raw_line.rstrip("\n")
                if not line.strip() or line.rstrip() == "c" or line.startswith("c "):
                    continue
                if line == wanted:
                    if saw_status:
                        fail("duplicate status line")
                    saw_status = True
                    continue
                if not line.startswith("v "):
                    fail(f"unexpected competition stdout line: {line[:100]!r}")
                if expected == "UNSAT":
                    fail("UNSAT output must not contain value lines")
                if len(line) > 4096:
                    fail(f"value line is {len(line)} characters, limit is 4096")
                fields = line.split()[1:]
                if not fields:
                    fail("empty value line")
                for token in fields:
                    if terminated:
                        fail("model terminator must be the final model token")
                    try:
                        literal = int(token)
                    except ValueError:
                        fail(f"non-integer model token {token!r}")
                    if literal == 0:
                        terminated = True
                        continue
                    variable = abs(literal)
                    highest = max(highest, variable)
                    number, offset = divmod(variable, PAGE_SIZE)
                    page = pages.get(number)
                    if page is None:
                        page = pages[number] = bytearray(PAGE_SIZE)
                    value = 1 if literal > 0 else 2
                    if page[offset] and page[offset] != value:
                        fail(f"model assigns variable {variable} both polarities")
                    page[offset] = value
    except (OSError, UnicodeDecodeError) as error:
        fail(f"stdout is not readable ASCII: {error}")
    if not saw_status:
        fail(f"missing {wanted!r}")
    if expected == "SAT" and not terminated:
        fail("missing model or final zero terminator")
    return pages, highest


def check_output(cnf_path: Path, output_path: Path, expected: str, actual_exit: int) -> None:
    expected_exit = {"SAT": 10, "UNSAT": 20}[expected]
    if actual_exit != expected_exit:
        fail(f"{expected} must exit {expected_exit}, got {actual_exit}")
    pages, highest = read_output(output_path, expected)
    if expected == "UNSAT":
        return
    try:
        with cnf_path.open(encoding="ascii") as stream:
            nvars, declared = dimacs_header(stream)
            if highest > nvars:
                fail(f"model variable {highest} exceeds variable count {nvars}")
            clause = 1
            satisfied = False
            for literal in dimacs_literals(stream, nvars, declared):
                if literal == 0:
                    if not satisfied:
                        fail(f"reported model does not satisfy clause {clause}")
                    clause += 1
                    satisfied = False
                elif not satisfied:
                    number, offset = divmod(abs(literal), PAGE_SIZE)
                    value = pages.get(number, UNASSIGNED)[offset]
                    satisfied = value == (1 if literal > 0 else 2)
    except (OSError, UnicodeDecodeError) as error:
        fail(f"cannot read ASCII DIMACS {cnf_path}: {error}")


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
