#!/usr/bin/env python3
"""Resumable SC2026 Parallel-AI Wassat/Green LymphoSAT comparison.

The primary result is a competition-style, single-run PAR-2 comparison over
the exact published SAT Competition 2026 400-instance manifest, using the
Parallel-track output contract: SAT models are mandatory and UNSAT proofs are
not. Runs are sequential so the two solvers do not contend for cores, and the
first solver alternates by instance to balance filesystem-cache and
thermal-order effects.

This harness intentionally does not import or vendor Green code.  It accepts
an external Green composite binary and its source archive, hashes both, and
invokes the composite's public ``solver <cnf> <proof>`` interface.
Wassat deliberately runs its adaptive threaded ``--fast`` entry. Green's
public composite still requires a proof destination and may write an UNSAT
proof even though the Parallel track does not require one. The exact commands
and that implementation asymmetry travel with every result set.

Validation is deliberately bounded by what can be established locally:

* SAT answers must have strict competition output and a model that satisfies
  the original CNF under an independent streaming check.
* UNSAT answers count only when they agree with a published, verified verdict.
* UNSAT answers on one of the competition's unresolved instances are recorded
  as ``unverified`` and receive the PAR-2 penalty.

Example:

    python3 benchmarks/parallel_h2h.py \
      --dir /tmp/satbench-2026-all \
      --scores /tmp/sc2026/scores.csv \
      --wassat /tmp/wassat-release \
      --green /opt/green/lymphosat/src/solver/solver \
      --green-source /opt/green/green.tar.xz \
      --out /tmp/wassat-green-sc2026.jsonl \
      --timeout 10
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
SCHEMA_VERSION = 1
OFFICIAL_INSTANCE_COUNT = 400
OFFICIAL_TIMEOUT_SECONDS = 1000.0
OFFICIAL_VIRTUAL_CPUS = 64
OFFICIAL_PHYSICAL_CORES = 32
OFFICIAL_MEMORY_BYTES = 256 * 1024 * 1024 * 1024
VERIFIED_STATUSES = {"sat-verified", "unsat-verified"}
SOLVED_STATUSES = {"sat", "unsat"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha256(value: Any) -> str:
    encoded = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("ascii")
    return hashlib.sha256(encoded).hexdigest()


def source_tree_sha256(paths: list[Path], root: Path) -> str:
    rows = []
    for path in sorted(paths):
        if path.is_file():
            rows.append((str(path.relative_to(root)), sha256_file(path)))
    return canonical_sha256(rows)


def published_verdicts(scores_path: Path) -> dict[str, str]:
    """Return the consensus verified verdict for every published instance."""
    by_hash: dict[str, list[dict[str, str]]] = defaultdict(list)
    with scores_path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        required = {"solverid", "instanceid", "runtime", "status", "vresult"}
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise ValueError(f"{scores_path}: missing required score columns")
        for row in reader:
            instance_hash = row["instanceid"]
            if not re.fullmatch(r"[0-9a-f]{32}", instance_hash):
                raise ValueError(
                    f"{scores_path}: invalid instance hash {instance_hash!r}"
                )
            by_hash[instance_hash].append(row)

    verdicts = {}
    for instance_hash, rows in by_hash.items():
        verified = {
            row["vresult"]
            for row in rows
            if row["status"] in VERIFIED_STATUSES
        }
        if not verified:
            verdicts[instance_hash] = "unknown"
        elif len(verified) == 1 and next(iter(verified)) in {"sat", "unsat"}:
            verdicts[instance_hash] = next(iter(verified))
        else:
            raise ValueError(
                f"{scores_path}: inconsistent verified verdicts for "
                f"{instance_hash}: {sorted(verified)}"
            )
    return verdicts


def validate_manifest(
    corpus_dir: Path,
    scores_path: Path,
    expected_count: int = OFFICIAL_INSTANCE_COUNT,
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    """Require exact score/index/file coverage and return stable instance rows."""
    expected = published_verdicts(scores_path)
    if len(expected) != expected_count:
        raise ValueError(
            f"published scores contain {len(expected)} instances, "
            f"expected {expected_count}"
        )

    index_path = corpus_dir / "index.json"
    try:
        index = json.loads(index_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ValueError(f"cannot read corpus index {index_path}: {error}") from error
    if not isinstance(index, dict):
        raise ValueError(f"{index_path}: top level must be an object")
    if len(index) != expected_count:
        raise ValueError(
            f"{index_path}: contains {len(index)} rows, expected {expected_count}"
        )

    indexed_hashes = []
    for stem, entry in index.items():
        if (
            not isinstance(stem, str)
            or not isinstance(entry, dict)
            or not isinstance(entry.get("hash"), str)
        ):
            raise ValueError(f"{index_path}: malformed entry {stem!r}")
        indexed_hashes.append(entry["hash"])
    if len(set(indexed_hashes)) != len(indexed_hashes):
        raise ValueError(f"{index_path}: duplicate official instance hash")
    if set(indexed_hashes) != set(expected):
        raise ValueError(
            f"{index_path}: hash coverage differs from published scores "
            f"(missing={len(set(expected) - set(indexed_hashes))}, "
            f"extra={len(set(indexed_hashes) - set(expected))})"
        )

    files = {path.stem: path for path in corpus_dir.glob("*.cnf") if path.is_file()}
    if set(files) != set(index):
        raise ValueError(
            f"{corpus_dir}: CNF/index coverage differs "
            f"(missing={len(set(index) - set(files))}, "
            f"extra={len(set(files) - set(index))})"
        )

    instances = []
    manifest_rows = []
    for stem, entry in index.items():
        instance_hash = entry["hash"]
        verdict = expected[instance_hash]
        indexed_verdict = entry.get("verdict", "unknown")
        if indexed_verdict != verdict:
            raise ValueError(
                f"{index_path}: {stem} says {indexed_verdict!r}, "
                f"published scores say {verdict!r}"
            )
        path = files[stem]
        size = path.stat().st_size
        if size <= 0:
            raise ValueError(f"{path}: empty CNF")
        row = {
            "stem": stem,
            "path": str(path.resolve()),
            "instance_hash": instance_hash,
            "expected": verdict,
            "cnf_bytes": size,
        }
        instances.append(row)
        manifest_rows.append(
            {
                "stem": stem,
                "instance_hash": instance_hash,
                "expected": verdict,
                "cnf_bytes": size,
            }
        )

    instances.sort(key=lambda row: row["instance_hash"])
    manifest_rows.sort(key=lambda row: row["instance_hash"])
    hashes = {
        "corpus_index_sha256": sha256_file(index_path),
        "corpus_manifest_sha256": canonical_sha256(manifest_rows),
        "scores_sha256": sha256_file(scores_path),
    }
    return instances, hashes


def output_error(message: str) -> dict[str, Any]:
    return {
        "verdict": "none",
        "assignment": {},
        "error": message,
        "value_lines": 0,
    }


def competition_output(path: Path) -> dict[str, Any]:
    """Parse strict 2026 output without loading a potentially huge model line."""
    statuses: list[str] = []
    assignment: dict[int, bool] = {}
    value_lines = 0
    terminated = False
    try:
        stream = path.open("r", encoding="ascii")
    except OSError as error:
        return output_error(f"cannot read stdout: {error}")

    try:
        with stream:
            for raw_line in stream:
                line = raw_line[:-1] if raw_line.endswith("\n") else raw_line
                if line.endswith("\r"):
                    line = line[:-1]
                if not line:
                    return output_error("blank stdout line")
                if line.startswith("c "):
                    continue
                if line in (
                    "s SATISFIABLE",
                    "s UNSATISFIABLE",
                    "s UNKNOWN",
                ):
                    statuses.append(line)
                    continue
                if not line.startswith("v "):
                    return output_error(
                        f"non-competition stdout line: {line[:120]!r}"
                    )
                if len(line) > 4096:
                    return output_error(
                        f"value line exceeds 4096 characters ({len(line)})"
                    )
                value_lines += 1
                fields = line.split()[1:]
                if not fields:
                    return output_error("empty value line")
                for index, token in enumerate(fields):
                    try:
                        literal = int(token)
                    except ValueError:
                        return output_error(f"non-integer model token: {token!r}")
                    if literal == 0:
                        if terminated or index != len(fields) - 1:
                            return output_error(
                                "model terminator is not the final model token"
                            )
                        terminated = True
                        continue
                    if terminated:
                        return output_error("model literal appears after terminator")
                    variable = abs(literal)
                    if variable == 0:
                        return output_error("zero model variable")
                    value = literal > 0
                    if variable in assignment and assignment[variable] != value:
                        return output_error(
                            f"model assigns variable {variable} both polarities"
                        )
                    assignment[variable] = value
    except (OSError, UnicodeError, ValueError) as error:
        return output_error(f"cannot parse stdout: {error}")

    if len(statuses) != 1:
        return output_error(
            f"expected exactly one solution line, found {len(statuses)}"
        )
    status = statuses[0]
    if status == "s SATISFIABLE":
        if value_lines == 0 or not terminated:
            return output_error("SAT output has no terminated model")
        return {
            "verdict": "sat",
            "assignment": assignment,
            "error": None,
            "value_lines": value_lines,
        }
    if value_lines:
        return output_error("non-SAT output contains value lines")
    if status == "s UNSATISFIABLE":
        return {
            "verdict": "unsat",
            "assignment": {},
            "error": None,
            "value_lines": 0,
        }
    return {
        "verdict": "unknown",
        "assignment": {},
        "error": None,
        "value_lines": 0,
    }


def model_satisfies(
    path: Path, assignment: dict[int, bool]
) -> tuple[bool, str | None]:
    """Stream the original DIMACS and require every clause to be satisfied."""
    header: tuple[int, int] | None = None
    clause: list[int] = []
    clauses = 0
    try:
        stream = path.open("r", encoding="ascii")
    except OSError as error:
        return False, f"cannot read CNF: {error}"

    try:
        with stream:
            for raw_line in stream:
                line = raw_line.strip()
                if not line or line.startswith("c"):
                    continue
                if line.startswith("p"):
                    fields = line.split()
                    if (
                        header is not None
                        or len(fields) != 4
                        or fields[:2] != ["p", "cnf"]
                    ):
                        return False, "invalid or repeated DIMACS header"
                    header = (int(fields[2]), int(fields[3]))
                    if header[0] < 0 or header[1] < 0:
                        return False, "negative DIMACS header count"
                    continue
                if header is None:
                    return False, "clause precedes DIMACS header"
                for token in line.split():
                    literal = int(token)
                    if literal == 0:
                        if not any(
                            assignment.get(abs(item)) == (item > 0)
                            for item in clause
                        ):
                            return False, f"unsatisfied clause {clauses + 1}"
                        clauses += 1
                        clause.clear()
                    else:
                        if abs(literal) > header[0]:
                            return False, "literal exceeds DIMACS variable count"
                        clause.append(literal)
    except (OSError, UnicodeError, ValueError) as error:
        return False, f"cannot parse CNF: {error}"

    if header is None:
        return False, "missing DIMACS header"
    if clause:
        return False, "unterminated final clause"
    if clauses != header[1]:
        return False, f"DIMACS clause count is {clauses}, expected {header[1]}"
    if any(variable < 1 or variable > header[0] for variable in assignment):
        return False, "model variable exceeds DIMACS range"
    return True, None


def send_group_signal(process: subprocess.Popen[bytes], sig: int) -> None:
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        return
    except (AttributeError, PermissionError):
        try:
            process.send_signal(sig)
        except ProcessLookupError:
            pass


def process_group_exists(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def terminate_process_group(
    process: subprocess.Popen[bytes], term_grace: float
) -> int:
    """Terminate the session leader and any dispatcher children it left."""
    sent_signal = signal.SIGTERM
    send_group_signal(process, signal.SIGTERM)
    try:
        process.wait(timeout=term_grace)
    except subprocess.TimeoutExpired:
        sent_signal = signal.SIGKILL
        send_group_signal(process, signal.SIGKILL)
        process.wait()
    # The dispatcher may exit after SIGTERM while a child remains. Its
    # isolated process group is still ours to reap forcefully.
    if process_group_exists(process.pid):
        sent_signal = signal.SIGKILL
        send_group_signal(process, signal.SIGKILL)
    return int(sent_signal)


def run_process(
    command: list[str],
    stdout_path: Path,
    stderr_path: Path,
    timeout: float,
    term_grace: float,
) -> dict[str, Any]:
    """Run one solver and kill its whole process group at the deadline."""
    started = time.perf_counter()
    timed_out = False
    sent_signal: int | None = None
    launch_error: str | None = None
    process: subprocess.Popen[bytes] | None = None
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        try:
            process = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                start_new_session=True,
            )
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                sent_signal = terminate_process_group(process, term_grace)
        except OSError as error:
            launch_error = str(error)
            stderr.write(f"launch error: {error}\n".encode("utf-8", "replace"))
        except BaseException:
            if process is not None:
                terminate_process_group(process, term_grace)
            raise

    elapsed = time.perf_counter() - started
    returncode = process.returncode if process is not None else None
    return {
        "elapsed": elapsed,
        "timed_out": timed_out,
        "exit_code": returncode if returncode is not None and returncode >= 0 else None,
        "signal": -returncode if returncode is not None and returncode < 0 else None,
        "sent_signal": int(sent_signal) if sent_signal is not None else None,
        "launch_error": launch_error,
    }


def classify_result(
    process_result: dict[str, Any],
    parsed: dict[str, Any],
    expected: str,
    cnf_path: Path,
) -> dict[str, Any]:
    if process_result["timed_out"]:
        return {
            "status": "timeout",
            "verdict": "none",
            "error": None,
            "model_checked": False,
        }
    if process_result["launch_error"] is not None:
        return {
            "status": "wrong",
            "verdict": "none",
            "error": process_result["launch_error"],
            "model_checked": False,
        }
    if parsed["error"] is not None:
        return {
            "status": "wrong",
            "verdict": "none",
            "error": parsed["error"],
            "model_checked": False,
        }

    verdict = parsed["verdict"]
    wanted_exit = {"sat": 10, "unsat": 20, "unknown": 0}[verdict]
    if process_result["exit_code"] != wanted_exit:
        return {
            "status": "wrong",
            "verdict": verdict,
            "error": (
                f"{verdict} exit code {process_result['exit_code']}, "
                f"expected {wanted_exit}"
            ),
            "model_checked": False,
        }

    if verdict == "sat":
        if expected == "unsat":
            return {
                "status": "wrong",
                "verdict": verdict,
                "error": "SAT contradicts published UNSAT",
                "model_checked": False,
            }
        valid, error = model_satisfies(cnf_path, parsed["assignment"])
        return {
            "status": "sat" if valid else "wrong",
            "verdict": verdict,
            "error": error,
            "model_checked": valid,
        }
    if verdict == "unsat":
        if expected == "sat":
            return {
                "status": "wrong",
                "verdict": verdict,
                "error": "UNSAT contradicts published SAT",
                "model_checked": False,
            }
        if expected == "unknown":
            return {
                "status": "unverified",
                "verdict": verdict,
                "error": "UNSAT on published UNKNOWN has no independent proof check",
                "model_checked": False,
            }
        return {
            "status": "unsat",
            "verdict": verdict,
            "error": None,
            "model_checked": False,
        }
    return {
        "status": "unknown",
        "verdict": verdict,
        "error": None,
        "model_checked": False,
    }


def accepted_green_matchers(stderr_path: Path) -> list[str]:
    matchers = []
    pattern = re.compile(r"^c composite: matcher (.+) accepted formula$")
    try:
        with stderr_path.open("r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                match = pattern.match(line.rstrip("\r\n"))
                if match:
                    matchers.append(match.group(1))
    except OSError:
        pass
    return matchers


def scratch_bytes(root: Path, proof_path: Path) -> tuple[int, int]:
    proof_size = proof_path.stat().st_size if proof_path.is_file() else 0
    total = 0
    for path in root.glob(proof_path.name + "*"):
        if path.is_file():
            total += path.stat().st_size
    return proof_size, total


def run_one(
    solver: str,
    executable: Path,
    instance: dict[str, Any],
    timeout: float,
    term_grace: float,
) -> dict[str, Any]:
    cnf_path = Path(instance["path"])
    started_at = datetime.now(timezone.utc).isoformat()
    with tempfile.TemporaryDirectory(
        prefix=f"wassat-green-h2h-{instance['instance_hash'][:8]}-{solver}-"
    ) as directory:
        scratch = Path(directory)
        stdout_path = scratch / "stdout"
        stderr_path = scratch / "stderr"
        proof_path = scratch / "proof.pbp"
        if solver == "wassat":
            command = [str(executable), str(cnf_path), "--fast"]
        elif solver == "green":
            command = [str(executable), str(cnf_path), str(proof_path)]
        else:
            raise ValueError(f"unknown solver {solver!r}")

        process_result = run_process(
            command, stdout_path, stderr_path, timeout, term_grace
        )
        parsed = competition_output(stdout_path)
        classified = classify_result(
            process_result, parsed, instance["expected"], cnf_path
        )
        proof_size, all_scratch_bytes = scratch_bytes(scratch, proof_path)
        elapsed = process_result["elapsed"]
        status = classified["status"]
        record = {
            "type": "result",
            "schema_version": SCHEMA_VERSION,
            "solver": solver,
            "instance_hash": instance["instance_hash"],
            "instance": instance["stem"],
            "expected": instance["expected"],
            "cnf_bytes": instance["cnf_bytes"],
            "started_at": started_at,
            "timeout": timeout,
            "elapsed": elapsed,
            "status": status,
            "verdict": classified["verdict"],
            "par2": elapsed if status in SOLVED_STATUSES else 2.0 * timeout,
            "exit_code": process_result["exit_code"],
            "signal": process_result["signal"],
            "sent_signal": process_result["sent_signal"],
            "timed_out": process_result["timed_out"],
            "stdout_bytes": stdout_path.stat().st_size,
            "stderr_bytes": stderr_path.stat().st_size,
            "proof_bytes": proof_size,
            "proof_scratch_bytes": all_scratch_bytes,
            "value_lines": parsed["value_lines"],
            "model_checked": classified["model_checked"],
            "error": classified["error"],
            "green_matchers": (
                accepted_green_matchers(stderr_path) if solver == "green" else []
            ),
        }
    return record


def green_solver_manifest(green: Path) -> tuple[str, int, str | None]:
    root = green.parent
    binaries = [green]
    binaries.extend(
        sorted(
            path
            for path in root.glob("solvers/*/solver/**")
            if path.is_file() and os.access(path, os.X_OK)
        )
    )
    seen: set[Path] = set()
    rows = []
    for path in binaries:
        resolved = path.resolve()
        if resolved in seen or not path.is_file():
            continue
        seen.add(resolved)
        rows.append((str(path.relative_to(root)), sha256_file(path)))
    fallback = root / "solvers/fallback/solver/src/build/kissat"
    fallback_sha = sha256_file(fallback) if fallback.is_file() else None
    return canonical_sha256(rows), len(rows), fallback_sha


def host_metadata() -> dict[str, Any]:
    uname = platform.uname()
    physical_cpu_count = None
    memory_bytes = None
    cpu_brand = uname.processor
    if uname.system == "Darwin":
        values = {}
        for name in ("hw.physicalcpu", "hw.memsize", "machdep.cpu.brand_string"):
            result = subprocess.run(
                ["sysctl", "-n", name],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode == 0:
                values[name] = result.stdout.strip()
        physical_cpu_count = int(values["hw.physicalcpu"]) if values.get(
            "hw.physicalcpu", ""
        ).isdigit() else None
        memory_bytes = int(values["hw.memsize"]) if values.get(
            "hw.memsize", ""
        ).isdigit() else None
        cpu_brand = values.get("machdep.cpu.brand_string", cpu_brand)
    elif hasattr(os, "sysconf"):
        try:
            page_size = int(os.sysconf("SC_PAGE_SIZE"))
            physical_pages = int(os.sysconf("SC_PHYS_PAGES"))
            memory_bytes = page_size * physical_pages
        except (OSError, ValueError):
            pass
    return {
        "hostname": socket.gethostname(),
        "system": uname.system,
        "release": uname.release,
        "version": uname.version,
        "machine": uname.machine,
        "processor": cpu_brand,
        "python": platform.python_version(),
        "logical_cpu_count": os.cpu_count(),
        "physical_cpu_count": physical_cpu_count,
        "memory_bytes": memory_bytes,
    }


def git_revision() -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def run_configuration(
    args: argparse.Namespace, corpus_hashes: dict[str, str]
) -> dict[str, Any]:
    (
        green_manifest_sha,
        green_binary_count,
        green_fallback_sha,
    ) = green_solver_manifest(args.green)
    wassat_sources = list((ROOT / "lib").glob("*.w"))
    wassat_sources.extend((ROOT / "bin").glob("*.w"))
    return {
        "schema_version": SCHEMA_VERSION,
        "track": {
            "name": "SAT Competition 2026 AI-Generated Parallel sub-track",
            "official_timeout_seconds": OFFICIAL_TIMEOUT_SECONDS,
            "official_virtual_cpus": OFFICIAL_VIRTUAL_CPUS,
            "official_physical_cores": OFFICIAL_PHYSICAL_CORES,
            "official_memory_bytes": OFFICIAL_MEMORY_BYTES,
            "sat_model_required": True,
            "unsat_proof_required": False,
            "local_short_cap_emulation": True,
        },
        "host": host_metadata(),
        "timeout": args.timeout,
        "term_grace": args.term_grace,
        "wassat_command": [str(args.wassat.resolve()), "{cnf}", "--fast"],
        "green_command": [
            str(args.green.resolve()),
            "{cnf}",
            "{per-run-proof-scratch}",
        ],
        "wassat_sha256": sha256_file(args.wassat),
        "wassat_source_sha256": source_tree_sha256(wassat_sources, ROOT),
        "wassat_git_revision": git_revision(),
        "green_sha256": sha256_file(args.green),
        "green_solver_manifest_sha256": green_manifest_sha,
        "green_solver_manifest_files": green_binary_count,
        "green_fallback_sha256": green_fallback_sha,
        "green_source_sha256": sha256_file(args.green_source),
        "corpus": corpus_hashes,
        "scores_path": str(args.scores.resolve()),
    }


class DurableLog:
    """Exclusive, fsync-after-every-line JSONL storage."""

    def __init__(self, path: Path):
        self.path = path
        self.stream = None

    def __enter__(self) -> "DurableLog":
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.stream = self.path.open("a+", encoding="utf-8")
        try:
            fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            self.stream.close()
            raise RuntimeError(f"{self.path} is locked by another run") from error
        return self

    def __exit__(self, _type, _value, _traceback) -> None:
        if self.stream is not None:
            fcntl.flock(self.stream.fileno(), fcntl.LOCK_UN)
            self.stream.close()

    def read(self) -> tuple[dict[str, Any] | None, dict[tuple[str, str], dict]]:
        assert self.stream is not None
        self.stream.seek(0)
        metadata = None
        results = {}
        for line_number, line in enumerate(self.stream, start=1):
            if not line.strip():
                raise ValueError(f"{self.path}:{line_number}: blank JSONL line")
            try:
                row = json.loads(line)
            except ValueError as error:
                raise ValueError(
                    f"{self.path}:{line_number}: invalid JSON: {error}"
                ) from error
            if row.get("type") == "meta":
                if metadata is not None or line_number != 1:
                    raise ValueError(
                        f"{self.path}:{line_number}: duplicate or misplaced metadata"
                    )
                metadata = row
            elif row.get("type") == "result":
                key = (row.get("instance_hash"), row.get("solver"))
                if key in results:
                    raise ValueError(
                        f"{self.path}:{line_number}: duplicate result {key}"
                    )
                results[key] = row
            else:
                raise ValueError(
                    f"{self.path}:{line_number}: unknown record type"
                )
        self.stream.seek(0, os.SEEK_END)
        return metadata, results

    def append(self, row: dict[str, Any]) -> None:
        assert self.stream is not None
        self.stream.write(
            json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n"
        )
        self.stream.flush()
        os.fsync(self.stream.fileno())


def comparison_outcome(
    wassat: float, green: float, tie_band: float, tie_floor: float
) -> str:
    if wassat < tie_floor and green < tie_floor:
        return "tie"
    if wassat * tie_band < green:
        return "win"
    if green * tie_band < wassat:
        return "loss"
    return "tie"


def summarize(
    results: dict[tuple[str, str], dict],
    total_instances: int,
    tie_band: float,
    tie_floor: float,
) -> dict[str, Any]:
    summary: dict[str, Any] = {"total_instances": total_instances, "solvers": {}}
    for solver in ("wassat", "green"):
        rows = [row for (_hash, name), row in results.items() if name == solver]
        counts = Counter(row["status"] for row in rows)
        summary["solvers"][solver] = {
            "completed": len(rows),
            "sat": counts["sat"],
            "unsat": counts["unsat"],
            "timeout": counts["timeout"],
            "wrong": counts["wrong"],
            "unverified": counts["unverified"],
            "unknown": counts["unknown"],
            "par2": sum(float(row["par2"]) for row in rows),
        }

    overlap = Counter()
    ratios = []
    hashes = {instance_hash for instance_hash, _solver in results}
    for instance_hash in hashes:
        wassat = results.get((instance_hash, "wassat"))
        green = results.get((instance_hash, "green"))
        w_solved = wassat is not None and wassat["status"] in SOLVED_STATUSES
        g_solved = green is not None and green["status"] in SOLVED_STATUSES
        if w_solved and g_solved:
            verdict = comparison_outcome(
                float(wassat["elapsed"]),
                float(green["elapsed"]),
                tie_band,
                tie_floor,
            )
            overlap[verdict] += 1
            if wassat["elapsed"] > 0 and green["elapsed"] > 0:
                ratios.append(float(green["elapsed"]) / float(wassat["elapsed"]))
        elif w_solved:
            overlap["wassat_only"] += 1
        elif g_solved:
            overlap["green_only"] += 1
        elif wassat is not None and green is not None:
            overlap["neither"] += 1
    summary["overlap"] = {
        "both_solved": overlap["win"] + overlap["tie"] + overlap["loss"],
        "wassat_wins": overlap["win"],
        "ties": overlap["tie"],
        "wassat_losses": overlap["loss"],
        "wassat_only": overlap["wassat_only"],
        "green_only": overlap["green_only"],
        "neither": overlap["neither"],
        "shared_geomean_green_over_wassat": (
            math.exp(statistics.fmean(math.log(ratio) for ratio in ratios))
            if ratios
            else None
        ),
    }
    return summary


def print_summary(summary: dict[str, Any]) -> None:
    print("\n== SC2026 Parallel-AI head-to-head summary ==")
    for solver in ("wassat", "green"):
        row = summary["solvers"][solver]
        print(
            f"{solver:7s} completed={row['completed']:3d} "
            f"SAT={row['sat']:3d} UNSAT={row['unsat']:3d} "
            f"timeout={row['timeout']:3d} wrong={row['wrong']:3d} "
            f"unverified={row['unverified']:3d} unknown={row['unknown']:3d} "
            f"PAR-2={row['par2']:.2f}s"
        )
    overlap = summary["overlap"]
    geomean = overlap["shared_geomean_green_over_wassat"]
    geomean_text = "--" if geomean is None else f"{geomean:.3f}x"
    print(
        "shared solved: "
        f"W/T/L={overlap['wassat_wins']}/{overlap['ties']}/"
        f"{overlap['wassat_losses']}; "
        f"W-only={overlap['wassat_only']} G-only={overlap['green_only']} "
        f"neither={overlap['neither']}; "
        f"geomean Green/Wassat={geomean_text}"
    )
    print("SUMMARY_JSON " + json.dumps(summary, sort_keys=True))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, required=True, help="exact 400-CNF corpus")
    parser.add_argument("--scores", type=Path, default=Path("/tmp/sc2026/scores.csv"))
    parser.add_argument("--wassat", type=Path, required=True)
    parser.add_argument("--green", type=Path, required=True)
    parser.add_argument(
        "--green-source",
        type=Path,
        required=True,
        help="Green source archive used to produce the external composite",
    )
    parser.add_argument("--out", type=Path, required=True, help="durable JSONL result")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--term-grace", type=float, default=1.0)
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="run only the first N rows of the exact manifest (resume smoke tests)",
    )
    parser.add_argument("--tie-band", type=float, default=1.10)
    parser.add_argument("--tie-floor", type=float, default=0.05)
    args = parser.parse_args(argv)
    if args.timeout <= 0 or args.term_grace <= 0:
        parser.error("--timeout and --term-grace must be positive")
    if args.limit < 0:
        parser.error("--limit must be nonnegative")
    if args.tie_band < 1 or args.tie_floor < 0:
        parser.error("--tie-band must be >= 1 and --tie-floor nonnegative")
    for label in ("scores", "wassat", "green", "green_source"):
        path = getattr(args, label)
        if not path.is_file():
            parser.error(f"--{label.replace('_', '-')} is not a file: {path}")
    return args


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    instances, corpus_hashes = validate_manifest(args.dir, args.scores)
    configuration = run_configuration(args, corpus_hashes)
    run_id = canonical_sha256(configuration)
    metadata = {
        "type": "meta",
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "configuration": configuration,
    }

    selected = instances[: args.limit] if args.limit else instances
    with DurableLog(args.out) as log:
        stored_metadata, results = log.read()
        if stored_metadata is None:
            log.append(metadata)
        elif stored_metadata.get("run_id") != run_id:
            raise SystemExit(
                f"{args.out}: configuration changed; use a new result path\n"
                f"stored={stored_metadata.get('run_id')} current={run_id}"
            )

        print(
            f"[h2h] exact corpus={len(instances)} selected={len(selected)} "
            f"timeout={args.timeout:g}s resume={len(results)} records "
            f"run_id={run_id}"
        )
        executables = {"wassat": args.wassat, "green": args.green}
        for position, instance in enumerate(selected):
            order = ("wassat", "green") if position % 2 == 0 else ("green", "wassat")
            for solver in order:
                key = (instance["instance_hash"], solver)
                if key in results:
                    continue
                record = run_one(
                    solver,
                    executables[solver],
                    instance,
                    args.timeout,
                    args.term_grace,
                )
                record["run_id"] = run_id
                log.append(record)
                results[key] = record
                print(
                    f"[{position + 1:03d}/{len(selected):03d}] "
                    f"{solver:7s} {instance['stem'][:36]:36s} "
                    f"{record['status']:10s} {record['elapsed']:8.3f}s",
                    flush=True,
                )

        summary = summarize(
            results, len(instances), args.tie_band, args.tie_floor
        )
        print_summary(summary)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError) as error:
        raise SystemExit(f"error: {error}") from error
