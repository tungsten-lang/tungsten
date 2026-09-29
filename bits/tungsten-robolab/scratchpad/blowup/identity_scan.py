"""Official-vs-guarded identity at scale: run the OFFICIAL task (tasks/myo_soccer.py) on the seeds of a trial for one entry and compare every base metric with the
guarded rows of the same entry (scratchpad/blowup/evals/*.json, newest file for the entry).

usage: identity_scan.py hold20|310 lift|ramp|shc [--workers 2] [--seeds a:b]
Writes scratchpad/blowup/evals/official-<trial>-<entry>.json (official rows) and prints, over the starts whose guarded run had no NaN event: how many rows are
identical in every base metric, and the differences."""
import argparse, glob, json, os, sys, time
import multiprocessing as mp

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "soccer4"))
ENTRY = {"lift": ("soccer5-lift", "params/myo_soccer_single_leg_310_lift.txt"), "ramp": ("soccer6-i", "params/myo_soccer_single_leg_310_ramp.txt"),
         "shc": ("soccer6-p", "params/myo_soccer_single_leg_310_shc.txt")}
BASE = ("bal1_raw", "bal1_300", "bal_l_tot", "bal_r_tot", "stand_time", "fallen", "t_fall", "pelvis_min", "act_reg", "pain_sum", "time", "up_time", "single_l", "single_r", "l_load_min")


def run(job):
    import arena
    trial = job["trial"]
    trial = dict(trial)
    row = arena.rollout((trial, job["params"], job["controller"], "myo_soccer", job["seed"]))
    return job["seed"], row


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("which"); ap.add_argument("entry"); ap.add_argument("--workers", type=int, default=2); ap.add_argument("--seeds")
    a = ap.parse_args()
    import arena
    name = "soccer_single_leg_310_40_ng" if a.which == "310" else "soccer_hold20_120_ng"
    trial = arena.load_json(arena.TRIALS, {})[name]
    tag, pfile = ENTRY[a.entry]
    metric = "bal1_300" if a.which == "310" else "hold20"
    guarded_file = sorted(glob.glob(os.path.join(HERE, "scratchpad", "blowup", "evals", f"{metric}-{tag}-*.json")))[-1]
    G = json.load(open(guarded_file))
    seeds = G["seeds"]
    if a.seeds:
        lo, hi = a.seeds.split(":"); seeds = [s for s in seeds if int(lo) <= s < int(hi)]
    params = arena.read_params(os.path.join(HERE, pfile))
    ctl = os.path.join(HERE, "bin", "challengers", tag)
    jobs = [{"trial": trial, "params": params, "controller": ctl, "seed": s} for s in seeds]
    t0 = time.time()
    out = {}
    with mp.get_context("spawn").Pool(a.workers) as pool:
        for s, row in pool.imap(run, jobs, chunksize=1):
            out[s] = row
    json.dump({"seeds": seeds, "rows": [out[s] for s in seeds]}, open(os.path.join(HERE, "scratchpad", "blowup", "evals", f"official-{a.which}-{a.entry}.json"), "w"))
    same = diff = skipped = 0
    for s in seeds:
        g = G["rows"][G["seeds"].index(s)]
        o = out[s]
        if (g.get("nan_events") or 0) > 0:
            skipped += 1
            print(f"  seed {s}: guarded run had {g.get('nan_events')} NaN events (first at {g.get('nan_first_t')}): official {[o.get(k) for k in ('bal1_raw', 'fallen', 't_fall')]} vs guarded {[g.get(k) for k in ('bal1_raw', 'fallen', 't_fall')]}")
            continue
        bad = [(k, o.get(k), g.get(k)) for k in BASE if o.get(k) != g.get(k)]
        if bad:
            diff += 1
            print(f"  seed {s}: DIFFERENT {bad[:4]}")
        else:
            same += 1
    print(f"{a.which} {a.entry}: {len(seeds)} starts in {time.time() - t0:.0f} s; guarded runs without a NaN event: {same + diff}; official row identical in all base metrics: {same}, different: {diff}; with events (compared separately): {skipped}")
