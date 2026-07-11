"""7-hour <5,5,5> GF(2) record hunt — single format, sawtooth (cal2zone2)
schedule + GPU add-on, fully unattended.

Adapted from hunt_5_6_7.py (the canonical cal2zone hunt harness) to the specific
run Erik asked for:

  - ONE format: <5,5,5>, run for exactly 7 hours (25200s). World record = 93.
    The sampled rank-93 frontier is locally rigid under the tested moves, but
    this is not a global SAT lower bound (see FINDINGS.md 2026-07-11).
  - 18 CPU cal2zone2 walkers: work zone +1 band / 2.5B moves, wander +12/500M,
    sawtooth wrap at band 60. wthr rises by ONE whenever a descent lands within
    one band of the threshold. After FOUR full cycles with no descent a walker
    prints CYCLEOUT and exits; the supervisor rewrites its reseed file with a
    RANDOM one of the fleet's current best-rank schemes (ties) and relaunches it
    (reset-to-fleet-best). When a walker's LIVE rank reaches or passes the record
    (rank <= 93) the per-band move budget rises to 10B (record_bandq), so a walker
    on the frontier gets a much longer look at each band.
  - GPU add-on: flipgraph_gpu_cal2zone (local Metal, NW=4096 x STEPS=500000 =
    ~2.048B GPU moves/round; re-reads its seed file every round). It is pointed
    at a dedicated gpu_seed.txt that THIS orchestrator rotates: every ~5B GPU
    moves it swaps the GPU's seed to the next CPU walker that is TIED at the
    current-best rank (round-robin over the tied-best set). That single mechanism
    is both "reset the GPU every 5B moves" and "cycle through the current-best
    walkers when more than one is tied on the same rank." A generous seed that is
    always a valid current-best keeps the GPU's budget healthy (never starved).
  - Seed: NAIVE (rank 125) on first launch, read from each walker's own reseed
    file at startup; reset-to-fleet-best on CYCLEOUT thereafter. The 10B-per-band
    record budget arms once a walker reaches the record (rank <= 93) or beyond.
  - Fleet record log: a rank-93 result (== world record) is logged to
    RECORD_93_fleet.log + copied to records/<tag>_fleet/ ONLY when its total set
    bits are the least the whole fleet has produced so far this run (strictly
    below the density we already hold in the seed). A genuine beat (rank < 93 =
    a NEW world record) is always logged.
  - RSS watchdog kills any walker over 2GB (wide-mask boxed-bigint OOM lesson).

Usage: python3 hunt_555_9h.py [seconds=25200]
"""
import glob
import os
import random
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
METAFLIP = os.path.join(ROOT, "benchmarks", "matmul", "metaflip")
sys.path.insert(0, METAFLIP)
sys.path.insert(0, HERE)

from bucket_gen import gen as bucket_gen  # noqa: E402

# ---- run configuration ------------------------------------------------------
TAG = "555_7h"
N = M = P = 5
RECORD = 93                         # <5,5,5> world record (== equal-to-WR target)
NWALKERS = 18
CAP_MOVES = 50_000_000_000_000      # 5e13 — vast headroom over any 7h move count
RECORD_BANDQ = 10_000_000_000       # 10B moves/band while rank is at/past the record
RSS_LIMIT_KB = 2 * 1024 * 1024
TIEGAP = 20000
DEFAULT_SECONDS = 25200             # 7 hours
FASTFAIL_SECS = 12                  # a walker exiting sooner than this counts as a crash
FASTFAIL_MAX = 3                    # give up relaunching after this many consecutive crashes

# GPU relay geometry (from flipgraph_gpu_cal2zone.w: NW=4096, STEPS=500000)
GPU_MOVES_PER_ROUND = 4096 * 500000     # 2,048,000,000
GPU_RESET_MOVES = 5_000_000_000         # rotate the GPU seed every ~5B GPU moves

SEED_FILE = os.path.join(METAFLIP, "matmul_5x5_rank93_sparse_gf2.txt")


