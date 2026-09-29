"""bat_search: sep-CMA-ES over the in-representation bat swing's tunables on fresh pitches, with a CALIBRATED-AIM
objective (batting round 2).

    ROBOLAB_CONTROLLER=bin/challengers/bat_r2-t1 .venv/bin/python playground/bat_search.py \
        --init params/bat_r2_taim1.txt --only "arm_swing_kd,..." --box "arm_swing_kd=0:0.15,..." \
        --seeds 3008,3049,... --budget 4500 --workers 2 --out params/search/bat_r2_s1.txt --log out/bat_r2/s1.jsonl

Why a calibrated aim. The swing's miss (the ball's offset from the swing plane at contact, tasks/bat_rep.py `aim_n_cm`)
is linear in the pitch: aim_n = a0 + a_z dz + a_x dx, with dz, dx the location mismatch of the program blend
(see lib/robolab/skills/bat_power.w `aim_correction`), and any change of a physical parameter (arm damping, the drive,
the train's end) shifts a0 (and a little a_z, a_x) by several cm: a candidate that is FASTER can miss on every
pitch only because its aim is off by 3-4 cm, an error the taim gains remove again (two probes measured their
sensitivities: -59.4 and -52.4 cm of plane offset per m of mismatch per unit gain). So a candidate is scored on the
aim it would have AFTER that recalibration: per pitch

    score = bat speed (at contact, or at the closest approach of a miss)
            - BATS_AIM per cm of |residual aim_n| beyond BATS_AIM_CAP (the residual of the candidate's own least-squares
              fit of aim_n on (1, dz, dx) over its pitches)
            - BATS_TIME per ms of |aim_v - 2.5| beyond 4 ms       (timing is not recalibrated by taim)
            - BATS_FLOW per unit of bat_flow beyond BATS_FLOW_CAP
            - a penalty when the shift the recalibration would have to make is beyond what the taim gains can deliver
    candidate = mean - risk * (mean - min) over its pitches.

The best candidate is then recalibrated (scratchpad/bat/calibrate.py) and evaluated as it is. Nothing about the
representation changes: every candidate is an ordinary params file for the skill.
"""

import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")
os.environ.setdefault("BAT_BODY", "athlete")

import numpy as np  # noqa: E402

import search  # noqa: E402
from search import BoxRep, Problem, Search  # noqa: E402

LOCS = np.array([[0.0, 0.80], [-0.14, 1.00], [0.15, 0.62], [-0.06, 0.68], [0.10, 0.95], [-0.12, 0.72]])   # the 6 programs' crossings

AIM_W = float(os.environ.get("BATS_AIM", "0.5"))
AIM_CAP = float(os.environ.get("BATS_AIM_CAP", "3.0"))
TIME_W = float(os.environ.get("BATS_TIME", "0.3"))
FLOW_W = float(os.environ.get("BATS_FLOW", "8"))
FLOW_CAP = float(os.environ.get("BATS_FLOW_CAP", "2.7"))
AIM_V_REF = 2.5
A0_CAP = float(os.environ.get("BATS_A0CAP", "8"))   # cm of bias the taim offset can still remove


def blend_mismatch(x, z):
    """dz, dx: the pitch's crossing minus the inverse-squared-distance blend's location (program_weights)."""
    d2 = (x - LOCS[:, 0]) ** 2 + (z - LOCS[:, 1]) ** 2
    w = 1.0 / (d2 + 1e-8)
    w = w / w.sum()
    return z - float(w @ LOCS[:, 1]), x - float(w @ LOCS[:, 0])


def records(results):
    out = []
    for _, m, _ in results:
        ps = (m or {}).get("pitches") or []
        if not ps or ps[0].get("aim_n_cm") is None or ps[0].get("flow") is None:
            return None
        out.append(ps[0])
    return out


