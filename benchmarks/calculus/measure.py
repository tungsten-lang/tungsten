"""Paired process-level timings for two compiled scaling.w binaries.

Usage: python3 benchmarks/calculus/measure.py /path/before /path/after
Prints JSON Lines with raw samples, median, MAD, and output parity.
"""
import json
import platform
import statistics
import subprocess
import sys
import time

before, after = sys.argv[1:]
executables = {"before": before, "after": after}
for kind, size, repeats in [
    ("add", 16, 10), ("add", 32, 10),
    ("gk", 64, 4), ("gk", 256, 4), ("gk", 512, 4),
]:
    samples = {"before": [], "after": []}
    outputs = {}
    for executable in executables.values():
        subprocess.run([executable, kind, str(size), str(repeats)],
                       check=True, capture_output=True)
    for iteration in range(30):
        order = ["before", "after"] if iteration % 2 == 0 else ["after", "before"]
        for variant in order:
            start = time.perf_counter_ns()
            result = subprocess.run(
                [executables[variant], kind, str(size), str(repeats)],
                check=True, capture_output=True, text=True)
            samples[variant].append((time.perf_counter_ns() - start) / 1e6)
            output = result.stdout.strip()
            if variant in outputs and outputs[variant] != output:
                raise RuntimeError("Nondeterministic benchmark output")
            outputs[variant] = output
    if outputs["before"] != outputs["after"]:
        raise RuntimeError("Benchmark checksum mismatch")
    summary = {}
    for variant, values in samples.items():
        median = statistics.median(values)
        summary[variant] = {
            "median_ms": median,
            "mad_ms": statistics.median(abs(value - median) for value in values),
        }
    print(json.dumps({
        "workload": kind, "size": size, "iterations": repeats,
        "summary": summary, "outputs": outputs, "samples_ms": samples,
        "speedup": summary["before"]["median_ms"] / summary["after"]["median_ms"],
    }), flush=True)
print(json.dumps({"platform": platform.platform(), "machine": platform.machine()}))
