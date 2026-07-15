#!/usr/bin/env python3
"""Append checked Benders cuts to an OPB instance and update its header."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("cuts", nargs="+", type=Path)
    args = parser.parse_args()

    text = args.base.read_text()
    first, rest = text.split("\n", 1)
    match = re.fullmatch(
        r"\* #variable= (\d+) #constraint= (\d+) #equal= 0 intsize= 64", first
    )
    assert match, first
    variables, constraints = map(int, match.groups())
    cut_lines = []
    for path in args.cuts:
        lines = [line for line in path.read_text().splitlines() if line.strip()]
        assert lines and all(line.endswith(";") for line in lines), path
        cut_lines.extend(lines)
    header = (
        f"* #variable= {variables} #constraint= {constraints + len(cut_lines)} "
        "#equal= 0 intsize= 64"
    )
    args.output.write_text(header + "\n" + rest + "\n".join(cut_lines) + "\n")
    print(
        f"base_constraints={constraints} cuts={len(cut_lines)} "
        f"output_constraints={constraints + len(cut_lines)}"
    )


if __name__ == "__main__":
    main()
