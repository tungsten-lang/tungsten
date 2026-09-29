"""For a list of seeds: when does the plant foot first touch after the ik program starts, and how hard (scratch, mine)."""
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
for seed in seeds.split(","):
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = None if seed == "None" else int(seed)
    sim = Sim(task, params=dict(params0), controller=os.path.abspath(ctl))
    m, d = sim.m, sim.d
    task.reset(m, d); mujoco.mj_forward(m, d); sim.start_controller()
    substeps = max(1, round(task.control_dt / m.opt.timestep))
    rows = []
    t_ik = None
    try:
        while d.time < task.seconds:
            act, c = sim.tick()
            lab = sim.label
            if t_ik is None and lab.endswith("_ik"):
                t_ik = d.time
            for _ in range(substeps):
                task.before_step(m, d); mujoco.mj_step(m, d)
            sim.log.append((d.time, sim.label, act.copy(), c.copy(), sim.targets.copy()))
            ct = sim.contacts()
            rows.append((d.time, lab, ct["l_foot"], ct["r_foot"]))
            if task.done(m, d):
                break
            if t_ik is not None and d.time > t_ik + 0.9:
                break
    finally:
        sim.stop_controller()
    if t_ik is None:
        print(seed, "no ik start"); continue
    # plant = r_ for these params; first r contact after t_ik
    ev = []
    prev = 0.0
    for t, lab, lc, rc in rows:
        if t < t_ik: continue
        if rc > 0.05 and prev <= 0.05:
            ev.append(("R down", round(t - t_ik, 3), round(rc, 2)))
        if rc <= 0.05 and prev > 0.05:
            ev.append(("R up", round(t - t_ik, 3)))
        prev = rc
    pk = max((rc for t, lab, lc, rc in rows if t >= t_ik), default=0)
    print(seed, "ik start", round(t_ik, 3), "R events (s after start):", ev, "peak R", round(pk, 1))
