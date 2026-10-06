#!/usr/bin/env python3
"""SOLVING BACKWARDS (Erik, 3 Oct 2026), an ORACLE experiment: plan from the legal return back to the arm instead of forward from the stroke.

For each serve (the champion's own log gives the ball's free path; foreknowledge, as in the earlier oracle ladder) and each SLICE of that path around the champion's own contact time (+-100 ms, 20 ms
apart), the impact model (tt_impact.py, E 0.95, MU 0.012, ALPHA 0.9) gives the LEGAL contact states: pad orientation (pitch, yaw; 1 deg grid) and retreat speed s, scored by the landing margin (the cushion
to the net / table edges). Candidates per slice: (1) the best-margin cell at s = 0, (2) the best-margin cell at s = 1 m/s, (3) the margin >= 0.15 cell nearest to the champion's own pad orientation at that tick.
Each candidate is a PLAN (t_hit = the slice time, P = p - 0.04 n_out, n_out, v = (s, 0, 0)) executed by the ideal-arm oracle (o1 settled pelvis, o5 time-to-go pad servo with the arm muscles off, o6 weld,
o7 trunk lock: the best configuration of the earlier ladder) and the run reports the pad error at the planned contact (o5_pad_err_last) and the environment's outcome. A SELECTION that never looks at the
outcome (the best margin among the candidates the servo REACHED: pad error <= 1.5 cm and <= 2.5 deg) is what a backward planner with a reachability test (IK) would pick.
LABELLED DIAGNOSTIC ORACLE (ideal arm, foreknowledge of the ball path): never comparable with the official trial.
    TT_ENV=P2 .venv-myo/bin/python scratchpad/tt5/backward_plan.py SEEDS [--out out/tt5/bwd.jsonl] [--workers 6]       SEEDS: valid | setb | a comma list      from bits/tungsten-robolab"""
import argparse
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
CFG = {"o5_togo": 1, "o5_tact": 0.15, "o5_hold": 0.03, "o5_wrot": 0.30, "o5_lead": 0.05, "o5_hold_alpha": 0.6, "o1_margin": 0.15, "o6_ton": 0.0, "o5_mus_off": 1}
os.environ["TT_ENV"] = "P2"
os.environ["TT_TASK"] = "myo_tt_oracle"
os.environ.setdefault("MYO_TT_ORACLE", "o1,o5,o6,o7")      # setdefault: scratchpad/tt5/backward_rerun.py sets its own modes and config before importing this file
os.environ.setdefault("TT3_CFG", json.dumps(CFG))
os.environ["TT3_PASS1"] = "out/tt3/logs_o0"
os.environ["TT3_PLAN"] = "scratchpad/tt3/results/plan_bn0.1.json"
sys.path.insert(0, os.path.join(ROOT, "playground"))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "tt5"))
import tt_impact as ti  # noqa: E402
from slice_model import margin, free_path, E, MU, ALPHA  # noqa: E402

PARAMS = "params/myo_tt_p2_r10_c3.txt"
CONTROLLER = "bin/challengers/myo_tt_r10-n"
PIT = np.arange(-40.0, 60.1, 1.0)
YAW = np.arange(-35.0, 35.1, 1.0)
OFFS = [-0.10, -0.08, -0.06, -0.04, -0.02, 0.0, 0.02, 0.04, 0.06, 0.08, 0.10]
NRM = ti.normals_grid(PIT, YAW)          # (P, Y, 3) pad axes pointing +x


