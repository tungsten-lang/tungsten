"""4-hour-per-format record hunt across <5,5,5>, <6,6,6>, <7,7,7> over GF(2),
run sequentially (18 CPU cores is this box's ceiling — three formats' worth
of CPU walkers can't run concurrently without starving each other).

Each stage:
  - 18 CPU cal2zone walkers (bucket_gen.py), seeded from the best scheme we
    hold for that format, world_record= the published record so every TIE is
    logged (not just improvements) with density, in addition to the existing
    beat-the-record dump path (recv = record-1).
  - GPU relay: 5x5 ONLY. The existing flipgraph_gpu_cal2zone kernel uses i32
    masks (max(AB,BB,CB) <= 32, i.e. n<=5 square) — verified by bisection
    2026-07-05 that 6x6 (36-bit masks) corrupts deterministically regardless
    of CAP/WPG tuning (see gpu_cal2zone_gen.py's guard assertion). Needs an
    i64/two-limb mask kernel rewrite before GPU can join 6x6/7x7 — out of
    scope for this run. 6x6/7x7 get CPU-only, full 18-walker strength.
  - relay_coordinator.py keeps one canonical current-best file per format.
  - RSS watchdog kills any walker over 2GB (past OOM lesson: wide (>=2^47)
    masks boxed as heap bigints through a boxed-ABI call leak unboundedly).

Seeds, honestly labeled:
  5x5: OUR sparsified 93 (matmul_5x5_rank93_sparse_gf2.txt) — our own asset.
  6x6: Moosbauer-Poole's published 153 (imported via seed_prep.py from their
       repo, search/seed_mp153.txt) — we hold no independent 6x6 find yet.
  7x7: naive (343) — no better asset exists on disk; the old "329" result
       from a prior campaign was never persisted to a scheme file.

Usage: python3 hunt_5_6_7.py [seconds_per_stage=14400]
"""
import glob
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
METAFLIP = os.path.join(ROOT, "benchmarks", "matmul", "metaflip")
SEARCH = os.path.join(ROOT, "benchmarks", "matmul", "search")
sys.path.insert(0, METAFLIP)
sys.path.insert(0, HERE)

from bucket_gen import gen as bucket_gen  # noqa: E402

NWALKERS = 18
CAP_MOVES = 50_000_000_000_000  # 5e13 — ~60x headroom over any realistic 4h move count
RSS_LIMIT_KB = 2 * 1024 * 1024
TIEGAP = 20000

STAGES = [
    dict(tag="555", n=5, m=5, p=5, record=93,
         seed=os.path.join(METAFLIP, "matmul_5x5_rank93_sparse_gf2.txt"),
         seed_label="our sparsified rank-93 (1724 bits)", gpu=True),
    dict(tag="666", n=6, m=6, p=6, record=153,
         seed=os.path.join(SEARCH, "seed_mp153.txt"),
         seed_label="Moosbauer-Poole published rank-153 (imported)", gpu=False),
    dict(tag="777", n=7, m=7, p=7, record=248,
         seed=None,  # naive — no better asset held
         seed_label="naive (343) — no independent 7x7 asset on disk", gpu=False),
]


def log(f, msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    f.write(line + "\n")
    f.flush()


def read_scheme(path):
    terms = []
    us, vs, ws = {}, {}, {}
    import re
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("R "):
            terms.append(tuple(int(x) for x in ln.split()[1:]))
        elif ln.startswith(("us[", "vs[", "ws[")):
            m = re.match(r"(us|vs|ws)\[(\d+)\] = (\d+)", ln)
            {"us": us, "vs": vs, "ws": ws}[m.group(1)][int(m.group(2))] = int(m.group(3))
    if us:
        terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    return terms


def naive_scheme(n, m, p):
    return [(1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k))
            for i in range(n) for j in range(m) for k in range(p)]


def write_dump(terms, path):
    """Bare 'rank\\nu v w...' format — what the coordinator/GPU relay read/write."""
    with open(path, "w") as f:
        f.write(f"{len(terms)}\n")
        for u, v, w in terms:
            f.write(f"{u} {v} {w}\n")


def write_usvw_seed(terms, path):
    """'us[i] = ...' format — the ONLY format bucket_gen.py's seed loader
    recognizes (it filters lines by startswith("us[","vs[","ws[") and treats
    anything else as a zero-term seed WITHOUT erroring — silently walks from
    rank 0. Never pass a write_dump()-format file to bucket_gen(seed=...)."""
    with open(path, "w") as f:
        for i, (u, v, w) in enumerate(terms):
            f.write(f"us[{i}] = {u}\nvs[{i}] = {v}\nws[{i}] = {w}\n")


def kill_all(*names):
    for n in names:
        subprocess.run(["pkill", "-f", n], stderr=subprocess.DEVNULL)
    time.sleep(2)


