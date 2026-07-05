"""Frontier-wave (DETOUR-style) zero-cell ladder: apply Erik's zero-and-
reexpand technique to an EXISTING found scheme (not from-naive), and explore
ALL re-inclusion orderings of the zeroed cells SIMULTANEOUSLY as a beam of
candidates, rather than committing to one fixed order (the 4x4 ladder.py did
the latter). At each depth, every surviving frontier member is branched over
every remaining zeroed cell; all branches get a short independent re-search;
the top-B by (rank, bits) survive to the next depth. This is the "frontier
wave" / "explore all paths at once" idea, as opposed to Dijkstra/UCS-style
single-path expansion.

Pipeline per starting scheme:
  1. Z-restrict the scheme to the given zeroed-cell mask (w &= ~Z, drop
     zero/dup terms) -- this is the SAME normalization partial_gen.py's
     xor_insert applies, done once in Python to build the seed.
  2. FLOOR: a short walker re-search from that Z-restricted seed, hunting a
     genuinely lower rank for the reduced target (not just the mechanical
     restriction's rank).
  3. FRONTIER WAVE: beam of B candidates, branching over remaining cells,
     re-searching each branch briefly, keeping the top-B every depth, until
     every zeroed cell is restored and the full tensor is back.

Every candidate at every depth is exact-validated in Python against the
(possibly still-partial) target via recon()/T() from metaflip_proto2.

Usage: python3 detour_ladder.py <n> <m> <p> <zcells csv> <beam_width>
         <budget_per_branch_s> <max_concurrent> <schemefile> [schemefile...]
"""
import glob
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "benchmarks", "matmul", "metaflip"))

import partial_gen  # noqa: E402
from metaflip_proto2 import T, recon  # noqa: E402


def read_scheme(path):
    import re
    terms = []
    us, vs, ws = {}, {}, {}
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("R "):
            terms.append(tuple(int(x) for x in ln.split()[1:]))
        elif ln.startswith(("us[", "vs[", "ws[")):
            m = re.match(r"(us|vs|ws)\[(\d+)\] = (\d+)", ln)
            {"us": us, "vs": vs, "ws": ws}[m.group(1)][int(m.group(2))] = int(m.group(3))
        elif len(ln.split()) == 3:
            terms.append(tuple(int(x) for x in ln.split()))
    if us:
        terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    return terms


def write_seed(S, path):
    with open(path, "w") as f:
        for r, (u, v, w) in enumerate(sorted(S)):
            f.write(f"us[{r}] = {u}\nvs[{r}] = {v}\nws[{r}] = {w}\n")


def z_restrict(terms, zmask, cb):
    """Mechanical Z-normalization: w &= ~Z, drop zero/dup terms — exactly
    what partial_gen.py's xor_insert does to every inserted term."""
    notz = ((1 << cb) - 1) & ~zmask
    acc = {}
    for u, v, w in terms:
        w2 = w & notz
        if u and v and w2:
            key = (u, v, w2)
            acc[key] = acc.get(key, 0) ^ 1
    return set(k for k, x in acc.items() if x)


def add_naive_cell(S, cell, n, m, p, new_zmask):
    """S + the naive terms computing `cell` (an (i,k) output position),
    XOR-reduced and w-normalized against the shrunk zmask."""
    i, k = divmod(cell, p)
    cb = n * p
    notz = ((1 << cb) - 1) & ~new_zmask
    acc = {}
    def toggle(t):
        u, v, w = t
        w &= notz
        if u and v and w:
            key = (u, v, w)
            acc[key] = acc.get(key, 0) ^ 1
    for t in S:
        toggle(t)
    for j in range(m):
        toggle((1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k)))
    return set(k for k, x in acc.items() if x)


def partial_target(n, m, p, zmask):
    return set(t for t in T(n, m, p) if not ((zmask >> t[2]) & 1))


def partial_ok(S, n, m, p, zmask):
    got = set(t for t in recon(S, n, m, p) if not ((zmask >> t[2]) & 1))
    return got == partial_target(n, m, p, zmask)


def bits_of(S):
    return sum(bin(u).count("1") + bin(v).count("1") + bin(w).count("1") for u, v, w in S)


def compile_walker(n, m, p, zmask, seed_terms, workdir, tag):
    seed_path = os.path.join(workdir, f"seed_{tag}.txt")
    write_seed(seed_terms, seed_path)
    src_path = os.path.join(workdir, f"w_{tag}.w")
    bin_path = os.path.join(workdir, f"w_{tag}")
    with open(src_path, "w") as f:
        f.write(partial_gen.gen(n, m, p, 999999, zmask=zmask, seed=seed_path))
    # bin/tungsten build races itself across concurrent sessions on this repo
    # (documented, recurring): a torn read of the compiler binary mid-rebuild
    # produces a nonsensical internal error unrelated to our source. Retry a
    # few times with a short backoff rather than treating it as a real bug.
    last_err = None
    for attempt in range(4):
        r = subprocess.run(["bin/tungsten", "-o", bin_path, src_path], cwd=ROOT,
                           capture_output=True, text=True, timeout=300)
        if r.returncode == 0 and os.path.exists(bin_path):
            return bin_path
        last_err = f"compile failed for {tag} (attempt {attempt+1}/4):\n{r.stdout}\n{r.stderr}"
        time.sleep(5 * (attempt + 1))
    raise RuntimeError(last_err)


def parse_blocks(text):
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


