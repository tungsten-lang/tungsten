#!/usr/bin/env python3
"""A/B driver for the pmndrs-math-inspired Tungsten benchmarks.

Each bench binary takes `<variant> <iters>` and runs ONE variant's timed
loop, printing a line `ns/op: <float> checksum: <value>`. This driver runs
every variant in its own process, interleaved round-robin, `reps` times,
under `/usr/bin/time -l`, and reports per variant:

  wall ns/op   median of the program's own clock() loop timing
  instr/op     (instructions retired at iters - at iters=0) / iters, median
  cyc/op       same, from `cycles elapsed`
  peak MB      peak memory footprint at the full iteration count

Instructions retired is immune to CPU contention, so it is the stable
signal for "did the change remove work". It is blind to latency (one
fdiv and one fmul are each one instruction), so latency-bound changes
(reciprocal-multiply instead of divide) must be judged on wall/cycles,
which are only trustworthy on a quiet machine. Ratios are vs the first
variant listed.

usage: ab.py <binary> <iters> <reps> <variant> [<variant> ...]
"""
import re
import statistics
import subprocess
import sys


def run(binary, variant, iters):
    p = subprocess.run(["/usr/bin/time", "-l", binary, variant, str(iters)],
                       capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"{binary} {variant} {iters} failed ({p.returncode}):\n{p.stdout}\n{p.stderr}")
    ns = re.search(r"ns/op:\s*([0-9.eE+-]+)", p.stdout)
    ck = re.search(r"checksum:\s*(\S+)", p.stdout)
    ins = re.search(r"(\d+)\s+instructions retired", p.stderr)
    cyc = re.search(r"(\d+)\s+cycles elapsed", p.stderr)
    mem = re.search(r"(\d+)\s+peak memory footprint", p.stderr)
    return {
        "ns": float(ns.group(1)) if ns else float("nan"),
        "checksum": ck.group(1) if ck else "?",
        "ins": int(ins.group(1)) if ins else 0,
        "cyc": int(cyc.group(1)) if cyc else 0,
        "mem": int(mem.group(1)) / 1e6 if mem else 0.0,
    }


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    binary, iters, reps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    variants = sys.argv[4:]
    base = {v: run(binary, v, 0) for v in variants}
    rows = {v: [] for v in variants}
    for _ in range(reps):
        for v in variants:
            rows[v].append(run(binary, v, iters))
    first = None
    print(f"{'variant':<28}{'wall ns/op':>12}{'instr/op':>11}{'cyc/op':>10}{'peak MB':>9}"
          f"{'wall x':>8}{'instr x':>9}  checksum")
    for v in variants:
        r = rows[v]
        ns = statistics.median(x["ns"] for x in r)
        ins = statistics.median((x["ins"] - base[v]["ins"]) / iters for x in r)
        cyc = statistics.median((x["cyc"] - base[v]["cyc"]) / iters for x in r)
        mem = statistics.median(x["mem"] for x in r)
        if first is None:
            first = (ns, ins)
        print(f"{v:<28}{ns:>12.2f}{ins:>11.1f}{cyc:>10.1f}{mem:>9.1f}"
              f"{first[0] / ns:>8.2f}{first[1] / ins if ins else 0:>9.2f}  {r[0]['checksum']}")


if __name__ == "__main__":
    main()
