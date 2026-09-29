"""Real guarded 310 s runs of the PASSING starts of one entry (the ones the primed cache copied from the official run), compared with the official rows.

usage: full310.py lift|ramp|shc [--workers 2] [--seeds a:b]
Runs tasks/myo_soccer_ng.py on every start whose official run held 300 s, saves the rows to scratchpad/blowup/evals/full310-<entry>.json (resumable: rows already saved
are kept) and prints identity against the official rows and the guard / telemetry totals. The arena state is not touched."""
import argparse, glob, json, os, sys, time
import multiprocessing as mp

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
ENTRIES = {"lift": ("soccer5-lift", "params/myo_soccer_single_leg_310_lift.txt"), "ramp": ("soccer6-i", "params/myo_soccer_single_leg_310_ramp.txt"),
           "shc": ("soccer6-p", "params/myo_soccer_single_leg_310_shc.txt")}
BASE = ("bal1_raw", "bal1_300", "bal_l_tot", "bal_r_tot", "stand_time", "fallen", "t_fall", "pelvis_min", "act_reg", "pain_sum", "time", "up_time", "single_l", "single_r", "l_load_min")


def run(job):
    import arena
    return job["seed"], arena.rollout((job["trial"], job["params"], job["controller"], "myo_soccer_ng", job["seed"]))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("entry"); ap.add_argument("--workers", type=int, default=2); ap.add_argument("--seeds")
    a = ap.parse_args()
    import arena
    trial = arena.load_json(arena.TRIALS, {})["soccer_single_leg_310_40_ng"]
    tag, pfile = ENTRIES[a.entry]
    O = json.load(open(sorted(glob.glob(os.path.join(HERE, "scratchpad", "soccer4", "evals", f"bal1_300-{tag}-*.json")))[-1]))
    passing = [s for s, r in zip(O["seeds"], O["rows"]) if r.get("bal1_300") == 1.0]
    if a.seeds:
        lo, hi = a.seeds.split(":"); passing = [s for s in passing if int(lo) <= s < int(hi)]
    out_path = os.path.join(HERE, "scratchpad", "blowup", "evals", f"full310-{a.entry}.json")
    done = json.load(open(out_path)) if os.path.exists(out_path) else {}
    todo = [s for s in passing if str(s) not in done]
    params = arena.read_params(os.path.join(HERE, pfile)); ctl = os.path.join(HERE, "bin", "challengers", tag)
    jobs = [{"seed": s, "trial": trial, "params": params, "controller": ctl} for s in todo]
    t0 = time.time()
    print(f"{a.entry}: {len(passing)} passing official starts, {len(done)} already done, running {len(todo)}", flush=True)
    with mp.get_context("spawn").Pool(a.workers) as pool:
        for s, row in pool.imap_unordered(run, jobs, chunksize=1):
            done[str(s)] = row
            json.dump(done, open(out_path + ".tmp", "w")); os.replace(out_path + ".tmp", out_path)
            o = O["rows"][O["seeds"].index(s)]
            bad = [(k, row.get(k), o.get(k)) for k in BASE if row.get(k) != o.get(k)]
            print(f"  seed {s}: events {row.get('nan_events')} identical-to-official {not bad} {bad[:2] if row.get('nan_events') in (0, 0.0) else ''} ({time.time() - t0:.0f} s, {len(done)}/{len(passing)})", flush=True)
    same = sum(1 for s in passing if not [k for k in BASE if done[str(s)].get(k) != O['rows'][O['seeds'].index(s)].get(k)])
    ev = sum(int(done[str(s)].get("nan_events") or 0) for s in passing)
    st = sum(float(done[str(s)].get("time") or 0) for s in passing)
    print(f"{a.entry}: {len(passing)} real guarded runs of passing starts; identical to the official row in every base metric: {same}; NaN events {ev} in {st:.0f} start-seconds")