def candidates(sd, sig_p=0.0, sig_v=0.0, stance=False):
    z = np.load(f"out/tt3/logs_o0/{sd}.npz", allow_pickle=True)
    L, k = z["L"], int(z["contact"])
    T, P, V = free_path(L, k, t_extra=0.3)
    if sig_p > 0 or sig_v > 0:                    # what the planner believes about the ball (the TRUE ball still arrives where it arrives): one error draw per serve, held along the path
        rg = np.random.default_rng(sd)
        P = P + rg.normal(0, sig_p, 3)
        V = V + rg.normal(0, sig_v, 3)
    kc = (k - 1) if k >= 1 else int(np.argmin(np.linalg.norm(L[:, 1:4] - L[:, 7:10], axis=1)))
    nL = L[:, 13:16] / np.linalg.norm(L[:, 13:16], axis=1, keepdims=True)
    nL = np.where(nL[:, :1] < 0, -nL, nL)
    out = []
    for off in OFFS:
        j = kc + int(round(off / 0.01))
        if not (0 <= j < len(T)) or not (1.2 <= P[j, 0] <= 2.8 and P[j, 2] > 0.5):
            continue
        champ_pit = float(np.degrees(np.arcsin(np.clip(nL[min(j, len(nL) - 1), 2], -1, 1))))
        champ_yaw = float(np.degrees(np.arctan2(nL[min(j, len(nL) - 1), 1], nL[min(j, len(nL) - 1), 0])))
        M = {}
        for s in (0.0, 1.0):
            v = ti.impact(V[j], ALPHA * np.array([s, 0.0, 0.0]), NRM, E, MU)
            M[s] = margin(P[j], v)
        picks = []
        for s in (0.0, 1.0):
            a, b = np.unravel_index(int(np.argmax(M[s])), M[s].shape)
            if M[s][a, b] > 0.05:
                picks.append(("best_s%d" % int(s), s, float(PIT[a]), float(YAW[b]), float(M[s][a, b])))
        ok = M[0.0] >= 0.15
        if ok.any():
            PP, YY = np.meshgrid(PIT, YAW, indexing="ij")
            ang = np.where(ok, np.hypot(PP - champ_pit, YY - champ_yaw), 1e9)
            a, b = np.unravel_index(int(np.argmin(ang)), ang.shape)
            picks.append(("near_champ", 0.0, float(PIT[a]), float(YAW[b]), float(M[0.0][a, b])))
        seen = set()
        for kind, s, pit, yaw, mg in picks:
            if (s, pit, yaw) in seen:
                continue
            seen.add((s, pit, yaw))
            n = ti.normal_from_angles(np.radians(pit), np.radians(yaw))
            n_out = -n
            plan = {"t_hit": float(T[j]), "P": (P[j] - 0.04 * n_out).tolist(), "n_out": n_out.tolist(), "v": [s, 0.0, 0.0], "t_on": float(T[j]) - 0.15, "t_off": float(T[j]) + 0.15}
            if stance:
                # STANCE: the champion's contact posture is a comfortable one (it holds the paddle there in every serve): keep its pelvis-to-pad geometry and move the pelvis with the pad's
                # horizontal displacement. The slides are minus the world pelvis position (world x = 1.6 - slide x, world y = -slide y), so the slide target moves by -(dP_xy).
                plan["pel"] = (np.array(z["X"][kc, 10:12], float) - (np.array(plan["P"][:2]) - L[kc, 7:9])).tolist()
            out.append(dict(seed=sd, off=off, kind=kind, speed=s, pitch=pit, yaw=yaw, margin=mg, plan=plan))
    return out


def seeds_of(a):
    if a == "valid":
        return list(range(98030, 98100))
    if a == "setb":
        return list(range(830000, 830100))
    return [int(x) for x in a.split(",")]


def main():
    import tt_fast
    ap = argparse.ArgumentParser()
    ap.add_argument("seeds")
    ap.add_argument("--out", default="out/tt5/bwd.jsonl")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--stance", action="store_true", help="candidates carry a pelvis target (the champion's stance moved with the pad); run with cfg o1_plan_time 1")
    ap.add_argument("--speed0", action="store_true", help="only still-pad candidates (retreat speed 0)")
    ap.add_argument("--sig-p", type=float, default=0.0, help="planner's ball position error (m) per axis, one draw per serve")
    ap.add_argument("--sig-v", type=float, default=0.0, help="planner's ball velocity error (m/s) per axis")
    a = ap.parse_args()
    params = tt_fast.read_params(PARAMS)
    ctl = os.path.abspath(CONTROLLER)
    done = set()
    if os.path.exists(a.out):
        for l in open(a.out):
            r = json.loads(l)
            done.add((r["seed"], r["off"], r["kind"], r["speed"]))
    jobs, meta = [], []
    for sd in seeds_of(a.seeds):
        for c in candidates(sd, a.sig_p, a.sig_v, a.stance):
            if a.speed0 and c["speed"] != 0.0:
                continue
            if (sd, c["off"], c["kind"], c["speed"]) in done:
                continue
            jobs.append((params, sd, None, ctl, {"orc_plan": c["plan"]}))
            meta.append({k: v for k, v in c.items() if k != "plan"} | {"t_hit_plan": c["plan"]["t_hit"]})
    print(f"{len(jobs)} candidate runs ({len(done)} done)", flush=True)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "a") as f:
        pool = tt_fast.pool(a.workers)
        for m, r in zip(meta, pool.imap(tt_fast.episode, jobs, chunksize=2)):
            m.update(error=r.get("error"), hit=r.get("hit"), solved=r.get("solved"), landed=r.get("landed"), perr=r.get("o5_pad_err_last"), palm=r.get("palm_err_max"), qlast=r.get("o5_q_last"))
            f.write(json.dumps(m) + "\n")
            f.flush()


if __name__ == "__main__":
    main()
