#!/usr/bin/env python3
"""Collect leakage-resistant paired Wassat routing interventions as JSONL.

This is a developer/training harness, not a solver option.  Every policy runs
the same binary with a complete, recorded environment override.  Columns are
interleaved within each instance/repetition, SAT models are checked against the
original DIMACS, and every raw repetition is retained.  Passive race winners
are deliberately not labels: downstream training derives marginal PAR-2 from
paired policy interventions.

Example:

  python3 benchmarks/router_dataset.py \
    --dir /path/to/sc2026-main --solver /tmp/wassat \
    --verdict sat --max-file-bytes 50000000 --max-field-seconds 10 \
    --timeout 3 --reps 3 --out /tmp/router.jsonl \
    --policy baseline \
    --policy sls_off:WASSAT_SLS_FLIPS=0 \
    --policy stage_off:WASSAT_STAGE_PRE=0

The deterministic family/split fields are audit metadata and must never be
included in a model feature vector.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sc2026 as SC  # noqa: E402

SCHEMA_VERSION = 2
FEATURE_VERSION = "wassat-static-v2"
FEATURE_SCHEMA_VERSION = 2
RATIO_SCALE = 1_000_000
EXACT_ONE_MAX_WIDTH = 16
EXACT_ONE_MAX_CANDIDATES = 4096
EXACT_ONE_SKETCH_BITS = 1 << 22
SPLIT_VERSION = "family-sha256-v1"
FEATURE_NAMES = [
    "nvars",
    "nclauses",
    "nlits",
    "used_vars",
    "max_clause",
    "units",
    "binary",
    "ternary",
    "width4",
    "width5_7",
    "width8_plus",
    "positive_literals",
    "negative_literals",
    "horn_clauses",
    "dual_horn_clauses",
    "all_positive_clauses",
    "all_negative_clauses",
    "variable_degree_max",
    "variable_degree_p50",
    "variable_degree_p90",
    "variable_degree_p99",
    "clause_span_sum",
    "exact_one_sketch_candidates",
    "exact_one_sketch_pair_coverage_ppm",
    "exact_one_sketch_full_groups",
    "binary_graph_edges",
    "binary_graph_vertices",
    "binary_graph_degree_max",
    "variable_occurrence_top1_ppm",
    "variable_occurrence_top10_ppm",
    "variable_occurrence_hhi_ppm",
]

# Contract consumed by the compiled offline trainer in router_trainer.w.
# Raw paired interventions still need to be aggregated into one labelled row
# per instance; this names the output columns for that separate, auditable
# step without pretending a passive race winner is a training label.
TRAINING_CSV_SCHEMA_VERSION = 2
TRAINING_CSV_METADATA_NAMES = [
    "instance_sha256",
    "family_id",
    "split",
    "label",
    "utility",
    "weight",
]
TRAINING_CSV_COLUMNS = TRAINING_CSV_METADATA_NAMES + FEATURE_NAMES


def training_csv_header() -> str:
    """Exact unquoted CSV header accepted by the compiled router trainer."""
    return ",".join(TRAINING_CSV_COLUMNS)


def _feature_schema_payload() -> bytes:
    """Canonical extractor ABI/semantics payload used by the drift guard."""
    fields = [
        f"schema_version={FEATURE_SCHEMA_VERSION}",
        f"feature_version={FEATURE_VERSION}",
        f"ratio_scale={RATIO_SCALE}",
        f"exact_one_max_width={EXACT_ONE_MAX_WIDTH}",
        f"exact_one_max_candidates={EXACT_ONE_MAX_CANDIDATES}",
        f"exact_one_sketch_bits={EXACT_ONE_SKETCH_BITS}",
        "exact_one_candidate=first-positive-distinct-width-2-through-max",
        "exact_one_pairs=two-hash-negative-binary-bloom",
        "binary_graph=nonloop-binary-clause-occurrence-multigraph",
        "occurrence=all-literal-occurrences-including-duplicates",
        *(
            f"feature[{index}]={name}"
            for index, name in enumerate(FEATURE_NAMES)
        ),
    ]
    return ("\n".join(fields) + "\n").encode("ascii")


FEATURE_SCHEMA_SHA256 = hashlib.sha256(_feature_schema_payload()).hexdigest()
# Deliberately literal: changing names, order, version, or bounded semantics
# requires an explicit checksum migration rather than silently changing data.
PINNED_FEATURE_SCHEMA_SHA256 = (
    "6c74c4ea6a670c9ff8aab655baa60243d4f34c2869d3accd91d9924afea244ca"
)
if FEATURE_SCHEMA_SHA256 != PINNED_FEATURE_SCHEMA_SHA256:
    raise AssertionError(
        "router feature schema drift: update version, checksum, fixtures, and models"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def family_id(stem: str) -> str:
    """Conservatively group obvious generator siblings without model leakage."""
    name = re.sub(r"--[0-9a-f]{12}$", "", stem.lower())
    name = re.sub(r"\.(?:cnf|xz|sanitized|dimacs)+$", "", name)
    name = re.sub(r"[0-9a-f]{24,}", "#", name)
    name = re.sub(r"\d+", "#", name)
    name = re.sub(r"[^a-z#]+", "-", name)
    name = re.sub(r"(?:-?#-?)+", "-#-", name).strip("-")
    return name or "unnamed"


def split_for_family(family: str) -> str:
    bucket = int(
        hashlib.sha256(f"{SPLIT_VERSION}|{family}".encode("utf-8")).hexdigest()[:8],
        16,
    ) % 10
    if bucket < 6:
        return "train"
    if bucket < 8:
        return "validation"
    return "test"


def parse_policy(text: str) -> tuple[str, dict[str, str]]:
    label, separator, encoded = text.partition(":")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", label):
        raise argparse.ArgumentTypeError(f"invalid policy label: {label!r}")
    overrides: dict[str, str] = {}
    if separator:
        for item in encoded.split(";"):
            key, equals, value = item.partition("=")
            if not equals or not re.fullmatch(r"WASSAT_[A-Z0-9_]+", key):
                raise argparse.ArgumentTypeError(f"invalid policy override: {item!r}")
            if key in overrides:
                raise argparse.ArgumentTypeError(f"duplicate policy override: {key}")
            overrides[key] = value
    return label, overrides


def percentile(sorted_values: list[int], numerator: int, denominator: int) -> int:
    if not sorted_values:
        return 0
    index = ((len(sorted_values) - 1) * numerator) // denominator
    return sorted_values[index]


def scaled_ratio(numerator: int, denominator: int) -> int:
    """Return a deterministic floor-scaled ratio in [0, RATIO_SCALE]."""
    if numerator <= 0 or denominator <= 0:
        return 0
    return min(RATIO_SCALE, numerator * RATIO_SCALE // denominator)


_MASK64 = (1 << 64) - 1


def _mix64(value: int) -> int:
    """Fixed SplitMix64 finalizer; unlike hash(), stable across processes."""
    value &= _MASK64
    value ^= value >> 30
    value = (value * 0xBF58476D1CE4E5B9) & _MASK64
    value ^= value >> 27
    value = (value * 0x94D049BB133111EB) & _MASK64
    return value ^ (value >> 31)


def _pair_sketch_positions(left: int, right: int) -> tuple[int, int]:
    if left > right:
        left, right = right, left
    combined = (
        left * 0x9E3779B97F4A7C15
        + right * 0xD1B54A32D192ED03
    ) & _MASK64
    first = _mix64(combined)
    second = _mix64(combined ^ 0xA0761D6478BD642F)
    mask = EXACT_ONE_SKETCH_BITS - 1
    return first & mask, second & mask


def _sketch_set(sketch: bytearray, position: int) -> None:
    sketch[position >> 3] |= 1 << (position & 7)


def _sketch_get(sketch: bytearray, position: int) -> bool:
    return bool(sketch[position >> 3] & (1 << (position & 7)))


def _sketch_add_pair(sketch: bytearray, left: int, right: int) -> None:
    first, second = _pair_sketch_positions(left, right)
    _sketch_set(sketch, first)
    _sketch_set(sketch, second)


def _sketch_has_pair(sketch: bytearray, left: int, right: int) -> bool:
    first, second = _pair_sketch_positions(left, right)
    return _sketch_get(sketch, first) and _sketch_get(sketch, second)


def static_features(path: Path) -> dict[str, int]:
    header: tuple[int, int] | None = None
    clause: list[int] = []
    hist = [0] * 9
    nlits = 0
    max_clause = 0
    positive = 0
    negative = 0
    horn = 0
    dual_horn = 0
    all_positive = 0
    all_negative = 0
    span_sum = 0
    degrees: list[int] | None = None
    binary_degrees: list[int] | None = None
    binary_graph_edges = 0
    exact_one_candidates: list[tuple[int, ...]] = []
    negative_binary_sketch = bytearray(EXACT_ONE_SKETCH_BITS >> 3)
    clauses_seen = 0

    with path.open("r", encoding="ascii") as stream:
        for line_number, raw_line in enumerate(stream, start=1):
            line = raw_line.strip()
            if not line or line.startswith("c"):
                continue
            if line.startswith("p"):
                fields = line.split()
                if header is not None or len(fields) != 4 or fields[:2] != ["p", "cnf"]:
                    raise ValueError(f"{path}: malformed header at line {line_number}")
                header = (int(fields[2]), int(fields[3]))
                degrees = [0] * (header[0] + 1)
                binary_degrees = [0] * (header[0] + 1)
                continue
            if header is None or degrees is None or binary_degrees is None:
                raise ValueError(f"{path}: clause before header at line {line_number}")
            for token in line.split():
                literal = int(token)
                if literal != 0:
                    variable = abs(literal)
                    if variable > header[0]:
                        raise ValueError(f"{path}: variable {variable} exceeds header")
                    clause.append(literal)
                    degrees[variable] += 1
                    continue

                width = len(clause)
                hist[min(width, 8)] += 1
                nlits += width
                max_clause = max(max_clause, width)
                positives = sum(item > 0 for item in clause)
                negatives = width - positives
                positive += positives
                negative += negatives
                horn += positives <= 1
                dual_horn += negatives <= 1
                all_positive += negatives == 0
                all_negative += positives == 0
                if clause:
                    variables = [abs(item) for item in clause]
                    span_sum += max(variables) - min(variables)
                    if width == 2 and variables[0] != variables[1]:
                        left, right = variables
                        binary_graph_edges += 1
                        binary_degrees[left] += 1
                        binary_degrees[right] += 1
                        if clause[0] < 0 and clause[1] < 0:
                            _sketch_add_pair(
                                negative_binary_sketch,
                                left,
                                right,
                            )
                    if (
                        2 <= width <= EXACT_ONE_MAX_WIDTH
                        and negatives == 0
                        and len(set(variables)) == width
                        and len(exact_one_candidates)
                        < EXACT_ONE_MAX_CANDIDATES
                    ):
                        exact_one_candidates.append(tuple(sorted(variables)))
                clauses_seen += 1
                clause.clear()

    if header is None or degrees is None or binary_degrees is None or clause:
        raise ValueError(f"{path}: incomplete DIMACS")
    if clauses_seen != header[1]:
        raise ValueError(
            f"{path}: declares {header[1]} clauses but contains {clauses_seen}"
        )
    used_degrees = sorted(value for value in degrees[1:] if value)
    binary_used_degrees = sorted(
        value for value in binary_degrees[1:] if value
    )
    exact_one_pair_probes = 0
    exact_one_pair_hits = 0
    exact_one_full_groups = 0
    for variables in exact_one_candidates:
        complete = True
        for left_index in range(len(variables) - 1):
            for right_index in range(left_index + 1, len(variables)):
                exact_one_pair_probes += 1
                if _sketch_has_pair(
                    negative_binary_sketch,
                    variables[left_index],
                    variables[right_index],
                ):
                    exact_one_pair_hits += 1
                else:
                    complete = False
        exact_one_full_groups += complete

    degree_square_sum = sum(value * value for value in used_degrees)
    values = {
        "nvars": header[0],
        "nclauses": header[1],
        "nlits": nlits,
        "used_vars": len(used_degrees),
        "max_clause": max_clause,
        "units": hist[1],
        "binary": hist[2],
        "ternary": hist[3],
        "width4": hist[4],
        "width5_7": hist[5] + hist[6] + hist[7],
        "width8_plus": hist[8],
        "positive_literals": positive,
        "negative_literals": negative,
        "horn_clauses": horn,
        "dual_horn_clauses": dual_horn,
        "all_positive_clauses": all_positive,
        "all_negative_clauses": all_negative,
        "variable_degree_max": used_degrees[-1] if used_degrees else 0,
        "variable_degree_p50": percentile(used_degrees, 1, 2),
        "variable_degree_p90": percentile(used_degrees, 9, 10),
        "variable_degree_p99": percentile(used_degrees, 99, 100),
        "clause_span_sum": span_sum,
        "exact_one_sketch_candidates": len(exact_one_candidates),
        "exact_one_sketch_pair_coverage_ppm": scaled_ratio(
            exact_one_pair_hits,
            exact_one_pair_probes,
        ),
        "exact_one_sketch_full_groups": exact_one_full_groups,
        "binary_graph_edges": binary_graph_edges,
        "binary_graph_vertices": len(binary_used_degrees),
        "binary_graph_degree_max": (
            binary_used_degrees[-1] if binary_used_degrees else 0
        ),
        "variable_occurrence_top1_ppm": scaled_ratio(
            used_degrees[-1] if used_degrees else 0,
            nlits,
        ),
        "variable_occurrence_top10_ppm": scaled_ratio(
            sum(used_degrees[-10:]),
            nlits,
        ),
        "variable_occurrence_hhi_ppm": scaled_ratio(
            degree_square_sum,
            nlits * nlits,
        ),
    }
    if list(values) != FEATURE_NAMES:
        raise AssertionError("feature ABI/order drift")
    return values


def classify_run(
    path: Path,
    expected: str,
    command: list[str],
    env: dict[str, str],
    timeout: float,
) -> dict:
    started = time.perf_counter()
    try:
        proc = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            check=False,
        )
        wall = time.perf_counter() - started
    except subprocess.TimeoutExpired:
        return {
            "wall_seconds": timeout,
            "par2": 2 * timeout,
            "status": "timeout",
            "verdict": "unknown",
            "exit_code": None,
            "verified": False,
            "error": None,
        }

    verdict, model, output_error = SC.competition_output(proc.stdout)
    status = "wrong"
    error = output_error
    verified = False
    if output_error is None and verdict == "sat" and proc.returncode == 10:
        if expected == "unsat":
            error = f"SAT contradicts published {expected}"
        elif SC.model_satisfies(path, model):
            status = "sat"
            verified = True
        else:
            error = "SAT model does not satisfy DIMACS"
    elif output_error is None and verdict == "unsat" and proc.returncode == 20:
        if expected == "sat":
            error = f"UNSAT contradicts published {expected}"
        elif expected == "unsat":
            # The published verdict is the independent correctness oracle for
            # this performance dataset. Proof validation remains a separate
            # competition gate.
            status = "unsat"
            verified = True
        else:
            # An UNKNOWN corpus label is not a correctness oracle for UNSAT.
            # Retain the run as unknown until a proof-aware collector validates
            # it; do not train a speed label from an unverified answer.
            status = "unknown"
            error = "UNSAT on published UNKNOWN is not proof-validated"
    elif output_error is None and verdict == "unknown":
        status = "unknown"
        error = None
    elif output_error is None:
        error = f"{verdict} with exit code {proc.returncode}"

    solved = status in ("sat", "unsat")
    return {
        "wall_seconds": wall,
        "par2": wall if solved else 2 * timeout,
        "status": status,
        "verdict": verdict,
        "exit_code": proc.returncode,
        "verified": verified,
        "error": error,
    }


def load_completed(path: Path) -> tuple[set[str], set[tuple]]:
    instances: set[str] = set()
    runs: set[tuple] = set()
    if not path.is_file():
        return instances, runs
    with path.open() as stream:
        for line in stream:
            record = json.loads(line)
            if record.get("record_type") == "instance":
                if (
                    record.get("schema_version") != SCHEMA_VERSION
                    or record.get("feature_version") != FEATURE_VERSION
                    or record.get("feature_schema_version")
                    != FEATURE_SCHEMA_VERSION
                    or record.get("feature_schema_sha256")
                    != FEATURE_SCHEMA_SHA256
                    or record.get("feature_names") != FEATURE_NAMES
                ):
                    raise ValueError(
                        f"{path}: incompatible instance/feature schema; "
                        "start a new dataset"
                    )
                instances.add(record["instance_sha256"])
            elif record.get("record_type") == "run":
                if record.get("schema_version") != SCHEMA_VERSION:
                    raise ValueError(
                        f"{path}: incompatible run schema; start a new dataset"
                    )
                runs.add(
                    (
                        record["instance_sha256"],
                        record["solver_sha256"],
                        record["policy_id"],
                        record["repetition"],
                        record["timeout_seconds"],
                    )
                )
    return instances, runs


def append_record(stream, record: dict) -> None:
    stream.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
    stream.flush()


def solver_environment(overrides: dict[str, str]) -> dict[str, str]:
    """Return a reproducible policy environment.

    Ambient WASSAT_* variables are deliberately removed.  Otherwise a shell
    left over from an earlier experiment can silently alter both the baseline
    and treatment while the JSON record claims that no such override existed.
    """
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("WASSAT_")
    }
    env.update(overrides)
    return env


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, required=True)
    parser.add_argument("--solver", type=Path, required=True)
    parser.add_argument("--solver-arg", action="append", default=["--fast"])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--policy", type=parse_policy, action="append", required=True)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--reps", type=int, default=1)
    parser.add_argument("--verdict", choices=("any", "sat", "unsat", "unknown"), default="any")
    parser.add_argument("--max-file-bytes", type=int, default=0)
    parser.add_argument("--min-field-seconds", type=float, default=0.0)
    parser.add_argument("--max-field-seconds", type=float)
    parser.add_argument(
        "--instance",
        action="append",
        default=[],
        help="exact CNF stem, filename, or published instance hash to include",
    )
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--features-only", action="store_true")
    args = parser.parse_args()

    if args.timeout <= 0 or args.reps < 1:
        parser.error("timeout and repetitions must be positive")
    labels = [label for label, _overrides in args.policy]
    if len(labels) != len(set(labels)):
        parser.error("policy labels must be unique")
    if not args.solver.is_file() or not os.access(args.solver, os.X_OK):
        parser.error(f"solver is not executable: {args.solver}")

    index_path = args.dir / "index.json"
    if not index_path.is_file():
        parser.error(f"missing corpus index: {index_path}")
    index = json.loads(index_path.read_text())
    requested = set(args.instance)
    matched: set[str] = set()
    files = sorted(args.dir.glob("*.cnf"))
    selected: list[Path] = []
    for path in files:
        entry = index.get(path.stem)
        if entry is None:
            continue
        selectors = {path.name, path.stem, str(entry.get("hash", ""))}
        hits = requested & selectors
        if requested and not hits:
            continue
        matched.update(hits)
        if args.verdict != "any" and entry.get("verdict") != args.verdict:
            continue
        if args.max_file_bytes and path.stat().st_size > args.max_file_bytes:
            continue
        best = entry.get("field_best")
        if args.min_field_seconds > 0 and (best is None or best < args.min_field_seconds):
            continue
        if args.max_field_seconds is not None and (
            best is None or best > args.max_field_seconds
        ):
            continue
        selected.append(path)
    missing = requested - matched
    if missing:
        parser.error(f"unknown --instance selector(s): {', '.join(sorted(missing))}")
    selected.sort(
        key=lambda path: hashlib.sha256(
            f"instance-order-v1|{family_id(path.stem)}|{path.stem}".encode()
        ).hexdigest()
    )
    if args.limit:
        selected = selected[: args.limit]
    if not selected:
        parser.error("no instances matched the requested corpus filters")

    solver_sha = sha256_file(args.solver)
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=Path(__file__).resolve().parents[3],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    machine = {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "logical_cpus": os.cpu_count(),
    }
    known_instances, known_runs = load_completed(args.out)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    print(
        f"{len(selected)} instances x {len(args.policy)} policies x "
        f"{args.reps} repetitions, timeout {args.timeout:g}s"
    )

    with args.out.open("a", encoding="utf-8") as output:
        for number, path in enumerate(selected, start=1):
            entry = index[path.stem]
            instance_sha = sha256_file(path)
            family = family_id(path.stem)
            features = static_features(path)
            if instance_sha not in known_instances:
                append_record(
                    output,
                    {
                        "record_type": "instance",
                        "schema_version": SCHEMA_VERSION,
                        "feature_version": FEATURE_VERSION,
                        "feature_schema_version": FEATURE_SCHEMA_VERSION,
                        "feature_schema_sha256": FEATURE_SCHEMA_SHA256,
                        "feature_names": FEATURE_NAMES,
                        "instance_sha256": instance_sha,
                        "competition_hash": entry.get("hash"),
                        "name": path.stem,
                        "path": str(path),
                        "bytes": path.stat().st_size,
                        "family_id": family,
                        "split_version": SPLIT_VERSION,
                        "split": split_for_family(family),
                        "published_verdict": entry.get("verdict"),
                        "published_best_seconds": entry.get("field_best"),
                        "features": features,
                        "feature_vector": [features[name] for name in FEATURE_NAMES],
                    },
                )
                known_instances.add(instance_sha)
            if args.features_only:
                print(f"[{number}/{len(selected)}] {path.stem}: features")
                continue

            for repetition in range(args.reps):
                rotation_seed = int(
                    hashlib.sha256(
                        f"policy-order-v1|{instance_sha}|{repetition}".encode()
                    ).hexdigest()[:8],
                    16,
                )
                rotation = rotation_seed % len(args.policy)
                policies = args.policy[rotation:] + args.policy[:rotation]
                for order, (policy_id, overrides) in enumerate(policies):
                    key = (
                        instance_sha,
                        solver_sha,
                        policy_id,
                        repetition,
                        args.timeout,
                    )
                    if key in known_runs:
                        continue
                    env = solver_environment(overrides)
                    result = classify_run(
                        path,
                        entry.get("verdict", "unknown"),
                        [str(args.solver), str(path), *args.solver_arg],
                        env,
                        args.timeout,
                    )
                    record = {
                        "record_type": "run",
                        "schema_version": SCHEMA_VERSION,
                        "instance_sha256": instance_sha,
                        "solver_sha256": solver_sha,
                        "source_commit": commit,
                        "machine": machine,
                        "policy_id": policy_id,
                        "policy_env": overrides,
                        "environment_contract": "ambient-wassat-stripped-v1",
                        "repetition": repetition,
                        "interleave_order": order,
                        "timeout_seconds": args.timeout,
                        **result,
                    }
                    append_record(output, record)
                    known_runs.add(key)
                    print(
                        f"[{number}/{len(selected)}] rep{repetition} "
                        f"{path.stem[:38]:38s} {policy_id:14s} "
                        f"{result['status']:8s} {result['wall_seconds']:.3f}s",
                        flush=True,
                    )
                    if result["status"] == "wrong":
                        raise SystemExit(
                            f"wrong result for {path.name} under {policy_id}: "
                            f"{result['error']}"
                        )


if __name__ == "__main__":
    main()
