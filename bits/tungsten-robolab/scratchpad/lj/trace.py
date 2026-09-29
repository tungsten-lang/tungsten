"""Full-rollout trace around the take-off (scratch, mine): per tick from the penultimate touchdown."""
import os, sys, json, math
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import importlib
import numpy as np
import mujoco
import arena
from bridge import Sim
trial_name, task_name, ctl, params_path, seed = sys.argv[1:6]
extra = dict(kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)
t_from = float(sys.argv[7]) if len(sys.argv) > 7 else None
step = int(sys.argv[8]) if len(sys.argv) > 8 else 2
trials = arena.load_json(arena.TRIALS, {})
trial = trials[trial_name]
for k, v in trial.get("env", {}).items():
    os.environ[k] = str(v)
task = importlib.import_module(f"tasks.{task_name}").TASK()
task.seed = None if seed == "None" else int(seed)
params = arena.read_params(params_path)
for k, v in extra.items():
    params[k] = float(v)
sim = Sim(task, params=params, controller=os.path.abspath(ctl))
m, d = sim.m, sim.d
task.reset(m, d)
mujoco.mj_forward(m, d)
sim.start_controller()
substeps = max(1, round(task.control_dt / m.opt.timestep))
rows = []
cmds = []
orig = task.on_command
def oc(mm, dd, cmd):
    cmds.append((round(dd.time, 3), cmd))
    return orig(mm, dd, cmd)
task.on_command = oc
head = m.geom("head").id
try:
    k = 0
    while d.time < task.seconds:
        act, c = sim.tick()
        for _ in range(substeps):
            task.before_step(m, d)
            mujoco.mj_step(m, d)
        sim.log.append((d.time, sim.label, act.copy(), c.copy(), sim.targets.copy()))
        mujoco.mj_subtreeVel(m, d)
        pel = m.body("pelvis").id
        com = d.subtree_com[pel]; v = d.subtree_linvel[pel]
        up = d.xmat[m.body("torso").id].reshape(3, 3)[:, 2]
        feet = []
        for side in ("l", "r"):
            feet.append((float(d.xpos[m.body(f"{side}_foot").id][0]), float(d.xpos[m.body(f"{side}_foot").id][2])))
        ct = sim.contacts()
        rows.append((d.time, sim.label, float(com[0]), float(com[2]), float(v[0]), float(v[2]), math.atan2(up[0], up[2]),
                     feet[0][0], feet[0][1], feet[1][0], feet[1][1], ct["l_foot"], ct["r_foot"], float(d.subtree_angmom[pel][1])))
        if task.done(m, d):
            break
finally:
    sim.stop_controller()
mt = task.metrics(m, d, sim.log)
print({k: mt.get(k) for k in ("official_m", "effective_m", "board_offset_m", "foul_max_x", "takeoff_vx", "takeoff_vz", "flight_s", "failed", "somersault", "landed_short")})
b = task.board_x
# window
t0 = t_from if (t_from is not None and t_from > 0) else next(r[0] for r in rows if r[1].endswith("_ik")) - 0.05
print("t   label     com_x(rel board) com_z  vx    vz   torso  L_x(rel)/z  R_x/z   Lc   Rc   Ly")
for i, r in enumerate(rows):
    if r[0] < t0 or (i % step):
        continue
    if r[0] > t0 + 1.9:
        break
    print("%6.3f %-12s %6.2f %5.2f %5.2f %5.2f %5.2f | %6.2f %4.2f | %6.2f %4.2f | %4.1f %4.1f | %6.1f" % (
        r[0], r[1][5:], r[2] - b, r[3], r[4], r[5], r[6], r[7] - b, r[8], r[9] - b, r[10], r[11], r[12], r[13]))
