"""Exactness of the new skill (agent L4): the stock frozen controller bin/challengers/run_geary-s5-final (RunGearYSkill) and the jump controller
(LongJumpRunYSkill) with j_run 1 (approach only, neutral jump settings) on the same task / seed / F1 params must give the same tick log (time, labels and all
32 activations) for the first N seconds. LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP.
usage: exact_y.py <params> <jump_controller> <task> <seed|None> <seconds>"""
import os
import sys
import importlib

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)


def run(ctl, task_name, params_path, seed, seconds, extra):
    import arena
    from bridge import Sim
    os.environ.update({"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"})
    task = importlib.import_module("tasks." + task_name).TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params.update(extra)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    sim.run(seconds)
    return sim.log


def main():
    params, jump_ctl, task_name, seed, seconds = sys.argv[1:6]
    seed = None if seed == "None" else int(seed)
    seconds = float(seconds)
    a = run(os.path.join(ROOT, "bin/challengers/run_geary-s5-final"), task_name, params, seed, seconds, {})
    b = run(jump_ctl, task_name, params, seed, seconds, {"j_run": 1.0})
    n = min(len(a), len(b))
    bad = None
    for i in range(n):
        ta, la, acta = a[i][0], a[i][1], a[i][2]
        tb, lb, actb = b[i][0], b[i][1], b[i][2]
        if ta != tb or la != lb or (acta != actb).any():
            bad = i
            break
    if bad is None and len(a) == len(b):
        print("IDENTICAL seed %s task %s: %d ticks, labels and activations equal (t %.3f .. %.3f)" % (seed, task_name, n, a[0][0], a[n - 1][0]))
    else:
        i = bad if bad is not None else n
        print("DIFFER seed %s task %s at tick %d (ticks %d / %d) t %s labels %s / %s" % (seed, task_name, i, len(a), len(b),
              a[i][0] if i < len(a) else None, a[i][1] if i < len(a) else None, b[i][1] if i < len(b) else None))
        if bad is not None:
            import numpy as np
            print("max |dact|", float(np.abs(a[i][2] - b[i][2]).max()))


if __name__ == "__main__":
    main()
