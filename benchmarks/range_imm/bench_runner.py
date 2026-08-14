#!/usr/bin/env python3
"""Interleaved median timing for the range_imm before/after binaries.

Usage: python3 bench_runner.py <dir-with-binaries>
Expects: null_bench, {arr,arr4k,fused}_{before,after}, imm_after,
imm4k_after (build each .w here with `bin/tungsten -o <bin> --release`;
null_bench is any trivial `<< 0` program, used as the startup baseline).
"""
import subprocess, time, statistics, sys, os

S = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
BINARIES = [
    "null_bench",
    "arr_before", "arr_after",
    "arr4k_before", "arr4k_after",
    "fused_before", "fused_after",
    "imm_after", "imm4k_after",
]
ROUNDS = 11  # first round discarded as warmup

times = {b: [] for b in BINARIES}
for r in range(ROUNDS):
    for b in BINARIES:
        t0 = time.perf_counter()
        subprocess.run([os.path.join(S, b)], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=True)
        times[b].append(time.perf_counter() - t0)

null_med = statistics.median(times["null_bench"][1:])
print(f"{'binary':<14} {'median(s)':>10} {'adj(s)':>10} {'min(s)':>10}")
for b in BINARIES:
    med = statistics.median(times[b][1:])
    print(f"{b:<14} {med:>10.4f} {med - null_med:>10.4f} {min(times[b][1:]):>10.4f}")
print(f"\nstartup baseline (null median): {null_med:.4f}s")

def adj(name):
    return statistics.median(times[name][1:]) - null_med

print("\nworkload-only ratios (median - startup):")
print(f"  arr   before/after : {adj('arr_before')/adj('arr_after'):6.3f}x  (producer win, len 64)")
print(f"  arr4k before/after : {adj('arr4k_before')/adj('arr4k_after'):6.3f}x  (producer win, len 4096)")
print(f"  fused before/after : {adj('fused_before')/adj('fused_after'):6.3f}x  (parity ≈ 1.0)")
print(f"  arr_before / imm_after     (len 64)  : {adj('arr_before')/adj('imm_after'):8.2f}x")
print(f"  arr4k_before / imm4k_after (len 4096): {adj('arr4k_before')/adj('imm4k_after'):8.2f}x")
