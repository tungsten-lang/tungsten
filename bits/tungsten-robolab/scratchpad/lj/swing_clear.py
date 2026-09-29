"""Swing (plant-side) foot site heights vs program time for given seeds (scratch, mine)."""
import os, sys, json, math, importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import mujoco
import arena
from bridge import Sim
trial_name, task_name, ctl, params_path, seeds, extra = sys.argv[1:7]
extra = dict(kv.split("=") for kv in extra.split(",") if kv)
trials = arena.load_json(arena.TRIALS, {})
trial = trials[trial_name]
for k, v in trial.get("env", {}).items():
    os.environ[k] = str(v)
params0 = arena.read_params(params_path)
for k, v in extra.items():
    params0[k] = float(v)
res = {}
for seed in seeds.split(","):
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = None if seed == "None" else int(seed)
    sim = Sim(task, params=dict(params0), controller=os.path.abspath(ctl))
    m, d = sim.m, sim.d
    task.reset(m, d); mujoco.mj_forward(m, d); sim.start_controller()
    substeps = max(1, round(task.control_dt / m.opt.timestep))
    t_ik = None; rows = []
    try:
        while d.time < task.seconds:
            act, c = sim.tick()
            if t_ik is None and sim.label.endswith("_ik"):
                t_ik = d.time
            for _ in range(substeps):
                task.before_step(m, d); mujoco.mj_step(m, d)
            sim.log.append((d.time, sim.label, act.copy(), c.copy(), sim.targets.copy()))
            if t_ik is not None:
                tz = float(d.site("r_toe").xpos[2]); hz = float(d.site("r_heel").xpos[2])
                fz = float(d.body("r_foot").xpos[2])
                rows.append((d.time - t_ik, tz, hz, fz, sim.contacts()["r_foot"]))
            if task.done(m, d) or (t_ik is not None and d.time > t_ik + 0.3):
                break
    finally:
        sim.stop_controller()
    res[seed] = rows
print("s     " + "  ".join(f"{s:>22}" for s in res))
n = min(len(r) for r in res.values())
for i in range(0, n, 3):
    print("%.3f " % res[list(res)[0]][i][0] + "  ".join("toe %.3f heel %.3f c%.1f" % (r[i][1], r[i][2], r[i][4]) for r in res.values()))
