#!/usr/bin/env python3
"""Compare Tungsten BigInt operations with GMP and Python integers."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
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
)
# Per-operation limb-count ceilings: pow results grow to 5N limbs, and the
# powmod lane mirrors Tungsten's naive square-and-multiply (O(bits)
# multiplications), which would break the target-time calibration above
# these sizes.
SIZE_CAPS = {"pow": 256, "powmod": 128}
POW_EXPONENT = 5
POWMOD_M_SEED = 0xA4093822299F31D0

# str(int) / int(str) above 640 digits raise ValueError since Python 3.11
# unless the conversion-length guard is disabled.
if hasattr(sys, "set_int_max_str_digits"):
    sys.set_int_max_str_digits(0)
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
    512,
    1024,
)
QUICK_SIZES = (1, 4, 16, 64)


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
    if any(item <= 0 or item > 16384 for item in result):
        raise argparse.ArgumentTypeError("sizes must be in 1..16384 limbs")
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
    if operation == "add":
        for _ in range(iterations):
            result = a + b
            previous = result
    elif operation == "sub":
        for _ in range(iterations):
            result = a - b
            previous = result
    elif operation == "mul":
        for _ in range(iterations):
            result = a * b
            previous = result
    elif operation == "sqr":
        for _ in range(iterations):
            result = a * a
            previous = result
    elif operation == "div":
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


def run_checked(command: list[str], *, capture: bool = True) -> str:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=capture,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(command)}"
            + (f"\n{detail}" if detail else "")
        )
    return completed.stdout if capture else ""


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
        "fastest": min(timings, key=timings.get),
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
        if len(fields) != 10 or fields[0] != "capacity":
            raise RuntimeError(f"unexpected capacity benchmark output: {line}")
        results.append(
            {
                "policy": fields[1],
                "max_limbs": int(fields[2]),
                "requests": int(fields[3]),
                "ns_per_request": float(fields[4]),
                "hit_percent": float(fields[5]),
                "allocations": int(fields[6]),
                "average_slack_limbs": float(fields[7]),
                "peak_kib": float(fields[8]),
                "retained_kib": float(fields[9]),
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
    built = NATIVE.stat().st_mtime
    sources = [ROOT / "benchmarks" / "big_math" / "bench_big_math.c", BUILD]
    runtime_dir = ROOT / "runtime"
    if runtime_dir.is_dir():
        sources += [
            path
            for pattern in ("*.c", "*.h", "*.m")
            for path in runtime_dir.glob(pattern)
        ]
    return any(p.exists() and p.stat().st_mtime > built for p in sources)


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
    for line in process.stdout:
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 6 or fields[0] != "boxed":
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
        row["tungsten_over_gmp"] = row["tungsten_ns"] / row["gmp_ns"]
        row["tungsten_over_python"] = 0.0
        row["fastest"] = (
            "tungsten" if row["tungsten_ns"] < row["gmp_ns"] else "gmp"
        )
        rows.append(row)
        on_row(row)
    process.wait()
    if process.returncode != 0:
        detail = (process.stderr.read() or "").strip()
        raise RuntimeError(
            f"sweep failed for {operation}" + (f"\n{detail}" if detail else "")
        )
    return rows


def format_time(value: float) -> str:
    if value < 1_000:
        return f"{value:.1f} ns"
    if value < 1_000_000:
        return f"{value / 1_000:.2f} us"
    return f"{value / 1_000_000:.2f} ms"


def print_results_header(metadata: dict[str, Any]) -> None:
    lanes = (
        f"Tungsten BigInt vs GMP {metadata['gmp_version']}"
        + (f" vs Python {metadata['python_version']}"
           if metadata.get("python_lane") else "")
    )
    print(lanes)
    print(
        "Lower is better. Best-of-"
        f"{metadata['runs']}; operands are deterministic positive 64-bit limbs."
    )
    print(
        "Each lane computes a new immutable result while the previous result "
        "is live; Tungsten and GMP may reuse dead result capacity."
    )
    print()
    if metadata.get("python_lane"):
        print(
            f"{'op':<8} {'limbs':>6} {'bits':>8} {'N iters':>9} {'Py iters':>9} "
            f"{'Tungsten':>11} {'GMP':>11} {'Python':>11} "
            f"{'T/GMP':>7} {'T/Py':>7} {'fastest':>9}"
        )
    else:
        print(
            f"{'op':<8} {'limbs':>6} {'bits':>8} {'N iters':>9} "
            f"{'Tungsten':>11} {'GMP':>11} {'T/GMP':>7} {'fastest':>9}"
        )


def print_result_row(row: dict[str, Any], python_lane: bool) -> None:
    if python_lane:
        print(
            f"{row['operation']:<8} {row['limbs']:>6} {row['bits']:>8} "
            f"{row['native_iterations']:>9} {row['python_iterations']:>9} "
            f"{format_time(row['tungsten_ns']):>11} "
            f"{format_time(row['gmp_ns']):>11} "
            f"{format_time(row['python_ns']):>11} "
            f"{row['tungsten_over_gmp']:>7.2f} "
            f"{row['tungsten_over_python']:>7.2f} "
            f"{row['fastest']:>9}",
            flush=True,
        )
    else:
        print(
            f"{row['operation']:<8} {row['limbs']:>6} {row['bits']:>8} "
            f"{row['native_iterations']:>9} "
            f"{format_time(row['tungsten_ns']):>11} "
            f"{format_time(row['gmp_ns']):>11} "
            f"{row['tungsten_over_gmp']:>7.2f} "
            f"{row['fastest']:>9}",
            flush=True,
        )


def print_results_summary(results: list[dict[str, Any]], python_lane: bool) -> None:
    if not results:
        return
    gmp_wins = sum(row["tungsten_ns"] < row["gmp_ns"] for row in results)
    print()
    line = f"Tungsten faster than GMP in {gmp_wins}/{len(results)} cases"
    if python_lane:
        py = sum(row["tungsten_ns"] < row["python_ns"] for row in results)
        line += f"; faster than Python in {py}/{len(results)} cases"
    print(line + ".")


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
        f"{'policy':<14} {'ns/request':>10} {'hit %':>8} {'allocs':>8} "
        f"{'slack limbs':>12} {'peak KiB':>10} {'kept KiB':>10}"
    )
    for row in results:
        print(
            f"{row['policy']:<14} {row['ns_per_request']:>10.3f} "
            f"{row['hit_percent']:>8.3f} {row['allocations']:>8} "
            f"{row['average_slack_limbs']:>12.1f} "
            f"{row['peak_kib']:>10.1f} {row['retained_kib']:>10.1f}"
        )
    fastest = min(results, key=lambda row: row["ns_per_request"])
    fewest_allocations = min(results, key=lambda row: row["allocations"])
    least_retained = min(results, key=lambda row: row["retained_kib"])
    print()
    print(
        f"Best measured time: {fastest['policy']}; fewest allocations: "
        f"{fewest_allocations['policy']}; least retained memory: "
        f"{least_retained['policy']}."
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="tungsten bench bignum",
        description=(
            "Compare boxed immutable bignum operations across Tungsten, GMP, "
            "and Python, then test reusable-buffer capacity policies."
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
        help="comma-separated limb counts (default: 15 sizes from 1..1024)",
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
        help="per-lane timing target (default: 20, or 5 quick)",
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
        "--accurate",
        action="store_true",
        help=(
            "longer timed regions and more reps (~8x slower). Default mode "
            "agrees with this on ~94%% of win/lose verdicts, median 2.8%% "
            "deviation; disagreements sit in the 1-7ns cells. Use this "
            "before concluding anything about a cell within ~5%% of 1.0"
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


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
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
            target_ms = 20.0
        else:
            target_ms = 1.0 if args.quick else 2.0
    if args.accurate and args.runs == 3:
        args.runs = 5

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
        return 0

    if harness_is_stale():
        print("Building native BigInt/GMP harness...", file=sys.stderr)
        try:
            run_checked([str(BUILD), "--build-only"])
        except RuntimeError as error:
            print(f"tungsten bench bignum: {error}", file=sys.stderr)
            return 1

    try:
        gmp_version = run_checked(
            ["pkg-config", "--modversion", "gmp"]
        ).strip()
    except (RuntimeError, FileNotFoundError):
        gmp_version = "unknown"
    metadata = {
        "runs": args.runs,
        "python_lane": bool(args.python),
        "target_ms": target_ms,
        "python_version": platform.python_version(),
        "gmp_version": gmp_version,
        "platform": platform.platform(),
        "limb_bits": 64,
        "methodology": {
            "result_lifecycle": (
                "compute next immutable result while previous result remains "
                "live, then release previous"
            ),
            "tungsten": (
                "dead result capacity returned to a thread-local "
                "power-of-two reserve pool"
            ),
            "gmp": "two alternating mpz result destinations retain capacity",
            "python": "ordinary immutable Python integer expressions",
            "division_shape": "2N-limb positive dividend by N-limb positive divisor",
            "isqrt_shape": "2N-limb positive operand, N-limb root",
            "cmp_operands": (
                "equal except the lowest limb, forcing a full-length scan"
            ),
            "pow_exponent": POW_EXPONENT,
            "powmod": (
                "Tungsten lane mirrors Int#modpow (naive LSB-first "
                "square-and-multiply); odd modulus"
            ),
            "size_caps": SIZE_CAPS,
            "shift_bits": 13,
            "selection": "best elapsed time from all runs",
            "native_lane_order": (
                "alternate Tungsten-first and GMP-first samples"
            ),
            "calibration": (
                "native and Python iteration counts calibrated independently "
                "to the requested per-lane timing target; native harness "
                "warms both implementations before timing"
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
                if args.python:
                    for limbs in todo:
                        row = benchmark_case(
                            operation, limbs, args.runs,
                            round(target_ms * 1_000_000),
                        )
                        results.append(row)
                        if streaming:
                            print_result_row(row, python_lane=True)
                else:
                    results.extend(
                        sweep_operation(
                            operation, todo, args.runs, target_ms,
                            (lambda row: print_result_row(row, python_lane=False))
                            if streaming else (lambda row: None),
                        )
                    )
        except RuntimeError as error:
            print(f"tungsten bench bignum: {error}", file=sys.stderr)
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

    if args.json:
        print(
            json.dumps(
                {
                    "metadata": metadata,
                    "results": results,
                    "capacity_policies": capacities,
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        if not args.capacity_only:
            if args.python:
                # non-streaming path already printed rows above
                pass
            print_results_summary(results, bool(args.python))
        print_capacity(capacities)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