# ---- scheme IO (bit-identical to hunt_5_6_7.py) ------------------------------
def read_scheme(path):
    import re
    terms, us, vs, ws = [], {}, {}, {}
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("R "):
            terms.append(tuple(int(x) for x in ln.split()[1:]))
        elif ln.startswith(("us[", "vs[", "ws[")):
            mo = re.match(r"(us|vs|ws)\[(\d+)\] = (\d+)", ln)
            {"us": us, "vs": vs, "ws": ws}[mo.group(1)][int(mo.group(2))] = int(mo.group(3))
    if us:
        terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    return terms


def naive_scheme(n, m, p):
    """The naive rank-(n*m*p) decomposition — one term per (i,j,k)."""
    return [(1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k))
            for i in range(n) for j in range(m) for k in range(p)]


def write_dump(terms, path):
    """Bare 'rank\\nu v w...' format — what the coordinator/GPU relay read/write."""
    with open(path, "w") as f:
        f.write(f"{len(terms)}\n")
        for u, v, w in terms:
            f.write(f"{u} {v} {w}\n")


def write_usvw_seed(terms, path):
    """'us[i] = ...' format — the ONLY format bucket_gen.py's seed loader reads."""
    with open(path, "w") as f:
        for i, (u, v, w) in enumerate(terms):
            f.write(f"us[{i}] = {u}\nvs[{i}] = {v}\nws[{i}] = {w}\n")


def scheme_bits(terms):
    """Total set bits (density) of a scheme = sum of popcounts over all masks."""
    return sum(bin(u).count("1") + bin(v).count("1") + bin(w).count("1")
               for u, v, w in terms)


def read_dump(path):
    """Parse a bare 'rank\\nu v w' dump. Returns (rank, terms) or (None, None)."""
    try:
        with open(path) as f:
            lines = f.read().splitlines()
        rank = int(lines[0])
        terms = []
        for ln in lines[1:1 + rank]:
            a = ln.split()
            terms.append((int(a[0]), int(a[1]), int(a[2])))
        if len(terms) != rank:
            return None, None
        return rank, terms
    except Exception:
        return None, None


def tail_has(path, needle, n=8):
    """True if any of the last n lines of a file contains needle."""
    try:
        with open(path) as f:
            return any(needle in ln for ln in f.readlines()[-n:])
    except Exception:
        return False


def gpu_round(gpu_log):
    """Latest completed GPU round from gpu.log ('round N/... ' lines)."""
    try:
        best = -1
        with open(gpu_log) as f:
            for ln in f:
                if ln.startswith("round "):
                    best = int(ln.split()[1].split("/")[0])
        return best
    except Exception:
        return -1


