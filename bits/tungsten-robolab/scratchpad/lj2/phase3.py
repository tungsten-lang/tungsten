"""Where does the stride pattern's seed-to-seed phase spread come from? sd of the k-th touchdown position / time across seeds (L2 scratch)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import multiprocessing as mp


def job(args):
    import arena
    from bridge import Sim
    params_path, ctl, task_name, board, seed, extra = args
    os.environ["ROBOLAB_LJ_APPROACH"] = str(board)
    for k, v in {"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "p95", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}.items():
        os.environ.setdefault(k, v)
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_run"] = 1.0
    params.pop("j_ik", None); params.pop("j_il", None)
    for k, v in extra.items():
        params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    tds = sorted(task.touchdowns, key=lambda k: k[1])
    return {"seed": seed, "fell": bool(m.get("fell_approach")), "tds": [(t[0], t[1], t[2] + float(board), t[3]) for t in tds]}


def main():
    import numpy as np
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import phase
    params_path, ctl, task_name, board, seeds = sys.argv[1:6]
    extra = dict(kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)
    seeds = phase.parse_seeds(seeds)
    jobs = [(params_path, ctl, task_name, float(board), s, extra) for s in seeds]
    with mp.get_context("spawn").Pool(2) as pool:
        rows = pool.map(job, jobs)
    X, T, F = [], [], []
    for r in rows:
        if r["fell"]:
            continue
        tds = []
        for t in r["tds"]:
            if tds and tds[-1][0] == t[0] and t[1] - tds[-1][1] < 0.12:
                continue
            tds.append(t)
        n = 22
        if len(tds) < n:
            continue
        X.append([t[2] for t in tds[:n]]); T.append([t[1] for t in tds[:n]]); F.append("".join(t[0] for t in tds[:n]))
    X, T = np.array(X), np.array(T)
    print("n seeds", len(X))
    print("first foot counts:", {c: sum(1 for f in F if f[0] == c) for c in "lr"})
    for k in range(n):
        print("td %2d: x mean %6.2f sd %.3f | t mean %5.2f sd %.3f | step-to-step sd %.3f" % (
            k, X[:, k].mean(), X[:, k].std(), T[:, k].mean(), T[:, k].std(), (X[:, k] - X[:, k - 1]).std() if k else 0.0))


if __name__ == "__main__":
    main()
