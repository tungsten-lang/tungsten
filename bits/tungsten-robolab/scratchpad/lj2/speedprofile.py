"""COM speed / stride vs distance for the run-up alone (j_run 1) on a long runway (L2 scratch).
usage: speedprofile.py <trial> <task> <controller> <params> <seed|None> <approach_m> [k=v,...]"""
import os
import sys
import importlib

os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")


def main():
    import numpy as np
    import arena
    from bridge import Sim
    trial_name, task_name, ctl, params_path, seed, approach = sys.argv[1:7]
    extra = dict(kv.split("=") for kv in (sys.argv[7] if len(sys.argv) > 7 else "").split(",") if kv)
    os.environ["ROBOLAB_LJ_APPROACH"] = approach
    trials = arena.load_json(arena.TRIALS, {})
    trial = trials[trial_name]
    for k, v in trial.get("env", {}).items():
        os.environ[k] = str(v)
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = None if seed == "None" else int(seed)
    params = arena.read_params(params_path)
    params["j_run"] = 1.0
    params.pop("j_ik", None)
    for k, v in extra.items():
        params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    tr = np.array(task.run_trace)
    x, t = tr[:, 1], tr[:, 0]
    print("rollout seconds", task.seconds, "trace", tr.shape, "fell_approach", m.get("fell_approach"))
    for xx in (5, 10, 15, 20, 25, 30, 35, 37.5, 40, 42.5, 44, 45, 50, 55, 60, 65, 70, 75):
        k = np.searchsorted(x, xx)
        if k >= len(x) - 1:
            break
        lo = np.searchsorted(x, xx - 2.5)
        hi = np.searchsorted(x, xx + 2.5)
        if hi >= len(x):
            hi = len(x) - 1
        sp = (x[hi] - x[lo]) / (t[hi] - t[lo])
        print("x %5.1f  t %5.2f  speed(5 m window) %5.2f  vx %5.2f" % (xx, t[k], sp, tr[k, 2]))
    tds = sorted(task.touchdowns, key=lambda k: k[1])
    steps = [(round(a[1], 2), round(b[2] - a[2], 2)) for a, b in zip(tds[:-1], tds[1:]) if a[0] != b[0]]
    print("touchdowns", len(tds), "step lengths (t, m) last 14:", steps[-14:])


if __name__ == "__main__":
    main()
