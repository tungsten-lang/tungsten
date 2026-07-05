"""Sweep the partial-tensor ladder (Erik's zero-seed + re-inclusion idea) over the
number of zeroed output cells, k = 1..max_k (of 16), for the 4x4 GF(2) matmul tensor.

Z_k is the first k cells of ONE fixed random permutation of the 16 output cells, so
Z_1 subset Z_2 subset ... subset Z_max_k -- a single consistent zeroing order, so the
k-sweep reads as "zero out more cells, watch the floor and the recovered final rank"
without Z-choice noise confounding the trend. Each k still gets its own independent
ladder run (own floor rung + own re-inclusion sequence in sorted(Z_k) order); k=12
does not reuse k=11's run.

Usage: python3 ladder_sweep.py [budget_per_rung=25] [max_k=12]
Writes runs/ladder_sweep/summary.txt (rewritten after every k, so it's readable
mid-sweep) and one workdir per k under runs/ladder_sweep/sweepk<k>/.
"""
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ladder

PERM_SEED = 4242
CB = 16


def main():
    budget = int(sys.argv[1]) if len(sys.argv) > 1 else 25
    max_k = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    perm = random.Random(PERM_SEED).sample(range(CB), CB)

    here = os.path.dirname(os.path.abspath(__file__))
    base_out = os.path.join(here, "runs", "ladder_sweep")
    os.makedirs(base_out, exist_ok=True)
    summary_path = os.path.join(base_out, "summary.txt")

    print(f"fixed permutation (seed {PERM_SEED}): {perm}", flush=True)
    print(f"budget={budget}s/rung, k=1..{max_k}", flush=True)

    results = []
    t0 = time.time()
    for k in range(1, max_k + 1):
        cells = sorted(perm[:k])
        tag = f"sweepk{k}"
        workdir = os.path.join(base_out, tag)
        os.makedirs(workdir, exist_ok=True)
        ladder.WORKDIR = workdir  # ladder.py reads this module global at call time

        print(f"\n########## k={k} cells={cells} ({time.time()-t0:.0f}s elapsed) ##########",
              flush=True)
        traj, final_scheme, valid = ladder.ladder(cells, tag, budget=budget)
        floor = traj[0][2]
        final_rank = len(final_scheme)
        results.append((k, cells, floor, final_rank, valid))

        with open(summary_path, "w") as f:
            f.write("k  floor  final_rank  valid  cells\n")
            for row in results:
                f.write(f"{row[0]:2d}  {row[2]:4d}  {row[3]:4d}  {str(row[4]):5s}  {row[1]}\n")
        print(f"[sweep] k={k} floor={floor} final_rank={final_rank} valid={valid} "
              f"({time.time()-t0:.0f}s total)", flush=True)
        if valid and final_rank <= 46:
            print(f"!!!!!! k={k}: FINAL RANK {final_rank} <= 46 — BEATS ALPHATENSOR !!!!!!",
                  flush=True)

    print(f"\nTOTAL SWEEP TIME: {time.time()-t0:.0f}s", flush=True)
    print(f"summary: {summary_path}", flush=True)


if __name__ == "__main__":
    main()
