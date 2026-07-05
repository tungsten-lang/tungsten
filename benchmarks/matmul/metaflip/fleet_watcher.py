"""Watches an 18-walker CPU fleet (+ GPU relay) for the stop condition:
all walkers reach the known-best rank, OR total elapsed time hits 15x the
time it took the FIRST walker to reach it. Each walker was built with
stopat=<target>, so it self-exits (prints DONE) exactly when it gets there.

Usage: python3 fleet_watcher.py <logdir> <nwalkers> <walker_log_prefix> <walker_binary_name>
"""
import sys
import time
import subprocess


def count_done(logdir, nwalkers, prefix):
    done = []
    for i in range(1, nwalkers + 1):
        path = f"{logdir}/{prefix}_{i}.log"
        try:
            with open(path) as f:
                content = f.read()
            if "DONE" in content:
                done.append(i)
        except FileNotFoundError:
            pass
    return done


def main():
    logdir = sys.argv[1]
    nwalkers = int(sys.argv[2])
    prefix = sys.argv[3]
    binary_name = sys.argv[4]

    start_time = time.time()
    first_done_time = None
    first_done_walker = None

    with open(f"{logdir}/watcher.log", "w") as wf:
        def log(msg):
            wf.write(msg + "\n")
            wf.flush()
            print(msg, flush=True)

        log(f"watcher started, watching {nwalkers} walkers ({prefix}_N.log)")
        while True:
            done = count_done(logdir, nwalkers, prefix)
            if first_done_time is None and len(done) > 0:
                first_done_time = time.time()
                first_done_walker = done[0]
                time_to_first = first_done_time - start_time
                log(f"FIRST DONE: walker {first_done_walker} at t={time_to_first:.1f}s "
                    f"-> 15x cutoff = {15 * time_to_first:.1f}s total elapsed")
            if len(done) == nwalkers:
                log(f"ALL {nwalkers} WALKERS DONE at total_elapsed={time.time() - start_time:.1f}s")
                break
            if first_done_time is not None:
                time_to_first = first_done_time - start_time
                total_elapsed = time.time() - start_time
                cutoff = 15 * time_to_first
                if total_elapsed >= cutoff:
                    log(f"CUTOFF REACHED: total_elapsed={total_elapsed:.1f}s >= "
                        f"15x_first={cutoff:.1f}s, with {len(done)}/{nwalkers} done")
                    break
            time.sleep(30)

        log("STOPPING FLEET")
        subprocess.run(f"pkill -f {binary_name}", shell=True)
        subprocess.run("pkill -f relay_coordinator.py", shell=True)
        subprocess.run("pkill -f flipgraph_gpu_relay_bestof", shell=True)
        log("STOPPED")


if __name__ == "__main__":
    main()
