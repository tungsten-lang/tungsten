"""Zero-seeded partial-tensor + re-inclusion ladder for 4x4 GF(2) matmul tensor rank.

Idea (Erik): delete a subset Z of the 16 output cells of C from the matmul tensor,
flip-walk the reduced target well below 47, then re-include the zeroed cells one at
a time (adding the 4 naive terms that compute the restored cell) and re-squeeze.
Track the rank trajectory; a final full-tensor rank <= 46 would beat AlphaTensor.

Every accepted scheme is exact-validated IN PYTHON against the partial target:
recon(S) restricted to non-Z output cells must equal T restricted to non-Z cells.
(recon computes the trilinear form symbolically, so the zmask=0 final check is an
exhaustive proof, not a sampling test.)

Usage (from anywhere; subprocesses run from the repo root):
  python3 ladder.py gate0            # sanity: zmask=0 walker descends 64 -> ~low 50s in 60s
  python3 ladder.py gate1            # sanity: |Z|=4 partial naive seed is 48 terms, verify=1
  python3 ladder.py corners [budget] # ladder with Z = 4 corners of C
  python3 ladder.py random  [budget] # ladder with a random 4-cell Z (seeded RNG)
Env: LADDER_WORKDIR sets the scratch directory for generated sources/binaries/logs.
"""
import os
import random
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "benchmarks", "matmul", "metaflip"))

import partial_gen
from metaflip_proto2 import T, recon

N = M = P = 4
CB = N * P
WORKDIR = os.environ.get("LADDER_WORKDIR") or tempfile.mkdtemp(prefix="ladder-")
os.makedirs(WORKDIR, exist_ok=True)


def partial_target(zmask):
    return set(t for t in T(N, M, P) if not ((zmask >> t[2]) & 1))


def partial_ok(S, zmask):
    """Exact validation: S computes every C cell outside Z; Z cells are don't-care."""
    got = set(t for t in recon(S, N, M, P) if not ((zmask >> t[2]) & 1))
    return got == partial_target(zmask)


def naive_partial(zmask):
    return set((1 << (i * M + j), 1 << (j * P + k), 1 << (i * P + k))
               for i in range(N) for j in range(M) for k in range(P)
               if not ((zmask >> (i * P + k)) & 1))


def add_naive_cell(S, cell, new_zmask):
    """Previous rung's scheme + the 4 naive terms computing `cell`, XOR-reduced and
    w-normalized against the new (smaller) zmask."""
    i, k = divmod(cell, P)
    acc = {}
    def toggle(t):
        u, v, w = t
        w &= ((1 << CB) - 1) & ~new_zmask
        if u and v and w:
            key = (u, v, w)
            acc[key] = acc.get(key, 0) ^ 1
    for t in S:
        toggle(t)
    for j in range(M):
        toggle((1 << (i * M + j), 1 << (j * P + k), 1 << (i * P + k)))
    return set(key for key, x in acc.items() if x)


def write_seed(S, path):
    with open(path, "w") as f:
        for r, (u, v, w) in enumerate(sorted(S)):
            f.write(f"us[{r}] = {u}\nvs[{r}] = {v}\nws[{r}] = {w}\n")


def compile_walker(zmask, seed_path, tag):
    src = os.path.join(WORKDIR, f"walker_{tag}.w")
    binp = os.path.join(WORKDIR, f"walker_{tag}")
    with open(src, "w") as f:
        f.write(partial_gen.gen(N, M, P, 999, zmask=zmask, seed=seed_path))
    r = subprocess.run(["bin/tungsten", "-o", binp, src], cwd=ROOT,
                       capture_output=True, text=True, timeout=600)
    if r.returncode != 0 or not os.path.exists(binp):
        raise RuntimeError(f"compile failed for {tag}:\n{r.stdout}\n{r.stderr}")
    return binp


def parse_blocks(text):
    """All R-dump blocks (FOUND and DONE) in a walker's stdout, as sets of triples."""
    blocks, cur = [], None
    for line in text.splitlines():
        if line.startswith("R "):
            parts = line.split()
            if cur is None:
                cur = []
            cur.append((int(parts[1]), int(parts[2]), int(parts[3])))
        elif cur is not None:
            blocks.append(set(cur))
            cur = None
    if cur is not None:
        blocks.append(set(cur))
    return blocks


def run_walkers(binp, tag, budget, bases=(1, 2)):
    """Run len(bases) walkers concurrently for `budget` seconds, kill, return stdouts."""
    procs, files = [], []
    for b in bases:
        out = os.path.join(WORKDIR, f"out_{tag}_b{b}.txt")
        fh = open(out, "w")
        procs.append((subprocess.Popen([binp, str(b)], cwd=ROOT, stdout=fh,
                                       stderr=subprocess.STDOUT), fh))
        files.append(out)
    deadline = time.time() + budget
    for pr, fh in procs:
        try:
            pr.wait(timeout=max(0.5, deadline - time.time()))
        except subprocess.TimeoutExpired:
            pr.kill()
            pr.wait()
        fh.close()
    return [open(f).read() for f in files]


