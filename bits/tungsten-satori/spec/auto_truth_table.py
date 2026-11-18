#!/usr/bin/env python3
"""Check auto against truth tables: python3 auto_truth_table.py SATORI_BINARY.

Run from the Tungsten root. This independently checks every implication between
two formulas built from p, q, their negations, and one binary connective.
"""

import itertools
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: auto_truth_table.py SATORI_BINARY")
    binary = str(Path(sys.argv[1]).resolve())
    valuations = list(itertools.product((False, True), repeat=2))
    atoms = [
        ("p", tuple(p for p, _ in valuations)),
        ("q", tuple(q for _, q in valuations)),
    ]
    base = atoms + [(f"¬{s}", tuple(not v for v in values)) for s, values in atoms]
    formulas = base[:]
    operators = (
        ("∧", lambda p, q: p and q),
        ("∨", lambda p, q: p or q),
        ("→", lambda p, q: not p or q),
    )
    for (left, a), (right, b) in itertools.product(base, repeat=2):
        for symbol, op in operators:
            formulas.append((f"({left} {symbol} {right})", tuple(op(x, y) for x, y in zip(a, b))))

    cases = []
    for (left, a), (right, b) in itertools.product(formulas, repeat=2):
        cases.append((f"({left} → {right})", all(not x or y for x, y in zip(a, b))))

    with tempfile.TemporaryDirectory(prefix="satori-truth-table-") as tmp:
        source = Path(tmp) / "propositions.sat"
        source.write_text("".join(
            f"+ prop_{i} (p q : Prop) : {formula} := by auto\n"
            for i, (formula, _) in enumerate(cases)
        ), encoding="utf-8")
        result = subprocess.run(
            [binary, "check", "--no-cache", str(source)],
            capture_output=True, text=True, timeout=60, check=False,
        )

    passed = set()
    failed = set()
    for line in result.stdout.splitlines():
        match = re.match(r"^✓ prop_(\d+) : ", line)
        if match:
            passed.add(int(match.group(1)))
        match = re.match(r"^✗ line \d+ \(theorem prop_(\d+)\): ", line)
        if match:
            failed.add(int(match.group(1)))
    expected = {i for i, (_, valid) in enumerate(cases) if valid}
    all_cases = set(range(len(cases)))
    if result.returncode != 1 or passed != expected or failed != all_cases - expected:
        bad = sorted(passed - expected)
        missed = sorted(expected - passed)
        missing = sorted(all_cases - passed - failed)
        print(f"truth-table audit failed: invalid accepted={bad}, valid missed={missed}, missing={missing}", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise SystemExit(1)
    print(f"auto truth tables passed: {len(cases)} formulas, {len(expected)} valid")


if __name__ == "__main__":
    main()
