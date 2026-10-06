#!/usr/bin/env python3
"""The GENTLE execution as a dry run for every candidate (3 Oct 2026): each candidate of the welded still-pad sweep (out/tt5/bwd_wq.jsonl, with the joint configuration it ended in, `qlast`) is executed by the joint-space
min-jerk move to that configuration (oracle o9: start t_start, end t_hit - lead - blend) followed by the pad-space servo for the last `blend` seconds, WELDED, and the run reports the pad error at the planned
contact (reachability under THIS execution), the outcome, and the RETENTION measures of the palm's acceleration in the paddle's axes (ret_lat across the paddle in its plane, ret_ax along it, ret_n along the normal,
ret_tot). Hand-held, the paddle was lost above about 80 m/s^2 of ret_lat (and 115-120 in the other two axes): 95 % of 170 runs classified by ret_lat alone. A selection that uses only these dry-run numbers (R6, see
retention_select.py) never looks at the outcome. LABELLED DIAGNOSTIC ORACLE.
    TT_ENV=P2 .venv-myo/bin/python scratchpad/tt5/gentle_sweep.py [--t-start 0.12 --blend 0.10 --lead 0.05 --src out/tt5/bwd_wq.jsonl --out out/tt5/gentle.jsonl]       from bits/tungsten-robolab"""
import argparse
import json
import os
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--src", default="out/tt5/bwd_wq.jsonl")
ap.add_argument("--out", default="out/tt5/gentle.jsonl")
ap.add_argument("--t-start", type=float, default=0.12)
ap.add_argument("--blend", type=float, default=0.10)
ap.add_argument("--lead", type=float, default=0.05)
ap.add_argument("--workers", type=int, default=6)
ap.add_argument("--weld", type=int, default=1)
a = ap.parse_args()
base = {"o5_togo": 1, "o5_tact": 0.15, "o5_hold": 0.03, "o5_wrot": 0.30, "o5_lead": a.lead, "o5_hold_alpha": 0.6, "o1_margin": 0.15, "o6_ton": 0.0, "o5_mus_off": 1, "o2_taumax_j": [90, 90, 90, 60, 13, 20, 25]}
os.environ["MYO_TT_ORACLE"] = "o1,o5,o6,o7,o9" if a.weld else "o1,o5,o7,o9"
os.environ["TT3_CFG"] = json.dumps(base)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
import backward_plan as bp  # noqa: E402


def main():
    import tt_fast
    rows = [json.loads(l) for l in open(a.src)]
    rows = [r for r in rows if not r.get("error") and r.get("qlast") and r.get("speed") == 0.0]
    done = set()
    if os.path.exists(a.out):
        for l in open(a.out):
            r = json.loads(l)
            done.add((r["seed"], r["off"], r["kind"]))
    params = tt_fast.read_params(bp.PARAMS)
    ctl = os.path.abspath(bp.CONTROLLER)
    plan_cache = {}
    jobs, meta = [], []
    for r in rows:
        if (r["seed"], r["off"], r["kind"]) in done:
            continue
        sd = r["seed"]
        if sd not in plan_cache:
            plan_cache[sd] = {(c["off"], c["kind"]): c["plan"] for c in bp.candidates(sd) if c["speed"] == 0.0}
        plan = plan_cache[sd][(r["off"], r["kind"])]
        t_end = plan["t_hit"] - a.lead - a.blend
        oq = {"q_target": r["qlast"], "t_start": a.t_start, "t_end": t_end, "t_stop": t_end}
        jobs.append((params, sd, None, ctl, {"orc_plan": plan, "orc_q": oq, "orc_tact": t_end}))
        meta.append({"seed": sd, "off": r["off"], "kind": r["kind"], "margin": r["margin"], "t_hit_plan": plan["t_hit"], "qlast": r["qlast"], "A": None, "perr_aggr": r.get("perr"), "solved_aggr": r.get("solved")})
    print(f"{len(jobs)} gentle dry runs ({len(done)} done)", flush=True)
    with open(a.out, "a") as f:
        pool = tt_fast.pool(a.workers)
        for m, res in zip(meta, pool.imap(tt_fast.episode, jobs, chunksize=2)):
            m.update(error=res.get("error"), hit=res.get("hit"), solved=res.get("solved"), perr=res.get("o5_pad_err_last"), palm=res.get("palm_err_max"),
                     ret_lat=res.get("ret_lat"), ret_ax=res.get("ret_ax"), ret_n=res.get("ret_n"), ret_tot=res.get("ret_tot"))
            f.write(json.dumps(m) + "\n")
            f.flush()


if __name__ == "__main__":
    main()