def run_branch(n, m, p, zmask, seed_terms, workdir, tag, budget, bases=(1, 2)):
    """Compile + run a short walker from seed_terms against the zmask target;
    return the best Python-exact-valid result (>= as good as the seed)."""
    assert partial_ok(seed_terms, n, m, p, zmask), f"{tag}: seed invalid for its own target"
    binp = compile_walker(n, m, p, zmask, seed_terms, workdir, tag)
    procs, outs = [], []
    for b in bases:
        outp = os.path.join(workdir, f"out_{tag}_b{b}.txt")
        fh = open(outp, "w")
        procs.append((subprocess.Popen([binp, str(b)], cwd=ROOT, stdout=fh,
                                       stderr=subprocess.STDOUT), fh))
        outs.append(outp)
    deadline = time.time() + budget
    for pr, fh in procs:
        try:
            pr.wait(timeout=max(0.5, deadline - time.time()))
        except subprocess.TimeoutExpired:
            pr.kill()
            pr.wait()
        fh.close()
    best = seed_terms
    for outp in outs:
        for S in parse_blocks(open(outp).read()):
            if len(S) < len(best) or (len(S) == len(best) and bits_of(S) < bits_of(best)):
                if partial_ok(S, n, m, p, zmask):
                    best = S
    return best


def run_pool(jobs, max_concurrent, run_one):
    """jobs: list of arg-tuples for run_one; returns results in the same order,
    running at most max_concurrent at a time via a thread pool (each job itself
    shells out to subprocesses, so this just bounds how many walker pairs are
    compiling/running concurrently)."""
    import concurrent.futures
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_concurrent) as ex:
        return list(ex.map(lambda a: run_one(*a), jobs))


def detour_ladder(n, m, p, zcells, scheme_terms, tag, workdir, beam_width,
                  budget, max_concurrent):
    cb = n * p
    zmask_full = sum(1 << c for c in zcells)
    seed0 = z_restrict(scheme_terms, zmask_full, cb)
    print(f"[{tag}] Z={sorted(zcells)} (n={n}) starting_rank={len(scheme_terms)} "
          f"z_restricted_rank={len(seed0)}", flush=True)
    assert partial_ok(seed0, n, m, p, zmask_full), f"{tag}: z-restriction itself invalid"

    floor = run_branch(n, m, p, zmask_full, seed0, workdir, f"{tag}_floor", budget,
                       bases=(11, 22))
    print(f"[{tag}] FLOOR: {len(seed0)} -> {len(floor)} (bits={bits_of(floor)})", flush=True)

    # frontier: list of (scheme, zmask_remaining, cells_restored_path)
    frontier = [(floor, zmask_full, ())]
    remaining0 = list(zcells)

    depth = 0
    while any(fz for _, fz, _ in frontier):
        depth += 1
        jobs = []
        job_meta = []
        for S, zm, path in frontier:
            rem = [c for c in remaining0 if (zm >> c) & 1]
            for cell in rem:
                new_zm = zm & ~(1 << cell)
                seed = add_naive_cell(S, cell, n, m, p, new_zm)
                bt = f"{tag}_d{depth}_{len(job_meta)}"
                jobs.append((n, m, p, new_zm, seed, workdir, bt, budget, (100 * depth + len(job_meta) + 1,)))
                job_meta.append((path + (cell,), new_zm))
        print(f"[{tag}] depth {depth}: {len(jobs)} branches over {len(frontier)} "
              f"frontier members", flush=True)
        results = run_pool(jobs, max_concurrent, run_branch)
        scored = sorted(zip(results, job_meta), key=lambda r: (len(r[0]), bits_of(r[0])))
        best_rank, best_bits = len(scored[0][0]), bits_of(scored[0][0])
        print(f"[{tag}] depth {depth} best: rank={best_rank} bits={best_bits} "
              f"path={scored[0][1][0]}", flush=True)
        frontier = [(S, zm, path) for S, (path, zm) in scored[:beam_width]]

    finals = [(S, path) for S, zm, path in frontier]
    finals.sort(key=lambda x: (len(x[0]), bits_of(x[0])))
    best_final, best_path = finals[0]
    full_valid = recon(best_final, n, m, p) == T(n, m, p)
    print(f"[{tag}] FINAL: rank={len(best_final)} bits={bits_of(best_final)} "
          f"exact_valid={full_valid} order={best_path}", flush=True)
    if full_valid:
        out_path = os.path.join(workdir, f"FINAL_{tag}_rank{len(best_final)}.txt")
        write_seed(best_final, out_path)
        print(f"[{tag}] saved {out_path}", flush=True)
    return best_final, full_valid


def main():
    n, m, p = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    zcells = [int(x) for x in sys.argv[4].split(",")]
    beam_width = int(sys.argv[5])
    budget = int(sys.argv[6])
    max_concurrent = int(sys.argv[7])
    schemefiles = sys.argv[8:]

    base_workdir = os.path.join(HERE, "runs", "detour_ladder")
    os.makedirs(base_workdir, exist_ok=True)

    for sf in schemefiles:
        tag = os.path.basename(sf).replace(".txt", "").replace(".", "_")
        workdir = os.path.join(base_workdir, tag)
        os.makedirs(workdir, exist_ok=True)
        terms = read_scheme(sf)
        assert recon(set(terms), n, m, p) == T(n, m, p), f"{sf}: input scheme invalid"
        detour_ladder(n, m, p, zcells, terms, tag, workdir, beam_width, budget, max_concurrent)


if __name__ == "__main__":
    main()
