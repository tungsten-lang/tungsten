"""Overnight orchestrator: runs the CPU cal2zone fleet (18 walkers) + GPU
cal2zone relay (same schedule, ported to a GPU thread, first-found selection
not best-of-N -- see flipgraph_gpu_cal2zone.w's header for why) for exactly
2 hours on each of 3x3x3, 4x4x4, 5x5x5, 6x6x6 in sequence, fully unattended.
Each stage gets its own log directory so results can be plotted after the
fact without cross-contamination.

Usage: python3 overnight_orchestrator.py
"""
import glob
import os
import subprocess
import sys
import time

METAFLIP = "/Users/erik/tungsten/benchmarks/matmul/metaflip"
RELAY = f"{METAFLIP}/runs"
CAMPAIGN = f"{METAFLIP}/bin"
RECORDS = f"{METAFLIP}/records"
COORDINATOR = f"{METAFLIP}/relay_coordinator.py"
GPU_BIN = f"{CAMPAIGN}/flipgraph_gpu_cal2zone"
NWALKERS = 18
SECONDS_PER_STAGE = 7200  # 2 hours

STAGES = [
    (3, 3, 3, 23),
    (4, 4, 4, 47),
    (5, 5, 5, 93),
    (6, 6, 6, 153),
]


def log(f, msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    f.write(line + "\n")
    f.flush()


def kill_stage(binary_name):
    subprocess.run(f"pkill -f {binary_name}", shell=True)
    subprocess.run("pkill -f relay_coordinator.py", shell=True)
    subprocess.run(f"pkill -f {os.path.basename(GPU_BIN)}", shell=True)
    time.sleep(2)


def run_stage(n, m, p, target, masterlog):
    tag = f"{n}{m}{p}"
    stagedir = f"{RELAY}/run_{tag}"
    recorddir = f"{RECORDS}/{tag}"
    os.makedirs(stagedir, exist_ok=True)
    os.makedirs(recorddir, exist_ok=True)

    naive_path = f"{RELAY}/naive_{tag}.txt"
    canonical = f"{stagedir}/current_best.txt"
    gpu_best = f"{stagedir}/gpu_best.txt"
    subprocess.run(["cp", naive_path, canonical])
    for f in glob.glob(f"{stagedir}/cpu_*.txt") + [gpu_best]:
        try:
            os.remove(f)
        except FileNotFoundError:
            pass

    log(masterlog, f"=== STAGE {tag} (target={target}) starting, stagedir={stagedir} ===")

    binary = f"{CAMPAIGN}/cal2zone_{tag}"
    procs = []
    for i in range(1, NWALKERS + 1):
        dump = f"{stagedir}/cpu_{i}.txt"
        logf = open(f"{stagedir}/cpu_{i}.log", "w")
        seed = str(i * 97 + 13)
        p_ = subprocess.Popen([binary, seed, dump, f"{recorddir}/cpu{i}"], stdout=logf, stderr=subprocess.STDOUT)
        procs.append(p_)
    log(masterlog, f"launched {NWALKERS} CPU walkers, recording rank<={target} hits to {recorddir}")

    coord_logf = open(f"{stagedir}/coordinator.log", "w")
    coord_proc = subprocess.Popen(
        ["python3", COORDINATOR, canonical, str(n * m * p), f"{stagedir}/cpu_*.txt", gpu_best],
        stdout=coord_logf, stderr=subprocess.STDOUT
    )
    log(masterlog, "launched coordinator")

    time.sleep(2)

    gpu_logf = open(f"{stagedir}/gpu.log", "w")
    gpu_proc = subprocess.Popen(
        [GPU_BIN, canonical, gpu_best, str(n), str(m), str(p), f"{recorddir}/gpu", str(target)],
        stdout=gpu_logf, stderr=subprocess.STDOUT, cwd="/Users/erik/tungsten"
    )
    log(masterlog, "launched GPU cal2zone relay")

    stage_start = time.time()
    while time.time() - stage_start < SECONDS_PER_STAGE:
        time.sleep(60)
        elapsed = time.time() - stage_start
        best_line = "?"
        try:
            with open(canonical) as cf:
                best_line = cf.readline().strip()
        except FileNotFoundError:
            pass
        log(masterlog, f"  [{tag}] elapsed={elapsed:.0f}s / {SECONDS_PER_STAGE}s, current_best_rank={best_line}")

    log(masterlog, f"=== STAGE {tag} time box reached, stopping ===")
    kill_stage(f"cal2zone_{tag}")
    with open(f"{stagedir}/current_best.txt") as cf:
        final_best = cf.readline().strip()
    log(masterlog, f"=== STAGE {tag} DONE, final best rank = {final_best} (naive={n*m*p}, target={target}) ===")


def main():
    os.makedirs(RELAY, exist_ok=True)
    with open(f"{RELAY}/overnight_master.log", "w") as masterlog:
        log(masterlog, f"overnight orchestrator starting, {len(STAGES)} stages x {SECONDS_PER_STAGE}s")
        for n, m, p, target in STAGES:
            run_stage(n, m, p, target, masterlog)
        log(masterlog, "ALL STAGES DONE")
        with open(f"{RELAY}/ALL_DONE", "w") as marker:
            marker.write("done\n")


if __name__ == "__main__":
    main()