def log(f, msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    f.write(line + "\n")
    f.flush()


def kill_all(*names):
    for n in names:
        subprocess.run(["pkill", "-f", n], stderr=subprocess.DEVNULL)
    time.sleep(2)


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SECONDS
    stagedir = os.path.join(METAFLIP, "runs", f"hunt_{TAG}")
    recorddir = os.path.join(METAFLIP, "records", TAG)          # rank<=92 beats (walker/GPU)
    tiedir = os.path.join(METAFLIP, "records", f"{TAG}_ties")   # per-walker density-improving 93s
    fleetdir = os.path.join(METAFLIP, "records", f"{TAG}_fleet")  # fleet density-record 93s
    for d in (stagedir, recorddir, tiedir, fleetdir):
        os.makedirs(d, exist_ok=True)
    for f in glob.glob(os.path.join(stagedir, "*")):
        if os.path.isfile(f):
            os.remove(f)

    masterlog_path = os.path.join(stagedir, f"hunt_{TAG}_master.log")
    fleet_record_path = os.path.join(stagedir, "RECORD_93_fleet.log")

    kill_all(f"walker_{TAG}", "flipgraph_gpu_cal2zone", "relay_coordinator.py")

    with open(masterlog_path, "w") as masterlog:
        # ---- log locations, printed up front -------------------------------
        log(masterlog, f"=== <5,5,5> 7-HOUR HUNT — master log: {masterlog_path}")
        log(masterlog, f"=== fleet record log (rank-93 @ least density so far): {fleet_record_path}")
        log(masterlog, f"=== per-walker record dirs: beats->{recorddir}  ties->{tiedir}  fleet->{fleetdir}")

        # Seed from NAIVE: every walker starts at rank n*m*p (read from its own
        # reseed file) and descends. Work zone escalates +1 band / 2.5B moves;
        # after FOUR sawtooth cycles with no descent a walker prints CYCLEOUT and
        # exits — the supervisor then rewrites its reseed file with a RANDOM one of
        # the fleet's current best-rank schemes and relaunches it (reset-to-fleet-
        # best). The 10B-per-band record budget arms once rank reaches <= 93.
        terms = naive_scheme(N, M, P)
        seed_rank, seed_bits = len(terms), scheme_bits(terms)
        canonical = os.path.join(stagedir, "current_best.txt")
        gpu_seed = os.path.join(stagedir, "gpu_seed.txt")
        gpu_best = os.path.join(stagedir, "gpu_best.txt")
        write_dump(terms, canonical)
        write_dump(terms, gpu_seed)          # GPU's rotating seed — starts at naive
        log(masterlog, f"=== seed: NAIVE rank-{seed_rank} ({seed_bits} bits); "
                       f"record={RECORD}, recv={RECORD - 1}, 10B/band arms once rank<={RECORD}; "
                       f"reset->fleet-best after 4 cycles")

        # ---- build the cal2zone2 walker (--release --native --fast --lto) ----
        binpath = os.path.join(stagedir, f"walker_{TAG}")
        # band=1: START at band 1 so the walker actually traverses the WORK zone
        # (bands 1..wthr at 2.5B/band) before wandering — with the default band=10
        # (> wthr=7) the walker starts already in the wander zone and never uses
        # the work-zone quantum or the wthr calibration, making each sawtooth only
        # ~2.5B moves. At band=1 a full cycle is ~20B (17.5B work + 2.5B wander),
        # so a 4-cycle CYCLEOUT reset is ~80B moves per walker, as intended.
        src = bucket_gen(N, M, P, RECORD - 1, seed=None, cap=CAP_MOVES,
                         adaptive_esc="cal2zone2", band=1, thr0=7, world_record=RECORD,
                         tiegap=TIEGAP, record_bandq=RECORD_BANDQ, runtime_seed=True)
        srcpath = binpath + ".w"
        with open(srcpath, "w") as f:
            f.write(src)
        r = subprocess.run(["bin/tungsten", "-o", binpath, srcpath,
                            "--release", "--native", "--fast", "--lto"],
                           cwd=ROOT, capture_output=True, text=True, timeout=1200)
        if r.returncode != 0:
            log(masterlog, f"COMPILE FAILED:\n{r.stdout}\n{r.stderr}")
            return
        log(masterlog, "compiled cal2zone2 walker (2.5B work/band, 4-cycle reset-to-fleet-best, "
                       "wthr+1 within one band, 10B-at-record, runtime-seed; --release --native --fast --lto)")

        # ---- per-walker state + launch helpers -----------------------------
        def reseed_file(i):
            return os.path.join(stagedir, f"reseed_cpu{i}.txt")

        logfiles = {}

        def launch_walker(i, salt):
            # append across relaunches so the pre-CYCLEOUT history is preserved
            if i in logfiles:
                try:
                    logfiles[i].close()
                except Exception:
                    pass
            lf = open(os.path.join(stagedir, f"cpu_{i}.log"), "a")
            logfiles[i] = lf
            return subprocess.Popen(
                [binpath, str(i * 97 + 13 + salt * 100003),
                 os.path.join(stagedir, f"cpu_{i}.txt"),
                 os.path.join(recorddir, f"cpu{i}"),
                 os.path.join(tiedir, f"cpu{i}"), reseed_file(i)],
                stdout=lf, stderr=subprocess.STDOUT)

        def pick_tied_best():
            """A random scheme among the fleet's current best-rank dumps (ties)."""
            cur_rank, _ = read_dump(canonical)
            pool = []
            for cf in glob.glob(os.path.join(stagedir, "cpu_*.txt")) + [gpu_best]:
                rnk, trm = read_dump(cf)
                if trm and (cur_rank is None or rnk == cur_rank):
                    pool.append(trm)
            if pool:
                return random.choice(pool)
            _, ct = read_dump(canonical)          # fall back to the canonical best
            return ct

        # ---- launch 18 CPU walkers (each seeded from its naive reseed file) --
        procs = []
        launched_at = {}
        relaunches = {}
        fastfails = {}
        dead = set()
        for i in range(1, NWALKERS + 1):
            write_dump(terms, reseed_file(i))     # first launch: naive
            procs.append(launch_walker(i, 0))
            launched_at[i] = time.time()
            relaunches[i] = 0
            fastfails[i] = 0
        log(masterlog, f"launched {NWALKERS} CPU cal2zone2 walkers")

        # ---- coordinator (tracks global best) + GPU relay ------------------
        coord = subprocess.Popen(
            ["python3", os.path.join(METAFLIP, "relay_coordinator.py"), canonical,
             str(N * M * P), os.path.join(stagedir, "cpu_*.txt"), gpu_best],
            stdout=open(os.path.join(stagedir, "coordinator.log"), "w"),
            stderr=subprocess.STDOUT)
        time.sleep(2)
        gpu_log = os.path.join(stagedir, "gpu.log")
        gpu_bin = os.path.join(METAFLIP, "bin", "flipgraph_gpu_cal2zone")
        gpu_proc = subprocess.Popen(
            [gpu_bin, gpu_seed, gpu_best, str(N), str(M), str(P),
             os.path.join(recorddir, "gpu"), str(RECORD - 1)],
            stdout=open(gpu_log, "w"), stderr=subprocess.STDOUT, cwd=ROOT)
        log(masterlog, f"launched coordinator + GPU relay (seed rotates every "
                       f"{GPU_RESET_MOVES/1e9:.0f}B moves ~= {GPU_RESET_MOVES/GPU_MOVES_PER_ROUND:.1f} rounds)")

        # ---- supervise ------------------------------------------------------
        fleet_best = (seed_rank, seed_bits)   # (rank, bits) lexicographic; only strict improvements log
        logged_files = set()
        gpu_rotations = 0
        rot_idx = 0
        start = time.time()
        while time.time() - start < seconds:
            time.sleep(15)
            elapsed = time.time() - start

            # -- GPU seed rotation over the tied-best set, every ~5B GPU moves --
            rd = gpu_round(gpu_log)
            if rd >= 0:
                while rd * GPU_MOVES_PER_ROUND >= (gpu_rotations + 1) * GPU_RESET_MOVES:
                    gpu_rotations += 1
                    cur_rank, _ = read_dump(canonical)
                    tied = []
                    for cf in sorted(glob.glob(os.path.join(stagedir, "cpu_*.txt"))):
                        rnk, trm = read_dump(cf)
                        if rnk is not None and cur_rank is not None and rnk == cur_rank:
                            tied.append((cf, trm))
                    if len(tied) > 1:
                        rot_idx = (rot_idx + 1) % len(tied)
                        cf, trm = tied[rot_idx]
                        write_dump(trm, gpu_seed)
                        log(masterlog, f"  [gpu] {gpu_rotations*GPU_RESET_MOVES/1e9:.0f}B moves: "
                                       f"{len(tied)} walkers tied at rank={cur_rank}, "
                                       f"seed -> {os.path.basename(cf)} (#{rot_idx})")
                    else:
                        # <=1 tied at best: keep GPU on the canonical global best
                        cr, ct = read_dump(canonical)
                        if ct is not None:
                            write_dump(ct, gpu_seed)

            # -- fleet-level density gate on rank-93 ties ------------------------
            for tf in glob.glob(os.path.join(tiedir, "*.txt")) + glob.glob(os.path.join(recorddir, "*.txt")):
                if tf in logged_files:
                    continue
                rnk, trm = read_dump(tf)
                if rnk is None or rnk > RECORD:
                    continue
                bits = scheme_bits(trm)
                cand = (rnk, bits)
                if cand < fleet_best:                       # strictly sparser (or lower rank)
                    logged_files.add(tf)
                    prev = fleet_best
                    fleet_best = cand
                    kind = "NEW WORLD RECORD (rank<93!)" if rnk < RECORD else "rank-93 @ new fleet-min density"
                    with open(fleet_record_path, "a") as rl:
                        rl.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {kind}: "
                                 f"rank={rnk} bits={bits} src={os.path.basename(tf)}\n")
                    dst = os.path.join(fleetdir, f"rank{rnk}_bits{bits}_{os.path.basename(tf)}")
                    shutil.copy(tf, dst)
                    log(masterlog, f"  *** FLEET RECORD: {kind} rank={rnk} bits={bits} "
                                   f"(prev {prev[0]}/{prev[1]}b) -> {os.path.basename(dst)}")
                else:
                    logged_files.add(tf)   # seen but not a fleet improvement

            # -- RSS watchdog + reset-to-fleet-best relaunch ---------------------
            alive = 0
            for idx in range(1, NWALKERS + 1):
                pr = procs[idx - 1]
                if pr.poll() is None:
                    alive += 1
                    try:
                        rss = int(subprocess.run(["ps", "-o", "rss=", "-p", str(pr.pid)],
                                                 capture_output=True, text=True).stdout.strip() or 0)
                        if rss > RSS_LIMIT_KB:
                            log(masterlog, f"RSS watchdog killing walker {idx} pid {pr.pid} at {rss}KB")
                            pr.kill()
                    except Exception:
                        pass
                elif idx not in dead:
                    # walker exited (CYCLEOUT after 4 cycles, or a crash) — reseed
                    # from a random fleet-best and relaunch, unless it is crash-looping
                    ran = time.time() - launched_at[idx]
                    cyc = tail_has(os.path.join(stagedir, f"cpu_{idx}.log"), "CYCLEOUT")
                    fastfails[idx] = fastfails[idx] + 1 if ran < FASTFAIL_SECS else 0
                    if fastfails[idx] >= FASTFAIL_MAX:
                        dead.add(idx)
                        log(masterlog, f"  [reset] walker {idx} exited {FASTFAIL_MAX}x within "
                                       f"{FASTFAIL_SECS}s — leaving it down")
                        continue
                    trm = pick_tied_best()
                    if trm:
                        write_dump(trm, reseed_file(idx))
                    relaunches[idx] += 1
                    procs[idx - 1] = launch_walker(idx, relaunches[idx])
                    launched_at[idx] = time.time()
                    alive += 1
                    log(masterlog, f"  [reset] walker {idx} {'CYCLEOUT' if cyc else 'exit'} -> "
                                   f"reseed from fleet-best rank {len(trm) if trm else '?'} "
                                   f"(relaunch #{relaunches[idx]})")
            if int(elapsed) % 120 < 15:
                best = "?"
                try:
                    best = open(canonical).readline().strip()
                except FileNotFoundError:
                    pass
                beats = len(glob.glob(os.path.join(recorddir, "*.txt")))
                ties = len(glob.glob(os.path.join(tiedir, "*.txt")))
                log(masterlog, f"  [{TAG}] elapsed={elapsed:.0f}s/{seconds}s alive={alive}/{NWALKERS} "
                               f"best_rank={best} fleet_best={fleet_best} beats={beats} ties={ties} "
                               f"gpu_round={rd} rot={gpu_rotations} resets={sum(relaunches.values())} down={len(dead)}")

        # ---- teardown -------------------------------------------------------
        log(masterlog, "=== 7h time box reached, stopping ===")
        for pr in procs:
            pr.kill()
        coord.kill()
        gpu_proc.kill()
        time.sleep(2)
        try:
            final_best = open(canonical).readline().strip()
        except FileNotFoundError:
            final_best = "?"
        beats = len(glob.glob(os.path.join(recorddir, "*.txt")))
        ties = len(glob.glob(os.path.join(tiedir, "*.txt")))
        log(masterlog, f"=== DONE: final_best_rank={final_best} fleet_best_density={fleet_best} "
                       f"(seed was rank {seed_rank} @ {seed_bits} bits) beats={beats} ties={ties} ===")
        with open(os.path.join(stagedir, "HUNT_DONE"), "w") as marker:
            marker.write("done\n")


if __name__ == "__main__":
    main()
