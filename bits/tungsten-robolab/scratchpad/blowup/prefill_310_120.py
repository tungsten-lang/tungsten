"""Fill the rollout cache of soccer_single_leg_310_120_ng for one entry on a seed range, so that two or more of these processes can share the workers and the arena
`seed` / `eval` command afterwards finds every rollout cached (arena_ng.cached_rollout: same key, same row).

usage: prefill_310_120.py lift|ramp|shc --seeds a:b [--workers 2]"""
import argparse, os, sys, time
import multiprocessing as mp

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "blowup"))
ENTRIES = {"lift": ("soccer5-lift", "params/myo_soccer_single_leg_310_lift.txt"), "ramp": ("soccer6-i", "params/myo_soccer_single_leg_310_ramp.txt"),
           "shc": ("soccer6-p", "params/myo_soccer_single_leg_310_shc.txt")}

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("entry"); ap.add_argument("--seeds", required=True); ap.add_argument("--workers", type=int, default=2)
    a = ap.parse_args()
    import arena, arena_ng
    trial = arena.load_json(arena.TRIALS, {})["soccer_single_leg_310_120_ng"]
    tag, pfile = ENTRIES[a.entry]
    lo, hi = a.seeds.split(":")
    seeds = [s for s in trial["seeds"] if int(lo) <= s < int(hi)]
    params = arena.read_params(os.path.join(HERE, pfile)); ctl = os.path.join(HERE, "bin", "challengers", tag)
    jobs = [(trial, params, ctl, "myo_soccer_ng", s) for s in seeds]
    t0 = time.time()
    n = 0
    with mp.get_context("spawn").Pool(a.workers) as pool:
        for row in pool.imap(arena_ng.cached_rollout, jobs, chunksize=1):
            n += 1
            print(f"{n}/{len(jobs)} bal1_300 {row.get('bal1_300')} bal1_raw {row.get('bal1_raw')} events {row.get('nan_events')} ({time.time() - t0:.0f} s)", flush=True)
    print("done", a.entry, a.seeds)
