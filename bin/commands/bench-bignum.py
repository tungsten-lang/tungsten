#!/usr/bin/env python3
"""Compare Tungsten BigInt operations with GMP and Python integers."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


MASK64 = (1 << 64) - 1
OPERATIONS = (
    "add",
    "sub",
    "mul",
    "sqr",
    "div",
    "mod",
    "gcd",
    "and",
    "or",
    "xor",
    "shl",
    "shr",
    "cmp",
    "neg",
    "abs",
    "pow",
    "powmod",
    "lcm",
    "isqrt",
    "tostr",
    "fromstr",
    # Asymmetric rows: second operand is ONE limb ("big op small", the
    # dominant real-loop shape E3 exposed). The GMP lane uses mpz_*_ui.
    "add1",
    "sub1",
    "mul1",
    "div1",
)
# Per-operation limb-count ceilings: pow results grow to 5N limbs, and the
# powmod lane mirrors Tungsten's naive square-and-multiply (O(bits)
# multiplications), which would break the target-time calibration above
# these sizes.
SIZE_CAPS = {"pow": 256, "powmod": 128}
POW_EXPONENT = 5
POWMOD_M_SEED = 0xA4093822299F31D0
# Above this, the harness switches to median-of-reps + interquartile spread:
# a single op exceeds the timing window and min-of-reps measures page-fault
# luck on multi-MB operands. FFT-band cells are not directly comparable to
# the min-based matrix and every report must say so.
FFT_BAND_LIMBS = 8192
# BN_BIGINT_POOL_MAX_CAP in runtime.c — sizes above it bypass the recycler
# entirely, so they measure a different allocation regime.
POOL_MAX_CAP_LIMBS = 16384

# str(int) / int(str) above 640 digits raise ValueError since Python 3.11
# unless the conversion-length guard is disabled.
if hasattr(sys, "set_int_max_str_digits"):
    sys.set_int_max_str_digits(0)
# 1..8192 is the min-based matrix every op can afford. The FFT band above
# 8192 stays opt-in (--sizes 16384,...,1048576): those cells use the
# median+IQR methodology, bypass the recycler above BN_BIGINT_POOL_MAX_CAP,
# and are not directly comparable — and the heavy ops (div/gcd/tostr/
# fromstr) cost minutes per cell up there. 384/448 cover the former
# 368..512 blind spot where two losing cells hid.
DEFAULT_SIZES = (
    1,
    2,
    3,
    4,
    8,
    16,
    24,
    32,
    40,
    48,
    64,
    128,
    256,
    384,
    448,
    512,
    1024,
    2048,
    4096,
    8192,
)
QUICK_SIZES = (1, 4, 16, 64)
LANE_LABELS = {
    "tungsten": "Tungsten",
    "gmp": "GMP",
    "python": "Python",
    "rust": "Rust",
    "odin": "Odin",
}


def parse_csv(value: str, *, integers: bool = False) -> list[Any]:
    pieces = [piece.strip() for piece in value.split(",") if piece.strip()]
    if not pieces:
        raise argparse.ArgumentTypeError("expected a non-empty comma list")
    if not integers:
        return pieces
    try:
        result = [int(piece) for piece in pieces]
    except ValueError as error:
        raise argparse.ArgumentTypeError("sizes must be integers") from error
    if any(item <= 0 or item > 1_048_576 for item in result):
        raise argparse.ArgumentTypeError("sizes must be in 1..1048576 limbs")
    if any(item > POOL_MAX_CAP_LIMBS for item in result):
        print(
            f"note: sizes above {POOL_MAX_CAP_LIMBS} limbs bypass the "
            "recycler (BN_BIGINT_POOL_MAX_CAP) — those cells measure a "
            "different allocation regime and must be reported as such",
            file=sys.stderr,
        )
    return result


def xorshift_word(state: int) -> tuple[int, int]:
    x = state & MASK64
    x ^= x >> 12
    x ^= (x << 25) & MASK64
    x &= MASK64
    x ^= x >> 27
    x &= MASK64
    return x, (x * 2685821657736338717) & MASK64


def operand(limbs: int, seed: int) -> int:
    state = seed & MASK64
    value = 0
    for index in range(limbs):
        state, word = xorshift_word(state)
        value |= word << (index * 64)
    value |= 1
    value |= 1 << (limbs * 64 - 1)
    return value


def operands(operation: str, limbs: int) -> tuple[int, int]:
    # Mirrors bench_boxed_operands in the native harness exactly:
    # isqrt reads a 2N-limb operand (N-limb result); cmp compares values
    # that differ only in the lowest limb (forcing a full-length scan);
    # abs takes a negative operand.
    a_limbs = 2 * limbs if operation in ("div", "mod", "isqrt") else limbs
    a = operand(a_limbs, 0x243F6A8885A308D3 ^ limbs)
    if operation == "cmp":
        b = a ^ 1
    elif operation in ("add1", "sub1", "mul1", "div1"):
        b = operand(1, 0x13198A2E03707344 ^ limbs)
    else:
        b = operand(limbs, 0x13198A2E03707344 ^ limbs)
    if operation == "abs":
        a = -a
    return a, b


def time_python(operation: str, a: int, b: int, iterations: int) -> float:
    result = 0
    previous = 0
    # Inputs that must not be charged to the timed region: the powmod
    # modulus (deterministic, mirrors the native harness seed) and the
    # decimal string that fromstr parses.
    modulus = 0
    text = ""
    if operation == "powmod":
        limbs = (b.bit_length() + 63) // 64
        modulus = operand(limbs, POWMOD_M_SEED ^ limbs)
    elif operation == "fromstr":
        text = str(a)
    start = time.perf_counter_ns()
    if operation in ("add", "add1"):
        for _ in range(iterations):
            result = a + b
            previous = result
    elif operation in ("sub", "sub1"):
        for _ in range(iterations):
            result = a - b
            previous = result
    elif operation in ("mul", "mul1"):
        for _ in range(iterations):
            result = a * b
            previous = result
    elif operation == "sqr":
        for _ in range(iterations):
            result = a * a
            previous = result
    elif operation in ("div", "div1"):
        for _ in range(iterations):
            result = a // b
            previous = result
    elif operation == "mod":
        for _ in range(iterations):
            result = a % b
            previous = result
    elif operation == "gcd":
        for _ in range(iterations):
            result = math.gcd(a, b)
            previous = result
    elif operation == "and":
        for _ in range(iterations):
            result = a & b
            previous = result
    elif operation == "or":
        for _ in range(iterations):
            result = a | b
            previous = result
    elif operation == "xor":
        for _ in range(iterations):
            result = a ^ b
            previous = result
    elif operation == "shl":
        for _ in range(iterations):
            result = a << 13
            previous = result
    elif operation == "shr":
        for _ in range(iterations):
            result = a >> 13
            previous = result
    elif operation == "cmp":
        # Accumulate counters so the comparisons cannot be folded away.
        below = 0
        above = 0
        for _ in range(iterations):
            if a < b:
                below += 1
            if a > b:
                above += 1
        previous = below - above
    elif operation == "neg":
        for _ in range(iterations):
            result = -a
            previous = result
    elif operation == "abs":
        for _ in range(iterations):
            result = abs(a)
            previous = result
    elif operation == "pow":
        for _ in range(iterations):
            result = a**POW_EXPONENT
            previous = result
    elif operation == "powmod":
        for _ in range(iterations):
            result = pow(a, b, modulus)
            previous = result
    elif operation == "lcm":
        for _ in range(iterations):
            result = math.lcm(a, b)
            previous = result
    elif operation == "isqrt":
        for _ in range(iterations):
            result = math.isqrt(a)
            previous = result
    elif operation == "tostr":
        for _ in range(iterations):
            result = str(a)
            previous = result
    elif operation == "fromstr":
        for _ in range(iterations):
            result = int(text)
            previous = result
    else:
        raise ValueError(f"unknown operation: {operation}")
    elapsed = time.perf_counter_ns() - start
    # Keep the final immutable value observable without adding per-iteration
    # Python work to the timed operation.
    if isinstance(previous, str):
        previous = len(previous)
    if (previous & MASK64) == 0xDEADBEEFDEADBEEF:
        print("", end="")
    return elapsed / iterations


def calibrate_python(
    operation: str, a: int, b: int, target_ns: int
) -> int:
    iterations = 1
    for _ in range(8):
        ns_per_operation = time_python(operation, a, b, iterations)
        elapsed = ns_per_operation * iterations
        if elapsed >= target_ns * 0.55:
            estimate = max(1, round(iterations * target_ns / elapsed))
            return min(50_000_000, estimate)
        scale = min(100.0, max(2.0, target_ns / max(elapsed, 1.0)))
        iterations = min(50_000_000, max(iterations + 1, int(iterations * scale)))
    return iterations


def run_checked(
    command: list[str],
    *,
    capture: bool = True,
    env: dict[str, str] | None = None,
) -> str:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=capture,
        check=False,
        env=env,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(command)}"
            + (f"\n{detail}" if detail else "")
        )
    return completed.stdout if capture else ""


def time_python_case(
    row: dict[str, Any], runs: int, target_ns: int
) -> None:
    operation = row["operation"]
    limbs = row["limbs"]
    a, b = operands(operation, limbs)
    iterations = calibrate_python(operation, a, b, target_ns)
    samples = [
        time_python(operation, a, b, iterations) for _ in range(runs)
    ]
    row["python_iterations"] = iterations
    row["python_ns"] = min(samples)
    row["tungsten_over_python"] = row["tungsten_ns"] / row["python_ns"]
    row.setdefault("samples", {})["python_ns"] = samples


def external_sweep(
    language: str,
    operation: str,
    sizes: list[int],
    runs: int,
    target_ms: float,
) -> dict[int, dict[str, Any]]:
    binary = EXTERNAL_BINARIES[language]
    command = [
        str(binary),
        "--sweep",
        operation,
        ",".join(str(size) for size in sizes),
        str(runs),
        f"{target_ms:g}",
    ]
    output = run_checked(command)
    rows: dict[int, dict[str, Any]] = {}
    for line in output.splitlines():
        fields = line.split("\t")
        if (
            len(fields) != 6
            or fields[0] != "external"
            or fields[1] != language
            or fields[2] != operation
        ):
            raise RuntimeError(
                f"unexpected {language} benchmark output: {line}"
            )
        limbs = int(fields[3])
        rows[limbs] = {
            "iterations": int(fields[4]),
            "ns": float(fields[5]),
        }
    if not rows and sizes:
        raise RuntimeError(f"{language} benchmark returned no rows")
    missing = sorted(set(sizes) - set(rows))
    if missing:
        raise RuntimeError(
            f"{language} benchmark omitted limb sizes: "
            + ",".join(map(str, missing))
        )
    return rows


def add_external_lanes(
    rows: list[dict[str, Any]],
    languages: list[str],
    runs: int,
    target_ms: float,
) -> None:
    if not rows:
        return
    operation = rows[0]["operation"]
    # The external harnesses (Rust num-bigint, Odin core:math/big) predate
    # the asymmetric rows; skip ops they don't implement rather than
    # erroring the whole run.
    if operation in ("add1", "sub1", "mul1", "div1"):
        return
    sizes = [row["limbs"] for row in rows]
    by_size = {row["limbs"]: row for row in rows}
    for language in languages:
        external = external_sweep(
            language, operation, sizes, runs, target_ms
        )
        for limbs, measurement in external.items():
            row = by_size[limbs]
            row[f"{language}_iterations"] = measurement["iterations"]
            row[f"{language}_ns"] = measurement["ns"]
            row[f"tungsten_over_{language}"] = (
                row["tungsten_ns"] / measurement["ns"]
            )


def fastest_label(timings: dict[str, float]) -> str:
    best = min(timings.values())
    winners = [lane for lane, timing in timings.items() if timing == best]
    return winners[0] if len(winners) == 1 else "tie"


def update_fastest(row: dict[str, Any], lanes: list[str]) -> None:
    timings: dict[str, float] = {
        lane: row[f"{lane}_ns"]
        for lane in lanes
        if f"{lane}_ns" in row and row[f"{lane}_ns"] > 0
    }
    row["fastest"] = fastest_label(timings)


def geometric_mean(values: list[float]) -> float:
    return math.exp(sum(math.log(value) for value in values) / len(values))


def aggregate_results(
    results: list[dict[str, Any]], lanes: list[str]
) -> dict[str, Any]:
    competitors = lanes[1:]
    overall: dict[str, Any] = {}
    for lane in competitors:
        ratios = [row[f"tungsten_over_{lane}"] for row in results]
        overall[lane] = {
            "cases": len(ratios),
            "tungsten_wins": sum(ratio < 1.0 for ratio in ratios),
            "tungsten_ties": sum(ratio == 1.0 for ratio in ratios),
            "tungsten_losses": sum(ratio > 1.0 for ratio in ratios),
            "tungsten_over_peer_geomean": geometric_mean(ratios),
        }
    operations = []
    for operation in OPERATIONS:
        selected = [row for row in results if row["operation"] == operation]
        if not selected:
            continue
        item: dict[str, Any] = {
            "operation": operation,
            "cases": len(selected),
        }
        for lane in competitors:
            item[f"tungsten_over_{lane}_geomean"] = geometric_mean(
                [row[f"tungsten_over_{lane}"] for row in selected]
            )
        operations.append(item)
    return {"overall": overall, "operations": operations}


def native_sample(
    operation: str, limbs: int, iterations: int, *, reverse: bool = False
) -> tuple[float, float]:
    command = [
        str(NATIVE),
        "--bench-boxed-compare",
        operation,
        str(limbs),
        str(iterations),
    ]
    if reverse:
        command.append("reverse")
    output = run_checked(command)
    fields = output.strip().split("\t")
    if len(fields) != 6 or fields[0] != "boxed":
        raise RuntimeError(f"unexpected native benchmark output: {output.strip()}")
    return float(fields[4]), float(fields[5])


def benchmark_case(
    operation: str, limbs: int, runs: int, target_ns: int
) -> dict[str, Any]:
    a, b = operands(operation, limbs)
    python_iterations = calibrate_python(operation, a, b, target_ns)
    # Python is often an order of magnitude slower than both native lanes.
    # Reusing its iteration count can leave Tungsten/GMP with only a 1-5 ms
    # timed region, where scheduler noise and CPU frequency ramp dominate.
    # Use one native pilot to choose a separate count that gives even the
    # faster native implementation approximately the requested timing window.
    pilot_tungsten_ns, pilot_gmp_ns = native_sample(
        operation, limbs, python_iterations
    )
    fastest_native_ns = max(0.001, min(pilot_tungsten_ns, pilot_gmp_ns))
    native_iterations = min(
        50_000_000,
        max(1, round(target_ns / fastest_native_ns)),
    )
    tungsten_samples: list[float] = []
    gmp_samples: list[float] = []
    python_samples: list[float] = []
    for run in range(runs):
        tungsten_ns, gmp_ns = native_sample(
            operation, limbs, native_iterations, reverse=bool(run & 1)
        )
        tungsten_samples.append(tungsten_ns)
        gmp_samples.append(gmp_ns)
        python_samples.append(
            time_python(operation, a, b, python_iterations)
        )
    tungsten_ns = min(tungsten_samples)
    gmp_ns = min(gmp_samples)
    python_ns = min(python_samples)
    timings = {
        "tungsten": tungsten_ns,
        "gmp": gmp_ns,
        "python": python_ns,
    }
    return {
        "operation": operation,
        "limbs": limbs,
        "bits": limbs * 64,
        "iterations": native_iterations,
        "native_iterations": native_iterations,
        "python_iterations": python_iterations,
        "tungsten_ns": tungsten_ns,
        "gmp_ns": gmp_ns,
        "python_ns": python_ns,
        "tungsten_over_gmp": tungsten_ns / gmp_ns,
        "tungsten_over_python": tungsten_ns / python_ns,
        "fastest": fastest_label(timings),
        "samples": {
            "tungsten_ns": tungsten_samples,
            "gmp_ns": gmp_samples,
            "python_ns": python_samples,
        },
    }


def capacity_results(max_limbs: int, requests: int, runs: int) -> list[dict[str, Any]]:
    output = run_checked(
        [
            str(NATIVE),
            "--bench-capacity-policies",
            str(max_limbs),
            str(requests),
            str(runs),
        ]
    )
    results = []
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) != 11 or fields[0] != "capacity":
            raise RuntimeError(f"unexpected capacity benchmark output: {line}")
        results.append(
            {
                "policy": fields[1],
                "live_depth": int(fields[2]),
                "max_limbs": int(fields[3]),
                "requests": int(fields[4]),
                "ns_per_request": float(fields[5]),
                "hit_percent": float(fields[6]),
                "allocations": int(fields[7]),
                "average_slack_limbs": float(fields[8]),
                "peak_kib": float(fields[9]),
                "retained_kib": float(fields[10]),
            }
        )
    return results




def harness_is_stale() -> bool:
    """Rebuild only when a source is newer than the binary.

    The unconditional rebuild cost ~7s on every invocation — far more than
    the measurements themselves for anything short of a full sweep.
    """
    if not NATIVE.exists():
        return True
    try:
        expected_profile = run_checked([str(BUILD), "--profile"]).strip()
        actual_profile = NATIVE_PROFILE.read_text().strip()
    except (RuntimeError, OSError):
        return True
    if actual_profile != expected_profile:
        return True
    built = NATIVE.stat().st_mtime
    sources = [ROOT / "benchmarks" / "big_math" / "bench_big_math.c", BUILD]
    runtime_dir = ROOT / "runtime"
    if runtime_dir.is_dir():
        sources += [
            path
            for pattern in ("*.c", "*.h", "*.m", "generated/*.h")
            for path in runtime_dir.glob(pattern)
        ]
    return any(p.exists() and p.stat().st_mtime > built for p in sources)


def external_harness_is_stale(language: str) -> bool:
    binary = EXTERNAL_BINARIES[language]
    if not binary.exists():
        return True
    built = binary.stat().st_mtime
    if language == "rust":
        sources = list(RUST_DIR.rglob("*.rs")) + [
            RUST_DIR / "Cargo.toml",
            RUST_DIR / "Cargo.lock",
        ]
    else:
        sources = list(ODIN_DIR.rglob("*.odin"))
    return any(path.exists() and path.stat().st_mtime > built for path in sources)


def build_external_harness(language: str) -> None:
    if language == "rust":
        if shutil.which("cargo") is None:
            raise RuntimeError("--rust requested, but cargo is not installed")
        env = os.environ.copy()
        native_flag = "-C target-cpu=native"
        existing_flags = env.get("RUSTFLAGS", "").strip()
        env["RUSTFLAGS"] = (
            f"{existing_flags} {native_flag}".strip()
        )
        run_checked(
            [
                "cargo",
                "build",
                "--manifest-path",
                str(RUST_DIR / "Cargo.toml"),
                "--release",
                "--locked",
            ],
            env=env,
        )
        return
    if shutil.which("odin") is None:
        raise RuntimeError("--odin requested, but odin is not installed")
    run_checked(
        [
            "odin",
            "build",
            str(ODIN_DIR),
            "-o:speed",
            "-microarch:native",
            "-no-bounds-check",
            "-disable-assert",
            f"-out:{ODIN_BINARY}",
        ]
    )


def sweep_operation(operation, sizes, runs, target_ms, on_row):
    """Time every size for one operation in ONE process, streaming rows.

    The native harness calibrates each size internally and prints a row as
    soon as it finishes, so the ~12ms process spawn and the per-rep warm-up
    are paid once per operation instead of once per (size, rep).
    """
    command = [
        str(NATIVE), "--bench-boxed-sweep", operation,
        ",".join(str(s) for s in sizes), str(runs), f"{target_ms:g}",
    ]
    rows = []
    process = subprocess.Popen(
        command, cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    malformed: list[str] = []
    for line in process.stdout:
        fields = line.rstrip("\n").split("\t")
        if (
            len(fields) != 8
            or fields[0] != "boxed"
            or fields[1] != operation
        ):
            malformed.append(line.rstrip("\n"))
            continue
        row = {
            "operation": operation,
            "limbs": int(fields[2]),
            "bits": int(fields[2]) * 64,
            "iterations": int(fields[3]),
            "native_iterations": int(fields[3]),
            "python_iterations": 0,
            "tungsten_ns": float(fields[4]),
            "gmp_ns": float(fields[5]),
            "python_ns": 0.0,
        }
        # FFT band (> 8192 limbs): the harness reports median-of-reps with
        # the interquartile spread instead of min — not directly comparable
        # to the min-based cells, so the band is flagged on the row.
        if int(fields[2]) > FFT_BAND_LIMBS:
            row["fft_band"] = True
            row["tungsten_iqr_ns"] = float(fields[6])
            row["gmp_iqr_ns"] = float(fields[7])
        row["tungsten_over_gmp"] = row["tungsten_ns"] / row["gmp_ns"]
        row["tungsten_over_python"] = 0.0
        row["fastest"] = fastest_label(
            {"tungsten": row["tungsten_ns"], "gmp": row["gmp_ns"]}
        )
        rows.append(row)
        on_row(row)
    process.wait()
    if process.returncode != 0:
        detail = (process.stderr.read() or "").strip()
        raise RuntimeError(
            f"sweep failed for {operation}" + (f"\n{detail}" if detail else "")
        )
    if malformed:
        raise RuntimeError(
            f"sweep emitted malformed rows for {operation}: {malformed!r}"
        )
    actual_sizes = [row["limbs"] for row in rows]
    if actual_sizes != list(sizes):
        raise RuntimeError(
            f"sweep row mismatch for {operation}: "
            f"expected {list(sizes)!r}, got {actual_sizes!r}"
        )
    return rows


def format_time(value: float) -> str:
    if value < 1_000:
        return f"{value:.1f} ns"
    if value < 1_000_000:
        return f"{value / 1_000:.2f} us"
    return f"{value / 1_000_000:.2f} ms"


def print_results_header(metadata: dict[str, Any]) -> None:
    labels = [f"Tungsten BigInt", f"GMP {metadata['gmp_version']}"]
    if metadata.get("python_lane"):
        labels.append(f"Python {metadata['python_version']}")
    if metadata.get("rust_lane"):
        labels.append(f"Rust num-bigint {metadata['rust_bigint_version']}")
    if metadata.get("odin_lane"):
        labels.append(f"Odin core:math/big ({metadata['odin_version']})")
    print(" vs ".join(labels))
    print(
        "Lower is better. Best-of-"
        f"{metadata['runs']}; operands are deterministic positive 64-bit limbs."
    )
    mutable = "GMP"
    if metadata.get("odin_lane"):
        mutable += " and Odin"
    print(
        "Immutable lanes keep the previous result live while computing the "
        f"next; {mutable} alternate two mutable destinations."
    )
    print()
    lanes = metadata["lanes"]
    columns = f"{'op':<8} {'limbs':>6} {'bits':>8} {'N iters':>9}"
    for lane in lanes:
        columns += f" {LANE_LABELS[lane]:>11}"
    for lane in lanes[1:]:
        columns += f" {('T/' + LANE_LABELS[lane]):>8}"
    columns += f" {'fastest':>10}"
    print(columns)


def print_result_row(row: dict[str, Any], lanes: list[str]) -> None:
    line = (
        f"{row['operation']:<8} {row['limbs']:>6} {row['bits']:>8} "
        f"{row['native_iterations']:>9}"
    )
    for lane in lanes:
        line += f" {format_time(row[f'{lane}_ns']):>11}"
    for lane in lanes[1:]:
        line += f" {row[f'tungsten_over_{lane}']:>8.2f}"
    line += f" {row['fastest']:>10}"
    print(line, flush=True)


def print_results_summary(
    results: list[dict[str, Any]], lanes: list[str], aggregate: dict[str, Any]
) -> None:
    if not results:
        return
    print()
    pieces = []
    for lane in lanes[1:]:
        stats = aggregate["overall"][lane]
        pieces.append(
            f"{LANE_LABELS[lane]} {stats['tungsten_wins']}/{stats['cases']}"
        )
    print("Tungsten faster than: " + "; ".join(pieces) + ".")
    ratios = "; ".join(
        f"T/{LANE_LABELS[lane]} "
        f"{aggregate['overall'][lane]['tungsten_over_peer_geomean']:.3f}"
        for lane in lanes[1:]
    )
    print("Overall geometric-mean ratios (lower is better): " + ratios + ".")
    print(verdict_line(results, aggregate), flush=True)


def verdict_line(
    results: list[dict[str, Any]], aggregate: dict[str, Any]
) -> str:
    """One line that scopes its own claim: architecture, size range, op
    count, fixture nature, and the unresolved band — so the headline can
    never quietly outrun what was measured."""
    limb_values = sorted({row["limbs"] for row in results})
    ops = {row["operation"] for row in results}
    ratios = [
        row["tungsten_over_gmp"] for row in results
        if row.get("tungsten_over_gmp", 0) > 0
    ]
    if not ratios:
        return "verdict: no GMP cells measured"
    wins = sum(r < 1.0 for r in ratios)
    unresolved = sum(0.95 < r < 1.05 for r in ratios)
    fft = sum(1 for row in results if row.get("fft_band"))
    stats = aggregate["overall"].get("gmp", {})
    geo = stats.get("tungsten_over_peer_geomean", 0.0)
    scope = (
        f"verdict: {platform.machine()} ({platform.system()}), "
        f"{len(ops)} ops x {limb_values[0]}..{limb_values[-1]} limbs, "
        f"one deterministic fixture per cell, mpz_* public API: "
        f"{wins}/{len(ratios)} cells < 1.0, geomean {geo:.3f}; "
        f"{unresolved} cells inside the +-5% unresolved band"
    )
    if fft:
        scope += (
            f"; {fft} FFT-band cells (median+IQR, > {FFT_BAND_LIMBS} limbs) "
            "not comparable to the min-based cells"
        )
    return scope + "."
    if len(aggregate["operations"]) <= 1:
        return
    print()
    header = f"{'op':<8} {'cases':>5}"
    for lane in lanes[1:]:
        header += f" {('T/' + LANE_LABELS[lane]):>10}"
    print(header)
    for item in aggregate["operations"]:
        line = f"{item['operation']:<8} {item['cases']:>5}"
        for lane in lanes[1:]:
            ratio = item[f"tungsten_over_{lane}_geomean"]
            line += f" {ratio:>10.3f}"
        print(line)


def print_capacity(results: list[dict[str, Any]]) -> None:
    if not results:
        return
    print()
    print("Mixed-size result-buffer capacity policies")
    print(
        "Production pool shape: power-of-two reserve, 15 logarithmic buckets, "
        "two buffers/bucket plus one hot handoff slot, one previous result live."
    )
    print(
        "Trace mixes ascending/descending sweeps, uniform and logarithmic "
        "sizes, local +1 growth, doubled results, and small-value-heavy traffic."
    )
    print(
        f"{'policy':<14} {'live':>4} {'ns/request':>10} {'hit %':>8} "
        f"{'allocs':>8} {'slack limbs':>12} {'peak KiB':>10} {'kept KiB':>10}"
    )
    for row in results:
        print(
            f"{row['policy']:<14} {row.get('live_depth', 1):>4} "
            f"{row['ns_per_request']:>10.3f} "
            f"{row['hit_percent']:>8.3f} {row['allocations']:>8} "
            f"{row['average_slack_limbs']:>12.1f} "
            f"{row['peak_kib']:>10.1f} {row['retained_kib']:>10.1f}"
        )
    # Depth 1's single-live churn pins hit% near 100 for every policy; the
    # deeper working sets are where the policies separate, so the verdict
    # line reads only those.
    deep = [r for r in results if r.get("live_depth", 1) > 1] or results
    fastest = min(deep, key=lambda row: row["ns_per_request"])
    fewest_allocations = min(deep, key=lambda row: row["allocations"])
    least_retained = min(deep, key=lambda row: row["retained_kib"])
    print()
    print(
        f"Best measured time: {fastest['policy']}; fewest allocations: "
        f"{fewest_allocations['policy']}; least retained memory: "
        f"{least_retained['policy']} (live depth > 1)."
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="tungsten bench bignum",
        description=(
            "Compare boxed immutable bignum operations across Tungsten, GMP, "
            "Python, Rust num-bigint, and Odin core:math/big, then test "
            "reusable-buffer capacity policies."
        ),
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="use 1,4,16,64-limb sizes and a shorter timing target",
    )
    parser.add_argument(
        "--sizes",
        metavar="CSV",
        help="comma-separated limb counts (default: 20 sizes from 1..8192; "
        "the >8192 FFT band is opt-in, see --list)",
    )
    parser.add_argument(
        "--operations",
        metavar="CSV",
        help="comma-separated operations (default: all)",
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=3,
        help="best-of-N measurements (default: 3)",
    )
    parser.add_argument(
        "--target-ms",
        type=float,
        help="per-lane timing target ms (default: 2, 1 quick, 110 accurate)",
    )
    parser.add_argument(
        "--python",
        action="store_true",
        help=(
            "also time CPython ints. Off by default: the Python lane is "
            "10-30x slower than the other two, so calibrating and running it "
            "dominated the suite"
        ),
    )
    parser.add_argument(
        "--rust",
        action="store_true",
        help="also time Rust num-bigint 0.5.1 (optimized native build)",
    )
    parser.add_argument(
        "--odin",
        action="store_true",
        help="also time Odin core:math/big (optimized native build)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="enable the Python, Rust, and Odin lanes",
    )
    parser.add_argument(
        "--accurate",
        action="store_true",
        help=(
            "measurement discipline for conclusions: >=110ms timed regions, "
            "9 runs alternating lane order (a 20ms region is dominated by "
            "warmup and invents phantom losses). Much slower than the "
            "default mode; required before concluding anything about a cell "
            "within ~5%% of 1.0"
        ),
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit machine-readable JSON",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="list operations, sizes, and capacity policies",
    )
    parser.add_argument(
        "--no-capacity",
        action="store_true",
        help="skip the capacity-policy experiment",
    )
    parser.add_argument(
        "--capacity-only",
        action="store_true",
        help="run only the capacity-policy experiment",
    )
    parser.add_argument(
        "--capacity-max",
        type=int,
        default=1024,
        metavar="LIMBS",
        help="largest mixed-workload result (default: 1024 limbs)",
    )
    parser.add_argument(
        "--capacity-requests",
        type=int,
        metavar="N",
        help="mixed-size requests (default: 1,000,000; quick: 200,000)",
    )
    return parser


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "benchmarks" / "big_math" / "run.sh"
NATIVE = ROOT / "benchmarks" / "big_math" / "bench_big_math"
NATIVE_PROFILE = ROOT / "benchmarks" / "big_math" / "bench_big_math.profile"
RUST_DIR = ROOT / "benchmarks" / "big_math" / "rust"
RUST_BINARY = RUST_DIR / "target" / "release" / "tungsten-bignum-rust-bench"
ODIN_DIR = ROOT / "benchmarks" / "big_math" / "odin"
ODIN_BINARY = ROOT / "benchmarks" / "big_math" / "bench_big_math_odin"
EXTERNAL_BINARIES = {"rust": RUST_BINARY, "odin": ODIN_BINARY}


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.all:
        args.python = True
        args.rust = True
        args.odin = True
    external_languages = [
        language
        for language, enabled in (("rust", args.rust), ("odin", args.odin))
        if enabled
    ]
    lanes = ["tungsten", "gmp"]
    if args.python:
        lanes.append("python")
    lanes.extend(external_languages)
    if args.runs <= 0:
        parser.error("--runs must be positive")
    if args.target_ms is not None and args.target_ms <= 0:
        parser.error("--target-ms must be positive")
    if args.capacity_max <= 0 or args.capacity_max > 16384:
        parser.error("--capacity-max must be in 1..16384")
    if args.no_capacity and args.capacity_only:
        parser.error("--no-capacity and --capacity-only cannot be combined")

    sizes = (
        parse_csv(args.sizes, integers=True)
        if args.sizes
        else list(QUICK_SIZES if args.quick else DEFAULT_SIZES)
    )
    operations = (
        parse_csv(args.operations) if args.operations else list(OPERATIONS)
    )
    unknown = [operation for operation in operations if operation not in OPERATIONS]
    if unknown:
        parser.error("unknown operation(s): " + ", ".join(unknown))
    requests = args.capacity_requests
    if requests is None:
        requests = 200_000 if args.quick else 1_000_000
    if requests < 1000:
        parser.error("--capacity-requests must be at least 1000")
    target_ms = args.target_ms
    if target_ms is None:
        if args.accurate:
            target_ms = 110.0
        else:
            target_ms = 1.0 if args.quick else 2.0
    if args.accurate and args.runs == 3:
        args.runs = 9

    if args.list:
        print("operations: " + ",".join(OPERATIONS))
        print(
            "size caps (limbs): "
            + ",".join(f"{op}={cap}" for op, cap in sorted(SIZE_CAPS.items()))
        )
        print("default sizes (limbs): " + ",".join(map(str, DEFAULT_SIZES)))
        print("quick sizes (limbs): " + ",".join(map(str, QUICK_SIZES)))
        print(
            "capacity policies: exact/+1,quantum-4,quantum-8,"
            "quantum-16,quantum-32,reserve-1.5x,power-of-two"
        )
        print("optional lanes: python,rust-num-bigint-0.5.1,odin-core-math-big")
        return 0

    if harness_is_stale():
        print("Building native BigInt/GMP harness...", file=sys.stderr)
        try:
            run_checked([str(BUILD), "--build-only"])
        except RuntimeError as error:
            print(f"tungsten bench bignum: {error}", file=sys.stderr)
            return 1

    if not args.capacity_only:
        for language in external_languages:
            if not external_harness_is_stale(language):
                continue
            print(
                f"Building optimized native {language.title()} harness...",
                file=sys.stderr,
            )
            try:
                build_external_harness(language)
            except RuntimeError as error:
                print(f"tungsten bench bignum: {error}", file=sys.stderr)
                return 1

    try:
        gmp_version = run_checked(
            ["pkg-config", "--modversion", "gmp"]
        ).strip()
    except (RuntimeError, FileNotFoundError):
        gmp_version = "unknown"
    rustc_version = ""
    if args.rust:
        try:
            rustc_version = run_checked(["rustc", "--version"]).strip()
        except (RuntimeError, FileNotFoundError):
            rustc_version = "unknown"
    odin_version = ""
    if args.odin:
        try:
            odin_version = run_checked(["odin", "version"]).strip()
            if " version " in odin_version:
                odin_version = odin_version.split(" version ", 1)[1]
        except (RuntimeError, FileNotFoundError):
            odin_version = "unknown"
    metadata = {
        "runs": args.runs,
        "python_lane": bool(args.python),
        "rust_lane": bool(args.rust),
        "odin_lane": bool(args.odin),
        "lanes": lanes,
        "target_ms": target_ms,
        "python_version": platform.python_version(),
        "gmp_version": gmp_version,
        "rust_bigint_version": "0.5.1",
        "rustc_version": rustc_version,
        "rust_digit_bits": 64,
        "odin_version": odin_version,
        "odin_digit_bits": 63,
        "platform": platform.platform(),
        "limb_bits": 64,
        "methodology": {
            "result_lifecycle": (
                "immutable APIs compute the next result while the previous "
                "one remains live; mutable APIs alternate two destinations"
            ),
            "tungsten": (
                "dead result capacity returned to a thread-local "
                "power-of-two reserve pool"
            ),
            "gmp": "two alternating mpz result destinations retain capacity",
            "python": "ordinary immutable Python integer expressions",
            "rust": (
                "borrowed operands and ordinary immutable num-bigint results; "
                "the previous result stays live until the next is computed"
            ),
            "odin": (
                "two alternating mutable core:math/big destinations retain "
                "capacity, matching the library's idiomatic API"
            ),
            "division_shape": "2N-limb positive dividend by N-limb positive divisor",
            "isqrt_shape": "2N-limb positive operand, N-limb root",
            "cmp_operands": (
                "equal except the lowest limb, forcing a full-length scan"
            ),
            "pow_exponent": POW_EXPONENT,
            "powmod": (
                "Tungsten uses bigint_powmod_any's Montgomery/Barrett window "
                "implementation (also validated against an independent naive "
                "mirror); Rust uses num-bigint modpow; Odin uses its shipped "
                "internal Montgomery/window implementation; odd modulus"
            ),
            "size_caps": SIZE_CAPS,
            "shift_bits": 13,
            "selection": "best elapsed time from all runs",
            "native_lane_order": (
                "alternate Tungsten-first and GMP-first samples"
            ),
            "calibration": (
                "the shared native iteration count is derived from the "
                "faster Tungsten/GMP pilot so both lanes reach the requested "
                "window; Python, Rust, and Odin are calibrated independently; "
                "native harness warms both implementations before timing"
            ),
            "capacity_trace": (
                "ascending/descending sweeps, uniform and logarithmic sizes, "
                "local +1 growth, doubled results, and small-value-heavy traffic"
            ),
            "capacity_selection": (
                "smallest sufficient retained capacity; hot handoff wins only "
                "within its smallest available size class"
            ),
        },
    }

    results: list[dict[str, Any]] = []
    if not args.capacity_only:
        total = sum(
            1
            for operation in operations
            for limbs in sizes
            if SIZE_CAPS.get(operation) is None or limbs <= SIZE_CAPS[operation]
        )
        print(
            f"Benchmarking {total} operation/size cases "
            f"(best of {args.runs})...",
            file=sys.stderr,
        )
        streaming = not args.json
        if streaming:
            print_results_header(metadata)
        try:
            for operation in operations:
                cap = SIZE_CAPS.get(operation)
                todo = [
                    limbs for limbs in sizes
                    if cap is None or limbs <= cap
                ]
                if not todo:
                    continue
                operation_rows = sweep_operation(
                    operation, todo, args.runs, target_ms, lambda row: None
                )
                if args.python:
                    for row in operation_rows:
                        time_python_case(
                            row,
                            args.runs,
                            round(target_ms * 1_000_000),
                        )
                add_external_lanes(
                    operation_rows,
                    external_languages,
                    args.runs,
                    target_ms,
                )
                for row in operation_rows:
                    update_fastest(row, lanes)
                    results.append(row)
                    if streaming:
                        print_result_row(row, lanes)
        except RuntimeError as error:
            print(f"tungsten bench bignum: {error}", file=sys.stderr)
            return 1
        expected_keys = [
            (operation, limbs)
            for operation in operations
            for limbs in sizes
            if SIZE_CAPS.get(operation) is None
            or limbs <= SIZE_CAPS[operation]
        ]
        actual_keys = [
            (row["operation"], row["limbs"]) for row in results
        ]
        if actual_keys != expected_keys or len(set(actual_keys)) != total:
            print(
                "tungsten bench bignum: incomplete or duplicate matrix: "
                f"expected {total} ordered cells, got {len(actual_keys)}",
                file=sys.stderr,
            )
            return 1

    capacities: list[dict[str, Any]] = []
    if not args.no_capacity:
        print(
            f"Testing capacity policies with {requests:,} mixed-size requests...",
            file=sys.stderr,
        )
        try:
            capacities = capacity_results(
                args.capacity_max, requests, args.runs
            )
        except RuntimeError as error:
            print(f"tungsten bench bignum: {error}", file=sys.stderr)
            return 1

    aggregate = (
        aggregate_results(results, lanes)
        if results
        else {"overall": {}, "operations": []}
    )
    if results and "gmp" in aggregate.get("overall", {}):
        aggregate["verdict"] = verdict_line(results, aggregate)
    if args.json:
        print(
            json.dumps(
                {
                    "metadata": metadata,
                    "results": results,
                    "summary": aggregate,
                    "capacity_policies": capacities,
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        if not args.capacity_only:
            print_results_summary(results, lanes, aggregate)
        print_capacity(capacities)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
