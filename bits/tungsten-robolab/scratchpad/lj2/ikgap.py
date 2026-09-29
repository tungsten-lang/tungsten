"""Full jump rollouts with the planner's debug: per start the penultimate toe's gap error (ik_gap_err: board - pen toe - ik_gap0)
and the outcome (L2 scratch).
usage: ikgap.py <trial> <task> <controller> <params> <seeds> [k=v,...] [workers]"""
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
    trial_name, task_name, ctl, params_path, seed, extra = args
    trials = arena.load_json(arena.TRIALS, {})
    for k, v in trials[trial_name].get("env", {}).items():
        os.environ[k] = str(v)
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_debug"] = 1.0
    for k, v in extra.items():
        params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    cmds = []
    orig = task.on_command

    def oc(m, d, cmd):
        if cmd.startswith("dbg:"):
            cmds.append(cmd)
        return orig(m, d, cmd)
    task.on_command = oc
    m = sim.run(None)
    gap = None
    pen = None
    for c in cmds:
        if c.startswith("dbg:ikgap"):
            t = c.split(":")
            gap = float(t[-1])
            pen = t[2]
    res = {"seed": seed, "gap_err": gap, "pen": pen}
    for k in ("official_m", "effective_m", "ballistic_m", "board_offset_m", "foul_max_x", "takeoff_vx", "takeoff_vz",
              "speed_5m", "foul", "somersault", "landed_short", "fell_approach", "failed", "L_takeoff", "torso_pitch_takeoff"):
        res[k] = m.get(k)
    return res


def main():
    trial, task_name, ctl, params_path, seeds = sys.argv[1:6]
    extra = dict(kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    seeds = parse_seeds(seeds)
    jobs = [(trial, task_name, ctl, params_path, s, extra) for s in seeds]
    with mp.get_context("spawn").Pool(workers) as pool:
        rows = pool.map(job, jobs)
    for r in rows:
        print("seed %-5s pen %-3s gap_err %s | official %s off %s foul_x %s vx %s vz %s v5 %s L %s pitch %s" % (
            r["seed"], r["pen"], ("%+.3f" % r["gap_err"]) if r["gap_err"] is not None else "-", r["official_m"], r["board_offset_m"],
            r["foul_max_x"], r["takeoff_vx"], r["takeoff_vz"], r["speed_5m"], r["L_takeoff"], r["torso_pitch_takeoff"]))
    import numpy as np
    n_none = sum(1 for r in rows if r["gap_err"] is None)
    print("starts %d, without a penultimate/plant (fell or no take-off) %d" % (len(rows), n_none))
    ok = [r for r in rows if r["gap_err"] is not None and r["board_offset_m"] is not None]
    if len(ok) > 3:
        g = np.array([r["gap_err"] for r in ok])
        o = np.array([r["board_offset_m"] for r in ok])
        A = np.vstack([g, np.ones_like(g)]).T
        sl, ic = np.linalg.lstsq(A, o, rcond=None)[0]
        print("sorted pen gap errors:", " ".join("%+.2f" % x for x in sorted(g.tolist())))
        print("plant offset vs pen gap error: slope %.3f intercept %.3f resid sd %.3f | gap_err mean %.3f sd %.3f | offset mean %.3f sd %.3f n %d" % (
            sl, ic, (o - (sl * g + ic)).std(), g.mean(), g.std(), o.mean(), o.std(), len(ok)))


if __name__ == "__main__":
    main()
