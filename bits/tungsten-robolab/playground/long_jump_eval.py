"""long_jump_eval: full rollouts of a long-jump controller + params on a list of
starts, one line per start (official mark, why a jump failed, the take-off's
numbers), the same rollouts as the arena's (arena.rollout), for validation on
starts that are NOT the arena's.

    .venv/bin/python playground/long_jump_eval.py long_jump_p95_robust --params P --controller C \
        --task long_jump_p95d --seeds 2001-2016 [--set j_board_shift=1.07,ik_gap0=2.0] [--workers 3] [--out x.json]

The trial supplies the body (env) and, unless overridden, the task. `--seeds`
takes comma lists and ranges (None = the nominal start). `--set` overrides
params-file entries for the run (a check-mark shift, a landing clock...).
"""

import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)


def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if tok in ("None", "0", "nominal"):
            out.append(None if tok != "0" else 0)
        elif "-" in tok[1:]:
            a, b = tok.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(tok))
    return out


def why(m):
    if m.get("error"):
        return "error"
    if m.get("official_m", 0.0) > 0.0:
        return ""
    for k, lab in (("foul", "foul"), ("somersault", "somersault"), ("landed_short", "short"),
                   ("touched_runway_after_landing", "runway-after"), ("fell_approach", "fell-in-run")):
        if m.get(k):
            return lab
    return "no-take-off" if m.get("takeoff_vx") is None else "0"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trial")
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--task")
    ap.add_argument("--seeds")
    ap.add_argument("--set", default="", help="k=v,... overrides of params entries")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--out")
    a = ap.parse_args()
    import arena
    trials = arena.load_json(arena.TRIALS, {})
    trial = dict(trials[a.trial])
    seeds = parse_seeds(a.seeds) if a.seeds else trial["seeds"]
    trial["seeds"] = seeds
    params = arena.read_params(a.params)
    for kv in a.set.split(","):
        if kv:
            k, v = kv.split("=")
            params[k] = float(v)
    task = a.task or trial["task"]
    controller = os.path.abspath(a.controller)
    t0 = time.time()
    rows, scores = arena.evaluate(trial, params, controller, task, a.workers)
    print(f"{a.trial} task {task} controller {os.path.basename(controller)} params {os.path.basename(a.params)} "
          f"{a.set}  ({time.time() - t0:.0f}s)")
    ok = 0
    for s, m, sc in zip(seeds, rows, scores):
        w = why(m)
        print("seed %-5s official %6.3f %-12s eff %s ballistic %s off %s foul_x %s vx %s vz %s ang %s contact %s flight %s v5 %s" % (
            s, sc if abs(sc) < 1e8 else -1, w, m.get("effective_m"), m.get("ballistic_m"), m.get("board_offset_m"),
            m.get("foul_max_x"), m.get("takeoff_vx"), m.get("takeoff_vz"), m.get("takeoff_angle_deg"),
            m.get("contact_time_s"), m.get("flight_s"), m.get("speed_5m")))
        ok += 1 if sc > 0 else 0
    good = [sc for sc in scores if abs(sc) < 1e8]
    mean = sum(good) / len(good)
    sd = math.sqrt(sum((x - mean) ** 2 for x in good) / max(1, len(good) - 1))
    fails = [why(m) for m in rows if why(m)]
    print(f"MEAN {mean:.4f} (+-{1.96 * sd / math.sqrt(len(good)):.3f}) over {len(good)} starts; legal {ok}/{len(good)}; "
          f"failures {fails}; mean of legal {sum(x for x in good if x > 0) / max(1, ok):.3f}")
    if a.out:
        json.dump({"trial": a.trial, "task": task, "controller": controller, "params": a.params, "set": a.set,
                   "seeds": seeds, "scores": scores, "rows": rows}, open(a.out, "w"), default=float)


if __name__ == "__main__":
    main()
