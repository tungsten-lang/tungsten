"""M1 foot placement: per start (approach only, j_run 1, chain C, check mark 150 m) the gaps to the line of the last touchdowns before it and the steps. (L3)"""
import os, sys, importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import arena
from bridge import Sim

board = 150.0
os.environ.update({"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation", "ROBOLAB_LJ_APPROACH": str(board)})
params0 = arena.read_params("/Users/erik/tungsten/bits/tungsten-robolab/params/run_gearx_v4_beyond_c.txt")
params0["j_run"] = 1.0
params0["j_debug"] = 1.0
out = []
for seed in range(601, 617):
    task = importlib.import_module("tasks.long_jump_v4_beyond").TASK()
    task.seed = seed
    sim = Sim(task, params=dict(params0), controller="/Users/erik/tungsten/bits/tungsten-robolab/bin/challengers/long_jump_run_x-l3b")
    cmds = []
    orig = task.on_command
    def oc(m, d, cmd, cmds=cmds, orig=orig):
        if cmd.startswith("dbg:td"):
            cmds.append(cmd)
        return orig(m, d, cmd)
    task.on_command = oc
    m = sim.run(task.seconds)
    tds = []
    for c in cmds:
        t = c.split(":")
        kv = dict(x.split("=") for x in t[3:] if "=" in x)
        tds.append((float(kv["t"]), t[2], board - float(kv["gap"]), float(kv["gap"]), float(kv["step"])))
    # drop contact-chatter touchdowns (step < 1 m)
    clean = [r for r in tds if r[4] > 1.0 or r is tds[0]]
    before = [r for r in clean if r[3] > 0.0]
    if m.get("fell_approach") or len(before) < 3:
        print("seed %d: fell in the run" % seed)
        continue
    last, prev = before[-1], before[-2]
    out.append((seed, last[3], prev[3], last[4], last[1]))
    print("seed %d: last touchdown before the line %s gap %.3f m (previous %.3f), step %.3f m" % (seed, last[1], last[3], prev[3], last[4]))
g = np.array([o[1] for o in out])
print("SUMMARY %d starts reached the line: gap of the last touchdown before the line: mean %.3f sd %.3f min %.3f max %.3f; mean step %.3f (a uniform phase over one step would give sd %.3f)" % (
    len(g), g.mean(), g.std(), g.min(), g.max(), np.mean([o[3] for o in out]), np.mean([o[3] for o in out]) / np.sqrt(12)))
