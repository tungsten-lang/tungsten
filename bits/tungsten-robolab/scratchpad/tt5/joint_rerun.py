#!/usr/bin/env python3
"""Execute the backward plans with the JOINT-SPACE MIN-JERK servo (oracle mode o9) instead of the pad-space servo: the 7 arm joints move from where they are at t_start to the configuration the welded
dry run of the SAME plan ended in (`o5_q_last`, out/tt5/rerun_<src>.json), arriving at t_hit - lead with zero velocity and acceleration (computed-torque PD with the reference acceleration as feed-forward),
hand-held or welded. The plans are R2 selected among the still-pad candidates (backward_rerun.py --speed0). LABELLED DIAGNOSTIC ORACLE.
    TT_ENV=P2 .venv-myo/bin/python scratchpad/tt5/joint_rerun.py LABEL --modes o1,o7,o9 --t-start 0.15 [--lead 0.05] [--cfg '{...}'] [--src qdry0]       from bits/tungsten-robolab"""
import argparse
import json
import os
import sys

ap = argparse.ArgumentParser()
ap.add_argument("label")
ap.add_argument("--modes", default="o1,o7,o9")
ap.add_argument("--t-start", type=float, default=0.15)
ap.add_argument("--lead", type=float, default=0.05)
ap.add_argument("--src", default="qdry0")
ap.add_argument("--stance", action="store_true", help="regenerate the plans with the stance (pelvis target); run with --cfg '{\"o1_plan_time\":1}'")
ap.add_argument("--blend", type=float, default=0.0, help="HYBRID: the joint-space min-jerk move ends BLEND s earlier and the pad-space servo (o5, add it to --modes) takes over for the last BLEND s")
ap.add_argument("--cfg", default="{}")
ap.add_argument("--workers", type=int, default=6)
ap.add_argument("--set", default="", help="params name=value,... (grip variants)")
a = ap.parse_args()
base = {"o5_togo": 1, "o5_tact": 0.15, "o5_hold": 0.03, "o5_wrot": 0.30, "o5_lead": 0.05, "o5_hold_alpha": 0.6, "o1_margin": 0.15, "o6_ton": 0.0, "o5_mus_off": 1, "o2_taumax_j": [90, 90, 90, 60, 13, 20, 25]}
base.update(json.loads(a.cfg))
os.environ["MYO_TT_ORACLE"] = a.modes
os.environ["TT3_CFG"] = json.dumps(base)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
import backward_plan as bp  # noqa: E402


def main():
    import tt_fast
    src = json.load(open(f"out/tt5/rerun_{a.src}.json"))
    params = tt_fast.read_params(bp.PARAMS)
    for kv in filter(None, a.set.split(",")):
        k_, v_ = kv.split("=")
        params[k_] = float(v_)
    ctl = os.path.abspath(bp.CONTROLLER)
    jobs, meta = [], []
    for r in src:
        if not r.get("qlast"):
            continue
        sd = r["seed"]
        plan = next(c["plan"] for c in bp.candidates(sd, 0.0, 0.0, a.stance) if c["off"] == r["off"] and c["kind"] == r["kind"] and c["speed"] == 0.0)
        t_end = plan["t_hit"] - a.lead - a.blend
        oq = {"q_target": r["qlast"], "t_start": a.t_start, "t_end": t_end, "t_stop": (t_end if a.blend > 0 else plan["t_hit"] + 0.03)}
        attrs = {"orc_plan": plan, "orc_q": oq}
        if a.blend > 0:
            attrs["orc_tact"] = t_end
        jobs.append((params, sd, None, ctl, attrs))
        meta.append(r)
    pool = tt_fast.pool(a.workers)
    res = list(pool.imap(tt_fast.episode, jobs, chunksize=1))
    out = []
    for m, r in zip(meta, res):
        out.append(dict(seed=m["seed"], off=m["off"], kind=m["kind"], solved=r.get("solved"), hit=r.get("hit"), palm_err_max=r.get("palm_err_max"), err=r.get("error")))
    json.dump(out, open(f"out/tt5/joint_{a.label}.json", "w"))
    for name, rng in (("valid", range(98030, 98100)), ("setb", range(830000, 830100))):
        ss = [o for o in out if o["seed"] in rng]
        k = sum(1 for o in ss if (o["solved"] or 0) > 0)
        t = sum(1 for o in ss if (o["hit"] or 0) > 0)
        lost = sum(1 for o in ss if (o["palm_err_max"] or 0) > 0.3)
        print(f"{a.label} [{a.modes} t_start {a.t_start} lead {a.lead} blend {a.blend} {a.cfg}{(" " + a.set) if a.set else ""}] {name}: solved {k} of {len(ss)} = {100 * k / max(len(ss), 1):.0f} %, touched {t}, paddle left the hand (palm_err_max > 0.3) {lost}", flush=True)


if __name__ == "__main__":
    main()
