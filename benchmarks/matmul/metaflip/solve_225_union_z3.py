#!/usr/bin/env python3
"""Bounded Z3 comparison for the serialized <2,2,5> fixed dictionary.

The production generator/orchestrator is Tungsten.  This intentionally small
comparison reads its SHA-pinned term order and asks Z3 for the same native
Bool-Xor + pseudo-Boolean problem.  SAT models are reconstructed against all
400 tensor coefficients before a certificate is written.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

import z3

from audit_225_union_subset_sat import column, read_terms, target


def xor_all(values: list[z3.BoolRef]) -> z3.BoolRef:
    assert values
    layer = values
    while len(layer) > 1:
        following = []
        for i in range(0, len(layer) - 1, 2):
            following.append(z3.Xor(layer[i], layer[i + 1]))
        if len(layer) & 1:
            following.append(layer[-1])
        layer = following
    return layer[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("terms", type=Path)
    parser.add_argument("--limit", type=int, default=17)
    parser.add_argument("--timeout", type=int, default=60, help="seconds")
    parser.add_argument("--sha256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--exact", action="store_true")
    parser.add_argument(
        "--lb17-certified",
        action="store_true",
        help="required for exact-17; acknowledges the checked R>=17 certificate",
    )
    args = parser.parse_args()
    if args.exact and (args.limit != 17 or not args.lb17_certified):
        parser.error("--exact is allowed only for 17 with --lb17-certified")

    lower_bound_audited = False
    if args.exact:
        verifier = Path(__file__).with_name("proof_inner2") / "n225_verify_wang.py"
        audit = subprocess.run(
            [sys.executable, str(verifier), "--audit-only"],
            check=True,
            capture_output=True,
            text=True,
        )
        payload = json.loads(audit.stdout)
        assert payload["tensor"] == "<2,2,5>"
        assert payload["field"] == "GF(2)"
        assert payload["verified_lower_bound_encoded"] == 17
        lower_bound_audited = True

    digest = hashlib.sha256(args.terms.read_bytes()).hexdigest()
    if args.sha256:
        assert digest == args.sha256, (digest, args.sha256)
    terms = read_terms(args.terms)
    columns = [column(term) for term in terms]
    wanted = target()
    variables = [z3.Bool(f"x{i}") for i in range(len(terms))]
    solver = z3.Solver()
    solver.set(timeout=args.timeout * 1000)

    xor_rows = 0
    for cell in range(400):
        row = [variables[i] for i, value in enumerate(columns) if (value >> cell) & 1]
        if not row:
            assert not ((wanted >> cell) & 1), f"uncovered target cell {cell}"
            continue
        parity = xor_all(row)
        solver.add(parity if ((wanted >> cell) & 1) else z3.Not(parity))
        xor_rows += 1
    weighted = [(variable, 1) for variable in variables]
    if args.exact:
        solver.add(z3.PbEq(weighted, args.limit))
        cardinality = "PbEq"
    else:
        solver.add(z3.PbLe(weighted, args.limit))
        cardinality = "PbLe"

    started = time.monotonic()
    result = solver.check()
    elapsed = time.monotonic() - started
    reason = ""
    selected = None
    if result == z3.sat:
        model = solver.model()
        chosen = [i for i, variable in enumerate(variables) if z3.is_true(model.eval(variable, model_completion=True))]
        assert len(chosen) <= args.limit
        if args.exact:
            assert len(chosen) == args.limit
        reconstruction = 0
        for index in chosen:
            reconstruction ^= columns[index]
        assert reconstruction == wanted
        selected = len(chosen)
        if args.output:
            body = "\n".join(f"R {terms[i][0]} {terms[i][1]} {terms[i][2]}" for i in chosen) + "\n"
            args.output.write_text(body)
    elif result == z3.unknown:
        reason = solver.reason_unknown()

    stats = solver.statistics()
    stat_text = ",".join(f"{key}={stats.get_key_value(key)}" for key in stats.keys())
    print(
        "FF225_UNION_Z3_RESULT"
        f" status={result} reason={reason or '-'} elapsed_ms={int(elapsed * 1000)}"
        f" terms={len(terms)} xor_rows={xor_rows} cardinality={cardinality}"
        f" limit={args.limit} selected={selected} sha256={digest} stats={stat_text}"
        f" lb17_audit={int(lower_bound_audited)}"
    )


if __name__ == "__main__":
    main()
