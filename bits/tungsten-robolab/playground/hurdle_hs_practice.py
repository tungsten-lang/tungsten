"""Practice driver for the high-school hurdles skill (HurdleHSSkill).

Runs `--repeats` independent searches of one method (playground/search.py)
in lockstep over one worker pool, over the tunables matching `--only`
(default: the hurdle tunables `h_*`), everything else fixed from `--init`
(the run gait's practised params plus any earlier hurdle stage). The course
comes from the ROBOLAB_HURDLE_* environment (see tasks/hurdle_hs.py), e.g. a
single 0.762 m hurdle with a 6 m run-out:

    ROBOLAB_HURDLE_HEIGHT=0.762 ROBOLAB_HURDLE_COUNT=1 ROBOLAB_HURDLE_RUNOUT=6 \\
      .venv/bin/python playground/hurdle_hs_practice.py hurdle_hs_v3 --init params/run_v3.txt \\
      --method oneplusone --repeats 3 --budget 600 --seconds 9 --out out/hurdle_hs/a1

Rollouts run a frozen copy of the controller (<out>.controller). Each
search writes <out>_s<seed>.txt (best params, full precision) and
<out>_s<seed>.jsonl (per generation); the overall best is copied to <out>.txt.
"""

import argparse
import multiprocessing as mp
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from search import BoxRep, Problem, Search, describe, load_task, parse_list, read_params, run_searches  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task")
    ap.add_argument("--init", required=True, help="params file(s), comma-separated, later files override")
    ap.add_argument("--method", default="oneplusone", help="a method, or one per search, comma-separated")
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--budget", type=int, default=600, help="rollouts per search")
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--seeds", help="training seeds (0 = clean start), comma-separated; default 0")
    ap.add_argument("--risk", type=float, default=0.5)
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--only", default="h_*")
    ap.add_argument("--exclude", default="h_leg_len")
    ap.add_argument("--fixed", help="name=value,... (params-file switches such as h_via=1)")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--controller", help="controller binary (default: the task's); a frozen copy is what runs")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    # every rollout runs a frozen copy of the controller, so rebuilding the
    # skill mid-search cannot change the program being practised
    src = a.controller or load_task(a.task).controller
    snap = f"{a.out}.controller"
    os.makedirs(os.path.dirname(snap) or ".", exist_ok=True)
    shutil.copy2(src, snap)
    os.environ["ROBOLAB_CONTROLLER"] = os.path.abspath(snap)
    init = {}
    for path in a.init.split(","):
        init.update(read_params(path))
    fixed = {}
    for kv in filter(None, (a.fixed or "").split(",")):
        k, v = kv.split("=")
        fixed[k] = float(v)
    init.update(fixed)
    tun = describe(a.task, init)
    rep = BoxRep.from_tunables(tun, parse_list(a.only), parse_list(a.exclude), init, fixed)
    seeds = parse_list(a.seeds, int) or [0]
    prob = Problem(a.task, rep, seeds, a.seconds, a.risk)
    opts = {"popsize": a.pop} if a.pop else {}
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    # --method may list one method per search (e.g. bo,oneplusone,oneplusone)
    methods = a.method.split(",")
    if len(methods) == 1:
        methods = methods * a.repeats
    searches = [Search(prob, meth, a.budget, s, a.sigma, out=f"{a.out}_s{s}.txt", log=f"{a.out}_s{s}.jsonl",
                       label=f"{a.task}/{meth}/s{s}", **(opts if meth not in ("oneplusone", "bo") else {}))
                for s, meth in zip(range(a.seed0, a.seed0 + len(methods)), methods)]
    env = {k: v for k, v in os.environ.items() if k.startswith("ROBOLAB_")}
    print(f"practice {a.task}: {methods}, {rep.n} tunables, {a.budget} rollouts each, "
          f"seeds {seeds}, env {env}", flush=True)
    t0 = time.time()

    def progress(s):
        if s.gen % 20 == 0 or s.done:
            m = s.best[2][0] if s.best[2] else {}
            print(f"[{s.label}] gen {s.gen} used {s.used} best {s.best[0]:.3f} "
                  f"(cleared {m.get('cleared')} margin {m.get('margin')} vmargin {m.get('vmargin')} "
                  f"{m.get('vmargin_part')} com {m.get('com_clearance')} "
                  f"x {m.get('x')} fell {m.get('fell')}) {time.time() - t0:.0f}s {s.opt.info() if s.opt else ''}",
                  flush=True)

    with mp.Pool(a.workers) as pool:
        run_searches(searches, pool, progress)
    best = max(searches, key=lambda s: s.best[0])
    shutil.copy2(best.out, a.out + ".txt")
    for s in searches:
        print(f"{s.label}: best {s.best[0]:.3f}", flush=True)
    print(f"best: {best.label} {best.best[0]:.3f} -> {a.out}.txt", flush=True)


if __name__ == "__main__":
    main()
