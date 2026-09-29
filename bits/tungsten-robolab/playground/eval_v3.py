"""Evaluate practised sprint and long-jump params with the protocols the v2
results were recorded with (out/run_v2_metrics.json, out/long_jump_v2_metrics.json):

  run   clean 40 s from the standing start, plus 12 held-out perturbed standing
        starts (seeds 101 ... 333: N(0, 0.04 rad) hips, knees, ankles, spine;
        N(0, 0.02 rad) pelvis pitch), 30 s each
  jump  the nominal start plus 12 perturbed starts (ROBOLAB_LJ_SEED 100-111:
        runway position +-0.15 m, leg joints 0-0.04 rad), 8 s each

    .venv/bin/python playground/eval_v3.py run run_v3 params/run_v3.txt --out out/x.json
    ROBOLAB_V3_RIGID=1 .venv/bin/python playground/eval_v3.py run run_v3 params/run_v3_rigid1ms.txt
    .venv/bin/python playground/eval_v3.py jump long_jump_v3 params/long_jump_v3.txt
"""

import argparse
import json
import multiprocessing as mp
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from practice import load_task, read_params  # noqa: E402
from bridge import Sim  # noqa: E402

RUN_SEEDS = [101, 202, 303, 404, 505, 606, 707, 808, 909, 111, 222, 333]
JUMP_SEEDS = list(range(100, 112))
RUN_KEYS = ("time", "distance", "speed_last5", "speed_10s", "min_speed_1s", "peak_speed_1s", "steady_speed", "t_100m",
            "stride_freq", "step_freq", "stride_length", "step_length", "flight_frac", "contact_time", "flight_time",
            "peak_grf", "pelvis_z", "torso_pitch", "effort", "strides", "fell")
JUMP_KEYS = ("official_m", "effective_m", "ballistic_m", "foul", "board_offset_m", "approach_speed", "last_step_speed",
             "takeoff_vx", "takeoff_vz", "takeoff_angle_deg", "contact_time_s", "takeoff_com_z", "peak_com_z",
             "flight_s", "clean_landing", "landed_short", "recovered", "fell_approach", "effort_msa", "state")


def one(job):
    kind, task_name, params_path, seed, seconds = job
    if kind == "jump":
        if seed is None:
            os.environ.pop("ROBOLAB_LJ_SEED", None)
        else:
            os.environ["ROBOLAB_LJ_SEED"] = str(seed)
    task = load_task(task_name)
    if kind == "run":
        task.seed = seed
    elif hasattr(task, "seed"):
        task.seed = seed
    m = Sim(task, params=read_params(params_path)).run(seconds)
    keys = RUN_KEYS if kind == "run" else JUMP_KEYS
    out = {k: m.get(k) for k in keys if k in m}
    out["seed"] = seed
    out["score"] = round(float(task.score(m)), 3)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=("run", "jump"))
    ap.add_argument("task")
    ap.add_argument("params")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.kind == "run":
        jobs = [("run", a.task, a.params, None, 40.0)] + [("run", a.task, a.params, s, 30.0) for s in RUN_SEEDS]
    else:
        jobs = [("jump", a.task, a.params, None, 8.0)] + [("jump", a.task, a.params, s, 8.0) for s in JUMP_SEEDS]
    with mp.Pool(a.workers) as pool:
        res = pool.map(one, jobs)
    out = {"task": a.task, "params": a.params, "env": {k: v for k, v in os.environ.items() if k.startswith("ROBOLAB_")},
           "clean": res[0], "perturbed": res[1:]}
    per = res[1:]
    if a.kind == "run":
        ok = [r for r in per if not r.get("fell")]
        out["robustness"] = {"survived": f"{len(ok)}/{len(per)}",
                             "mean_speed_last5": round(sum(r["speed_last5"] for r in ok) / len(ok), 3) if ok else None,
                             "min_speed_last5": min((r["speed_last5"] for r in ok), default=None)}
    else:
        legal = [r for r in per if r.get("official_m") and not r.get("foul")]
        eff = [r["effective_m"] for r in per if r.get("effective_m") is not None]
        out["robustness"] = {"completed_approach": sum(1 for r in per if not r.get("fell_approach")),
                             "legal_jumps": len(legal), "fouls": sum(1 for r in per if r.get("foul")),
                             "clean_landings": sum(1 for r in per if r.get("clean_landing")),
                             "mean_official_legal_m": round(sum(r["official_m"] for r in legal) / len(legal), 3)
                             if legal else None,
                             "mean_effective_m": round(sum(eff) / len(eff), 3) if eff else None}
    print(json.dumps(out, indent=1))
    if a.out:
        os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
        with open(a.out, "w") as f:
            json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
