"""Natural stride phase at the check mark: approach-only rollouts (j_run 1) of a jump controller + params, the toe
position of each touchdown relative to the check mark (L2 scratch).
usage: phase.py <params> <controller> <task> <board_m> <seeds> [k=v,...] [workers]"""
import os
import sys
import importlib
import multiprocessing as mp

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)


def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if tok == "None":
            out.append(None)
        elif "-" in tok[1:]:
            a, b = tok.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(tok))
    return out


def job(args):
    import arena
    from bridge import Sim
    params_path, ctl, task_name, board, seed, extra = args
    os.environ["ROBOLAB_LJ_APPROACH"] = str(board)
    env = {"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "p95", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}
    for k, v in env.items():
        os.environ.setdefault(k, v)
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_run"] = 1.0
    params.pop("j_ik", None)
    params.pop("j_il", None)
    for k, v in extra.items():
        params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    tds = sorted(task.touchdowns, key=lambda k: k[1])
    # the touchdowns before the check mark: (foot, t, toe x - board, vx)
    pre = [(t[0], t[1], t[2], t[3]) for t in tds if t[2] < 1.0]
    return {"seed": seed, "fell": bool(m.get("fell_approach")), "tds": pre[-8:]}


def main():
    params_path, ctl, task_name, board, seeds = sys.argv[1:6]
    extra = dict(kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    seeds = parse_seeds(seeds)
    jobs = [(params_path, ctl, task_name, float(board), s, extra) for s in seeds]
    with mp.get_context("spawn").Pool(workers) as pool:
        rows = pool.map(job, jobs)
    import numpy as np
    last = []
    for r in rows:
        if r["fell"] or len(r["tds"]) < 5:
            print("seed", r["seed"], "fell" if r["fell"] else "short", r["tds"][-3:])
            continue
        xs = [round(t[2], 2) for t in r["tds"]]
        print("seed %-5s toes rel. to the line: %s  feet %s" % (r["seed"], xs[-6:], "".join(t[0][0] for t in r["tds"][-6:])))
        last.append([t[2] for t in r["tds"][-6:]])
    A = np.array(last)
    print("last 6 touchdowns (rel. to the line): mean", np.round(A.mean(0), 3).tolist(), "sd", np.round(A.std(0), 3).tolist())
    print("min", np.round(A.min(0), 2).tolist(), "max", np.round(A.max(0), 2).tolist())


if __name__ == "__main__":
    main()