def analyse(recs):
    """Per-pitch calibrated scores and the candidate's diagnostics."""
    x = np.array([r["target_x"] for r in recs])
    z = np.array([r["target_z"] for r in recs])
    dz, dx = np.array([blend_mismatch(a, b) for a, b in zip(x, z)]).T
    an = np.array([r["aim_n_cm"] for r in recs])
    A = np.column_stack([np.ones(len(an)), dz, dx])
    coef = np.linalg.lstsq(A, an, rcond=None)[0]
    res = an - A @ coef
    speed = np.array([r.get("bat_speed", 0.0) for r in recs])
    av = np.array([r.get("aim_v_ms", AIM_V_REF) for r in recs])
    flow = np.array([r["flow"] for r in recs])
    hit = np.array([bool(r["hit"]) for r in recs])
    pen_aim = AIM_W * np.maximum(0.0, np.abs(res) - AIM_CAP)
    pen_time = TIME_W * np.maximum(0.0, np.abs(av - AIM_V_REF) - 4.0)
    pen_flow = FLOW_W * np.maximum(0.0, flow - FLOW_CAP)
    # what the recalibration must deliver (the fit's own a0 / a_z / a_x are what the taim gains must still remove):
    # shifts beyond the gains' reach (about 8 cm, 90 and 70 cm/m) are penalised
    shift = 0.3 * max(0.0, abs(coef[0]) - A0_CAP) + 0.02 * max(0.0, abs(coef[1]) - 90.0) + 0.02 * max(0.0, abs(coef[2]) - 70.0)
    per = speed - pen_aim - pen_time - pen_flow - shift
    return {"per": per, "speed": speed, "flow": flow, "aim_res": res, "coef": coef, "hit": hit, "shift": shift}


class BatCalProblem(Problem):
    def aggregate(self, results):
        recs = records(results)
        if recs is None:
            return -1e3
        a = analyse(recs)
        per = a["per"]
        mean, mn = float(np.mean(per)), float(np.min(per))
        return mean - self.risk * (mean - mn)


def describe_candidate(metrics_list):
    recs = [(m.get("pitches") or [None])[0] for m in metrics_list]
    if any(r is None or r.get("aim_n_cm") is None for r in recs):
        return "crashed"
    a = analyse(recs)
    return ("speed %.3f (hits %d/%d as run) flow %.3f max %.3f | aim fit a0 %+.1f az %+.0f ax %+.0f resid rms %.2f max %.1f shiftpen %.2f"
            % (a["speed"].mean(), a["hit"].sum(), len(recs), a["flow"].mean(), a["flow"].max(), a["coef"][0], a["coef"][1],
               a["coef"][2], np.sqrt(np.mean(a["aim_res"] ** 2)), np.abs(a["aim_res"]).max(), a["shift"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init", required=True)
    ap.add_argument("--only", required=True)
    ap.add_argument("--box")
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--budget", type=int, default=3000)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--risk", type=float, default=0.25)
    ap.add_argument("--seconds", type=float, default=4.3)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", required=True)
    ap.add_argument("--log", required=True)
    a = ap.parse_args()
    init = search.read_params(a.init)
    tun = search.describe("bat_rep", init)
    if a.box:
        box = {kv.split("=")[0]: tuple(float(x) for x in kv.split("=")[1].split(":")) for kv in a.box.split(",")}
        unknown = sorted(set(box) - {t[0] for t in tun})
        if unknown:
            raise SystemExit(f"--box names no tunable: {', '.join(unknown)}")
        tun = [(t[0], t[1], *box.get(t[0], (t[2], t[3]))) for t in tun]
    rep = BoxRep.from_tunables(tun, a.only.split(","), None, init, {})
    seeds = [int(s) for s in a.seeds.split(",")]
    prob = BatCalProblem("bat_rep", rep, seeds, a.seconds, a.risk)
    opts = {"popsize": a.pop} if a.pop else {}
    s = Search(prob, "sep_cma", a.budget, a.seed, a.sigma, out=a.out, log=a.log, **opts)
    print(f"bat_search: sep_cma, {rep.n} tunables, {len(seeds)} pitches per candidate, budget {a.budget} rollouts, "
          f"controller {os.environ.get('ROBOLAB_CONTROLLER')}", flush=True)
    print("names:", ",".join(rep.names), flush=True)
    last = [-1e18]

    def progress(s):
        line = f"gen {s.gen} used {s.used} best {s.best[0]:.4f} ({time.time() - s.t0:.0f}s) {s.opt.info() if s.opt else ''}"
        if s.best[0] > last[0]:
            last[0] = s.best[0]
            line += " | NEW BEST " + describe_candidate(s.best[2])
        print(line, flush=True)

    with mp.Pool(a.workers) as pool:
        search.run_searches([s], pool, progress)
    print("best", s.best[0], describe_candidate(s.best[2]), flush=True)


if __name__ == "__main__":
    main()
