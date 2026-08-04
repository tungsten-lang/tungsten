#!/usr/bin/env python3
"""Verify that every imported BigNum suggestion has auditable evidence."""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BIG_MATH = ROOT / "benchmarks/big_math"
AUDIT = BIG_MATH / "SUGGESTION_AUDIT.md"
PREFIXES = ("GLM", "KIMI", "GEMMA", "QWEN", "GROK", "DEEP")
ROW = re.compile(
    r"^\| ((?:GLM|KIMI|GEMMA|QWEN|GROK|DEEP)-\d+) "
    r"\| ([^|]+) \| ([^|]+) \| (.+) \|$"
)
ARTIFACT = re.compile(r"(?<![A-Za-z0-9_.-])([A-Za-z0-9][A-Za-z0-9_.-]*\.(?:json|tsv|svg))")
FINAL_STATUSES = {"kept", "rejected", "premise rejected", "validated"}


def resolve_artifact(name: str) -> Path | None:
    for parent in (BIG_MATH / "baselines", BIG_MATH, ROOT):
        path = parent / name
        if path.is_file():
            return path
    return None


def main() -> None:
    rows = []
    errors = []
    for number, line in enumerate(AUDIT.read_text().splitlines(), 1):
        match = ROW.match(line)
        if match:
            rows.append((number, *match.groups()))

    ids = [row[1] for row in rows]
    counts = Counter(identifier.split("-", 1)[0] for identifier in ids)
    if len(rows) != 120:
        errors.append(f"expected 120 suggestion rows, found {len(rows)}")
    if len(ids) != len(set(ids)):
        errors.append("suggestion IDs are not unique")
    for prefix in PREFIXES:
        expected = {f"{prefix}-{number:02d}" for number in range(1, 21)}
        actual = {identifier for identifier in ids if identifier.startswith(prefix + "-")}
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        if missing or extra:
            errors.append(f"{prefix}: missing={missing}, extra={extra}")

    resolved = {}
    for number, identifier, _hypothesis, raw_status, evidence in rows:
        status = raw_status.strip()
        if status not in FINAL_STATUSES:
            errors.append(f"line {number} {identifier}: non-final status {status!r}")
        names = ARTIFACT.findall(evidence)
        if not names:
            errors.append(f"line {number} {identifier}: no experiment artifact")
        for name in names:
            path = resolve_artifact(name)
            if path is None:
                errors.append(f"line {number} {identifier}: missing artifact {name}")
                continue
            resolved[name] = path

    for name, path in sorted(resolved.items()):
        if path.stat().st_size == 0:
            errors.append(f"empty artifact: {path.relative_to(ROOT)}")
        if path.suffix == ".json":
            try:
                payload = json.loads(path.read_text())
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                errors.append(f"invalid JSON {path.relative_to(ROOT)}: {error}")
                continue
            if not isinstance(payload, (dict, list)) or len(payload) == 0:
                errors.append(f"empty JSON payload: {path.relative_to(ROOT)}")

    if errors:
        raise SystemExit("\n".join(f"ERROR: {error}" for error in errors))

    status_counts = Counter(row[3].strip() for row in rows)
    rendered_statuses = ", ".join(
        f"{status}={count}" for status, count in sorted(status_counts.items())
    )
    rendered_prefixes = ", ".join(f"{prefix}={counts[prefix]}" for prefix in PREFIXES)
    print(
        f"PASS suggestions={len(rows)} artifacts={len(resolved)} "
        f"({rendered_prefixes}; {rendered_statuses})"
    )


if __name__ == "__main__":
    main()
