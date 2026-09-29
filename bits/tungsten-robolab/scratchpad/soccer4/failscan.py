"""Fast failure scan: run a controller+params on a seed list for T seconds (episode horizon MYO_SOCCER_MAX_TIME
310 so the official 10 s cut does not end it) and print per seed: bal1_s, stand_time, fallen, the phase labels with
their start times, and the label active when the kicker stopped standing.

  failscan.py --controller C --seeds a:b [--seconds 20] [--set k=v,..] [--json out.json] params
"""
import argparse, json, os, sys, multiprocessing as mp
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params


def run(job):
    params, seed, ctl, secs, env = job
    for k, v in env.items():
        os.environ[k] = v
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    try:
        m = MyoSim(MyoSoccerTask(), params=params, controller=ctl, seed=seed).run(secs)
    except Exception as e:
        return seed, {"error": str(e)[:200]}
    keep = {k: m.get(k) for k in ("bal1_s", "bal1_raw", "stand_time", "fallen", "time", "bal_l_tot", "bal_r_tot", "bal1_300")}
    ev = m.get("events") or []
    keep["events"] = [(e[1].split(":")[-1], e[0]) for e in ev]
    return seed, keep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--seconds", type=float, default=20.0)
    ap.add_argument("--set", default="")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--json")
    ap.add_argument("--env", default="myoChallengeSoccerP2-v0")
    ap.add_argument("params")
    a = ap.parse_args()
    if ":" in a.seeds:
        lo, hi = a.seeds.split(":")
        seeds = list(range(int(lo), int(hi)))
    else:
        seeds = [int(s) for s in a.seeds.split(",")]
    p = read_params(a.params)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            p[k.strip()] = float(v)
    env = {"MYO_SOCCER_ENV": a.env, "MYO_SOCCER_MAX_TIME": "310"}
    ctl = os.path.abspath(a.controller)
    with mp.Pool(a.workers) as pool:
        res = pool.map(run, [(p, s, ctl, a.seconds, env) for s in seeds])
    ok = 0
    out = []
    for seed, m in sorted(res):
        if "error" in m:
            print(seed, "ERROR", m["error"]); continue
        st = m["stand_time"] or 0.0
        alive = not m["fallen"] and st >= a.seconds - 0.1
        # the phase active at the end of standing
        lab = ""
        for name, t in m["events"]:
            if t <= st + 1e-6:
                lab = name
        good = (m["bal1_s"] or 0) >= a.seconds - 4.0 and alive
        ok += good
        first = " ".join(f"{n}@{t:.1f}" for n, t in m["events"][:7])
        print(f"{seed} {'OK ' if good else 'BAD'} bal1 {m['bal1_s']:6.2f} stand {st:6.2f} fallen {int(bool(m['fallen']))} last_label {lab:10s} | {first}", flush=True)
        out.append({"seed": seed, "good": bool(good), **m})
    print(f"{ok}/{len(res)} hold to {a.seconds:.0f} s")
    if a.json:
        json.dump(out, open(a.json, "w"))


if __name__ == "__main__":
    main()