def run_rung(zmask, seed_terms, tag, budget, bases=(1, 2)):
    """One rung: compile a zmask walker (seeded if seed_terms), run walkers, return
    the best Python-exact-valid scheme (falling back to the seed itself)."""
    seed_path = None
    if seed_terms is not None:
        assert partial_ok(seed_terms, zmask), f"rung {tag}: seed is INVALID for its target"
        seed_path = os.path.join(WORKDIR, f"seed_{tag}.txt")
        write_seed(seed_terms, seed_path)
    binp = compile_walker(zmask, seed_path, tag)
    outs = run_walkers(binp, tag, budget, bases)
    cands = [b for out in outs for b in parse_blocks(out)]
    best, checked, invalid = seed_terms, 0, 0
    for S in cands:
        checked += 1
        if best is not None and len(S) >= len(best):
            continue
        if partial_ok(S, zmask):
            best = S
        else:
            invalid += 1
    if best is None:  # rung 0 unseeded and no dump improved on the naive partial seed
        best = naive_partial(zmask)
        assert partial_ok(best, zmask)
    print(f"[rung {tag}] zmask={zmask:#06x} seed={'-' if seed_terms is None else len(seed_terms)} "
          f"dumps={checked} invalid_dumps={invalid} best_valid_rank={len(best)}", flush=True)
    return best


def ladder(z_cells, tag, budget=90):
    zmask = sum(1 << c for c in z_cells)
    print(f"=== LADDER {tag}: Z cells {sorted(z_cells)} zmask={zmask:#06x} budget={budget}s/rung ===",
          flush=True)
    traj = []
    cur = run_rung(zmask, None, f"{tag}_r0", budget, bases=(11, 22))
    traj.append(("floor", sorted(z_cells), len(cur)))
    for step, cell in enumerate(sorted(z_cells), 1):
        zmask &= ~(1 << cell)
        seed = add_naive_cell(cur, cell, zmask)
        cur = run_rung(zmask, seed, f"{tag}_r{step}", budget,
                       bases=(100 * step + 1, 100 * step + 2))
        traj.append((f"+cell{cell}", f"seed={len(seed)}", len(cur)))
    assert zmask == 0
    full_valid = recon(cur, N, M, P) == T(N, M, P)
    print(f"=== LADDER {tag} trajectory ===", flush=True)
    for row in traj:
        print(f"  {row}", flush=True)
    print(f"=== LADDER {tag} FINAL full-tensor rank={len(cur)} exact_valid={full_valid} ===", flush=True)
    if full_valid and len(cur) <= 46:
        print("!!!!!! RANK <= 46 — BEATS ALPHATENSOR (exact symbolic verification passed) !!!!!!",
              flush=True)
        write_seed(cur, os.path.join(WORKDIR, f"RECORD_{tag}_rank{len(cur)}.txt"))
    return traj, cur, full_valid


def gate0(budget=60):
    """zmask=0 walker must behave like the stock rect walker: 64 -> ~low 50s quickly."""
    binp = compile_walker(0, None, "gate0")
    out = run_walkers(binp, "gate0", budget, bases=(1,))[0]
    first = out.splitlines()[0] if out else "(no output)"
    bests = [len(b) for b in parse_blocks(out)]
    print(f"gate0: {first}")
    print(f"gate0: best rank seen in {budget}s = {min(bests) if bests else 'none'}")
    ok = first.strip() == "seed rank=64 verify=1" and bests and min(bests) <= 55
    print(f"gate0 {'PASS' if ok else 'FAIL'}")
    return ok


def gate1():
    """|Z|=4 (corners) partial naive seed must be 48 terms and verify=1 in the walker."""
    zmask = CORNERS_MASK
    py_ok = partial_ok(naive_partial(zmask), zmask)
    binp = compile_walker(zmask, None, "gate1")
    out = run_walkers(binp, "gate1", 5, bases=(1,))[0]
    first = out.splitlines()[0] if out else "(no output)"
    print(f"gate1: python naive-partial exact-valid={py_ok}; walker says: {first}")
    ok = py_ok and first.strip() == "seed rank=48 verify=1"
    print(f"gate1 {'PASS' if ok else 'FAIL'}")
    return ok


CORNERS = [0, 3, 12, 15]                      # C cells (0,0) (0,3) (3,0) (3,3)
CORNERS_MASK = sum(1 << c for c in CORNERS)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "corners"
    budget = int(sys.argv[2]) if len(sys.argv) > 2 else 90
    print(f"workdir: {WORKDIR}", flush=True)
    if cmd == "gate0":
        sys.exit(0 if gate0(budget if len(sys.argv) > 2 else 60) else 1)
    if cmd == "gate1":
        sys.exit(0 if gate1() else 1)
    if cmd == "corners":
        ladder(CORNERS, "corners", budget)
        return
    if cmd == "random":
        rng_seed = int(sys.argv[3]) if len(sys.argv) > 3 else 7
        cells = sorted(random.Random(rng_seed).sample(range(CB), 4))
        ladder(cells, f"random{rng_seed}", budget)
        return
    print(f"unknown command {cmd}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