def run_stage(stage, seconds, masterlog):
    tag = stage["tag"]
    n, m, p, record = stage["n"], stage["m"], stage["p"], stage["record"]
    stagedir = os.path.join(METAFLIP, "runs", f"hunt_{tag}")
    recorddir = os.path.join(METAFLIP, "records", tag)
    tiedir = os.path.join(METAFLIP, "records", f"{tag}_ties")
    os.makedirs(stagedir, exist_ok=True)
    os.makedirs(recorddir, exist_ok=True)
    os.makedirs(tiedir, exist_ok=True)
    for f in glob.glob(os.path.join(stagedir, "*")):
        try:
            os.remove(f)
        except IsADirectoryError:
            pass

    terms = read_scheme(stage["seed"]) if stage["seed"] else naive_scheme(n, m, p)
    canonical = os.path.join(stagedir, "current_best.txt")
    write_dump(terms, canonical)
    usvw_seed = os.path.join(stagedir, "seed_usvw.txt")
    write_usvw_seed(terms, usvw_seed)
    log(masterlog, f"=== STAGE {tag}: seed={stage['seed_label']} rank={len(terms)} "
                    f"record={record} gpu={stage['gpu']} ===")

    binpath = os.path.join(stagedir, f"walker_{tag}")
    src = bucket_gen(n, m, p, record - 1, seed=usvw_seed, cap=CAP_MOVES,
                     adaptive_esc="cal2zone", workq=2_000_000_000, wstep=12,
                     wq=500_000_000, thr0=7, world_record=record, tiegap=TIEGAP)
    srcpath = binpath + ".w"
    with open(srcpath, "w") as f:
        f.write(src)
    r = subprocess.run(["bin/tungsten", "-o", binpath, srcpath], cwd=ROOT,
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        log(masterlog, f"COMPILE FAILED for {tag}:\n{r.stdout}\n{r.stderr}")
        return
    log(masterlog, f"compiled {tag} walker")

    procs = []
    for i in range(1, NWALKERS + 1):
        logf = open(os.path.join(stagedir, f"cpu_{i}.log"), "w")
        p_ = subprocess.Popen(
            [binpath, str(i * 97 + 13), os.path.join(stagedir, f"cpu_{i}.txt"),
             os.path.join(recorddir, f"cpu{i}"), os.path.join(tiedir, f"cpu{i}")],
            stdout=logf, stderr=subprocess.STDOUT)
        procs.append(p_)
    log(masterlog, f"launched {NWALKERS} CPU walkers")

    coord = None
    gpu_proc = None
    if stage["gpu"]:
        gpu_best = os.path.join(stagedir, "gpu_best.txt")
        coord = subprocess.Popen(
            ["python3", os.path.join(METAFLIP, "relay_coordinator.py"), canonical,
             str(n * m * p), os.path.join(stagedir, "cpu_*.txt"), gpu_best],
            stdout=open(os.path.join(stagedir, "coordinator.log"), "w"), stderr=subprocess.STDOUT)
        time.sleep(2)
        gpu_bin = os.path.join(METAFLIP, "bin", "flipgraph_gpu_cal2zone")
        gpu_proc = subprocess.Popen(
            [gpu_bin, canonical, gpu_best, str(n), str(m), str(p),
             os.path.join(recorddir, "gpu"), str(record - 1)],
            stdout=open(os.path.join(stagedir, "gpu.log"), "w"), stderr=subprocess.STDOUT, cwd=ROOT)
        log(masterlog, "launched coordinator + GPU relay")
    else:
        coord = subprocess.Popen(
            ["python3", os.path.join(METAFLIP, "relay_coordinator.py"), canonical,
             str(n * m * p), os.path.join(stagedir, "cpu_*.txt")],
            stdout=open(os.path.join(stagedir, "coordinator.log"), "w"), stderr=subprocess.STDOUT)
        log(masterlog, f"launched coordinator (no GPU — i32-mask kernel maxes at 32-bit "
                        f"masks, <{n},{m},{p}> needs {max(n*m,m*p,n*p)}-bit)")

    start = time.time()
    while time.time() - start < seconds:
        time.sleep(120)
        alive = 0
        for pr in procs:
            if pr.poll() is None:
                alive += 1
                try:
                    rss = int(subprocess.run(["ps", "-o", "rss=", "-p", str(pr.pid)],
                                             capture_output=True, text=True).stdout.strip() or 0)
                    if rss > RSS_LIMIT_KB:
                        log(masterlog, f"RSS watchdog killing pid {pr.pid} at {rss}KB")
                        pr.kill()
                except Exception:
                    pass
        try:
            best = open(canonical).readline().strip()
        except FileNotFoundError:
            best = "?"
        hits = len(glob.glob(os.path.join(recorddir, "*.txt")))
        ties = len(glob.glob(os.path.join(tiedir, "*.txt")))
        log(masterlog, f"  [{tag}] elapsed={time.time()-start:.0f}s/{seconds}s "
                        f"alive={alive}/{NWALKERS} best={best} beats={hits} ties={ties}")

    log(masterlog, f"=== STAGE {tag} time box reached, stopping ===")
    for pr in procs:
        pr.kill()
    if coord:
        coord.kill()
    if gpu_proc:
        gpu_proc.kill()
    time.sleep(2)
    try:
        final_best = open(canonical).readline().strip()
    except FileNotFoundError:
        final_best = "?"
    hits = len(glob.glob(os.path.join(recorddir, "*.txt")))
    ties = len(glob.glob(os.path.join(tiedir, "*.txt")))
    log(masterlog, f"=== STAGE {tag} DONE: final_best={final_best} "
                    f"(seed_rank={len(terms)}, record={record}) beats={hits} ties={ties} ===")


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 14400
    outdir = os.path.join(METAFLIP, "runs")
    os.makedirs(outdir, exist_ok=True)
    kill_all("walker_555", "walker_666", "walker_777", "flipgraph_gpu_cal2zone",
             "relay_coordinator.py")
    with open(os.path.join(outdir, "hunt_5_6_7_master.log"), "w") as masterlog:
        log(masterlog, f"hunt_5_6_7 starting: {len(STAGES)} stages x {seconds}s")
        for stage in STAGES:
            run_stage(stage, seconds, masterlog)
        log(masterlog, "ALL STAGES DONE")
        with open(os.path.join(outdir, "HUNT_ALL_DONE"), "w") as marker:
            marker.write("done\n")


if __name__ == "__main__":
    main()
